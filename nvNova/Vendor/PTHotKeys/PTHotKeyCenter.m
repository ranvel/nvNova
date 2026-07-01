//
//  PTHotKeyCenter.m
//  Protein
//
//  Created by Quentin Carnicelli on Sat Aug 02 2003.
//  Copyright (c) 2003 Quentin D. Carnicelli. All rights reserved.
//
//  NVN-5: reimplemented on a CGEventTap (Quartz Event Services) so global hot keys no longer depend on
//  the Carbon Event Manager (RegisterEventHotKey / InstallEventHandler / the Carbon event dispatcher).
//  Behavior change: an active session tap requires the app to be trusted for Accessibility; the user is
//  prompted the first time a hot key is registered without that trust. The public API is unchanged.
//

#import "PTHotKeyCenter.h"
#import "PTHotKey.h"
#import "PTKeyCombo.h"
#import <ApplicationServices/ApplicationServices.h>

//PTKeyCombo persists modifiers as Carbon modifier bits (Events.h cmdKey/shiftKey/optionKey/controlKey),
//and those values are stored in user defaults, so they must be interpreted exactly. Mirror them here
//rather than importing Carbon.
enum {
	kPTCmdKeyMask     = 0x0100,
	kPTShiftKeyMask   = 0x0200,
	kPTOptionKeyMask  = 0x0800,
	kPTControlKeyMask = 0x1000
};

@interface PTHotKeyCenter (Private)
- (void)_ensureEventTap;
- (void)_teardownEventTapIfIdle;
- (void)_reenableTap;
- (PTHotKey*)_hotKeyMatchingKeyCode:(CGKeyCode)keyCode flags:(CGEventFlags)flags;
- (void)_fireHotKey:(PTHotKey*)hotKey;
@end

static CGEventRef PTHotKeyEventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon);

@implementation PTHotKeyCenter

static id _sharedHotKeyCenter = nil;

+ (id)sharedCenter
{
	if( _sharedHotKeyCenter == nil )
	{
		_sharedHotKeyCenter = [[self alloc] init];
	}

	return _sharedHotKeyCenter;
}

- (id)init
{
	self = [super init];

	if( self )
	{
		mHotKeys = [[NSMutableDictionary alloc] init];
	}

	return self;
}

- (void)dealloc
{
	[self _teardownEventTapIfIdle];
	[mHotKeys release];
	[super dealloc];
}

#pragma mark -

- (BOOL)registerHotKey: (PTHotKey*)hotKey
{
	if( hotKey == nil )
		return NO;

	if( [[hotKey keyCombo] isValidHotKeyCombo] == NO )
	{
		//a "clear" combo is accepted but registers nothing (matches the original behavior)
		return YES;
	}

	[mHotKeys setObject: hotKey forKey: [hotKey name]];
	[self _ensureEventTap];

	return YES;
}

- (void)unregisterHotKey: (PTHotKey*)hotKey
{
	if( ![mHotKeys objectForKey:[hotKey name]] )
		return;

	[mHotKeys removeObjectForKey: [hotKey name]];
	[self _teardownEventTapIfIdle];
}

- (void) unregisterHotKeyForName:(NSString *)name
{
    [self unregisterHotKey:[mHotKeys objectForKey:name]];
}

- (void) unregisterAllHotKeys;
{
    NSEnumerator *enumerator = [[mHotKeys allValues] objectEnumerator];
    id thing;
    while ((thing = [enumerator nextObject]))
    {
        [self unregisterHotKey:thing];
    }
}

- (void) setHotKeyRegistrationForName:(NSString *)name enable:(BOOL)ena
{
    if (ena)
    {
        [self registerHotKey:[mHotKeys objectForKey:name]];
    } else
    {
        [self unregisterHotKey:[mHotKeys objectForKey:name]];
    }
}

- (void) updateHotKey:(PTHotKey *)hk
{
    [hk retain];
    [self unregisterHotKey:[mHotKeys objectForKey:[hk name]]];
    [self registerHotKey:hk];
    [hk release];
}

- (PTHotKey *) hotKeyForName:(NSString *)name
{
    return [mHotKeys objectForKey:name];
}

- (NSArray*)allHotKeys
{
	return [mHotKeys allValues];
}

#pragma mark -

- (void)_ensureEventTap
{
	if( mEventTap != NULL || [mHotKeys count] == 0 )
		return;

	//an active tap that can swallow the matched combo requires Accessibility trust; prompt once if needed
	if( !AXIsProcessTrusted() )
	{
		NSDictionary *opts = [NSDictionary dictionaryWithObject:(id)kCFBooleanTrue
														 forKey:(id)kAXTrustedCheckOptionPrompt];
		AXIsProcessTrustedWithOptions( (CFDictionaryRef)opts );
	}

	CGEventMask mask = CGEventMaskBit( kCGEventKeyDown );
	mEventTap = CGEventTapCreate( kCGSessionEventTap, kCGHeadInsertEventTap,
								  kCGEventTapOptionDefault, mask, PTHotKeyEventTapCallback, (void*)self );
	if( mEventTap == NULL )
	{
		NSLog(@"PTHotKeyCenter: could not create the global hot-key event tap. Grant Notational Velocity "
			  @"Accessibility access in System Settings to enable global hot keys.");
		return;
	}

	mRunLoopSource = CFMachPortCreateRunLoopSource( kCFAllocatorDefault, mEventTap, 0 );
	CFRunLoopAddSource( CFRunLoopGetMain(), mRunLoopSource, kCFRunLoopCommonModes );
	CGEventTapEnable( mEventTap, true );
}

- (void)_teardownEventTapIfIdle
{
	if( [mHotKeys count] > 0 )
		return;

	if( mRunLoopSource != NULL )
	{
		CFRunLoopRemoveSource( CFRunLoopGetMain(), mRunLoopSource, kCFRunLoopCommonModes );
		CFRelease( mRunLoopSource );
		mRunLoopSource = NULL;
	}
	if( mEventTap != NULL )
	{
		CGEventTapEnable( mEventTap, false );
		CFRelease( mEventTap );
		mEventTap = NULL;
	}
}

- (void)_reenableTap
{
	//the system disables a tap that is too slow or is interrupted; turn it back on
	if( mEventTap != NULL )
		CGEventTapEnable( mEventTap, true );
}

- (PTHotKey*)_hotKeyMatchingKeyCode:(CGKeyCode)keyCode flags:(CGEventFlags)flags
{
	BOOL cmd   = (flags & kCGEventFlagMaskCommand)   != 0;
	BOOL shift = (flags & kCGEventFlagMaskShift)     != 0;
	BOOL opt   = (flags & kCGEventFlagMaskAlternate) != 0;
	BOOL ctrl  = (flags & kCGEventFlagMaskControl)   != 0;

	for( id name in mHotKeys )
	{
		PTHotKey *hotKey = [mHotKeys objectForKey:name];
		PTKeyCombo *combo = [hotKey keyCombo];
		if( (CGKeyCode)[combo keyCode] != keyCode )
			continue;

		int m = [combo modifiers];
		if( (((m & kPTCmdKeyMask)    != 0) == cmd)   &&
			(((m & kPTShiftKeyMask)  != 0) == shift) &&
			(((m & kPTOptionKeyMask) != 0) == opt)   &&
			(((m & kPTControlKeyMask)!= 0) == ctrl) )
			return hotKey;
	}
	return nil;
}

- (void)_fireHotKey:(PTHotKey*)hotKey
{
	[hotKey invoke];
}

@end

static CGEventRef PTHotKeyEventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
	PTHotKeyCenter *center = (PTHotKeyCenter*)refcon;

	if( type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput )
	{
		[center _reenableTap];
		return event;
	}

	if( type != kCGEventKeyDown )
		return event;

	CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField( event, kCGKeyboardEventKeycode );
	CGEventFlags flags = CGEventGetFlags( event );

	PTHotKey *hotKey = [center _hotKeyMatchingKeyCode:keyCode flags:flags];
	if( hotKey != nil )
	{
		//the callback runs on the main run loop (the source is added there); defer the invoke to the
		//next cycle so we don't re-enter event handling while still inside the tap callback
		[center performSelectorOnMainThread:@selector(_fireHotKey:) withObject:hotKey waitUntilDone:NO];
		return NULL; //swallow the combo, matching the old RegisterEventHotKey behavior
	}

	return event;
}
