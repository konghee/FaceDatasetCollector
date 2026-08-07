//
//  EyeCropper.swift
//  FaceDatasetCollector
//

import CoreImage
import Vision

/// 눈/얼굴 크롭 규칙을 한곳에 모아 둔 타입.
///
/// 학습 데이터를 만들 때(`DatasetCapture`)와 추론할 때(`EyeReader`)의 크롭이 다르면
/// 모델이 학습한 구도와 실제 입력이 어긋나 정확도가 떨어진다.
/// 그래서 두 경로가 **같은 함수**를 쓰도록 여기로 빼 두었다. 규칙을 바꾸면
/// 기존 학습 데이터도 같이 다시 만들어야 한다.
enum EyeCropper {

    /// 눈 랜드마크를 감싸는 정사각형 크롭.
    ///
    /// 눈 바운딩 박스의 2배 크기로 잘라 눈꼬리·쌍꺼풀 주변 맥락까지 담는다.
    /// Vision과 CIImage 모두 y=0이 이미지 하단이라 좌표 변환이 필요 없다.
    static func cropEye(
        _ region: FaceObservation.Landmarks2D.Region?,
        from image: CIImage
    ) -> CIImage? {
        guard let region else { return nil }

        let points = region.pointsInImageCoordinates(image.extent.size)
        guard !points.isEmpty else { return nil }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }

        return squareCrop(
            center: CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2),
            side: max(maxX - minX, maxY - minY) * 2,
            in: image
        )
    }

    /// 얼굴형 학습용 크롭.
    ///
    /// Vision의 `boundingBox`는 턱과 이마를 바싹 자르는데, 얼굴형은 바로 그
    /// 턱선·이마 폭이 정보라서 그대로 쓰면 안 된다. 1.5배로 넓혀 여백을 준다.
    static func cropFace(_ observation: FaceObservation, from image: CIImage) -> CIImage? {
        let extent = image.extent
        let box = observation.boundingBox.toImageCoordinates(extent.size, origin: .lowerLeft)

        return squareCrop(
            center: CGPoint(x: box.midX, y: box.midY),
            side: max(box.width, box.height) * 1.5,
            in: image
        )
    }

    private static func squareCrop(center: CGPoint, side: CGFloat, in image: CIImage) -> CIImage? {
        let rect = CGRect(
            x: center.x - side / 2,
            y: center.y - side / 2,
            width: side,
            height: side
        ).intersection(image.extent)

        guard !rect.isNull, !rect.isEmpty else { return nil }
        return image.cropped(to: rect)
    }
}
