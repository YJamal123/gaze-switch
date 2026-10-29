import AVFoundation
import Foundation
import GazeSwitchCore

final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Failure: Error, CustomStringConvertible {
        case cannotUse(String)
        var description: String { switch self { case .cannotUse(let name): "Couldn't open the camera \"\(name)\"." } }
    }

    let device: AVCaptureDevice
    /// Called on the camera queue for every frame.
    var onFrame: ((CVPixelBuffer) -> Void)?
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "gaze-switch.camera")

    static var all: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices
    }

    /// The camera whose name contains `name`, or else the built-in one.
    static func pick(named name: String?) -> AVCaptureDevice? {
        let devices = all
        if let name, !name.isEmpty {
            return devices.first { $0.localizedName.localizedCaseInsensitiveContains(name) }
        }
        return devices.first { $0.deviceType == .builtInWideAngleCamera } ?? devices.first
    }

    static func requestAccess(_ done: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            done(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in DispatchQueue.main.async { done(granted) } }
        default:
            done(false)
        }
    }

    init(device: AVCaptureDevice) throws {
        self.device = device
        super.init()
        session.beginConfiguration()
        // Higher resolution gives the irises more pixels to work with.
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw Failure.cannotUse(device.localizedName) }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
    }

    func start() {
        queue.async { self.session.startRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}

/// Camera frames in, tracking results out on the main queue.
final class CameraPipeline {
    private let tracker: VisionTracker
    private var camera: Camera?

    init(tracksHands: Bool) {
        tracker = VisionTracker(tracksHands: tracksHands)
    }

    func start(cameraName: String?, onResult: @escaping (FrameResult) -> Void) {
        Camera.requestAccess { [self] granted in
            guard granted else {
                fail("""
                Camera access is off. Turn it on for \(permissionHolder) in
                System Settings → Privacy & Security → Camera, then start gaze-switch again.
                """)
            }
            guard let device = Camera.pick(named: cameraName) else {
                fail("No camera found\(cameraName.map { " matching \"\($0)\"" } ?? ""). Run 'gaze-switch cameras' to list them.")
            }
            do {
                let camera = try Camera(device: device)
                camera.onFrame = { [tracker] pixelBuffer in
                    let result = tracker.process(pixelBuffer, time: ProcessInfo.processInfo.systemUptime)
                    DispatchQueue.main.async { onResult(result) }
                }
                camera.start()
                self.camera = camera
                print("Camera: \(device.localizedName)")
            } catch {
                fail("\(error)")
            }
        }
    }
}
