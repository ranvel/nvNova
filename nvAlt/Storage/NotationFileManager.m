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
#include <openssl/md5.h>

NSString *NotesDatabaseFileName = @"Notes & Settings";

@implementation NotationController (NotationFileManager)

static struct statfs *StatFSVolumeInfo(NotationController *controller);

OSStatus CreateDirectoryIfNotPresent(FSRef *parentRef, CFStringRef subDirectoryName, FSRef *childRef) {
    UniChar chars[256];
    
    OSStatus result;
    if ((result = FSRefMakeInDirectoryWithString(parentRef, childRef, subDirectoryName, chars))) {
		if (result == fnfErr) {
			result = FSCreateDirectoryUnicode (parentRef, CFStringGetLength(subDirectoryName),
											   chars, kFSCatInfoNone, NULL, childRef, NULL, NULL);
		}
		return result;
    }
    
    return noErr;
}

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
	
    MD5_CTX c;
	
    MD5_Init(&c);
    MD5_Update(&c, FSUUIDNamespaceSHA1, sizeof(FSUUIDNamespaceSHA1));
    MD5_Update(&c, name, namelen);
    MD5_Final(result_uuid, &c);
	
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

CFUUIDRef CopySyntheticUUIDForVolumeCreationDate(FSRef *fsRef) {
	
	FSCatalogInfo fileInfo;
	if (FSGetCatalogInfo(fsRef, kFSCatInfoVolume, &fileInfo, NULL, NULL, NULL) == noErr) {
		
		FSVolumeInfo volInfo;
		OSStatus err = FSGetVolumeInfo(fileInfo.volume, 0, NULL, kFSVolInfoCreateDate, &volInfo, NULL, NULL);
		if (err == noErr) {
			volInfo.createDate.highSeconds = CFSwapInt16HostToBig(volInfo.createDate.highSeconds);
			volInfo.createDate.lowSeconds = CFSwapInt32HostToBig(volInfo.createDate.lowSeconds);
			volInfo.createDate.fraction = CFSwapInt16HostToBig(volInfo.createDate.fraction);

			CFUUIDBytes uuidBytes;
			uuid_create_md5_from_name((void*)&uuidBytes, (void*)&volInfo.createDate, sizeof(UTCDateTime));
			
			return CFUUIDCreateFromUUIDBytes(NULL, uuidBytes);
		} else {
			NSLog(@"can't even get the volume creation date -- what are you trying to do to me?");
		}
	}
	return NULL;
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
			diskUUID = CopySyntheticUUIDForVolumeCreationDate(&noteDirectoryRef);
		}
		diskUUIDIndex = [notationPrefs tableIndexOfDiskUUID:diskUUID];
	}
}

static struct statfs *StatFSVolumeInfo(NotationController *controller) {
	if (!controller->statfsInfo) {
		OSStatus err = noErr;
		const UInt32 maxPathSize = 4 * 1024;
		UInt8 *convertedPath = (UInt8*)malloc(maxPathSize * sizeof(UInt8));
		
		if ((err = FSRefMakePath(&(controller->noteDirectoryRef), convertedPath, maxPathSize)) == noErr) {
			
			controller->statfsInfo = calloc(1, sizeof(struct statfs));
			
			if (statfs((char*)convertedPath, controller->statfsInfo))
				NSLog(@"statfs: error %d\n", errno);
		} else
			NSLog(@"FSRefMakePath: error %d\n", err);
		
		free(convertedPath);
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
	Boolean isInTrash = false;	
	if (FSDetermineIfRefIsEnclosedByFolder(0, kTrashFolderType, &noteDirectoryRef, &isInTrash) != noErr)
		isInTrash = false;
	return (BOOL)isInTrash;
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
            
			CFStringRef filename = (CFStringRef)[[openPanel URL]path];
			if (filename) {
				
				FSRef newParentRef;
				CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, filename, kCFURLPOSIXPathStyle, true);
				[(id)url autorelease];
				if (!url || !CFURLGetFSRef(url, &newParentRef)) {
					NSRunAlertPanel(NSLocalizedString(@"Unable to create an FSRef from the chosen directory.",nil), 
									NSLocalizedString(@"Your notes were not moved.",nil), NSLocalizedString(@"OK",nil), NULL, NULL);
					continue;
				}
				
				FSRef newNotesDirectory;
				OSErr err = FSMoveObject(&noteDirectoryRef,  &newParentRef, &newNotesDirectory);
				if (err != noErr) {
					NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Couldn't move notes into the chosen folder because %@",nil), 
						[NSString reasonStringFromCarbonFSError:err]], NSLocalizedString(@"Your notes were not moved.",nil), NSLocalizedString(@"OK",nil), NULL, NULL);
					continue;
				}
				
				if (FSCompareFSRefs(&noteDirectoryRef, &newNotesDirectory) != noErr) {
					NSString *newPath = [[NSFileManager defaultManager] pathWithFSRef:&newNotesDirectory];
					if (newPath) [[GlobalPrefs defaultPrefs] setNotesDirectoryPath:newPath sender:self];
					//we must quit now, as notes will very likely be re-initialized in the same place
					goto terminate;
				}
				
				//directory move successful! //show the user where new notes are
				NSString *newNotesPath = [[NSFileManager defaultManager] pathWithFSRef:&newNotesDirectory];
				if (newNotesPath) [[NSWorkspace sharedWorkspace] selectFile:newNotesPath inFileViewerRootedAtPath:nil];
				
				break;
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

+ (OSStatus)getDefaultNotesDirectoryRef:(FSRef*)notesDir {
    FSRef appSupportFoundRef;
    
    OSErr err = FSFindFolder(kUserDomain, kApplicationSupportFolderType, kCreateFolder, &appSupportFoundRef);
    if (err != noErr) {
	NSLog(@"Unable to locate or create an Application Support directory: %d", err);
	return err;
    } else {
	//now try to get Notational Database directory
	if ((err = CreateDirectoryIfNotPresent(&appSupportFoundRef, (CFStringRef)@"Notational Data", notesDir)) != noErr) {
	    
	    return err;
	}
    }
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

//bridge a URL resource date (NSDate) into the UTCDateTime the model + on-disk serialization still use.
//NVN-3 deliberately keeps UTCDateTime as the stored type (NSCoding compat); only the *source* and the
//*comparison* change. UTCDateTime/UCConvert* excision is NVN-5.
static void UTCDateTimeFromNSDate(NSDate *date, UTCDateTime *outDateTime) {
	if (!outDateTime) return;
	bzero(outDateTime, sizeof(UTCDateTime));
	if (date) (void)UCConvertCFAbsoluteTimeToUTCDateTime((CFAbsoluteTime)[date timeIntervalSinceReferenceDate], outDateTime);
}

- (OSStatus)fileInNotesDirectory:(NSString*)filename isOwnedByUs:(BOOL*)owned hasCatalogInfo:(FSCatalogInfo *)info {
	if (owned) *owned = NO;
	if (info) bzero(info, sizeof(FSCatalogInfo));

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

		UTCDateTimeFromNSDate(contentMod, &info->contentModDate);
		UTCDateTimeFromNSDate(attrMod, &info->attributeModDate);
		UTCDateTimeFromNSDate(created, &info->createDate);
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
	FSRef folder;
	
	OSStatus err = [NotationController trashFolderRef:&folder forChild:&noteDirectoryRef];
	
	if (err == noErr)
		FNNotify(&folder, kFNDirectoryModifiedMessage, kNilOptions);
	 else
		NSLog(@"notifyOfChangedTrash: error getting trash: %d", err);
	
	 NSString *sillyDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[(NSString*)CreateRandomizedFileName() autorelease]];
//	 [[NSFileManager defaultManager] createDirectoryAtPath:sillyDirectory attributes:nil];
    
    [[NSFileManager defaultManager]createFolderAtPath:sillyDirectory];
	 NSInteger tag = 0;
	 [[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:NSTemporaryDirectory() destination:@"" 
												   files:[NSArray arrayWithObject:[sillyDirectory lastPathComponent]] tag:&tag];
}

+ (OSStatus)trashFolderRef:(FSRef*)trashRef forChild:(FSRef*)childRef {
    FSVolumeRefNum volume = kOnAppropriateDisk;
    FSCatalogInfo info;
    // get the volume the file resides on and use this as the base for finding the trash folder
    // since each volume will contain its own trash folder...
    
    if (FSGetCatalogInfo(childRef, kFSCatInfoVolume, &info, NULL, NULL, NULL) == noErr)
		volume = info.volume;
    // go ahead and find the trash folder on that volume.
    // the trash folder for the current user may not yet exist on that volume, so ask to automatically create it

	return FSFindFolder(volume, kTrashFolderType, kCreateFolder, trashRef);
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
