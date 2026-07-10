//
//  NVCodeTokenizer.m
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


#import "NVCodeTokenizer.h"

@implementation NVCodeTokenizer

+ (NSUInteger)languageIDForInfoString:(NSString*)infoString {
	return NVCodeLanguageNone;
}

+ (void)enumerateTokensInString:(NSString*)string range:(NSRange)range languageID:(NSUInteger)languageID
					 usingBlock:(void (^)(NSRange tokenRange, NVCodeTokenClass tokenClass))block {
	//no language tables yet; nothing to enumerate
}

@end
