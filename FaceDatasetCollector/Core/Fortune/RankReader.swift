//
//  RankReader.swift
//  FaceDatasetCollector
//

import Foundation

/// 판정 결과. 신분과 함께 "왜 그렇게 나왔는지"를 들고 있다.
nonisolated struct RankResult: Sendable {
    let rank: JoseonRank
    let metrics: FaceMetrics

    /// 결과 화면에 보여 줄 근거. ("갸름한 얼굴형", "시원한 미간")
    let reasons: [String]
}

/// 얼굴 비율에서 조선시대 신분을 고른다.
///
/// ## 구조
/// 12명을 한 번에 고르지 않고 두 단계로 나눈다.
///
/// 1. **얼굴형(세로 비율) × 턱(아래 폭)** 으로 4분면을 만든다 → 성격이 비슷한 3명씩 묶임
/// 2. 그 안에서 **미간 너비**로 셋 중 하나를 고른다
///
/// 최근접 이웃 같은 방식 대신 이렇게 짠 이유는 **결과를 설명할 수 있어야 하기 때문**이다.
/// 참여자가 "왜 이게 나왔냐"고 물으면 답할 수 있어야 재미가 산다.
///
/// - Important: 아래 기준값은 **실측 전의 초기 추정치**다. 실제로 사람들을 찍어 보면
///   한쪽으로 쏠릴 수 있다. 결과 화면 하단의 수치를 모아 중앙값으로 다시 맞출 것.
///   ([BACKLOG](../../../docs/BACKLOG.md) 참고)
nonisolated enum RankReader {

    /// 4분면을 가르는 기준값. 사람들의 중앙값에 가깝게 맞춰야 결과가 골고루 나온다.
    private enum Threshold {
        /// 세로 비율. 이보다 크면 긴 얼굴.
        static let aspectRatio: Float = 0.82

        /// 턱 폭 비율. 이보다 크면 턱이 발달한 쪽.
        static let jawRatio: Float = 0.86

        /// 미간. 3등분 경계 두 개.
        static let eyeSpacingNarrow: Float = 0.40
        static let eyeSpacingWide: Float = 0.45
    }

    static func read(_ metrics: FaceMetrics) -> RankResult {
        let isLongFace = metrics.aspectRatio >= Threshold.aspectRatio
        let isStrongJaw = metrics.jawRatio >= Threshold.jawRatio

        // 분면마다 성격이 통하는 셋을 둔다. 순서는 미간이 좁은 쪽 → 넓은 쪽.
        let candidates: [JoseonRank] = switch (isLongFace, isStrongJaw) {
        case (true, true): [.slaveHunter, .general, .bandit]        // 길고 각진 — 기개
        case (true, false): [.scholar, .inspector, .physician]      // 길고 갸름 — 지성
        case (false, true): [.primeMinister, .king, .tavernKeeper]  // 둥글고 각진 — 무게
        case (false, false): [.merchant, .entertainer, .servant]    // 둥글고 갸름 — 재치
        }

        let index = if metrics.eyeSpacing < Threshold.eyeSpacingNarrow {
            0
        } else if metrics.eyeSpacing < Threshold.eyeSpacingWide {
            1
        } else {
            2
        }

        return RankResult(
            rank: candidates[index],
            metrics: metrics,
            reasons: reasons(for: metrics, isLongFace: isLongFace, isStrongJaw: isStrongJaw)
        )
    }

    /// 촬영한 표본에서 바로 판정한다. 얼굴을 못 잡았으면 `nil`.
    static func read(_ sample: PendingSample) -> RankResult? {
        FaceMetrics(
            vertices: sample.vertices,
            interpupillaryDistanceMM: sample.geometry.interpupillaryDistance
        ).map(read)
    }

    private static func reasons(
        for metrics: FaceMetrics,
        isLongFace: Bool,
        isStrongJaw: Bool
    ) -> [String] {
        var reasons = [
            isLongFace ? "길고 갸름한 얼굴형" : "둥글고 복스러운 얼굴형",
            isStrongJaw ? "단단한 턱선" : "부드럽게 좁아지는 턱선",
        ]

        if metrics.eyeSpacing >= Threshold.eyeSpacingWide {
            reasons.append("시원하게 트인 미간")
        } else if metrics.eyeSpacing < Threshold.eyeSpacingNarrow {
            reasons.append("또렷하게 모인 눈")
        }

        if metrics.depthRatio >= 0.50 {
            reasons.append("입체적인 이목구비")
        }

        return reasons
    }
}
