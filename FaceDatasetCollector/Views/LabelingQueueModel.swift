//
//  LabelingQueueModel.swift
//  FaceDatasetCollector
//

import Foundation
import Observation

/// 라벨링을 기다리는 표본들의 상태.
///
/// 수집(`DatasetCollectionModel`)과 분리해 둔 이유는 두 작업이 다른 시각에, 다른 사람 앞에서
/// 일어나기 때문이다. 수집은 부스에서 참여자를 앞에 두고, 라벨링은 부스가 끝난 뒤 혼자
/// 한다. 한 모델에 섞으면 촬영 중에는 쓰지 않는 상태가 계속 딸려 다닌다.
@MainActor
@Observable
final class LabelingQueueModel {

    private(set) var subjects: [UnlabeledSubject] = []
    private(set) var isLoading = false

    var errorMessage: String?

    var totalCount: Int { subjects.reduce(0) { $0 + $1.count } }

    func reload() async {
        isLoading = true
        subjects = await FaceDatasetStore.shared.unlabeledSubjects()
        isLoading = false
    }

    /// 고른 표본들에 같은 라벨을 붙인다. 크롭이 라벨 폴더로 옮겨 가고 index.csv가 다시 쓰인다.
    func apply(
        to ids: [UUID],
        leftEye: EyeLabel,
        rightEye: EyeLabel,
        faceShape: FaceShapeLabel
    ) async {
        errorMessage = nil
        do {
            try await FaceDatasetStore.shared.applyLabels(
                to: ids,
                leftEye: leftEye,
                rightEye: rightEye,
                faceShape: faceShape
            )
        } catch {
            errorMessage = "라벨 적용 실패: \(error.localizedDescription)"
        }
        await reload()
    }

    /// 잘못 찍힌 표본을 지운다. 촬영 때 버릴 기회가 없어졌으니 여기서 골라낸다.
    func delete(_ ids: [UUID]) async {
        errorMessage = nil
        do {
            try await FaceDatasetStore.shared.delete(ids: ids)
        } catch {
            errorMessage = "삭제 실패: \(error.localizedDescription)"
        }
        await reload()
    }
}
