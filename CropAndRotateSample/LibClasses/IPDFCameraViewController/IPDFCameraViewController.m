//
//  IPDFCameraViewController.m
//  InstaPDF
//
//  Created by Maximilian Mackh on 06/01/15.
//  Copyright (c) 2015 mackh ag. All rights reserved.
//

#import "IPDFCameraViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>

#import <GLKit/GLKit.h>

@interface IPDFRectangleFeature : NSObject

@property (nonatomic) CGPoint topLeft;
@property (nonatomic) CGPoint topRight;
@property (nonatomic) CGPoint bottomRight;
@property (nonatomic) CGPoint bottomLeft;

@end @implementation IPDFRectangleFeature @end

@interface IPDFCameraViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic,strong) AVCaptureSession *captureSession;
@property (nonatomic,strong) AVCaptureDevice *captureDevice;
@property (nonatomic,strong) EAGLContext *context;

@property (nonatomic, strong) AVCaptureStillImageOutput* stillImageOutput;

@property (nonatomic, assign) BOOL forceStop;
@property (nonatomic, assign) CGSize intrinsicContentSize;

@end



@implementation IPDFCameraViewController
{
    CIContext *_coreImageContext;
    GLuint _renderBuffer;
    GLKView *_glkView;
    
    BOOL _isStopped;
    
    CGFloat _imageDedectionConfidence;
    NSTimer *_borderDetectTimeKeeper;
    BOOL _borderDetectFrame;
    CIRectangleFeature *_borderDetectLastRectangleFeature;
    
    BOOL _isCapturing;
    dispatch_queue_t _captureQueue;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_backgroundMode) name:UIApplicationWillResignActiveNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_foregroundMode) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    _captureQueue = dispatch_queue_create("com.instapdf.AVCameraCaptureQueue", DISPATCH_QUEUE_SERIAL);
}

- (void)_backgroundMode
{
    self.forceStop = YES;
}

- (void)_foregroundMode
{
    self.forceStop = NO;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)createGLKView
{
    if (self.context) return;
    
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    GLKView *view = [[GLKView alloc] initWithFrame:self.bounds];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.translatesAutoresizingMaskIntoConstraints = YES;
    view.context = self.context;
    view.contentScaleFactor = 1.0f;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    [self insertSubview:view atIndex:0];
    _glkView = view;
    _coreImageContext = [CIContext contextWithEAGLContext:self.context options:@{ kCIContextWorkingColorSpace : [NSNull null],kCIContextUseSoftwareRenderer : @(NO)}];
}

- (void)setupCameraView
{
    [self createGLKView];
    
    NSArray *possibleDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *device = [possibleDevices firstObject];
    if (!device) return;
    
    _imageDedectionConfidence = 0.0;
    
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    self.captureSession = session;
    [session beginConfiguration];
    self.captureDevice = device;
    
    NSError *error = nil;
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    
    ///Code added by Ganesh.
    session.sessionPreset = AVCaptureSessionPresetPhoto;
    [session addInput:input];
    
    AVCaptureVideoDataOutput *dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    [dataOutput setVideoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
    [dataOutput setSampleBufferDelegate:self queue:_captureQueue];
    [session addOutput:dataOutput];
    
    self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    [session addOutput:self.stillImageOutput];
    
    AVCaptureConnection *connection = [dataOutput.connections firstObject];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    
    if (device.isFlashAvailable)
    {
        [device lockForConfiguration:nil];
        [device setFlashMode:AVCaptureFlashModeAuto];
        [device unlockForConfiguration];
        
        
        if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
        {
            [device lockForConfiguration:nil];
            [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
            [device unlockForConfiguration];
        }
    }
//    // Adjusting focus observer, Rajat
//    [self.captureDevice addObserver:self forKeyPath:@"adjustingFocus" options:NSKeyValueObservingOptionNew context:nil];
    [session commitConfiguration];
}

- (void)setCameraViewType:(IPDFCameraViewType)cameraViewType
{
    UIBlurEffect * effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *viewWithBlurredBackground =[[UIVisualEffectView alloc] initWithEffect:effect];
    viewWithBlurredBackground.frame = self.bounds;
    [self insertSubview:viewWithBlurredBackground aboveSubview:_glkView];
    
    _cameraViewType = cameraViewType;
    
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
                   {
                       [viewWithBlurredBackground removeFromSuperview];
                   });
}

-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (self.forceStop) return;
    if (_isStopped || _isCapturing || !CMSampleBufferIsValid(sampleBuffer)) return;
    
    CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    
    CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    
    if (self.cameraViewType != IPDFCameraViewTypeNormal)
    {
        image = [self filteredImageUsingEnhanceFilterOnImage:image];
    }
    else
    {
        image = [self filteredImageUsingContrastFilterOnImage:image];
    }
    
    if (self.isBorderDetectionEnabled)
    {
        if (_borderDetectFrame)
        {
//            dispatch_async(dispatch_get_main_queue(),^{
//                _borderDetectLastRectangleFeature = [self biggestRectangleInRectangles:[[self highAccuracyRectangleDetector] featuresInImage:image]];
//                _borderDetectFrame = NO;
//            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                //Background Thread
                dispatch_async(dispatch_get_main_queue(), ^(void){
                    _borderDetectLastRectangleFeature = [self biggestRectangleInRectangles:[[self highAccuracyRectangleDetector] featuresInImage:image options:@{CIDetectorAspectRatio : @1.5}]];
                    _borderDetectFrame = NO;
                });
            });
        }
        
        if (_borderDetectLastRectangleFeature)
        {
            _imageDedectionConfidence += .5;
            
            // Add border lines
            // Top line
            image = [self drawHighlightOverlayForPoints:image topLeft:_borderDetectLastRectangleFeature.topLeft topRight:_borderDetectLastRectangleFeature.topRight bottomLeft:CGPointMake(_borderDetectLastRectangleFeature.topLeft.x, _borderDetectLastRectangleFeature.topLeft.y+5) bottomRight:CGPointMake(_borderDetectLastRectangleFeature.topRight.x, _borderDetectLastRectangleFeature.topRight.y+5)];
            
            // Left line
            image = [self drawHighlightOverlayForPoints:image topLeft:_borderDetectLastRectangleFeature.topLeft topRight:_borderDetectLastRectangleFeature.bottomLeft bottomLeft:CGPointMake(_borderDetectLastRectangleFeature.topLeft.x+5, _borderDetectLastRectangleFeature.topLeft.y) bottomRight:CGPointMake(_borderDetectLastRectangleFeature.bottomLeft.x+5, _borderDetectLastRectangleFeature.bottomLeft.y)];
            
            // Bottom line
            image = [self drawHighlightOverlayForPoints:image topLeft:_borderDetectLastRectangleFeature.bottomLeft topRight:_borderDetectLastRectangleFeature.bottomRight bottomLeft:CGPointMake(_borderDetectLastRectangleFeature.bottomLeft.x, _borderDetectLastRectangleFeature.bottomLeft.y-5) bottomRight:CGPointMake(_borderDetectLastRectangleFeature.bottomRight.x, _borderDetectLastRectangleFeature.bottomRight.y-5)];
            
            // Right line
            image = [self drawHighlightOverlayForPoints:image topLeft:_borderDetectLastRectangleFeature.topRight topRight:_borderDetectLastRectangleFeature.bottomRight bottomLeft:CGPointMake(_borderDetectLastRectangleFeature.topRight.x-5, _borderDetectLastRectangleFeature.topRight.y) bottomRight:CGPointMake(_borderDetectLastRectangleFeature.bottomRight.x-5, _borderDetectLastRectangleFeature.bottomRight.y)];
        }
        else
        {
            _imageDedectionConfidence = 0.0f;
        }
    }
    
    if (self.context && _coreImageContext)
    {
        if(_context != [EAGLContext currentContext])
        {
            [EAGLContext setCurrentContext:_context];
        }
        [_glkView bindDrawable];
        [_coreImageContext drawImage:image inRect:self.bounds fromRect:[self cropRectForPreviewImage:image]];
        [_glkView display];
        
        if(_intrinsicContentSize.width != image.extent.size.width) {
            self.intrinsicContentSize = image.extent.size;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self invalidateIntrinsicContentSize];
            });
        }
        
        image = nil;
    }
}

- (CGSize)intrinsicContentSize
{
    if(_intrinsicContentSize.width == 0 || _intrinsicContentSize.height == 0) {
        return CGSizeMake(1, 1); //just enough so rendering doesn't crash
    }
    return _intrinsicContentSize;
}

- (CGRect)cropRectForPreviewImage:(CIImage *)image
{
    CGFloat cropWidth = image.extent.size.width;
    CGFloat cropHeight = image.extent.size.height;
    if (image.extent.size.width>image.extent.size.height) {
        cropWidth = image.extent.size.width;
        cropHeight = cropWidth*self.bounds.size.height/self.bounds.size.width;
    }else if (image.extent.size.width<image.extent.size.height) {
        cropHeight = image.extent.size.height;
        cropWidth = cropHeight*self.bounds.size.width/self.bounds.size.height;
    }
    return CGRectInset(image.extent, (image.extent.size.width-cropWidth)/2, (image.extent.size.height-cropHeight)/2);
}

- (void)enableBorderDetectFrame
{
    _borderDetectFrame = YES;
}

- (CIImage *)drawHighlightOverlayForPoints:(CIImage *)image topLeft:(CGPoint)topLeft topRight:(CGPoint)topRight bottomLeft:(CGPoint)bottomLeft bottomRight:(CGPoint)bottomRight
{
    int count = 1;
    CIImage *overlay = [CIImage imageWithColor:[CIColor colorWithCGColor:[UIColor colorWithRed:0/255.0 green:192/255.0 blue:191/255.0 alpha:1.0].CGColor]];
    
    overlay = [overlay imageByCroppingToRect:image.extent];
    
    CIImage *clearStrip = [CIImage imageWithColor:[CIColor colorWithCGColor:[UIColor colorWithRed:255/255.0 green:250/255.0 blue:250/255.0 alpha:0.0].CGColor]];
    
    if ((count % 2) == 0) {
        clearStrip = [clearStrip imageByCroppingToRect:CGRectMake(image.extent.origin.x, image.extent.origin.y+(((image.extent.size.height/2))/2), image.extent.size.width, (image.extent.size.height/2))];
        count++;
    } else {
        clearStrip = [clearStrip imageByCroppingToRect:CGRectMake(image.extent.origin.x + (((image.extent.size.width/2))/2), image.extent.origin.y, (image.extent.size.width/2), image.extent.size.height)];
        CIImage *overlay1 = [overlay imageByCroppingToRect:CGRectMake(image.extent.origin.x, image.extent.origin.y, (image.extent.size.width-clearStrip.extent.size.width)/2, image.extent.size.height)];
        CIImage *overlay2 = [overlay imageByCroppingToRect:CGRectMake(image.extent.origin.x + overlay1.extent.size.width + clearStrip.extent.size.width, image.extent.origin.y, overlay1.extent.size.width, overlay1.extent.size.height)];
        overlay = [clearStrip imageByCompositingOverImage:overlay1];
        overlay = [overlay2 imageByCompositingOverImage:overlay];
        count++;
    }
    
    CIImage *overlayNew = [clearStrip imageByCompositingOverImage:overlay];
    overlayNew = [clearStrip imageByCompositingOverImage:overlayNew];
    
    overlay = [overlayNew imageByApplyingFilter:@"CIPerspectiveTransformWithExtent" withInputParameters:@{@"inputExtent":[CIVector vectorWithCGRect:image.extent],@"inputTopLeft":[CIVector vectorWithCGPoint:topLeft],@"inputTopRight":[CIVector vectorWithCGPoint:topRight],@"inputBottomLeft":[CIVector vectorWithCGPoint:bottomLeft],@"inputBottomRight":[CIVector vectorWithCGPoint:bottomRight]}];
    
    return [overlay imageByCompositingOverImage:image];
}

- (void)start
{
    _isStopped = NO;
    
    [self.captureSession startRunning];
    
    ///Code added by Ganesh.
    self.captureSession.sessionPreset = AVCaptureSessionPresetPhoto;
    
    _borderDetectTimeKeeper = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(enableBorderDetectFrame) userInfo:nil repeats:YES];
    
    [self hideGLKView:NO completion:nil];
}

- (void)stop
{
    _isStopped = YES;
    
    [self.captureSession stopRunning];
    
    [_borderDetectTimeKeeper invalidate];
    
    [self hideGLKView:YES completion:nil];
}

- (void)setEnableTorch:(BOOL)enableTorch
{
    _enableTorch = enableTorch;
    
    AVCaptureDevice *device = self.captureDevice;
    if ([device hasTorch] && [device hasFlash])
    {
        [device lockForConfiguration:nil];
        if (enableTorch)
        {
            [device setTorchMode:AVCaptureTorchModeOn];
        }
        else
        {
            [device setTorchMode:AVCaptureTorchModeOff];
        }
        [device unlockForConfiguration];
    }
}

- (void)focusAtPoint:(CGPoint)point completionHandler:(void(^)(void))completionHandler
{
    AVCaptureDevice *device = self.captureDevice;
    CGPoint pointOfInterest = CGPointZero;
    CGSize frameSize = self.bounds.size;
    pointOfInterest = CGPointMake(point.y / frameSize.height, 1.f - (point.x / frameSize.width));
    
    if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
    {
        NSError *error;
        if ([device lockForConfiguration:&error])
        {
            if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
            {
                [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
                [device setFocusPointOfInterest:pointOfInterest];
                //Code Added by Ganesh.
                [device setExposureMode:AVCaptureFocusModeContinuousAutoFocus];
            }
            
            if([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
            {
                [device setExposurePointOfInterest:pointOfInterest];
                [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
                completionHandler();
            }
            
            [device unlockForConfiguration];
        }
    }
    else
    {
        completionHandler();
    }
}

-(void)cropImage: (CIImage *)imageToCrop withFeatureRectPointsTopLeft:(CGPoint)featureTopLeft TopRight:(CGPoint)featureTopRight BottomRight:(CGPoint)featureBottomRight BottomLeft:(CGPoint)featureBottomLeft completionHander:(void(^)(NSString *croppedImageFilePath))completionHandler
{
    __block NSString *croppedImageFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"sbq_cropped_%i.jpeg",(int)[NSDate date].timeIntervalSince1970]];
    
    @autoreleasepool
    {
        imageToCrop = [self correctPerspectiveForImage:imageToCrop withFeaturePointsTopLeft:featureTopLeft TopRight:featureTopRight BottomRight:featureBottomRight BottomLeft:featureBottomLeft];
        
        CIFilter *transform = [CIFilter filterWithName:@"CIAffineTransform"];
        [transform setValue:imageToCrop forKey:kCIInputImageKey];
        NSValue *rotation = [NSValue valueWithCGAffineTransform:CGAffineTransformMakeRotation(0 * (M_PI/180))];
        [transform setValue:rotation forKey:@"inputTransform"];
        imageToCrop = [transform outputImage];
        
        if (!imageToCrop || CGRectIsEmpty(imageToCrop.extent)) return;
        
        static CIContext *ctx = nil;
        if (!ctx)
        {
            ctx = [CIContext contextWithOptions:@{kCIContextWorkingColorSpace:[NSNull null]}];
        }
        
        CGSize bounds = imageToCrop.extent.size;
        bounds = CGSizeMake(floorf(bounds.width / 4) * 4,floorf(bounds.height / 4) * 4);
        CGRect extent = CGRectMake(imageToCrop.extent.origin.x, imageToCrop.extent.origin.y, bounds.width, bounds.height);
        
        static int bytesPerPixel = 8;
        uint rowBytes = bytesPerPixel * bounds.width;
        uint totalBytes = rowBytes * bounds.height;
        uint8_t *byteBuffer = malloc(totalBytes);
        
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        
        [ctx render:imageToCrop toBitmap:byteBuffer rowBytes:rowBytes bounds:extent format:kCIFormatRGBA8 colorSpace:colorSpace];
        
        CGContextRef bitmapContext = CGBitmapContextCreate(byteBuffer,bounds.width,bounds.height,bytesPerPixel,rowBytes,colorSpace,kCGImageAlphaNoneSkipLast);
        CGImageRef imgRef = CGBitmapContextCreateImage(bitmapContext);
        CGColorSpaceRelease(colorSpace);
        CGContextRelease(bitmapContext);
        free(byteBuffer);
        
        if (imgRef == NULL)
        {
            CFRelease(imgRef);
            return;
        }
        saveCGImageAsJPEGToFilePath(imgRef, croppedImageFilePath);
        CFRelease(imgRef);
        
        dispatch_async(dispatch_get_main_queue(), ^
                       {
                           completionHandler(croppedImageFilePath);
                       });
    }
}

- (void)captureImageWithCompletionHander:(void(^)(NSString *captureImageFilePath, NSString *originalImageFilePath, CIRectangleFeature* croppedRect))completionHandler
{
    dispatch_suspend(_captureQueue);
    
    AVCaptureConnection *videoConnection = nil;
    for (AVCaptureConnection *connection in self.stillImageOutput.connections)
    {
        for (AVCaptureInputPort *port in [connection inputPorts])
        {
            if ([[port mediaType] isEqual:AVMediaTypeVideo] )
            {
                videoConnection = connection;
                break;
            }
        }
        if (videoConnection) break;
    }
    
    __weak typeof(self) weakSelf = self;
    
    [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:videoConnection completionHandler: ^(CMSampleBufferRef imageSampleBuffer, NSError *error)
     {
         if (error)
         {
             dispatch_resume(_captureQueue);
             return;
         }
         
         __block NSString *capturedImageFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"sbq_captured_%i.jpeg",(int)[NSDate date].timeIntervalSince1970]];
         
         __block NSString *originalImageFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"sbq_original_%i.jpeg",(int)[NSDate date].timeIntervalSince1970]];
         
         CIRectangleFeature *rectangleFeature;
         
         @autoreleasepool
         {
             NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageSampleBuffer];
             CIImage *enhancedImage = [[CIImage alloc] initWithData:imageData options:@{kCIImageColorSpace:[NSNull null]}];
             CIImage *capturedImage = [[CIImage alloc] initWithData:imageData options:@{kCIImageColorSpace:[NSNull null]}];
             
             imageData = nil;
             
             if (weakSelf.cameraViewType == IPDFCameraViewTypeBlackAndWhite)
             {
                 enhancedImage = [self filteredImageUsingEnhanceFilterOnImage:enhancedImage];
                 capturedImage = [self filteredImageUsingEnhanceFilterOnImage:capturedImage];
             }
             else
             {
                 enhancedImage = [self filteredImageUsingContrastFilterOnImage:enhancedImage];
                 capturedImage = [self filteredImageUsingContrastFilterOnImage:capturedImage];
             }
             
             if (weakSelf.isBorderDetectionEnabled && rectangleDetectionConfidenceHighEnough(_imageDedectionConfidence))
             {
                 rectangleFeature = [self biggestRectangleInRectangles:[[self highAccuracyRectangleDetector] featuresInImage:enhancedImage]];
                 
                 if (rectangleFeature)
                 {
                     enhancedImage = [self correctPerspectiveForImage:enhancedImage withFeatures:rectangleFeature];
                 }
             }
             
             CIFilter *transform = [CIFilter filterWithName:@"CIAffineTransform"];
             [transform setValue:enhancedImage forKey:kCIInputImageKey];
             NSValue *rotation = [NSValue valueWithCGAffineTransform:CGAffineTransformMakeRotation(-90 * (M_PI/180))];
             [transform setValue:rotation forKey:@"inputTransform"];
             enhancedImage = [transform outputImage];
             
             [transform setValue:capturedImage forKey:kCIInputImageKey];
             rotation = [NSValue valueWithCGAffineTransform:CGAffineTransformMakeRotation(-90 * (M_PI/180))];
             [transform setValue:rotation forKey:@"inputTransform"];
             capturedImage = [transform outputImage];
             
             if ((!enhancedImage || CGRectIsEmpty(enhancedImage.extent)) || (!capturedImage || CGRectIsEmpty(capturedImage.extent))) return;
             
             static CIContext *ctx = nil;
             if (!ctx)
             {
                 ctx = [CIContext contextWithOptions:@{kCIContextWorkingColorSpace:[NSNull null]}];
             }
             
             CGSize bounds = enhancedImage.extent.size;
             bounds = CGSizeMake(floorf(bounds.width / 4) * 4,floorf(bounds.height / 4) * 4);
             CGRect extent = CGRectMake(enhancedImage.extent.origin.x, enhancedImage.extent.origin.y, bounds.width, bounds.height);
             
             static int bytesPerPixel = 8;
             uint rowBytes = bytesPerPixel * bounds.width;
             uint totalBytes = rowBytes * bounds.height;
             uint8_t *byteBuffer = malloc(totalBytes);
             
             CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
             
             [ctx render:enhancedImage toBitmap:byteBuffer rowBytes:rowBytes bounds:extent format:kCIFormatRGBA8 colorSpace:colorSpace];
             
             CGContextRef bitmapContext = CGBitmapContextCreate(byteBuffer,bounds.width,bounds.height,bytesPerPixel,rowBytes,colorSpace,kCGImageAlphaNoneSkipLast);
             CGImageRef imgRef = CGBitmapContextCreateImage(bitmapContext);
             CGColorSpaceRelease(colorSpace);
             CGContextRelease(bitmapContext);
             free(byteBuffer);
             
             if (imgRef == NULL)
             {
                 CFRelease(imgRef);
                 return;
             }
             saveCGImageAsJPEGToFilePath(imgRef, capturedImageFilePath);
             CFRelease(imgRef);
             
             bounds = capturedImage.extent.size;
             bounds = CGSizeMake(floorf(bounds.width / 4) * 4,floorf(bounds.height / 4) * 4);
             extent = CGRectMake(capturedImage.extent.origin.x, capturedImage.extent.origin.y, bounds.width, bounds.height);
             
             rowBytes = bytesPerPixel * bounds.width;
             totalBytes = rowBytes * bounds.height;
             byteBuffer = malloc(totalBytes);
             
             colorSpace = CGColorSpaceCreateDeviceRGB();
             
             [ctx render:capturedImage toBitmap:byteBuffer rowBytes:rowBytes bounds:extent format:kCIFormatRGBA8 colorSpace:colorSpace];
             
             bitmapContext = CGBitmapContextCreate(byteBuffer,bounds.width,bounds.height,bytesPerPixel,rowBytes,colorSpace,kCGImageAlphaNoneSkipLast);
             imgRef = CGBitmapContextCreateImage(bitmapContext);
             CGColorSpaceRelease(colorSpace);
             CGContextRelease(bitmapContext);
             free(byteBuffer);
             
             if (imgRef == NULL)
             {
                 CFRelease(imgRef);
                 return;
             }
             saveCGImageAsJPEGToFilePath(imgRef, originalImageFilePath);
             CFRelease(imgRef);
             
             dispatch_async(dispatch_get_main_queue(), ^
                            {
                                completionHandler(capturedImageFilePath, originalImageFilePath, rectangleFeature);
                                dispatch_resume(_captureQueue);
                            });
             
             _imageDedectionConfidence = 0.0f;
         }
     }];
}

void saveCGImageAsJPEGToFilePath(CGImageRef imageRef, NSString *filePath)
{
    @autoreleasepool
    {
        CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:filePath];
        CGImageDestinationRef destination = CGImageDestinationCreateWithURL(url, kUTTypeJPEG, 1, NULL);
        CGImageDestinationAddImage(destination, imageRef, nil);
        CGImageDestinationFinalize(destination);
        CFRelease(destination);
    }
}

- (void)hideGLKView:(BOOL)hidden completion:(void(^)(void))completion
{
    [UIView animateWithDuration:0.1 animations:^
     {
         _glkView.alpha = (hidden) ? 0.0 : 1.0;
     }
                     completion:^(BOOL finished)
     {
         if (!completion) return;
         completion();
     }];
}

- (CIImage *)filteredImageUsingEnhanceFilterOnImage:(CIImage *)image
{
    return [CIFilter filterWithName:@"CIColorControls" keysAndValues:kCIInputImageKey, image, @"inputBrightness", [NSNumber numberWithFloat:0.0], @"inputContrast", [NSNumber numberWithFloat:1.14], @"inputSaturation", [NSNumber numberWithFloat:0.0], nil].outputImage;
}

- (CIImage *)filteredImageUsingContrastFilterOnImage:(CIImage *)image
{
    return [CIFilter filterWithName:@"CIColorControls" withInputParameters:@{@"inputContrast":@(1.1),kCIInputImageKey:image}].outputImage;
}

- (CIImage *)correctPerspectiveForImage:(CIImage *)image withFeaturePointsTopLeft:(CGPoint)topLeft TopRight:(CGPoint)topRight BottomRight:(CGPoint)bottomRight BottomLeft:(CGPoint)bottomLeft
{
    NSMutableDictionary *rectangleCoordinates = [NSMutableDictionary new];
    rectangleCoordinates[@"inputTopLeft"] = [CIVector vectorWithCGPoint:topLeft];
    rectangleCoordinates[@"inputTopRight"] = [CIVector vectorWithCGPoint:topRight];
    rectangleCoordinates[@"inputBottomLeft"] = [CIVector vectorWithCGPoint:bottomLeft];
    rectangleCoordinates[@"inputBottomRight"] = [CIVector vectorWithCGPoint:bottomRight];
    return [image imageByApplyingFilter:@"CIPerspectiveCorrection" withInputParameters:rectangleCoordinates];
}

- (CIImage *)correctPerspectiveForImage:(CIImage *)image withFeatures:(CIRectangleFeature *)rectangleFeature
{
    NSMutableDictionary *rectangleCoordinates = [NSMutableDictionary new];
    rectangleCoordinates[@"inputTopLeft"] = [CIVector vectorWithCGPoint:rectangleFeature.topLeft];
    rectangleCoordinates[@"inputTopRight"] = [CIVector vectorWithCGPoint:rectangleFeature.topRight];
    rectangleCoordinates[@"inputBottomLeft"] = [CIVector vectorWithCGPoint:rectangleFeature.bottomLeft];
    rectangleCoordinates[@"inputBottomRight"] = [CIVector vectorWithCGPoint:rectangleFeature.bottomRight];
    return [image imageByApplyingFilter:@"CIPerspectiveCorrection" withInputParameters:rectangleCoordinates];
}

- (CIDetector *)rectangleDetetor
{
    static CIDetector *detector = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
                  {
                      detector = [CIDetector detectorOfType:CIDetectorTypeRectangle context:nil options:@{CIDetectorAccuracy : CIDetectorAccuracyLow,CIDetectorTracking : @(YES)}];
                  });
    return detector;
}

- (CIDetector *)highAccuracyRectangleDetector
{
    static CIDetector *detector = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
                  {
                      detector = [CIDetector detectorOfType:CIDetectorTypeRectangle context:nil options:@{CIDetectorAccuracy : CIDetectorAccuracyHigh, CIDetectorAspectRatio : @1.5}];
                  });
    return detector;
}

- (CIRectangleFeature *)_biggestRectangleInRectangles:(NSArray *)rectangles
{
    if (![rectangles count]) return nil;
    
    float halfPerimiterValue = 0;
    
    CIRectangleFeature *biggestRectangle = [rectangles firstObject];
    
    for (CIRectangleFeature *rect in rectangles)
    {
        CGPoint p1 = rect.topLeft;
        CGPoint p2 = rect.topRight;
        CGFloat width = hypotf(p1.x - p2.x, p1.y - p2.y);
        
        CGPoint p3 = rect.topLeft;
        CGPoint p4 = rect.bottomLeft;
        CGFloat height = hypotf(p3.x - p4.x, p3.y - p4.y);
        
        CGFloat currentHalfPerimiterValue = height + width;
        
        if (halfPerimiterValue < currentHalfPerimiterValue)
        {
            halfPerimiterValue = currentHalfPerimiterValue;
            biggestRectangle = rect;
        }
    }
    if ([self.delegate respondsToSelector:@selector(ipdfCameraViewController: didFinishAutoCaptureImageWithResponse:)]) {
        [self.delegate ipdfCameraViewController:self didFinishAutoCaptureImageWithResponse:biggestRectangle];
    }
    return biggestRectangle;
}

- (CIRectangleFeature *)biggestRectangleInRectangles:(NSArray *)rectangles
{
    CIRectangleFeature *rectangleFeature = [self _biggestRectangleInRectangles:rectangles];
    
    if (!rectangleFeature) return nil;
    
    // Credit: http://stackoverflow.com/a/20399468/1091044
    
    NSArray *points = @[[NSValue valueWithCGPoint:rectangleFeature.topLeft],[NSValue valueWithCGPoint:rectangleFeature.topRight],[NSValue valueWithCGPoint:rectangleFeature.bottomLeft],[NSValue valueWithCGPoint:rectangleFeature.bottomRight]];
    
    CGPoint min = [points[0] CGPointValue];
    CGPoint max = min;
    for (NSValue *value in points)
    {
        CGPoint point = [value CGPointValue];
        min.x = fminf(point.x, min.x);
        min.y = fminf(point.y, min.y);
        max.x = fmaxf(point.x, max.x);
        max.y = fmaxf(point.y, max.y);
    }
    
    CGPoint center =
    {
        0.5f * (min.x + max.x),
        0.5f * (min.y + max.y),
    };
    
    NSNumber *(^angleFromPoint)(id) = ^(NSValue *value)
    {
        CGPoint point = [value CGPointValue];
        CGFloat theta = atan2f(point.y - center.y, point.x - center.x);
        CGFloat angle = fmodf(M_PI - M_PI_4 + theta, 2 * M_PI);
        return @(angle);
    };
    
    NSArray *sortedPoints = [points sortedArrayUsingComparator:^NSComparisonResult(id a, id b)
                             {
                                 return [angleFromPoint(a) compare:angleFromPoint(b)];
                             }];
    
    IPDFRectangleFeature *rectangleFeatureMutable = [IPDFRectangleFeature new];
    rectangleFeatureMutable.topLeft = [sortedPoints[3] CGPointValue];
    rectangleFeatureMutable.topRight = [sortedPoints[2] CGPointValue];
    rectangleFeatureMutable.bottomRight = [sortedPoints[1] CGPointValue];
    rectangleFeatureMutable.bottomLeft = [sortedPoints[0] CGPointValue];
    
    
    
//       if ([self.delegate respondsToSelector:@selector(ipdfCameraViewController: didFinishAutoCaptureImageWithResponse:)]) {
//           [self.delegate ipdfCameraViewController:self didFinishAutoCaptureImageWithResponse:rectangleFeatureMutable];
//       }
    
    
    return (id)rectangleFeatureMutable;
}

BOOL rectangleDetectionConfidenceHighEnough(float confidence)
{
    return (confidence > 1.0);
}

@end
