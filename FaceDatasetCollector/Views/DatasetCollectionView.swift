//
//  DatasetCollectionView.swift
//  FaceDatasetCollector
//

// 관상 모델 학습용 얼굴 데이터를 현장에서 모으는 화면.
// 전면 카메라로 얼굴을 잡고 → 셔터 → 눈/얼굴형을 손으로 라벨링 → 라벨별 폴더로 저장.
// 제품 플로우와는 분리된 수집 전용 도구다.

import ARKit
import SceneKit
import SwiftUI

struct DatasetCollectionView: View {
    @State private var model = DatasetCollectionModel()
    @State private var isShowingLibrary = false

#if DEBUG
    /// 판정 지표가 프레임마다 얼마나 흔들리는지 모은 범위. (계측용)
    @State private var spread: MetricSpread?
#endif

    var body: some View {
        ZStack {
            cameraLayer

            VStack {
                topBar
                Spacer()
                metricsProbe
                statusLabel
                shutterBar
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            model.manager.start()
            Task { await model.refreshStats() }
        }
        .onDisappear { model.manager.stop() }
        .sheet(item: $model.pending) { sample in
            // 시트를 두 번 여닫지 않고 안쪽 내용만 바꾼다. 시트를 갈아 끼우면
            // 닫힘 애니메이션 도중 다시 뜨면서 깜빡인다.
            switch model.stage {
            case .rank:
                if let result = model.rankResult {
                    RankResultView(
                        sample: sample,
                        result: result,
                        onContinue: model.advanceToLabeling
                    )
                } else {
                    DatasetLabelingView(sample: sample, model: model)
                }
            case .labeling:
                DatasetLabelingView(sample: sample, model: model)
            }
        }
        .sheet(isPresented: $isShowingLibrary) {
            DatasetLibraryView(model: model)
        }
        .alert("오류", isPresented: .init(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - 카메라

    @ViewBuilder
    private var cameraLayer: some View {
        if model.manager.isSupported {
            DatasetCameraPreview(session: model.manager.session)
                .ignoresSafeArea()
        } else {
            Color.black.ignoresSafeArea()
            Text("얼굴 추적을 지원하지 않는 기기입니다.\nTrueDepth 카메라가 있는 실기기에서 실행하세요.\n(시뮬레이터 불가)")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding()
        }
    }

    // MARK: - 상단

    private var topBar: some View {
        HStack(alignment: .top) {
            subjectField

            Spacer()

            Button {
                isShowingLibrary = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "folder")
                    Text("\(model.stats.totalSamples)장")
                        .font(.caption2.monospacedDigit())
                }
                .padding(10)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .foregroundStyle(.white)
    }

    private var subjectField: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle")

            TextField("피험자", text: $model.subjectID)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .frame(width: 80)

            Button("다음 사람") { model.advanceSubject() }
                .font(.caption.bold())
                .buttonStyle(.bordered)
        }
        .padding(10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 판정 지표 계측기

    /// 신분 판정에 쓰는 네 지표를 실시간으로 보여 준다. (DEBUG 전용)
    ///
    /// `RankReader.Threshold`의 기준값을 실측으로 맞추기 위한 도구다. 촬영하지 않고
    /// 카메라를 향하기만 해도 값이 보이므로 여러 사람을 빠르게 훑을 수 있다.
    ///
    /// 볼 것 두 가지 —
    /// 1. **중앙값**: 기준값을 어디에 둬야 반씩 갈리는가
    /// 2. **사람 간 차이**: 사람이 바뀌어도 값이 거의 안 변하면 그 지표는 못 쓴다
    @ViewBuilder
    private var metricsProbe: some View {
#if DEBUG
        if let result = model.liveResult {
            VStack(spacing: 4) {
                probeRow("IPD", result.metrics.ipdMM, spread?.ipd, "%.1f")
                probeRow("너비", result.metrics.widthMM, spread?.width, "%.1f")

                if let vision = model.landmarkMetrics {
                    Divider().overlay(.white.opacity(0.25)).padding(.vertical, 2)

                    probeRow("입", vision.mouthWidth, spread?.mouth, "%.3f")
                    probeRow("코", vision.noseWidth, spread?.nose, "%.3f")
                    probeRow("윤곽", vision.faceWidth, spread?.contour, "%.3f")
                    probeRow("눈입", vision.eyeToMouth, spread?.eyeToMouth, "%.3f")
                    probeRow("눈폭", vision.eyeWidth, spread?.eyeWidth, "%.3f")
                }

                HStack(spacing: 8) {
                    Text(result.rank.title)
                        .foregroundStyle(result.rank.tint)

                    Text("\(model.collectedFrameCount)장")
                        .foregroundStyle(.white.opacity(0.45))

                    Button("기억 삭제", action: model.forgetRanks)
                        .foregroundStyle(.orange.opacity(0.9))
                }
                .padding(.top, 2)
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 8)
            .onChange(of: result.metrics, initial: true) { _, metrics in
                spread = spread?.adding(metrics) ?? MetricSpread(metrics)
            }
            .onChange(of: model.landmarkMetrics) { _, vision in
                if let vision { spread = spread?.adding(vision) }
            }
            // 얼굴이 화면을 벗어나면 범위를 버린다. 안 그러면 ±가 앱을 켠 이후 본 모든
            // 얼굴의 누적 범위가 되어, 한 사람의 떨림을 재는 계측기 구실을 못 한다.
            .onChange(of: model.collectedFrameCount) { _, count in
                if count == 0 { spread = nil }
            }
        }
#endif
    }

#if DEBUG
    /// 같은 얼굴을 계속 보면서 값이 얼마나 떨리는지 모은다.
    ///
    /// 사람이 바뀔 때의 차이보다 이 떨림이 크면, 그 지표로는 사람을 가를 수 없다.
    private struct MetricSpread {
        var width: ClosedRange<Float>
        var ipd: ClosedRange<Float>

        // Vision 랜드마크 쪽. 얼굴이 잡히기 전에는 값이 없다.
        var mouth: ClosedRange<Float>?
        var nose: ClosedRange<Float>?
        var contour: ClosedRange<Float>?
        var eyeToMouth: ClosedRange<Float>?
        var eyeWidth: ClosedRange<Float>?

        init(_ metrics: FaceMetrics) {
            width = metrics.widthMM...metrics.widthMM
            ipd = metrics.ipdMM...metrics.ipdMM
        }

        func adding(_ metrics: FaceMetrics) -> MetricSpread {
            var copy = self
            copy.width = Self.extend(width, with: metrics.widthMM)
            copy.ipd = Self.extend(ipd, with: metrics.ipdMM)
            return copy
        }

        func adding(_ vision: FaceLandmarkMetrics) -> MetricSpread {
            var copy = self
            copy.mouth = Self.extend(mouth, with: vision.mouthWidth)
            copy.nose = Self.extend(nose, with: vision.noseWidth)
            copy.contour = Self.extend(contour, with: vision.faceWidth)
            copy.eyeToMouth = Self.extend(eyeToMouth, with: vision.eyeToMouth)
            copy.eyeWidth = Self.extend(eyeWidth, with: vision.eyeWidth)
            return copy
        }

        private static func extend(_ range: ClosedRange<Float>?, with value: Float) -> ClosedRange<Float> {
            guard let range else { return value...value }
            return extend(range, with: value)
        }

        private static func extend(_ range: ClosedRange<Float>, with value: Float) -> ClosedRange<Float> {
            min(range.lowerBound, value)...max(range.upperBound, value)
        }
    }

    /// `현재값  (떨림폭)` 한 줄.
    private func probeRow(
        _ title: String,
        _ value: Float,
        _ range: ClosedRange<Float>?,
        _ format: String
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 34, alignment: .leading)

            Text(String(format: format, value))

            if let range {
                Text(String(format: "±\(format)", (range.upperBound - range.lowerBound) / 2))
                    .foregroundStyle(.orange.opacity(0.9))
            }
        }
    }
#endif

    // MARK: - 상태 표시

    @ViewBuilder
    private var statusLabel: some View {
        // 각도·눈 상태가 제각각인 사진이 섞이면 모델이 얼굴이 아니라 자세를 배운다.
        // 촬영을 막지는 않고, 지금 상태를 계속 보여 주기만 한다.
        if let snapshot = model.manager.snapshot, let quality = model.quality {
            VStack(spacing: 6) {
                if let warning = quality.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                } else {
                    Label("촬영 가능", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                let pose = snapshot.headPose
                Text(String(
                    format: "yaw %+.0f°  pitch %+.0f°  roll %+.0f°",
                    pose.yaw, pose.pitch, pose.roll
                ))
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.8))

                if let lastSaved = model.lastSaved {
                    Text("저장됨 · \(lastSaved)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.55), in: Capsule())
        } else if model.manager.isSupported {
            Label("얼굴을 찾는 중…", systemImage: "face.dashed")
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.55), in: Capsule())
        }
    }

    // MARK: - 셔터

    private var shutterBar: some View {
        Button(action: model.capture) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)

                if model.isProcessing {
                    ProgressView().tint(.black)
                }

                Circle()
                    .fill(model.quality?.isGood == true ? .white : .white.opacity(0.5))
                    .frame(width: 62, height: 62)
            }
        }
        .disabled(!model.manager.isFaceTracked || model.isProcessing)
        .padding(.top, 16)
    }
}

// MARK: - 카메라 프리뷰

/// ARKit 세션의 카메라 화면만 띄우는 뷰.
///
/// 전면 카메라 원본은 거울 반전이 아니라서 화면이 좌우 반대로 보인다.
/// 저장되는 이미지와 같은 그림을 보여 주려면 이대로 두는 편이 맞다.
private struct DatasetCameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        view.automaticallyUpdatesLighting = false
        view.rendersContinuously = true
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

#Preview {
    DatasetCollectionView()
}
