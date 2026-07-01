//
//  PTHotKeyCenter.h
//  Protein
//
//  Created by Quentin Carnicelli on Sat Aug 02 2003.
//  Copyright (c) 2003 Quentin D. Carnicelli. All rights reserved.
//

#import <AppKit/AppKit.h>

@class PTHotKey;

@interface PTHotKeyCenter : NSObject
{
	NSMutableDictionary*	mHotKeys; //name → PTHotKey
	//NVN-5: replaced the Carbon Event Manager hot-key registration with a single CGEventTap
	//(Carbon RegisterEventHotKey/InstallEventHandler are gone). One session tap watches key-down events
	//and matches them against the registered key combos.
	CFMachPortRef			mEventTap;
	CFRunLoopSourceRef		mRunLoopSource;
}

+ (id)sharedCenter;

//- (void) enterHotKeyWithName:(NSString *)name enable:(BOOL)ena;
- (BOOL)registerHotKey: (PTHotKey*)hotKey;
- (void)unregisterHotKey: (PTHotKey*)hotKey;
- (void) unregisterHotKeyForName:(NSString *)name;
- (void) unregisterAllHotKeys;
- (void) setHotKeyRegistrationForName:(NSString *)name enable:(BOOL)ena;
- (PTHotKey *) hotKeyForName:(NSString *)name;
- (void) updateHotKey:(PTHotKey *)hk;

- (NSArray*)allHotKeys;

@end
