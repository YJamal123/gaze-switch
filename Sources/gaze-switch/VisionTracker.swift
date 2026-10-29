import CoreGraphics
import Foundation
import GazeSwitchCore
import Vision

struct FrameResult {
    var time: Double
    var face: GazeFeatures?
    var hand: HandSample?
}

/// Runs Vision's face-landmark and hand-pose detection on camera frames.
final class VisionTracker {
    private let faceRequest = VNDetectFaceLandmarksRequest()
    private let handRequest = VNDetectHumanHandPoseRequest()
    private let tracksHands: Bool

    init(tracksHands: Bool) {
        self.tracksHands = tracksHands
        faceRequest.revision = VNDetectFaceLandmarksRequestRevision3
        handRequest.maximumHandCount = 1
    }

    /// Call from one queue at a time; the requests are reused between frames.
    func process(_ pixelBuffer: CVPixelBuffer, time: Double) -> FrameResult {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let requests: [VNRequest] = tracksHands ? [faceRequest, handRequest] : [faceRequest]
        do { try handler.perform(requests) } catch { return FrameResult(time: time) }

        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        // The largest face is the person sitting closest to the camera.
        let face = faceRequest.results?
            .max { $0.boundingBox.width < $1.boundingBox.width }
            .flatMap { Self.features(of: $0, imageSize: size) }
        let hand = tracksHands ? handRequest.results?.first.flatMap { Self.sample(of: $0, aspect: size.width / size.height) } : nil
        return FrameResult(time: time, face: face, hand: hand)
    }

    static func features(of face: VNFaceObservation, imageSize: CGSize) -> GazeFeatures? {
        guard let landmarks = face.landmarks,
              let eyeA = landmarks.leftEye?.pointsInImage(imageSize: imageSize), eyeA.count >= 4,
              let eyeB = landmarks.rightEye?.pointsInImage(imageSize: imageSize), eyeB.count >= 4,
              let nose = landmarks.nose?.pointsInImage(imageSize: imageSize), !nose.isEmpty
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
        var pupilOffsets: [CGPoint] = []
        var openness: [Double] = []
        for (contour, pupil) in [(eyeA, landmarks.leftPupil), (eyeB, landmarks.rightPupil)] {
            let points = contour.map(local)
            let xs = points.map(\.x), ys = points.map(\.y)
            let halfWidth = (xs.max()! - xs.min()!) / 2
            guard halfWidth > 0.5 else { continue }
            openness.append((ys.max()! - ys.min()!) / (2 * halfWidth))
            guard let p = pupil?.pointsInImage(imageSize: imageSize).first else { continue }
            let lp = local(p)
            pupilOffsets.append(CGPoint(x: (lp.x - (xs.max()! + xs.min()!) / 2) / halfWidth,
                                        y: (lp.y - (ys.max()! + ys.min()!) / 2) / halfWidth))
        }
        let eye = pupilOffsets.isEmpty ? .zero : centroid(pupilOffsets)
        let meanOpenness = openness.isEmpty ? 0 : openness.reduce(0, +) / Double(openness.count)

        return GazeFeatures(
            yaw: face.yaw?.doubleValue ?? 0,
            pitch: face.pitch?.doubleValue ?? 0,
            noseX: noseOffset.x / interocular,
            noseY: noseOffset.y / interocular,
            eyeX: eye.x,
            eyeY: eye.y,
            eyesOpen: !pupilOffsets.isEmpty && meanOpenness > 0.13
        )
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
