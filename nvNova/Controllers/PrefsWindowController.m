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

#import "AppController.h"
#import "PrefsWindowController.h"
#import "PTKeyComboPanel.h"
#import "PTKeyCombo.h"
#import "NotationPrefsViewController.h"
#import "ExternalEditorListController.h"
#import "NSData_transformations.h"
#import "NSString_NV.h"
#import "NSFileManager_NV.h"
#import "NSBezierPath_NV.h"
#import "BufferUtils.h"
#import "NotationPrefs.h"
#import "NotationFileManager.h"
#import "GlobalPrefs.h"

#define SYSTEM_LIST_FONT_SIZE 12.0f

//NVN-15 sidebar settings shell geometry
static const CGFloat kSidebarWidth = 190.0f;
static const CGFloat kDetailWidth = 460.0f;	//fits the widest legacy pane (Fonts & Colors, 420) with margins
static const CGFloat kPaneMargin = 20.0f;
static NSString *const kNavBackItemIdentifier = @"NVNavBack";
static NSString *const kNavForwardItemIdentifier = @"NVNavForward";
static NSString *const kSidebarSeparatorItemIdentifier = @"NVSidebarSeparator";

static NSString *NVSymbolNameForPane(NSString *identifier) {
	if ([identifier isEqualToString:@"Notes"]) return @"folder";
	if ([identifier isEqualToString:@"Editing"]) return @"pencil";
	if ([identifier isEqualToString:@"Fonts & Colors"]) return @"textformat";
	return @"gearshape";	//General
}

//programmatic control builders for the rebuilt General pane; each returns an
//unretained reference (the superview owns it), matching IBOutlet semantics
static NSButton *NVAddCheckbox(NSView *parent, NSString *title, id target, SEL action, NSRect frame) {
	NSButton *button = [[NSButton alloc] initWithFrame:frame];
	[button setButtonType:NSButtonTypeSwitch];
	[button setTitle:title];
	[button setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[button setTarget:target];
	[button setAction:action];
	[parent addSubview:button];
	[button release];
	return button;
}

static NSTextField *NVAddLabel(NSView *parent, NSString *string, NSRect frame, NSTextAlignment alignment, BOOL small) {
	NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
	[field setStringValue:string];
	[field setEditable:NO];
	[field setSelectable:NO];
	[field setBezeled:NO];
	[field setDrawsBackground:NO];
	[field setAlignment:alignment];
	[field setFont:[NSFont systemFontOfSize:small ? [NSFont smallSystemFontSize] : [NSFont systemFontSize]]];
	if (small) [field setTextColor:[NSColor secondaryLabelColor]];
	[parent addSubview:field];
	[field release];
	return field;
}

static NSButton *NVAddPushButton(NSView *parent, NSString *title, id target, SEL action, NSRect frame) {
	NSButton *button = [[NSButton alloc] initWithFrame:frame];
	[button setBezelStyle:NSBezelStyleRounded];
	[button setTitle:title];
	[button setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[button setTarget:target];
	[button setAction:action];
	[parent addSubview:button];
	[button release];
	return button;
}

@implementation PrefsWindowController

- (id)init {
    if (self=[super init]) {
		prefsController = [GlobalPrefs defaultPrefs];
		fontPanelWasOpen = NO;
      // remove opacity slider from color pickers -bt
    [[NSColorPanel sharedColorPanel] setShowsAlpha:NO];
		[prefsController registerWithTarget:self forChangesInSettings:
		 @selector(resolveNoteBodyFontFromNotationPrefsFromSender:), 
//		 @selector(setCheckSpellingAsYouType:sender:), 
		 @selector(setConfirmNoteDeletion:sender:), nil];
    }
    return self;
}

- (void)showWindow:(id)sender {
	if (!window) {
		if (![NSBundle loadNibNamed:@"Preferences" owner:self])  {
			NSLog(@"Failed to load Preferences.nib");
			return;
		}
	}
	[checkSpellingButton setState:[prefsController checkSpellingAsYouType]];
	BOOL firstShow = ![window isVisible];
	if (firstShow)
		[window center];

	[window makeKeyAndOrderFront:self];
	if (firstShow) {
		//the toolbar's safe-area inset isn't final until the window has been laid
		//out on screen, so re-run the pane fit once now
		[self selectPaneWithIdentifier:currentPaneIdentifier animate:NO];
	}
    if (!NSApp.isActive) {
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)windowWillClose:(NSNotification *)aNotification {
	[prefsController performSelector:@selector(synchronize) withObject:nil afterDelay:0.0];
	
	[[NSFontPanel sharedFontPanel] close];
}
- (void)windowDidResignMain:(NSNotification *)aNotification {
	//hide the font panel--don't want to confuse people into thinking it will affect some other part of the program
	fontPanelWasOpen = [[NSFontPanel sharedFontPanel] isVisible];
	[[NSFontPanel sharedFontPanel] orderOut:nil];
}
- (void)windowDidBecomeMain:(NSNotification *)aNotification {
	if (fontPanelWasOpen) {
		[self changeBodyFont:self];
	}
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
	NSLog(@"I need an update: %@", [menu description]);
}

- (IBAction)setAppShortcut:(id)sender {
	[[PTKeyComboPanel sharedPanel] showSheetForHotkey:[prefsController appActivationHotKey] forWindow:window modalDelegate:self];
}

- (void)keyComboPanelEnded:(PTKeyComboPanel*)panel {
	PTKeyCombo *oldKeyCombo = [[prefsController appActivationKeyCombo] retain];
	[prefsController setAppActivationKeyCombo:[panel keyCombo] sender:self];
	
	[appShortcutField setStringValue:[[prefsController appActivationKeyCombo] description]];
		
	if (![prefsController registerAppActivationKeystrokeWithTarget:[NSApp delegate] selector:@selector(toggleNVActivation:)]) {
		[prefsController setAppActivationKeyCombo:oldKeyCombo sender:self];
		NSLog(@"reverting to old (hopefully working key combo");
	}
	
	[oldKeyCombo release];
}

- (IBAction)changeBodyFont:(id)sender {
	[[NSFontManager sharedFontManager] setSelectedFont:[prefsController noteBodyFont] isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

- (void)changeFont:(id)sender {
	NSFontManager *fontMan = [NSFontManager sharedFontManager];
	NSFont *panelFont = [fontMan convertFont:[fontMan selectedFont]];
	
	if (/*![fontMan fontNamed:[panelFont fontName] hasTraits:NSUnboldFontMask | NSUnitalicFontMask]*/
	([fontMan traitsOfFont:panelFont] & NSItalicFontMask) == NSItalicFontMask ||
	([fontMan traitsOfFont:panelFont] & NSBoldFontMask) == NSBoldFontMask) {
		//revert the font--using a bold or italic variant as the default could cause some notes to lose styles
	//	NSLog(@"traits: %u", [fontMan traitsOfFont:panelFont]); 
		
		[self performSelector:@selector(changeBodyFont:) withObject:sender afterDelay:0.0];
		NSBeep();
	} else {
		[prefsController setNoteBodyFont:panelFont sender:self];
	
		[self previewNoteBodyFont];
	}
}

- (NSUInteger)validModesForFontPanel:(NSFontPanel *)fontPanel {
	
	return NSFontPanelSizeModeMask | NSFontPanelCollectionModeMask;
}

- (void)previewNoteBodyFont {

	if (!centerStyle) {
		centerStyle = [[NSMutableParagraphStyle alloc] init];
		[centerStyle setAlignment:NSCenterTextAlignment];
	}

	NSFont *font = [prefsController noteBodyFont];
    CGFloat lh=[font pointSize];
    if (lh<27.0) {
        lh=floorf(27.0-((27.0-lh)/2));
    }
    [centerStyle setMaximumLineHeight:lh];
	NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:font ? font : [NSFont systemFontOfSize:12.0],
		NSFontAttributeName, [NSColor blackColor], NSForegroundColorAttributeName, centerStyle, NSParagraphStyleAttributeName, nil];

	NSString *fontNameAndSize = font ? [NSString stringWithFormat:@"%@ %g", [font fontName], [font pointSize]] : @"Unknown";
	NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:fontNameAndSize attributes:attributes];
	
	[[bodyTextFontField cell] setAttributedStringValue:attributedString];
    [bodyTextFontField updateCell:[bodyTextFontField cell]];
	
	[attributedString autorelease];
	
}

- (IBAction)changedUseETScrollbarsOnLion:(id)sender{
    [prefsController setUseETScrollbarsOnLion:[useETScrollbarsOnLionButton state] sender:self];
}

- (IBAction)changedBackgroundTextColorWell:(id)sender {
	[prefsController setBackgroundTextColor:[backgroundColorWell color] sender:self];
}
- (IBAction)changedForegroundTextColorWell:(id)sender {
	[prefsController setForegroundTextColor:[foregroundColorWell color] sender:self];
}
- (IBAction)changedSearchHighlightColorWell:(id)sender {
	[prefsController setSearchTermHighlightColor:[searchHighlightColorWell color] sender:self];
}
- (IBAction)changedHighlightSearchTerms:(id)sender {
	[prefsController setShouldHighlightSearchTerms:[highlightSearchTermsButton state] sender:self];
}
- (IBAction)changedDarkCodeBlocks:(id)sender {
	[prefsController setUseDarkCodeBlocks:[darkCodeBlocksButton state] sender:self];
}
- (IBAction)changedStyledTextBehavior:(id)sender {
    [prefsController setPastePreservesStyle:[styledTextButton state] sender:self];
}
- (IBAction)changedAutoSuggestLinks:(id)sender {
    [prefsController setLinksAutoSuggested:[autoSuggestLinksButton state] sender:self];
}

- (IBAction)changedMakeURLsClickable:(id)sender {
	[prefsController setMakeURLsClickable:[makeURLsClickable state] sender:self];
}

- (IBAction)changedNoteDeletion:(id)sender {
	[prefsController setConfirmNoteDeletion:[confirmDeletionButton state] sender:self];
}

- (IBAction)changedNotesFolderLocation:(id)sender {
    NSLog(@"Changed notes folder menu");
}

- (IBAction)changedQuitBehavior:(id)sender {
    [prefsController setQuitWhenClosingWindow:[quitWhenClosingButton state] sender:self];
}

- (IBAction)changedSpellChecking:(id)sender {
    [prefsController setCheckSpellingAsYouType:[checkSpellingButton state] sender:self];
}


- (IBAction)changedTabBehavior:(id)sender {
    if (sender != self)
	[self performSelector:@selector(changedTabBehavior:) withObject:self afterDelay:0.0];
    else
	[prefsController setTabIndenting:[[tabKeyRadioMatrix cellAtRow:0 column:0] state] sender:self];
}

- (IBAction)changedExternalEditorsMenu:(id)sender {
  //not currently called as an action in practice
  [self _selectDefaultExternalEditor];
}

- (void)_selectDefaultExternalEditor {
  ExternalEditor *ed = [[ExternalEditorListController sharedInstance] defaultExternalEditor];
  NSInteger idx = ed ? [externalEditorMenuButton indexOfItemWithRepresentedObject:ed] : 0;
  if (idx > -1) {
    [externalEditorMenuButton selectItemAtIndex:idx];
  }
}

- (IBAction)changedTableText:(id)sender {
	if (sender == tableTextMenuButton) {
		if ([tableTextSizeField selectedTag] != 3) [tableTextSizeField setFloatValue:[prefsController tableFontSize]];
		[self performSelector:@selector(changedTableText:) withObject:nil afterDelay:0.0];
	} else {
		[window makeFirstResponder:window];
		float newFontSize = 0.0;
		switch ([tableTextMenuButton selectedTag]) {
			case 1:
				newFontSize = [NSFont smallSystemFontSize];
				break;
			case 2:
				newFontSize = /*[NSFont systemFontSize]*/ SYSTEM_LIST_FONT_SIZE;
				break;
			case 3:
				newFontSize = [tableTextSizeField floatValue];
		}
		[tableTextSizeField setHidden:([tableTextMenuButton selectedTag] != 3)];
		if (![tableTextSizeField isHidden])
			[tableTextSizeField selectText:sender];
		
		[prefsController setTableFontSize:newFontSize sender:self];
	}	
}

- (IBAction)changedTitleCompletion:(id)sender {
    [prefsController setAutoCompleteSearches:[completeNoteTitlesButton state] sender:self];
}

- (IBAction)changedSoftTabs:(id)sender {
	[prefsController setSoftTabs:[softTabsButton state] sender:self];
}

- (void)settingChangedForSelectorString:(NSString*)selectorString {
    if ([selectorString isEqualToString:SEL_STR(resolveNoteBodyFontFromNotationPrefsFromSender:)]) {
		[self previewNoteBodyFont];
//	} else if ([selectorString isEqualToString:SEL_STR(setCheckSpellingAsYouType:sender:)]) {
//		[checkSpellingButton setState:[prefsController checkSpellingAsYouType]];
	} else if ([selectorString isEqualToString:SEL_STR(setConfirmNoteDeletion:sender:)]) {
		[confirmDeletionButton setState:[prefsController confirmNoteDeletion]];
	}
}

- (NSMenu*)directorySelectionMenu {
    NSMenu *theMenu = [[[NSMenu alloc] initWithTitle:@"Note Directory Menu"] autorelease];
    
    NSString *path = [prefsController notesDirectoryPath];
    NSString *name = [path length] ? [[NSFileManager defaultManager] displayNameAtPath:path] : nil;
    if (!name)
		name = NSLocalizedString(@"<Directory unknown>", nil);

	NSImage *iconImage = nil;
	if ([path length]) {
	    iconImage = [[NSWorkspace sharedWorkspace] iconForFile:path];
	    [iconImage setSize:NSMakeSize(16.0f, 16.0f)];
	}

    NSMenuItem *theMenuItem = [[[NSMenuItem alloc] initWithTitle:name action:nil keyEquivalent:@""] autorelease];
    
    if (iconImage)
		[theMenuItem setImage:iconImage];
    
    [theMenu addItem:theMenuItem];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    theMenuItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Other...", @"title of menu item for selecting a different notes folder")
											  action:@selector(changeDefaultDirectory) keyEquivalent:@""] autorelease];
    [theMenuItem setTarget:self];
    [theMenu addItem:theMenuItem];
    
    return theMenu;
}

- (void)changeDefaultDirectory {
	NSString *directoryPath = nil;

	if ([self getNewNotesPathFromOpenPanel:&directoryPath]) {

		//make sure we're not choosing the same folder as what we started with, because:
		//-[NotationController initWithDirectoryPath:] might attempt to initialize journaling, which will already be in use
		if (![directoryPath isEqualToString:[prefsController notesDirectoryPath]]) {

			//sender:self (PrefsWindowController is not a registered observer) fires the
			//callback to AppController, which reloads the database at the new location
			[prefsController setNotesDirectoryPath:directoryPath sender:self];

			//check for potential synchronization problems; (e.g., simplenote w/ dropbox or writeroom):
			[[prefsController notationPrefs] checkForKnownRedundantSyncConduitsAtPath:directoryPath];
		} else {
			NSLog(@"This folder is already chosen!");
		}

	}

	[folderLocationsMenuButton setMenu:[self directorySelectionMenu]];

	if ([folderLocationsMenuButton numberOfItems] > 0)
		[folderLocationsMenuButton selectItemAtIndex:0];
}

- (IBAction)changedRTL:(id)sender {
	[prefsController setRTL:[rtlButton state] sender:self];
	[[NSApp delegate] updateRTL];
}

//NVN-5: returns the chosen folder as a path only (the FSRef out-param is gone; callers pass the path
//to -[NotationController initWithDirectoryPath:])
- (BOOL)getNewNotesPathFromOpenPanel:(NSString**)path {
    //use the stored notes-directory path as the panel's starting location
    NSString *startingDirectory = [prefsController notesDirectoryPath];

    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanCreateDirectories:YES];
    [openPanel setCanChooseFiles:NO];
    [openPanel setCanChooseDirectories:YES];
    [openPanel setResolvesAliases:YES];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setTreatsFilePackagesAsDirectories:NO];
    [openPanel setTitle:NSLocalizedString(@"Select a folder",@"title of open panel for selecting a notes folder")];
    [openPanel setPrompt:NSLocalizedString(@"Select", @"title of open panel button to select a folder")];
    [openPanel setMessage:NSLocalizedString(@"Select the folder that Notational Velocity should use for reading and storing notes.",nil)];
    if ([startingDirectory length]) [openPanel setDirectoryURL:[NSURL fileURLWithPath:startingDirectory]];
    [openPanel setAllowedFileTypes:nil];
    while ([openPanel runModal]==NSFileHandlingPanelOKButton) {

		NSString *chosen = [[openPanel URL] path];
		if (![chosen length])
			return NO;

		//NVN-12: gate on the volume's filesystem before the path escapes the picker; this is
		//the shared chokepoint for the prefs "change folder" path (which used to persist — and
		//reload the database — before anything could object) and the startup retry loop
		NSString *fsTypeName = nil;
		if (!NVVolumeIsAcceptableForNotes(chosen, &fsTypeName)) {
			if (NSRunAlertPanel(NVUnacceptableFSAlertMessage(chosen, fsTypeName),
								NSLocalizedString(@"nvNova needs a filesystem with trustworthy timestamps and atomic saves: APFS, HFS+, or ZFS. Volumes like exFAT, FAT, and network shares can quietly eat your data. Please choose a folder on a supported volume.",nil),
								NSLocalizedString(@"Try Again",nil), NSLocalizedString(@"Cancel",nil), NULL) == NSAlertDefaultReturn)
				continue;
			return NO;
		}

		if (path)
			*path = [[chosen copy] autorelease];

		return YES;
    }

    return NO;
}

- (NotationPrefsViewController*)notationPrefsViewController {
	if (!notationPrefsViewController) {
		notationPrefsViewController = [[NotationPrefsViewController alloc] init];
	}
	return notationPrefsViewController;
}

- (NSView*)databaseView {
    if (![notationPrefsView subviews] || ![[notationPrefsView subviews] count])
		[notationPrefsView addSubview:[[self notationPrefsViewController] view]];
	
    return databaseView;
}

- (void)awakeFromNib {

	//NVN-15: the xib's legacy tabbed window and General pane are discarded here;
	//the other pane views are top-level nib objects and survive to be hosted by
	//the new sidebar shell
	NSWindow *legacyWindow = window;
	window = nil;
	NSView *legacyGeneralView = generalView;
	generalView = nil;

	[self _buildGeneralPane];
	[self _buildSettingsWindow];

	[legacyGeneralView release];
	[legacyWindow release];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changedTableText:)
												 name:NSControlTextDidEndEditingNotification object:tableTextSizeField];

    [tabKeyRadioMatrix setState:[prefsController tabKeyIndents] atRow:0 column:0];
    [tabKeyRadioMatrix setState:![prefsController tabKeyIndents] atRow:1 column:0];
    
    float fontSize = [prefsController tableFontSize];
    int fontButtonIndex = 3;
    if (fontSize == [NSFont smallSystemFontSize]) fontButtonIndex = 0;
    else if (fontSize == /*[NSFont systemFontSize]*/ SYSTEM_LIST_FONT_SIZE) fontButtonIndex = 1;
    [tableTextMenuButton selectItemAtIndex:fontButtonIndex];
    [tableTextSizeField setFloatValue:fontSize];
    [tableTextSizeField setHidden:(fontButtonIndex != 3)];
    
    [externalEditorMenuButton setMenu:[[ExternalEditorListController sharedInstance] addEditorPrefsMenu]];
    [self _selectDefaultExternalEditor];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changedExternalEditorsMenu:) 
                           name:ExternalEditorsChangedNotification object:nil];
    
    [completeNoteTitlesButton setState:[prefsController autoCompleteSearches]];
//    [checkSpellingButton setState:[prefsController checkSpellingAsYouType]];
    [confirmDeletionButton setState:[prefsController confirmNoteDeletion]];
    [quitWhenClosingButton setState:[prefsController quitWhenClosingWindow]];
    [styledTextButton setState:[prefsController pastePreservesStyle]];
    [autoSuggestLinksButton setState:[prefsController linksAutoSuggested]];
	[softTabsButton setState:[prefsController softTabs]];
	[makeURLsClickable setState:[prefsController URLsAreClickable]];
    [rtlButton setState:[prefsController rtl]];
    [self previewNoteBodyFont];
	[appShortcutField setStringValue:[[prefsController appActivationKeyCombo] description]];
	[searchHighlightColorWell setColor:[prefsController searchTermHighlightColorRaw:YES]];
	[highlightSearchTermsButton setState:[prefsController highlightSearchTerms]];
	[darkCodeBlocksButton setState:[prefsController useDarkCodeBlocks]];
	[foregroundColorWell setColor:[prefsController foregroundTextColor]];
	[backgroundColorWell setColor:[prefsController backgroundTextColor]];
    [maxWidthSlider setDoubleValue:[[NSUserDefaults standardUserDefaults] doubleForKey:@"NoteBodyMaxWidth"]];
	//for elasticthreads' hide dock icon option, check if OS compatible
	if (IsSnowLeopardOrLater) {
		[togDockButton setEnabled:YES];
		
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ShowDockIcon"]) {
            [togDockButton setTitle:@"Hide Dock Icon"];
//			[togDockLabel setStringValue:@"This will immediately restart NV"];		
		}else {
            [togDockButton setTitle:@"Show Dock Icon"];
//			[togDockLabel setStringValue:@""];
		}

	}else {	
		[togDockButton setEnabled:NO];
		[togDockButton setHidden:YES];
//		[togDockLabel setHidden:YES];
	}
    //for Brett's Markdownify/Readability import
	[useMarkdownImportButton setState:[prefsController useMarkdownImport]];
	[useReadabilityButton setState:[prefsController useReadability]];
	[useReadabilityButton setEnabled:[useMarkdownImportButton state]];
	
    [altRowsButton setState:[prefsController alternatingRows]];
    [showGridButton setState:[prefsController showGrid]];
    [autoPairButton setState:[prefsController useAutoPairing]];
    [useETScrollbarsOnLionButton setState:[prefsController useETScrollbarsOnLion]];
    [useETScrollbarsOnLionButton setHidden:!IsLionOrLater];
    [sidebarTable reloadData];
    [self selectPaneWithIdentifier:nil animate:NO];  //select last selected pane by default
}


#pragma mark NVN-15 sidebar settings shell

//rebuilds the General pane in code (the legacy xib pane is discarded at load).
//Controls are assigned to the same ivars the xib outlets used to fill, so the
//existing state-init and settings-callback code runs unchanged.
- (void)_buildGeneralPane {
	const CGFloat paneWidth = 368.0f;
	const CGFloat paneHeight = 310.0f;
	generalView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, paneWidth, paneHeight)];

	//list text size row
	NVAddLabel(generalView, NSLocalizedString(@"List Text Size:", nil),
			   NSMakeRect(20, paneHeight - 21 - 17, 148, 17), NSTextAlignmentRight, NO);
	tableTextMenuButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(171, paneHeight - 18 - 26, 95, 26) pullsDown:NO];
	[tableTextMenuButton addItemWithTitle:NSLocalizedString(@"Small", nil)];
	[[tableTextMenuButton lastItem] setTag:1];
	[tableTextMenuButton addItemWithTitle:NSLocalizedString(@"Large", nil)];
	[[tableTextMenuButton lastItem] setTag:2];
	[[tableTextMenuButton menu] addItem:[NSMenuItem separatorItem]];
	[tableTextMenuButton addItemWithTitle:NSLocalizedString(@"Other…", nil)];
	[[tableTextMenuButton lastItem] setTag:3];
	[tableTextMenuButton setTarget:self];
	[tableTextMenuButton setAction:@selector(changedTableText:)];
	[generalView addSubview:tableTextMenuButton];
	[tableTextMenuButton release];

	tableTextSizeField = [[NSTextField alloc] initWithFrame:NSMakeRect(272, paneHeight - 20 - 22, 61, 22)];
	[tableTextSizeField setBezeled:YES];
	[tableTextSizeField setEditable:YES];
	[[tableTextSizeField cell] setPlaceholderString:NSLocalizedString(@"Size", nil)];
	[generalView addSubview:tableTextSizeField];
	[tableTextSizeField release];

	//bring-to-front hotkey row
	NVAddLabel(generalView, NSLocalizedString(@"Bring-to-Front Hotkey:", nil),
			   NSMakeRect(8, paneHeight - 64 - 20, 161, 20), NSTextAlignmentRight, NO);
	appShortcutField = [[NSTextField alloc] initWithFrame:NSMakeRect(174, paneHeight - 63 - 22, 89, 22)];
	[appShortcutField setBezeled:YES];
	[appShortcutField setEditable:NO];
	[appShortcutField setSelectable:YES];
	[[appShortcutField cell] setPlaceholderString:NSLocalizedString(@"(None)", nil)];
	[generalView addSubview:appShortcutField];
	[appShortcutField release];
	NVAddPushButton(generalView, NSLocalizedString(@"Set…", nil), self, @selector(setAppShortcut:),
					NSMakeRect(265, paneHeight - 59 - 32, 73, 32));

	//behavior checkboxes
	completeNoteTitlesButton = NVAddCheckbox(generalView, NSLocalizedString(@"Auto-select notes by title when searching", nil),
											 self, @selector(changedTitleCompletion:), NSMakeRect(32, paneHeight - 99 - 18, 286, 18));
	NVAddLabel(generalView, NSLocalizedString(@"Automatically selecting very long notes may affect responsiveness.", nil),
			   NSMakeRect(49, paneHeight - 121 - 33, 286, 33), NSTextAlignmentLeft, YES);

	confirmDeletionButton = NVAddCheckbox(generalView, NSLocalizedString(@"Confirm note deletion", nil),
										  self, @selector(changedNoteDeletion:), NSMakeRect(32, paneHeight - 166 - 18, 242, 18));

	quitWhenClosingButton = NVAddCheckbox(generalView, NSLocalizedString(@"Quit when closing window", nil),
										  self, @selector(changedQuitBehavior:), NSMakeRect(32, paneHeight - 216 - 18, 223, 18));

	NSButton *menuBarIconButton = NVAddCheckbox(generalView, NSLocalizedString(@"Show menu bar icon", nil),
												self, @selector(toggleStatusItem:), NSMakeRect(32, paneHeight - 240 - 18, 269, 18));
	NSUserDefaultsController *defaultsController = [NSUserDefaultsController sharedUserDefaultsController];
	[menuBarIconButton bind:NSValueBinding toObject:defaultsController withKeyPath:@"values.StatusBarItem" options:nil];
	[menuBarIconButton bind:NSEnabledBinding toObject:defaultsController withKeyPath:@"values.ShowDockIcon"
					options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:NSNullPlaceholderBindingOption]];

	NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(0, paneHeight - 262 - 5, paneWidth, 5)];
	[separator setBoxType:NSBoxSeparator];
	[generalView addSubview:separator];
	[separator release];

	togDockButton = NVAddPushButton(generalView, @"Hide Dock Icon", self, @selector(toggleHideDockIcon:),
									NSMakeRect(34, paneHeight - 271 - 25, 121, 25));
	togDockLabel = NVAddLabel(generalView, NSLocalizedString(@"This will immediately restart nvNova", nil),
							  NSMakeRect(160, paneHeight - 276 - 14, 192, 14), NSTextAlignmentLeft, YES);
}

- (void)_buildSettingsWindow {
	paneIdentifiers = [[NSArray alloc] initWithObjects:@"General", @"Notes", @"Editing", @"Fonts & Colors", nil];
	navHistory = [[NSMutableArray alloc] init];
	navIndex = 0;

	//sidebar: a source-list table inside the sidebar split item, which supplies
	//the material and full-height appearance
	sidebarTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, kSidebarWidth, 300)];
	NSTableColumn *paneColumn = [[NSTableColumn alloc] initWithIdentifier:@"pane"];
	[paneColumn setEditable:NO];
	[sidebarTable addTableColumn:paneColumn];
	[paneColumn release];
	[sidebarTable setHeaderView:nil];
	[sidebarTable setStyle:NSTableViewStyleSourceList];
	[sidebarTable setRowHeight:26.0f];
	[sidebarTable setAllowsEmptySelection:NO];
	[sidebarTable setAllowsMultipleSelection:NO];
	[sidebarTable setDelegate:self];
	[sidebarTable setDataSource:self];

	NSScrollView *sidebarScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kSidebarWidth, 300)];
	[sidebarScroll setDocumentView:sidebarTable];
	[sidebarScroll setHasVerticalScroller:YES];
	[sidebarScroll setDrawsBackground:NO];
	[sidebarTable release];

	NSViewController *sidebarController = [[NSViewController alloc] init];
	[sidebarController setView:sidebarScroll];
	[sidebarScroll release];

	detailContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kDetailWidth, 400)];
	NSViewController *detailController = [[NSViewController alloc] init];
	[detailController setView:detailContainer];
	[detailContainer release];

	settingsSplitViewController = [[NSSplitViewController alloc] init];
	NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarController];
	[sidebarItem setMinimumThickness:kSidebarWidth];
	[sidebarItem setMaximumThickness:kSidebarWidth];
	[sidebarItem setCanCollapse:NO];
	[settingsSplitViewController addSplitViewItem:sidebarItem];
	[settingsSplitViewController addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:detailController]];
	[sidebarController release];
	[detailController release];

	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kSidebarWidth + 1 + kDetailWidth, 420)
										 styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
													NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView)
										   backing:NSBackingStoreBuffered defer:NO];
	[window setReleasedWhenClosed:NO];
	[window setContentViewController:settingsSplitViewController];
	[settingsSplitViewController release];	//the window's contentViewController retains it
	//setContentViewController: resizes the window to the split view's own fitting
	//size, so restore the intended dimensions afterward
	[window setContentSize:NSMakeSize(kSidebarWidth + 1 + kDetailWidth, 420)];

	[window setToolbarStyle:NSWindowToolbarStyleUnified];
	NSToolbar *settingsToolbar = [[NSToolbar alloc] initWithIdentifier:@"nvNovaSettingsToolbar"];
	[settingsToolbar setDelegate:self];
	[settingsToolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
	[settingsToolbar setAllowsUserCustomization:NO];
	[settingsToolbar setAutosavesConfiguration:NO];
	[window setToolbar:settingsToolbar];
	[settingsToolbar release];
	[window setShowsToolbarButton:NO];
	[window setDelegate:self];

	//keep the hosted pane pinned to the top of the detail area across window
	//resizes and safe-area (toolbar) changes; pane views use fixed frames
	[detailContainer setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_layoutCurrentPane)
												 name:NSViewFrameDidChangeNotification object:detailContainer];
}

- (NSView*)_paneViewForIdentifier:(NSString*)identifier {
	if ([identifier isEqualToString:@"General"]) return generalView;
	if ([identifier isEqualToString:@"Notes"]) return [self databaseView];
	if ([identifier isEqualToString:@"Editing"]) return editingView;
	if ([identifier isEqualToString:@"Fonts & Colors"]) return fontsColorsView;
	return nil;
}

- (void)_layoutCurrentPane {
	NSView *paneView = [[detailContainer subviews] count] ? [[detailContainer subviews] objectAtIndex:0] : nil;
	if (!paneView) return;
	NSRect bounds = [detailContainer bounds];
	NSRect paneFrame = [paneView frame];
	paneFrame.origin.x = floorf((NSWidth(bounds) - NSWidth(paneFrame)) / 2.0f);
	paneFrame.origin.y = NSHeight(bounds) - [detailContainer safeAreaInsets].top - kPaneMargin - NSHeight(paneFrame);
	[paneView setFrame:paneFrame];
}

- (void)selectPaneWithIdentifier:(NSString*)identifier animate:(BOOL)animate {
	if (!identifier) identifier = [prefsController lastSelectedPreferencesPane];
	if (!identifier || ![paneIdentifiers containsObject:identifier]) identifier = @"General";

	NSView *paneView = [self _paneViewForIdentifier:identifier];
	NSAssert(paneView != nil, @"switching to a nil prefs view!");

	if (paneView == databaseView)
		[folderLocationsMenuButton setMenu:[self directorySelectionMenu]];

	[prefsController setLastSelectedPreferencesPane:identifier sender:self];
	if (currentPaneIdentifier != identifier) {
		[currentPaneIdentifier autorelease];
		currentPaneIdentifier = [identifier retain];
	}

	if (!navigatingViaHistory) {
		if (navIndex + 1 < [navHistory count])
			[navHistory removeObjectsInRange:NSMakeRange(navIndex + 1, [navHistory count] - navIndex - 1)];
		if (![navHistory count] || ![[navHistory lastObject] isEqualToString:identifier])
			[navHistory addObject:identifier];
		navIndex = [navHistory count] - 1;
	}

	NSUInteger row = [paneIdentifiers indexOfObject:identifier];
	if ((NSInteger)row != [sidebarTable selectedRow])
		[sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];

	[[NSFontPanel sharedFontPanel] close];
	[window setTitle:[[NSBundle mainBundle] localizedStringForKey:identifier value:@"" table:nil]];

	while ([[detailContainer subviews] count])
		[[[detailContainer subviews] lastObject] removeFromSuperview];

	//fit the window height to the pane, System Settings-style, keeping the top edge fixed
	CGFloat contentHeight = [detailContainer safeAreaInsets].top + kPaneMargin + NSHeight([paneView frame]) + kPaneMargin;
	NSRect contentRect = [window contentRectForFrameRect:[window frame]];
	CGFloat delta = contentHeight - NSHeight(contentRect);
	if (delta != 0.0f) {
		NSRect newFrame = [window frame];
		newFrame.size.height += delta;
		newFrame.origin.y -= delta;
		[window setFrame:newFrame display:YES animate:animate];
	}

	[paneView setAutoresizingMask:NSViewNotSizable];
	[detailContainer addSubview:paneView];
	[self _layoutCurrentPane];
}

- (IBAction)navigateBack:(id)sender {
	if (!navIndex) return;
	navIndex--;
	navigatingViaHistory = YES;
	[self selectPaneWithIdentifier:[navHistory objectAtIndex:navIndex] animate:YES];
	navigatingViaHistory = NO;
}

- (IBAction)navigateForward:(id)sender {
	if (navIndex + 1 >= [navHistory count]) return;
	navIndex++;
	navigatingViaHistory = YES;
	[self selectPaneWithIdentifier:[navHistory objectAtIndex:navIndex] animate:YES];
	navigatingViaHistory = NO;
}

#pragma mark sidebar table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return [paneIdentifiers count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NSTableCellView *cellView = [tableView makeViewWithIdentifier:@"paneCell" owner:self];
	if (!cellView) {
		cellView = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, kSidebarWidth, 26)] autorelease];
		[cellView setIdentifier:@"paneCell"];

		NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(5, 5, 16, 16)];
		[cellView addSubview:iconView];
		[cellView setImageView:iconView];
		[iconView release];

		NSTextField *titleField = [[NSTextField alloc] initWithFrame:NSMakeRect(28, 4, kSidebarWidth - 34, 18)];
		[titleField setEditable:NO];
		[titleField setSelectable:NO];
		[titleField setBezeled:NO];
		[titleField setDrawsBackground:NO];
		[titleField setFont:[NSFont systemFontOfSize:13.0f]];
		[[titleField cell] setLineBreakMode:NSLineBreakByTruncatingTail];
		[titleField setAutoresizingMask:NSViewWidthSizable];
		[cellView addSubview:titleField];
		[cellView setTextField:titleField];
		[titleField release];
	}
	NSString *identifier = [paneIdentifiers objectAtIndex:row];
	[[cellView imageView] setImage:[NSImage imageWithSystemSymbolName:NVSymbolNameForPane(identifier) accessibilityDescription:nil]];
	[[cellView textField] setStringValue:[[NSBundle mainBundle] localizedStringForKey:identifier value:@"" table:nil]];
	return cellView;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
	NSInteger row = [sidebarTable selectedRow];
	if (row < 0 || row >= (NSInteger)[paneIdentifiers count]) return;
	NSString *identifier = [paneIdentifiers objectAtIndex:row];
	if ([identifier isEqualToString:currentPaneIdentifier]) return;
	[self selectPaneWithIdentifier:identifier animate:YES];
}

#pragma mark settings toolbar

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)theToolbar {
	return [NSArray arrayWithObjects:kSidebarSeparatorItemIdentifier, kNavBackItemIdentifier,
			kNavForwardItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier, nil];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)theToolbar {
	return [self toolbarDefaultItemIdentifiers:theToolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)aToolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
	if ([itemIdentifier isEqualToString:kSidebarSeparatorItemIdentifier]) {
		return [NSTrackingSeparatorToolbarItem trackingSeparatorToolbarItemWithIdentifier:itemIdentifier
																				splitView:[settingsSplitViewController splitView]
																			 dividerIndex:0];
	}
	BOOL isBack = [itemIdentifier isEqualToString:kNavBackItemIdentifier];
	if (isBack || [itemIdentifier isEqualToString:kNavForwardItemIdentifier]) {
		NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];
		NSString *label = isBack ? NSLocalizedString(@"Back", nil) : NSLocalizedString(@"Forward", nil);
		[item setNavigational:YES];
		[item setBordered:YES];
		[item setLabel:label];
		[item setPaletteLabel:label];
		[item setImage:[NSImage imageWithSystemSymbolName:isBack ? @"chevron.backward" : @"chevron.forward"
								 accessibilityDescription:label]];
		[item setTarget:self];
		[item setAction:isBack ? @selector(navigateBack:) : @selector(navigateForward:)];
		return item;
	}
	return nil;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem {
	if ([[theItem itemIdentifier] isEqualToString:kNavBackItemIdentifier])
		return navIndex > 0;
	if ([[theItem itemIdentifier] isEqualToString:kNavForwardItemIdentifier])
		return navIndex + 1 < [navHistory count];
	return YES;
}

//elasticwork

- (IBAction)toggleHideDockIcon:(id)sender{
    NSUserDefaults *stdDefaults=[NSUserDefaults standardUserDefaults];
    BOOL showIt=![stdDefaults boolForKey:@"ShowDockIcon"];
    if (showIt) {
        [stdDefaults setBool:YES forKey:@"ShowDockIcon"];
        [togDockButton setTitle:@"Hide Dock Icon"];        
//        [togDockLabel setStringValue:@"This will immediately restart NV"];	
    }else{
        [stdDefaults setBool:YES forKey:@"StatusBarItem"];
        [stdDefaults setBool:NO forKey:@"ShowDockIcon"];
        [togDockButton setTitle:@"Show Dock Icon"];
    }
    [stdDefaults synchronize];
	[[NSNotificationCenter defaultCenter]postNotificationName:@"AppShouldToggleDockIcon" object:[NSNumber numberWithBool:showIt]];
}

- (IBAction)toggleStatusItem:(id)sender{
//    NSUserDefaults *stdDefaults=[NSUserDefaults standardUserDefaults];
//    BOOL showIt=[stdDefaults boolForKey:@"StatusBarItem"];
//    if (showIt) {
//        [stdDefaults setBool:NO forKey:@"StatusBarItem"];
//        //        [togDockLabel setStringValue:@"This will immediately restart NV"];
//    }else{
//        [stdDefaults setBool:YES forKey:@"StatusBarItem"];
//    }
//    [stdDefaults synchronize];
	[[NSNotificationCenter defaultCenter]postNotificationName:@"AppShouldToggleStatusItem" object:nil];
}


- (IBAction)toggleKeepsTextWidthInWindow:(id)sender{
   
    [prefsController setManagesTextWidthInWindow:[sender state] sender:self];
//		[[NSApp delegate] setMaxNoteBodyWidth];
}

- (IBAction)setMaxWidth:(id)sender{
	CGFloat dbWidth = [maxWidthSlider floatValue];	
	dbWidth = dbWidth - fmod(dbWidth,2.0);
	[prefsController setMaxNoteBodyWidth:dbWidth sender:self];
//	[[NSApp delegate] setMaxNoteBodyWidth];
}

- (IBAction)changedUseMarkdownImport:(id)sender {
	[prefsController setUseMarkdownImport:[useMarkdownImportButton state] sender:self];
	[useReadabilityButton setEnabled:[useMarkdownImportButton state]];
}

- (IBAction)changedUseReadability:(id)sender {
	[prefsController setUseReadability:[useReadabilityButton state] sender:self];
}

- (IBAction)changedAltRows:(id)sender {
	[prefsController setAlternatingRows:[altRowsButton state] sender:self];
    [[NSApp delegate] refreshNotesList];
}

- (IBAction)changedAutoPairing:(id)sender{
	[prefsController setUseAutoPairing:[autoPairButton state]];
    //  [[NSApp delegate] refreshNotesList];
}

- (IBAction)changedShowGrid:(id)sender {
	[prefsController setShowGrid:[showGridButton state] sender:self];
    [[NSApp delegate] refreshNotesList];
}

@end
