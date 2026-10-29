import CoreGraphics
import Foundation
import GazeSwitchCore
import Vision

struct FrameResult {
    var time: Double
    var face: GazeFeatures?
    var hand: HandSample?
}

/// Runs Vision's face and hand-pose detection on camera frames, and finds the irises itself.
final class VisionTracker {
    // The rectangles request reports head yaw and pitch; the landmarks request doesn't.
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let landmarksRequest = VNDetectFaceLandmarksRequest()
    private let handRequest = VNDetectHumanHandPoseRequest()
    private let tracksHands: Bool
    private var blinks = BlinkDetector()

    init(tracksHands: Bool) {
        self.tracksHands = tracksHands
        faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
        landmarksRequest.revision = VNDetectFaceLandmarksRequestRevision3
        handRequest.maximumHandCount = 1
    }

    /// Call from one queue at a time; the requests are reused between frames.
    func process(_ pixelBuffer: CVPixelBuffer, time: Double) -> FrameResult {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        var result = FrameResult(time: time)
        do {
            try handler.perform(tracksHands ? [faceRequest, handRequest] : [faceRequest])
            if tracksHands { result.hand = handRequest.results?.first.flatMap { Self.sample(of: $0, aspect: size.width / size.height) } }
            // The largest face is the person sitting closest to the camera.
            guard let face = faceRequest.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }) else { return result }
            landmarksRequest.inputFaceObservations = [face]
            try handler.perform([landmarksRequest])
            guard let landmarks = landmarksRequest.results?.first?.landmarks else { return result }
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            result.face = features(pose: face, landmarks: landmarks, image: Self.brightness(of: pixelBuffer), size: size)
        } catch {}
        return result
    }

    private func features(pose: VNFaceObservation, landmarks: VNFaceLandmarks2D, image: GrayImage?, size: CGSize) -> GazeFeatures? {
        guard let eyeA = landmarks.leftEye?.pointsInImage(imageSize: size), eyeA.count >= 4,
              let eyeB = landmarks.rightEye?.pointsInImage(imageSize: size), eyeB.count >= 4,
              let nose = landmarks.nose?.pointsInImage(imageSize: size), !nose.isEmpty
        else { return nil }

        let centerA = centroid(eyeA), centerB = centroid(eyeB)
        let interocular = hypot(centerB.x - centerA.x, centerB.y - centerA.y)
        guard interocular > 1 else { return nil }
        let mid = CGPoint(x: (centerA.x + centerB.x) / 2, y: (centerA.y + centerB.y) / 2)
        // Undo head roll so offsets are measured along the face's own axes.
        let (first, second) = centerA.x < centerB.x ? (centerA, centerB) : (centerB, centerA)
        let roll = atan2(second.y - first.y, second.x - first.x)
        func local(_ p: CGPoint) -> CGPoint {
            let dx = p.x - mid.x, dy = p.y - mid.y
            return CGPoint(x: dx * cos(-roll) - dy * sin(-roll), y: dx * sin(-roll) + dy * cos(-roll))
        }

        let noseOffset = local(centroid(nose))
        var jawX = 0.0
        if let jaw = landmarks.faceContour?.pointsInImage(imageSize: size).map(local), jaw.count >= 3 {
            let left = jaw.map(\.x).min()!, right = jaw.map(\.x).max()!
            if right - left > 1 { jawX = (noseOffset.x - (left + right) / 2) / (right - left) }
        }

        var irisOffsets: [CGPoint] = []
        var openings: [Double] = []
        for (contour, pupil) in [(eyeA, landmarks.leftPupil), (eyeB, landmarks.rightPupil)] {
            let points = contour.map(local)
            let xs = points.map(\.x), ys = points.map(\.y)
            let halfWidth = (xs.max()! - xs.min()!) / 2
            guard halfWidth > 0.5 else { continue }
            openings.append((ys.max()! - ys.min()!) / (2 * halfWidth))
            // Measure from the corners rather than the eye's bounding box, which shifts as the lids move.
            let inner = points.min { $0.x < $1.x }!, outer = points.max { $0.x < $1.x }!
            let cornerMid = CGPoint(x: (inner.x + outer.x) / 2, y: (inner.y + outer.y) / 2)
            // Vision's points have y going up; the image's rows go down.
            let iris = image.flatMap { img in
                IrisLocator.locate(in: img, contour: contour.map { CGPoint(x: $0.x, y: size.height - $0.y) })
                    .map { CGPoint(x: $0.x, y: size.height - $0.y) }
            } ?? pupil?.pointsInImage(imageSize: size).first
            guard let iris else { continue }
            let p = local(iris)
            irisOffsets.append(CGPoint(x: (p.x - cornerMid.x) / halfWidth, y: (p.y - cornerMid.y) / halfWidth))
        }
        let eye = irisOffsets.isEmpty ? .zero : centroid(irisOffsets)
        let opening = openings.isEmpty ? 0 : openings.reduce(0, +) / Double(openings.count)

        return GazeFeatures(
            yaw: (pose.yaw ?? 0).doubleValue,
            pitch: (pose.pitch ?? 0).doubleValue,
            noseX: noseOffset.x / interocular,
            noseY: noseOffset.y / interocular,
            jawX: jawX,
            eyeX: eye.x,
            eyeY: eye.y,
            eyelids: opening,
            faceX: mid.x / size.width,
            faceY: mid.y / size.height,
            eyesOpen: !irisOffsets.isEmpty && blinks.eyesOpen(opening: opening)
        )
    }

    /// The brightness plane of a camera frame. The buffer must be locked.
    private static func brightness(of pixelBuffer: CVPixelBuffer) -> GrayImage? {
        guard CVPixelBufferIsPlanar(pixelBuffer), let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        return GrayImage(width: CVPixelBufferGetWidthOfPlane(pixelBuffer, 0),
                         height: CVPixelBufferGetHeightOfPlane(pixelBuffer, 0),
                         rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0),
                         pixels: base.assumingMemoryBound(to: UInt8.self))
    }

    /// Converts joints to frame-height units so distances aren't stretched by the frame's aspect ratio.
    static func sample(of hand: VNHumanHandPoseObservation, aspect: CGFloat) -> HandSample? {
        guard let points = try? hand.recognizedPoints(.all) else { return nil }
        var joints: [HandJoint: CGPoint] = [:]
        for (name, joint) in jointNames {
            if let p = points[name], p.confidence > 0.3 {
                joints[joint] = CGPoint(x: p.location.x * aspect, y: p.location.y)
            }
        }
        return joints.isEmpty ? nil : HandSample(joints: joints)
    }

    private static let jointNames: [(VNHumanHandPoseObservation.JointName, HandJoint)] = [
        (.wrist, .wrist),
        (.thumbCMC, .thumbCMC), (.thumbMP, .thumbMP), (.thumbIP, .thumbIP), (.thumbTip, .thumbTip),
        (.indexMCP, .indexMCP), (.indexPIP, .indexPIP), (.indexDIP, .indexDIP), (.indexTip, .indexTip),
        (.middleMCP, .middleMCP), (.middlePIP, .middlePIP), (.middleDIP, .middleDIP), (.middleTip, .middleTip),
        (.ringMCP, .ringMCP), (.ringPIP, .ringPIP), (.ringDIP, .ringDIP), (.ringTip, .ringTip),
        (.littleMCP, .littleMCP), (.littlePIP, .littlePIP), (.littleDIP, .littleDIP), (.littleTip, .littleTip),
    ]
}

private func centroid(_ points: [CGPoint]) -> CGPoint {
    let n = CGFloat(points.count)
    return CGPoint(x: points.map(\.x).reduce(0, +) / n, y: points.map(\.y).reduce(0, +) / n)
}
