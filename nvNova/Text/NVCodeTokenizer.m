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

typedef struct {
	const char *name;
	const char *aliases;				//comma-separated, no spaces
	const char *keywords;				//space-separated word list
	const char *lineCommentPrefix;		//NULL if the language has none
	const char *blockCommentOpen;		//NULL if the language has none
	const char *blockCommentClose;
	const char *keywordExtraPattern;	//extra regex alternative for the keyword class (e.g. objc @directives)
	const char *stringExtraPattern;		//extra regex alternative for the string class (e.g. js template literals)
	BOOL tripleQuotedStrings;
	BOOL caseInsensitiveKeywords;
} NVCodeLanguageDef;

static const NVCodeLanguageDef languageDefs[] = {
	{
		"python", "py,python3",
		"False None True and as assert async await break class continue def del elif else except finally "
		"for from global if import in is lambda nonlocal not or pass raise return try while with yield self",
		"#", NULL, NULL, NULL, NULL, YES, NO
	},
	{
		"bash", "sh,shell,zsh",
		"if then else elif fi case esac for while until do done in function select break continue return "
		"exit export local readonly declare typeset unset shift source alias eval exec set trap wait cd "
		"echo printf read test true false",
		"#", NULL, NULL, NULL, NULL, NO, NO
	},
	{
		"groovy", "gvy,gy,gradle",
		"abstract as assert boolean break byte case catch char class const continue def default do double "
		"else enum extends final finally float for goto if implements import in instanceof int interface "
		"long native new null package private protected public return short static strictfp super switch "
		"synchronized this throw throws trait transient try var void volatile while true false",
		"//", "/*", "*/", NULL, NULL, YES, NO
	},
	{
		"sql", "mysql,postgresql,tsql",
		"select from where insert into values update set delete create table alter drop index view as and "
		"or not null is in exists between like limit offset order by group having distinct join inner left "
		"right full outer cross on union all case when then else end primary key foreign references default "
		"unique check constraint database schema grant revoke begin commit rollback transaction with recursive",
		"--", "/*", "*/", NULL, NULL, NO, YES
	},
	{
		"javascript", "js,node",
		"async await break case catch class const continue debugger default delete do else export extends "
		"finally for function if import in instanceof let new of return static super switch this throw try "
		"typeof var void while with yield true false null undefined",
		"//", "/*", "*/", NULL, "(?s:`(?:\\\\.|[^`\\\\])*`)", NO, NO
	},
	{
		"objc", "objective-c,c,m,h",
		"auto break case char const continue default do double else enum extern float for goto if inline "
		"int long register return short signed sizeof static struct switch typedef union unsigned void "
		"volatile while BOOL Class SEL IMP id instancetype nil Nil self super YES NO",
		"//", "/*", "*/", "@[A-Za-z_][A-Za-z0-9_]*", NULL, NO, NO
	},
	{
		"json", NULL,
		"true false null",
		NULL, NULL, NULL, NULL, NULL, NO, NO
	},
	{
		"yaml", "yml",
		"true false null yes no on off",
		"#", NULL, NULL, "(?m:^[ \\t]*-?[ \\t]*[A-Za-z_][A-Za-z0-9_.-]*(?=:))", NULL, NO, YES
	},
};
#define kNVCodeLanguageCount (sizeof(languageDefs) / sizeof(languageDefs[0]))

//maps every language name and alias to its index in languageDefs; intentionally immortal
static NSDictionary *_tagMap(void) {
	static NSDictionary *map = nil;
	if (!map) {
		NSMutableDictionary *building = [[NSMutableDictionary alloc] init];
		NSUInteger i;
		for (i = 0; i < kNVCodeLanguageCount; i++) {
			NSNumber *index = [NSNumber numberWithUnsignedInteger:i];
			[building setObject:index forKey:[NSString stringWithUTF8String:languageDefs[i].name]];
			if (languageDefs[i].aliases) {
				NSArray *aliases = [[NSString stringWithUTF8String:languageDefs[i].aliases] componentsSeparatedByString:@","];
				NSString *alias;
				for (alias in aliases) [building setObject:index forKey:alias];
			}
		}
		map = building;
	}
	return map;
}

//one compiled expression per language, built lazily; four capture groups in
//token-class order (comment|string|number|keyword) so earlier classes win
static NSRegularExpression *_expressionForLanguage(NSUInteger languageID) {
	static NSRegularExpression *expressions[kNVCodeLanguageCount];
	if (languageID >= kNVCodeLanguageCount) return nil;
	if (expressions[languageID]) return expressions[languageID];

	const NVCodeLanguageDef *def = &languageDefs[languageID];
	NSString *neverMatch = @"[^\\s\\S]";

	NSMutableArray *commentAlts = [NSMutableArray array];
	if (def->lineCommentPrefix) {
		NSString *prefix = [NSRegularExpression escapedPatternForString:[NSString stringWithUTF8String:def->lineCommentPrefix]];
		[commentAlts addObject:[NSString stringWithFormat:@"%@[^\n]*", prefix]];
	}
	if (def->blockCommentOpen && def->blockCommentClose) {
		NSString *open = [NSRegularExpression escapedPatternForString:[NSString stringWithUTF8String:def->blockCommentOpen]];
		NSString *close = [NSRegularExpression escapedPatternForString:[NSString stringWithUTF8String:def->blockCommentClose]];
		[commentAlts addObject:[NSString stringWithFormat:@"(?s:%@.*?%@)", open, close]];
	}

	NSMutableArray *stringAlts = [NSMutableArray array];
	if (def->tripleQuotedStrings)
		[stringAlts addObject:@"(?s:'''.*?'''|\"\"\".*?\"\"\")"];
	if (def->stringExtraPattern)
		[stringAlts addObject:[NSString stringWithUTF8String:def->stringExtraPattern]];
	[stringAlts addObject:@"\"(?:\\\\.|[^\"\\\\\n])*\""];
	[stringAlts addObject:@"'(?:\\\\.|[^'\\\\\n])*'"];

	NSString *numberPattern = @"\\b(?:0[xX][0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b";

	NSMutableArray *keywordAlts = [NSMutableArray array];
	if (def->keywords) {
		NSArray *words = [[NSString stringWithUTF8String:def->keywords] componentsSeparatedByString:@" "];
		NSString *wordGroup = [NSString stringWithFormat:@"\\b(?:%@)\\b", [words componentsJoinedByString:@"|"]];
		if (def->caseInsensitiveKeywords)
			wordGroup = [NSString stringWithFormat:@"(?i:%@)", wordGroup];
		[keywordAlts addObject:wordGroup];
	}
	if (def->keywordExtraPattern)
		[keywordAlts addObject:[NSString stringWithUTF8String:def->keywordExtraPattern]];

	NSString *pattern = [NSString stringWithFormat:@"(%@)|(%@)|(%@)|(%@)",
						 [commentAlts count] ? [commentAlts componentsJoinedByString:@"|"] : neverMatch,
						 [stringAlts count] ? [stringAlts componentsJoinedByString:@"|"] : neverMatch,
						 numberPattern,
						 [keywordAlts count] ? [keywordAlts componentsJoinedByString:@"|"] : neverMatch];

	NSError *error = nil;
	NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:pattern options:0 error:&error];
	if (!regex) {
		//failure mode: this language simply doesn't highlight
		NSLog(@"[NVCTOK] regex build failed for %s: %@", def->name, error);
		return nil;
	}
	expressions[languageID] = regex;	//intentionally immortal
	return regex;
}

@implementation NVCodeTokenizer

+ (NSUInteger)languageIDForInfoString:(NSString*)infoString {
	if (![infoString length]) return NVCodeLanguageNone;
	NSRange spaceRange = [infoString rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
	NSString *tag = (spaceRange.location == NSNotFound) ? infoString : [infoString substringToIndex:spaceRange.location];
	NSNumber *index = [_tagMap() objectForKey:[tag lowercaseString]];
	return index ? [index unsignedIntegerValue] : NVCodeLanguageNone;
}

+ (void)enumerateTokensInString:(NSString*)string range:(NSRange)range languageID:(NSUInteger)languageID
					 usingBlock:(void (^)(NSRange tokenRange, NVCodeTokenClass tokenClass))block {
	if (!block || !range.length || NSMaxRange(range) > [string length]) return;
	NSRegularExpression *regex = _expressionForLanguage(languageID);
	if (!regex) return;

	@autoreleasepool {
		NSArray *matches = [regex matchesInString:string options:0 range:range];
		NSTextCheckingResult *match;
		for (match in matches) {
			NSUInteger groupIndex;
			for (groupIndex = 1; groupIndex <= NVCodeTokenClassCount; groupIndex++) {
				NSRange groupRange = [match rangeAtIndex:groupIndex];
				if (groupRange.location != NSNotFound && groupRange.length) {
					//capture groups are declared in NVCodeTokenClass order
					block(groupRange, (NVCodeTokenClass)(groupIndex - 1));
					break;
				}
			}
		}
	}
}

@end
