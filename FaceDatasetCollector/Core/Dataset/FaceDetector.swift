//
//  FaceDetector.swift
//  FaceDatasetCollector
//

import CoreGraphics
import CoreImage
import Vision

/// 촬영한 이미지에서 얼굴 랜드마크를 찾는다.
///
/// 크롭 기준을 ARKit 3D 정점이 아니라 Vision 2D 랜드마크로 잡는 이유는,
/// 본 앱의 추론 경로(`EyeReader`)가 Vision 랜드마크로 크롭하기 때문이다.
/// 학습 데이터도 같은 방식으로 잘라야 구도가 어긋나지 않는다.
enum FaceDetector {

    /// 이미지에서 첫 번째 얼굴을 찾는다. 없으면 nil.
    ///
    /// - Parameter image: EXIF 방향이 픽셀에 이미 반영된 이미지.
    ///   (`DatasetCapture`가 세로로 돌려 놓은 뒤 넘긴다.)
    static func detect(in image: CGImage) async throws -> FaceObservation? {
        let request = DetectFaceLandmarksRequest()
        let faces = try await request.perform(on: CIImage(cgImage: image), orientation: .up)
        return faces.first
    }
}
