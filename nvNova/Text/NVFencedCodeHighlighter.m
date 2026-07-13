//
//  NVFencedCodeHighlighter.m
//  Notation
//
//  Created for nvNova (NVN-18) on 7/10/26.

/*Copyright (c) 2026, nvNova contributors. All rights reserved.
    This file is part of Notational Velocity.

    Notational Velocity is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Notational Velocity is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Notational Velocity.  If not, see <http://www.gnu.org/licenses/>. */


#import "NVFencedCodeHighlighter.h"
#import "NVCodeTokenizer.h"
#import "GlobalPrefs.h"
#import "AttributedPlainText.h"

NSString *NVCodeBlockAttributeName = @"NVCodeBlock";

typedef enum {
	NVMarkerStateUnknown = 0,	//visibility attributes not yet applied for this block object
	NVMarkerStateVisible,
	NVMarkerStateHidden,
} NVMarkerState;

@interface NVFencedBlock : NSObject {
@public
	NSRange openFenceLineRange;		//opening fence line incl. leading spaces + info string, excl. newline
	NSRange codeRange;				//between the fence lines; may be zero-length
	NSRange closeFenceLineRange;	//location == NSNotFound while unclosed
	NSUInteger languageID;
	NVMarkerState markerState;
}
- (NSRange)totalRange;
@end

@implementation NVFencedBlock

- (NSRange)totalRange {
	NSUInteger end = (closeFenceLineRange.location != NSNotFound) ? NSMaxRange(closeFenceLineRange) : NSMaxRange(codeRange);
	return NSMakeRange(openFenceLineRange.location, end - openFenceLineRange.location);
}

@end

@implementation NVFencedCodeHighlighter

//up to three leading spaces before the backtick run (CommonMark), nothing else
static BOOL _fenceIsLineAnchored(NSString *string, NSUInteger lineStart, NSUInteger fenceLocation) {
	NSUInteger i;
	if (fenceLocation - lineStart > 3) return NO;
	for (i = lineStart; i < fenceLocation; i++) {
		if ([string characterAtIndex:i] != ' ') return NO;
	}
	return YES;
}

static BOOL _rangesTouch(NSRange a, NSRange b) {
	if (NSIntersectionRange(a, b).length > 0) return YES;
	if (!a.length && NSLocationInRange(a.location, b)) return YES;
	if (!b.length && NSLocationInRange(b.location, a)) return YES;
	return NO;
}

static NSFont *_codeFont(void) {
	return [NSFont userFixedPitchFontOfSize:[[[GlobalPrefs defaultPrefs] noteBodyFont] pointSize]];
}

//token colors as prebuilt temporary-attribute dictionaries, one palette per variant and
//background polarity (the editor background is user-configurable, so NSAppearance is no guide here)
static NSDictionary *_tokenAttributes(NVCodeTokenClass tokenClass, BOOL darkBackground, BOOL alternatePalette) {
	static NSDictionary *attributes[2][2][NVCodeTokenClassCount];
	static const CGFloat components[2][2][NVCodeTokenClassCount][3] = {
		{	//default variant
			{	//light background; Xcode-default-adjacent
				{ 0.0,   0.456, 0.0   },	//comment
				{ 0.77,  0.102, 0.086 },	//string
				{ 0.11,  0.0,   0.81  },	//number
				{ 0.608, 0.137, 0.576 },	//keyword
			},
			{	//dark background
				{ 0.424, 0.475, 0.525 },	//comment
				{ 0.988, 0.416, 0.365 },	//string
				{ 0.816, 0.749, 0.412 },	//number
				{ 0.988, 0.373, 0.639 },	//keyword
			},
		},
		{	//alternate variant; softer, low-saturation
			{	//light background
				{ 0.42,  0.48,  0.55  },	//comment (slate)
				{ 0.13,  0.55,  0.45  },	//string (teal)
				{ 0.72,  0.44,  0.05  },	//number (amber)
				{ 0.42,  0.36,  0.72  },	//keyword (indigo)
			},
			{	//dark background
				{ 0.55,  0.60,  0.54  },	//comment (sage)
				{ 0.60,  0.85,  0.75  },	//string (mint)
				{ 0.95,  0.76,  0.53  },	//number (peach)
				{ 0.72,  0.70,  0.95  },	//keyword (lavender)
			},
		},
	};
	NSUInteger variant = alternatePalette ? 1 : 0;
	NSUInteger palette = darkBackground ? 1 : 0;
	if ((NSUInteger)tokenClass >= NVCodeTokenClassCount) return nil;
	if (!attributes[variant][palette][tokenClass]) {
		const CGFloat *c = components[variant][palette][tokenClass];
		attributes[variant][palette][tokenClass] = [[NSDictionary alloc] initWithObjectsAndKeys:
			[NSColor colorWithCalibratedRed:c[0] green:c[1] blue:c[2] alpha:1.0], NSForegroundColorAttributeName, nil];
	}
	return attributes[variant][palette][tokenClass];
}

//default text color inside dark slabs: non-token code must stay readable on #1a1a1a
static NSDictionary *_lightDefaultTextAttributes(void) {
	static NSDictionary *attributes = nil;
	if (!attributes) {
		attributes = [[NSDictionary alloc] initWithObjectsAndKeys:
			[NSColor colorWithCalibratedWhite:0.847 alpha:1.0], NSForegroundColorAttributeName, nil];
	}
	return attributes;
}

//fence-marker lines render invisible (not collapsed) while the caret is outside the block
static NSDictionary *_invisibleMarkerAttributes(void) {
	static NSDictionary *attributes = nil;
	if (!attributes) {
		attributes = [[NSDictionary alloc] initWithObjectsAndKeys:
			[NSColor clearColor], NSForegroundColorAttributeName, nil];
	}
	return attributes;
}

//boundary-inclusive at both ends for carets, unlike _rangesTouch: the caret sitting
//right after the final backtick of a block still counts as inside it
static BOOL _selectionTouchesRange(NSRange sel, NSRange range) {
	if (!sel.length)
		return sel.location >= range.location && sel.location <= NSMaxRange(range);
	return NSIntersectionRange(sel, range).length > 0;
}

- (NSArray*)scanBlocksInString:(NSString*)string {
	NSMutableArray *scanned = [NSMutableArray array];
	NSUInteger docLength = [string length];
	NVFencedBlock *openBlock = nil;
	NSRange searchRange = NSMakeRange(0, docLength);

	while (searchRange.length) {
		NSRange hit = [string rangeOfString:@"```" options:NSLiteralSearch range:searchRange];
		if (hit.location == NSNotFound) break;

		NSUInteger lineStart = 0, lineEnd = 0, contentsEnd = 0;
		[string getLineStart:&lineStart end:&lineEnd contentsEnd:&contentsEnd forRange:NSMakeRange(hit.location, 0)];

		if (_fenceIsLineAnchored(string, lineStart, hit.location)) {
			NSUInteger runEnd = hit.location;
			while (runEnd < contentsEnd && [string characterAtIndex:runEnd] == '`') runEnd++;
			NSRange remainder = NSMakeRange(runEnd, contentsEnd - runEnd);

			if (!openBlock) {
				//opening fence: the info string may not itself contain backticks (CommonMark),
				//which also rejects single-line spans like ```code```
				if ([string rangeOfString:@"`" options:NSLiteralSearch range:remainder].location == NSNotFound) {
					openBlock = [[NVFencedBlock alloc] init];
					openBlock->openFenceLineRange = NSMakeRange(lineStart, contentsEnd - lineStart);
					openBlock->codeRange = NSMakeRange(lineEnd, 0);
					openBlock->closeFenceLineRange = NSMakeRange(NSNotFound, 0);
					NSString *infoString = [[string substringWithRange:remainder] stringByTrimmingCharactersInSet:
											[NSCharacterSet whitespaceCharacterSet]];
					openBlock->languageID = [infoString length] ? [NVCodeTokenizer languageIDForInfoString:infoString] : NVCodeLanguageNone;
				}
			} else {
				//closing fence: backticks alone on the line (trailing whitespace tolerated);
				//a backtick line carrying an info string is code content, per CommonMark
				BOOL closes = YES;
				NSUInteger i;
				for (i = remainder.location; i < NSMaxRange(remainder); i++) {
					unichar ch = [string characterAtIndex:i];
					if (ch != ' ' && ch != '\t') {
						closes = NO;
						break;
					}
				}
				if (closes) {
					openBlock->codeRange.length = lineStart > openBlock->codeRange.location ? lineStart - openBlock->codeRange.location : 0;
					openBlock->closeFenceLineRange = NSMakeRange(lineStart, contentsEnd - lineStart);
					[scanned addObject:openBlock];
					[openBlock release];
					openBlock = nil;
				}
			}
		}
		if (lineEnd >= docLength) break;
		searchRange = NSMakeRange(lineEnd, docLength - lineEnd);
	}

	if (openBlock) {
		//unclosed fence extends to the end of the note (CommonMark)
		openBlock->codeRange.length = docLength > openBlock->codeRange.location ? docLength - openBlock->codeRange.location : 0;
		[scanned addObject:openBlock];
		[openBlock release];
	}
	return scanned;
}

- (void)applyBaseStyleForBlock:(NVFencedBlock*)block inTextStorage:(NSTextStorage*)textStorage {
	NSRange totalRange = [block totalRange];
	if (!totalRange.length || NSMaxRange(totalRange) > [textStorage length]) return;
	NSFont *codeFont = _codeFont();
	if (!codeFont) return;	//failure mode is no highlighting, never mangled text
	[textStorage addAttribute:NVCodeBlockAttributeName value:[NSNull null] range:totalRange];
	[textStorage addAttribute:NSFontAttributeName value:codeFont range:totalRange];
}

static void _stripCodeStyle(NSTextStorage *textStorage, NSLayoutManager *layoutManager, NSRange range) {
	if (!range.length) return;
	[textStorage removeAttribute:NVCodeBlockAttributeName range:range];
	[textStorage addAttribute:NSFontAttributeName value:[[GlobalPrefs defaultPrefs] noteBodyFont] range:range];
	[layoutManager removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:range];
}

//remove code styling from marker runs inside area wherever they fall outside every block in newBlocks
- (void)cleanStaleMarkersInRange:(NSRange)area outsideBlocks:(NSArray*)newBlocks
					 textStorage:(NSTextStorage*)textStorage layoutManager:(NSLayoutManager*)layoutManager {
	NSUInteger docLength = [textStorage length];
	if (area.location >= docLength) return;
	if (NSMaxRange(area) > docLength) area.length = docLength - area.location;
	if (!area.length) return;
	if (![textStorage attribute:NVCodeBlockAttributeName existsInRange:area]) return;

	NSUInteger index = area.location;
	while (index < NSMaxRange(area)) {
		NSRange runRange;
		id marker = [textStorage attribute:NVCodeBlockAttributeName atIndex:index longestEffectiveRange:&runRange inRange:area];
		if (marker) {
			//blocks are disjoint and sorted; subtract each from the run and strip whatever is left
			NSUInteger pos = runRange.location;
			NSUInteger blockIndex;
			for (blockIndex = 0; blockIndex < [newBlocks count] && pos < NSMaxRange(runRange); blockIndex++) {
				NSRange blockRange = [(NVFencedBlock*)[newBlocks objectAtIndex:blockIndex] totalRange];
				if (NSMaxRange(blockRange) <= pos) continue;
				if (blockRange.location >= NSMaxRange(runRange)) break;
				if (blockRange.location > pos)
					_stripCodeStyle(textStorage, layoutManager, NSMakeRange(pos, blockRange.location - pos));
				pos = MAX(pos, NSMaxRange(blockRange));
			}
			if (pos < NSMaxRange(runRange))
				_stripCodeStyle(textStorage, layoutManager, NSMakeRange(pos, NSMaxRange(runRange) - pos));
		}
		index = NSMaxRange(runRange);
	}
}

- (void)restyleBlock:(NVFencedBlock*)block inTextStorage:(NSTextStorage*)textStorage
	   layoutManager:(NSLayoutManager*)layoutManager darkBackground:(BOOL)darkBackground {
	NSRange totalRange = [block totalRange];
	if (!totalRange.length || NSMaxRange(totalRange) > [textStorage length]) return;
	[self applyBaseStyleForBlock:block inTextStorage:textStorage];
	[layoutManager removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:totalRange];

	//dark slabs force the dark palette and need light default text over the whole block
	BOOL darkBlocks = [[GlobalPrefs defaultPrefs] useDarkCodeBlocks];
	if (darkBlocks)
		[layoutManager addTemporaryAttributes:_lightDefaultTextAttributes() forCharacterRange:totalRange];
	block->markerState = NVMarkerStateVisible;	//the temp-color wipe above re-showed the fences
	if (block->languageID == NVCodeLanguageNone || !block->codeRange.length) return;

	BOOL usesDarkPalette = darkBackground || darkBlocks;
	BOOL alternatePalette = [[GlobalPrefs defaultPrefs] useAlternateCodePalette];
	[NVCodeTokenizer enumerateTokensInString:[textStorage string] range:block->codeRange languageID:block->languageID
								  usingBlock:^(NSRange tokenRange, NVCodeTokenClass tokenClass) {
		NSDictionary *tokenAttributes = _tokenAttributes(tokenClass, usesDarkPalette, alternatePalette);
		if (tokenAttributes)
			[layoutManager addTemporaryAttributes:tokenAttributes forCharacterRange:tokenRange];
	}];
}

- (void)highlightChangedRange:(NSRange)changedRange inTextStorage:(NSTextStorage*)textStorage
				layoutManager:(NSLayoutManager*)layoutManager darkBackground:(BOOL)darkBackground {
	NSString *string = [textStorage string];
	NSUInteger docLength = [string length];

	if (changedRange.location > docLength) changedRange = NSMakeRange(docLength, 0);
	if (NSMaxRange(changedRange) > docLength) changedRange.length = docLength - changedRange.location;

	//quick reject: no known blocks, and the edited lines introduce no fence
	if (![blocks count] && [string rangeOfString:@"```" options:NSLiteralSearch range:changedRange].location == NSNotFound) {
		lastScannedLength = docLength;
		return;
	}

	NSArray *newBlocks = [self scanBlocksInString:string];
	NSInteger delta = (NSInteger)docLength - (NSInteger)lastScannedLength;
	NSInteger oldChangedLength = (NSInteger)changedRange.length - delta;
	NSRange oldChangedRange = NSMakeRange(changedRange.location, oldChangedLength > 0 ? (NSUInteger)oldChangedLength : 0);

	//old block ranges normalized into post-edit coordinates; blocks that overlapped the edit can't be trusted
	NSUInteger oldCount = [blocks count];
	NSRange *normalizedRanges = oldCount ? (NSRange*)malloc(sizeof(NSRange) * oldCount) : NULL;
	NSUInteger *normalizedLangs = oldCount ? (NSUInteger*)malloc(sizeof(NSUInteger) * oldCount) : NULL;
	BOOL *overlappedEdit = oldCount ? (BOOL*)malloc(sizeof(BOOL) * oldCount) : NULL;
	NSUInteger i, j;
	for (i = 0; i < oldCount; i++) {
		NVFencedBlock *oldBlock = [blocks objectAtIndex:i];
		NSRange range = [oldBlock totalRange];
		BOOL overlapped = NO;
		if (NSMaxRange(range) <= oldChangedRange.location) {
			//entirely before the edit; coordinates are stable
		} else if (range.location >= NSMaxRange(oldChangedRange)) {
			range.location = (NSUInteger)((NSInteger)range.location + delta);
		} else {
			overlapped = YES;
		}
		if (range.location > docLength) range = NSMakeRange(docLength, 0);
		if (NSMaxRange(range) > docLength) range.length = docLength - range.location;
		normalizedRanges[i] = range;
		normalizedLangs[i] = oldBlock->languageID;
		overlappedEdit[i] = overlapped;
	}

	//strip stale styling wherever old blocks (or typing-attribute bleed within the edit) left markers outside the new map
	for (i = 0; i < oldCount; i++)
		[self cleanStaleMarkersInRange:normalizedRanges[i] outsideBlocks:newBlocks textStorage:textStorage layoutManager:layoutManager];
	[self cleanStaleMarkersInRange:changedRange outsideBlocks:newBlocks textStorage:textStorage layoutManager:layoutManager];

	//restyle every new block unless it verifiably matches an undisturbed old block; when in doubt, restyle
	for (j = 0; j < [newBlocks count]; j++) {
		NVFencedBlock *newBlock = [newBlocks objectAtIndex:j];
		NSRange newRange = [newBlock totalRange];
		BOOL undisturbed = NO;
		if (!_rangesTouch(newRange, changedRange)) {
			for (i = 0; i < oldCount; i++) {
				if (!overlappedEdit[i] && normalizedLangs[i] == newBlock->languageID && NSEqualRanges(normalizedRanges[i], newRange)) {
					undisturbed = YES;
					//an undisturbed block was not restyled: its temporary attributes (including
					//hidden fence markers) survived and shifted with the edit, so carry the state
					newBlock->markerState = ((NVFencedBlock*)[blocks objectAtIndex:i])->markerState;
					break;
				}
			}
		}
		if (!undisturbed)
			[self restyleBlock:newBlock inTextStorage:textStorage layoutManager:layoutManager darkBackground:darkBackground];
	}

	if (normalizedRanges) free(normalizedRanges);
	if (normalizedLangs) free(normalizedLangs);
	if (overlappedEdit) free(overlappedEdit);

	[newBlocks retain];
	[blocks release];
	blocks = newBlocks;
	lastScannedLength = docLength;
}

- (void)highlightAllInTextStorage:(NSTextStorage*)textStorage layoutManager:(NSLayoutManager*)layoutManager
				   darkBackground:(BOOL)darkBackground {
	NSString *string = [textStorage string];
	NSUInteger docLength = [string length];
	NSArray *newBlocks = [self scanBlocksInString:string];

	//sweep the whole document: stored notes (single-DB/RTF) can round-trip markers from an earlier session
	[self cleanStaleMarkersInRange:NSMakeRange(0, docLength) outsideBlocks:newBlocks textStorage:textStorage layoutManager:layoutManager];

	NSUInteger i;
	for (i = 0; i < [newBlocks count]; i++)
		[self restyleBlock:[newBlocks objectAtIndex:i] inTextStorage:textStorage layoutManager:layoutManager darkBackground:darkBackground];

	[newBlocks retain];
	[blocks release];
	blocks = newBlocks;
	lastScannedLength = docLength;
}

- (NSArray*)cachedBlockCharacterRanges {
	NSUInteger count = [blocks count];
	if (!count) return [NSArray array];
	NSMutableArray *ranges = [NSMutableArray arrayWithCapacity:count];
	NSUInteger i;
	for (i = 0; i < count; i++)
		[ranges addObject:[NSValue valueWithRange:[(NVFencedBlock*)[blocks objectAtIndex:i] totalRange]]];
	return ranges;
}

- (NVFencedBlock*)_blockAtIndex:(NSUInteger)index {
	return index < [blocks count] ? (NVFencedBlock*)[blocks objectAtIndex:index] : nil;
}

- (NSUInteger)blockCount {
	return [blocks count];
}

- (NSRange)totalRangeOfBlockAtIndex:(NSUInteger)index {
	NVFencedBlock *block = [self _blockAtIndex:index];
	return block ? [block totalRange] : NSMakeRange(NSNotFound, 0);
}

- (NSRange)codeRangeOfBlockAtIndex:(NSUInteger)index {
	NVFencedBlock *block = [self _blockAtIndex:index];
	return block ? block->codeRange : NSMakeRange(NSNotFound, 0);
}

- (NSRange)openFenceLineRangeOfBlockAtIndex:(NSUInteger)index {
	NVFencedBlock *block = [self _blockAtIndex:index];
	return block ? block->openFenceLineRange : NSMakeRange(NSNotFound, 0);
}

- (NSRange)closeFenceLineRangeOfBlockAtIndex:(NSUInteger)index {
	NVFencedBlock *block = [self _blockAtIndex:index];
	return block ? block->closeFenceLineRange : NSMakeRange(NSNotFound, 0);
}

- (void)updateFenceMarkerVisibilityForSelectedRanges:(NSArray*)selectedRanges
									   layoutManager:(NSLayoutManager*)layoutManager {
	NSUInteger count = [blocks count];
	if (!count) return;
	NSUInteger docLength = [[layoutManager textStorage] length];
	BOOL darkBlocks = [[GlobalPrefs defaultPrefs] useDarkCodeBlocks];

	NSUInteger i;
	for (i = 0; i < count; i++) {
		NVFencedBlock *block = [blocks objectAtIndex:i];

		//unclosed blocks keep their markers: hiding the lone fence mid-authoring is disorienting
		NVMarkerState desired = NVMarkerStateVisible;
		if (block->closeFenceLineRange.location != NSNotFound) {
			NSRange totalRange = [block totalRange];
			BOOL inside = NO;
			NSValue *selValue;
			for (selValue in selectedRanges) {
				if (_selectionTouchesRange([selValue rangeValue], totalRange)) {
					inside = YES;
					break;
				}
			}
			desired = inside ? NVMarkerStateVisible : NVMarkerStateHidden;
		}
		if (desired == block->markerState) continue;

		NSRange lineRanges[2] = { block->openFenceLineRange, block->closeFenceLineRange };
		NSUInteger j;
		for (j = 0; j < 2; j++) {
			NSRange lineRange = lineRanges[j];
			if (lineRange.location == NSNotFound || !lineRange.length || NSMaxRange(lineRange) > docLength) continue;
			if (desired == NVMarkerStateHidden) {
				[layoutManager addTemporaryAttributes:_invisibleMarkerAttributes() forCharacterRange:lineRange];
			} else {
				[layoutManager removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:lineRange];
				//re-shown markers inside a dark slab need the light blanket back
				if (darkBlocks)
					[layoutManager addTemporaryAttributes:_lightDefaultTextAttributes() forCharacterRange:lineRange];
			}
		}
		block->markerState = desired;
	}
}

- (void)invalidateCache {
	[blocks release];
	blocks = nil;
	lastScannedLength = 0;
}

- (void)dealloc {
	[blocks release];
	[super dealloc];
}

@end
