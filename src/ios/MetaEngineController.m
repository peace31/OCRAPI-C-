//
//  NSString+DoubleMetaphone.m
//  DoubleMetaphone
//
//  Created by Adam Wulf on 4/14/17.
//  Copyright © 2017 Milestone Made. All rights reserved.
//

#include "MetaEngineController.h"
#import "DoubleMetaphone.h"

@interface MetaEngineController()

@property id<Coder> mCoder;

@end

@implementation MetaEngineController

+ (instancetype) initWithEngineId : (NSString*) engineId
{
    MetaEngineController *instance = [[MetaEngineController alloc] init];
    if( instance ) {
        NSMutableArray* arrayCoder = [[NSMutableArray alloc] init];
        [arrayCoder addObject: [[DoubleMetaphone alloc] init] ];
        
        for( id<Coder> coder in arrayCoder ){
            if( [coder.getEngineId isEqualToString:engineId] ){
                instance.mCoder = coder;
                break;
            }
        }
    }
    return instance;
}

- (NSString*) getSelectedEngineId
{
    if( self.mCoder != nil ) return [self.mCoder getEngineId];
    
    return @"native";
}

- (NSString*) getPhoneticText : (NSString*) text
{
    if( self.mCoder == nil) return text;
    
    return [self.mCoder getCode:text];
    
}

@end
