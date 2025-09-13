//
//  CameraPreview.swift
//
//
//  Created by narongrit kanhanoi on 7/10/2562 BE.
//  Copyright © 2562 PAM. All rights reserved.
//

import UIKit
import AVFoundation

public class CameraPreview: UIView {

    var cameraInput: AVCaptureDeviceInput?
    var cameraPosition = AVCaptureDevice.Position.back
    var previewLayer: AVCaptureVideoPreviewLayer?
    var session: AVCaptureSession?
    var supportBarcode: [AVMetadataObject.ObjectType]?

    var shapeLayer: CAShapeLayer?

    private var label: UILabel?

    var scanInterval: Double = 3.0
    var lastTime = Date(timeIntervalSince1970: 0)

    var onDraw: CBScanner.OnDraw?
    var onFound: CBScanner.OnFound?
    var mockBarCode: BarcodeData?
    var selectedCamera: AVCaptureDevice?

    var torchLightIsOn: Bool = false

    var removeFrameTimer: Timer?
    
    var lastScannedBarcode: BarcodeData?
    
    private let sessionQueue = DispatchQueue(label: "camera.session.queue", qos: .userInitiated)

    init() {
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupScanner() {
        #if targetEnvironment(simulator)
            createSimulatorView()
        #else
            checkCameraAuthorizationStatus()
        #endif
    }

    func setSupportedBarcode(supportBarcode: [AVMetadataObject.ObjectType]) {
        guard self.supportBarcode != supportBarcode else { return }
        self.supportBarcode = supportBarcode

        sessionQueue.async {
            guard let session = self.session else { return }

            session.beginConfiguration()

            // Remove existing metadata outputs to avoid duplicates
            session.outputs.forEach { output in
                if output is AVCaptureMetadataOutput {
                    session.removeOutput(output)
                }
            }

            let metadataOutput = AVCaptureMetadataOutput()
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.metadataObjectTypes = supportBarcode
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            }

            session.commitConfiguration()
        }
    }

    func setCamera(position: AVCaptureDevice.Position) {
        guard cameraPosition != position else { return }
        cameraPosition = position

        sessionQueue.async {
            guard let session = self.session else { return }

            session.beginConfiguration()
            
            // Remove current input
            if let input = self.cameraInput {
                session.removeInput(input)
                self.cameraInput = nil
            }

            // Add new camera input
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera], 
                mediaType: .video, 
                position: self.cameraPosition
            )
            
            if let camera = discovery.devices.first,
               let input = try? AVCaptureDeviceInput(device: camera),
               session.canAddInput(input) {
                session.addInput(input)
                self.cameraInput = input
                self.selectedCamera = camera
            }

            session.commitConfiguration()
        }
    }

    func setTorchLight(isOn: Bool) {
        guard torchLightIsOn != isOn else { return }
        
        torchLightIsOn = isOn
        guard let camera = selectedCamera, camera.hasTorch else { return }
        
        try? camera.lockForConfiguration()
        camera.torchMode = isOn ? .on : .off
        camera.unlockForConfiguration()
    }

    private func checkCameraAuthorizationStatus() {
        let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuthorizationStatus == .authorized {
            setupCamera()
        } else {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.setupCamera()
                    }
                }
            }
        }
    }

    func setupCamera() {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: cameraPosition)

        if let selectedCamera = deviceDiscoverySession.devices.first {
            if let input = try? AVCaptureDeviceInput(device: selectedCamera) {

                let session = AVCaptureSession()
                session.sessionPreset = .hd1280x720

                if session.canAddInput(input) {
                    session.addInput(input)
                    cameraInput = input
                }

                let metadataOutput = AVCaptureMetadataOutput()

                if session.canAddOutput(metadataOutput) {
                    session.addOutput(metadataOutput)

                    metadataOutput.metadataObjectTypes = supportBarcode
                    metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                }

                previewLayer?.removeFromSuperlayer()
                self.session = session
                self.selectedCamera = selectedCamera
                self.backgroundColor = UIColor.gray
                
                sessionQueue.async {
                    session.startRunning()
                    DispatchQueue.main.async {
                        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                        previewLayer.videoGravity = .resizeAspectFill
                        self.layer.addSublayer(previewLayer)
                        
                        self.previewLayer = previewLayer
                        self.updateCameraView()
                    }
                }
                
            }
        }
    }


    func getVideoOrientation() -> AVCaptureVideoOrientation {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene, windowScene.activationState == .foregroundActive
            else { return .portrait }

        let interfaceOrientation = windowScene.interfaceOrientation

        switch interfaceOrientation {
        case .unknown:
            return .portrait
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        @unknown default:
            return .portrait
        }
    }

    func updateCameraView() {
        previewLayer?.connection?.videoOrientation = getVideoOrientation()
    }

    func createSimulatorView() {
        self.backgroundColor = UIColor.black
        label = UILabel(frame: self.bounds)
        label?.numberOfLines = 4
        label?.text = "CarBode Scanner View\nSimulator mode\n\nClick here to simulate scan"
        label?.textColor = UIColor.white
        label?.textAlignment = .center
        if let label = label {
            addSubview(label)
        }
        let gesture = UITapGestureRecognizer(target: self, action: #selector(onClick))
        self.addGestureRecognizer(gesture)
    }

    @objc func onClick() {
        foundBarcode(mockBarCode ?? BarcodeData(value: "Mock Value", type: .qr))
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        #if targetEnvironment(simulator)
            label?.frame = self.bounds
        #else
            previewLayer?.frame = self.bounds
        #endif
    }
    
    func cleanup() {
        sessionQueue.async {
            self.session?.stopRunning()
        }
        
        DispatchQueue.main.async {
            self.removeFrameTimer?.invalidate()
            self.removeFrameTimer = nil
            self.previewLayer?.removeFromSuperlayer()
            self.previewLayer = nil
            self.shapeLayer?.removeFromSuperlayer()
            self.shapeLayer = nil
        }
        
        // Clear references immediately
        session = nil
        selectedCamera = nil
        cameraInput = nil
    }
    
    func startSession() {
        sessionQueue.async {
            self.session?.startRunning()
        }
    }
    
    func stopSession() {
        sessionQueue.async {
            self.session?.stopRunning()
        }
    }
}

extension CameraPreview: AVCaptureMetadataOutputObjectsDelegate {

    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {

        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }

            #if !targetEnvironment(simulator)
                var corners: [CGPoint] = []
                readableObject.corners.forEach {
                    let point = convertToViewCoordinate(point: $0)
                    corners.append(point)
                }
                let frame = BarcodeFrame(corners: corners, cameraPreviewView: self)
                onDraw?(frame)
            #endif

            if let stringValue = readableObject.stringValue {
                let barcode = BarcodeData(value: stringValue, type: readableObject.type)
                foundBarcode(barcode)
            }
        }
    }

    func foundBarcode(_ barcode: BarcodeData) {
        let now = Date()
        
        //When scan on difference barcode scanner will ignore the delay time
        if lastScannedBarcode?.value != barcode.value {
            lastTime = now
            onFound?(barcode)
            lastScannedBarcode = barcode
        }else if now.timeIntervalSince(lastTime) >= scanInterval {
            lastTime = now
            onFound?(barcode)
            lastScannedBarcode = barcode
        }
    }
}


extension CameraPreview {
    func convertToViewCoordinate(point: CGPoint) -> CGPoint {
        let orientation = getVideoOrientation()

        var pointX: CGFloat = 0
        var pointY: CGFloat = 0

        switch orientation {
        case .portrait:
            let scale = self.bounds.width / 720
            let previewWidth = 720 * scale
            let previewHeight = 1280 * scale

            let croppedFrameY = previewHeight / 2 - self.bounds.height / 2

            let x = 1.0 - point.y
            let y = point.x

            pointX = x * previewWidth
            pointY = (y * previewHeight) - croppedFrameY
        case .landscapeRight:
            let scale = self.bounds.width / 1280
            let previewWidth = 1280 * scale
            let previewHeight = 720 * scale

            let croppedFrameY = previewHeight / 2 - self.bounds.height / 2

            pointX = point.x * previewWidth
            pointY = (point.y * previewHeight) - croppedFrameY
        case .landscapeLeft:
            let scale = self.bounds.width / 1280
            let previewWidth = 1280 * scale
            let previewHeight = 720 * scale

            let croppedFrameY = previewHeight / 2 - self.bounds.height / 2

            let x = 1.0 - point.x
            let y = 1.0 - point.y

            pointX = x * previewWidth
            pointY = (y * previewHeight) - croppedFrameY
        case .portraitUpsideDown:
            let scale = self.bounds.width / 720
            let previewWidth = 720 * scale
            let previewHeight = 1280 * scale

            let croppedFrameY = previewHeight / 2 - self.bounds.height / 2

            let x = 1.0 - point.y
            let y = point.x

            pointX = x * previewWidth
            pointY = (y * previewHeight) - croppedFrameY
        @unknown default:
            pointX = 0
            pointY = 0
        }

        return CGPoint(x: pointX, y: pointY)
    }

    @objc func removeBarcodeFrame() {
        shapeLayer?.removeFromSuperlayer()
    }

    func drawFrame(corners: [CGPoint], lineWidth: CGFloat = 1, lineColor: UIColor = UIColor.red, fillColor: UIColor = UIColor.clear) -> Void {

        removeFrameTimer?.invalidate()
        removeFrameTimer = Timer.scheduledTimer(timeInterval: 0.3, target: self, selector: #selector(removeBarcodeFrame), userInfo: nil, repeats: false)

        if shapeLayer != nil {
            shapeLayer?.removeFromSuperlayer()
        }
        let bezierPath = UIBezierPath()
        var first = true

        corners.forEach {
            if first {
                first = false
                bezierPath.move(to: $0)
            } else {
                bezierPath.addLine(to: $0)
            }
        }

        if corners.count > 0 {
            let pnt = corners[0]
            bezierPath.addLine(to: pnt)
        }

        shapeLayer?.frame = self.bounds
        shapeLayer = CAShapeLayer()
        shapeLayer?.path = bezierPath.cgPath
        shapeLayer?.strokeColor = lineColor.cgColor
        shapeLayer?.fillColor = fillColor.cgColor
        shapeLayer?.lineWidth = lineWidth

        if let shapeLayer = shapeLayer {
            self.layer.addSublayer(shapeLayer)
        }
    }
}

