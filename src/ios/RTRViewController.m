/// ABBYY® Real-Time Recognition SDK 1 © 2016 ABBYY Production LLC.
/// ABBYY is either a registered trademark or a trademark of ABBYY Software Ltd.

#import "RTRViewController.h"
#import <AVFoundation/AVFoundation.h>

/// Cell ID for languagesTableView.
static NSString* const RTRTableCellID = @"RTRTableCellID";
/// Name for text region layers.
static NSString* const RTRTextRegionLayerName = @"RTRTextRegionLayerName";
/// Name for result text region layers.
static NSString* const ResultTextRegionLayerName = @"ResultTextRegionLayerName";

/// Shortcut. Perform block asynchronously on main thread.
void performBlockOnMainThread(NSInteger delay, void(^block)())
{
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

@interface RTRViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, weak) IBOutlet UIVisualEffectView* topBar;

@property (nonatomic) AVCaptureDevice* captureDevice;

@end

#pragma mark -

@implementation RTRViewController {
	/// Camera session.
	AVCaptureSession* _session;
	/// Video preview layer.
	AVCaptureVideoPreviewLayer* _previewLayer;
	/// Session Preset.
	NSString* _sessionPreset;

	/// Area of interest in view coordinates.
	CGRect _selectedArea;
    /// POSTAL code according country
    NSDictionary *_POSTAL_CODES;
}

#pragma mark - UIView LifeCycle

- (instancetype)init
{
    [self initPostalCodes];
	return [self initWithNibName:NSStringFromClass([RTRViewController class]) bundle:NSBundle.mainBundle];
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	// Recommended session preset.
	_sessionPreset = AVCaptureSessionPreset1280x720;
	_imageBufferSize = CGSizeMake(720.f, 1280.f);

	[self.settingsTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:RTRTableCellID];
	self.settingsTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

	[self prepareUIForRecognition];

	self.captureButton.hidden = !self.isStopButtonVisible;
	self.captureButton.selected = NO;

	self.flashButton.hidden = !self.isFlashlightVisible;
	if(!self.isFlashlightVisible && !self.isLanguageSelectionEnabled) {
		self.topBar.hidden = YES;
	}

	self.settingsTableView.hidden = YES;

	__weak RTRViewController* weakSelf = self;
	[self authorizeCameraDeviceWithCompletion:^(BOOL isGranted) {
		performBlockOnMainThread(0, ^{
			[weakSelf configureCompletionAccessGranted:isGranted];
		});
	}];

	_currentStabilityStatus = RTRResultStabilityNotReady;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
	[super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

	BOOL wasRunning = self.isRunning;
	self.running = NO;
	[self.service stopTasks];
	[self clearScreenFromRegions];

	[coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context)
	{
		_imageBufferSize = CGSizeMake(MIN(_imageBufferSize.width, _imageBufferSize.height),
			MAX(_imageBufferSize.width, _imageBufferSize.height));
		if(UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation)) {
			_imageBufferSize = CGSizeMake(_imageBufferSize.height, _imageBufferSize.width);
		 }

		[self updateAreaOfInterest];
		self.running = wasRunning;
	}];
}

- (void)authorizeCameraDeviceWithCompletion:(void (^)(BOOL isGranted))completion
{
	AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
	switch(status) {
		case AVAuthorizationStatusAuthorized:
			completion(YES);
			break;
		case AVAuthorizationStatusNotDetermined:
			[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:completion];
			break;
		case AVAuthorizationStatusRestricted:
		case AVAuthorizationStatusDenied:
			completion(NO);
			break;
	}
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return UIInterfaceOrientationPortrait;
}

- (void)configureCompletionAccessGranted:(BOOL)accessGranted
{
	NSString* error;
	if(![UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceRear]) {
		error = @"Device has no camera";
	} else if(!accessGranted) {
		error = @"Camera access denied";
	}
	if(error != nil) {
		self.errorOccurred = error;
		[self updateLogMessage:error];
		self.captureButton.enabled = NO;
		self.captureButton.hidden = YES;
		return;
	}

	[self configureAVCaptureSession];
	[self configurePreviewLayer];
	[_session startRunning];
	[self capturePressed];

	[[NSNotificationCenter defaultCenter] addObserver:self selector: @selector(avSessionFailed:)
		name: AVCaptureSessionRuntimeErrorNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector: @selector(applicationDidEnterBackground)
		name: UIApplicationDidEnterBackgroundNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector: @selector(applicationWillEnterForeground)
		name: UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)updateAreaOfInterest
{
	// Scale area of interest from view coordinate system to image coordinates.
	CGRect selectedRect = CGRectApplyAffineTransform(_selectedArea,
		CGAffineTransformMakeScale(_imageBufferSize.width * 1.f / CGRectGetWidth(_overlayView.frame),
		_imageBufferSize.height * 1.f / CGRectGetHeight(_overlayView.frame)));

	[self.service setAreaOfInterest:selectedRect];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[_session stopRunning];
	self.running = NO;
	self.captureButton.selected = NO;
	[_service stopTasks];

	[super viewWillDisappear:animated];
}

- (BOOL)prefersStatusBarHidden
{
	return YES;
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];

	[self updatePreviewLayerFrame];
}

- (void)updatePreviewLayerFrame
{
	UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
	[_previewLayer.connection setVideoOrientation:[self videoOrientationFromInterfaceOrientation:orientation]];

	CGRect viewBounds = self.view.bounds;

	_previewLayer.frame = viewBounds;

	CGFloat widthMargin = CGRectGetWidth(viewBounds) * (1 - self.areaOfInterestRatio.width) / 2;
	CGFloat heigthMargin = CGRectGetHeight(viewBounds) * (1 - self.areaOfInterestRatio.height) / 2;
	self.selectedArea = CGRectInset(viewBounds, widthMargin, heigthMargin);

	[self updateAreaOfInterest];
}

- (void)setSelectedArea:(CGRect)selectedArea
{
	_selectedArea = selectedArea;
	_overlayView.selectedArea = _selectedArea;
}

- (AVCaptureVideoOrientation)videoOrientationFromInterfaceOrientation:(UIInterfaceOrientation)orientation
{
	AVCaptureVideoOrientation result = AVCaptureVideoOrientationPortrait;
	switch(orientation) {
		case UIInterfaceOrientationPortrait:
			result = AVCaptureVideoOrientationPortrait;
			break;
		case UIInterfaceOrientationPortraitUpsideDown:
			result = AVCaptureVideoOrientationPortraitUpsideDown;
			break;
		case UIInterfaceOrientationLandscapeLeft:
			result = AVCaptureVideoOrientationLandscapeLeft;
			break;
		case UIInterfaceOrientationLandscapeRight:
			result = AVCaptureVideoOrientationLandscapeRight;
			break;
		default:
			break;
	}

	return result;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)applicationDidEnterBackground
{
	[_session stopRunning];
	[self.service stopTasks];
}

- (void)applicationWillEnterForeground
{
	[_session startRunning];
}

#pragma mark - Actions

- (IBAction)capturePressed
{
	if(!self.captureButton.enabled) {
		return;
	}

	self.captureButton.selected = !self.captureButton.selected;
	self.running = self.captureButton.selected;

	if(self.isRunning) {
		[self prepareUIForRecognition];
		self.errorOccurred = nil;
	} else {
		[self.service stopTasks];
		if(self.onSuccess != nil) {
			const BOOL StoppedByUser = YES;
			self.onSuccess(StoppedByUser);
		}
	}
}

- (IBAction)toggleSettingsTableVisibility
{
	BOOL state = self.settingsTableView.hidden;
	self.running = !state;
	self.captureButton.selected = !state;
	if(state) {
		[self.service stopTasks];
		[self.settingsTableView reloadData];
	}

	self.settingsTableView.hidden = !state;
	[self prepareUIForRecognition];
}

- (IBAction)toggleFlashMode
{
	if([self.captureDevice isTorchModeSupported:AVCaptureTorchModeOn]) {
		self.flashButton.selected = !self.flashButton.selected;
		[self.captureDevice lockForConfiguration:nil];
		self.captureDevice.torchMode = (self.flashButton.selected) ? AVCaptureTorchModeOn : AVCaptureTorchModeOff;
		[self.captureDevice unlockForConfiguration];
	}
}

- (IBAction)closeViewController
{
	self.captureButton.selected = NO;
	[self.service stopTasks];
	self.running = NO;

	if(self.onCancel != nil) {
		self.onCancel();
	}
}

- (void)prepareUIForRecognition
{
	[self clearScreenFromRegions];
	self.whiteBackgroundView.hidden = YES;
    RTRResultStabilityStatus status = RTRResultStabilityNotReady;
	[self.progressIndicatorView setProgress:0 color:[self progressColor:status]];
	[self updateLogMessage:nil];
    
    if( !self.isDebugMode ) self.progressIndicatorView.hidden = YES;
}

#pragma mark - AVCapture configuration

- (void)configureAVCaptureSession
{
	NSError* error = nil;
	_session = [[AVCaptureSession alloc] init];
	[_session setSessionPreset:_sessionPreset];

	self.captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:self.captureDevice error:&error];
	if(error != nil) {
		NSLog(@"%@", [error localizedDescription]);
		self.errorOccurred = error.localizedDescription;
		[self updateLogMessage:error.localizedDescription];
		return;
	}
	NSAssert([_session canAddInput:input], @"impossible to add AVCaptureDeviceInput");
	[_session addInput:input];

	AVCaptureVideoDataOutput* videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
	dispatch_queue_t videoDataOutputQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	[videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
	[videoDataOutput alwaysDiscardsLateVideoFrames];
	videoDataOutput.videoSettings = [NSDictionary dictionaryWithObject:
		[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
		forKey:(id)kCVPixelBufferPixelFormatTypeKey];
	NSAssert([_session canAddOutput:videoDataOutput], @"impossible to add AVCaptureVideoDataOutput");
	[_session addOutput:videoDataOutput];

	[[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];
}

- (void)configurePreviewLayer
{
	_previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_session];
	_previewLayer.backgroundColor = [[UIColor blackColor] CGColor];
	_previewLayer.videoGravity = AVLayerVideoGravityResize;
	CALayer* rootLayer = [self.previewView layer];
	[rootLayer insertSublayer:_previewLayer atIndex:0];

	[self updatePreviewLayerFrame];
}

- (void)avSessionFailed:(NSNotification*)notification
{
	NSError* error = notification.userInfo[AVCaptureSessionErrorKey];
	__weak RTRViewController* weakSelf = self;
	performBlockOnMainThread(0, ^{
		weakSelf.errorOccurred = error.localizedDescription;
		[weakSelf updateLogMessage:error.localizedDescription];
	});
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
	fromConnection:(AVCaptureConnection*)connection
{
	if(!self.isRunning) {
		return;
	}

	AVCaptureVideoOrientation videoOrientation = [self videoOrientationFromInterfaceOrientation:
		[UIApplication sharedApplication].statusBarOrientation];
	if(connection.videoOrientation != videoOrientation) {
		[connection setVideoOrientation:videoOrientation];
		return;
	}

	[self.service addSampleBuffer:sampleBuffer];
}

#pragma mark -

- (void)initPostalCodes
{
    NSArray *australia = [NSArray arrayWithObjects:@"VIC[\\s]*[0-9]{4}$",
                          @"NSW[\\s]*[0-9]{4}$",
                          @"QLD[\\s]*[0-9]{4}$",
                          @"NT[\\s]*[0-9]{4}$",
                          @"WA[\\s]*[0-9]{4}$",
                          @"SA[\\s]*[0-9]{4}$",
                          @"TAS[\\s]*[0-9]{4}$",
                          nil];
    _POSTAL_CODES = [NSDictionary dictionaryWithObject:australia forKey:@"Australia"];
}

- (void)initMetaPhoneEngine
{
    _mMetaEngine = [MetaEngineController initWithEngineId:self.metaEngineId];
}

- (void)initDetectionDictInfo
{
    _mDictInfoList = [NSMutableArray array];
    for( int i=0; i<self.dictArray.count; i++){
        [self.mDictInfoList addObject:[DetectionDictInfo initInstance]];
        self.mDictInfoList[i].ocrDict = [OCRDictionary initWithDictionary:self.dictArray[i] MetaEngine:self.mMetaEngine];
    }
}

- (void)updateLogMessage:(NSString*)message
{
	__weak RTRViewController* weakSelf = self;
	performBlockOnMainThread(0, ^{
		weakSelf.infoLabel.text = message;
	});
}

#pragma mark - Drawing results

/// Drawing text lines.
- (void)drawTextLines:(NSArray*)textLines progress:(RTRResultStabilityStatus)progress
{
	[self clearScreenFromRegions];
	
	CALayer* textRegionsLayer = [[CALayer alloc] init];
	textRegionsLayer.frame = _previewLayer.frame;
	textRegionsLayer.name = RTRTextRegionLayerName;

	for(RTRTextLine* textLine in textLines) {
		[self drawTextLine:textLine inLayer:textRegionsLayer progress:progress];
	}
	
	[self.previewView.layer addSublayer:textRegionsLayer];
}

- (void)drawTextLinesAction:(NSArray*)linesAction
{
    [self clearScreenFromRegions];
    
    CALayer* textRegionsLayer = [[CALayer alloc] init];
    textRegionsLayer.frame = _previewLayer.frame;
    textRegionsLayer.name = RTRTextRegionLayerName;
    
    for(TextLineAction* action in linesAction) {
        if( action.action == ACTION_NONE && ![self isDebugMode]) continue;
        [self drawTextLineAction:action inLayer:textRegionsLayer];
    }
    
    [self.previewView.layer addSublayer:textRegionsLayer];
}

- (void)drawResultText:(NSMutableArray<DetectionDictInfo*>*) dictInfo
{
    if( !self.isDebugMode ) return;
    // Get all visible regions.
    NSArray* sublayers = [NSArray arrayWithArray:[self.previewView.layer sublayers]];
    
    CALayer *resultLayer = NULL;
    for(CALayer* layer in sublayers) {
        if([[layer name] isEqualToString:ResultTextRegionLayerName]) {
            resultLayer = layer;
            for( DetectionDictInfo *item in dictInfo)
            {
                if( !item.bSelected ) continue;
                
                for( CATextLayer *layer in [resultLayer sublayers])
                {
                    if( layer.name == item.ocrDict.name){
                        layer.string = [item.ocrDict getDisplayString:[self isDebugMode]];
                        break;
                    }
                }
            }
            break;
        }
    }
    
    if( resultLayer == NULL ){
        CALayer* resultLayer = [CALayer layer];
        resultLayer.frame = _previewLayer.frame;
        resultLayer.name = ResultTextRegionLayerName;
        
        CGFloat offsetX = 10;
        CGFloat offsetY = 50;
        for( DetectionDictInfo *item in dictInfo)
        {
            CATextLayer* textLayer = [CATextLayer layer];
            // Creating the text layer rectangle: it should be close to the quadrangle drawn previously.
            
            // Selecting the initial font size to suit the rectangle size.
            textLayer.foregroundColor = [[UIColor whiteColor] CGColor];
            textLayer.string = [item.ocrDict getDisplayString:[self isDebugMode]];
            CGFloat width = MAX(self.view.bounds.size.width, self.view.bounds.size.height);
            textLayer.frame = CGRectMake(offsetX, offsetY, width-offsetX*2, 40);
            textLayer.alignmentMode = kCAAlignmentLeft;
            textLayer.name = item.ocrDict.name;
            textLayer.fontSize = 20;
            offsetY += 25;
            [resultLayer addSublayer:textLayer];
        }
        [self.previewView.layer addSublayer:resultLayer];
    }
}

/// Drawing data fields.
- (void)drawTextRegionsFromDataFields:(NSArray*)dataFields progress:(RTRResultStabilityStatus)progress
{
	[self clearScreenFromRegions];
	
	CALayer* textRegionsLayer = [[CALayer alloc] init];
	textRegionsLayer.frame = _previewLayer.frame;
	textRegionsLayer.name = RTRTextRegionLayerName;
	
	for(RTRDataField* dataField in dataFields) {
		for(RTRTextLine* textLine in dataField.components) {
			[self drawTextLine:textLine inLayer:textRegionsLayer progress:progress];
		}
	}
	
	[self.previewView.layer addSublayer:textRegionsLayer];
}

/// Remove all previously visible regions.
- (void)clearScreenFromRegions
{
	// Get all visible regions.
	NSArray* sublayers = [NSArray arrayWithArray:[self.previewView.layer sublayers]];
	
	// Remove all layers with the name RTRTextRegionLayerName.
	for(CALayer* layer in sublayers) {
		if([[layer name] isEqualToString:RTRTextRegionLayerName]) {
			[layer removeFromSuperlayer];
		}
	}
}

/// Drawing the quadrangle specified by the RTRTextLine object 
/// and a separate recognized text layer, if there is any recognized text.
- (void)drawTextLine:(RTRTextLine*)textLine inLayer:(CALayer*)layer progress:(RTRResultStabilityStatus)progress
{
	[self drawQuadrangle:textLine.quadrangle inLayer:layer Color:[self progressColor:progress]];

	NSString* recognizedString = textLine.text;
	if(recognizedString == nil) {
		return;
	}
	
	CATextLayer* textLayer = [CATextLayer layer];
	// Creating the text layer rectangle: it should be close to the quadrangle drawn previously.
	CGPoint topLeft = [self scaledPointFromImagePoint:textLine.quadrangle[0]];
	CGPoint bottomLeft = [self scaledPointFromImagePoint:textLine.quadrangle[1]];
	CGPoint bottomRight = [self scaledPointFromImagePoint:textLine.quadrangle[2]];
	CGPoint topRight = [self scaledPointFromImagePoint:textLine.quadrangle[3]];
	CGRect rectForTextLayer = CGRectMake(bottomLeft.x, bottomLeft.y,
		[self distanceBetweenPoint:topLeft andPoint:topRight],
		[self distanceBetweenPoint:topLeft andPoint:bottomLeft]);

	// Selecting the initial font size to suit the rectangle size.
	UIFont* textFont = [self fontForString:recognizedString inRect:rectForTextLayer];
	textLayer.font = (__bridge CFTypeRef)textFont;
	textLayer.fontSize = textFont.pointSize;
	textLayer.foregroundColor = [[self progressColor:progress] CGColor];
	textLayer.alignmentMode = kCAAlignmentCenter;
	textLayer.string = recognizedString;
	textLayer.frame = rectForTextLayer;
	
	// Rotating the text layer.
	CGFloat angle = asin((bottomRight.y - bottomLeft.y) / [self distanceBetweenPoint:bottomLeft andPoint:bottomRight]);
	textLayer.anchorPoint = CGPointMake(0.f, 0.f);
	textLayer.position = bottomLeft;
	CATransform3D t = CATransform3DIdentity;
	t = CATransform3DRotate(t, angle, 0.f, 0.f, 1.f);
	textLayer.transform = t;
	
	[layer addSublayer:textLayer];
}

- (void)drawTextLineAction:(TextLineAction*)action inLayer:(CALayer*)layer
{
    [self drawQuadrangle:action.textLine.quadrangle inLayer:layer Color:[action actionColor]];
    
    NSString* recognizedString = action.textLine.text;
    if(recognizedString == nil) {
        return;
    }
    
    CATextLayer* textLayer = [CATextLayer layer];
    // Creating the text layer rectangle: it should be close to the quadrangle drawn previously.
    CGPoint topLeft = [self scaledPointFromImagePoint:action.textLine.quadrangle[0]];
    CGPoint bottomLeft = [self scaledPointFromImagePoint:action.textLine.quadrangle[1]];
    CGPoint bottomRight = [self scaledPointFromImagePoint:action.textLine.quadrangle[2]];
    CGPoint topRight = [self scaledPointFromImagePoint:action.textLine.quadrangle[3]];
    CGRect rectForTextLayer = CGRectMake(bottomLeft.x, bottomLeft.y,
                                         [self distanceBetweenPoint:topLeft andPoint:topRight],
                                         [self distanceBetweenPoint:topLeft andPoint:bottomLeft]);
    
    // Selecting the initial font size to suit the rectangle size.
    UIFont* textFont = [self fontForString:recognizedString inRect:rectForTextLayer];
    textLayer.font = (__bridge CFTypeRef)textFont;
    textLayer.fontSize = textFont.pointSize;
    textLayer.foregroundColor = [[action actionColor] CGColor];
    textLayer.alignmentMode = kCAAlignmentCenter;
    textLayer.string = recognizedString;
    textLayer.frame = rectForTextLayer;
    
    // Rotating the text layer.
    CGFloat angle = asin((bottomRight.y - bottomLeft.y) / [self distanceBetweenPoint:bottomLeft andPoint:bottomRight]);
    textLayer.anchorPoint = CGPointMake(0.f, 0.f);
    textLayer.position = bottomLeft;
    CATransform3D t = CATransform3DIdentity;
    t = CATransform3DRotate(t, angle, 0.f, 0.f, 1.f);
    textLayer.transform = t;
    
    [layer addSublayer:textLayer];
}

/// Drawing a UIBezierPath using the quadrangle vertices.
- (void)drawQuadrangle:(NSArray<NSValue*>*)quadrangle inLayer:(CALayer*)layer Color:(UIColor*)color
{
	if(quadrangle.count == 0) {
		return;
	}

	CAShapeLayer* area = [CAShapeLayer layer];
	UIBezierPath* recognizedAreaPath = [UIBezierPath bezierPath];
	[quadrangle enumerateObjectsUsingBlock:^(NSValue* point, NSUInteger idx, BOOL* stop) {
		CGPoint scaledPoint = [self scaledPointFromImagePoint:point];
		if(idx == 0) {
			[recognizedAreaPath moveToPoint:scaledPoint];
		} else {
			[recognizedAreaPath addLineToPoint:scaledPoint];
		}
	}];

	[recognizedAreaPath closePath];
	area.path = recognizedAreaPath.CGPath;
	area.strokeColor = [color CGColor];
	area.fillColor = [UIColor clearColor].CGColor;
	[layer addSublayer:area];
}

- (UIFont*)fontForString:(NSString*)string inRect:(CGRect)rect
{
	// Selecting the font size by height and then fine-tuning by width.

	CGFloat minFontSize = 0.1f; // initial font size
	CGFloat maxFontSize = 72.f;
	CGFloat fontSize = minFontSize;

	CGSize rectSize = rect.size;
	for(;;) {
		CGSize labelSize = [string sizeWithAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:fontSize]}];
		if(rectSize.height - labelSize.height > 0) {
			minFontSize = fontSize;

			if(0.99f * rectSize.height - labelSize.height < 0) {
				break;
			}
		} else {
			maxFontSize = fontSize;
		}

		if(ABS(minFontSize - maxFontSize) < 0.01) {
			break;
		}

		fontSize = (minFontSize + maxFontSize) / 2;
	}

	return [UIFont boldSystemFontOfSize:fontSize];
}

/// Calculate the distance between points.
- (CGFloat)distanceBetweenPoint:(CGPoint)p1 andPoint:(CGPoint)p2
{
	CGVector vector = CGVectorMake(p2.x - p1.x, p2.y - p1.y);
	return sqrt(vector.dx * vector.dx + vector.dy * vector.dy);
}

/// Scale the point coordinates.
- (CGPoint)scaledPointFromImagePoint:(NSValue*)pointValue
{
	CGFloat layerWidth = _previewLayer.bounds.size.width;
	CGFloat layerHeight = _previewLayer.bounds.size.height;
	
	CGFloat widthScale = layerWidth / _imageBufferSize.width;
	CGFloat heightScale = layerHeight / _imageBufferSize.height;
	
	CGPoint point = [pointValue CGPointValue];
	point.x *= widthScale;
	point.y *= heightScale;
	
	return point;
}

/// Human-readable descriptions for the RTRCallbackWarningCode constants.
- (NSString*)stringFromWarningCode:(RTRCallbackWarningCode)warningCode
{
	NSString* warningString;
	switch(warningCode) {
		case RTRCallbackWarningTextTooSmall:
			warningString = @"Text is too small";
			break;

		default:
			break;
	}

	return warningString;
}

#pragma mark - Utils

#define RTRUIColorFromRGB(rgbValue) [UIColor \
	colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 \
	green:((float)((rgbValue & 0xFF00) >> 8))/255.0 \
	blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]

- (UIColor*)progressColor:(RTRResultStabilityStatus)progress
{
	switch(progress) {
		case RTRResultStabilityNotReady:
		case RTRResultStabilityTentative:
			return RTRUIColorFromRGB(0xFF6500);
		case RTRResultStabilityVerified:
			return RTRUIColorFromRGB(0xC96500);
		case RTRResultStabilityAvailable:
			return RTRUIColorFromRGB(0x886500);
		case RTRResultStabilityTentativelyStable:
			return RTRUIColorFromRGB(0x4B6500);
		case RTRResultStabilityStable:
			return RTRUIColorFromRGB(0x006500);

		default:
			return [UIColor redColor];
			break;
	}
}

- (UITableViewCell*)tableViewCellWithConfiguration:(void (^)(UITableViewCell* cell))configurationHandler
{
	UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4f];
	cell.textLabel.textColor = [UIColor whiteColor];
	cell.detailTextLabel.textColor = [UIColor lightGrayColor];
	cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
	cell.tintColor = [UIColor whiteColor];

	configurationHandler(cell);
	
	return cell;
}

- (void)findKeywords:(NSArray<TextLineAction*>*) linesAction
{
    for(int i=0; i<linesAction.count; i++){
        TextLineAction *item = linesAction[i];
        for (DetectionDictInfo *info in self.mDictInfoList) {
            OCRDictionary *dict = info.ocrDict;
            NSString *text = item.textLine.text;
            NSInteger inxKey = [dict getIndexKeywords:text];
            if (inxKey > -1) {
                info.mKeyText = item;
                info.mIndexOfKey = inxKey;
                item.action = ACTION_DETECT;
                //break;
            }
        }
    }
}

- (void)findValues:(NSArray<TextLineAction*>*) linesAction
{
    for (DetectionDictInfo *info in self.mDictInfoList) {
        
        if( [self checkAttribute:info] ) continue;
        
        if( [self findValueInText:info] ) continue;
        
        if( [self findValueInRight:info Actions:linesAction] ) continue;
        
        if( [self findValueInBelow:info Actions:linesAction] ) continue;
        
        if( [self findServiceAddressEx:info Actions:linesAction]) continue;
    }
}

- (NSInteger) getRateFromRTRResultStability:(RTRResultStabilityStatus) status
{
    NSInteger rate = 0;
    switch ( status ) {
        case RTRResultStabilityNotReady:
            rate = 0;
            break;
        case RTRResultStabilityTentative:
            rate = 1;
            break;
        case RTRResultStabilityVerified:
            rate = 2;
            break;
        case RTRResultStabilityAvailable:
            rate = 3;
            break;
        case RTRResultStabilityTentativelyStable:
            rate = 4;
            break;
        case RTRResultStabilityStable:
            rate = 5;
            break;
    }
    return rate;
}

- (BOOL)checkAttribute:(DetectionDictInfo*) dictInfo
{
    if( !dictInfo.ocrDict.attribute ) return false;
    if( dictInfo.mKeyText == NULL ) return false;
    
    NSInteger rate = [self getRateFromRTRResultStability:self.currentStabilityStatus];
    NSString *keyword = [dictInfo.ocrDict.keywords[dictInfo.mIndexOfKey] objectAtIndex:0];
    if( [dictInfo.ocrDict setValueIfAcceptable:keyword]) {
        dictInfo.mHeightRate = rate;
        dictInfo.bSelected = true;
        dictInfo.ocrDict.resKeyword = keyword;
        dictInfo.mKeyText.action = ACTION_SELECT;
        NSLog(@"checkAttribute: A new Value:%@", [dictInfo.ocrDict getDisplayString:YES]);
    }
    return true;
}

- (BOOL)findValueInText:(DetectionDictInfo*) dictInfo
{
    NSInteger rate = [self getRateFromRTRResultStability:self.currentStabilityStatus];
    
    if( dictInfo.mKeyText == NULL ) return false;
    if( dictInfo.mIndexOfKey < 0 ) return false;
    
    NSString *strContainer = dictInfo.mKeyText.textLine.text;
    NSString* key = [dictInfo.ocrDict.keywords[dictInfo.mIndexOfKey] objectAtIndex:0];
    NSRange range = [strContainer rangeOfString:key options:NSCaseInsensitiveSearch];
    
    if(range.location == NSNotFound) return false;
    
    range = NSMakeRange(range.location+range.length, strContainer.length-range.location-range.length);
    NSString *value = [ [strContainer substringWithRange:range]
                       stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if( [dictInfo.ocrDict checkMatchValuePattern:value] != NULL) {
        
        if (dictInfo.mHeightRate<=rate && [dictInfo.ocrDict setValueIfAcceptable:value]) {
            dictInfo.mHeightRate = rate;
            dictInfo.bSelected = true;
            dictInfo.ocrDict.resKeyword = key;
            dictInfo.mKeyText.action = ACTION_SELECT;
            NSLog(@"find_value_in_text: A new Value:%@", [dictInfo.ocrDict getDisplayString:YES]);
        }
        return true;
    }
    
    return false;
}

- (BOOL)findValueInRight:(DetectionDictInfo*) dictInfo Actions:(NSArray<TextLineAction*>*) lines
{   
    NSInteger rate = [self getRateFromRTRResultStability:self.currentStabilityStatus];
    
    if( dictInfo.mKeyText == NULL ) return false;
    
    RTRTextLine *keyword = dictInfo.mKeyText.textLine;
    
    CGPoint keyBL = [keyword.quadrangle[0] CGPointValue];
    CGPoint keyTL = [keyword.quadrangle[1] CGPointValue];
    CGPoint keyTR = [keyword.quadrangle[2] CGPointValue];
    CGPoint keyBR = [keyword.quadrangle[3] CGPointValue];
    //middle points
    CGPoint keyML = CGPointMake((keyBL.x+keyTL.x)/2, (keyBL.y+keyTL.y)/2);
    CGPoint keyMR = CGPointMake((keyBR.x+keyTR.x)/2, (keyBR.y+keyTR.y)/2);
    float limit = (keyBL.y - keyTL.y)/2;
    //Middle line of keyword text rect y = A * x + B
    float A = (keyML.y - keyMR.y)/(keyML.x - keyMR.x);
    float B = (keyML.x*keyMR.y - keyML.y*keyMR.x) / (keyML.x - keyMR.x);
    
    TextLineAction *rightText = NULL;
    for (TextLineAction* textAction in lines) {
        
        CGPoint textBL = [textAction.textLine.quadrangle[0] CGPointValue];
        CGPoint textTL = [textAction.textLine.quadrangle[1] CGPointValue];
        CGPoint textTR = [textAction.textLine.quadrangle[2] CGPointValue];
        CGPoint textBR = [textAction.textLine.quadrangle[3] CGPointValue];
        //middle points
        CGPoint textML = CGPointMake((textBL.x+textTL.x)/2, (textBL.y+textTL.y)/2);
        CGPoint textMR = CGPointMake((textBR.x+textTR.x)/2, (textBR.y+textTR.y)/2);
        
        if( keyMR.x > textML.x ) continue;
        
        float estimatLeftY = A * textML.x + B;
        if( fabs(estimatLeftY-textML.y) > limit ) continue;
        
        float estimatRightY = A * textMR.x + B;
        if( fabs(estimatRightY-textMR.y) > limit ) continue;
        
        if( rightText==NULL ){
            rightText = textAction;
        } else if( [rightText.textLine.quadrangle[0] CGPointValue].x > [textAction.textLine.quadrangle[0] CGPointValue].x){
            rightText = textAction;
        }
    }
    
    if( rightText == NULL ) return false;
    
    if( [dictInfo.ocrDict checkMatchValuePattern:rightText.textLine.text] != NULL) {
        rightText.action = ACTION_DETECT;
        if( dictInfo.mIndexOfKey < 0) dictInfo.ocrDict.resValue=@"";
        
        if (dictInfo.mHeightRate<=rate && [dictInfo.ocrDict setValueIfAcceptable:rightText.textLine.text]) {
            dictInfo.mHeightRate = rate;
            dictInfo.bSelected = true;
            dictInfo.ocrDict.resKeyword = [dictInfo.ocrDict.keywords[dictInfo.mIndexOfKey] objectAtIndex:0];
            rightText.action = ACTION_SELECT;
            dictInfo.mKeyText.action = ACTION_SELECT;
            NSLog(@"find_value_in_right: %@", [dictInfo.ocrDict getDisplayString:YES]);
        }
        return true;
    }
    return false;
}

- (BOOL)findValueInBelow:(DetectionDictInfo*) dictInfo Actions:(NSArray<TextLineAction*>*) lines
{
    NSInteger rate = [self getRateFromRTRResultStability:self.currentStabilityStatus];
 
    if( dictInfo.mKeyText == NULL ) return false;
    if( ![dictInfo.ocrDict hasPatterns] ) return false;
    
    RTRTextLine *keyword = dictInfo.mKeyText.textLine;
    
    CGPoint keyBL = [keyword.quadrangle[0] CGPointValue];
    CGPoint keyTL = [keyword.quadrangle[1] CGPointValue];
    CGPoint keyBR = [keyword.quadrangle[3] CGPointValue];
    float limit = (keyBL.y - keyTL.y)/2;
    //Bottom line of keyword text rect y = A * x + B
    float A = (keyBL.y - keyBR.y)/(keyBL.x - keyBR.x);
    float B = (keyBL.x*keyBR.y - keyBL.y*keyBR.x) / (keyBL.x - keyBR.x);
    
    TextLineAction *belowText = NULL;
    for( TextLineAction* textAction in lines) {
        CGPoint textTL = [textAction.textLine.quadrangle[1] CGPointValue];
        CGPoint textTR = [textAction.textLine.quadrangle[2] CGPointValue];
        
        float estimatLY = A * textTL.x + B;
        if( estimatLY > textTL.y ) continue;
        
        if( (keyBL.x-limit) > textTR.x ) continue;
        
        if( belowText==NULL ){
            belowText = textAction;
        } else if( [belowText.textLine.quadrangle[1]  CGPointValue].y > textTL.y){
            belowText = textAction;
        }
    }
    
    if( belowText == NULL ) return false;
    
    if( [dictInfo.ocrDict checkMatchValuePattern:belowText.textLine.text] != NULL) {
        belowText.action = ACTION_DETECT;
        if( dictInfo.mIndexOfKey < 0) dictInfo.ocrDict.resValue=@"";
        
        if (dictInfo.mHeightRate<=rate && [dictInfo.ocrDict setValueIfAcceptable:belowText.textLine.text]) {
            dictInfo.mHeightRate = rate;
            dictInfo.bSelected = true;
            dictInfo.ocrDict.resKeyword = [dictInfo.ocrDict.keywords[dictInfo.mIndexOfKey] objectAtIndex:0];
            belowText.action = ACTION_SELECT;
            dictInfo.mKeyText.action = ACTION_SELECT;
            NSLog(@"findValueInBelow: %@", [dictInfo.ocrDict getDisplayString:YES]);
        }
        return true;
    }
    return false;
}

- (BOOL)findServiceAddressEx:(DetectionDictInfo*) dictInfo Actions:(NSArray<TextLineAction*>*) lines
{
    if ( [dictInfo.ocrDict.name rangeOfString:@"service address" options:NSCaseInsensitiveSearch].location == NSNotFound) return false;
    if( dictInfo.ocrDict.resKeyword.length > 0 ) return false;
    
    NSInteger rate = [self getRateFromRTRResultStability:self.currentStabilityStatus];
    
    if (dictInfo.mIndexOfKey >= 0) return false;
    if (dictInfo.mKeyText != NULL) return false;
    
    NSArray<NSString*> *postals = [_POSTAL_CODES objectForKey:self.countryName];
    if (postals != NULL) {
        for( NSString* pattern in postals){
            for( TextLineAction *action in lines){
                NSError *error = NULL;
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                                       options:NSRegularExpressionCaseInsensitive
                                                                                         error:&error];
                NSString *detecedAddr = action.textLine.text;
                NSRange range = [regex rangeOfFirstMatchInString:detecedAddr
                                                         options:0
                                                           range:NSMakeRange(0, [detecedAddr length])];
                if ( range.location != NSNotFound ) {
                    action.action = ACTION_DETECT;
                    NSMutableArray *array = [NSMutableArray arrayWithArray:[detecedAddr
                                                                            componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" ,."]]];
                    [array removeObject:@""];
                    BOOL isOneLineAddr = (array.count > 4);
                    TextLineAction *firstAddrLine = NULL;
                    if( isOneLineAddr ){
                        
                    } else { // If Two lines Address, try to find another address line
                        RTRTextLine *secAddrLine = action.textLine;
                        
                        CGPoint secAddrBL = [secAddrLine.quadrangle[1] CGPointValue];
                        CGPoint secAddrBR = [secAddrLine.quadrangle[2] CGPointValue];
                        
                        for( TextLineAction* textAction in lines) {
                            CGPoint textTL = [textAction.textLine.quadrangle[0] CGPointValue];
                            CGPoint textTR = [textAction.textLine.quadrangle[3] CGPointValue];
                            if( secAddrBL.y < textTL.y ) continue;
                            
                            CGFloat textMX = (secAddrBL.x + secAddrBR.x) / 2;
                            if( textTL.x>textMX || textTR.x<textMX ) continue;
                            
                            if( firstAddrLine==NULL ){
                                firstAddrLine = textAction;
                            } else if( [firstAddrLine.textLine.quadrangle[1]  CGPointValue].y < [textAction.textLine.quadrangle[1] CGPointValue].y){
                                firstAddrLine = textAction;
                            }
                        }
                    }
                    
                    if( !isOneLineAddr && firstAddrLine != NULL){
                        firstAddrLine.action  = ACTION_DETECT;
                        detecedAddr = [NSString stringWithFormat:@"%@, %@", firstAddrLine.textLine.text, detecedAddr];
                    }
                    if (dictInfo.mHeightRate<=rate && [dictInfo.ocrDict setValueIfAcceptable:detecedAddr]) {
                        dictInfo.mHeightRate = rate;
                        dictInfo.bSelected = true;
                        action.action = ACTION_SELECT;
                        if( !isOneLineAddr && firstAddrLine != NULL){
                            firstAddrLine.action = ACTION_SELECT;
                        }
                        NSLog(@"findServiceAddressEx: %@", [dictInfo.ocrDict getDisplayString:YES]);
                    }
                    return true;
                }
            }
        }
    }
    
    return false;
}

#pragma mark - RTRRecognitionServiceDelegate

- (void)onWarning:(RTRCallbackWarningCode)warningCode
{
    if( !self.isDebugMode ) return;
    
	NSString* message = [self stringFromWarningCode:warningCode];
	if(message.length > 0) {
		if(!self.isRunning) {
			return;
		}

		[self updateLogMessage:message];

		// Clear message after 2 seconds.
		__weak RTRViewController* weakSelf = self;
		performBlockOnMainThread(2, ^{
			[weakSelf updateLogMessage:nil];
		});
	}
}

- (void)onError:(NSError*)error
{
	NSLog(@"Error: %@", error);
	__weak RTRViewController* weakSelf = self;
	performBlockOnMainThread(0, ^{
		if(!weakSelf.isRunning) {
			return;
		}

		weakSelf.captureButton.selected = NO;
		weakSelf.running = NO;
		[weakSelf.service stopTasks];

		weakSelf.errorOccurred = error.localizedDescription;
		[weakSelf updateLogMessage:error.localizedDescription];
	});
}

#pragma mark - UITableViewDataSource caps

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
	return self.settingsTableContent.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
	return [UITableViewCell new];
}

@end


#pragma mark -

@implementation DetectionDictInfo
+(instancetype) initInstance
{
    DetectionDictInfo *instance = [[DetectionDictInfo alloc] init];
    if( instance ) {
        instance.ocrDict = NULL;
        instance.bSelected = NO;
        instance.mHeightRate = 0;
        instance.mIndexOfKey = -1;
        instance.mKeyText = NULL;
        //instance.mIndexInKeyBlock = -1;
    }
    return instance;
}
@end

#pragma mark -

@implementation TextLineAction
+(instancetype) initWithTextLine:(RTRTextLine *)text Action:(TLAction)action
{
    TextLineAction *instance = [[TextLineAction alloc] init];
    if( instance ) {
        instance.textLine = text;
        instance.action = action;
    }
    return instance;
}

-(UIColor*) actionColor
{
    switch(self.action) {
        case ACTION_NONE:
            //return RTRUIColorFromRGB(0xFF6500);
            return [UIColor yellowColor];
        case ACTION_DETECT:
            //return RTRUIColorFromRGB(0xC96500);
            return [UIColor greenColor];
        case ACTION_SELECT:
            return [UIColor redColor];
            
        default:
            return [UIColor whiteColor];
            break;
    }
}
@end
