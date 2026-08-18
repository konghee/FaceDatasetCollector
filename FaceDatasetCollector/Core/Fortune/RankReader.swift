//
//  RankReader.swift
//  FaceDatasetCollector
//

import Foundation

/// 판정 결과. 신분과 함께 "왜 그렇게 나왔는지"를 들고 있다.
nonisolated struct RankResult: Sendable {
    let rank: Rank
    let metrics: FaceMetrics

    /// 결과 화면에 보여 줄 근거. ("너르고 시원한 얼굴")
    let reasons: [String]
}

/// 얼굴 치수와 피험자 구분자로 조선시대 신분을 고른다.
///
/// ## ARKit으로는 사람을 세밀하게 가를 수 없다
/// 얼굴 하나로 열두 갈래를 나누려 했지만 실패했다. 원인은 코드가 아니라 ARKit이 주는
/// 데이터의 성격에 있다.
///
/// Face ID는 적외선 점 3만 개로 정밀한 깊이 지도를 만들지만, 그 데이터는 Secure Enclave
/// 밖으로 나오지 않는다. 앱이 받는 `ARFaceGeometry`는 전혀 다른 물건으로, **일반화된 얼굴
/// 모델 하나를 표정 계수로 변형해 맞춘 것**이다. 목적이 표정 추적이라 개인 골격 차이는
/// 오히려 정규화되어 지워진다. 서로 다른 두 사람의 턱 폭 비율이 0.909와 0.908로 같게 나온
/// 것이 그 증거다. 버그가 아니라 설계 의도다.
///
/// 남은 절대 크기마저 측정 편차가 사람 간 차이만큼 컸다. 같은 사람의 동공간거리가
/// 61.5~63.7mm를 오갔는데, 다른 사람과의 차이는 3.0mm였다.
///
/// ## 그래서 두 단계로 나눈다
/// 1. **계열**은 얼굴로 정한다. 얼굴 너비는 편차가 ±1.2mm로 가장 안정적이었고, 두 갈래
///    정도는 신뢰할 수 있다.
/// 2. **그 안의 여섯 중 누구인지**는 피험자 구분자로 정한다. 얼굴로는 여기까지 나눌 수
///    없다는 것을 인정한 결과다.
///
/// 한번 나온 결과는 피험자별로 기억한다. 측정값이 경계선 근처에서 흔들려도 같은 사람에게는
/// 늘 같은 신분이 나와야 재미가 성립하기 때문이다.
nonisolated enum RankReader {

    /// 계열을 가르는 얼굴 너비(mm).
    ///
    /// 실측한 두 사람이 150.7과 152.5였으므로 그 한가운데에 둔다. 어느 쪽 값도 경계에
    /// 붙어 있지 않아야 흔들림에 견딘다. 사람이 모이면 중앙값으로 다시 맞춰야 한다.
    private static let faceWidthEdge: Float = 151.5

    /// 계열마다 여섯 신분. 순서에 의미는 없고 구분자 해시로 고른다.
    private static let families: [[Rank]] = [
        // 작고 단정한 얼굴
        [.primeMinister, .scholar, .inspector, .physician, .entertainer, .servant],
        // 너르고 큰 얼굴
        [.king, .general, .tavernKeeper, .merchant, .slaveHunter, .bandit],
    ]

    /// 지금 이 치수라면 어떤 신분인지 계산만 한다. **아무것도 저장하지 않는다.**
    ///
    /// 계측기처럼 매 프레임 불리는 자리에서 쓴다. 여기서 결과를 저장하면 얼굴이 잡히는
    /// 첫 프레임에 신분이 확정돼 버린다. 그 프레임은 ARKit이 얼굴을 막 잡기 시작한,
    /// 값이 가장 튀는 순간이다.
    static func preview(_ metrics: FaceMetrics, subjectID: String) -> RankResult {
        let family = metrics.widthMM >= faceWidthEdge ? 1 : 0
        let rank = RankMemory.rank(for: subjectID) ?? pick(family: family, subjectID: subjectID)

        return RankResult(
            rank: rank,
            metrics: metrics,
            reasons: reasons(family: family, metrics: metrics)
        )
    }

    /// 이 사람의 신분을 확정하고 기억한다. **셔터를 누른 순간에만 부른다.**
    ///
    /// 한 번 정해진 뒤에는 측정값이 흔들려도 바뀌지 않는다. 같은 사람에게 늘 같은 신분이
    /// 나와야 재미가 성립하기 때문이다.
    static func decide(_ metrics: FaceMetrics, subjectID: String) -> RankResult {
        let family = metrics.widthMM >= faceWidthEdge ? 1 : 0

        let rank: Rank
        if let remembered = RankMemory.rank(for: subjectID) {
            rank = remembered
        } else {
            rank = pick(family: family, subjectID: subjectID)
            RankMemory.remember(rank, for: subjectID)
        }

        return RankResult(
            rank: rank,
            metrics: metrics,
            reasons: reasons(family: family, metrics: metrics)
        )
    }

    /// 촬영한 표본에서 확정한다. 모아 둔 치수가 없을 때만 쓰는 대비책이다.
    static func decide(_ sample: PendingSample, subjectID: String) -> RankResult? {
        FaceMetrics(
            vertices: sample.vertices,
            interpupillaryDistanceMM: sample.geometry.interpupillaryDistance
        ).map { decide($0, subjectID: subjectID) }
    }

    private static func pick(family: Int, subjectID: String) -> Rank {
        let candidates = families[family]
        return candidates[Int(stableHash(subjectID) % UInt32(candidates.count))]
    }

    /// FNV-1a. Swift 기본 `hashValue`는 실행할 때마다 값이 달라져서 쓸 수 없다.
    /// 같은 구분자에는 언제나 같은 신분이 나와야 한다.
    private static func stableHash(_ text: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        return hash
    }

    /// 실제로 잰 값만 말한다. 계열은 얼굴로 갈랐으니 근거가 되지만,
    /// 그 안에서 누구인지는 얼굴이 정한 게 아니므로 얼굴 탓으로 돌리지 않는다.
    private static func reasons(family: Int, metrics: FaceMetrics) -> [String] {
        [
            family == 1 ? "너르고 시원한 얼굴" : "작고 단정한 얼굴",
            String(format: "미간 %.0fmm", metrics.ipdMM),
        ]
    }
}

// MARK: - 기억

/// 피험자별로 한번 나온 신분을 기억한다.
///
/// 측정값이 경계선 근처에서 흔들려도 같은 사람에게는 늘 같은 신분이 나와야 한다.
/// 실제로 같은 사람이 2분 사이에 장군과 암행어사를, 다시 영의정과 상인을 오간 적이 있다.
///
/// - Note: 다른 사람에게 같은 구분자를 쓰면 앞사람의 신분이 그대로 나온다.
///   화면의 `다음 사람` 버튼으로 구분자를 올려 가며 쓰는 것을 전제한다.
nonisolated enum RankMemory {

    private static let key = "fortune.rankBySubject"

    static func rank(for subjectID: String) -> Rank? {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: String]
        return stored?[subjectID].flatMap(Rank.init(rawValue:))
    }

    static func remember(_ rank: Rank, for subjectID: String) {
        var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        stored[subjectID] = rank.rawValue
        UserDefaults.standard.set(stored, forKey: key)
    }

    /// 기억을 지운다. 기준값을 바꿔 가며 시험할 때 쓴다.
    static func forgetAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
