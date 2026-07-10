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

@end
