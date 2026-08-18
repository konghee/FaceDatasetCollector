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

    /// 조선시대 인물 그림의 빈 얼굴 자리에 촬영한 얼굴을 끼워 넣는다.
    ///
    /// 관광지 얼굴 끼워넣기 포토존과 같은 방식이다. 그림 파일이 없으면 얼굴만 원형으로 보여 준다.
    @ViewBuilder
    private var portrait: some View {
        if let art = UIImage(named: result.rank.imageName) {
            Image(uiImage: art)
                .resizable()
                // 이미지 자체의 비율로 뷰를 잡아야 아래 overlay 좌표계가 그림과 정확히 겹친다.
                .aspectRatio(art.size, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        faceInHole(in: proxy.size)
                    }
                }
                .frame(maxHeight: 340)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        } else {
            faceOnly
        }
    }

    /// 그림 크기에 맞춰 얼굴 타원을 배치한다.
    @ViewBuilder
    private func faceInHole(in size: CGSize) -> some View {
        let hole = result.rank.faceHole
        let frame = CGRect(
            x: hole.minX * size.width,
            y: hole.minY * size.height,
            width: hole.width * size.width,
            height: hole.height * size.height
        )

        if let face = UIImage(data: sample.faceCrop ?? sample.fullFrame) {
            Color.clear
                .frame(width: frame.width, height: frame.height)
                .overlay {
                    Image(uiImage: face)
                        .resizable()
                        .scaledToFill()
                        // 얼굴 크롭은 얼굴 둘레를 1.5배로 넉넉히 잘라 둔 것이라,
                        // 그대로 넣으면 이목구비가 타원 안에서 작게 뜬다. 그만큼 당겨 준다.
                        .scaleEffect(1.45)
                }
                .clipShape(Ellipse())
                .position(x: frame.midX, y: frame.midY)
        }
    }

    private var faceOnly: some View {
        ZStack {
            Circle().fill(.black.opacity(0.35))

            if let image = UIImage(data: sample.faceCrop ?? sample.fullFrame) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 210, height: 210)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(result.rank.tint, lineWidth: 4) }
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
