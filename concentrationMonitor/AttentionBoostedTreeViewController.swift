//
//  AttentionBoostedTreeViewController.swift
//  concentrationMonitor
//
//  Created by Tommy on 2021/11/11.
//

import UIKit
import AVFoundation
import Vision

class AttentionBoostedTreeViewController: UIViewController {
    @IBOutlet var inputButton: UIButton!
    @IBOutlet var previewImageView: UIImageView!
    
    var avCaptureSession = AVCaptureSession()
    var eye = Eye()
    var concentrationResults: [Int] = []
    var detailedResults: [Double] = []
    var resultsForCSV: [String] = []
    
    var concentrationTime = 0.0
    var lastConcentrationTime: Date?
    var startedTime: Date?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        setupCamera()
        buildInputButton()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        avCaptureSession.stopRunning()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "done" {
            if self.lastConcentrationTime != nil {
                self.concentrationTime += Date().timeIntervalSince(self.lastConcentrationTime!)
                self.lastConcentrationTime = nil
            }
            let destination = segue.destination as! ResultsViewController
            destination.concentrationResults = self.concentrationResults
            destination.detailedResults = self.detailedResults
            destination.resultsForCSV = self.resultsForCSV
            destination.concentrationTime = self.concentrationTime
            destination.totalTime = Date().timeIntervalSince(self.startedTime!)
        }
    }
    
    @IBAction func done() {
        avCaptureSession.stopRunning()
        self.performSegue(withIdentifier: "done", sender: self)
    }
    
    func buildInputButton() {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        let devices = deviceDiscoverySession.devices
        
        var actions: [UIAction] = []
        
        for device in devices {
            let action = UIAction(title: device.localizedName, handler: { _ in
                self.avCaptureSession.stopRunning()
                self.avCaptureSession = AVCaptureSession()
                self.setupCamera(device)
            })
            actions.append(action)
        }
        
        self.inputButton.menu = UIMenu(title: "Camera Input", image: UIImage(systemName: "camera.fill"), identifier: nil, options: .displayInline, children: actions)
        self.inputButton.showsMenuAsPrimaryAction = true
    }
    
    func rad2deg(_ number: Double) -> Double {
        return number * 180 / .pi
    }
    
    func setupCamera(_ selectedDevice: AVCaptureDevice? = nil) {
        avCaptureSession.sessionPreset = .photo
        
        var device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        
        if selectedDevice != nil {
            device = selectedDevice
        }
        
        let input = try! AVCaptureDeviceInput(device: device!)
        avCaptureSession.addInput(input)
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: .global())
        
        avCaptureSession.addOutput(videoDataOutput)
        avCaptureSession.startRunning()
        startedTime = Date()
    }
    
    func rectColor() -> CGColor {
        guard let rightX = eye.rightY, let rightY = eye.rightY, let leftX = eye.leftX, let leftY = eye.leftY, let roll = eye.roll, let yaw = eye.yaw else {
            return UIColor.white.cgColor
        }
        
        // MARK: ここで集中度推測
        let attentionAnalyzer = attention_boostedTree()
        
        guard let concentration = try? attentionAnalyzer.prediction(rightEyeX: rightX, rightEyeY: rightY, leftEyeX: leftX, leftEyeY: leftY, roll: roll, yaw: yaw) else {
            return UIColor.white.cgColor
        }
        
        print(concentration.concentration, concentration.concentrationProbability)
        concentrationResults.append(Int(concentration.concentration))
        detailedResults.append(concentration.concentrationProbability[1] ?? 0.0)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMd-Hms"
        
        resultsForCSV.append("\(dateFormatter.string(from: Date())),\(concentration.concentration),\(concentration.concentrationProbability[1] ?? 0.0)")
        
        if concentration.concentration == 1 {
            if self.lastConcentrationTime == nil {
                self.lastConcentrationTime = Date()
            }
            return UIColor.green.cgColor
        } else if (concentration.concentrationProbability[1] ?? 0.0) > 0.4 {
            if self.lastConcentrationTime == nil {
                self.lastConcentrationTime = Date()
            }
            return UIColor.green.cgColor
        }
        
        if self.lastConcentrationTime != nil {
            self.concentrationTime += Date().timeIntervalSince(self.lastConcentrationTime!)
            self.lastConcentrationTime = nil
        }
        
        return UIColor.red.cgColor
    }
    
    func drawRect(_ rect: CGRect, context: CGContext) {
        context.setLineWidth(4.0)
        context.setStrokeColor(rectColor())
        context.stroke(rect)
    }
    
    func getFaceObservations(pixelBuffer: CVPixelBuffer, completion: @escaping (([VNFaceObservation])->())) {
        let landmarkRequest = VNDetectFaceLandmarksRequest { [self] (request, error) in
            self.eye.rightX = nil
            self.eye.rightY = nil
            self.eye.leftX = nil
            self.eye.leftY = nil
            
            guard let faces = request.results as? [VNFaceObservation] else {
                return
            }
            
            if let landmarks = faces.first?.landmarks {
                if let rightEye = relativeCoordinate(eye: landmarks.rightEye?.normalizedPoints ?? [], pupil: landmarks.rightPupil?.normalizedPoints.first) {
                    
                    if let x = rightEye.first, let y = rightEye.last {
                        self.eye.rightX = x
                        self.eye.rightY = y
                    }
                }
                if let leftEye = relativeCoordinate(eye: landmarks.leftEye?.normalizedPoints ?? [], pupil: landmarks.leftEye?.normalizedPoints.first) {
                    
                    if let x = leftEye.first, let y = leftEye.last {
                        self.eye.leftX = x
                        self.eye.leftY = y
                    }
                }
            }
        }
        
        if #available(iOS 12.0, *) {
            landmarkRequest.revision = 2
        }
        
        let rectangleRequest = VNDetectFaceRectanglesRequest { [self] (request, error) in
            self.eye.roll = nil
            self.eye.yaw = nil
            
            guard let faces = request.results as? [VNFaceObservation] else {
                completion([])
                return
            }
            
            if let face = faces.first {
                if let roll = face.roll?.doubleValue, let yaw = face.yaw?.doubleValue {
                    self.eye.roll = rad2deg(roll)
                    self.eye.yaw = rad2deg(yaw)
                }
            }
            completion(faces)
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([landmarkRequest, rectangleRequest])
    }
    
    func getUnfoldRect(normalizedRect: CGRect, targetSize: CGSize) -> CGRect {
        return CGRect(
            x: normalizedRect.minX * targetSize.width,
            y: normalizedRect.minY * targetSize.height,
            width: normalizedRect.width * targetSize.width,
            height: normalizedRect.height * targetSize.height
        )
    }
    
    func getFaceRectsImage(sampleBuffer :CMSampleBuffer, faceObservations: [VNFaceObservation]) -> UIImage? {

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))

        guard let pixelBufferBaseAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0) else {
            CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
            return nil
        }

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let bitmapInfo = CGBitmapInfo(rawValue:
                                        (CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        )

        guard let newContext = CGContext(
            data: pixelBufferBaseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(imageBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else
        {
            CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
            return nil
        }

        let imageSize = CGSize(width: width, height: height)
        let faceRects = faceObservations.compactMap {
            getUnfoldRect(normalizedRect: $0.boundingBox, targetSize: imageSize)
        }
        faceRects.forEach{ self.drawRect($0, context: newContext) }

        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))

        guard let imageRef = newContext.makeImage() else {
            return nil
        }
        let image = UIImage(cgImage: imageRef, scale: 1.0, orientation: getImageOrientation())

        return image
    }
    
    func relativeCoordinate(eye: [CGPoint], pupil: CGPoint?) -> [Double]? {
        guard let pupil = pupil else { return nil }
        
        if eye.count == 8 {
            let centerX = (eye[0].x + eye[4].x) / 2
            let multiplierX = 1 / (eye[4].x - centerX)
            let rX = (pupil.x - centerX) * multiplierX
            
            let centerY = (eye[1].y + eye[5].y) / 2
            let multiplierY = 1 / (eye[5].y - centerY)
            let rY = -((centerY - pupil.y) * multiplierY)
            
            return [rX, rY]
        } else {
            return nil
        }
    }
}

extension AttentionBoostedTreeViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        getFaceObservations(pixelBuffer: pixelBuffer) { [weak self] faceObservations in
            guard let self = self else { return }
            let image = self.getFaceRectsImage(sampleBuffer: sampleBuffer, faceObservations: faceObservations)
            DispatchQueue.main.async { [weak self] in
                self?.previewImageView.image = image
            }
        }
    }
    
    func getImageOrientation() -> UIImage.Orientation {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return .down
        case .mac:
            return .up
        default:
            return .right
        }
    }
}
