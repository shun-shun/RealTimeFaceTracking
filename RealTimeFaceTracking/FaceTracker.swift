//
//  FaceTracker.swift
//  RealTimeFaceTracking
//
//  Created by しゅん on 2020/01/18.
//  Copyright © 2020 g-chan. All rights reserved.
//
import UIKit
import AVFoundation

class FaceTracker: NSObject,AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    let videoDevice = AVCaptureDevice.default(for: AVMediaType.video)
    let audioDevice = AVCaptureDevice.default(for: AVMediaType.audio)
    
    var videoOutput = AVCaptureVideoDataOutput()
    var view:UIView
    var hideView = UIView()
    private var findface : (_ arr:Array<CGRect>) -> Void
    required init(view:UIView, findface: @escaping (_ arr:Array<CGRect>) -> Void)
    {
        self.view=view
        self.findface = findface
        super.init()
        self.initialize()
    }
    
    
    func initialize()
    {
        //各デバイスの登録(audioは実際いらない)
        do {
            let videoInput = try AVCaptureDeviceInput(device: self.videoDevice!) as AVCaptureDeviceInput
            self.captureSession.addInput(videoInput)
        } catch let error as NSError {
            print(error)
        }
        do {
            let audioInput = try AVCaptureDeviceInput(device: self.audioDevice!) as AVCaptureInput
            self.captureSession.addInput(audioInput)
        } catch let error as NSError {
            print(error)
        }
        
        self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable as! String : Int(kCVPixelFormatType_32BGRA)]
        
        //フレーム毎に呼び出すデリゲート登録
        //let queue:DispatchQueue = DispatchQueue(label:"myqueue",attribite: DISPATCH_QUEUE_SERIAL)
        let queue:DispatchQueue = DispatchQueue(label: "myqueue", attributes: .concurrent)
        self.videoOutput.setSampleBufferDelegate(self, queue: queue)
        self.videoOutput.alwaysDiscardsLateVideoFrames = true
        
        self.captureSession.addOutput(self.videoOutput)
        
        let videoLayer : AVCaptureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        videoLayer.frame = self.view.bounds
        videoLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        
        self.view.layer.addSublayer(videoLayer)
        
        //カメラ向き
        for connection in self.videoOutput.connections {
            let conn = connection
            if conn.isVideoOrientationSupported {
                conn.videoOrientation = AVCaptureVideoOrientation.portrait
            }
        }
        
        hideView = UIView(frame: self.view.bounds)
        self.view.addSubview(hideView)
        self.captureSession.startRunning()
    }
    
    func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage {
        //バッファーをUIImageに変換
        let imageBuffer: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let baseAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = (CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        let context = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)
        let imageRef = context!.makeImage()
        
        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let resultImage: UIImage = UIImage(cgImage: imageRef!)
        return resultImage
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        //同期処理（非同期処理ではキューが溜まりすぎて画面がついていかない）
        DispatchQueue.main.sync(execute: {
            
            //バッファーをUIImageに変換
            let image = self.imageFromSampleBuffer(sampleBuffer: sampleBuffer)
            let ciimage:CIImage! = CIImage(image: image)
            
            //CIDetectorAccuracyHighだと高精度（使った感じは遠距離による判定の精度）だが処理が遅くなる
            let detector : CIDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options:[CIDetectorAccuracy: CIDetectorAccuracyLow] )!
            let faces : [CIFaceFeature] = detector.features(in: ciimage) as! [CIFaceFeature]
            
            // 検出された顔データを処理
            for subview:UIView in self.hideView.subviews  {
                subview.removeFromSuperview()
            }
            
            
            if faces.count != 0
            {
                var rects = Array<CGRect>();
                var _ : CIFaceFeature = CIFaceFeature()
                for feature in faces {
                    
                    // 座標変換
                    var faceRect : CGRect = (feature as AnyObject).bounds
                    let widthPer = (self.view.bounds.width/image.size.width)
                    let heightPer = (self.view.bounds.height/image.size.height)
                    
                    let EyeHeight = faceRect.size.height/4
                    let EyeWidth = faceRect.size.width/3
                    
                    //左目
                    if feature.hasLeftEyePosition {
                        let leftEyeRect = self.toUIRectToLeftEye(image: image,
                                                                 feature: feature,
                                                                 widthPer: widthPer,
                                                                 heightPer: heightPer,
                                                                 originWidth: EyeWidth,
                                                                 originHeight: EyeHeight)
                        let leftEyeView = UIView(frame: leftEyeRect)
                        leftEyeView.layer.borderColor = UIColor.green.cgColor//四角い枠を用意しておく
                        leftEyeView.layer.borderWidth = 3
                        self.hideView.addSubview(leftEyeView)

                        let leftProcessingRect = self.toUIRectToLeftEye(image: image,
                                                                 feature: feature,
                                                                 widthPer: widthPer,
                                                                 heightPer: heightPer,
                                                                 originWidth: EyeWidth,
                                                                 originHeight: EyeHeight)
                        let leftEyeCIImage = ciimage.cropped(to: leftProcessingRect)

                        let ciFilter:CIFilter = CIFilter(name: "CIColorMonochrome")!
                        ciFilter.setValue(leftEyeCIImage, forKey: kCIInputImageKey)
                        ciFilter.setValue(CIColor(red: 0.75, green: 0.75, blue: 0.75), forKey: "inputColor")
                        ciFilter.setValue(1.0, forKey: "inputIntensity")
                        let ciContext:CIContext = CIContext(options: nil)
                        let cgimg:CGImage = ciContext.createCGImage(ciFilter.outputImage!, from:ciFilter.outputImage!.extent)!

                        let prosessing = UIImage(cgImage: cgimg, scale: 1.0, orientation:UIImage.Orientation.up)
                        let prosessingView = UIImageView(image: prosessing)
                        prosessingView.frame = leftEyeRect
                        self.hideView.addSubview(prosessingView)
                    }
                    
                    //右目
                    if feature.hasRightEyePosition {
                        let rightEyeRect = self.toUIRectToRightEye(image: image,
                                                                   feature: feature,
                                                                   widthPer: widthPer,
                                                                   heightPer: heightPer,
                                                                   originWidth: EyeWidth,
                                                                   originHeight: EyeHeight)
                        let rightEyeView = UIView(frame: rightEyeRect)
                        rightEyeView.layer.borderColor = UIColor.green.cgColor//四角い枠を用意しておく
                        rightEyeView.layer.borderWidth = 3
                        self.hideView.addSubview(rightEyeView)
                    }
                    
                    //口
                    if feature.hasMouthPosition {
                        let mouthHeight = faceRect.size.height/4
                        let mouthWidth = faceRect.size.width/2
                        
                        let mouthRectY = image.size.height - feature.mouthPosition.y - mouthHeight/2
                        let mouthRectX = feature.mouthPosition.x - mouthWidth/2
                        
                        let mouthRect = CGRect(x: mouthRectX * widthPer,
                                               y: mouthRectY * heightPer,
                                               width: mouthWidth * widthPer,
                                               height: mouthHeight * heightPer)
                        let mouthView = UIView(frame: mouthRect)
                        mouthView.layer.borderColor = UIColor.red.cgColor//四角い枠を用意しておく
                        mouthView.layer.borderWidth = 3
                        self.hideView.addSubview(mouthView)
                    }
                    
                    // UIKitは左上に原点があるが、CoreImageは左下に原点があるので揃える
                    faceRect.origin.y = image.size.height - faceRect.origin.y - faceRect.size.height
                    
                    //倍率変換
                    faceRect.origin.x = faceRect.origin.x * widthPer
                    faceRect.origin.y = faceRect.origin.y * heightPer
                    faceRect.size.width = faceRect.size.width * widthPer
                    faceRect.size.height = faceRect.size.height * heightPer
                    rects.append(faceRect)
                    
                    // 顔を隠す画像を表示
                    let faceView = UIView(frame: faceRect)
                    faceView.layer.borderWidth = 3//四角い枠を用意しておく
                    //                    print("face    X: \(faceView.frame.origin.x)  Y:\(faceView.frame.origin.y)")
                    //let hideImage = UIImageView(image:UIImage(named:"lauhuman.jpg"))
                    //hideImage.frame = faceRect
                    
                    self.hideView.addSubview(faceView)
                }
                self.findface(rects)
            }
        })
    }
    func uiRectToCirect(image:UIImage,feature:CIFaceFeature,widthPer:CGFloat,heightPer:CGFloat,originWidth:CGFloat,originHeight:CGFloat) -> CGRect {
        let originRectY = feature.leftEyePosition.y
        let originRectX = feature.leftEyePosition.x
        return CGRect(x: originRectX,
                      y: originRectY,
                      width: self.view.bounds.width,
                      height: self.view.bounds.height)
    }
    
    func toUIRectToLeftEye(image:UIImage,feature:CIFaceFeature,widthPer:CGFloat,heightPer:CGFloat,originWidth:CGFloat,originHeight:CGFloat) -> CGRect {
        let originRectY = image.size.height - (feature.leftEyePosition.y + originHeight/2)
        let originRectX = feature.leftEyePosition.x - originWidth/2
        return CGRect(x: originRectX * widthPer,
                      y: originRectY * heightPer,
                      width: originWidth * widthPer,
                      height: originHeight * heightPer)
    }
    
    func toUIRectToRightEye(image:UIImage,feature:CIFaceFeature,widthPer:CGFloat,heightPer:CGFloat,originWidth:CGFloat,originHeight:CGFloat) -> CGRect {
        let originRectY = image.size.height - (feature.rightEyePosition.y + originHeight/2)
        let originRectX = feature.rightEyePosition.x - originWidth/2
        return CGRect(x: originRectX * widthPer,
                      y: originRectY * heightPer,
                      width: originWidth * widthPer,
                      height: originHeight * heightPer)
    }
}
