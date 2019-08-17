//
//  DoubleMetaphone.m
//  DoubleMetaphone
//

#import "DoubleMetaphone.h"
#import "double_metaphone.h"

@implementation DoubleMetaphone

- (NSString*) getCode:(NSString *)input {
    
    NSArray<NSString*>* metaphones = [self getCodes:input];
    if([metaphones count]){
        return metaphones[0];
    }
    
    return @"";
}

- (NSString*) getEngineId {
    return @"DoubleMetaphone";
}

- (NSArray<NSString*>*) getCodes : (NSString *)input {
    const char* str = [input UTF8String];
    auto result = dm::double_metaphone(str);
    
    NSString* ret1;
    NSString* ret2;
    if(result.first.c_str() != nil){
        ret1 = [NSString stringWithUTF8String:result.first.c_str()];
    }
    
    if(result.second.c_str() != nil){
        ret2 = [NSString stringWithUTF8String:result.second.c_str()];
    }
    
    if(ret1 && ret2 && ![ret1 isEqualToString:ret2]){
        return @[ret1, ret2];
    }else if(ret1){
        return @[ret1];
    }else if(ret2){
        return @[ret2];
    }else{
        return @[];
    }
}

@end
