/// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
/// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

#import "RTRPlugin.h"
#import "CDVPluginResult+RTRPluginResult.h"
#import "RTRTextCaptureViewController.h"
#import "RTRDataCaptureViewController.h"
#import "RTRDataCaptureScenario.h"

static int const RECO_ERROR_FAILED = 3;
static int const RECO_ERROR_PERMISSION_DENIED = 4;
static int const RECO_ERROR_ALREADY_STARTED = 5;
static int const STOP_ERROR_ENGINE_NOT_STARTED = 6;

static NSString* const RTRCordovaPluginErrorDomain = @"com.abbyy.rtr-cordova-plugin";

static NSString* const RTRRecognitionLanguagesKey = @"recognitionLanguages";
static NSString* const RTRSelectableRecognitionLanguagesKey = @"selectableRecognitionLanguages";

static NSString* const RTRLicenseFileNameKey = @"licenseFileName";
static NSString* const RTRStopWhenStableKey = @"stopWhenStable";
static NSString* const RTRIsStopButtonVisibleKey = @"isStopButtonVisible";
static NSString* const RTRAreaOfInterestKey = @"areaOfInterest";
static NSString* const RTRIsFlashlightVisibleKey = @"isFlashlightVisible";
static NSString* const RTRDebugModeKey = @"debug";
static NSString* const RTRCountryKey = @"country";
static NSString* const RTRDictionaryKey = @"dictionary";
static NSString* const RTRBackgroundKey = @"toBack";
static NSString* const RTRMetaEngineKey = @"fieldMatchingMethodIos";

static NSString* const RTRCustomDataCaptureScenarioKey = @"customDataCaptureScenario";
static NSString* const RTRCustomDataCaptureScenarioNameKey = @"name";
static NSString* const RTRCustomDataCaptureFieldsKey = @"fields";
static NSString* const RTRCustomDataCaptureRegExKey = @"regEx";
static NSString* const RTRScenarioDescriptionKey = @"description";

static NSString* const RTRDataCaptureProfileKey = @"profile";

static NSString* const RTRDefaultRecognitionLanguage = @"English";

NSString* const RTRCallbackErrorKey = @"error";
NSString* const RTRCallbackErrorDescriptionKey = @"description";
NSString* const RTRCallbackResultInfoKey = @"resultInfo";
NSString* const RTRCallbackUserActionKey = @"userAction";
NSString* const RTRCallbackErrorCodeKey = @"code";
NSString* const RTRCallbackErrorMessageKey = @"message";

static NSString* const DEFAULT_VALUE = @"---";

@interface RTRPlugin ()

@property (atomic, assign) BOOL session;
@property (atomic, assign) BOOL toBack;
@property (nonatomic) RTRViewController* rtrViewController;
@property (nonatomic) RTRManager* rtrManager;

@end

@implementation RTRPlugin

- (void)pluginInitialize {
    [super pluginInitialize];
    self.session = false;
    self.toBack = false;
}
#pragma mark - Public

- (void)startOCR:(CDVInvokedUrlCommand*)command
{
    if( self.session || self.rtrViewController != nil){
        NSMutableDictionary* result = [@{
                                         RTRCallbackResultInfoKey : @{
                                                 RTRCallbackErrorCodeKey: [NSNumber numberWithInt:RECO_ERROR_ALREADY_STARTED],
                                                 RTRCallbackErrorMessageKey : @"Camera already started."
                                                 }
                                         } mutableCopy];
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:result];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }
	[self.commandDelegate runInBackground:^{
		if(![self initializeRtrManager:command]) {
			return;
		}

		NSDictionary* params = command.arguments.firstObject;
		NSArray<NSString*>* languages = params[RTRSelectableRecognitionLanguagesKey];
        NSArray<NSString*>* selectedLanguagesArray = params[RTRRecognitionLanguagesKey];
        
        self.toBack = false;
        if(params[RTRBackgroundKey] != nil) {
            self.toBack = [params[RTRBackgroundKey] boolValue];
        }
        
		if(selectedLanguagesArray.count == 0) {
			selectedLanguagesArray = @[RTRDefaultRecognitionLanguage];
		}

		NSSet* selectedLanguages = [NSSet setWithArray:selectedLanguagesArray];

		RTRTextCaptureViewController* rtrViewController = [RTRTextCaptureViewController new];
		rtrViewController.settingsTableContent = languages;
		rtrViewController.selectedRecognitionLanguages = [selectedLanguages mutableCopy];
		rtrViewController.languageSelectionEnabled = languages.count != 0;

		__weak RTRPlugin* weakSelf = self;
		__weak RTRTextCaptureViewController* textCaptureController = rtrViewController;
		rtrViewController.onSuccess = ^(BOOL isManuallyStopped) {
			CDVPluginResult* pluginResult = [CDVPluginResult rtrResultForTextCapture:textCaptureController stoppedByUser:isManuallyStopped];
			[textCaptureController.presentingViewController dismissViewControllerAnimated:YES completion:^{
				[weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
			}];
		};
        
        rtrViewController.onDetectText = ^() {
            CDVPluginResult* pluginResult = [CDVPluginResult rtrResultForTextCapture:textCaptureController stoppedByUser:NO];
            [pluginResult setKeepCallbackAsBool:YES];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        };
        self.session = true;

        [self presentCaptureViewController:rtrViewController command:command];
	}];
}
- (void)stopOCR:(CDVInvokedUrlCommand*)command
{
    [self.rtrViewController.view removeFromSuperview];
    [self.rtrViewController removeFromParentViewController];
    self.rtrViewController = nil;
    
    [self.commandDelegate runInBackground:^{
        CDVPluginResult* pluginResult;
        
        if( !self.session ){
            NSMutableDictionary* result = [@{
                                             RTRCallbackResultInfoKey : @{
                                                     RTRCallbackErrorCodeKey: [NSNumber numberWithInt:STOP_ERROR_ENGINE_NOT_STARTED],
                                                     RTRCallbackErrorMessageKey : @"Camera is not started."
                                                     }
                                             } mutableCopy];
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:result];
        } else {
            self.session = false;
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        }
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)startDataCapture:(CDVInvokedUrlCommand*)command
{
	[self.commandDelegate runInBackground:^{
		if(![self initializeRtrManager:command]) {
			return;
		}

		RTRDataCaptureViewController* rtrViewController = [RTRDataCaptureViewController new];

		NSDictionary* params = command.arguments.firstObject;
		NSDictionary* scenarioParams = params[RTRCustomDataCaptureScenarioKey];

		NSString* errorDescription = nil;

		if(scenarioParams != nil) {
			NSString* name = scenarioParams[RTRCustomDataCaptureScenarioNameKey];
			NSArray<NSString*>* languages = scenarioParams[RTRRecognitionLanguagesKey];
			if(languages.count == 0) {
				languages = @[RTRDefaultRecognitionLanguage];
			}
			NSString* description = scenarioParams[RTRScenarioDescriptionKey] ?: name;
			NSArray* fields = scenarioParams[RTRCustomDataCaptureFieldsKey];
			NSString* regEx = fields.firstObject[RTRCustomDataCaptureRegExKey];
			if(regEx.length == 0) {
				errorDescription = @"Invalid Data Capture scenario settings. Specify Reg Ex for Custom Data Capture scenario.";
			}

			rtrViewController.selectedScenario = [RTRDataCaptureScenario dataCaptureScenarioWithName:name regEx:regEx
				languages:[NSSet setWithArray:languages] description:description];
		} else if(params[RTRDataCaptureProfileKey] != nil) {
			rtrViewController.profile = params[RTRDataCaptureProfileKey];
		} else {
			errorDescription = @"Invalid Data Capture scenario settings. Specify Data Capture profile or params for Custom Data Capture Scenario.";
		}

		if(errorDescription.length != 0) {
			NSError* error = [NSError errorWithDomain:RTRCordovaPluginErrorDomain code:3 userInfo:@{
				NSLocalizedDescriptionKey : errorDescription
			}];
			CDVPluginResult* result = [CDVPluginResult rtrResultWithError:error];
			[self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
			return;
		}

		__weak RTRPlugin* weakSelf = self;
		__weak RTRDataCaptureViewController* dataCaptureController = rtrViewController;
		rtrViewController.onSuccess = ^(BOOL isManuallyStopped) {
			CDVPluginResult* pluginResult = [CDVPluginResult rtrResultForDataCapture:dataCaptureController stoppedByUser:isManuallyStopped];
			[dataCaptureController.presentingViewController dismissViewControllerAnimated:YES completion:^{
				[weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
			}];
		};

		[self presentCaptureViewController:rtrViewController command:command];
	}];
}

#pragma mark - Helpers

- (void)presentCaptureViewController:(RTRViewController*)rtrViewController command:(CDVInvokedUrlCommand*)command
{
	NSDictionary* params = command.arguments.firstObject;
	rtrViewController.rtrManager = self.rtrManager;
	rtrViewController.stopWhenStable = NO;
	if(params[RTRStopWhenStableKey] != nil) {
		rtrViewController.stopWhenStable = [params[RTRStopWhenStableKey] boolValue];
	}

	rtrViewController.isFlashlightVisible = NO;
	if(params[RTRIsFlashlightVisibleKey] != nil) {
		rtrViewController.isFlashlightVisible = [params[RTRIsFlashlightVisibleKey] boolValue];
	}

	rtrViewController.stopButtonVisible = NO;
	if(params[RTRIsStopButtonVisibleKey] != nil) {
		rtrViewController.stopButtonVisible = [params[RTRIsStopButtonVisibleKey] boolValue];
	}
    
    rtrViewController.isDebugMode = NO;
    if(params[RTRDebugModeKey] != nil) {
        rtrViewController.isDebugMode = [params[RTRDebugModeKey] boolValue];
    }
    
    [rtrViewController setCountryName:@"Australia"];
    if(params[RTRCountryKey] != nil) {
        [rtrViewController setCountryName:params[RTRCountryKey] ];
    }
    
    [rtrViewController setMetaEngineId:@"native"];
    if(params[RTRMetaEngineKey] != nil) {
        [rtrViewController setMetaEngineId:params[RTRMetaEngineKey]];
    }
    [rtrViewController initMetaPhoneEngine];
    
    [rtrViewController setDictArray:[[NSArray alloc] init] ];
    if(params[RTRDictionaryKey] != nil) {
        [rtrViewController setDictArray:params[RTRDictionaryKey]];
    }
    [rtrViewController initDetectionDictInfo];

	NSArray<NSString*>* parts = [params[RTRAreaOfInterestKey] componentsSeparatedByString:@" "];
	CGFloat widthPercentage = [parts.firstObject floatValue] ?: 1.0f;
	CGFloat heightPercentage = [parts.lastObject floatValue] ?: 1.0f;
	rtrViewController.areaOfInterestRatio = CGSizeMake(widthPercentage, heightPercentage);

	__weak RTRPlugin* weakSelf = self;
	__weak RTRViewController* weakController = rtrViewController;
	rtrViewController.onCancel = ^{
		NSMutableDictionary* result = [@{
			RTRCallbackResultInfoKey : @{
                    RTRCallbackErrorCodeKey: [NSNumber numberWithInt:RECO_ERROR_FAILED],
				RTRCallbackErrorMessageKey : @"Canceled Recognize."
			}
		} mutableCopy];

		if(weakController.errorOccurred != nil) {
			NSDictionary* errorDictionary = @{
				RTRCallbackErrorDescriptionKey : weakController.errorOccurred ?: @""
			};
			result[RTRCallbackErrorKey] = errorDictionary;
		}

        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:result];
		[weakController.presentingViewController dismissViewControllerAnimated:YES completion:^{
			[weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
		}];
	};

	dispatch_async(dispatch_get_main_queue(), ^{
		//[self.viewController presentViewController:rtrViewController animated:YES completion:nil];
        
        rtrViewController.view.frame = weakSelf.webView.frame;
        self.rtrViewController = rtrViewController;
        [self.viewController addChildViewController:self.rtrViewController];
        
        if (self.toBack) {
            // display the camera below the webview
            // make transparent
            self.webView.opaque = NO;
            self.webView.backgroundColor = [UIColor clearColor];
            
            [self.webView.superview addSubview:self.rtrViewController.view];
            [self.webView.superview bringSubviewToFront:self.webView];
        } else {
            //rtrViewController.view.alpha = alpha;
            [self.webView.superview insertSubview:self.rtrViewController.view aboveSubview:self.webView];
        }
	});
}

- (BOOL)initializeRtrManager:(CDVInvokedUrlCommand*)command
{
	NSString* licenseName = command.arguments.firstObject[RTRLicenseFileNameKey] ?: @"AbbyyRtrSdk.license";
	NSError* error = nil;
	self.rtrManager = [RTRManager managerWithLicense:licenseName error:&error];

	if(self.rtrManager == nil) {
		if(error == nil) {
			error = [NSError errorWithDomain:RTRCordovaPluginErrorDomain code:2 userInfo:@{
				NSLocalizedDescriptionKey : @"Real-Time Recognition SDK isn't initialized. Please check your license file."
			}];
		}
		CDVPluginResult* result = [CDVPluginResult rtrResultWithError:error];
		[self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
		return NO;
	}

	return YES;
}

@end


@interface OCRDictionary ()

@property (nonatomic, weak) MetaEngineController* mMetaEngine;

@end
@implementation OCRDictionary

+ (instancetype) initWithDictionary : (NSDictionary*) dict MetaEngine : (MetaEngineController *) engine
{
    OCRDictionary *instance = [[OCRDictionary alloc] init];
    if( instance ) {
        instance.name = (dict[@"Name"]!=NULL) ? dict[@"Name"] : @"";
        instance.mandatory = (dict[@"Mandatory"]!=NULL) ? [dict[@"Mandatory"] boolValue] : true;
        instance.mMetaEngine = engine;
        if( dict[@"Keywords"]!=NULL ){
            NSMutableArray *keywords = [[NSMutableArray alloc] init];
            for( NSString *key in dict[@"Keywords"]){
                NSString *phoneticKey = [engine getPhoneticText:key];
                [keywords addObject:[[NSArray alloc] initWithObjects:key, phoneticKey, nil] ];
            }
            instance.keywords = [[NSArray alloc] initWithArray:keywords];
        } else {
            instance.keywords = [[NSArray alloc] init];
        }
        NSString *strPatterns = dict[@"Patterns"];
        if( strPatterns == NULL) instance.patterns = NULL;
        else instance.patterns = [strPatterns componentsSeparatedByString:@"&&"];
        
        instance.attribute = (dict[@"Attribute"]!=NULL) ? [dict[@"Attribute"] boolValue] : false;
        
        instance.resKeyword = @"";
        instance.resValue = @"";
        instance.indexOfPattern = -1;
    }
    return instance;
}

- (BOOL) hasPatterns
{
    return self.patterns!=NULL && self.patterns.count > 0;
}

- (NSString*) getKeyName
{
    return self.resKeyword.length==0 ? self.name : self.resKeyword;
}

- (NSString*) getDisplayValue
{
    return self.resValue.length==0 ? DEFAULT_VALUE : self.resValue;
}

- (NSString*) getDisplayString: (BOOL) isDebug
{
    NSString *result = [NSString stringWithFormat:@"%@:%@", self.name, [self getDisplayValue]];
    if( isDebug )
        result = [NSString stringWithFormat:@"%@/%@/%ld", result, self.resKeyword, (self.indexOfPattern + 1)];
    
    return result;
}

- (BOOL) isSetValue
{
    return self.resValue.length > 0;
}

- (NSInteger) getIndexKeywords: (NSString*) string
{
    for(int i=0; i<self.keywords.count; i++){
        if( self.attribute) {
            if( [self checkContainKeyword:[self.keywords[i] objectAtIndex:0] Container:string] )
                return i;
        } else {
            if( [self matchMetaPhonetic: self.keywords[i] Container:string])
                return i;
        }
    }
    return -1;
}

- (BOOL) checkContainKeyword: (NSString*) key Container:(NSString*) container
{
    if ([container rangeOfString:key options:NSCaseInsensitiveSearch].location == NSNotFound) return false;
    
    if( key.length > 10 ) return true;
    
    NSError *error = NULL;
    NSString *strReg = [NSString stringWithFormat:@"[a-z0-9]%@", key];
    NSString *strReg1 = [NSString stringWithFormat:@"%@[a-z0-9]", key];
    NSArray *Regs = [NSArray arrayWithObjects:strReg, strReg1, nil];
    for( NSString *Reg in Regs){
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:Reg
                                                                               options:NSRegularExpressionCaseInsensitive
                                                                                 error:&error];
        
        NSUInteger numberOfMatches = [regex numberOfMatchesInString:container
                                                            options:0
                                                              range:NSMakeRange(0, [container length])];
        if(numberOfMatches > 0)
            return false;
    }
    
    return true;
}

- (BOOL) matchMetaPhonetic: (NSArray<NSString*>*) key Container:(NSString*) container
{
    NSString *phoneticKey = [key objectAtIndex:1];
    
    NSInteger wordCount = [[[key objectAtIndex:0] componentsSeparatedByString:@" "] count];
    NSMutableArray *words = [NSMutableArray arrayWithArray:[container componentsSeparatedByString:@" "]];
    [words removeObject:@""];
    if( words.count < wordCount ) return false;
    
    NSMutableArray<NSString*> *list = [[NSMutableArray alloc] init];
    for( int i=0; i<wordCount; i++){
        [list addObject:words[i]];
    }
    NSString *limitedString = [list componentsJoinedByString:@" "];
    NSString *phoneticText = [self.mMetaEngine getPhoneticText:limitedString];
    
    if( [phoneticKey caseInsensitiveCompare:phoneticText] == NSOrderedSame)
        return true;
    
    return false;
}

- (NSDictionary*) checkMatchValuePattern: (NSString*) string
{
    if( string==NULL || string.length==0 ) return NULL;
    if( self.patterns == NULL ) return NULL;
    
    NSMutableDictionary *resultMap = [NSMutableDictionary dictionary];
    NSString *res = @""; NSInteger num = -1;
    BOOL result = false;
    if( ![self hasPatterns] ){
        res = string;
        num = -1;
        result = true;
    } else {
        for (int i=0; i<self.patterns.count; i++) {
            NSString *pattern = self.patterns[i];
            NSError *error = NULL;
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                                   options:NSRegularExpressionCaseInsensitive
                                                                                     error:&error];
            
            NSRange rangeOfFirstMatch = [regex rangeOfFirstMatchInString:string
                                                                 options:0
                                                                   range:NSMakeRange(0, [string length])];
            if ( rangeOfFirstMatch.location != NSNotFound ) {
                NSString *substringForFirstMatch = [string substringWithRange:rangeOfFirstMatch];
                if( substringForFirstMatch.length > res.length){
                    res = substringForFirstMatch;
                    num = i;
                    result = true;
                }
            }
        }
    }
    if( result ){
        [resultMap setObject:res forKey:@"result_value"];
        [resultMap setObject:[NSNumber numberWithInteger:num] forKey:@"pattern_num"];
        return resultMap;
    }
    return NULL;
}

- (BOOL) setValueIfAcceptable: (NSString*) string
{
    if( self.attribute ){
        if( string != NULL && string.length!=0){
            if( self.resValue.length == 0){
                self.resValue = string;
                return true;
            }
        }
        return false;
    }
    
    NSDictionary *result = [self checkMatchValuePattern:string];
    if( result == NULL) return false;
    
    NSString *value = [result valueForKey:@"result_value"];
    if(value==NULL) value = @"";
    
    NSInteger num = -1;
    if([result valueForKey:@"pattern_num"] != NULL)
        num = [[result valueForKey:@"pattern_num"] integerValue];
    
    if( [self isSetValue] ){
        if( [value length] > [self.resValue length]){
            self.resValue = value;
            self.indexOfPattern = num;
            return true;
        }
    } else {
        self.resValue = value;
        self.indexOfPattern = num;
        return true;
    }
    
    return false;
}

@end
