import UIKit
import AVFoundation
import ARKit

class DepthCameraViewController: UIViewController {
    private var session: AVCaptureSession!
    private var depthDataOutput: AVCaptureDepthDataOutput!
    private var videoDataOutput: AVCaptureVideoDataOutput!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var depthView: UIImageView!
    private var statusLabel: UILabel!
    private var depthLegendView: UIView!
    private var depthLegendLabels: [UILabel] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupInitialUI()
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
        
        // Create status label
        statusLabel = UILabel(frame: CGRect(x: 20, y: 50, width: view.bounds.width - 40, height: 30))
        statusLabel.textColor = .white
        statusLabel.text = "Initializing..."
        statusLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        view.addSubview(statusLabel)
        
        // Create depth visualization view
        depthView = UIImageView(frame: view.bounds)
        depthView.contentMode = .scaleAspectFill
        depthView.alpha = 0.8
        view.addSubview(depthView)
        
        // Create depth legend
        setupDepthLegend()
    }
    
    private func setupDepthLegend() {
        // Create legend container
        depthLegendView = UIView(frame: CGRect(x: 20, y: view.bounds.height - 120, width: 40, height: 100))
        depthLegendView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        depthLegendView.layer.cornerRadius = 8
        view.addSubview(depthLegendView)
        
        // Create gradient view
        let gradientView = UIView(frame: CGRect(x: 5, y: 5, width: 30, height: 90))
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = gradientView.bounds
        gradientLayer.colors = [
            UIColor.red.cgColor,
            UIColor.yellow.cgColor,
            UIColor.green.cgColor,
            UIColor.blue.cgColor
        ]
        gradientLayer.locations = [0.0, 0.33, 0.66, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        gradientView.layer.addSublayer(gradientLayer)
        depthLegendView.addSubview(gradientView)
        
        // Create depth labels
        let distances = ["0.5m", "1.5m", "2.5m", "3.5m"]
        for (index, distance) in distances.enumerated() {
            let label = UILabel(frame: CGRect(x: 40, y: CGFloat(index) * 30, width: 60, height: 20))
            label.text = distance
            label.textColor = .white
            label.font = UIFont.systemFont(ofSize: 12)
            depthLegendLabels.append(label)
            depthLegendView.addSubview(label)
        }
    }
    
    private func setupCamera() {
        session = AVCaptureSession()
        session.sessionPreset = .photo
        
        // First try to get the LiDAR camera
        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else {
            print("LiDAR camera not available")
            statusLabel.text = "LiDAR camera not available"
            statusLabel.textColor = .red
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
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            
            // Set video orientation
            if let connection = videoDataOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            
            // Create and setup preview layer
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.frame = view.bounds
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.connection?.videoOrientation = .portrait
            view.layer.insertSublayer(previewLayer, at: 0)
            
            // Start the session
            session.startRunning()
            statusLabel.text = "Camera running"
            statusLabel.textColor = .green
            
        } catch {
            print("Error setting up camera: \(error)")
            statusLabel.text = "Error setting up camera"
            statusLabel.textColor = .red
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        depthView.frame = view.bounds
        statusLabel.frame = CGRect(x: 20, y: 50, width: view.bounds.width - 40, height: 30)
        
        // Update depth legend position
        depthLegendView.frame = CGRect(x: 20, y: view.bounds.height - 120, width: 40, height: 100)
        for (index, label) in depthLegendLabels.enumerated() {
            label.frame = CGRect(x: 45, y: CGFloat(index) * 30, width: 60, height: 20)
        }
        
        // Update preview layer orientation
        if let connection = previewLayer?.connection {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
    }
}

extension DepthCameraViewController: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        // Convert depth data to grayscale image
        let depthMap = depthData.depthDataMap
        let ciImage = CIImage(cvPixelBuffer: depthMap)
        
        // Get the view size
        let viewSize = view.bounds.size
        
        // Calculate the scale to match the view size
        let scaleX = viewSize.width / ciImage.extent.width
        let scaleY = viewSize.height / ciImage.extent.height
        
        // Create transform sequence
        var transform = CGAffineTransform.identity
        
        // Rotate 180 degrees counter-clockwise and flip vertically
        transform = transform.rotated(by: -.pi)
        transform = transform.rotated(by: -.pi / 2)
        transform = transform.scaledBy(x: 1, y: -1)
        
        // Scale to match view size
        transform = transform.scaledBy(x: scaleX, y: scaleY)
        
        // Apply the transform
        let transformedImage = ciImage.transformed(by: transform)
        
        // Create a color filter for depth visualization
        let colorFilter = CIFilter(name: "CIColorMap")!
        colorFilter.setValue(transformedImage, forKey: kCIInputImageKey)
        
        // Create a custom color gradient for depth visualization
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors: [CGFloat] = [
            1.0, 0.0, 0.0, 1.0, // Red
            1.0, 1.0, 0.0, 1.0, // Yellow
            0.0, 1.0, 0.0, 1.0, // Green
            0.0, 0.0, 1.0, 1.0  // Blue
        ]
        let locations: [CGFloat] = [0.0, 0.33, 0.66, 1.0]
        let gradient = CGGradient(colorSpace: colorSpace, colorComponents: colors, locations: locations, count: 4)!
        
        let context = CIContext()
        if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            DispatchQueue.main.async {
                self.depthView.image = uiImage
            }
        }
    }
}

extension DepthCameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Handle video frame if needed
    }
} 