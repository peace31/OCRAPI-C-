/// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
/// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

#import <Foundation/Foundation.h>
#import <Cordova/CDVPlugin.h>
#include "MetaEngineController.h"

@interface RTRPlugin : CDVPlugin

- (void)startOCR:(CDVInvokedUrlCommand*)command;
- (void)stopOCR:(CDVInvokedUrlCommand*)command;
- (void)startDataCapture:(CDVInvokedUrlCommand*)command;

@end

@interface OCRDictionary : NSObject

+ (instancetype) initWithDictionary : (NSDictionary*) dict MetaEngine : (MetaEngineController *) engine;

- (BOOL) hasPatterns;
- (NSString*) getKeyName;
- (NSString*) getDisplayValue;
- (NSString*) getDisplayString:(BOOL) isDebug;
- (BOOL) isSetValue;
- (NSInteger) getIndexKeywords: (NSString*) string;
- (NSDictionary*) checkMatchValuePattern: (NSString*) string;
- (BOOL) setValueIfAcceptable: (NSString*) string;

@property (nonatomic) NSString *name;
@property (nonatomic, assign) BOOL mandatory;
@property (nonatomic) NSArray<NSArray<NSString*>*>* keywords;
@property (nonatomic) NSArray<NSString*>* patterns;
@property (nonatomic, assign) BOOL attribute;
@property (nonatomic) NSString *resKeyword;
@property (nonatomic) NSString *resValue;
@property (nonatomic) NSInteger indexOfPattern;

@end
