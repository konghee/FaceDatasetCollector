//
//  DatasetLabelingView.swift
//  FaceDatasetCollector
//

import SwiftUI
import UIKit

/// 방금 찍은 표본에 눈/얼굴형 정답을 붙이는 화면.
///
/// 실제로 저장될 크롭을 그대로 보여 준다. 라벨은 이 크롭을 보고 정해야
/// 모델이 보게 될 그림과 정답이 어긋나지 않는다.
///
/// 눈은 왼쪽·오른쪽을 따로 고른다. 한 사람의 두 눈이 다른 모양인 경우가 드물지 않아서,
/// 한 번에 묶어 고르면 둘 중 한쪽에는 틀린 정답이 붙는다.
struct DatasetLabelingView: View {
    let sample: PendingSample
    let model: DatasetCollectionModel

    @State private var leftEyeLabel: EyeLabel?
    @State private var rightEyeLabel: EyeLabel?
    @State private var faceLabel: FaceShapeLabel?

    private var canSave: Bool {
        leftEyeLabel != nil && rightEyeLabel != nil && faceLabel != nil && !model.isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !sample.hasAllCrops {
                        Label(
                            "얼굴 검출에 실패해 일부 크롭이 비어 있습니다. 원본은 저장되니 나중에 다시 자를 수 있지만, 다시 찍는 편이 좋습니다.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }

                    header

                    labelSection(
                        title: "왼쪽 \(EyeLabel.axisTitle)",
                        preview: sample.leftEyeCrop,
                        options: Array(EyeLabel.allCases),
                        selection: $leftEyeLabel
                    )

                    labelSection(
                        title: "오른쪽 \(EyeLabel.axisTitle)",
                        preview: sample.rightEyeCrop,
                        options: Array(EyeLabel.allCases),
                        selection: $rightEyeLabel
                    )

                    labelSection(
                        title: FaceShapeLabel.axisTitle,
                        preview: sample.faceCrop,
                        options: Array(FaceShapeLabel.allCases),
                        selection: $faceLabel
                    )
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) { saveBar }
            .navigationTitle("라벨 붙이기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 시트는 `model.pending`이 비면 닫힌다. 따로 dismiss를 부르면
                    // 아직 pending이 남아 있는 순간에 시트가 다시 뜰 수 있다.
                    Button("버리기", role: .destructive) { model.discardPending() }
                }
            }
            .interactiveDismissDisabled()
        }
    }

    // MARK: - 미리보기

    /// 전체 프레임과 촬영 수치. 방향이 어긋났는지 여기서 바로 보인다.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = UIImage(data: sample.fullFrame) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 8) {
                let geometry = sample.geometry
                Text(String(
                    format: "yaw %+.0f°\npitch %+.0f°\nroll %+.0f°\n동공간거리 %.0fmm\n피험자 %@",
                    geometry.yaw, geometry.pitch, geometry.roll,
                    geometry.interpupillaryDistance, model.subjectID
                ))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

                Text("사진이 옆으로 누워 있으면 데이터셋 화면에서 이미지 방향을 바꾸세요.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func cropThumbnail(_ data: Data?, side: CGFloat) -> some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .frame(width: side, height: side)
                .overlay(Image(systemName: "xmark").foregroundStyle(.secondary))
        }
    }

    // MARK: - 라벨 선택

    /// 저장될 크롭을 축 바로 옆에 붙여 둔다.
    /// 눈은 좌·우가 따로 나오므로, 지금 어느 쪽을 고르는지 그림으로 봐야 헷갈리지 않는다.
    private func labelSection<Label: DatasetLabel>(
        title: String,
        preview: Data?,
        options: [Label],
        selection: Binding<Label?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                cropThumbnail(preview, side: 96)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    if selection.wrappedValue == nil {
                        Text("선택 필요")
                            .font(.caption)
                            .foregroundStyle(.orange)
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

    // MARK: - 저장

    private var saveBar: some View {
        VStack(spacing: 8) {
            // 저장 실패는 여기서 보여 준다. 뒤 화면의 알림은 시트에 가려 보이지 않는다.
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                guard let leftEyeLabel, let rightEyeLabel, let faceLabel else { return }
                // 저장이 끝나 `pending`이 비면 시트가 알아서 닫힌다.
                model.save(leftEye: leftEyeLabel, rightEye: rightEyeLabel, faceShape: faceLabel)
            } label: {
                HStack {
                    if model.isSaving { ProgressView().tint(.white) }
                    Text(canSave ? "저장하고 다음 촬영" : "양쪽 눈·얼굴형을 모두 고르세요")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
        .padding()
        .background(.bar)
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
