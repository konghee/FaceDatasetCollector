//
//  DatasetCollectionModel.swift
//  FaceDatasetCollector
//

import ARKit
import Foundation
import Observation

/// 데이터 수집 화면의 상태.
///
/// 촬영 → 라벨링 → 저장의 한 사이클을 들고 있으며, 저장이 끝나면 곧바로
/// 다음 촬영을 받을 수 있게 스스로를 비운다.
@MainActor
@Observable
final class DatasetCollectionModel {

    let manager = ARFaceCaptureManager()

    /// 라벨링을 기다리는 표본. 값이 있으면 라벨링 시트가 뜬다.
    var pending: PendingSample?

    var stats = DatasetStats()
    var isProcessing = false
    var isSaving = false
    var errorMessage: String?

    /// 방금 저장한 표본 요약. 화면 위에 잠깐 띄운다.
    var lastSaved: String?

    /// 피험자 구분자.
    ///
    /// 같은 사람의 사진이 학습 셋과 검증 셋에 나뉘어 들어가면 모델이 "그 사람"을 외워
    /// 정확도가 실제보다 높게 나온다. 나중에 사람 단위로 나누려면 촬영 시점에
    /// 누구인지 남겨 두는 수밖에 없다.
    var subjectID: String {
        didSet { UserDefaults.standard.set(subjectID, forKey: Keys.subjectID) }
    }

    /// 센서 원본(가로)을 세로로 세우는 방식.
    ///
    /// 기본값은 ARKit의 표시 변환에서 매번 역산하는 `.automatic`이라 손댈 일이 없다.
    /// 그래도 고정 방향을 남겨 둔 건, 자동이 어긋나는 기기를 만났을 때 전부 다시 찍는 대신
    /// 화면에서 바로 덮어쓸 수 있게 하기 위해서다.
    var captureOrientation: CaptureOrientation {
        didSet { UserDefaults.standard.set(captureOrientation.storedValue, forKey: Keys.orientation) }
    }

    private enum Keys {
        static let subjectID = "dataset.subjectID"
        static let orientation = "dataset.imageOrientation"
    }

    init() {
        subjectID = UserDefaults.standard.string(forKey: Keys.subjectID) ?? "S001"
        captureOrientation = CaptureOrientation(
            storedValue: UserDefaults.standard.integer(forKey: Keys.orientation)
        )
    }

    // MARK: - 촬영

    var quality: CaptureQuality? {
        manager.snapshot.map(CaptureQuality.init)
    }

    func capture() {
        guard !isProcessing, pending == nil else { return }

        guard let raw = DatasetCapture.grab(from: manager, orientation: captureOrientation) else {
            errorMessage = "얼굴을 찾지 못했습니다. 화면 안에 얼굴을 맞춰 주세요."
            return
        }

        isProcessing = true
        Task {
            // Vision 검출과 JPEG 인코딩은 무거워서 백그라운드로 넘긴다.
            let sample = await DatasetCapture.makeSample(from: raw)
            pending = sample
            isProcessing = false
        }
    }

    func discardPending() {
        pending = nil
    }

    // MARK: - 저장

    func save(leftEye: EyeLabel, rightEye: EyeLabel, faceShape: FaceShapeLabel) {
        guard let sample = pending, !isSaving else { return }

        isSaving = true
        Task {
            do {
                try await FaceDatasetStore.shared.save(
                    sample,
                    leftEye: leftEye,
                    rightEye: rightEye,
                    faceShape: faceShape,
                    subjectID: subjectID
                )
                lastSaved = "\(subjectID) · \(leftEye.folderName)/\(rightEye.folderName) · \(faceShape.folderName)"
                pending = nil
                await refreshStats()
            } catch {
                errorMessage = "저장 실패: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }

    func refreshStats() async {
        stats = await FaceDatasetStore.shared.stats()
    }

    /// 다음 사람으로 넘어간다. `S001` → `S002`처럼 숫자 부분만 올린다.
    func advanceSubject() {
        let digits = subjectID.suffix(while: \.isNumber)
        guard let number = Int(digits), !digits.isEmpty else {
            subjectID += "-2"
            return
        }

        let prefix = subjectID.dropLast(digits.count)
        subjectID = prefix + String(format: "%0\(digits.count)d", number + 1)
    }
}

private extension StringProtocol {
    /// 문자열 끝에서부터 조건을 만족하는 동안 잘라낸다. (`"S012"` → `"012"`)
    func suffix(while predicate: (Character) -> Bool) -> String {
        String(reversed().prefix(while: predicate).reversed())
    }
}
