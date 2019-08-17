/// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
/// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

#import <Cordova/CDVPluginResult.h>
#import <AbbyyRtrSDK/AbbyyRtrSDK.h>

#import "RTRTextCaptureViewController.h"
#import "RTRDataCaptureViewController.h"

extern NSString* const RTRCallbackErrorKey;
extern NSString* const RTRCallbackErrorDescriptionKey;
extern NSString* const RTRCallbackResultInfoKey;
extern NSString* const RTRCallbackUserActionKey;

@interface CDVPluginResult (RTRPluginResult)

+ (CDVPluginResult*)rtrResultWithError:(NSError*)error;
+ (CDVPluginResult*)rtrResultForTextCapture:(RTRTextCaptureViewController*)textCaptureController
	stoppedByUser:(BOOL)stoppedByUser;
+ (CDVPluginResult*)rtrResultForDataCapture:(RTRDataCaptureViewController*)dataCaptureController
	stoppedByUser:(BOOL)stoppedByUser;

@end
