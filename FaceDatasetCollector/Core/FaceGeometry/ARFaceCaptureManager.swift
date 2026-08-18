//
//  ARFaceCaptureManager.swift
//  FaceDatasetCollector
//

import ARKit
import Foundation

/// TrueDepth 얼굴 추적 세션을 관리하고 최신 `FaceAnchorSnapshot`을 공개한다.
///
/// 기존 `CameraManager`(AVCaptureSession)와 **동시에 실행할 수 없다.**
/// `ARFaceTrackingConfiguration`이 전면 카메라를 독점하기 때문에,
/// 한쪽을 시작하기 전에 다른 쪽을 반드시 정지시켜야 한다.
@Observable
@MainActor
final class ARFaceCaptureManager {

    /// 얼굴 추적 미지원 기기(TrueDepth 없음) 또는 시뮬레이터 여부.
    let isSupported = ARFaceTrackingConfiguration.isSupported

    private(set) var snapshot: FaceAnchorSnapshot?
    private(set) var isRunning = false

    let session = ARSession()
    private var proxy: ARSessionProxy?

    var isFaceTracked: Bool { snapshot != nil }

    /// 매 프레임 얼굴 값을 흘려보낸다. 프레임을 모아 평균을 내려는 쪽에서 쓴다.
    ///
    /// `snapshot`은 최신 한 장만 남기므로, 여러 프레임을 누적하려면 이 통로가 필요하다.
    var onSnapshot: (@MainActor (FaceAnchorSnapshot?) -> Void)?

    func start() {
        guard isSupported, !isRunning else { return }

        let proxy = ARSessionProxy { [weak self] snapshot in
            self?.snapshot = snapshot
            self?.onSnapshot?(snapshot)
        }
        self.proxy = proxy
        session.delegate = proxy
        // 콜백을 메인 큐로 고정해야 아래 `assumeIsolated`가 성립한다.
        session.delegateQueue = .main

        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        // 관상 분석은 얼굴 기하만 쓰므로 조명 추정은 꺼서 부하를 줄인다.
        configuration.isLightEstimationEnabled = false

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        session.pause()
        session.delegate = nil
        proxy = nil
        snapshot = nil
        isRunning = false
    }

    /// 촬영 시점의 얼굴 상태를 값으로 고정해 반환한다.
    ///
    /// 라이브 `snapshot`은 다음 프레임에 교체되므로, 분석에 넘길 값은 이 메서드로 확보한다.
    func capture() -> FaceAnchorSnapshot? {
        guard
            let frame = session.currentFrame,
            let anchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first,
            anchor.isTracked
        else { return nil }

        return FaceAnchorSnapshot(anchor: anchor, camera: frame.camera)
    }
}

// MARK: - ARSessionProxy

/// `ARSessionDelegate`는 `@MainActor` 격리를 모르는 프로토콜이라
/// 델리게이트 수신을 별도 객체로 분리하고 메인 액터로 넘겨준다.
private final class ARSessionProxy: NSObject, ARSessionDelegate {
    private let onUpdate: @MainActor (FaceAnchorSnapshot?) -> Void

    init(onUpdate: @escaping @MainActor (FaceAnchorSnapshot?) -> Void) {
        self.onUpdate = onUpdate
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let anchor = frame.anchors.compactMap { $0 as? ARFaceAnchor }.first
        let snapshot = anchor.flatMap {
            $0.isTracked ? FaceAnchorSnapshot(anchor: $0, camera: frame.camera) : nil
        }

        // `delegateQueue = .main`으로 지정했으므로 이 콜백은 항상 메인 스레드다.
        MainActor.assumeIsolated { onUpdate(snapshot) }
    }
}
