//
//  DatasetLibraryView.swift
//  FaceDatasetCollector
//

import ImageIO
import SwiftUI
import UIKit

/// 모은 데이터를 확인하고 밖으로 빼는 화면.
///
/// 라벨별 장수를 보여 주는 게 핵심이다. 클래스별 장수가 크게 기울면
/// 모델이 많은 쪽으로만 답하게 되므로, 다음에 누구를 찍어야 하는지 여기서 정한다.
struct DatasetLibraryView: View {
    let model: DatasetCollectionModel

    @State private var exportArchive: ExportArchive?
    @State private var isExporting = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("요약") {
                    LabeledContent("총 표본", value: "\(model.stats.totalSamples)장")
                    LabeledContent("저장 위치", value: "Documents/FaceDataset")
                }

                labelingSection

                countSection(
                    title: EyeLabel.axisTitle,
                    labels: EyeLabel.allCases.map { ($0.pickerTitle, $0.folderName) },
                    counts: model.stats.eyeCounts
                )

                countSection(
                    title: FaceShapeLabel.axisTitle,
                    labels: FaceShapeLabel.allCases.map { ($0.pickerTitle, $0.folderName) },
                    counts: model.stats.faceShapeCounts
                )

                Section {
                    Button {
                        export()
                    } label: {
                        HStack {
                            Label("zip으로 내보내기", systemImage: "square.and.arrow.up")
                            Spacer()
                            if isExporting { ProgressView() }
                        }
                    }
                    .disabled(isExporting || model.stats.totalSamples == 0)

                    Button("전체 삭제", role: .destructive) { isConfirmingDelete = true }
                        .disabled(model.stats.totalSamples == 0)
                } header: {
                    Text("내보내기")
                } footer: {
                    Text("zip 안의 images/eye, images/faceShape 폴더는 Create ML 이미지 분류기에 그대로 넣을 수 있습니다. Xcode에서 기기를 연결하면 Devices and Simulators → 앱 → Download Container로도 통째로 받을 수 있습니다.")
                }

                orientationSection
            }
            .navigationTitle("데이터셋")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .task { await model.refreshStats() }
            .sheet(item: $exportArchive) { archive in
                DatasetShareSheet(items: [archive.url])
            }
            .confirmationDialog(
                "저장된 표본을 모두 지웁니다. 되돌릴 수 없습니다.",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("전체 삭제", role: .destructive) { deleteAll() }
            }
            .alert("오류", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - 라벨링 대기

    /// 아직 라벨이 안 붙은 표본으로 들어가는 입구.
    ///
    /// 부스에서는 사진만 모으므로, 촬영이 끝나면 여기에 전부 쌓여 있다.
    /// 내보내기 바로 위에 둔 건 순서가 그렇기 때문이다 — 라벨을 붙여야 내보낼 값이 된다.
    private var labelingSection: some View {
        Section {
            NavigationLink {
                DatasetLabelingQueueView(collection: model)
            } label: {
                HStack {
                    Label("라벨링 대기", systemImage: "tag")

                    Spacer()

                    if model.stats.unlabeledSamples == 0 {
                        Text("없음").foregroundStyle(.secondary)
                    } else {
                        Text("\(model.stats.unlabeledSubjects)명 · \(model.stats.unlabeledSamples)장")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }
            }
        } header: {
            Text("라벨링")
        } footer: {
            Text("촬영은 라벨 없이 저장합니다. 눈·얼굴형은 여기서 사람 단위로 몰아서 붙이세요. 라벨이 붙어야 사진이 `images/` 아래 클래스 폴더로 옮겨져 Create ML에 들어갑니다.")
        }
    }

    // MARK: - 라벨별 장수

    private func countSection(
        title: String,
        labels: [(String, String)],
        counts: [String: Int]
    ) -> some View {
        let maximum = max(counts.values.max() ?? 0, 1)

        return Section {
            ForEach(labels, id: \.1) { name, folder in
                let count = counts[folder] ?? 0

                HStack {
                    Text(name)
                    Spacer()

                    // 클래스 불균형을 숫자보다 막대로 보는 편이 빠르다.
                    Capsule()
                        .fill(count == 0 ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tint))
                        .frame(width: 90 * CGFloat(count) / CGFloat(maximum) + 4, height: 8)

                    Text("\(count)")
                        .font(.callout.monospacedDigit())
                        .frame(width: 36, alignment: .trailing)
                        .foregroundStyle(count == 0 ? .secondary : .primary)
                }
            }
        } header: {
            Text(title)
        } footer: {
            // 미분류가 쌓여 있는 동안 막대는 전체 분포가 아니다. 그걸 모르고 보면
            // "아직 아무것도 안 모였다"고 오해한다.
            if model.stats.unlabeledSamples > 0 {
                Text("라벨이 붙은 \(model.stats.totalSamples - model.stats.unlabeledSamples)장만 셉니다. 미분류 \(model.stats.unlabeledSamples)장은 아직 어느 칸에도 들어 있지 않습니다.")
            }
        }
    }

    // MARK: - 이미지 방향

    private var orientationSection: some View {
        Section {
            Picker("이미지 방향", selection: Binding(
                get: { model.captureOrientation },
                set: { model.captureOrientation = $0 }
            )) {
                ForEach(Self.orientationOptions, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
        } header: {
            Text("촬영 설정")
        } footer: {
            Text("`자동`은 ARKit이 미리보기를 그릴 때 쓰는 변환에서 방향을 계산하므로, 화면에서 똑바로 보이는 그림이 그대로 저장됩니다. 그래도 저장본이 눕거나 뒤집혀 보일 때만 고정 방향으로 바꾸세요. 바꾸기 전에 찍은 사진은 그대로 남으므로 초반에 한 번만 확인하는 게 좋습니다.")
        }
    }

    private static let orientationOptions: [(title: String, value: CaptureOrientation)] = [
        ("자동 (기본)", .automatic),
        ("오른쪽으로 90°", .fixed(.right)),
        ("오른쪽 90° + 좌우반전", .fixed(.rightMirrored)),
        ("왼쪽으로 90°", .fixed(.left)),
        ("왼쪽 90° + 좌우반전", .fixed(.leftMirrored)),
        ("그대로", .fixed(.up)),
        ("좌우반전", .fixed(.upMirrored)),
        ("180° 회전", .fixed(.down)),
    ]

    // MARK: - 동작

    private func export() {
        isExporting = true
        Task {
            do {
                exportArchive = ExportArchive(url: try await FaceDatasetStore.shared.exportArchive())
            } catch {
                errorMessage = "내보내기 실패: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }

    private func deleteAll() {
        Task {
            do {
                try await FaceDatasetStore.shared.deleteAll()
                await model.refreshStats()
            } catch {
                errorMessage = "삭제 실패: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 공유 시트

/// `sheet(item:)`에 넘기기 위한 래퍼. (`URL`에 retroactive conformance를 붙이지 않으려고 둔다.)
private struct ExportArchive: Identifiable {
    let id = UUID()
    let url: URL
}

/// zip 파일을 AirDrop·파일 앱 등으로 넘기기 위한 래퍼.
struct DatasetShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
