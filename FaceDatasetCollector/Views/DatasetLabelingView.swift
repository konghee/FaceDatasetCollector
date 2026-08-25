//
//  DatasetLabelingView.swift
//  FaceDatasetCollector
//

import SwiftUI
import UIKit

/// 한 사람의 미분류 사진에 눈/얼굴형 정답을 한 번에 붙이는 화면.
///
/// 실제로 저장된 크롭을 그대로 보여 준다. 라벨은 이 크롭을 보고 정해야
/// 모델이 보게 될 그림과 정답이 어긋나지 않는다.
///
/// 눈은 왼쪽·오른쪽을 따로 고른다. 한 사람의 두 눈이 다른 모양인 경우가 드물지 않아서,
/// 한 번에 묶어 고르면 둘 중 한쪽에는 틀린 정답이 붙는다.
///
/// ## 왜 사람 단위인가
/// 라벨은 사진이 아니라 사람의 속성이다. 같은 사람을 다섯 장 찍었으면 눈 모양도 얼굴형도
/// 다섯 장 모두 같다. 장당 고르게 하면 같은 답을 다섯 번 고르게 되고, 반복 중에 손이
/// 미끄러지면 같은 얼굴에 다른 라벨이 붙어 그 클래스는 학습이 안 된다.
///
/// 그래도 사진을 골라 뺄 수 있게 둔 건, 눈을 감았거나 고개가 돌아간 한 장만 따로
/// 처리해야 할 때가 있기 때문이다.
struct DatasetLabelingView: View {
    let subject: UnlabeledSubject
    let queue: LabelingQueueModel

    /// 수집 화면의 집계. 라벨이 붙으면 클래스별 막대가 달라진다.
    let collection: DatasetCollectionModel

    /// 화면에 남아 있는 사진. 지운 장은 여기서 빠진다.
    ///
    /// `subject`를 그대로 그리지 않는 이유는, 값 타입이라 삭제 후에도 지운 사진이
    /// 계속 보이기 때문이다.
    @State private var records: [FaceSampleRecord]

    /// 라벨을 붙일 사진. 처음에는 전부 고른 상태다.
    @State private var selection: Set<UUID>

    @State private var leftEyeLabel: EyeLabel?
    @State private var rightEyeLabel: EyeLabel?
    @State private var faceLabel: FaceShapeLabel?
    @State private var isApplying = false
    @State private var deletionTarget: FaceSampleRecord?

    @Environment(\.dismiss) private var dismiss

    init(subject: UnlabeledSubject, queue: LabelingQueueModel, collection: DatasetCollectionModel) {
        self.subject = subject
        self.queue = queue
        self.collection = collection
        _records = State(initialValue: subject.records)
        _selection = State(initialValue: Set(subject.records.map(\.id)))
    }

    private var selectedRecords: [FaceSampleRecord] {
        records.filter { selection.contains($0.id) }
    }

    private var canApply: Bool {
        leftEyeLabel != nil && rightEyeLabel != nil && faceLabel != nil
            && !selection.isEmpty && !isApplying
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                photoStrip

                labelSection(
                    title: "왼쪽 \(EyeLabel.axisTitle)",
                    previews: selectedRecords.map(\.leftEyeCropPath),
                    options: Array(EyeLabel.allCases),
                    selection: $leftEyeLabel
                )

                labelSection(
                    title: "오른쪽 \(EyeLabel.axisTitle)",
                    previews: selectedRecords.map(\.rightEyeCropPath),
                    options: Array(EyeLabel.allCases),
                    selection: $rightEyeLabel
                )

                labelSection(
                    title: FaceShapeLabel.axisTitle,
                    previews: selectedRecords.map(\.faceCropPath),
                    options: Array(FaceShapeLabel.allCases),
                    selection: $faceLabel
                )
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) { applyBar }
        .navigationTitle(subject.subjectID)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "이 사진을 지웁니다. 원본과 기하값까지 함께 지워지며 되돌릴 수 없습니다.",
            isPresented: .init(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let deletionTarget { delete(deletionTarget) }
            }
        }
    }

    // MARK: - 사진 고르기

    /// 이 사람의 사진들. 눌러서 라벨 적용 대상에서 빼거나 넣는다.
    private var photoStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("사진 \(records.count)장").font(.headline)

                Spacer()

                Text("\(selection.count)장 선택됨")
                    .font(.caption)
                    .foregroundStyle(selection.isEmpty ? .orange : .secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(records) { record in
                        photoThumbnail(record)
                    }
                }
            }

            Text("눈을 감았거나 고개가 돌아간 사진은 눌러서 빼 두고, 나머지에 먼저 라벨을 붙이세요. 길게 누르면 지울 수 있습니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func photoThumbnail(_ record: FaceSampleRecord) -> some View {
        let isSelected = selection.contains(record.id)

        return Button {
            if isSelected {
                selection.remove(record.id)
            } else {
                selection.insert(record.id)
            }
        } label: {
            DatasetCropView(path: record.faceCropPath, side: 84)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 3)
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.footnote)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
                        .background(Circle().fill(.black.opacity(0.35)))
                        .padding(5)
                }
                .opacity(isSelected ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("이 사진 삭제", systemImage: "trash", role: .destructive) {
                deletionTarget = record
            }
        }
    }

    // MARK: - 라벨 선택

    /// 저장된 크롭을 축 바로 위에 깔아 둔다.
    ///
    /// 한 장이 아니라 고른 사진 전부를 보여 주는 이유는, 조명이나 각도 때문에 한 장에서만
    /// 다르게 보이는 경우가 있기 때문이다. 여러 장을 같이 놓고 봐야 그 사람의 눈이 보인다.
    private func labelSection<Label: DatasetLabel>(
        title: String,
        previews: [String?],
        options: [Label],
        selection: Binding<Label?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title).font(.headline)

                if selection.wrappedValue == nil {
                    Text("선택 필요")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(previews.enumerated()), id: \.offset) { _, path in
                        DatasetCropView(path: path, side: 96)
                    }
                }
            }

            // 라벨 수가 9개까지라 한 화면에 다 깔아 두는 편이 스크롤보다 빠르다.
            FlowLayout(spacing: 8) {
                ForEach(options) { option in
                    let isSelected = selection.wrappedValue == option

                    Button {
                        selection.wrappedValue = isSelected ? nil : option
                    } label: {
                        Text(option.pickerTitle)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 적용

    private var applyBar: some View {
        // 실패는 목록 화면의 alert가 이 위에 띄운다. 시트가 아니라 푸시된 화면이라
        // 가려지지 않으므로, 여기에 같은 말을 또 적지 않는다.
        VStack(spacing: 8) {
            Button(action: apply) {
                HStack {
                    if isApplying { ProgressView().tint(.white) }
                    Text(applyTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canApply)
        }
        .padding()
        .background(.bar)
    }

    private var applyTitle: String {
        if selection.isEmpty { return "사진을 하나 이상 고르세요" }
        guard leftEyeLabel != nil, rightEyeLabel != nil, faceLabel != nil else {
            return "양쪽 눈·얼굴형을 모두 고르세요"
        }
        return "\(selection.count)장에 라벨 붙이기"
    }

    private func apply() {
        guard let leftEyeLabel, let rightEyeLabel, let faceLabel else { return }

        isApplying = true
        Task {
            await queue.apply(
                to: Array(selection),
                leftEye: leftEyeLabel,
                rightEye: rightEyeLabel,
                faceShape: faceLabel
            )
            await collection.refreshStats()
            isApplying = false

            // 실패했으면 화면에 남아 메시지를 보여 준다. 닫아 버리면 무엇이 안 됐는지 모른다.
            if queue.errorMessage == nil { dismiss() }
        }
    }

    private func delete(_ record: FaceSampleRecord) {
        Task {
            await queue.delete([record.id])
            await collection.refreshStats()

            records.removeAll { $0.id == record.id }
            selection.remove(record.id)
            deletionTarget = nil

            if records.isEmpty { dismiss() }
        }
    }
}

// MARK: - FlowLayout

/// 칩을 왼쪽부터 채우다 폭이 모자라면 다음 줄로 넘기는 레이아웃.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: width == .infinity ? rows.map(\.width).max() ?? 0 : width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in layout(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)

            if !current.indices.isEmpty, x + size.width > width {
                current.width = x - spacing
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
                x = 0
            }

            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }

        if !current.indices.isEmpty {
            current.width = x - spacing
            rows.append(current)
        }

        return rows
    }
}
