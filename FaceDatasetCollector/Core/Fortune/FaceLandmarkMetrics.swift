//
//  FaceLandmarkMetrics.swift
//  FaceDatasetCollector
//

import CoreGraphics
import Vision

/// Vision 2D 랜드마크에서 뽑은 얼굴 비율.
///
/// ## 왜 ARKit 대신 Vision인가
/// ARKit `ARFaceGeometry`는 **일반화된 얼굴 모델을 표정 계수로 변형한 것**이라 개인 골격
/// 차이가 정규화되어 지워진다. 실제로 서로 다른 두 사람의 턱 폭 비율이 0.909와 0.908로
/// 같게 나왔다. 반면 Vision 랜드마크는 **찍힌 그림에서 직접 찾은 좌표**라 사람마다 다른
/// 값이 나올 여지가 있다.
///
/// ## 눈 사이 거리로 나누는 이유
/// 2D 좌표는 카메라와의 거리에 따라 통째로 커지고 작아진다. 얼굴 계측에서 관례적으로
/// 쓰는 기준자가 두 눈 중심 사이 거리(IOD)이므로 그것으로 나눠 크기를 지운다.
/// 남는 것은 "눈 사이 거리에 견줘 입이 얼마나 넓은가" 같은 순수한 비율이다.
///
/// - Important: 2D 투영이라 고개가 돌아가면 값이 달라진다. 촬영 화면이 정면 ±12°를
///   요구하고 있으므로 그 범위 안에서만 유효하다.
nonisolated struct FaceLandmarkMetrics: Sendable, Equatable {

    /// 입 너비 / 눈 사이 거리.
    let mouthWidth: Float

    /// 코 너비 / 눈 사이 거리.
    let noseWidth: Float

    /// 얼굴 윤곽 너비 / 눈 사이 거리.
    let faceWidth: Float

    /// 두 눈 중심에서 입 중심까지 / 눈 사이 거리.
    let eyeToMouth: Float

    /// 한쪽 눈 가로 길이 / 눈 사이 거리.
    let eyeWidth: Float

    init?(_ observation: FaceObservation, imageSize: CGSize) {
        guard
            let landmarks = observation.landmarks,
            let left = Self.center(of: landmarks.leftEye, in: imageSize),
            let right = Self.center(of: landmarks.rightEye, in: imageSize)
        else { return nil }

        let interocular = Self.distance(left, right)
        // 얼굴이 너무 작게 잡히면 좌표 잡음이 비율을 지배한다.
        guard interocular > 10 else { return nil }

        let eyeCenter = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)

        guard
            let lips = Self.bounds(of: landmarks.outerLips, in: imageSize),
            let nose = Self.bounds(of: landmarks.nose, in: imageSize),
            let contour = Self.bounds(of: landmarks.faceContour, in: imageSize),
            let leftEyeBox = Self.bounds(of: landmarks.leftEye, in: imageSize),
            let rightEyeBox = Self.bounds(of: landmarks.rightEye, in: imageSize)
        else { return nil }

        mouthWidth = Float(lips.width / interocular)
        noseWidth = Float(nose.width / interocular)
        faceWidth = Float(contour.width / interocular)
        eyeToMouth = Float(
            Self.distance(eyeCenter, CGPoint(x: lips.midX, y: lips.midY)) / interocular
        )
        eyeWidth = Float((leftEyeBox.width + rightEyeBox.width) / 2 / interocular)
    }

    // MARK: - 랜드마크 다루기

    private static func points(
        of region: FaceObservation.Landmarks2D.Region?,
        in size: CGSize
    ) -> [CGPoint]? {
        guard let region else { return nil }
        let points = region.pointsInImageCoordinates(size)
        return points.isEmpty ? nil : points
    }

    private static func center(
        of region: FaceObservation.Landmarks2D.Region?,
        in size: CGSize
    ) -> CGPoint? {
        guard let points = points(of: region, in: size) else { return nil }
        let sum = points.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
        }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private static func bounds(
        of region: FaceObservation.Landmarks2D.Region?,
        in size: CGSize
    ) -> CGRect? {
        guard let points = points(of: region, in: size) else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard
            let minX = xs.min(), let maxX = xs.max(),
            let minY = ys.min(), let maxY = ys.max()
        else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
}
