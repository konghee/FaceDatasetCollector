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

    var body: some View {
        ZStack {
            cameraLayer

            VStack {
                topBar
                Spacer()
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
            DatasetLabelingView(sample: sample, model: model)
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
