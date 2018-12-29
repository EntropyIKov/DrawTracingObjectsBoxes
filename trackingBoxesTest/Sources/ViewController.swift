//
//  ViewController.swift
//  trackingBoxesTest
//
//  Created by entropy on 25/12/2018.
//  Copyright © 2018 entropy. All rights reserved.
//

import UIKit
import AVFoundation
import CoreML
import Vision

class ViewController: UIViewController {
    
    // MARK: - Outlets
    @IBOutlet weak var captureView: UIView!
    @IBOutlet weak var resetButton: UIButton!
    
    // MARK: - Properties
    var bufferSize: CGSize = .zero
    private var rootLayer: CALayer!
    private var detectionOverlay: CALayer!
    
    private var objectsToTrack = [CGRect]()
    private var inputObservations = [UUID: VNDetectedObjectObservation]()
    private var rectsToDraw = [UUID: CGRect]()
    
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer! = nil
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    private let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private var needToDetect = false
    
    private let trackingRequestHandler = VNSequenceRequestHandler()
    private var trackingLevel = VNRequestTrackingLevel.accurate
    private lazy var detectBikeRequest: VNCoreMLRequest = {
        do {
            let model = try VNCoreMLModel(for: MrCupper().model)
            
            return VNCoreMLRequest(model: model, completionHandler: handleBikeDetection)
        } catch {
            fatalError("Can't load Vision ML model: \(error)")
        }
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupView()
        
        startCaptureSession()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        resetSessionConfiguration()
    }

    // MARK: - Actions
    @objc func handleUserTap(_ sender: UITapGestureRecognizer) {
        needToDetect = true
    }
    
    func handleBikeDetection(_ request: VNRequest, error: Error?) {
        print("Detection")
        
        DispatchQueue.main.async {
            guard let observations = request.results else {
                return
            }
            
            for observation in observations where observation is VNRecognizedObjectObservation {
                guard let objectObservation = observation as? VNRecognizedObjectObservation,
                    objectObservation.confidence > Constants.confidenceThreshold else { continue }
                
                let boundingBox = objectObservation.boundingBox
                let detectedObjectObservation = VNDetectedObjectObservation(boundingBox: boundingBox)
                
                self.inputObservations[detectedObjectObservation.uuid] = detectedObjectObservation
            }
            
        }
    }
    
    func handleTrackingRequestUpdate(_ request: VNRequest, error: Error?) {
       
        DispatchQueue.main.async {
            guard let observations = request.results else {
                return
            }
            
            for observation in observations {
                guard let observation = observation as? VNDetectedObjectObservation else { return }
                
                var transformedRect = observation.boundingBox
                transformedRect.origin.y = 1 - transformedRect.origin.y - transformedRect.height
                
                let convertedRect = transformedRect.remaped(from: CGSize(width: 1.0, height: 1.0), to: self.captureView.layer.bounds.size)
                
                if let _ = self.inputObservations[observation.uuid] {
                    self.inputObservations[observation.uuid] = observation
                    self.rectsToDraw[observation.uuid] = convertedRect
                }
                
            }
        }
    }
    
    @IBAction func handleResetButtonTap(_ sender: UIButton) {
        resetSessionConfiguration()
    }
    
    
}

// MARK: - Private methods
private extension ViewController {
    func startCaptureSession() {
        session.startRunning()
    }
    
    // Clean up capture setup
    func teardownAVCapture() {
        previewLayer.removeFromSuperlayer()
        previewLayer = nil
    }
    
    func setupView() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleUserTap(_:)))
        
        captureView.addGestureRecognizer(tapGestureRecognizer)
        
        resetButton.backgroundColor = .white
        resetButton.clipsToBounds = true
        resetButton.layer.cornerRadius = 4
        
        setupAVCapture()
        setupLayers()
    }
    
    func setupAVCapture() {
        var deviceInput: AVCaptureDeviceInput!
        
        // Select a video device, make an input
        let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first
        do {
            deviceInput = try AVCaptureDeviceInput(device: videoDevice!)
        } catch {
            print("Could not create video device input: \(error)")
            return
        }
        
        session.beginConfiguration()
        session.sessionPreset = .vga640x480 // Model image size is smaller.
        
        // Add a video input
        guard session.canAddInput(deviceInput) else {
            print("Could not add video device input to the session")
            session.commitConfiguration()
            return
        }
        session.addInput(deviceInput)
        
        guard session.canAddOutput(videoDataOutput) else {
            print("Could not add video data output to the session")
            session.commitConfiguration()
            return
        }
        session.addOutput(videoDataOutput)
        // Add a video data output
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        let captureConnection = videoDataOutput.connection(with: .video)
        // Always process the frames
        captureConnection?.isEnabled = true
        do {
            try  videoDevice!.lockForConfiguration()
            let dimensions = CMVideoFormatDescriptionGetDimensions((videoDevice?.activeFormat.formatDescription)!)
            bufferSize.width = CGFloat(dimensions.width)
            bufferSize.height = CGFloat(dimensions.height)
            videoDevice!.unlockForConfiguration()
        } catch {
            print(error)
        }
        session.commitConfiguration()
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        rootLayer = captureView.layer
        previewLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(previewLayer)
    }
    
    func setupLayers() {
//        rootLayer = captureView.layer
        
        detectionOverlay = CALayer()
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = rootLayer.bounds
        detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        
        rootLayer.addSublayer(detectionOverlay)
    }
    
    func resetSessionConfiguration() {
        objectsToTrack.removeAll()
        inputObservations.removeAll()
        rectsToDraw.removeAll()
        detectionOverlay.sublayers = nil

    }
    
    // Drawing
    func drawRects() {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        detectionOverlay.sublayers = nil
        
        for (_, rect) in rectsToDraw {
            let shapeLayer = createRoundedRectLayerWithBounds(rect)

            detectionOverlay.addSublayer(shapeLayer)
        }
        
        CATransaction.commit()
    }
    
    func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.2, 1.0, 1.0, 0.4])
        shapeLayer.cornerRadius = 7
        return shapeLayer
    }
    
    func exifOrientationFromDeviceOrientation() -> CGImagePropertyOrientation {
        let curDeviceOrientation = UIDevice.current.orientation
        let exifOrientation: CGImagePropertyOrientation
        
        switch curDeviceOrientation {
        case UIDeviceOrientation.portraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = .left
        case UIDeviceOrientation.landscapeLeft:       // Device oriented horizontally, home button on the right
            exifOrientation = .upMirrored
        case UIDeviceOrientation.landscapeRight:      // Device oriented horizontally, home button on the left
            exifOrientation = .down
        case UIDeviceOrientation.portrait:            // Device oriented vertically, home button on the bottom
            exifOrientation = .up
        default:
            exifOrientation = .up
        }
        return exifOrientation
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixbuff = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                
        if needToDetect {
            needToDetect = false
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixbuff, orientation: .right, options: [:])
            do {
                try handler.perform([detectBikeRequest])
            } catch {
                print("Throws: \(error)")
            }
        }
        
        var requests = [VNRequest]()
        for observation in inputObservations {
            let request = VNTrackObjectRequest(detectedObjectObservation: observation.value, completionHandler: handleTrackingRequestUpdate)
            request.trackingLevel = trackingLevel
            requests.append(request)
        }

        do {
            try trackingRequestHandler.perform(requests, on: pixbuff, orientation: .right)
        } catch {
            print("Throws: \(error)")
        }
        
        drawRects()
    }
    
//    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
//        guard let pixbuff = sceneView.session.currentFrame?.capturedImage else { return }
//
//        drawRects()
//
//        var requests = [VNRequest]()
//        for observation in inputObservations {
//            let request = VNTrackObjectRequest(detectedObjectObservation: observation.value, completionHandler: handleTrackingRequestUpdate)
//            request.trackingLevel = trackingLevel
//            requests.append(request)
//        }
//
//        do {
//            try trackingRequestHandler.perform(requests, on: pixbuff, orientation: .right)
//        } catch {
//            print("Throws: \(error)")
//        }
//    }
}

// MARK: - Constants
extension ViewController {
    private enum Constants {
        static let confidenceThreshold: Float = 0.1
    }
}
