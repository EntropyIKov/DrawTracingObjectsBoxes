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
    
    // MARK: - Properties
    private var objectsToTrack = [CGRect]()
    private var inputObservations = [UUID: VNDetectedObjectObservation]()
    private var rectsToDraw = [UUID: CGRect]()
    private var presentingViews = [UUID: UIView]()
    
    private let trackingRequestHandler = VNSequenceRequestHandler()
    private var trackingLevel = VNRequestTrackingLevel.accurate
    private lazy var detectBikeRequest: VNCoreMLRequest = {
        do {
            let model = try VNCoreMLModel(for: CarsAndBikesDetector().model)
            
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
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixbuff, options: [:])
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
                
                let detectedObjectObservation = VNDetectedObjectObservation(boundingBox: objectObservation.boundingBox)
                self.inputObservations[detectedObjectObservation.uuid] = detectedObjectObservation
            }
            
        }
    }
    
    func handleTrackingRequestUpdate(_ request: VNRequest, error: Error?) {
        print("Update")
        
        DispatchQueue.main.async {
            guard let observations = request.results else {
                return
            }
            
            for observation in observations {
                guard let observation = observation as? VNDetectedObjectObservation else { return }
                
                var transformedRect = observation.boundingBox
                transformedRect.origin.y = 1 - transformedRect.origin.y
                let convertedRect = transformedRect.remaped(from: CGSize(width: 1.0, height: 1.0), to: self.sceneView.layer.bounds.size)
                
                self.inputObservations[observation.uuid] = observation
                
                self.presentingViews[observation.uuid]?.frame = convertedRect
//                self.addPresentingView(frame: convertedRect, uuid: observation.uuid)
            }
        }
    }
    
}

// MARK: - Private methods
private extension ViewController {
    func setupView() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleUserTap(_:)))
        
        sceneView.addGestureRecognizer(tapGestureRecognizer)
        sceneView.delegate = self
    }
    
    func resetSessionConfiguration() {
        let config = ARWorldTrackingConfiguration()
        let options: ARSession.RunOptions = [.resetTracking]
        
        sceneView.session.run(config, options: options)
    }
    
    func addPresentingView(frame: CGRect, uuid: UUID) {
        let view = UIView(frame: frame)
        
        view.layer.borderColor = UIColor.red.cgColor
        view.layer.borderWidth = 2
        view.backgroundColor = .clear
        
        presentingViews[uuid] = view
    }
}

// MARK: - ARSCNViewDelegate
extension ViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let pixbuff = sceneView.session.currentFrame?.capturedImage else { return }
        
        var requests = [VNRequest]()
        for observation in inputObservations {
            let request = VNTrackObjectRequest(detectedObjectObservation: observation.value, completionHandler: handleTrackingRequestUpdate)
            request.trackingLevel = trackingLevel
            requests.append(request)
        }
        
        do {
            try trackingRequestHandler.perform(requests, on: pixbuff)
        } catch {
            print("Throws: \(error)")
        }
    }
}

// MARK: - Constants
extension ViewController {
    private enum Constants {
        static let confidenceThreshold: Float = 0.1
    }
}
