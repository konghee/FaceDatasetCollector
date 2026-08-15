//
//  RankReader.swift
//  FaceDatasetCollector
//

import Foundation

/// 판정 결과. 신분과 함께 "왜 그렇게 나왔는지"를 들고 있다.
nonisolated struct RankResult: Sendable {
    let rank: Rank
    let metrics: FaceMetrics

    /// 결과 화면에 보여 줄 근거. ("시원하게 트인 미간", "너른 얼굴")
    let reasons: [String]
}

/// 얼굴 치수에서 조선시대 신분을 고른다.
///
/// ## 왜 동공간거리와 얼굴 너비인가
/// 처음에는 세로 비율·턱 폭 같은 **비율**로 판정했는데 전부 실패했다. ARKit 얼굴 메시는
/// 표정 추적용이라 정해진 형태를 거의 균일하게 확대·축소해 맞춘다. 그래서 비율은 누구나
/// 비슷하고 **크기만 사람마다 다르다.** 실측이 그대로 보여 줬다.
///
/// | 지표 | 사람 A | 사람 B | 차이 |
/// |---|---|---|---|
/// | 동공간거리 | 60.6mm | 63.6mm | 3.0mm ✅ |
/// | 얼굴 너비 | 153.3mm | 150.8mm | 2.5mm ✅ |
/// | 턱 폭 비율 | 0.909 | 0.908 | 0.001 ❌ |
/// | 코 돌출 | 0.171 | 0.179 | 0.008 ❌ |
///
/// 턱 폭은 **서로 다른 사람인데 소수점 셋째 자리까지 같았다.** 비율 계열은 전부 버렸다.
///
/// 같은 사람을 세 번 재면 너비 150.6 / 151.3 / 150.8, 동공간거리 62.7 / 63.7 / 63.6으로
/// ±0.5mm 안에서 반복된다. 사람 간 차이(2~3mm)가 이보다 크므로 판정 근거로 쓸 수 있다.
///
/// - Important: 아직 **두 사람으로 맞춘 기준선이다.** 사람이 모일수록 한쪽으로 쏠리는지
///   확인하고 경계를 옮겨야 한다. ([BACKLOG](../../../docs/BACKLOG.md) 8-1)
nonisolated enum RankReader {

    /// 동공간거리(mm) 경계 셋 → 네 칸. 성인 평균은 63mm 근처다.
    ///
    /// 62.0은 실측한 사람이 62.7~63.7을 오가서, 경계에 걸터앉지 않도록 아래로 내려 둔 값이다.
    private static let eyeSpanEdges: [Float] = [60.0, 62.0, 65.0]

    /// 얼굴 너비(mm) 경계 둘 → 세 칸.
    private static let faceWidthEdges: [Float] = [148.0, 152.5]

    /// 미간(가로) × 얼굴 크기(세로). 네 칸 × 세 칸 = 열두 신분이 빠짐없이 채워진다.
    ///
    /// 미간이 넓고 얼굴이 클수록 위쪽 신분에 가깝게 두었다. 관상에서 시원한 미간과 너른
    /// 얼굴을 후덕함으로 읽는 통념을 그대로 따른 것이고, 근거라기보다 재미를 위한 배치다.
    private static let table: [[Rank]] = [
        //  작은 얼굴        보통 얼굴          너른 얼굴
        [.servant, .inspector, .bandit],        // 미간 아주 좁음
        [.scholar, .merchant, .slaveHunter],    // 미간 좁음
        [.physician, .primeMinister, .general], // 미간 넓음
        [.entertainer, .tavernKeeper, .king],   // 미간 아주 넓음
    ]

    static func read(_ metrics: FaceMetrics) -> RankResult {
        let eyeSpan = bucket(metrics.ipdMM, edges: eyeSpanEdges)
        let faceWidth = bucket(metrics.widthMM, edges: faceWidthEdges)

        return RankResult(
            rank: table[eyeSpan][faceWidth],
            metrics: metrics,
            reasons: reasons(eyeSpan: eyeSpan, faceWidth: faceWidth)
        )
    }

    /// 촬영한 표본에서 바로 판정한다. 얼굴을 못 잡았으면 `nil`.
    static func read(_ sample: PendingSample) -> RankResult? {
        FaceMetrics(
            vertices: sample.vertices,
            interpupillaryDistanceMM: sample.geometry.interpupillaryDistance
        ).map(read)
    }

    /// 값이 어느 칸에 드는지. 경계를 넘을 때마다 한 칸씩 오른다.
    private static func bucket(_ value: Float, edges: [Float]) -> Int {
        edges.reduce(0) { $0 + (value >= $1 ? 1 : 0) }
    }

    private static func reasons(eyeSpan: Int, faceWidth: Int) -> [String] {
        [
            ["또렷하게 모인 눈", "단정한 미간", "시원하게 트인 미간", "훤하게 벌어진 미간"][eyeSpan],
            ["또렷하고 작은 얼굴", "균형 잡힌 얼굴", "너르고 시원한 얼굴"][faceWidth],
        ]
    }
}
