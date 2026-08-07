//
//  FaceAnchorSnapshot.swift
//  FaceDatasetCollector
//

import ARKit
import simd

/// 한 프레임의 `ARFaceAnchor`에서 필요한 값만 복사해 둔 스냅샷.
///
/// `ARFaceAnchor`와 `ARFrame`은 모두 ARKit이 내부에서 재사용/갱신하는 참조 타입이라
/// 촬영 시점의 상태를 남기려면 반드시 값으로 복사해야 한다.
/// (특히 `ARFrame`을 오래 붙들면 픽셀버퍼 풀이 고갈돼 세션이 멈춘다.)
///
/// 정점 좌표는 **얼굴 앵커 로컬 좌표계**라 고개 방향이 이미 제거돼 있고, 단위는 미터다.
/// 2D 랜드마크와 달리 촬영 각도에 따라 값이 흔들리지 않는 이유가 이것이다.
struct FaceAnchorSnapshot: Sendable {

    /// 얼굴 메시 정점 (얼굴 로컬 좌표계, 미터). ARKit 기준 1220개.
    let vertices: [SIMD3<Float>]

    /// 얼굴 앵커 기준 좌/우 안구 transform. **사용자 기준** 좌/우다.
    /// 안구 중심(눈꺼풀 표면이 아님)에 위치하므로 두 좌표 사이 거리는 동공간거리에 가깝다.
    let leftEyeTransform: simd_float4x4
    let rightEyeTransform: simd_float4x4

    /// 카메라 좌표계에서 본 얼굴 자세. yaw/pitch/roll 판정에 사용한다.
    ///
    /// `anchor.transform`은 월드 기준인데, 얼굴 추적 세션의 월드 원점은
    /// 세션 시작 시점의 카메라 위치라서 폰이 움직이면 기준이 어긋난다.
    /// 현재 카메라의 역행렬을 곱해 "지금 카메라에서 본 얼굴"로 바꿔 둔다.
    let faceInCamera: simd_float4x4

    /// 월드 좌표계 얼굴 transform. 정점을 화면에 투영할 때 사용한다.
    let faceInWorld: simd_float4x4

    /// 카메라 좌표계에서 본 중력 반대 방향(= 월드 +Y).
    ///
    /// 얼굴 추적 세션은 중력 기준 정렬이라 월드 +Y가 곧 실제 "위"다.
    /// 카메라 좌표계는 기기가 가로로 누운 상태를 기준으로 정의돼 있어서, 폰을 세로로 들면
    /// 카메라의 위쪽과 실제 위쪽이 90° 어긋난다. roll을 카메라 축이 아니라 이 벡터 기준으로
    /// 재야 "저장된 사진에서 고개가 얼마나 기울었나"와 같은 값이 나온다.
    let upInCamera: SIMD3<Float>

    let blendShapes: [ARFaceAnchor.BlendShapeLocation: Float]

    init(anchor: ARFaceAnchor, camera: ARCamera) {
        vertices = anchor.geometry.vertices
        leftEyeTransform = anchor.leftEyeTransform
        rightEyeTransform = anchor.rightEyeTransform
        faceInWorld = anchor.transform
        faceInCamera = camera.transform.inverse * anchor.transform
        let up = camera.transform.inverse * SIMD4<Float>(0, 1, 0, 0)
        upInCamera = SIMD3(up.x, up.y, up.z)
        blendShapes = anchor.blendShapes.reduce(into: [:]) { $0[$1.key] = $1.value.floatValue }
    }

    func blendShape(_ location: ARFaceAnchor.BlendShapeLocation) -> Float {
        blendShapes[location] ?? 0
    }
}

// MARK: - HeadPose

/// 카메라 기준 머리 자세. 정면 응시가 (0, 0, 0)에 가깝다.
struct HeadPose: Sendable {
    /// 좌우 회전 (도)
    let yaw: Float
    /// 상하 끄덕임 (도)
    let pitch: Float
    /// 갸웃 (도)
    let roll: Float

    /// 세 축 중 가장 큰 이탈각. 정면 판정에 쓴다.
    var maxDeviation: Float { max(abs(yaw), abs(pitch), abs(roll)) }
}

extension FaceAnchorSnapshot {

    /// `faceInCamera`의 각 열은 곧 "카메라 좌표계에서 본 얼굴의 로컬 축"이다.
    /// 정면 벡터(+Z)의 수평/수직 편차에서 yaw·pitch를, 위쪽 벡터(+Y)의 기울기에서 roll을 얻는다.
    ///
    /// roll만은 카메라 축이 아니라 중력(`upInCamera`) 기준으로 잰다. 카메라 좌표계는 기기가
    /// 가로로 누운 상태 기준이라, 폰을 세로로 들고 똑바로 앉은 사람을 찍어도 카메라 축 기준
    /// roll이 ±90°로 나와 정면 판정이 항상 실패한다.
    ///
    /// 세 축이 동시에 크게 돌아가면 축 간 결합이 생겨 값이 정확하지 않다.
    /// 이 값은 "정면에 충분히 가까운가"를 판정하는 용도이고 그 구간(±15° 내외)에서는
    /// 오차가 무시할 수준이라 별도의 정식 오일러 분해를 쓰지 않는다.
    ///
    /// - Important: 각 축의 **부호는 실기기에서 확인이 필요하다.**
    ///   ARKit 좌표계 규약상 아래가 맞다고 보지만, 검증 전에는 `ARFaceDebugView`로
    ///   실제 고개를 돌려 보고 부호가 반대면 여기서 뒤집는다.
    var headPose: HeadPose {
        let forward = faceInCamera.columns.2  // 얼굴 정면 (+Z)
        let up = faceInCamera.columns.1       // 얼굴 위쪽 (+Y)

        let yaw = atan2(forward.x, forward.z)
        let pitch = -asin(max(-1, min(1, forward.y)))

        // 이미지 평면(카메라 x·y)에 얼굴의 위쪽과 중력의 위쪽을 눕히고 사이각을 잰다.
        // 폰을 완전히 눕히면 중력의 투영이 0에 가까워 각이 무의미해지므로, 그때는 카메라 축으로 돌아간다.
        let reference = simd_length(SIMD2(upInCamera.x, upInCamera.y)) > 0.1
            ? SIMD2(upInCamera.x, upInCamera.y)
            : SIMD2<Float>(0, 1)
        let roll = atan2(
            up.x * reference.y - up.y * reference.x,
            up.x * reference.x + up.y * reference.y
        )

        let toDegrees = Float(180 / Double.pi)
        return HeadPose(
            yaw: yaw * toDegrees,
            pitch: pitch * toDegrees,
            roll: roll * toDegrees
        )
    }

    /// 눈을 뜬 정도 (0 = 완전히 감음, 1 = 완전히 뜸).
    ///
    /// - Note: ARKit의 `.eyeBlinkLeft`가 **사용자 기준** 왼쪽인지는 실기기 확인이 필요하다.
    ///   한쪽 눈만 감아 보면 바로 드러난다.
    var leftEyeOpenness: Float { 1 - blendShape(.eyeBlinkLeft) }
    var rightEyeOpenness: Float { 1 - blendShape(.eyeBlinkRight) }
}
