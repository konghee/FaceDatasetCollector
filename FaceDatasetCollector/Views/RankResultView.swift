//
//  RankResultView.swift
//  FaceDatasetCollector
//

// 촬영 직후 참여자에게 보여 주는 화면.
//
// 부스에서 이 화면은 **참여자 쪽으로 돌려서** 보여 준다. 수집자용 라벨링 화면과 달리
// 정보를 최대한 덜어내고 결과 하나만 크게 띄운다.

import SwiftUI

struct RankResultView: View {
    let sample: PendingSample
    let result: RankResult

    /// 라벨링으로 넘어간다. 참여자가 결과를 다 본 뒤 수집자가 누른다.
    let onContinue: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                portrait
                    .scaleEffect(hasAppeared ? 1 : 0.86)
                    .opacity(hasAppeared ? 1 : 0)

                rankTitle
                    .padding(.top, 22)
                    .opacity(hasAppeared ? 1 : 0)

                headline
                    .padding(.top, 14)
                    .opacity(hasAppeared ? 1 : 0)

                reasonChips
                    .padding(.top, 20)
                    .opacity(hasAppeared ? 1 : 0)

                Spacer(minLength: 12)

                continueButton
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // 결과가 툭 튀어나오는 것보다 살짝 떠오르는 편이 "판정받는" 기분이 난다.
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - 배경

    private var background: some View {
        LinearGradient(
            colors: [
                result.rank.tint.opacity(0.55),
                Color(red: 0.09, green: 0.08, blue: 0.07),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - 얼굴

    /// 얼굴 크롭을 원형 액자에 넣는다. 크롭이 없으면 전체 프레임으로 대신한다.
    private var portrait: some View {
        let imageData = sample.faceCrop ?? sample.fullFrame

        return ZStack {
            Circle()
                .fill(.black.opacity(0.35))

            if let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 210, height: 210)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(result.rank.tint, lineWidth: 4)
        }
        .overlay(alignment: .bottom) {
            Image(systemName: result.rank.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.black.opacity(0.85))
                .frame(width: 54, height: 54)
                .background(result.rank.tint, in: Circle())
                .overlay {
                    Circle().strokeBorder(.black.opacity(0.25), lineWidth: 2)
                }
                .offset(y: 22)
        }
        .padding(.bottom, 22)
    }

    // MARK: - 결과

    private var rankTitle: some View {
        VStack(spacing: 6) {
            Text("그대는")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))

            Text(result.rank.title)
                .font(.system(size: 52, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }

    private var headline: some View {
        VStack(spacing: 10) {
            Text(result.rank.headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(result.rank.tint)

            Text(result.rank.detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
                .lineSpacing(3)
        }
        .multilineTextAlignment(.center)
    }

    private var reasonChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(result.reasons, id: \.self) { reason in
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - 하단

    private var continueButton: some View {
        VStack(spacing: 14) {
            Text("재미로 보는 관상입니다")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))

            Button(action: onContinue) {
                Text("라벨링하러 가기")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.black)
            }
        }
    }
}
