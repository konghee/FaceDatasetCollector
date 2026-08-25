//
//  DatasetLabelingQueueView.swift
//  FaceDatasetCollector
//

// 라벨이 아직 안 붙은 표본을 사람별로 보여 주는 목록.
//
// 부스에서는 사진만 모으고 라벨은 여기서 나중에 몰아 붙인다. 참여자를 앞에 세워 둔 채
// 눈 9종·얼굴형 5종을 고르면 한 사람당 수십 초가 더 걸리고, 급하게 고른 라벨은
// 어차피 다시 봐야 한다.

import SwiftUI

struct DatasetLabelingQueueView: View {

    /// 수집 화면의 집계. 라벨을 붙이면 막대가 달라지므로 같이 갱신한다.
    let collection: DatasetCollectionModel

    @State private var queue = LabelingQueueModel()

    var body: some View {
        List {
            if !queue.subjects.isEmpty {
                Section {
                    ForEach(queue.subjects) { subject in
                        NavigationLink {
                            DatasetLabelingView(
                                subject: subject,
                                queue: queue,
                                collection: collection
                            )
                        } label: {
                            row(subject)
                        }
                    }
                } header: {
                    Text("\(queue.subjects.count)명 · \(queue.totalCount)장")
                } footer: {
                    Text("한 사람을 고르면 그 사람의 사진 전부에 같은 라벨이 붙습니다. 같은 사람의 눈 모양과 얼굴형은 사진이 바뀐다고 달라지지 않기 때문입니다.")
                }
            }
        }
        .navigationTitle("라벨링 대기")
        .navigationBarTitleDisplayMode(.inline)
        .task { await queue.reload() }
        .overlay {
            if queue.isLoading {
                if queue.subjects.isEmpty { ProgressView() }
            } else if queue.subjects.isEmpty {
                ContentUnavailableView(
                    "라벨링 대기 없음",
                    systemImage: "checkmark.circle",
                    description: Text("찍은 사진에 라벨이 모두 붙었습니다.")
                )
            }
        }
        .alert("오류", isPresented: .init(
            get: { queue.errorMessage != nil },
            set: { if !$0 { queue.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { queue.errorMessage = nil }
        } message: {
            Text(queue.errorMessage ?? "")
        }
    }

    private func row(_ subject: UnlabeledSubject) -> some View {
        HStack(spacing: 12) {
            DatasetCropView(path: subject.records.first?.faceCropPath, side: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(subject.subjectID)
                    .font(.headline.monospaced())

                Text("\(subject.count)장")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let capturedAt = subject.capturedAt {
                    Text(capturedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
