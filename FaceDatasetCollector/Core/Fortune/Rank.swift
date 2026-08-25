//
// Rank.swift
//  FaceDatasetCollector
//

import SwiftUI

/// 촬영 직후 참여자에게 재미로 보여 주는 조선시대 신분.
///
/// ## 문구 원칙
/// **12개 결과가 전부 칭찬이거나 웃겨야 한다.** 노비·도적처럼 신분제에서 아래에 놓였던
/// 자리도 여기서는 놀림거리가 아니라 웃음이 되어야 한다. 부스에서 처음 만난 사람에게
/// 얼굴을 근거로 "너는 아래다"라고 말하는 화면이 되면 그 순간 재미 요소가 아니라 사고다.
///
/// 새 신분을 추가하거나 문구를 고칠 때 이 기준을 먼저 통과시킬 것.
enum Rank: String, CaseIterable, Identifiable, Sendable {
    case king           // 임금
    case primeMinister  // 영의정
    case inspector      // 암행어사
    case general        // 장군
    case tavernKeeper   // 주모
    case merchant       // 상인
    case entertainer    // 광대
    case scholar        // 유생
    case physician      // 의녀
    case servant        // 노비
    case slaveHunter    // 추노꾼
    case bandit         // 도적

    var id: String { rawValue }

    var title: String {
        switch self {
        case .king: "임금"
        case .primeMinister: "영의정"
        case .inspector: "암행어사"
        case .general: "장군"
        case .tavernKeeper: "주모"
        case .merchant: "상인"
        case .entertainer: "광대"
        case .scholar: "유생"
        case .physician: "의녀"
        case .servant: "노비"
        case .slaveHunter: "추노꾼"
        case .bandit: "도적"
        }
    }

    /// 결과 화면에 크게 뜨는 한 줄.
    var headline: String {
        switch self {
        case .king: "그대가 왕이 될 상이오"
        case .primeMinister: "만조백관이 그대 말을 기다리오"
        case .inspector: "품 안에 마패가 있는 얼굴이오"
        case .general: "적장이 먼저 달아날 기세요"
        case .tavernKeeper: "국밥 한 그릇에 온 마을이 모이오"
        case .merchant: "손해 보는 장사는 안 할 얼굴이오"
        case .entertainer: "그대가 지나면 저잣거리가 웃음바다요"
        case .scholar: "먹 냄새가 여기까지 나는구려"
        case .physician: "그대 손이 닿으면 병이 달아나오"
        case .servant: "묵묵히 집안을 일으킬 상이오"
        case .slaveHunter: "한번 쫓으면 놓치는 법이 없구려"
        case .bandit: "의적일지도 모르오. 아마도."
        }
    }

    /// 헤드라인 아래 붙는 설명.
    var detail: String {
        switch self {
        case .king: "타고난 무게감이 있소. 가만히 있어도 사람이 모이는 상이오."
        case .primeMinister: "머리와 인망을 다 갖췄소. 왕도 그대 눈치를 볼 것이오."
        case .inspector: "조용히 보고 정확히 짚는 눈이오. 숨길 게 있는 자는 조심하시오."
        case .general: "물러설 줄 모르는 기개가 얼굴에 그대로 있소."
        case .tavernKeeper: "누구든 편하게 만드는 재주가 있소. 이 시대 최고의 사교술이오."
        case .merchant: "셈이 빠르고 눈치가 밝소. 곳간 걱정은 없겠구려."
        case .entertainer: "표정 하나로 판을 뒤집는 재주요. 아무나 가질 수 없소."
        case .scholar: "생각이 깊고 말을 아끼오. 언젠가 크게 쓰일 상이오."
        case .physician: "남의 아픔을 먼저 보는 얼굴이오. 귀한 재주요."
        case .servant: "성실함이 무기요. 이 시대 모든 집이 그대를 탐낼 것이오."
        case .slaveHunter: "집념이 대단하오. 그 끈기면 무엇을 해도 되겠소."
        case .bandit: "규칙에 매이지 않는 얼굴이오. 크게 될 상이라는 뜻이기도 하오."
        }
    }

    /// `Resources/`에 든 조선시대 인물 그림. 얼굴 자리가 흰 타원으로 비어 있다.
    var imageName: String { "rank-\(rawValue)" }

    /// 그림 안에서 얼굴 타원이 차지하는 자리. 이미지 크기 대비 비율(0~1)이다.
    ///
    /// 원본 시트에서 흰 타원을 자동으로 검출해 뽑은 값이라 눈대중이 아니다.
    /// 그림을 교체하면 이 값도 다시 뽑아야 한다.
    var faceHole: CGRect {
        switch self {
        case .king: CGRect(x: 0.3750, y: 0.1513, width: 0.2500, height: 0.2174)
        case .primeMinister: CGRect(x: 0.3750, y: 0.1513, width: 0.2500, height: 0.2174)
        case .inspector: CGRect(x: 0.3750, y: 0.1513, width: 0.2500, height: 0.2174)
        case .general: CGRect(x: 0.5357, y: 0.1513, width: 0.2500, height: 0.2174)
        case .tavernKeeper: CGRect(x: 0.3750, y: 0.1513, width: 0.2500, height: 0.2174)
        case .merchant: CGRect(x: 0.4643, y: 0.1513, width: 0.2500, height: 0.2174)
        case .scholar: CGRect(x: 0.3750, y: 0.1513, width: 0.2500, height: 0.2174)
        case .slaveHunter: CGRect(x: 0.1976, y: 0.1513, width: 0.2500, height: 0.2174)
        case .bandit: CGRect(x: 0.4583, y: 0.0712, width: 0.2500, height: 0.2174)
        case .physician: CGRect(x: 0.3750, y: 0.1513, width: 0.2500, height: 0.2174)
        case .entertainer: CGRect(x: 0.2212, y: 0.1513, width: 0.2500, height: 0.2174)
        case .servant: CGRect(x: 0.3750, y: 0.1513, width: 0.2500, height: 0.2174)
        }
    }

    var symbol: String {
        switch self {
        case .king: "crown.fill"
        case .primeMinister: "text.document.fill"
        case .inspector: "magnifyingglass"
        case .general: "shield.lefthalf.filled"
        case .tavernKeeper: "takeoutbag.and.cup.and.straw.fill"
        case .merchant: "scalemass.fill"
        case .entertainer: "theatermasks.fill"
        case .scholar: "book.closed.fill"
        case .physician: "leaf.fill"
        case .servant: "hands.and.sparkles.fill"
        case .slaveHunter: "figure.run"
        case .bandit: "eye.trianglebadge.exclamationmark.fill"
        }
    }

    var tint: Color {
        switch self {
        case .king: Color(red: 0.85, green: 0.65, blue: 0.13)
        case .primeMinister: Color(red: 0.55, green: 0.36, blue: 0.64)
        case .inspector: Color(red: 0.20, green: 0.45, blue: 0.72)
        case .general: Color(red: 0.72, green: 0.25, blue: 0.22)
        case .tavernKeeper: Color(red: 0.87, green: 0.47, blue: 0.20)
        case .merchant: Color(red: 0.24, green: 0.55, blue: 0.42)
        case .entertainer: Color(red: 0.83, green: 0.33, blue: 0.51)
        case .scholar: Color(red: 0.31, green: 0.42, blue: 0.55)
        case .physician: Color(red: 0.36, green: 0.60, blue: 0.35)
        case .servant: Color(red: 0.50, green: 0.45, blue: 0.38)
        case .slaveHunter: Color(red: 0.45, green: 0.35, blue: 0.28)
        case .bandit: Color(red: 0.35, green: 0.35, blue: 0.40)
        }
    }
}
