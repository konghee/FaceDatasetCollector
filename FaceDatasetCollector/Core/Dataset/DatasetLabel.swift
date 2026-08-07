//
//  DatasetLabel.swift
//  FaceDatasetCollector
//

import Foundation

/// 학습 데이터에 붙이는 정답 라벨의 공통 계약.
///
/// `rawValue`가 그대로 **폴더 이름**이 된다(`images/eye/phoenix/...`).
/// Create ML 이미지 분류기가 "폴더명 = 클래스명" 규약을 쓰기 때문에,
/// 내보낸 폴더를 그대로 끌어다 놓으면 학습이 된다.
protocol DatasetLabel: CaseIterable, Hashable, Identifiable, Sendable {

    /// 데이터셋 안에서 이 라벨 축을 구분하는 이름. (= 상위 폴더명)
    static var axisName: String { get }

    /// 화면에 표시할 축 이름.
    static var axisTitle: String { get }

    /// 폴더·CSV에 기록할 값.
    var folderName: String { get }

    /// 버튼에 표시할 이름.
    var pickerTitle: String { get }
}

// 이 앱은 기본 액터 격리가 MainActor라, 아래를 그대로 두면 `Sendable` 요구와 충돌한다.
// 라벨은 상태 없는 값 타입이므로 전부 nonisolated로 두어 저장 액터에서도 쓸 수 있게 한다.
extension DatasetLabel where Self: RawRepresentable, RawValue == String {
    nonisolated var folderName: String { rawValue }
    nonisolated var id: String { rawValue }
}

// MARK: - 눈 (9종)

/// 눈 모양 라벨.
///
/// - Important: rawValue는 본 앱(Vultus)의 `EyeShape.EyeType`과 **반드시 같아야 한다.**
///   여기서 만든 폴더 이름이 곧 CoreML 모델의 출력 레이블이 되고,
///   본 앱은 그 레이블 문자열로 `EyeShape.EyeType(label:)`을 만들기 때문이다.
///   본 앱에서 케이스를 추가하면 여기에도 같은 rawValue로 추가한다.
enum EyeLabel: String, DatasetLabel {
    case phoenix
    case dragon
    case crane
    case tiger
    case lion
    case ox
    case deer
    case turtle
    case duck

    nonisolated static var axisName: String { "eye" }
    nonisolated static var axisTitle: String { "눈" }

    nonisolated var pickerTitle: String {
        switch self {
        case .phoenix: "봉황눈"
        case .dragon:  "용눈"
        case .crane:   "학눈"
        case .tiger:   "호랑이눈"
        case .lion:    "사자눈"
        case .ox:      "소눈"
        case .deer:    "사슴눈"
        case .turtle:  "거북이눈"
        case .duck:    "원앙눈"
        }
    }
}

// MARK: - 얼굴형 (5종)

/// 얼굴형 라벨. rawValue는 본 앱(Vultus)의 `FaceShape`과 같아야 한다.
enum FaceShapeLabel: String, DatasetLabel {
    case invertedTriangle
    case triangle
    case rhombus
    case longRectangle
    case round

    nonisolated static var axisName: String { "faceShape" }
    nonisolated static var axisTitle: String { "얼굴형" }

    nonisolated var pickerTitle: String {
        switch self {
        case .invertedTriangle: "역삼각형"
        case .triangle:         "삼각형"
        case .rhombus:          "마름모형"
        case .longRectangle:    "긴 네모형"
        case .round:            "둥근형"
        }
    }
}
