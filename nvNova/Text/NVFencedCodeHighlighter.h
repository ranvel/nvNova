//
//  NVFencedCodeHighlighter.h
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


#import <Cocoa/Cocoa.h>

//tombstone marking ranges styled as fenced code, so stale styling can be found and undone
//(same pattern as NVHiddenDoneTagAttributeName)
extern NSString *NVCodeBlockAttributeName;

@interface NVFencedCodeHighlighter : NSObject {
	NSArray *blocks;
	NSUInteger lastScannedLength;
}

- (void)highlightChangedRange:(NSRange)changedRange inTextStorage:(NSTextStorage*)textStorage
				layoutManager:(NSLayoutManager*)layoutManager darkBackground:(BOOL)darkBackground;
- (void)highlightAllInTextStorage:(NSTextStorage*)textStorage layoutManager:(NSLayoutManager*)layoutManager
				   darkBackground:(BOOL)darkBackground;
- (void)invalidateCache;
//character ranges (NSValue) of the cached fence blocks, for background drawing
- (NSArray*)cachedBlockCharacterRanges;

//cached-block sub-ranges, indexed in cachedBlockCharacterRanges order;
//out-of-bounds indexes return {NSNotFound, 0}
- (NSUInteger)blockCount;
- (NSRange)totalRangeOfBlockAtIndex:(NSUInteger)index;
- (NSRange)codeRangeOfBlockAtIndex:(NSUInteger)index;
- (NSRange)openFenceLineRangeOfBlockAtIndex:(NSUInteger)index;
- (NSRange)closeFenceLineRangeOfBlockAtIndex:(NSUInteger)index;	//also {NSNotFound, 0} while unclosed

//hides fence-marker lines of blocks the selection doesn't touch (clear-color temporary
//attribute); selectedRanges holds NSValue ranges. Cheap when nothing flips state.
- (void)updateFenceMarkerVisibilityForSelectedRanges:(NSArray*)selectedRanges
									   layoutManager:(NSLayoutManager*)layoutManager;

@end
