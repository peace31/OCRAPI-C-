/// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
/// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

#import <UIKit/UIKit.h>
#import <AbbyyRtrSDK/AbbyyRtrSDK.h>
#import <Cordova/CDVPlugin.h>
#import "MetaEngineController.h"
#import "RTRManager.h"
#import "RTRSelectedAreaView.h"
#import "RTRProgressView.h"
#import "RTRPlugin.h"

typedef NS_ENUM(NSInteger, TLAction) {
    ACTION_NONE = 0,
    ACTION_DETECT = 1,
    ACTION_SELECT = 2
};
@interface TextLineAction : NSObject
+ (instancetype) initWithTextLine:(RTRTextLine*) text Action:(TLAction) action;

- (UIColor*) actionColor;

@property (nonatomic, strong) RTRTextLine* textLine;

@property (nonatomic, assign) TLAction action;

@end

@interface DetectionDictInfo : NSObject
+(instancetype)initInstance;

@property (nonatomic) OCRDictionary *ocrDict;
@property (nonatomic, assign) BOOL bSelected;
@property (nonatomic, assign) NSInteger mHeightRate;
@property (nonatomic, assign) NSInteger mIndexOfKey;
@property (nonatomic, strong) TextLineAction *mKeyText;
//@property (nonatomic, assign) NSInteger mIndexInKeyBlock;
@end

extern void performBlockOnMainThread(NSInteger delay, void(^block)());

@interface RTRViewController : UIViewController <RTRRecognitionServiceDelegate, UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, weak) RTRManager* rtrManager;
@property (nonatomic) id<RTRRecognitionService> service;

/// Image size.
@property (nonatomic, assign) CGSize imageBufferSize;

@property (nonatomic, copy) void (^onCancel)();
@property (nonatomic, copy) void (^onSuccess)(BOOL isManuallyStopped);
@property (nonatomic, copy) void (^onDetectText)();

@property (nonatomic) BOOL stopWhenStable;
@property (nonatomic, getter=isFlashlightVisible) BOOL isFlashlightVisible;
@property (nonatomic, getter=isStopButtonVisible) BOOL stopButtonVisible;
@property (nonatomic, getter=isLanguageSelectionEnabled) BOOL languageSelectionEnabled;
@property (nonatomic) CGSize areaOfInterestRatio;
@property (nonatomic, assign, getter=isDebugMode) BOOL isDebugMode;
@property (nonatomic, strong, getter=country) NSString *countryName;
@property (nonatomic, strong, getter=dictArray) NSArray *dictArray;
@property (nonatomic, strong, getter=metaEngineId) NSString *metaEngineId;

@property (nonatomic) NSArray* settingsTableContent;

@property (nonatomic, assign) RTRResultStabilityStatus currentStabilityStatus;
@property (nonatomic, strong) NSString* errorOccurred;

/// Is recognition running.
@property (atomic, assign, getter=isRunning) BOOL running;

/// Capture settings table.
@property (nonatomic, weak) IBOutlet UITableView* settingsTableView;
/// Button for show / hide table with recognition languages.
@property (nonatomic, weak) IBOutlet UIButton* settingsButton;
/// Button for switching flash mode.
@property (nonatomic, weak) IBOutlet UIButton* flashButton;

/// View with camera preview layer.
@property (nonatomic, weak) IBOutlet UIView* previewView;
/// Stop/Start capture button
@property (nonatomic, weak) IBOutlet UIButton* captureButton;

/// View for displaying current area of interest.
@property (nonatomic, weak) IBOutlet RTRSelectedAreaView* overlayView;
/// White view for highlight recognition results.
@property (nonatomic, weak) IBOutlet UIView* whiteBackgroundView;

/// Label for current scenario description.
@property (nonatomic, weak) IBOutlet UILabel* descriptionLabel;
/// Label for error or warning info.
@property (nonatomic, weak) IBOutlet UILabel* infoLabel;
/// Progress indicator view.
@property (nonatomic, weak) IBOutlet RTRProgressView* progressIndicatorView;

@property (nonatomic, strong) NSMutableArray<DetectionDictInfo*> *mDictInfoList;

@property (nonatomic, strong) MetaEngineController *mMetaEngine;;

- (IBAction)capturePressed;
- (IBAction)toggleSettingsTableVisibility;
- (IBAction)toggleFlashMode;

- (void)drawTextLines:(NSArray*)textLines progress:(RTRResultStabilityStatus)progress;
- (void)drawTextLinesAction:(NSArray*)linesAction;
- (void)drawTextRegionsFromDataFields:(NSArray*)dataFields progress:(RTRResultStabilityStatus)progress;
- (void)drawResultText:(NSMutableArray<DetectionDictInfo*>*) dictInfo;

- (void)prepareUIForRecognition;
- (void)updateAreaOfInterest;

- (UITableViewCell*)tableViewCellWithConfiguration:(void (^)(UITableViewCell* cell))configurationHandler;
- (void)findKeywords:(NSArray<TextLineAction*>*) linesAction;
- (void)findValues:(NSArray<TextLineAction*>*) linesAction;

- (void)updateLogMessage:(NSString*)message;
- (UIColor*)progressColor:(RTRResultStabilityStatus)progress;

-(void) initMetaPhoneEngine;
-(void) initDetectionDictInfo;
@end
