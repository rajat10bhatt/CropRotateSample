//
//  IPDFCameraViewController.h
//  InstaPDF
//
//  Created by Maximilian Mackh on 06/01/15.
//  Copyright (c) 2015 mackh ag. All rights reserved.
//

#import <UIKit/UIKit.h>

@class IPDFCameraViewController;
@protocol IPDFCameraViewControllerDelegate <NSObject>

- (void)ipdfCameraViewController:(IPDFCameraViewController *)ipdfCameraViewController didFinishAutoCaptureImageWithResponse:(id)response;

@end

typedef NS_ENUM(NSInteger,IPDFCameraViewType)
{
    IPDFCameraViewTypeBlackAndWhite,
    IPDFCameraViewTypeNormal
};

@interface IPDFCameraViewController : UIView

- (void)setupCameraView;

- (void)start;
- (void)stop;

@property (nonatomic,assign,getter=isBorderDetectionEnabled) BOOL enableBorderDetection;
@property (nonatomic,assign,getter=isTorchEnabled) BOOL enableTorch;
@property (nonatomic,assign) IPDFCameraViewType cameraViewType;
@property (nonatomic, weak) id <IPDFCameraViewControllerDelegate> delegate;

- (void)focusAtPoint:(CGPoint)point completionHandler:(void(^)(void))completionHandler;

- (void)captureImageWithCompletionHander:(void(^)(NSString *captureImageFilePath, NSString *originalImageFilePath, CIRectangleFeature* croppedRect))completionHandler;

-(void)cropImage: (CIImage *)imageToCrop withFeatureRectPointsTopLeft:(CGPoint)featureTopLeft TopRight:(CGPoint)featureTopRight BottomRight:(CGPoint)featureBottomRight BottomLeft:(CGPoint)featureBottomLeft completionHander:(void(^)(NSString *croppedImageFilePath))completionHandler;
- (CIRectangleFeature *)biggestRectangleInRectangles:(NSArray *)rectangles;

@end
