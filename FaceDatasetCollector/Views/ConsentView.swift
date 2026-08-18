//
//  ConsentView.swift
//  FaceDatasetCollector
//

// 촬영 전에 참여자에게 보여 주는 동의 화면.
//
// 부스에서 이 화면은 `RankResultView`처럼 **참여자 쪽으로 돌려서** 보여 준다.
// 사진이 모델 학습에 쓰인다는 사실을 참여자가 직접 읽고 누르게 하는 것이 목적이므로,
// 수집자가 대신 넘길 수 있는 자리(스와이프로 내리기)는 막아 둔다.

import SwiftUI

struct ConsentView: View {
    /// 지금 동의를 받는 사람의 구분자. 누구에게 받는 동의인지 수집자가 눈으로 확인한다.
    let subjectID: String

    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    VStack(alignment: .leading, spacing: 20) {
                        clause(
                            "camera.fill",
                            "무엇을 저장하나요",
                            "얼굴 사진(전체 사진과 눈·얼굴 부분 사진), 고개 각도와 동공간거리 같은 얼굴 치수, 얼굴 메시 좌표를 저장합니다."
                        )

                        clause(
                            "brain",
                            "어디에 쓰나요",
                            "눈 모양과 얼굴형을 알아보는 관상 모델을 학습하고 검증하는 데 씁니다."
                        )

                        clause(
                            "person.text.rectangle",
                            "이름도 함께 남나요",
                            "사진에는 지금 입력한 구분자 \(displayedSubjectID)가 함께 저장됩니다. 같은 사람의 사진을 한데 묶기 위한 표시입니다."
                        )

                        clause(
                            "externaldrive.fill",
                            "어디에 보관되나요",
                            "사진은 이 기기의 앱 폴더에 저장되며, 수집자가 학습용으로 내보냅니다."
                        )

                        clause(
                            "hand.raised.fill",
                            "그만두고 싶으면",
                            "촬영 도중 언제든 말해 주세요. 저장하기 전이면 그 자리에서 버립니다."
                        )
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .navigationTitle("촬영 동의")
            .navigationBarTitleDisplayMode(.inline)
        }
        // 읽지 않고 시트를 쓸어내려 닫는 것으로는 동의가 되지 않는다.
        // 동의든 거절이든 버튼을 눌러 정하게 한다.
        .interactiveDismissDisabled()
    }

    /// 구분자를 아직 안 적었을 때 빈칸이 보이지 않게 한다.
    private var displayedSubjectID: String {
        subjectID.isEmpty ? "(미입력)" : subjectID
    }

    // MARK: - 머리말

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("피험자 \(displayedSubjectID)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Text("찍은 사진은\n모델 학습에 쓰입니다")
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text("아래 내용을 읽고 동의하면 촬영을 시작합니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 항목

    private func clause(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)

                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 하단

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button(action: onAgree) {
                Text("동의합니다")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)

            Button("동의하지 않습니다", role: .cancel, action: onDecline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.bar)
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            ConsentView(subjectID: "S001", onAgree: {}, onDecline: {})
        }
}
