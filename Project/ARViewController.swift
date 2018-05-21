//
//  ARRecognitionController.swift
//  Project
//
//  Created by Brendan Milton on 05/12/2017.
//  Copyright © 2017 Brendan Milton. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import Vision

class ARViewController: ViewController, ARSCNViewDelegate  {
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var predictionLabel: UILabel!
    
    var currentPrediction = "Empty"
    var currentConfidence = "Empty"
    var visionRequests = [VNRequest]()
    
    // Use queue to make sure coreml requeusts are running smoothly without effecting other processes
    let coreMLQueue = DispatchQueue(label: "com.rume.coremlqueue")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Create a new scene
        let scene = SCNScene()
        
        // Set the scene to the view
        sceneView.scene = scene
        
        // Automatically adjust lightning for ARobjects
        sceneView.autoenablesDefaultLighting = true
        
        initializeModel()
        coreMLUpdate()
    }
    
    // Following functions are in charge of running pausing and resuming AR session
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    // Pauses session
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    // Gets called each time camera changes its tracking state
    // User indicates wether or not ready to recognize object
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        
        // Checks value of camera.tracking state
        switch camera.trackingState {
        // Camera could still be initializing
        case .limited(let reason):
            statusLabel.text = "Tracking limited: \(reason)"
        // Camera issue could be halting tracking
        case .notAvailable:
            statusLabel.text = "Tracking unavailable"
        case .normal:
            statusLabel.text = "Tap to add a Label"
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        tapHandler()
    }
    
    //Handle user tapping on screen
    func tapHandler(){
        // Get centre point for AR label
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        // Feature point to place label
        let hitTestResults = sceneView.hitTest(center, types: [.featurePoint])
        
        if let closestPoint = hitTestResults.first {
            let transform = closestPoint.worldTransform
            let worldPosition = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            
            // Create prediction text
            let node = createText(for: currentPrediction)
            sceneView.scene.rootNode.addChildNode(node)
            node.position = worldPosition
        }
    }
    
    func createText(for string: String) -> SCNNode {
        
        let text = SCNText(string: string, extrusionDepth: 0.01)
        let font = UIFont(name: "AvenirNext-Bold", size: 0.15)
        text.font = font
        text.alignmentMode = kCAAlignmentCenter
        text.firstMaterial?.diffuse.contents = UIColor(red: 52/255, green: 152/255, blue: 219/255, alpha : 1.0)
        // let confidence = prediction.confidence
        text.firstMaterial?.specular.contents = UIColor.white
        text.firstMaterial?.isDoubleSided = true
        
        let textNode = SCNNode(geometry: text)
        let bounds = text.boundingBox
        
        // Pivot and center when label placed
        textNode.pivot = SCNMatrix4MakeTranslation((bounds.max.x - bounds.min.x)/2, bounds.min.y, 0.005)
        
        textNode.scale = SCNVector3Make(0.2, 0.2, 0.2)
        
        let sphere = SCNSphere(radius: 0.005)
        sphere.firstMaterial?.diffuse.contents = UIColor(red: 52/255, green: 152/255, blue: 219/255, alpha : 1.0)
        let sphereNode = SCNNode(geometry: sphere)
        
        // Label contraints rotation
        let billBoardConstraint = SCNBillboardConstraint()
        billBoardConstraint.freeAxes = SCNBillboardAxis.Y
        
        let parentNode = SCNNode()
        parentNode.addChildNode(textNode)
        parentNode.addChildNode(sphereNode)
    
        parentNode.constraints = [billBoardConstraint]
        
        return parentNode
    }
    
    // Initialize coreml model
    func initializeModel() {
        guard let model = try? VNCoreMLModel(for: Inceptionv3().model) else {
            print("Could not load model")
            return
        }
        
        // Completion handler
        let classificationRequest = VNCoreMLRequest(model: model, completionHandler: classificationCompletionHandler)
        // Crop photo and scale image from center to pass correct format to Carrecognition model
        classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop
        visionRequests = [classificationRequest]
    }
    
    // get vision request result to work with
    func classificationCompletionHandler(request: VNRequest, error: Error?) {
        // Check error
        if error != nil {
            // print error and return so not to continue
            print(error?.localizedDescription as Any)
            return
        }
        // Access results of vision request
        guard let results = request.results else {
            print("No results found")
            return
        }
        
        // If not nil prediction will contain a classification
        if let prediction = results.first as? VNClassificationObservation {
            
            // ****** SHOW IN LIVE LABEL USE IN AR LABEL
            // Obtain prediction information for label
            let object = prediction.identifier
            let confidence = prediction.confidence
            currentPrediction = object
            currentConfidence = "\(confidence)"
            DispatchQueue.main.async {
                self.predictionLabel.text = self.currentPrediction // self.currentConfidence
            }
            
            /* let classifications = results.map { observation in
                "\(observation.identifier) \(observation.confidence * 100)"
            } */
            
        }
    }
    
    // Continuously called from coreml update to check latest image
    func visionRequest() {
        // Create vision framework request
        let pixelBuffer = sceneView.session.currentFrame?.capturedImage
        if pixelBuffer == nil {
            return
        }
        
        let image = CIImage(cvPixelBuffer: pixelBuffer!)
        
        // Perform requests with vision framework
        let imageRequestHandler = VNImageRequestHandler(ciImage: image, options: [:])
        
        do {
            // Pass vision request that contains model
            try imageRequestHandler.perform(self.visionRequests)
        } catch {
            print(error)
        }
    }
    
    // APP DIFFERENCE due to augmented reality constant image changing model must update to keep up
    // Constantly update to offer predictions based on what is seen
    func coreMLUpdate() {
        // Runs in custom queue
        coreMLQueue.async {
            
            self.visionRequest()
            // calls itself to continually run
            self.coreMLUpdate()
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    
    @IBAction func MainScreenPressedButton(_ sender: Any) {
        
        self.performSegue(withIdentifier: "MainScreenSegue4", sender: self)
    }
}


