//
//  CaptureOrientation.swift
//  FaceDatasetCollector
//

import ARKit
import ImageIO
import UIKit

/// 저장할 이미지를 어느 방향으로 세울지 정하는 설정.
///
/// 전면 카메라의 센서 방향/거울 반전 규약은 문서만 보고 확정하기 어렵다.
/// 상수를 손으로 박아 두면 한 번 틀렸을 때 옆으로 누운 데이터가 통째로 쌓인다.
/// 그래서 기본값은 ARKit이 **미리보기를 그릴 때 쓰는 변환**에서 방향을 역산하는 `.automatic`이다.
/// 화면에서 똑바로 보이는 그림이 그대로 저장되므로 규약을 추측할 필요가 없어진다.
enum CaptureOrientation: Hashable, Sendable {

    /// 매 촬영마다 ARKit의 표시 변환에서 계산한다.
    case automatic

    /// 고정 EXIF 방향. 자동이 어긋나는 기기에서 손으로 덮어쓸 때만 쓴다.
    case fixed(CGImagePropertyOrientation)

    /// 이 프레임에 실제로 적용할 EXIF 방향.
    func resolved(for frame: ARFrame) -> CGImagePropertyOrientation {
        switch self {
        case .fixed(let orientation): orientation
        case .automatic: Self.derived(from: frame)
        }
    }

    /// ARKit의 표시 변환에서 90° 단위 회전과 좌우반전을 되읽어 EXIF 방향으로 바꾼다.
    ///
    /// `displayTransform(for:viewportSize:)`는 ARKit이 카메라 영상을 화면에 얹을 때 쓰는 바로 그
    /// 변환이다. 여기서 뽑은 방향으로 저장하면 미리보기와 저장본이 항상 같은 그림이 된다.
    /// 뷰포트를 원본(가로)을 세로로 눕힌 크기로 주면 비율이 같아, 확대·잘라내기 성분 없이
    /// 회전·반전만 남는다.
    private static func derived(from frame: ARFrame) -> CGImagePropertyOrientation {
        let resolution = frame.camera.imageResolution
        let transform = frame.displayTransform(
            for: .portrait,  // 이 앱은 세로 고정이다. (Info.plist의 지원 방향도 세로 하나뿐)
            viewportSize: CGSize(width: resolution.height, height: resolution.width)
        )

        // 좌우반전을 먼저 걷어내면 남는 건 순수 회전이라 각도를 바로 읽을 수 있다.
        let isMirrored = transform.a * transform.d - transform.b * transform.c < 0
        let rotation = isMirrored
            ? CGAffineTransform(scaleX: -1, y: 1).concatenating(transform)
            : transform

        // 표시 좌표계는 y가 아래로 향하므로 시계방향이 양의 각도다.
        // 남은 성분은 90°의 배수라 반올림하면 정확히 떨어진다.
        let quarterTurns = Int((atan2(rotation.b, rotation.a) / (.pi / 2)).rounded())
        let index = (quarterTurns % 4 + 4) % 4

        return isMirrored
            ? [.upMirrored, .rightMirrored, .downMirrored, .leftMirrored][index]
            : [.up, .right, .down, .left][index]
    }
}

// MARK: - 저장

extension CaptureOrientation {

    /// `UserDefaults`에 남기는 값.
    ///
    /// 저장된 적이 없으면 `integer(forKey:)`가 0을 주고, EXIF 방향에는 0이 없다.
    /// 그래서 0을 `.automatic`으로 두면 별도의 "설정한 적 있음" 플래그가 필요 없다.
    var storedValue: Int {
        switch self {
        case .automatic: 0
        case .fixed(let orientation): Int(orientation.rawValue)
        }
    }

    init(storedValue: Int) {
        guard
            let raw = UInt32(exactly: storedValue),
            let orientation = CGImagePropertyOrientation(rawValue: raw)
        else {
            self = .automatic
            return
        }
        self = .fixed(orientation)
    }
}
