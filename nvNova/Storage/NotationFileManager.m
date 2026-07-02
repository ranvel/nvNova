//
//  NotationFileManager.m
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


#import "NotationFileManager.h"
#import "NotationPrefs.h"
#import "NSString_NV.h"
#import "NSFileManager_NV.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "NSData_transformations.h"
#include <sys/param.h>
#include <sys/mount.h>

#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>

NSString *NotesDatabaseFileName = @"Notes & Settings";

@implementation NotationController (NotationFileManager)

static struct statfs *StatFSVolumeInfo(NotationController *controller);

/*
 Read the UUID from a mounted volume, by calling getattrlist().
 Assumes the path is the mount point of an HFS volume.
 */
static BOOL GetVolumeUUIDAttr(const char *path, VolumeUUID *volumeUUIDPtr) {
	struct attrlist alist;
	struct FinderAttrBuf {
		u_int32_t info_length;
		u_int32_t finderinfo[8];
	} volFinderInfo;
	
	int result = -1;
	
	/* Set up the attrlist structure to get the volume's Finder Info */
	alist.bitmapcount = 5;
	alist.reserved = 0;
	alist.commonattr = ATTR_CMN_FNDRINFO;
	alist.volattr = ATTR_VOL_INFO;
	alist.dirattr = 0;
	alist.fileattr = 0;
	alist.forkattr = 0;
	
	/* Get the Finder Info */
	if ((result = getattrlist(path, &alist, &volFinderInfo, sizeof(volFinderInfo), 0))) {
		NSLog(@"GetVolumeUUIDAttr error: %d", result);
		return NO;
	}
	
	/* Copy the UUID from the Finder Into to caller's buffer */
	VolumeUUID *finderInfoUUIDPtr = (VolumeUUID *)(&volFinderInfo.finderinfo[6]);
	volumeUUIDPtr->v.high = CFSwapInt32BigToHost(finderInfoUUIDPtr->v.high);
	volumeUUIDPtr->v.low = CFSwapInt32BigToHost(finderInfoUUIDPtr->v.low);
	
	return YES;
}


// Create a version 3 UUID; derived using "name" via MD5 checksum.
static void uuid_create_md5_from_name(unsigned char result_uuid[16], const void *name, int namelen) {
	
	static unsigned char FSUUIDNamespaceSHA1[16] = { 
		0xB3, 0xE2, 0x0F, 0x39, 0xF2, 0x92, 0x11, 0xD6, 
		0x97, 0xA4, 0x00, 0x30, 0x65, 0x43, 0xEC, 0xAC
	};
	
    CC_MD5_CTX c;

	//MD5 here is UUID-v3-style name derivation, not a security boundary
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5_Init(&c);
    CC_MD5_Update(&c, FSUUIDNamespaceSHA1, sizeof(FSUUIDNamespaceSHA1));
    CC_MD5_Update(&c, name, namelen);
    CC_MD5_Final(result_uuid, &c);
#pragma clang diagnostic pop
	
    result_uuid[6] = (result_uuid[6] & 0x0F) | 0x30;
    result_uuid[8] = (result_uuid[8] & 0x3F) | 0x80;
}


CFUUIDRef CopyHFSVolumeUUIDForMount(const char *mntonname) {
	VolumeUUID targetVolumeUUID;
	
	unsigned char rawUUID[8];
	
	if (!GetVolumeUUIDAttr(mntonname, &targetVolumeUUID))
		return NULL;
	
	((uint32_t *)rawUUID)[0] = CFSwapInt32HostToBig(targetVolumeUUID.v.high);
	((uint32_t *)rawUUID)[1] = CFSwapInt32HostToBig(targetVolumeUUID.v.low);
	
	CFUUIDBytes uuidBytes;
	uuid_create_md5_from_name((void*)&uuidBytes, rawUUID, sizeof(rawUUID));
	
	return CFUUIDCreateFromUUIDBytes(NULL, uuidBytes);
}

//NVN-5: synthesize a stable per-volume UUID from the volume's creation date via NSURL resource keys
//(was Carbon FSGetCatalogInfo + FSGetVolumeInfo over a UTCDateTime). This is the last-resort fallback
//when neither the HFS volume UUID nor the FSEvents device UUID is available; a given volume still maps
//to a stable UUID, though it differs from the pre-NVN-5 Carbon value (a synthetic-fallback disk re-reads
//its per-disk attr times once after upgrade — see recon §2.7).
static CFUUIDRef CopySyntheticUUIDForVolumeURL(NSURL *dirURL) {
	if (!dirURL) return NULL;

	NSURL *volURL = nil;
	if (![dirURL getResourceValue:&volURL forKey:NSURLVolumeURLKey error:NULL] || !volURL)
		volURL = dirURL;

	NSDate *created = nil;
	if (![volURL getResourceValue:&created forKey:NSURLVolumeCreationDateKey error:NULL] || !created) {
		NSLog(@"can't get the volume creation date for %@", [dirURL path]);
		return NULL;
	}

	CFAbsoluteTime createAbs = [created timeIntervalSinceReferenceDate];
	CFUUIDBytes uuidBytes;
	uuid_create_md5_from_name((void*)&uuidBytes, (void*)&createAbs, sizeof(createAbs));
	return CFUUIDCreateFromUUIDBytes(NULL, uuidBytes);
}

- (void)purgeOldPerDiskInfoFromNotes {
	//here's where notes' PerDiskInfo arrays would have older times removed, depending on -[DiskUUIDEntry lastAccessed]
	//each note will use RemovePerDiskInfoWithTableIndex
}

- (void)initializeDiskUUIDIfNecessary {
	//create a CFUUIDRef that identifies the volume this database sits on
	
	//don't bother unless we will be reading notes as separate files; otherwise there's no need to track the source of the attr mod dates
	//maybe disk UUIDs will be used in the future for something else; at that point this check should be altered
	
	if (!diskUUID && [self currentNoteStorageFormat] != SingleDatabaseFormat) {
		
		struct statfs * sfsb = StatFSVolumeInfo(self);
		//if this is not an hfs+ disk, then get the FSEvents UUID
		//if this is not Leopard or the FSEvents UUID is null, 
		//then take MD5 sum of creation date + some other info?

		if (!strcmp(sfsb->f_fstypename, "hfs")) {
			//if this is an HFS volume, then use getattrlist to get finderinfo from the volume
			diskUUID = CopyHFSVolumeUUIDForMount(sfsb->f_mntonname);
		}

		//ah but what happens when a non-hfs disk is first mounted on leopard+, and then moves to a tiger machine?
		//or vise-versa; that calls for tracking how the UUIDs were generated, and grouping them together when others are found;
		//this is probably unnecessary for now
		if (!diskUUID && IsLeopardOrLater) {
			//this is not an hfs disk, and this computer is new enough to have FSEvents	
			diskUUID = FSEventsCopyUUIDForDevice(sfsb->f_fsid.val[0]);
		}
		
		if (!diskUUID) {
			//all other checks failed; just use the volume's creation date
			diskUUID = CopySyntheticUUIDForVolumeURL([self notesDirectoryURL]);
		}
		diskUUIDIndex = [notationPrefs tableIndexOfDiskUUID:diskUUID];
	}
}

static struct statfs *StatFSVolumeInfo(NotationController *controller) {
	if (!controller->statfsInfo) {
		//NVN-5: derive the C path from the stored notes-directory path (was FSRefMakePath on the FSRef);
		//the statfs() filesystem-acceptability logic itself is NVN-12's concern, untouched here.
		const char *path = [controller->notesDirectoryPath fileSystemRepresentation];
		if (path) {
			controller->statfsInfo = calloc(1, sizeof(struct statfs));

			if (statfs(path, controller->statfsInfo))
				NSLog(@"statfs: error %d\n", errno);
		} else
			NSLog(@"StatFSVolumeInfo: no notes directory path");
	}
	return controller->statfsInfo;
}

NSUInteger diskUUIDIndexForNotation(NotationController *controller) {
	return controller->diskUUIDIndex;
}

long BlockSizeForNotation(NotationController *controller) {
    if (!controller->blockSize) {
		long iosize = 0;

		struct statfs * sfsb = StatFSVolumeInfo(controller);
		if (sfsb) iosize = sfsb->f_iosize;
		
		controller->blockSize = MAX(iosize, 16 * 1024);
    }
    
    return controller->blockSize;
}

//the notes directory as a file-URL, derived from the live directory FSRef (which stays NVN-2's bridge seam).
//every file-I/O primitive below works in URL-land relative to this; the single FSRef->URL conversion lives here.
- (NSURL*)notesDirectoryURL {
	NSString *dirPath = [self notesDirectoryPath];
	return dirPath ? [NSURL fileURLWithPath:dirPath isDirectory:YES] : nil;
}

- (NSURL*)notesDirectoryFileURLForFilename:(NSString*)filename {
	if (![filename length]) return nil;
	NSURL *dirURL = [self notesDirectoryURL];
	return dirURL ? [dirURL URLByAppendingPathComponent:filename] : nil;
}


- (BOOL)notesDirectoryIsTrashed {
	//NVN-5: replacement for Carbon FSDetermineIfRefIsEnclosedByFolder(kTrashFolderType). There is no
	//public NSURL "is in trash" resource key on this SDK, so detect the trash by path component: a
	//trashed item lives under the home Trash (~/.Trash) or a volume's per-user trash (/Volumes/X/.Trashes/<uid>).
	NSString *path = [self notesDirectoryPath];
	if (![path length]) return NO;

	for (NSString *component in [path pathComponents]) {
		if ([component isEqualToString:@".Trash"] || [component isEqualToString:@".Trashes"])
			return YES;
	}
	return NO;
}

- (BOOL)notesDirectoryContainsFile:(NSString*)filename {
	NSURL *fileURL = [self notesDirectoryFileURLForFilename:filename];
	return fileURL && [[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]];
}

- (OSStatus)renameAndForgetNoteDatabaseFile:(NSString*)newfilename {
	//used when upgrading an incompatible database: move the current DB file aside under a new name
	NSURL *dbURL = [self notesDirectoryFileURLForFilename:NotesDatabaseFileName];
	NSURL *newURL = [self notesDirectoryFileURLForFilename:newfilename];
	if (!dbURL || !newURL) return fnfErr;

	NSError *error = nil;
	if (![[NSFileManager defaultManager] moveItemAtURL:dbURL toURL:newURL error:&error]) {
		NSLog(@"Error renaming notes database file to %@: %@", newfilename, error);
		return error ? (OSStatus)[error code] : kFileStorageErr;
    }
	return noErr;
}

- (BOOL)removeSpuriousDatabaseFileNotes {
	//remove any notes that might have been made out of the database or write-ahead-log files by accident
	//but leave the files intact; ensure only that they are also remotely unsynced
	//returns true if at least one note was removed, in which case allNotes should probably be refiltered
	
	NSUInteger i = 0;
	NoteObject *dbNote = nil, *walNote = nil;
	
	for (i=0; i<[allNotes count]; i++) {
		NoteObject *obj = [allNotes objectAtIndex:i];
		
		if (!dbNote && [filenameOfNote(obj) isEqualToString:NotesDatabaseFileName])
			dbNote = [[obj retain] autorelease];
		if (!walNote && [filenameOfNote(obj) isEqualToString:@"Interim Note-Changes"])
			walNote = [[obj retain] autorelease];
	}
	if (dbNote) {
		[allNotes removeObjectIdenticalTo:dbNote];
		[self _addDeletedNote:dbNote];
	}
	if (walNote) {
		[allNotes removeObjectIdenticalTo:walNote];
		[self _addDeletedNote:walNote];
	}
	return walNote || dbNote;
}

- (void)relocateNotesDirectory {
	
	while (1) {
		NSOpenPanel *openPanel = [NSOpenPanel openPanel];
		[openPanel setCanCreateDirectories:YES];
		[openPanel setCanChooseFiles:NO];
		[openPanel setCanChooseDirectories:YES];
		[openPanel setResolvesAliases:YES];
		[openPanel setAllowsMultipleSelection:NO];
		[openPanel setTreatsFilePackagesAsDirectories:NO];
		[openPanel setTitle:NSLocalizedString(@"Select a folder",nil)];
		[openPanel setPrompt:NSLocalizedString(@"Select",nil)];
		[openPanel setMessage:NSLocalizedString(@"Select a new location for your Notational Velocity notes.",nil)];
		
		if ([openPanel runModal] == NSOKButton) {
            
			NSURL *destParentURL = [openPanel URL];
			if (destParentURL) {

				//NVN-5: NSFileManager move replaces the Carbon FSMoveObject/FSCompareFSRefs dance.
				//the notes directory is moved into the chosen parent folder, keeping its name.
				NSString *srcPath = [self notesDirectoryPath];
				NSURL *srcURL = [NSURL fileURLWithPath:srcPath isDirectory:YES];
				NSURL *destURL = [destParentURL URLByAppendingPathComponent:[srcURL lastPathComponent] isDirectory:YES];

				if ([[destURL path] isEqualToString:srcPath]) {
					//chose the notes directory's current location; nothing to move
					[[NSWorkspace sharedWorkspace] selectFile:srcPath inFileViewerRootedAtPath:nil];
					break;
				}

				NSError *moveErr = nil;
				if (![[NSFileManager defaultManager] moveItemAtURL:srcURL toURL:destURL error:&moveErr]) {
					NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Couldn't move notes into the chosen folder because %@",nil),
						[moveErr localizedDescription]], NSLocalizedString(@"Your notes were not moved.",nil), NSLocalizedString(@"OK",nil), NULL, NULL);
					continue;
				}

				if ([destURL path]) [[GlobalPrefs defaultPrefs] setNotesDirectoryPath:[destURL path] sender:self];
				//we must quit now, as notes will very likely be re-initialized in the same place
				goto terminate;
			} else {
				goto terminate;
			}
		} else {
terminate:
			[NSApp terminate:nil];
			break;
		}
	}
}

+ (OSStatus)getDefaultNotesDirectoryPath:(NSString**)outPath {
	//NVN-5: ~/Library/Application Support/Notational Data via NSFileManager
	//(was Carbon FSFindFolder(kApplicationSupportFolderType) + FSCreateDirectoryUnicode)
	if (outPath) *outPath = nil;

	NSFileManager *fileMan = [NSFileManager defaultManager];
	NSURL *appSupportURL = [[fileMan URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
	if (!appSupportURL) {
		NSLog(@"Unable to locate an Application Support directory");
		return fnfErr;
	}

	NSURL *notesURL = [appSupportURL URLByAppendingPathComponent:@"Notational Data" isDirectory:YES];
	NSError *error = nil;
	if (![fileMan createDirectoryAtURL:notesURL withIntermediateDirectories:YES attributes:nil error:&error]) {
		NSLog(@"Unable to create the Notational Data directory: %@", error);
		return error ? (OSStatus)[error code] : kFileStorageErr;
	}

	if (outPath) *outPath = [notesURL path];
	return noErr;
}

//whenever a note uses this method to change its filename, we will have to re-establish all the links to it
- (NSString*)uniqueFilenameForTitle:(NSString*)title fromNote:(NoteObject*)note {
    //generate a unique filename based on title, varying numbers
    BOOL isUnique = YES;
    NSString *uniqueFilename = title;
	
	//remove illegal characters
	NSMutableString *sanitizedName = [[[uniqueFilename stringByReplacingOccurrencesOfString:@":" withString:@"-"] mutableCopy] autorelease];
	if ([sanitizedName characterAtIndex:0] == (unichar)'.')	[sanitizedName replaceCharactersInRange:NSMakeRange(0, 1) withString:@"_"];
	uniqueFilename = [[sanitizedName copy] autorelease];
	
	//use the note's current format if the current default format is for a database; get the "ideal" extension for that format
	NSInteger noteFormat = [notationPrefs notesStorageFormat] || !note ? [notationPrefs notesStorageFormat] : storageFormatOfNote(note);
	NSString *extension = [notationPrefs chosenPathExtensionForFormat:noteFormat];
	
	//if the note's current extension is compatible with the storage format above, then use the existing extension instead
	if (note && filenameOfNote(note) && [notationPrefs pathExtensionAllowed:[filenameOfNote(note) pathExtension] forFormat:noteFormat])
		extension = [filenameOfNote(note) pathExtension];
	
	//assume that we won't have more than 999 notes with the exact same name and of more than 247 chars
	uniqueFilename = [uniqueFilename filenameExpectingAdditionalCharCount:3 + [extension length] + 2];
	
    unsigned int iteration = 0;
    do {
		isUnique = YES;
		unsigned int i;
		
		//this ought to just use an nsset, but then we'd have to maintain a parallel data structure for marginal benefit
		//also, it won't quite work right for filenames with no (real) extensions and periods in their names
		for (i=0; i<[allNotes count]; i++) {
			NoteObject *aNote = [allNotes objectAtIndex:i];
			NSString *basefilename = [filenameOfNote(aNote) stringByDeletingPathExtension];
			
			if (note != aNote && [basefilename caseInsensitiveCompare:uniqueFilename] == NSOrderedSame) {
				isUnique = NO;
				
				uniqueFilename = [uniqueFilename stringByDeletingPathExtension];
				NSString *numberPath = [[NSNumber numberWithInt:++iteration] stringValue];
				uniqueFilename = [uniqueFilename stringByAppendingPathExtension:numberPath];
				break;
			}
		}
    } while (!isUnique);
	
    return [uniqueFilename stringByAppendingPathExtension:extension];
}

- (OSStatus)noteFileRenamedFromName:(NSString*)oldName toName:(NSString*)newName {
    if (![self currentNoteStorageFormat])
		return noErr;

	NSURL *oldURL = [self notesDirectoryFileURLForFilename:oldName];
	NSURL *newURL = [self notesDirectoryFileURLForFilename:newName];
	if (!oldURL || !newURL) return fnfErr;

	//mirrors the old FSRenameUnicode contract: a missing source file is a failure (the caller reverts the in-memory name)
	NSError *error = nil;
	if (![[NSFileManager defaultManager] moveItemAtURL:oldURL toURL:newURL error:&error]) {
		NSLog(@"Error renaming file %@ to %@: %@", oldName, newName, error);
		return error ? (OSStatus)[error code] : kFileStorageErr;
    }

    return noErr;
}

//NVN-5: an unset resource date maps to 0.0; NSDate's reference-date interval IS a CFAbsoluteTime,
//so this is a plain read with no Carbon conversion (the old UTCDateTimeFromNSDate/UCConvert shim is gone).
static inline CFAbsoluteTime AbsTimeFromResourceDate(NSDate *date) {
	return date ? (CFAbsoluteTime)[date timeIntervalSinceReferenceDate] : 0.0;
}

- (OSStatus)fileInNotesDirectory:(NSString*)filename isOwnedByUs:(BOOL*)owned hasCatalogInfo:(NoteFileInfo *)info {
	if (owned) *owned = NO;
	if (info) bzero(info, sizeof(NoteFileInfo));

	NSURL *fileURL = [self notesDirectoryFileURLForFilename:filename];
	if (!fileURL) return fnfErr;

	NSFileManager *fileMan = [NSFileManager defaultManager];
	BOOL exists = [fileMan fileExistsAtPath:[fileURL path]];
	//ownership: by construction the URL resolves inside the notes directory, so "owned" reduces to "actually present"
	//(createFileIfNotPresentInNotesDirectory: works by name; a missing file here means it was moved out from under us)
	if (owned) *owned = exists;
	if (!exists) return fnfErr;

	if (info) {
		NSDate *contentMod = nil, *attrMod = nil, *created = nil;
		NSNumber *fileSize = nil;
		[fileURL getResourceValue:&contentMod forKey:NSURLContentModificationDateKey error:NULL];
		[fileURL getResourceValue:&attrMod forKey:NSURLAttributeModificationDateKey error:NULL];
		[fileURL getResourceValue:&created forKey:NSURLCreationDateKey error:NULL];
		[fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:NULL];

		info->contentModDate = AbsTimeFromResourceDate(contentMod);
		info->attributeModDate = AbsTimeFromResourceDate(attrMod);
		info->createDate = AbsTimeFromResourceDate(created);
		info->dataLogicalSize = (UInt64)[fileSize unsignedLongLongValue];

		//inode/CNID has no direct NSURL resource key; NSFileSystemFileNumber is the inode used for note<->file matching
		NSDictionary *attrs = [fileMan attributesOfItemAtPath:[fileURL path] error:NULL];
		info->nodeID = (UInt32)[[attrs objectForKey:NSFileSystemFileNumber] unsignedLongLongValue];
	}

	return noErr;
}

- (OSStatus)deleteFileInNotesDirectory:(NSString*)filename {
	NSURL *fileURL = [self notesDirectoryFileURLForFilename:filename];
	if (!fileURL) return fnfErr;

	NSError *error = nil;
	if (![[NSFileManager defaultManager] removeItemAtURL:fileURL error:&error]) {
		//preserve the fnfErr signal: -removeFileFromDirectory falls back to trashing only on errors OTHER than not-found
		if ([[error domain] isEqualToString:NSCocoaErrorDomain] && [error code] == NSFileNoSuchFileError)
			return fnfErr;
		NSLog(@"Error deleting file %@: %@", filename, error);
		return error ? (OSStatus)[error code] : kFileStorageErr;
	}

    return noErr;
}

- (NSMutableData*)dataFromFileInNotesDirectory:(NSString*)filename {
	NSURL *fileURL = [self notesDirectoryFileURLForFilename:filename];
	if (!fileURL) return nil;

	//+[NSMutableData dataWithContentsOfURL:...] returns a mutable instance (callers mutate it in place: decryption, -updateFromData:)
	NSError *error = nil;
	NSMutableData *data = [NSMutableData dataWithContentsOfURL:fileURL options:0 error:&error];
	if (!data) {
		NSLog(@"%@: error reading %@: %@", NSStringFromSelector(_cmd), filename, error);
		return nil;
	}
	return data;
}

- (NSMutableData*)dataFromFileInNotesDirectoryForCatalogEntry:(NoteCatalogEntry*)catEntry {
    return [self dataFromFileInNotesDirectory:(NSString*)catEntry->filename];
}

- (OSStatus)createFileIfNotPresentInNotesDirectory:(NSString*)filename fileWasCreated:(BOOL*)created {
	if (created) *created = NO;
	NSURL *fileURL = [self notesDirectoryFileURLForFilename:filename];
	if (!fileURL) return fnfErr;

	NSFileManager *fileMan = [NSFileManager defaultManager];
	if ([fileMan fileExistsAtPath:[fileURL path]])
		return noErr;

	//createFileAtPath: would TRUNCATE an existing file, so the existence guard above is load-bearing, not just an optimization
	if (![fileMan createFileAtPath:[fileURL path] contents:[NSData data] attributes:nil]) {
		NSLog(@"Error creating file %@", filename);
		return kFileStorageErr;
	}
	if (created) *created = YES;
	return noErr;
}

- (OSStatus)storeDataAtomicallyInNotesDirectory:(NSData*)data withName:(NSString*)filename {
	return [self storeDataAtomicallyInNotesDirectory:data withName:filename verifyWithSelector:NULL verificationDelegate:nil];
}

//The headline of NVN-3: replaces the hand-rolled FSExchangeObjectsEmulate swap (which ran on 100% of saves
//because APFS lacks exchangedata(2)) with -[NSFileManager replaceItemAtURL:...], the documented replacefile(2)
//successor to FSExchangeObjects. Chosen over plain NSDataWritingAtomic because it preserves the destination's
//mode/ACL/xattrs (the whole DB blob is rewritten on every save under SingleDatabaseFormat). The replacement temp
//lives in NSItemReplacementDirectory on the same volume so the swap stays intra-volume and atomic.
//Crash-safety contract preserved: the destination ends up either old-good or new-good, never empty.

- (OSStatus)storeDataAtomicallyInNotesDirectory:(NSData*)data withName:(NSString*)filename
							 verifyWithSelector:(SEL)verificationSel verificationDelegate:(id)verifyDelegate {
	NSFileManager *fileMan = [NSFileManager defaultManager];
	NSURL *notesDirURL = [self notesDirectoryURL];
	NSURL *destURL = [self notesDirectoryFileURLForFilename:filename];
	if (!notesDirURL || !destURL) return fnfErr;

	NSError *error = nil;

	//obtain a temporary directory on the same volume as the notes directory (keeps the later replace/move intra-volume)
	NSURL *tempDirURL = [fileMan URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask
							   appropriateForURL:notesDirURL create:YES error:&error];
	if (!tempDirURL) {
		NSLog(@"error creating temporary directory for %@: %@", filename, error);
		return error ? (OSStatus)[error code] : kFileStorageErr;
	}
	NSURL *tempURL = [tempDirURL URLByAppendingPathComponent:filename];

	//write the new contents into the temp file
	if (![data writeToURL:tempURL options:0 error:&error]) {
		NSLog(@"error writing to temporary file for %@: %@", filename, error);
		[fileMan removeItemAtURL:tempDirURL error:NULL];
		return error ? (OSStatus)[error code] : kFileStorageErr;
	}

	//before swapping the temp into place, give the delegate a chance to read it back and confirm it decrypts/decodes
	if (verifyDelegate && verificationSel) {
		OSStatus verr = (OSStatus)[[verifyDelegate performSelector:verificationSel withObject:tempURL withObject:filename] intValue];
		if (noErr != verr) {
			NSLog(@"couldn't verify written notes, so not continuing to save");
			[fileMan removeItemAtURL:tempDirURL error:NULL];
			return verr;
		}
	}

	if ([fileMan fileExistsAtPath:[destURL path]]) {
		//atomic, metadata-preserving swap of an existing destination
		NSURL *resultingURL = nil;
		if (![fileMan replaceItemAtURL:destURL withItemAtURL:tempURL backupItemName:nil
							   options:0 resultingItemURL:&resultingURL error:&error]) {
			NSLog(@"error replacing destination file %@: %@", filename, error);
			[fileMan removeItemAtURL:tempDirURL error:NULL];
			return error ? (OSStatus)[error code] : kFileStorageErr;
		}
	} else {
		//destination doesn't exist yet (first save / new note): an intra-volume move is itself atomic
		if (![fileMan moveItemAtURL:tempURL toURL:destURL error:&error]) {
			NSLog(@"error moving temporary file into place for %@: %@", filename, error);
			[fileMan removeItemAtURL:tempDirURL error:NULL];
			return error ? (OSStatus)[error code] : kFileStorageErr;
		}
	}

	//clean up the (now-empty, or replace-consumed) temporary directory; cosmetic, so don't fail the save on it
	[fileMan removeItemAtURL:tempDirURL error:NULL];

	return noErr;
}


- (void)notifyOfChangedTrash {
	//NVN-5: dropped the Carbon half (trashFolderRef → FSFindFolder/FSGetCatalogInfo + FNNotify on the
	//trash folder) that consumed the FSRef substrate. The NSWorkspace recycle below already nudges the
	//Finder to refresh its Trash; -moveFileToTrashForFilename: (NVN-4) drives the actual trashing.
	NSString *sillyDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[(NSString*)CreateRandomizedFileName() autorelease]];

    [[NSFileManager defaultManager]createFolderAtPath:sillyDirectory];
	 NSInteger tag = 0;
	 [[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:NSTemporaryDirectory() destination:@""
												   files:[NSArray arrayWithObject:[sillyDirectory lastPathComponent]] tag:&tag];
}

- (OSStatus)moveFileToTrashForFilename:(NSString*)filename {
	NSURL *fileURL = [self notesDirectoryFileURLForFilename:filename];
	if (!fileURL) return fnfErr;

	//-[NSFileManager trashItemAtURL:...] is the modern successor to the FSFindFolder + FSMoveObject trash dance,
	//and it resolves in-Trash name collisions itself. Being NSError-based, it structurally cannot report success
	//while having moved nothing -- which is exactly NVN-4's silent-success bug (there's no stale OSStatus to return).
	NSError *error = nil;
	if (![[NSFileManager defaultManager] trashItemAtURL:fileURL resultingItemURL:NULL error:&error]) {
		NSLog(@"Error moving %@ to trash: %@", filename, error);
		return error ? (OSStatus)[error code] : kFileStorageErr;
	}

	return noErr;
}

@end
