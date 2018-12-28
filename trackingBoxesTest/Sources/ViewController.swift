//
//  ViewController.swift
//  trackingBoxesTest
//
//  Created by entropy on 25/12/2018.
//  Copyright © 2018 entropy. All rights reserved.
//

import UIKit
import ARKit
import CoreML
import Vision

class ViewController: UIViewController {
    
    // MARK: - Outlets
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var resetButton: UIButton!
    
    // MARK: - Properties
    private var rootLayer: CALayer!
    private var detectionOverlay: CALayer!
    private var objectsToTrack = [CGRect]()
    private var inputObservations = [UUID: VNDetectedObjectObservation]()
    private var rectsToDraw = [UUID: CGRect]()
    
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
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        resetSessionConfiguration()
    }

    // MARK: - Actions
    @objc func handleUserTap(_ sender: UITapGestureRecognizer) {
        print("Tap")
        
        guard let pixbuff = sceneView.session.currentFrame?.capturedImage else { return }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixbuff, orientation: .right
            , options: [:])
        do {
            try handler.perform([detectBikeRequest])
        } catch {
            print("Throws: \(error)")
        }
        
        
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
                print(transformedRect)
                let convertedRect = transformedRect.remaped(from: CGSize(width: 1.0, height: 1.0), to: self.sceneView.layer.bounds.size)
                
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
    func setupView() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleUserTap(_:)))
        
        sceneView.addGestureRecognizer(tapGestureRecognizer)
        sceneView.delegate = self
        
        resetButton.backgroundColor = .white
        resetButton.clipsToBounds = true
        resetButton.layer.cornerRadius = 4
        
        setupLayers()
    }
    
    func setupLayers() {
        rootLayer = sceneView.layer
        
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
        
        let config = ARWorldTrackingConfiguration()
        let options: ARSession.RunOptions = [.resetTracking]
        
        
        sceneView.session.run(config, options: options)
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
}

// MARK: - ARSCNViewDelegate
extension ViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let pixbuff = sceneView.session.currentFrame?.capturedImage else { return }
        
        drawRects()
        
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
    }
}

// MARK: - Constants
extension ViewController {
    private enum Constants {
        static let confidenceThreshold: Float = 0.7
    }
}
