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
    /// 실측: 사람 A 150.1~151.3, 사람 B 152.5 근처. 사람이 모이면 다시 맞춰야 한다.
    private static let faceWidthEdge: Float = 152.0

    /// 계열마다 여섯 신분. 순서에 의미는 없고 구분자 해시로 고른다.
    private static let families: [[Rank]] = [
        // 작고 단정한 얼굴
        [.primeMinister, .scholar, .inspector, .physician, .entertainer, .servant],
        // 너르고 큰 얼굴
        [.king, .general, .tavernKeeper, .merchant, .slaveHunter, .bandit],
    ]

    static func read(_ metrics: FaceMetrics, subjectID: String) -> RankResult {
        let family = metrics.widthMM >= faceWidthEdge ? 1 : 0
        let candidates = families[family]

        // 이미 이 사람에게 나온 적이 있으면 그대로 쓴다.
        let rank = RankMemory.rank(for: subjectID)
            ?? candidates[Int(stableHash(subjectID) % UInt32(candidates.count))]

        RankMemory.remember(rank, for: subjectID)

        return RankResult(
            rank: rank,
            metrics: metrics,
            reasons: reasons(family: family, metrics: metrics)
        )
    }

    /// 촬영한 표본에서 바로 판정한다. 얼굴을 못 잡았으면 `nil`.
    static func read(_ sample: PendingSample, subjectID: String) -> RankResult? {
        FaceMetrics(
            vertices: sample.vertices,
            interpupillaryDistanceMM: sample.geometry.interpupillaryDistance
        ).map { read($0, subjectID: subjectID) }
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
