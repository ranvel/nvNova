//
//  NotationFileManager.h
//  Notation
//
//  Created by Zachary Schneirov on 4/9/06.

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


#import <Cocoa/Cocoa.h>
#import "NotationController.h"
#import "BufferUtils.h"

extern NSString *NotesDatabaseFileName;

typedef union VolumeUUID {
	u_int32_t value[2];
	struct {
		u_int32_t high;
		u_int32_t low;
	} v;
} VolumeUUID;


@interface NotationController (NotationFileManager)

OSStatus CreateDirectoryIfNotPresent(FSRef *parentRef, CFStringRef subDirectoryName, FSRef *childRef);
CFUUIDRef CopyHFSVolumeUUIDForMount(const char *mntonname);
long BlockSizeForNotation(NotationController *controller);
NSUInteger diskUUIDIndexForNotation(NotationController *controller);

- (void)purgeOldPerDiskInfoFromNotes;
- (void)initializeDiskUUIDIfNecessary;

- (BOOL)notesDirectoryIsTrashed;

- (NSURL*)notesDirectoryURL;
- (NSURL*)notesDirectoryFileURLForFilename:(NSString*)filename;
- (BOOL)notesDirectoryContainsFile:(NSString*)filename;

- (OSStatus)renameAndForgetNoteDatabaseFile:(NSString*)newfilename;
- (BOOL)removeSpuriousDatabaseFileNotes;

- (void)relocateNotesDirectory;

+ (OSStatus)getDefaultNotesDirectoryRef:(FSRef*)notesDir;

- (NSMutableData*)dataFromFileInNotesDirectory:(NSString*)filename;
- (NSMutableData*)dataFromFileInNotesDirectoryForCatalogEntry:(NoteCatalogEntry*)catEntry;
- (OSStatus)noteFileRenamedFromName:(NSString*)oldName toName:(NSString*)newName;
- (NSString*)uniqueFilenameForTitle:(NSString*)title fromNote:(NoteObject*)note;
- (OSStatus)fileInNotesDirectory:(NSString*)filename isOwnedByUs:(BOOL*)owned hasCatalogInfo:(FSCatalogInfo *)info;
- (OSStatus)deleteFileInNotesDirectory:(NSString*)filename;
- (OSStatus)createFileIfNotPresentInNotesDirectory:(NSString*)filename fileWasCreated:(BOOL*)created;
- (OSStatus)storeDataAtomicallyInNotesDirectory:(NSData*)data withName:(NSString*)filename;
- (OSStatus)storeDataAtomicallyInNotesDirectory:(NSData*)data withName:(NSString*)filename
							 verifyWithSelector:(SEL)verifySel verificationDelegate:(id)verifyDelegate;
- (OSStatus)moveFileToTrashForFilename:(NSString*)filename;
+ (OSStatus)trashFolderRef:(FSRef*)trashRef forChild:(FSRef*)childRef;
- (void)notifyOfChangedTrash;
@end

@interface NSObject (NotationFileManagerDelegate)
- (NSNumber*)verifyDataAtTemporaryURL:(NSURL*)tempURL withFinalName:(NSString*)filename;
@end
