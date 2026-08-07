//
//  DatasetCapture.swift
//  FaceDatasetCollector
//

import ARKit
import CoreImage
import Foundation
import ImageIO

/// 촬영 순간의 `ARFrame`에서 학습용 표본을 뽑아내는 파이프라인.
///
/// ## 왜 두 단계로 나눴나
/// `ARFrame`은 붙들고 있으면 픽셀버퍼 풀이 고갈돼 세션이 멈춘다.
/// 그래서 `grab(...)`이 메인 스레드에서 픽셀버퍼를 `CGImage`로 복사해 프레임을 즉시 놓아주고,
/// 무거운 Vision 검출·JPEG 인코딩은 `makeSample(...)`에서 백그라운드로 처리한다.
enum DatasetCapture {

    /// JPEG 품질. 학습 데이터라 압축 아티팩트를 최소화한다.
    static let jpegQuality: CGFloat = 0.95

    private static let context = CIContext()

    /// 프레임에서 복사해 온 원본 한 장. ARKit 객체를 더는 참조하지 않는다.
    ///
    /// `CGImage`는 Sendable로 표시돼 있지 않지만 생성 후 불변이라 백그라운드로 넘겨도 안전하다.
    struct RawFrame: @unchecked Sendable {
        let image: CGImage
        let snapshot: FaceAnchorSnapshot
    }

    // MARK: - 1단계: 프레임 복사

    /// 세션의 현재 프레임을 세로 방향 `CGImage`로 복사한다.
    ///
    /// - Parameter orientation: 센서 원본(가로)을 세로로 세우는 방식.
    ///   기본값(`.automatic`)은 프레임마다 ARKit의 표시 변환에서 역산하므로 미리보기와 같은 그림이 된다.
    @MainActor
    static func grab(
        from manager: ARFaceCaptureManager,
        orientation: CaptureOrientation
    ) -> RawFrame? {
        guard
            let frame = manager.session.currentFrame,
            let anchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first,
            anchor.isTracked
        else { return nil }

        let snapshot = FaceAnchorSnapshot(anchor: anchor, camera: frame.camera)

        // createCGImage 시점에 픽셀이 복사되므로, 이후 프레임이 재사용돼도 안전하다.
        let ciImage = CIImage(cvPixelBuffer: frame.capturedImage)
            .oriented(orientation.resolved(for: frame))
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        return RawFrame(image: cgImage, snapshot: snapshot)
    }

    // MARK: - 2단계: 크롭 + 인코딩

    /// 원본에서 얼굴/눈을 잘라 라벨링 대기 표본을 만든다.
    ///
    /// Vision이 얼굴을 못 찾아도 표본은 만든다. 전체 프레임과 기하값은 이미 유효하고,
    /// 크롭은 나중에 원본에서 다시 뜰 수 있기 때문이다. (`hasAllCrops`로 화면에서 경고한다.)
    static func makeSample(from raw: RawFrame) async -> PendingSample {
        let ciImage = CIImage(cgImage: raw.image)
        let observation = try? await FaceDetector.detect(in: raw.image)

        var faceCrop: Data?
        var leftEye: Data?
        var rightEye: Data?

        if let observation {
            faceCrop = EyeCropper.cropFace(observation, from: ciImage).flatMap(jpeg)
            leftEye = EyeCropper.cropEye(observation.landmarks?.leftEye, from: ciImage).flatMap(jpeg)
            rightEye = EyeCropper.cropEye(observation.landmarks?.rightEye, from: ciImage).flatMap(jpeg)
        }

        return PendingSample(
            id: UUID(),
            capturedAt: Date(),
            fullFrame: jpeg(ciImage) ?? Data(),
            faceCrop: faceCrop,
            leftEyeCrop: leftEye,
            rightEyeCrop: rightEye,
            vertices: raw.snapshot.vertices,
            geometry: SampleGeometry(snapshot: raw.snapshot)
        )
    }

    private static func jpeg(_ image: CIImage) -> Data? {
        // cropped(to:)를 거친 CIImage는 origin이 (0,0)이 아니라서, 그대로 인코딩하면
        // 좌표계에 따라 빈 영역이 섞인다. 원점으로 옮긴 뒤 인코딩한다.
        let normalized = image.transformed(
            by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y)
        )

        return context.jpegRepresentation(
            of: normalized,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [.init(rawValue: kCGImageDestinationLossyCompressionQuality as String): jpegQuality]
        )
    }
}

// MARK: - 촬영 품질 판정

/// 촬영해도 되는 상태인지 판단한다.
///
/// 고개가 돌아갔거나 눈을 감은 사진이 섞이면 모델이 "각도"를 학습해 버린다.
/// 막지는 않고(수집 속도가 더 중요할 때가 있다) 경고만 띄운다.
struct CaptureQuality {

    /// 정면으로 인정하는 최대 이탈각(도).
    static let maxDeviation: Float = 12

    /// 눈을 떴다고 인정하는 최소값.
    static let minOpenness: Float = 0.6

    let isFrontal: Bool
    let isEyesOpen: Bool

    var isGood: Bool { isFrontal && isEyesOpen }

    var warning: String? {
        if !isFrontal { return "고개를 정면으로 맞춰 주세요" }
        if !isEyesOpen { return "눈을 크게 떠 주세요" }
        return nil
    }

    init(snapshot: FaceAnchorSnapshot) {
        isFrontal = snapshot.headPose.maxDeviation <= Self.maxDeviation
        isEyesOpen = min(snapshot.leftEyeOpenness, snapshot.rightEyeOpenness) >= Self.minOpenness
    }
}
