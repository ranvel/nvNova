//
//  StatusItemView.m
//  Notation
//
//  Created by elasticthreads on 07/03/2010.
//  Copyright 2010 elasticthreads. All rights reserved.
//

#import <Cocoa/Cocoa.h>


typedef enum { DarkMenuIcon, SelectedMenuIcon } StatusIconType;

@interface StatusItemView : NSView {
//    BOOL clicked;
    StatusIconType sbIconType;
}


@property(readwrite,nonatomic)StatusIconType sbIconType;

@end
