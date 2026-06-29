//
//  NotationDirectoryManager.m
//  Notation
//
//  Created by Zachary Schneirov on 12/10/09.

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

#import "NotationDirectoryManager.h"
#import "NSFileManager_NV.h"
#import "NotationPrefs.h"
#import "BufferUtils.h"
#import "GlobalPrefs.h"
#import "NotationSyncServiceManager.h"
#import "NoteObject.h"
#import "DeletionManager.h"
#import "NSCollection_utils.h"

@implementation NotationController (NotationDirectoryManager)


NSInteger compareCatalogEntryName(const void *one, const void *two) {
    return (int)CFStringCompare((CFStringRef)((*(NoteCatalogEntry **)one)->filename), 
								(CFStringRef)((*(NoteCatalogEntry **)two)->filename), kCFCompareCaseInsensitive);
}

NSInteger compareCatalogValueNodeID(id *a, id *b) {
	NoteCatalogEntry* aEntry = (NoteCatalogEntry*)[*(id*)a pointerValue];
	NoteCatalogEntry* bEntry = (NoteCatalogEntry*)[*(id*)b pointerValue];
	
    return aEntry->nodeID - bEntry->nodeID;
}

NSInteger compareCatalogValueFileSize(id *a, id *b) {
	NoteCatalogEntry* aEntry = (NoteCatalogEntry*)[*(id*)a pointerValue];
	NoteCatalogEntry* bEntry = (NoteCatalogEntry*)[*(id*)b pointerValue];
	
    return aEntry->logicalSize - bEntry->logicalSize;
}


//used to find notes corresponding to a group of existing files in the notes dir, with the understanding 
//that the files' contents are up-to-date and the filename property of the note objs is also up-to-date
//e.g. caller should know that if notes are stored as a single DB, then the file could still be out-of-date
- (NSSet*)notesWithFilenames:(NSArray*)filenames unknownFiles:(NSArray**)unknownFiles {
	//intersects a list of filenames with the current set of available notes
	
	NSUInteger i = 0;
	
	NSMutableDictionary *lcNamesDict = [NSMutableDictionary dictionaryWithCapacity:[filenames count]];
	for (i=0; i<[filenames count]; i++) {
		NSString *path = [filenames objectAtIndex:i];
		//assume that paths are of NSFileManager origin, not Carbon File Manager
		//(note filenames are derived with the expectation of matching against Carbon File Manager)
		[lcNamesDict setObject:path forKey:[[[[path lastPathComponent] precomposedStringWithCanonicalMapping] 
											 lowercaseString] stringByReplacingOccurrencesOfString:@":" withString:@"/"]];
	}
	
	NSMutableSet *foundNotes = [NSMutableSet setWithCapacity:[filenames	count]];
	
	for (i=0; i<[allNotes count]; i++) {
		NoteObject *aNote = [allNotes objectAtIndex:i];
		NSString *existingRequestedFilename = [filenameOfNote(aNote) lowercaseString];
		if (existingRequestedFilename && [lcNamesDict objectForKey:existingRequestedFilename]) {
			[foundNotes addObject:aNote];
			//remove paths from the dict as they are matched to existing notes; those left over will be new ("unknown") files
			[lcNamesDict removeObjectForKey:existingRequestedFilename];
		}
	}
	if (unknownFiles) *unknownFiles = [lcNamesDict allValues];
	return foundNotes;
}


void FSEventsCallback(ConstFSEventStreamRef stream, void* info, size_t num_events, void* event_paths, 
					  const FSEventStreamEventFlags flags[],
                      const FSEventStreamEventId event_ids[]) {
	NotationController* self = (NotationController*)info;
	
	BOOL rootChanged = NO;
	size_t i = 0;
	for (i = 0; i < num_events; i++) {
		//on 10.5, could also check whether all the events are bookended by eventIDs that were contemporaneous with a change by NotationFileManager
		//as it lacks kFSEventStreamCreateFlagIgnoreSelf
		if ((flags[i] & kFSEventStreamEventFlagRootChanged) && !event_ids[i]) {
			rootChanged = YES;
			break;
		}
	}
	
	//the directory was moved; re-initialize the event stream for the new path
	//but do so after this callback ends to avoid confusing FSEvents
	if (rootChanged) {
		NSLog(@"FSEventsCallback detected directory dislocation; reconfiguring stream");
		[self performSelector:@selector(_configureDirEventStream) withObject:nil afterDelay:0];
	}
	
	//NSLog(@"FSEventsCallback got a path change");
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(synchronizeNotesFromDirectory) object:nil];
	[self performSelector:@selector(synchronizeNotesFromDirectory) withObject:nil afterDelay:0.0];
}


- (void)_configureDirEventStream {
	//"updates" the event stream to point to the current notation directory path
	//or if the stream doesn't exist, creates it
	
	if (!eventStreamStarted) return;
	
	if (noteDirEventStreamRef) {
		//remove the event stream if it already exists, so that a new one can be created
		[self _destroyDirEventStream];
	}
	
	NSString *path = [[NSFileManager defaultManager] pathWithFSRef:&noteDirectoryRef];
	
	FSEventStreamContext context = { 0, self, CFRetain, CFRelease, CFCopyDescription };
	
	noteDirEventStreamRef = FSEventStreamCreate(NULL, &FSEventsCallback, &context, (CFArrayRef)[NSArray arrayWithObject:path], kFSEventStreamEventIdSinceNow, 
												1.0, kFSEventStreamCreateFlagWatchRoot | 0x00000008 /*kFSEventStreamCreateFlagIgnoreSelf*/);
	
	FSEventStreamScheduleWithRunLoop(noteDirEventStreamRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	if (!FSEventStreamStart(noteDirEventStreamRef)) {
		NSLog(@"could not start the FSEvents stream!");
	}
	
}

- (void)_destroyDirEventStream {
	if (eventStreamStarted) {
		NSAssert(noteDirEventStreamRef != NULL, @"can't destroy a NULL event stream");
		
		FSEventStreamStop(noteDirEventStreamRef);
		FSEventStreamInvalidate(noteDirEventStreamRef);
		FSEventStreamRelease(noteDirEventStreamRef);
		noteDirEventStreamRef = NULL;
	}
}

- (void)startFileNotifications {
	eventStreamStarted = YES;
	
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5				
	if (IsZeros(&noteDirSubscription, sizeof(FNSubscriptionRef))) {
		
		OSStatus err = FNSubscribe(&noteDirectoryRef, subscriptionCallback, self, kFNNoImplicitAllSubscription | kFNNotifyInBackground, &noteDirSubscription);
		if (err != noErr) {
			NSLog(@"Could not subscribe to changes in notes directory!");
			//just check modification time of directory?
		}
	}
#endif
	if (IsLeopardOrLater) {
		[self _configureDirEventStream];
	}
}

- (void)stopFileNotifications {
	
	if (!eventStreamStarted) return;
	
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
	OSStatus err = noErr;
    if (!IsZeros(&noteDirSubscription, sizeof(FNSubscriptionRef))) {
		
		if ((err = FNUnsubscribe(noteDirSubscription)) != noErr) {
			NSLog(@"Could not unsubscribe from note changes callback: %d", err);
		} else {
			bzero(&noteDirSubscription, sizeof(FNSubscriptionRef));
		}
		
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(synchronizeNotesFromDirectory) object:nil];
    }
#endif
    
	if (IsLeopardOrLater) {
		[self _destroyDirEventStream];
	}
	
	eventStreamStarted = NO;
}

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
void NotesDirFNSubscriptionProc(FNMessage message, OptionBits flags, void * refcon, FNSubscriptionRef subscription) {
    //this only works for the Finder and perhaps the navigation manager right now
	if (kFNDirectoryModifiedMessage == message) {
		//NSLog(@"note directory changed");
		if (refcon) {
			[NSObject cancelPreviousPerformRequestsWithTarget:(id)refcon selector:@selector(synchronizeNotesFromDirectory) object:nil];
			[(id)refcon performSelector:@selector(synchronizeNotesFromDirectory) withObject:nil afterDelay:0.0];
		}
		
    } else {
		NSLog(@"we received an FNSubscr. callback and the directory didn't actually change?");
    }
}
#endif

- (BOOL)synchronizeNotesFromDirectory {
    if ([self currentNoteStorageFormat] == SingleDatabaseFormat) {
		//NSLog(@"%s: called when storage format is singledatabase", _cmd);
		return NO;
	}
	
    //NSDate *date = [NSDate date];
    if ([self _readFilesInDirectory]) {
		//NSLog(@"read files in directory");
		
		directoryChangesFound = NO;
		if (catEntriesCount && [allNotes count]) {
			[self makeNotesMatchCatalogEntries:sortedCatalogEntries ofSize:catEntriesCount];
		} else {
			unsigned int i;
			
			if (![allNotes count]) {
				//no notes exist, so every file must be new
				for (i=0; i<catEntriesCount; i++) {
					if ([notationPrefs catalogEntryAllowed:sortedCatalogEntries[i]])
						[self addNoteFromCatalogEntry:sortedCatalogEntries[i]];
				}
			}
			
			if (!catEntriesCount) {
				//there is nothing at all in the directory, so remove all the notes
				[deletionManager addDeletedNotes:allNotes];
			}
		}
		
		if (directoryChangesFound) {
			[self resortAllNotes];
		    [self refilterNotes];
			
			[self updateTitlePrefixConnections];
		}
		
		//NSLog(@"file sync time: %g, ",[[NSDate date] timeIntervalSinceDate:date]);
		return YES;
    }
    
    return NO;
}

//bridge a URL resource date (NSDate) into the UTCDateTime the model + on-disk serialization still use (NVN-3 §4b
//keeps UTCDateTime as the stored type; only the source and the comparison change). file-local to this translation unit.
static void UTCDateTimeFromNSDate(NSDate *date, UTCDateTime *outDateTime) {
	if (!outDateTime) return;
	bzero(outDateTime, sizeof(UTCDateTime));
	if (date) (void)UCConvertCFAbsoluteTimeToUTCDateTime((CFAbsoluteTime)[date timeIntervalSinceReferenceDate], outDateTime);
}

//scour the notes directory for fresh meat
- (BOOL)_readFilesInDirectory {

	NSURL *dirURL = [self notesDirectoryURL];
	if (!dirURL) {
		NSLog(@"_readFilesInDirectory: no notes directory URL");
		return NO;
	}

	NSFileManager *fileMan = [NSFileManager defaultManager];
	NSArray *keys = [NSArray arrayWithObjects:NSURLIsDirectoryKey, NSURLContentModificationDateKey,
					 NSURLAttributeModificationDateKey, NSURLFileSizeKey, NSURLNameKey, nil];
	NSError *error = nil;
	//shallow enumeration (the FSIterate was kFSIterateFlat); dotfile/system-file filtering stays in -catalogEntryAllowed:
	NSArray *fileURLs = [fileMan contentsOfDirectoryAtURL:dirURL includingPropertiesForKeys:keys options:0 error:&error];
	if (!fileURLs) {
		NSLog(@"Error reading notes directory %@: %@", [dirURL path], error);
		return NO;
	}

	unsigned int catIndex = 0;
	NSUInteger fileCount = [fileURLs count];

	//the catalog-entry buffers persist across syncs (their per-entry filenameChars buffers are reused/grown); grow to fit
	if (fileCount > totalCatEntriesCount) {
		unsigned int oldCatEntriesCount = (unsigned int)totalCatEntriesCount;
		totalCatEntriesCount = fileCount;
		catalogEntries = (NoteCatalogEntry *)realloc(catalogEntries, totalCatEntriesCount * sizeof(NoteCatalogEntry));
		sortedCatalogEntries = (NoteCatalogEntry **)realloc(sortedCatalogEntries, totalCatEntriesCount * sizeof(NoteCatalogEntry*));

		//clear new space so filename and filenameChars start NULL
		bzero(catalogEntries + oldCatEntriesCount, (totalCatEntriesCount - oldCatEntriesCount) * sizeof(NoteCatalogEntry));
	}

	for (NSURL *fileURL in fileURLs) {
		// Only read files, not directories
		NSNumber *isDir = nil;
		[fileURL getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:NULL];
		if ([isDir boolValue]) continue;

		NoteCatalogEntry *entry = &catalogEntries[catIndex];

		NSDate *contentMod = nil, *attrMod = nil;
		NSNumber *fileSize = nil;
		NSString *name = nil;
		[fileURL getResourceValue:&contentMod forKey:NSURLContentModificationDateKey error:NULL];
		[fileURL getResourceValue:&attrMod forKey:NSURLAttributeModificationDateKey error:NULL];
		[fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:NULL];
		[fileURL getResourceValue:&name forKey:NSURLNameKey error:NULL];
		if (!name) name = [fileURL lastPathComponent];

		//HFS type codes are effectively obsolete on modern volumes; -catalogEntryAllowed: falls back to the path extension
		entry->fileType = 0;
		entry->logicalSize = (UInt32)([fileSize unsignedLongLongValue] & 0xFFFFFFFF);

		//inode/CNID has no direct NSURL resource key; NSFileSystemFileNumber is the inode used for note<->file matching
		NSDictionary *attrs = [fileMan attributesOfItemAtPath:[fileURL path] error:NULL];
		entry->nodeID = (UInt32)[[attrs objectForKey:NSFileSystemFileNumber] unsignedLongLongValue];

		UTCDateTimeFromNSDate(contentMod, &entry->lastModified);
		UTCDateTimeFromNSDate(attrMod, &entry->lastAttrModified);

		//store the name into the entry's reused external-character buffer, mirroring the old FSGetCatalogInfoBulk path
		CFIndex nameLen = CFStringGetLength((CFStringRef)name);
		if ((UniCharCount)nameLen > entry->filenameCharCount) {
			entry->filenameCharCount = (UniCharCount)nameLen;
			entry->filenameChars = (UniChar*)realloc(entry->filenameChars, entry->filenameCharCount * sizeof(UniChar));
		}
		CFStringGetCharacters((CFStringRef)name, CFRangeMake(0, nameLen), entry->filenameChars);

		if (!entry->filename)
			entry->filename = CFStringCreateMutableWithExternalCharactersNoCopy(NULL, entry->filenameChars, nameLen, entry->filenameCharCount, kCFAllocatorNull);
		else
			CFStringSetExternalCharactersNoCopy(entry->filename, entry->filenameChars, nameLen, entry->filenameCharCount);

		// mipe: Normalize the filename to make sure that it will be found regardless of international characters
		CFStringNormalize(entry->filename, kCFStringNormalizationFormC);

		catIndex++;
	}

	catEntriesCount = catIndex;

	for (catIndex = 0; catIndex < catEntriesCount; catIndex++)
		sortedCatalogEntries[catIndex] = &catalogEntries[catIndex];

	return YES;
}

//NVN-3 §4b: the old code compared the whole UTCDateTime struct bitwise (including the sub-second fraction), which
//cannot survive re-sourcing dates from NSDate. Compare as CFAbsoluteTime with a 1-second tolerance instead: this
//preserves HFS+ 1s semantics, absorbs APFS-nanosecond float noise, and keeps the safe failure mode -- if the dates
//can't be compared we report "changed", triggering a spurious reload rather than masking a real on-disk change.
static BOOL UTCDateTimesDifferBeyondTolerance(UTCDateTime *a, UTCDateTime *b) {
	CFAbsoluteTime ta = 0, tb = 0;
	if (UCConvertUTCDateTimeToCFAbsoluteTime(a, &ta) != noErr || UCConvertUTCDateTimeToCFAbsoluteTime(b, &tb) != noErr)
		return YES;
	return fabs(ta - tb) >= 1.0;
}

- (BOOL)modifyNoteIfNecessary:(NoteObject*)aNoteObject usingCatalogEntry:(NoteCatalogEntry*)catEntry {
	//check dates
	UTCDateTime lastReadDate = fileModifiedDateOfNote(aNoteObject);
	UTCDateTime *lastAttrModDate = attrsModifiedDateOfNote(aNoteObject);
	
	//should we always update the note's stored inode here regardless?
//	NSLog(@"content mod: %d,%d,%d, attr mod: %d,%d,%d", catEntry->lastModified.highSeconds,catEntry->lastModified.lowSeconds,catEntry->lastModified.fraction,
//		  catEntry->lastAttrModified.highSeconds,catEntry->lastAttrModified.lowSeconds,catEntry->lastAttrModified.fraction);
	
	updateForVerifiedExistingNote(deletionManager, aNoteObject);
	
	if (fileSizeOfNote(aNoteObject) != catEntry->logicalSize ||
		UTCDateTimesDifferBeyondTolerance(&lastReadDate, &(catEntry->lastModified)) ||
		UTCDateTimesDifferBeyondTolerance(lastAttrModDate, &(catEntry->lastAttrModified))) {

		//assume the file on disk was modified by someone other than us
				
		//check if this note has changes in memory that still need to be committed -- that we _know_ the other writer never had a chance to see
		if (![unwrittenNotes containsObject:aNoteObject]) {
			
			if (![aNoteObject updateFromCatalogEntry:catEntry]) {
				NSLog(@"file %@ was modified but could not be updated", catEntry->filename);
				//return NO;
			}
			//do not call makeNoteDirty because use of the WAL in this instance would cause redundant disk activity
			//in the event of a crash this change could still be recovered; 
			
			[aNoteObject registerModificationWithOwnedServices];
			[self schedulePushToAllSyncServicesForNote:aNoteObject];
			
			[self note:aNoteObject attributeChanged:NotePreviewString]; //reverse delegate?
			
			[delegate contentsUpdatedForNote:aNoteObject];
			
			[self performSelector:@selector(scheduleUpdateListForAttribute:) withObject:NoteDateModifiedColumnString afterDelay:0.0];
			
			notesChanged = YES;
			NSLog(@"FILE WAS MODIFIED: %@", catEntry->filename);
			
			return YES;
		} else {
			//it's a conflict! we win.
			NSLog(@"%@ was modified with unsaved changes in NV! Deciding the conflict in favor of NV.", catEntry->filename); 
		}
		
	}
	
	return NO;
}

- (void)makeNotesMatchCatalogEntries:(NoteCatalogEntry**)catEntriesPtrs ofSize:(size_t)catCount {
    
    unsigned int aSize = [allNotes count];
    unsigned int bSize = catCount;
    
	ResizeArray(&allNotesBuffer, aSize, &allNotesBufferSize);
	
	NSAssert(allNotesBuffer != NULL, @"sorting buffer not initialized");
	
    NoteObject **currentNotes = allNotesBuffer;
    [allNotes getObjects:(id*)currentNotes];
	
	mergesort((void *)allNotesBuffer, (size_t)aSize, sizeof(id), (int (*)(const void *, const void *))compareFilename);
	mergesort((void *)catEntriesPtrs, (size_t)bSize, sizeof(NoteCatalogEntry*), (int (*)(const void *, const void *))compareCatalogEntryName);
	
    NSMutableArray *addedEntries = [NSMutableArray array];
    NSMutableArray *removedEntries = [NSMutableArray array];
	
    //oldItems(a,i) = currentNotes
    //newItems(b,j) = catEntries;
    
    unsigned int i, j, lastInserted = 0;
    
    for (i=0; i<aSize; i++) {
		
		BOOL exitedEarly = NO;
		for (j=lastInserted; j<bSize; j++) {
			
			CFComparisonResult order = CFStringCompare((CFStringRef)(catEntriesPtrs[j]->filename),
													   (CFStringRef)filenameOfNote(currentNotes[i]), 
													   kCFCompareCaseInsensitive);
			if (order == kCFCompareGreaterThan) {    //if (A[i] < B[j])
				lastInserted = j;
				exitedEarly = YES;
				
				//NSLog(@"FILE DELETED (during): %@", filenameOfNote(currentNotes[i]));
				[removedEntries addObject:currentNotes[i]];
				break;
			} else if (order == kCFCompareEqualTo) {			//if (A[i] == B[j])
				//the name matches, so add this to changed iff its contents also changed
				lastInserted = j + 1;
				exitedEarly = YES;
				
				[self modifyNoteIfNecessary:currentNotes[i] usingCatalogEntry:catEntriesPtrs[j]];
				
				break;
			}
			
			//NSLog(@"FILE ADDED (during): %@", catEntriesPtrs[j]->filename);
			if ([notationPrefs catalogEntryAllowed:catEntriesPtrs[j]])
				[addedEntries addObject:[NSValue valueWithPointer:catEntriesPtrs[j]]];
		}
		
		if (!exitedEarly) {
			
			//element A[i] "appended" to the end of list B
			if (CFStringCompare((CFStringRef)filenameOfNote(currentNotes[i]),
								(CFStringRef)(catEntriesPtrs[MIN(lastInserted, bSize-1)]->filename), 
								kCFCompareCaseInsensitive) == kCFCompareGreaterThan) {
				lastInserted = bSize;
				
				//NSLog(@"FILE DELETED (after): %@", filenameOfNote(currentNotes[i]));
				[removedEntries addObject:currentNotes[i]];
			}
		}
		
    }
    
    for (j=lastInserted; j<bSize; j++) {
		
		//NSLog(@"FILE ADDED (after): %@", catEntriesPtrs[j]->filename);
		if ([notationPrefs catalogEntryAllowed:catEntriesPtrs[j]])
			[addedEntries addObject:[NSValue valueWithPointer:catEntriesPtrs[j]]];
    }
    
	if ([addedEntries count] && [removedEntries count]) {
		[self processNotesAddedByCNID:addedEntries removed:removedEntries];
	} else {
		
		if (![removedEntries count]) {
			for (i=0; i<[addedEntries count]; i++) {
				[self addNoteFromCatalogEntry:(NoteCatalogEntry*)[[addedEntries objectAtIndex:i] pointerValue]];
			}
		}
		
		if (![addedEntries count]) {
			[deletionManager addDeletedNotes:removedEntries];
		}
	}
	
}

//find renamed notes through unique file IDs
- (void)processNotesAddedByCNID:(NSMutableArray*)addedEntries removed:(NSMutableArray*)removedEntries {
	unsigned int aSize = [removedEntries count], bSize = [addedEntries count];
    
    //sort on nodeID here
	[addedEntries sortUnstableUsingFunction:compareCatalogValueNodeID];
	[removedEntries sortUnstableUsingFunction:compareNodeID];
	
	NSMutableArray *hfsAddedEntries = [NSMutableArray array];
	NSMutableArray *hfsRemovedEntries = [NSMutableArray array];
	
    //oldItems(a,i) = currentNotes
    //newItems(b,j) = catEntries;
    
    unsigned int i, j, lastInserted = 0;
    
    for (i=0; i<aSize; i++) {
		NoteObject *currentNote = [removedEntries objectAtIndex:i];
		
		BOOL exitedEarly = NO;
		for (j=lastInserted; j<bSize; j++) {
			
			NoteCatalogEntry *catEntry = (NoteCatalogEntry *)[[addedEntries objectAtIndex:j] pointerValue];
			int order = catEntry->nodeID - fileNodeIDOfNote(currentNote);
			
			if (order > 0) {    //if (A[i] < B[j])
				lastInserted = j;
				exitedEarly = YES;
				
				NSLog(@"File deleted as per CNID: %@", filenameOfNote(currentNote));
				[hfsRemovedEntries addObject:currentNote];
				
				break;
			} else if (order == 0) {			//if (A[i] == B[j])
				lastInserted = j + 1;
				exitedEarly = YES;
				
				
				//note was renamed!
				NSLog(@"File %@ renamed as per CNID to %@", filenameOfNote(currentNote), catEntry->filename);
				if (![self modifyNoteIfNecessary:currentNote usingCatalogEntry:catEntry]) {
					//at least update the file name, because we _know_ that changed
					
					directoryChangesFound = YES;
					
					[currentNote setFilename:(NSString*)catEntry->filename withExternalTrigger:YES];
				}
				
				notesChanged = YES;
				
				break;
			}
			
			//a new file was found on the disk! read it into memory!
			
			NSLog(@"File added as per CNID: %@", catEntry->filename);
			[hfsAddedEntries addObject:[NSValue valueWithPointer:catEntry]];
		}
		
		if (!exitedEarly) {
			
			NoteCatalogEntry *appendedCatEntry = (NoteCatalogEntry *)[[addedEntries objectAtIndex:MIN(lastInserted, bSize-1)] pointerValue];
			if (fileNodeIDOfNote(currentNote) - appendedCatEntry->nodeID > 0) {
				lastInserted = bSize;
				
				//file deleted from disk; 
				NSLog(@"File deleted as per CNID: %@", filenameOfNote(currentNote));
				[hfsRemovedEntries addObject:currentNote];
			}
		}
    }
    
    for (j=lastInserted; j<bSize; j++) {
		NoteCatalogEntry *appendedCatEntry = (NoteCatalogEntry *)[[addedEntries objectAtIndex:j] pointerValue];
		NSLog(@"File added as per CNID: %@", appendedCatEntry->filename);
		[hfsAddedEntries addObject:[NSValue valueWithPointer:appendedCatEntry]];
    }
	
	if ([hfsAddedEntries count] && [hfsRemovedEntries count]) {
		[self processNotesAddedByContent:hfsAddedEntries removed:hfsRemovedEntries];
	} else {
		//NSLog(@"hfsAddedEntries: %@, hfsRemovedEntries: %@", hfsAddedEntries, hfsRemovedEntries);
		if (![hfsRemovedEntries count]) {
			for (i=0; i<[hfsAddedEntries count]; i++) {
				NSLog(@"File _actually_ added: %@ (%@)", ((NoteCatalogEntry*)[[hfsAddedEntries objectAtIndex:i] pointerValue])->filename, NSStringFromSelector(_cmd));
				[self addNoteFromCatalogEntry:(NoteCatalogEntry*)[[hfsAddedEntries objectAtIndex:i] pointerValue]];
			}
		}
		
		if (![hfsAddedEntries count]) {
			[deletionManager addDeletedNotes:hfsRemovedEntries];
		}
	}
	
}

//reconcile the "actually" added/deleted files into renames for files with identical content, looking at logical size first
- (void)processNotesAddedByContent:(NSMutableArray*)addedEntries removed:(NSMutableArray*)removedEntries {
	//more than 1 entry in the same list could have the same file size, so sort-algo assumptions above don't apply here
	//instead of sorting, build a dict keyed by file size, with duplicate sizes (on the same side) chained into arrays
	//make temporary notes out of the new NoteCatalogEntries to allow their contents to be compared directly where sizes match
	
	NSUInteger i;
	NSMutableDictionary *addedDict = [NSMutableDictionary dictionaryWithCapacity:[addedEntries count]];
	
	for (i=0; i<[addedEntries count]; i++) {
		NSNumber *sizeKey = [NSNumber numberWithUnsignedInt:((NoteCatalogEntry*)[[addedEntries objectAtIndex:i] pointerValue])->logicalSize];
		id sameSizeObj = [addedDict objectForKey:sizeKey];
		
		if ([sameSizeObj isKindOfClass:[NSArray class]]) {
			//just insert it directly; an array already exists
			NSAssert([sameSizeObj isKindOfClass:[NSMutableArray class]], @"who's inserting immutable collections into my dictionary?");
			[sameSizeObj addObject:[addedEntries objectAtIndex:i]];
		} else if (sameSizeObj) {
			//two objects need to be inserted into the new array
			[addedDict setObject:[NSMutableArray arrayWithObjects:sameSizeObj, [addedEntries objectAtIndex:i], nil] forKey:sizeKey];
		} else {
			//nothing with this key, just insert it directly
			[addedDict setObject:[addedEntries objectAtIndex:i] forKey:sizeKey];
		}
	}
//	NSLog(@"removedEntries: %@", removedEntries);
//	NSLog(@"addedDict: %@", addedDict);
	
	for (i=0; i<[removedEntries count]; i++) {
		NoteObject *removedObj = [removedEntries objectAtIndex:i];
		NSNumber *sizeKey = [NSNumber numberWithUnsignedInt:fileSizeOfNote(removedObj)];
		BOOL foundMatchingContent = NO;
		
		//does any added item have the same size as removedObj?
		//if sizes match, see if that added item's actual content fully matches removedObj's
		//if content matches, then both items cancel each other out, with a rename operation resulting on the item in the removedEntries list
		//if content doesn't match, then check the next item in the array (if there is more than one matching size), and so on
		//any item in removedEntries that has no match in the addedEntries list is marked deleted
		//everything left over in the addedEntries list is marked as new
		
		id sameSizeObj = [addedDict objectForKey:sizeKey];
		NSUInteger addedObjCount = [sameSizeObj isKindOfClass:[NSArray class]] ? [sameSizeObj count]: 1;
		while (sameSizeObj && !foundMatchingContent && addedObjCount-- > 0) {
			NSValue *val = [sameSizeObj isKindOfClass:[NSArray class]] ? [sameSizeObj objectAtIndex:addedObjCount] : sameSizeObj;
			NoteObject *addedObjToCompare = [[NoteObject alloc] initWithCatalogEntry:[val pointerValue] delegate:self];
			
			if ([[[addedObjToCompare contentString] string] isEqualToString:[[removedObj contentString] string]]) {
				//process this pair as a modification
				
				NSLog(@"File %@ renamed as per content to %@", filenameOfNote(removedObj), filenameOfNote(addedObjToCompare));
				if (![self modifyNoteIfNecessary:removedObj usingCatalogEntry:[val pointerValue]]) {
					//at least update the file name, because we _know_ that changed
					directoryChangesFound = YES;
					notesChanged = YES;
					[removedObj setFilename:filenameOfNote(addedObjToCompare) withExternalTrigger:YES];
				}
				
				if ([sameSizeObj isKindOfClass:[NSArray class]]) {
					[sameSizeObj removeObjectIdenticalTo:val];
				} else {
					[addedDict removeObjectForKey:sizeKey];
				}
				//also remove it from original array, which is easier to process for the leftovers that will actually be added
				[addedEntries removeObjectIdenticalTo:val];
				foundMatchingContent = YES;
			}
			[addedObjToCompare release];
		}
		
		if (!foundMatchingContent) {
			NSLog(@"File %@ _actually_ removed (size: %u)", filenameOfNote(removedObj), fileSizeOfNote(removedObj));
			[deletionManager addDeletedNote:removedObj];
		}
	}
	
	for (i=0; i<[addedEntries count]; i++) {
		NoteCatalogEntry *appendedCatEntry = (NoteCatalogEntry *)[[addedEntries objectAtIndex:i] pointerValue];
		NSLog(@"File _actually_ added: %@ (%@)", appendedCatEntry->filename, NSStringFromSelector(_cmd));
		[self addNoteFromCatalogEntry:appendedCatEntry];
    }	
}

@end


