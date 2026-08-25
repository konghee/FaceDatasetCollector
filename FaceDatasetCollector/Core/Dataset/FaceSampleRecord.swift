//
//  FaceSampleRecord.swift
//  FaceDatasetCollector
//

import ARKit
import Foundation
import simd

/// 촬영 직후, 아직 라벨이 붙지 않은 한 장의 표본.
///
/// `ARFrame`/`ARFaceAnchor`는 ARKit이 재사용하는 참조 타입이라 촬영 순간에
/// 전부 값(JPEG `Data`, 정점 배열)으로 떠 두고 프레임은 즉시 놓아준다.
/// 그래야 라벨링 화면에 오래 머물러도 세션이 멈추지 않는다.
nonisolated struct PendingSample: Identifiable, Sendable {
    let id: UUID
    let capturedAt: Date

    /// 전체 프레임(세로 방향). 나중에 크롭 규칙을 바꿔도 다시 자를 수 있게 원본을 남긴다.
    let fullFrame: Data

    /// 얼굴형 학습용 크롭. 턱선·이마가 잘리면 얼굴형을 못 배우므로 넉넉히 자른다.
    let faceCrop: Data?

    /// 눈 학습용 크롭. `EyeCropper` 규칙을 그대로 써서 추론 때와 같은 구도로 맞춘다.
    let leftEyeCrop: Data?
    let rightEyeCrop: Data?

    /// ARKit 얼굴 메시 정점(얼굴 로컬 좌표계, 미터). 1220개.
    let vertices: [SIMD3<Float>]

    let geometry: SampleGeometry

    /// Vision이 얼굴을 못 찾아 크롭이 비었는지. 비었으면 저장 전에 경고한다.
    var hasAllCrops: Bool { faceCrop != nil && leftEyeCrop != nil && rightEyeCrop != nil }
}

/// 이미지와 함께 남기는 수치. 나중에 기하 기반(비이미지) 모델을 학습할 때 쓴다.
nonisolated struct SampleGeometry: Codable, Sendable {
    let yaw: Float
    let pitch: Float
    let roll: Float

    /// 동공간거리(mm). 얼굴 메시의 절대 크기 기준값이라 정규화에 쓸 수 있다.
    let interpupillaryDistance: Float

    let leftEyeOpenness: Float
    let rightEyeOpenness: Float

    let blendShapes: [String: Float]

    init(snapshot: FaceAnchorSnapshot) {
        let pose = snapshot.headPose
        yaw = pose.yaw
        pitch = pose.pitch
        roll = pose.roll
        interpupillaryDistance = simd_distance(
            snapshot.leftEyeTransform.translation,
            snapshot.rightEyeTransform.translation
        ).inMillimeters
        leftEyeOpenness = snapshot.leftEyeOpenness
        rightEyeOpenness = snapshot.rightEyeOpenness
        blendShapes = snapshot.blendShapes.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
    }
}

/// 저장이 끝난 표본 한 건의 기록. `meta/<id>.json`으로 남는다.
nonisolated struct FaceSampleRecord: Codable, Sendable, Identifiable {
    let id: UUID
    let capturedAt: Date

    /// 같은 사람의 사진이 학습/검증 셋에 나뉘어 들어가면 정확도가 부풀려진다.
    /// 나중에 사람 단위로 split 하려면 이 값이 반드시 필요하다.
    let subjectID: String

    /// 이 사람에게 촬영 동의를 받은 시각.
    ///
    /// 옵셔널이 아닌 이유는, 동의 시각이 없는 표본은 애초에 저장되지 않기 때문이다.
    /// 데이터셋을 나중에 넘겨받은 사람이 "이 사진들은 동의를 받고 찍은 것인가"를
    /// 앱 밖에서, 파일만 보고 답할 수 있어야 한다.
    let consentedAt: Date

    /// 눈은 좌·우를 따로 본다. 한쪽이 봉황눈이고 다른 쪽이 용눈일 수 있어
    /// 한 라벨로 묶으면 둘 중 하나는 틀린 정답이 된다.
    ///
    /// 촬영 시점에는 셋 다 `nil`이다. 부스에서는 참여자를 세워 둔 채 눈 9종·얼굴형 5종을
    /// 고를 시간이 없어, 사진만 먼저 모으고 나중에 사람 단위로 몰아서 붙인다.
    /// (`FaceDatasetStore.applyLabels(to:...)`)
    var leftEyeLabel: String?
    var rightEyeLabel: String?
    var faceShapeLabel: String?

    let geometry: SampleGeometry

    /// 데이터셋 루트 기준 상대 경로.
    ///
    /// 크롭 셋은 라벨이 붙는 순간 `pending/`에서 `images/<축>/<라벨>/`로 **옮겨진다.**
    /// 경로가 `let`이 아닌 건 그래서다.
    let fullFramePath: String
    var faceCropPath: String?
    var leftEyeCropPath: String?
    var rightEyeCropPath: String?
    let verticesPath: String

    let deviceModel: String
    let schemaVersion: Int

    /// 세 축이 모두 정해졌는지. 하나라도 비면 라벨링 대기 목록에 남는다.
    var isLabeled: Bool {
        leftEyeLabel != nil && rightEyeLabel != nil && faceShapeLabel != nil
    }

    /// 2: `eyeLabel` 하나를 `leftEyeLabel`/`rightEyeLabel`로 나눴고,
    ///    roll을 카메라 축이 아닌 중력 기준으로 재기 시작했다.
    /// 3: 촬영 동의 시각(`consentedAt`)을 표본마다 남기기 시작했다.
    ///    이 값이 없는 2 이하의 기록은 동의를 받기 전에 모은 것이다.
    /// 4: 라벨을 촬영과 분리했다. 라벨 셋이 옵셔널이 되고, 붙기 전의 크롭은
    ///    `images/`가 아니라 `pending/`에 있다.
    static let currentSchemaVersion = 4
}
