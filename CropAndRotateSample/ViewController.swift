//
//  ViewController.swift
//  SBQ_Editing_Screens
//
//  Created by Rajat Bhatt on 31/07/17.
//  Copyright © 2017 Rajat Bhatt. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    //MARK: Outlets
    @IBOutlet weak var imageSuperViewWidth: NSLayoutConstraint!
    @IBOutlet weak var imageSuperViewHeight: NSLayoutConstraint!
    @IBOutlet weak var imageSuperView: UIView!
    @IBOutlet weak var topLeftButton: UIButton!
    @IBOutlet weak var topRightButton: UIButton!
    @IBOutlet weak var bottomLeftButton: UIButton!
    @IBOutlet weak var bottomRightButton: UIButton!
    @IBOutlet weak var centerBottomButton: UIButton!
    @IBOutlet weak var centerLeftButton: UIButton!
    @IBOutlet weak var centerTopButton: UIButton!
    @IBOutlet weak var centerRightButton: UIButton!
    @IBOutlet weak var imageViewOutlet: UIImageView!
    @IBOutlet weak var centerButtonOutlet: UIButton!
    @IBOutlet weak var leftButtonOutlet: UIButton!
    @IBOutlet weak var titleButtonOutlet: UIButton!
    @IBOutlet weak var tabBottomView: UIView!
    @IBOutlet weak var imageViewHorizontalCenterConstraint: NSLayoutConstraint!
    
    //MARK: Properties
    var scaleFactor = CGFloat(0)
    var cropRectOverlay = CAShapeLayer()
    var capturedRect : CIRectangleFeature? = nil
    var cameraViewController: IPDFCameraViewController?
    
    //MARK: View did load
    override func viewDidLoad() {
        super.viewDidLoad()
        titleButtonOutlet.layer.masksToBounds = true
        titleButtonOutlet.layer.cornerRadius = titleButtonOutlet.frame.size.height/2
        titleButtonOutlet.frame.size.width = 110
        self.calculateScaleFactor()
        self.centerTopButton.isHidden = true
        self.centerLeftButton.isHidden = true
        self.centerRightButton.isHidden = true
        self.centerBottomButton.isHidden = true
        self.showHideCropButtons(hide: true)
        self.imageViewHorizontalCenterConstraint.constant = -(tabBottomView.frame.size.height/2)
    }
    
    func showHideCropButtons(hide: Bool) {
        self.topLeftButton.isHidden = hide
        self.topRightButton.isHidden = hide
        self.bottomLeftButton.isHidden = hide
        self.bottomRightButton.isHidden = hide
//        self.centerTopButton.isHidden = hide
//        self.centerLeftButton.isHidden = hide
//        self.centerRightButton.isHidden = hide
//        self.centerBottomButton.isHidden = hide
    }
    
    //MARK: Left button click
    @IBAction func leftButton(_ sender: UIButton) {
        if sender.imageView?.image == #imageLiteral(resourceName: "ic_admin") {
            //TODO: Click of settings Button
        } else if sender.imageView?.image == #imageLiteral(resourceName: "crop") {
            //Clixk of crop button
            leftButtonOutlet.setImage(#imageLiteral(resourceName: "undo"), for: .normal)
            centerButtonOutlet.isHidden = true
            self.showHideCropButtons(hide: false)
            //Add rectangle overlay
            self.addCropRectOverlay()
            self.refreshCropRectOverlay()
            //Add gesture recognizer on buttons
            self.addGestureRecognizersForButtons()
        } else if sender.imageView?.image == #imageLiteral(resourceName: "undo") {
            if centerButtonOutlet.isHidden {
                setImagesToCropAndRotate()
                centerButtonOutlet.isHidden = false
                self.showHideCropButtons(hide: true)
                self.cropRectOverlay.isHidden = true
            } else {
                setImagesToCropAndRotate()
            }
        }
    }
    
    //MARK: Center Button click
    @IBAction func centerButton(_ sender: UIButton) {
        if sender.imageView?.image == #imageLiteral(resourceName: "controls") {
            setImagesToCropAndRotate()
        } else if sender.imageView?.image == #imageLiteral(resourceName: "rotate") && leftButtonOutlet.imageView?.image == #imageLiteral(resourceName: "undo") {
            print("rotate")
            if let image = self.imageViewOutlet.image {
                self.imageViewOutlet.image = self.rotateImage(image: image, byAngle: 90)
                calculateScaleFactor()
            }
            
        } else if sender.imageView?.image == #imageLiteral(resourceName: "rotate") {
            leftButtonOutlet.setImage(#imageLiteral(resourceName: "undo"), for: .normal)
            centerButtonOutlet.setImage(#imageLiteral(resourceName: "rotate"), for: .normal)
        }
    }
    
    //MARK: Done Button click
    @IBAction func doneButton(_ sender: UIButton) {
        if leftButtonOutlet.imageView?.image == #imageLiteral(resourceName: "crop") && centerButtonOutlet.imageView?.image == #imageLiteral(resourceName: "rotate") {
            leftButtonOutlet.setImage(#imageLiteral(resourceName: "ic_admin"), for: .normal)
            centerButtonOutlet.setImage(#imageLiteral(resourceName: "controls"), for: .normal)
        } else if leftButtonOutlet.imageView?.image == #imageLiteral(resourceName: "undo") && centerButtonOutlet.isHidden {
            setImagesToCropAndRotate()
            centerButtonOutlet.isHidden = false
            //TODO: CropImage
            self.cropAndReshapeImage(completion: { (croppedImage) in
                DispatchQueue.main.async {
                    self.imageViewOutlet.image = croppedImage
                    self.calculateScaleFactor()
                }
            })
            self.showHideCropButtons(hide: true)
            self.cropRectOverlay.isHidden = true
        } else if leftButtonOutlet.imageView?.image == #imageLiteral(resourceName: "undo") && centerButtonOutlet.imageView?.image == #imageLiteral(resourceName: "rotate") {
            setImagesToCropAndRotate()
        }
    }
    
    private func setImagesToCropAndRotate() {
        leftButtonOutlet.setImage(#imageLiteral(resourceName: "crop"), for: .normal)
        centerButtonOutlet.setImage(#imageLiteral(resourceName: "rotate"), for: .normal)
    }
    
    //MARK: Rotate Image
    private func rotateImage(image: UIImage, byAngle degrees: CGFloat) -> UIImage {
        //Calculate the size of the rotated view's containing box for our drawing space
        let rotatedViewBox: UIView = UIView(frame: CGRect(x:0, y:0, width:image.size.width, height:image.size.height))
        let t: CGAffineTransform = CGAffineTransform(rotationAngle: degrees * CGFloat(Double.pi / 180))
        rotatedViewBox.transform = t
        let rotatedSize: CGSize = rotatedViewBox.frame.size
        
        //Create the bitmap context
        UIGraphicsBeginImageContext(rotatedSize)
        let bitmap: CGContext = UIGraphicsGetCurrentContext()!
        
        //Move the origin to the middle of the image so we will rotate and scale around the center.
        bitmap.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        //Rotate the image context
        bitmap.rotate(by: (degrees * CGFloat(Double.pi / 180)))
        //Now, draw the rotated/scaled image into the context
        bitmap.scaleBy(x: 1.0, y: -1.0)
        
        bitmap.draw(image.cgImage!, in: CGRect(x:-image.size.width / 2, y:-image.size.height / 2, width:image.size.width, height:image.size.height))
        
        let newImage: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return newImage
    }
    
    //MARK:- Calculate image scale factor and set height and width of the imageview
    private func calculateScaleFactor() {
        if let image = imageViewOutlet.image {
            let imageScale : CGFloat = image.size.width/image.size.height
            
            if (Int(imageScale) > 0) {
                imageSuperViewWidth.constant = (self.view.bounds.width-50)
                imageSuperViewHeight.constant = (self.view.bounds.width-50)/imageScale
            } else {
                imageSuperViewHeight.constant = (self.view.bounds.height-150)
                imageSuperViewWidth.constant = (self.view.bounds.height-150)*imageScale
            }
            
            imageSuperView.layoutIfNeeded()
            
            scaleFactor = CGFloat(fminf(Float(imageSuperView.bounds.width / image.size.width), Float(imageSuperView.bounds.height / image.size.height)))
        }
    }
    
    //MARK:- Add crop overlay on the image
    private func addCropRectOverlay() {
        cropRectOverlay.fillColor = UIColor(red: CGFloat(25 / 255.0), green: CGFloat(17 / 255.0), blue: CGFloat(100 / 255.0), alpha: CGFloat(0.0)).cgColor
        cropRectOverlay.lineWidth = 3.0
        //cropRectOverlay.lineCap = kCALineCapRound
        cropRectOverlay.strokeColor = UIColor(red: CGFloat(53 / 255.0), green: CGFloat(176 / 255.0), blue: CGFloat(175 / 255.0), alpha: CGFloat(1.0)).cgColor
        
        if (capturedRect != nil)
        {
            topLeftButton.center = CGPoint(x: ((capturedRect?.bottomLeft.y)!*scaleFactor), y: ((capturedRect?.bottomLeft.x)!*scaleFactor))
            topRightButton.center =  CGPoint(x: ((capturedRect?.topLeft.y)!*scaleFactor), y: ((capturedRect?.topLeft.x)!*scaleFactor))
            bottomRightButton.center = CGPoint(x: ((capturedRect?.topRight.y)!*scaleFactor), y: ((capturedRect?.topRight.x)!*scaleFactor))
            bottomLeftButton.center = CGPoint(x: ((capturedRect?.bottomRight.y)!*scaleFactor), y: ((capturedRect?.bottomRight.x)!*scaleFactor))
//            centerTopButton.center = CGPoint(x: (((capturedRect?.bounds.size.width)!/2)*scaleFactor), y: (topLeftButton.center.y*scaleFactor))
//            centerLeftButton.center = CGPoint(x: topLeftButton.center.x, y:(((capturedRect?.bounds.size.height)!/2)*scaleFactor))
//            centerBottomButton.center = CGPoint(x: centerTopButton.center.x, y: bottomLeftButton.center.y)
//            centerRightButton.center = CGPoint(x: topLeftButton.center.x, y: centerLeftButton.center.y)
        }
        else
        {
            topLeftButton.frame.origin = CGPoint(x: 50, y: 50)
            bottomRightButton.frame.origin =  CGPoint(x: imageSuperViewWidth.constant-75, y: imageSuperViewHeight.constant-75)
            topRightButton.center = CGPoint(x: bottomRightButton.center.x, y: topLeftButton.center.y)
            bottomLeftButton.center = CGPoint(x: topLeftButton.center.x, y: bottomRightButton.center.y)
//            let width = (topRightButton.center.x-topLeftButton.center.x)/2
//            let height = (bottomLeftButton.center.y - topLeftButton.center.y)/2
//            centerTopButton.center = CGPoint(x: (width + topLeftButton.center.x), y: topLeftButton.center.y)
//            centerLeftButton.center = CGPoint(x: topLeftButton.center.x, y: height+topLeftButton.center.y)
//            centerBottomButton.center = CGPoint(x: centerTopButton.center.x, y: bottomLeftButton.center.y)
//            centerRightButton.center = CGPoint(x: topRightButton.center.x, y: centerLeftButton.center.y)
        }
        
        imageSuperView.addSubview(topLeftButton)
        imageSuperView.addSubview(topRightButton)
        imageSuperView.addSubview(bottomLeftButton)
        imageSuperView.addSubview(bottomRightButton)
//        imageSuperView.addSubview(centerTopButton)
//        imageSuperView.addSubview(centerLeftButton)
//        imageSuperView.addSubview(centerBottomButton)
//        imageSuperView.addSubview(centerRightButton)
        
        imageSuperView.layer.addSublayer(cropRectOverlay)
    }
    
    //MARK:- Add Pan gesture to all the buttons
    private func addGestureRecognizersForButtons()
    {
        var pan = UIPanGestureRecognizer(target: self, action: #selector(self.panGestureHandler))
        topLeftButton.addGestureRecognizer(pan)
        
        pan = UIPanGestureRecognizer(target: self, action: #selector(self.panGestureHandler))
        topRightButton.addGestureRecognizer(pan)
        
        pan = UIPanGestureRecognizer(target: self, action: #selector(self.panGestureHandler))
        bottomRightButton.addGestureRecognizer(pan)
        
        pan = UIPanGestureRecognizer(target: self, action: #selector(self.panGestureHandler))
        bottomLeftButton.addGestureRecognizer(pan)
        
//        pan = UIPanGestureRecognizer(target: self, action: #selector(self.panGestureHandler))
//        centerTopButton.addGestureRecognizer(pan)
//
//        pan = UIPanGestureRecognizer(target: self, action: #selector(self.panGestureHandler))
//        centerBottomButton.addGestureRecognizer(pan)
//
//        pan = UIPanGestureRecognizer(target: self, action: #selector(self.panGestureHandler))
//        centerLeftButton.addGestureRecognizer(pan)
//
//        pan = UIPanGestureRecognizer(target: self, action: #selector(self.panGestureHandler))
//        centerRightButton.addGestureRecognizer(pan)
    }
    
    //Pan handler
    @objc private func panGestureHandler(panGesture : UIPanGestureRecognizer)
    {
        self.translateView(panView: panGesture.view, forGestuer: panGesture)
        self.refreshCropRectOverlay()
    }
    
    private func translateView(panView : UIView?, forGestuer panGesture : UIPanGestureRecognizer)
    {
        let translation: CGPoint = panGesture.translation(in: self.view)
        let pointOnpan = CGPoint(x: CGFloat((panView?.center.x)! + translation.x), y: CGFloat((panView?.center.y)! + translation.y))
        if imageViewOutlet.frame.contains(pointOnpan) {
            panView?.center = pointOnpan
            panGesture.setTranslation(CGPoint.zero , in: self.view)
        }
        
        //        switch panView?.center {
        //        case centerBottomButton.center?:
        //            if imageViewOutlet.frame.contains(pointOnpan) {
        //                panView?.center = pointOnpan
        //                bottomLeftButton.center = CGPoint(x: CGFloat((bottomLeftButton.center.x) + translation.x), y: CGFloat((bottomLeftButton.center.y) + translation.y))
        //                bottomRightButton.center = CGPoint(x: CGFloat((bottomRightButton.center.x) + translation.x), y: CGFloat((bottomRightButton.center.y) + translation.y))
        //                panGesture.setTranslation(CGPoint.zero , in: self.view)
        //            }
        //        case centerLeftButton.center?:
        //            if imageViewOutlet.frame.contains(pointOnpan) {
        //                panView?.center = pointOnpan
        //                topLeftButton.center = CGPoint(x: CGFloat((topLeftButton.center.x) + translation.x), y: CGFloat((topLeftButton.center.y) + translation.y))
        //                bottomLeftButton.center = CGPoint(x: CGFloat((bottomLeftButton.center.x) + translation.x), y: CGFloat((bottomLeftButton.center.y) + translation.y))
        //                panGesture.setTranslation(CGPoint.zero , in: self.view)
        //            }
        //        case centerTopButton.center?:
        //            if imageViewOutlet.frame.contains(pointOnpan) {
        //                panView?.center = pointOnpan
        //                topLeftButton.center = CGPoint(x: CGFloat((topLeftButton.center.x) + translation.x), y: CGFloat((topLeftButton.center.y) + translation.y))
        //                topRightButton.center = CGPoint(x: CGFloat((topRightButton.center.x) + translation.x), y: CGFloat((topRightButton.center.y) + translation.y))
        //                panGesture.setTranslation(CGPoint.zero , in: self.view)
        //            }
        //        case centerRightButton.center?:
        //            if imageViewOutlet.frame.contains(pointOnpan) {
        //                panView?.center = pointOnpan
        //                bottomRightButton.center = CGPoint(x: CGFloat((bottomRightButton.center.x) + translation.x), y: CGFloat((bottomRightButton.center.y) + translation.y))
        //                topRightButton.center = CGPoint(x: CGFloat((topRightButton.center.x) + translation.x), y: CGFloat((topRightButton.center.y) + translation.y))
        //                panGesture.setTranslation(CGPoint.zero , in: self.view)
        //            }
        //        default:
        //
        //        }
    }
    
    private func refreshCropRectOverlay()
    {
        self.cropRectOverlay.isHidden = false
        
        let rectPath = UIBezierPath()
        
        //Rectangle drawing
        rectPath.move(to: topLeftButton.center)
//        rectPath.addLine(to: centerTopButton.center)
        rectPath.addLine(to: topRightButton.center)
//        rectPath.addLine(to: centerRightButton.center)
        rectPath.addLine(to: bottomRightButton.center)
//        rectPath.addLine(to: centerBottomButton.center)
        rectPath.addLine(to: bottomLeftButton.center)
//        rectPath.addLine(to: centerLeftButton.center)
        rectPath.addLine(to: topLeftButton.center)
        
        self.cropRectOverlay.path = rectPath.cgPath
    }
    
    //MARK: Crop and reshape image
    private func cropAndReshapeImage( completion: @escaping (_ croppedImage: UIImage) -> Void)
    {
        cameraViewController = IPDFCameraViewController(frame: CGRect.zero)
        
        let topRightPoint =  CGPoint(x: (topRightButton.center.y/scaleFactor), y: (topRightButton.center.x/scaleFactor))
        let bottomRightPoint = CGPoint(x: (bottomRightButton.center.y/scaleFactor), y: (bottomRightButton.center.x/scaleFactor))
        let bottomLeftPoint = CGPoint(x: (bottomLeftButton.center.y/scaleFactor), y: (bottomLeftButton.center.x/scaleFactor))
        let topLeftPoint = CGPoint(x: (topLeftButton.center.y/scaleFactor), y: (topLeftButton.center.x/scaleFactor))
        
        let rotatedImage = self.rotateImage(image: imageViewOutlet.image!, byAngle: -90)
        
        let cropImage : CIImage = CIImage(cgImage: (rotatedImage.cgImage)!)
        
        cameraViewController?.cropImage(cropImage, withFeatureRectPointsTopLeft: topLeftPoint, topRight: topRightPoint, bottomRight: bottomRightPoint, bottomLeft: bottomLeftPoint)
        { (croppedImageFilePath) in
            
            if let croppedImage = UIImage(contentsOfFile: croppedImageFilePath!)
            {
                //let rotatedImage = self.rotateImage(image: croppedImage, byAngle: 180)
                completion(croppedImage)
            }
        }
    }
    
    //MARK: Title Clicked
    @IBAction func titleButtonClicked(_ sender: UIButton) {
        let popvc = SelectAdmin(nibName: "SelectAdmin", bundle: nil) as SelectAdmin
        
//        let popvc = SelectAdminViewController(nibName: "SelectAdminViewController", bundle: nil)
        popvc.removeAdminSelectPopup = self as RemoveAdminSelectPopup
        self.addChildViewController(popvc)
        
        popvc.view.frame = self.view.frame
        
        self.view.addSubview(popvc.view)
        
        popvc.didMove(toParentViewController: self)
        titleButtonOutlet.isEnabled = false
    }
}
extension ViewController: RemoveAdminSelectPopup {
    func adminSelectPopupRemoved() {
        print("popupRemoved")
        titleButtonOutlet.isEnabled = true
    }
}
