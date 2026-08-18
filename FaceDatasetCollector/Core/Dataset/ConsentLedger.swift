//
//  ConsentLedger.swift
//  FaceDatasetCollector
//

import Foundation

/// 피험자별 촬영 동의 기록.
///
/// 동의를 앱 실행 단위로 기억하면 다음 사람이 앞사람의 동의를 물려받는다. 부스에서는
/// 한 사람이 여러 장을 찍고 곧바로 다음 사람으로 넘어가므로, 구분자별로 남겨야
/// "이 사람에게 받았는가"를 물을 수 있다.
///
/// - Note: 같은 구분자를 다른 사람에게 다시 쓰면 앞사람의 동의가 그대로 따라온다.
///   화면의 `다음 사람` 버튼으로 구분자를 올려 가며 쓰는 것을 전제한다. `RankMemory`와 같다.
nonisolated enum ConsentLedger {

    private static let key = "dataset.consentBySubject"

    /// 동의를 받은 시각. 받은 적이 없으면 `nil`.
    static func consentedAt(_ subjectID: String) -> Date? {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Date]
        return stored?[subjectID]
    }

    static func hasConsented(_ subjectID: String) -> Bool {
        consentedAt(subjectID) != nil
    }

    /// 동의를 남긴다. 언제 받았는지까지 남겨야 나중에 "받았다"는 말의 근거가 된다.
    static func record(_ subjectID: String, at date: Date = Date()) {
        var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Date] ?? [:]
        stored[subjectID] = date
        UserDefaults.standard.set(stored, forKey: key)
    }
}
