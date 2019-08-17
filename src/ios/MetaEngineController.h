//
//  MetaEngineController.h
//  MetaEngineController
//
//

#import <Foundation/Foundation.h>

#pragma mark - Coder protocol

@protocol Coder <NSObject>

@required
- (NSString*) getCode:(NSString*)input;

@required
- (NSString*) getEngineId;

@end

#pragma mark - MetaEngineController
@interface MetaEngineController : NSObject

+ (instancetype) initWithEngineId : (NSString*) engineId;
- (NSString*) getSelectedEngineId;
- (NSString*) getPhoneticText : (NSString*) text;

@end
