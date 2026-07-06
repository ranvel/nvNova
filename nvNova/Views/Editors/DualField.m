/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
  Redistribution and use in source and binary forms, with or without modification, are permitted 
  provided that the following conditions are met:
   - Redistributions of source code must retain the above copyright notice, this list of conditions 
     and the following disclaimer.
   - Redistributions in binary form must reproduce the above copyright notice, this list of 
	 conditions and the following disclaimer in the documentation and/or other materials provided with
     the distribution.
   - Neither the name of Notational Velocity nor the names of its contributors may be used to endorse 
     or promote products derived from this software without specific prior written permission. */


#import "DualField.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "NotationPrefs.h"
#import "LinearDividerShader.h"
#import "AppController.h"
#import "BookmarksController.h"

#define ICON_DIM 16.0
#define ICON_PAD 6.0
#define LEFT_TEXT_INSET (ICON_PAD + ICON_DIM + 3.0)
#define RIGHT_TEXT_INSET (ICON_DIM + 6.0)

//the doc/search/snapback icons are dark-on-transparent bitmaps; tint them so
//they resolve against the current appearance when drawn over a system bezel
static NSImage *TintedImage(NSImage *img, NSColor *tint) {
	NSImage *tinted = [[img copy] autorelease];
	[tinted lockFocus];
	[tint set];
	NSRectFillUsingOperation((NSRect){NSZeroPoint, [tinted size]}, NSCompositingOperationSourceIn);
	[tinted unlockFocus];
	return tinted;
}

@implementation DualFieldCell

- (id) init {
	self = [super init];
	if (self != nil) {
		[self setStringValue:@""];
		[self setEditable:YES];
		[self setSelectable:YES];
		[self setBezeled:YES];
		[self setBezelStyle:NSTextFieldRoundedBezel];
		[self setDrawsBackground:YES];
		[self setWraps:YES];
		[self setPlaceholderString:NSLocalizedString(@"Search or Create", @"placeholder text in search/create field")];

		clearButtonState = snapbackButtonState = BUTTON_HIDDEN;
		
	}
	return self;
}

- (NSRect)drawingRectForBounds:(NSRect)someBounds {
	//reserve room for the doc/snapback icon on the left and the clear button
	//on the right, on top of the rounded bezel's own padding from super
	NSRect rect = [super drawingRectForBounds:someBounds];
	CGFloat minX = NSMinX(someBounds) + LEFT_TEXT_INSET;
	CGFloat maxX = NSMaxX(someBounds) - RIGHT_TEXT_INSET;
	if (NSMinX(rect) < minX) {
		rect.size.width -= minX - NSMinX(rect);
		rect.origin.x = minX;
	}
	if (NSMaxX(rect) > maxX) {
		rect.size.width = maxX - NSMinX(rect);
	}
	return rect;
}

- (NSText *)setUpFieldEditorAttributes:(NSText *)textObj {
	NSTextView *textView = (NSTextView*)[super setUpFieldEditorAttributes:textObj];
	[textView setDrawsBackground:NO];

	return textView;
}

- (void)endEditing:(NSText *)textObj {
	//fix up any changes we might have made to the field editor in setUpFieldEditorAttributes:
//	[(NSTextView*)textObj setTextContainerInset:NSMakeSize(0, 0)];
	[super endEditing:textObj];
}

- (NSRect)clearButtonRectForBounds:(NSRect)rect {
	NSRect part, clear;

	NSDivideRect(rect, &clear, &part, RIGHT_TEXT_INSET, NSMaxXEdge);
	return clear;
}

- (NSRect)snapbackButtonRectForBounds:(NSRect)rect {
	return NSMakeRect(NSMinX(rect) + ICON_PAD, floor(NSMidY(rect) - ICON_DIM / 2.0), ICON_DIM, ICON_DIM);
}

- (NSRect)textAreaForBounds:(NSRect)rect {
	return [self drawingRectForBounds:rect];
}

- (BOOL)clearButtonIsVisible {
	return BUTTON_HIDDEN != clearButtonState;
}

- (void)setShowsClearButton:(BOOL)shouldShow {
	if ((BUTTON_HIDDEN != clearButtonState) != shouldShow) {
		NSView *controlView = [self controlView];
		clearButtonState = shouldShow ? BUTTON_NORMAL : BUTTON_HIDDEN;
		[controlView setNeedsDisplayInRect:[self clearButtonRectForBounds:[controlView bounds]]];
		[[controlView window] invalidateCursorRectsForView:controlView];
	}
}

- (BOOL)snapbackButtonIsVisible {
	return BUTTON_HIDDEN != snapbackButtonState;
}

- (void)setShowsSnapbackButton:(BOOL)shouldShow {
	NSView *controlView = [self controlView];
	//used for being notified from a mouseover-ing
	if ((snapbackButtonState != BUTTON_HIDDEN) != shouldShow) {
		snapbackButtonState = shouldShow ? BUTTON_NORMAL : BUTTON_HIDDEN;
		[controlView setNeedsDisplayInRect:[self snapbackButtonRectForBounds:[controlView bounds]]];
		[[controlView window] invalidateCursorRectsForView:controlView];
	}	
}

- (BOOL)handleMouseDown:(NSEvent *)theEvent {
	DualField *controlView = (DualField *)[self controlView];
	
	if (![self clearButtonIsVisible] && ![self snapbackButtonIsVisible]) {
		return NO;
	}
	
	do {
		NSPoint mouseLoc = [controlView convertPoint:[theEvent locationInWindow] fromView:nil];
		
		if ([self clearButtonIsVisible])
			clearButtonState = [controlView mouse:mouseLoc inRect:[self clearButtonRectForBounds:[controlView bounds]]] ? BUTTON_PRESSED : BUTTON_NORMAL;
		
		if ([self snapbackButtonIsVisible])
			snapbackButtonState = [controlView mouse:mouseLoc inRect:[self snapbackButtonRectForBounds:[controlView bounds]]]  ? BUTTON_PRESSED : BUTTON_NORMAL;
		
		[controlView setNeedsDisplay:YES];
		
		NSEventType type = [theEvent type];
		if (type == NSLeftMouseUp || type == NSRightMouseUp) {
			if (BUTTON_PRESSED == snapbackButtonState) {
				[controlView snapback:nil];
			} else if (BUTTON_PRESSED == clearButtonState) {
				[NSApp tryToPerform:@selector(cancelOperation:) with:nil];
			}
			break;
		}
		theEvent = [[controlView window] nextEventMatchingMask: NSLeftMouseUpMask | NSLeftMouseDraggedMask | NSRightMouseUpMask | NSRightMouseDraggedMask];
	} while (1);
	
	return YES;
}
		
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {

	[super drawWithFrame:cellFrame inView:controlView];

	if (BUTTON_HIDDEN != clearButtonState) {
		NSImage *clearImg = [NSImage imageNamed:(clearButtonState == BUTTON_NORMAL ? @"Clear" : @"ClearPressed") ];
		[TintedImage(clearImg, [NSColor secondaryLabelColor]) drawCenteredInRect:[self clearButtonRectForBounds:cellFrame]];
	}
	NSRect snRect = [self snapbackButtonRectForBounds:cellFrame];
	if (BUTTON_HIDDEN != snapbackButtonState) {
		NSImage *snapImg = [NSImage imageNamed:
							[(DualField *)controlView hasFollowedLinks] ? (snapbackButtonState == BUTTON_NORMAL ? @"LinkBack" : @"LinkBackPressed") :
							(snapbackButtonState == BUTTON_NORMAL ? @"SnapBack" : @"SnapBackPressed") ];
		[snapImg drawCenteredInRect:snRect];
	} else {
		NSImage *docIcon = [NSImage imageNamed:[(DualField *)controlView showsDocumentIcon] ? @"Pencil" : @"Search"];
		[TintedImage(docIcon, [NSColor secondaryLabelColor]) drawCenteredInRect:snRect];
	}
}


+ (BOOL)prefersTrackingUntilMouseUp {
	// NSCell returns NO for this by default. If you want to have trackMouse:inRect:ofView:untilMouseUp: always track until the mouse is up, then you MUST return YES. Otherwise, strange things will happen.
	return YES;
}


@end

@implementation DualField

+ (Class)cellClass {
	return [DualFieldCell class];
}

- (void)awakeFromNib {
	
	NSCell *dualFieldCell = [[[DualFieldCell alloc] init] autorelease];
	[dualFieldCell setAction:[[self cell] action]];
	[dualFieldCell setTarget:[[self cell] target]];
	[self setCell:dualFieldCell];
	DualFieldCell *myCell = [self cell];
	[self setDrawsBackground:YES];
	[self setBezeled:YES];
	//explicit: the localized XIBs all say "none", which would suppress the system ring
	[self setFocusRingType:NSFocusRingTypeDefault];

	[myCell setAllowsUndo:NO];
	[myCell setLineBreakMode:NSLineBreakByCharWrapping];
	
	//remember this now to make sure we always use the same one, in case +IBeamCursor just happens to return a different object later (hint hint)
	IBeamCursor = [[NSCursor IBeamCursor] retain];
	
	followedLinks = [[NSMutableArray alloc] init];
}

- (void)setTrackingRect {
	if (!docIconRectTag)
		docIconRectTag = [self addTrackingRect:[[self cell] snapbackButtonRectForBounds:[self bounds]] 
										 owner:self userData:NULL assumeInside:NO];	
}

- (void)dealloc {
	[snapbackString release];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[followedLinks release];
	
	[super dealloc];
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)userData {
	unichar ch = 0x2318;
	
	if (tag == docIconTag) {
		//should be conditional on whether snapback exists, and include the snapback string
		if ([[self cell] snapbackButtonIsVisible]) {
			return [NSString stringWithFormat:NSLocalizedString(@"Go back to search; press %@-D to deselect", @"tooltip string for search/title field"), 
					[NSString stringWithCharacters:&ch length:1]];
		} else {
			return NSLocalizedString(@"Now searching for this text", @"tooltip string for search/title field");
		}
	} else if (tag == clearButtonTag) {
		if ([[self cell] clearButtonIsVisible]) {
			return NSLocalizedString(@"Clear the search; press ESC", @"tooltip string for search/title field");
		} else {
			return NSLocalizedString(@"Type any text to search; press Return to create a note", @"tooltip string for search/title field");
		}
	} else if (tag == textAreaTag) {
		if ([self showsDocumentIcon]) {
			return [NSString stringWithFormat:NSLocalizedString(@"Now editing this note; rename it with %@-R", @"tooltip string for search/title field"),
					[NSString stringWithCharacters:&ch length:1]];
		} else {
			return NSLocalizedString(@"Type any text to search; press Return to create a note", @"tooltip string for search/title field");
		}
	}
	return @"";
}

- (void)mouseEntered:(NSEvent *)theEvent {
	if ([theEvent trackingNumber] == docIconRectTag) {
		[[self cell] setShowsSnapbackButton:[self showsDocumentIcon]];
	} else {
		NSLog(@"got mouse entered on a different tracking number: %ld", [theEvent trackingNumber]);
	}
}
- (void)mouseExited:(NSEvent *)theEvent {
	if ([theEvent trackingNumber] == docIconRectTag) {
		[[self cell] setShowsSnapbackButton:NO];
	}
}

- (void)resetCursorRects {
	NSRect bounds = [self bounds];
	
	NSRect textArea = [[self cell] textAreaForBounds:bounds];
	NSRect clearButtonArea = [[self cell] clearButtonRectForBounds:bounds];
	NSRect snapbackButtonArea = [[self cell] snapbackButtonRectForBounds:bounds];
	
	//always show the pointer over the doc icon area; there is always a doc icon of some sort, even if non-functional
	[self addCursorRect: snapbackButtonArea cursor: [NSCursor arrowCursor]];
	
	//conditionally show the pointer over the clear button area
	if ([[self cell] clearButtonIsVisible]) {
		[self addCursorRect: clearButtonArea cursor: [NSCursor arrowCursor]];
	} else {
		textArea = NSUnionRect(textArea, clearButtonArea);
	}
	[self addCursorRect: textArea cursor: IBeamCursor];
	
	[self removeAllToolTips];
	textAreaTag = [self addToolTipRect:textArea owner:self userData:NULL];
	clearButtonTag = [self addToolTipRect:clearButtonArea owner:self userData:NULL];	
	docIconTag = [self addToolTipRect:snapbackButtonArea owner:self userData:NULL];
}


- (void)reflectScrolledClipView:(NSClipView *)aClipView {	
	[super setKeyboardFocusRingNeedsDisplayInRect: [self bounds]];
}

- (BOOL)hasFollowedLinks {
	return [followedLinks count] != 0;
}
- (void)pushFollowedLink:(NoteBookmark*)aBM {

	[followedLinks addObject:aBM];
}

- (NoteBookmark*)popLastFollowedLink {
	
	NoteBookmark *aBookmark = [[followedLinks lastObject] retain];
	[followedLinks removeLastObject];
	 
	[[NSApp delegate] searchForString:[aBookmark searchString]];
	[[NSApp delegate] revealNote:[aBookmark noteObject] options:0];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearFollowedLinks) object:nil];

	return [aBookmark autorelease];
}

- (void)clearFollowedLinks {
	[followedLinks removeAllObjects];
}

- (void)setSnapbackString:(NSString*)string {
	
	NSString *proposedString = string ? [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
	
	if (proposedString != snapbackString /*the nil == nil case*/ && ![proposedString isEqualToString:snapbackString]) {
		[snapbackString release];
		snapbackString = [proposedString copy];		
	}
	if (![proposedString length]) {
		[[self cell] setShowsSnapbackButton:NO];
	}
	[self performSelector:@selector(clearFollowedLinks) withObject:nil afterDelay:0];
}
- (NSString*)snapbackString {
	return snapbackString;
}

/*- (BOOL)becomeFirstResponder {
	[[NSApp delegate] updateEmptyViewStatus];
	return [super becomeFirstResponder];
}*/

- (void)setShowsDocumentIcon:(BOOL)showsIcon {
	if (showsIcon != showsDocumentIcon) {
		showsDocumentIcon = showsIcon;
		[self setNeedsDisplay:YES];
	}
}

- (BOOL)showsDocumentIcon {
	return showsDocumentIcon;
}

- (BOOL)textView:(NSTextView *)aTextView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString {
	
	//if ([replacementString rangeOfString:@"\n" options:NSLiteralSearch].location != NSNotFound) {
//		//NO! you cannot paste line feeds.
//		return NO;
//	}
	
	lastLengthReplaced = [replacementString length];
	
	return YES;
}

- (NSUInteger)lastLengthReplaced {
	return lastLengthReplaced;
}

- (void)snapback:(id)sender {
	if ([self hasFollowedLinks]) {
		[self popLastFollowedLink];
	} else {
		[notesTable deselectAll:sender];
	}
}

//elasticwork



- (void)mouseDown:(NSEvent*)anEvent {
    
//    NSLog(@"df mouse down");
//    [[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
    [[NSApp delegate] setIsEditing:NO];
	
	if ([[self cell] handleMouseDown:anEvent])
		return;
	
	[super mouseDown:anEvent];
    
}

- (void)flagsChanged:(NSEvent *)theEvent{
	[[NSApp delegate] flagsChanged:theEvent];
}

@end
