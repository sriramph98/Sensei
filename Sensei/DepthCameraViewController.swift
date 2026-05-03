import UIKit
import AVFoundation
import ARKit
import Vision
import VisionKit

class DepthCameraViewController: UIViewController {
    private var session: AVCaptureSession!
    private var depthDataOutput: AVCaptureDepthDataOutput!
    private var videoDataOutput: AVCaptureVideoDataOutput!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var depthView: UIImageView!
    private var statusLabel: UILabel!
    private var depthLegendView: UIView!
    private var depthLegendLabels: [UILabel] = []
    
    // Add UI visibility toggle
    private var uiToggleButton: UIButton!
    private var isUIHidden: Bool = false {
        didSet {
            updateUIVisibility()
        }
    }
    
    // Object detection properties
    private var objectDetectionToggle: UISwitch!
    private var objectDetectionLabel: UILabel!
    private var detectedObjectsView: UIView!
    private var detectedObjectsLabel: UILabel!
    private var isObjectDetectionEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "isObjectDetectionEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isObjectDetectionEnabled")
        }
    }
    private lazy var objectDetectionRequest: VNClassifyImageRequest = {
        let request = VNClassifyImageRequest()
        request.revision = VNClassifyImageRequestRevision1
        return request
    }()
    
    // Add haptic toggle
    private var hapticToggle: UISwitch!
    private var hapticLabel: UILabel!
    private var isHapticEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "isHapticEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isHapticEnabled")
        }
    }
    
    // Add haptic feedback properties
    private var lightHaptic: UIImpactFeedbackGenerator!
    private var mediumHaptic: UIImpactFeedbackGenerator!
    private var heavyHaptic: UIImpactFeedbackGenerator!
    private var lastHapticTime: TimeInterval = 0
    private let hapticCooldown: TimeInterval = 0.2  // Minimum time between haptics
    
    // Speech synthesis property
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenTime: TimeInterval = 0
    private let minimumTimeBetweenSpeeches: TimeInterval = 1.0  // Minimum 1 second between speeches
    private var latestDetection: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupInitialUI()
        setupHapticFeedback()
        setupTapGesture()
        checkCameraPermission()
    }
    
    override var shouldAutorotate: Bool {
        return false
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.showPermissionDenied()
                    }
                }
            }
        default:
            showPermissionDenied()
        }
    }
    
    private func showPermissionDenied() {
        statusLabel.text = "Camera access denied"
        statusLabel.textColor = .red
    }
    
    private func setupInitialUI() {
        view.backgroundColor = .black
        
        // Create depth visualization view first (will be at the bottom)
        depthView = UIImageView(frame: view.bounds)
        depthView.contentMode = .scaleAspectFill
        depthView.alpha = 0.8
        view.addSubview(depthView)
        
        // Create UI container that will hold all UI elements
        let uiContainer = UIView(frame: view.bounds)
        view.addSubview(uiContainer)
        
        // Create UI toggle button
        setupUIToggleButton(in: uiContainer)
        
        // Create status label
        statusLabel = UILabel(frame: CGRect(x: 20, y: 50, width: view.bounds.width - 40, height: 30))
        statusLabel.textColor = .white
        statusLabel.text = "Initializing..."
        statusLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        uiContainer.addSubview(statusLabel)
        
        // Create haptic toggle
        setupHapticToggle(in: uiContainer)
        
        // Create object detection toggle
        setupObjectDetectionToggle(in: uiContainer)
        
        // Create depth legend
        setupDepthLegend(in: uiContainer)
        
        // Create detected objects view
        setupDetectedObjectsView(in: uiContainer)
    }
    
    private func setupUIToggleButton(in container: UIView) {
        uiToggleButton = UIButton(type: .system)
        uiToggleButton.frame = CGRect(x: container.bounds.width - 60, y: 20, width: 40, height: 40)
        uiToggleButton.setTitle("UI", for: .normal)
        uiToggleButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        uiToggleButton.setTitleColor(.white, for: .normal)
        uiToggleButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        uiToggleButton.layer.cornerRadius = 8
        uiToggleButton.addTarget(self, action: #selector(toggleUI), for: .touchUpInside)
        container.addSubview(uiToggleButton)
    }
    
    @objc private func toggleUI() {
        isUIHidden.toggle()
    }
    
    private func updateUIVisibility() {
        let alpha: CGFloat = isUIHidden ? 0.0 : 1.0
        UIView.animate(withDuration: 0.3) {
            // Hide all UI elements and their containers
            self.statusLabel.alpha = alpha
            self.hapticToggle?.alpha = alpha
            self.hapticLabel?.alpha = alpha
            self.hapticToggle?.superview?.alpha = alpha  // Hide haptic container
            self.objectDetectionToggle?.alpha = alpha
            self.objectDetectionLabel?.alpha = alpha
            self.objectDetectionToggle?.superview?.alpha = alpha  // Hide object detection container
            self.detectedObjectsView?.alpha = alpha
            self.detectedObjectsLabel?.alpha = alpha
            self.depthLegendView?.alpha = alpha
            self.depthLegendLabels.forEach { $0.alpha = alpha }
            self.uiToggleButton.alpha = 1.0  // Keep the toggle button always visible
        }
    }
    
    private func setupDepthLegend(in container: UIView) {
        // Create legend container
        depthLegendView = UIView(frame: CGRect(x: 20, y: 190, width: 40, height: 100))
        depthLegendView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        depthLegendView.layer.cornerRadius = 8
        container.addSubview(depthLegendView)
        
        // Create gradient view
        let gradientView = UIView(frame: CGRect(x: 5, y: 5, width: 30, height: 90))
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = gradientView.bounds
        gradientLayer.colors = [
            UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0).cgColor,  // RED (CLOSE)
            UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0).cgColor   // BLUE (FAR)
        ]
        gradientLayer.locations = [0.0, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        gradientView.layer.addSublayer(gradientLayer)
        depthLegendView.addSubview(gradientView)
        
        // Clear existing labels
        depthLegendLabels.forEach { $0.removeFromSuperview() }
        depthLegendLabels.removeAll()
        
        // Create depth labels with more granular distances
        let distances = ["CLOSE", "MID", "FAR"]
        for (index, distance) in distances.enumerated() {
            let label = UILabel(frame: CGRect(x: 45, y: CGFloat(index) * 45, width: 60, height: 20))
            label.text = distance
            label.textColor = .white
            label.font = UIFont.systemFont(ofSize: 12)
            depthLegendLabels.append(label)
            depthLegendView.addSubview(label)
        }
    }
    
    private func setupHapticToggle(in container: UIView) {
        // Create container view for haptic controls
        let containerView = UIView(frame: CGRect(x: 20, y: 90, width: container.bounds.width - 40, height: 40))
        containerView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        containerView.layer.cornerRadius = 8
        container.addSubview(containerView)
        
        // Create haptic label
        hapticLabel = UILabel(frame: CGRect(x: 15, y: 0, width: 120, height: 40))
        hapticLabel.text = "Haptic Feedback"
        hapticLabel.textColor = .white
        hapticLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        containerView.addSubview(hapticLabel)
        
        // Create haptic toggle switch
        hapticToggle = UISwitch(frame: CGRect(x: containerView.bounds.width - 65, y: 5, width: 51, height: 31))
        hapticToggle.isOn = isHapticEnabled
        hapticToggle.addTarget(self, action: #selector(hapticToggleChanged), for: .valueChanged)
        containerView.addSubview(hapticToggle)
    }
    
    private func setupObjectDetectionToggle(in container: UIView) {
        // Create container view for object detection controls
        let containerView = UIView(frame: CGRect(x: 20, y: 140, width: container.bounds.width - 40, height: 40))
        containerView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        containerView.layer.cornerRadius = 8
        container.addSubview(containerView)
        
        // Create object detection label
        objectDetectionLabel = UILabel(frame: CGRect(x: 15, y: 0, width: 120, height: 40))
        objectDetectionLabel.text = "Object Detection"
        objectDetectionLabel.textColor = .white
        objectDetectionLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        containerView.addSubview(objectDetectionLabel)
        
        // Create object detection toggle switch
        objectDetectionToggle = UISwitch(frame: CGRect(x: containerView.bounds.width - 65, y: 5, width: 51, height: 31))
        objectDetectionToggle.isOn = isObjectDetectionEnabled
        objectDetectionToggle.addTarget(self, action: #selector(objectDetectionToggleChanged), for: .valueChanged)
        containerView.addSubview(objectDetectionToggle)
    }
    
    private func setupDetectedObjectsView(in container: UIView) {
        // Create container for detected objects
        detectedObjectsView = UIView(frame: CGRect(x: 20, y: container.bounds.height - 180, width: container.bounds.width - 40, height: 50))
        detectedObjectsView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        detectedObjectsView.layer.cornerRadius = 8
        container.addSubview(detectedObjectsView)
        
        // Create label for detected objects
        detectedObjectsLabel = UILabel(frame: CGRect(x: 15, y: 0, width: detectedObjectsView.bounds.width - 30, height: 50))
        detectedObjectsLabel.textColor = .white
        detectedObjectsLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        detectedObjectsLabel.text = "No objects detected"
        detectedObjectsLabel.textAlignment = .left
        detectedObjectsLabel.numberOfLines = 2
        detectedObjectsView.addSubview(detectedObjectsLabel)
    }
    
    private func setupTapGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tapGesture)
    }
    
    @objc private func hapticToggleChanged(_ sender: UISwitch) {
        isHapticEnabled = sender.isOn
        if sender.isOn {
            // Provide feedback that haptics are enabled
            lightHaptic.impactOccurred()
        }
    }
    
    @objc private func objectDetectionToggleChanged(_ sender: UISwitch) {
        isObjectDetectionEnabled = sender.isOn
        detectedObjectsView.isHidden = !sender.isOn
    }
    
    @objc private func handleTap() {
        guard isObjectDetectionEnabled else { return }
        
        guard let latestDetection = latestDetection else {
            speakText("No objects detected")
            return
        }
        speakText(latestDetection)
    }
    
    private func setupCamera() {
        session = AVCaptureSession()
        session.sessionPreset = .photo
        
        // First try to get the LiDAR camera
        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else {
            print("LiDAR camera not available")
            DispatchQueue.main.async {
                self.statusLabel.text = "LiDAR camera not available"
                self.statusLabel.textColor = .red
            }
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.addInput(input)
            
            // Setup depth data output
            depthDataOutput = AVCaptureDepthDataOutput()
            depthDataOutput.setDelegate(self, callbackQueue: DispatchQueue.main)
            session.addOutput(depthDataOutput)
            
            // Setup video data output
            videoDataOutput = AVCaptureVideoDataOutput()
            videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
            session.addOutput(videoDataOutput)
            
            // Connect depth and video outputs
            if let connection = depthDataOutput.connection(with: .depthData) {
                connection.isEnabled = true
                if #available(iOS 17.0, *) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                } else {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                }
            }
            
            // Set video orientation
            if let connection = videoDataOutput.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                } else {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                }
            }
            
            // Create and setup preview layer at the bottom of the view hierarchy
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.frame = view.bounds
            previewLayer.videoGravity = .resizeAspectFill
            if #available(iOS 17.0, *) {
                previewLayer.connection?.videoRotationAngle = 90
            } else {
                previewLayer.connection?.videoOrientation = .portrait
            }
            view.layer.insertSublayer(previewLayer, at: 0)  // Insert at index 0 to keep it at the bottom
            
            // Start the session on a background thread
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.statusLabel.text = "Camera running"
                    self.statusLabel.textColor = .green
                }
            }
            
        } catch {
            print("Error setting up camera: \(error)")
            DispatchQueue.main.async {
                self.statusLabel.text = "Error setting up camera"
                self.statusLabel.textColor = .red
            }
        }
    }
    
    private func setupHapticFeedback() {
        lightHaptic = UIImpactFeedbackGenerator(style: .light)
        mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
        heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
        
        // Prepare haptics for minimal latency
        lightHaptic.prepare()
        mediumHaptic.prepare()
        heavyHaptic.prepare()
    }
    
    private func generateHapticFeedback(forDepth depth: Float) {
        guard isHapticEnabled else { return }
        
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastHapticTime >= hapticCooldown else { return }
        
        // Only vibrate for close objects (RED in visualization)
        if depth < 0.5 {
            // The closer the object, the stronger the haptic
            if depth < 0.2 {
                print("Very close object detected: \(depth)m - Heavy haptic")
                heavyHaptic.impactOccurred()
            } else if depth < 0.35 {
                print("Close object detected: \(depth)m - Medium haptic")
                mediumHaptic.impactOccurred()
            } else {
                print("Moderately close object detected: \(depth)m - Light haptic")
                lightHaptic.impactOccurred()
            }
            lastHapticTime = currentTime
        } else {
            print("Object too far: \(depth)m - No haptic")
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        depthView.frame = view.bounds
        
        if let container = statusLabel.superview {
            // Calculate safe area insets
            let safeArea = view.safeAreaInsets
            
            // Update UI toggle button
            uiToggleButton.frame = CGRect(x: container.bounds.width - 60 - safeArea.right, 
                                        y: 20 + safeArea.top, 
                                        width: 40, 
                                        height: 40)
            
            // Update status label
            statusLabel.frame = CGRect(x: 20 + safeArea.left, 
                                     y: 50 + safeArea.top, 
                                     width: container.bounds.width - 40 - safeArea.left - safeArea.right, 
                                     height: 30)
            
            // Update haptic toggle
            if let containerView = hapticToggle?.superview {
                containerView.frame = CGRect(x: 20 + safeArea.left, 
                                           y: 90 + safeArea.top, 
                                           width: container.bounds.width - 40 - safeArea.left - safeArea.right, 
                                           height: 40)
                hapticLabel?.frame = CGRect(x: 15, y: 0, width: 120, height: 40)
                hapticToggle?.frame = CGRect(x: containerView.bounds.width - 65, y: 5, width: 51, height: 31)
            }
            
            // Update object detection toggle
            if let containerView = objectDetectionToggle?.superview {
                containerView.frame = CGRect(x: 20 + safeArea.left, 
                                           y: 140 + safeArea.top, 
                                           width: container.bounds.width - 40 - safeArea.left - safeArea.right, 
                                           height: 40)
                objectDetectionLabel?.frame = CGRect(x: 15, y: 0, width: 120, height: 40)
                objectDetectionToggle?.frame = CGRect(x: containerView.bounds.width - 65, y: 5, width: 51, height: 31)
            }
            
            // Update depth legend
            depthLegendView.frame = CGRect(x: 20 + safeArea.left, 
                                         y: 190 + safeArea.top, 
                                         width: 40, 
                                         height: 100)
            for (index, label) in depthLegendLabels.enumerated() {
                label.frame = CGRect(x: 45, y: CGFloat(index) * 45, width: 60, height: 20)
            }
            
            // Update detected objects view
            detectedObjectsView?.frame = CGRect(x: 20 + safeArea.left, 
                                              y: container.bounds.height - 180 - safeArea.bottom, 
                                              width: container.bounds.width - 40 - safeArea.left - safeArea.right, 
                                              height: 50)
            detectedObjectsLabel?.frame = CGRect(x: 15, y: 0, width: (detectedObjectsView?.bounds.width ?? 0) - 30, height: 50)
        }
        
        // Update preview layer orientation
        if let connection = previewLayer?.connection {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
        }
    }
    
    private func detectObjects(in image: CVPixelBuffer) {
        guard isObjectDetectionEnabled else { return }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .up)
        
        do {
            try imageRequestHandler.perform([objectDetectionRequest])
            
            guard let results = objectDetectionRequest.results else { return }
            
            // Process detection results
            let detectedObjects = results
                .prefix(3)  // Show top 3 detected objects
                .map { observation -> String in
                    return "\(observation.identifier) (\(Int(observation.confidence * 100))%)"
                }
                .joined(separator: ", ")
            
            // Store the most confident detection for speech
            if let topResult = results.first {
                latestDetection = "\(topResult.identifier)"
            } else {
                latestDetection = nil
            }
            
            DispatchQueue.main.async {
                self.detectedObjectsLabel.text = detectedObjects.isEmpty ? "No objects detected" : "Detected: \(detectedObjects)"
            }
        } catch {
            print("Failed to perform object detection: \(error)")
            latestDetection = nil
        }
    }
    
    private func speakText(_ text: String) {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastSpokenTime >= minimumTimeBetweenSpeeches else { return }
        
        // Stop any ongoing speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        
        speechSynthesizer.speak(utterance)
        lastSpokenTime = currentTime
    }
}

extension DepthCameraViewController: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        // Convert depth data to grayscale image
        let depthMap = depthData.depthDataMap
        
        // Get average depth from the center region
        let centerDepth = getAverageCenterDepth(from: depthMap)
        
        // Process depth data for visualization and haptic feedback
        if let depth = centerDepth {
            // Print depth for debugging
            print("Center depth: \(depth) meters")
            
            DispatchQueue.main.async {
                // Trigger haptic feedback based on depth
                self.generateHapticFeedback(forDepth: depth)
            }
        }
        
        let ciImage = CIImage(cvPixelBuffer: depthMap)
        
        // Get the view size
        let viewSize = view.bounds.size
        
        // Calculate the scale to match the view size
        let scaleX = viewSize.width / ciImage.extent.width
        let scaleY = viewSize.height / ciImage.extent.height
        
        // Create transform sequence
        var transform = CGAffineTransform.identity
        
        // Scale to match view size
        transform = transform.scaledBy(x: scaleX, y: scaleY)
        
        // Apply the transform
        let transformedImage = ciImage.transformed(by: transform)
        
        // Apply false color filter - RED for CLOSE, BLUE for FAR
        let falseColor = CIFilter(name: "CIFalseColor")!
        falseColor.setValue(transformedImage, forKey: kCIInputImageKey)
        falseColor.setValue(CIColor(red: 1, green: 0, blue: 0), forKey: "inputColor0") // CLOSE objects - RED
        falseColor.setValue(CIColor(red: 0, green: 0, blue: 1), forKey: "inputColor1") // FAR objects - BLUE
        
        if let outputImage = falseColor.outputImage {
            // Add color adjustments for better visualization
            let colorControls = CIFilter(name: "CIColorControls")!
            colorControls.setValue(outputImage, forKey: kCIInputImageKey)
            colorControls.setValue(1.5, forKey: kCIInputSaturationKey) // Increase saturation
            colorControls.setValue(1.2, forKey: kCIInputContrastKey)   // Increase contrast
            
            if let finalImage = colorControls.outputImage {
                let context = CIContext()
                if let cgImage = context.createCGImage(finalImage, from: finalImage.extent) {
                    let uiImage = UIImage(cgImage: cgImage)
                    DispatchQueue.main.async {
                        self.depthView.image = uiImage
                    }
                }
            }
        }
    }
    
    private func getAverageCenterDepth(from depthMap: CVPixelBuffer) -> Float? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        // Define center region (middle 20% of the frame)
        let regionWidth = Int(Float(width) * 0.2)
        let regionHeight = Int(Float(height) * 0.2)
        let startX = (width - regionWidth) / 2
        let startY = (height - regionHeight) / 2
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        var totalDepth: Float = 0
        var samplesCount = 0
        
        // Access depth data as float array
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
        
        for y in startY..<(startY + regionHeight) {
            for x in startX..<(startX + regionWidth) {
                let offset = (y * bytesPerRow / MemoryLayout<Float>.stride) + x
                let depth = floatBuffer[offset]
                if depth > 0 && depth.isFinite {  // Filter out invalid readings
                    totalDepth += depth
                    samplesCount += 1
                }
            }
        }
        
        return samplesCount > 0 ? totalDepth / Float(samplesCount) : nil
    }
}

extension DepthCameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == videoDataOutput, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            detectObjects(in: pixelBuffer)
        }
    }
} 