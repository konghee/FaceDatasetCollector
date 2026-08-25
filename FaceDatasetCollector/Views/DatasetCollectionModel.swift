//
//  DatasetCollectionModel.swift
//  FaceDatasetCollector
//

import ARKit
import Foundation
import Observation

/// 데이터 수집 화면의 상태.
///
/// 현장에서 하는 일만 들고 있다 — **구분자 정하기 → 동의 받기 → 촬영 → 저장.**
/// 눈·얼굴형 라벨은 여기서 붙이지 않는다. 참여자를 세워 둔 채 14종을 고를 시간이 없어서,
/// 사진만 먼저 모으고 나중에 사람 단위로 몰아서 붙인다. (`LabelingQueueModel`)
@MainActor
@Observable
final class DatasetCollectionModel {

    let manager = ARFaceCaptureManager()

    /// 방금 찍어 **이미 저장된** 표본. 값이 있으면 신분 결과 시트가 뜬다.
    ///
    /// 시트가 뜨기 전에 저장이 끝나 있는 건 의도한 것이다. 결과를 보여 주는 도중에
    /// 수집자가 실수로 시트를 닫아도 사진은 이미 디스크에 있다.
    var shown: PendingSample?

    /// 이번 표본의 신분 판정 결과. 얼굴 비율을 못 재면 `nil`이고, 그때는 결과 화면을 건너뛴다.
    var rankResult: RankResult?

    var stats = DatasetStats()
    var isProcessing = false
    var isSaving = false
    var errorMessage: String?

    /// 방금 저장한 표본 요약. 화면 위에 잠깐 띄운다.
    var lastSaved: String?

    /// 방금 찍은 사진에서 Vision이 얼굴을 못 찾았다는 표시.
    ///
    /// 크롭이 비면 나중에 라벨을 붙일 그림이 없다. 원본은 남으니 저장은 하되,
    /// **그 사람이 아직 앞에 있을 때** 다시 찍으라고 알려 줘야 한다.
    var captureWarning: String?

    /// 피험자 구분자.
    ///
    /// 같은 사람의 사진이 학습 셋과 검증 셋에 나뉘어 들어가면 모델이 "그 사람"을 외워
    /// 정확도가 실제보다 높게 나온다. 나중에 사람 단위로 나누려면 촬영 시점에
    /// 누구인지 남겨 두는 수밖에 없다.
    var subjectID: String {
        didSet {
            UserDefaults.standard.set(subjectID, forKey: Keys.subjectID)
            hasConsent = ConsentLedger.hasConsented(subjectID)
        }
    }

    /// 지금 피험자에게 촬영 동의를 받았는지.
    ///
    /// `ConsentLedger`를 그때그때 읽지 않고 들고 있는 이유는, 동의를 받아도 `subjectID`는
    /// 그대로라 화면이 다시 그려질 계기가 없기 때문이다.
    private(set) var hasConsent: Bool

    /// 동의 시트를 띄울지. 이름을 다 적은 직후와 다음 사람으로 넘어간 직후에 켜진다.
    var isRequestingConsent = false

    /// 센서 원본(가로)을 세로로 세우는 방식.
    ///
    /// 기본값은 ARKit의 표시 변환에서 매번 역산하는 `.automatic`이라 손댈 일이 없다.
    /// 그래도 고정 방향을 남겨 둔 건, 자동이 어긋나는 기기를 만났을 때 전부 다시 찍는 대신
    /// 화면에서 바로 덮어쓸 수 있게 하기 위해서다.
    var captureOrientation: CaptureOrientation {
        didSet { UserDefaults.standard.set(captureOrientation.storedValue, forKey: Keys.orientation) }
    }

    private enum Keys {
        static let subjectID = "dataset.subjectID"
        static let orientation = "dataset.imageOrientation"
    }

    init() {
        let restoredSubjectID = UserDefaults.standard.string(forKey: Keys.subjectID) ?? "S001"
        subjectID = restoredSubjectID
        hasConsent = ConsentLedger.hasConsented(restoredSubjectID)
        captureOrientation = CaptureOrientation(
            storedValue: UserDefaults.standard.integer(forKey: Keys.orientation)
        )

        manager.onSnapshot = { [weak self] snapshot in
            self?.collectMetrics(from: snapshot)
        }
    }

    // MARK: - 판정 지표 누적

    /// 최근 프레임들의 얼굴 치수. 한 장으로 판정하면 그 프레임의 떨림이 결과를 뒤집는다.
    ///
    /// 실제로 같은 사람이 2분 사이에 서로 다른 신분을 받은 적이 있다. 지표가 경계선에
    /// 걸터앉았을 때 한 프레임의 흔들림만으로 칸이 바뀌기 때문이다.
    private var recentMetrics: [FaceMetrics] = []

    private static let metricsWindow = 30

    private func collectMetrics(from snapshot: FaceAnchorSnapshot?) {
        guard let snapshot else {
            // 얼굴이 화면을 벗어났다. 다음 사람의 값과 섞이면 안 된다.
            recentMetrics.removeAll()
            return
        }

        let ipdMM = simd_distance(
            snapshot.leftEyeTransform.translation,
            snapshot.rightEyeTransform.translation
        ) * 1000

        guard let metrics = FaceMetrics(
            vertices: snapshot.vertices,
            interpupillaryDistanceMM: ipdMM
        ) else { return }

        recentMetrics.append(metrics)
        if recentMetrics.count > Self.metricsWindow {
            recentMetrics.removeFirst()
        }

#if DEBUG
        sampleLandmarksIfNeeded()
#endif
    }

#if DEBUG

    // MARK: - Vision 랜드마크 계측 (실측용)

    /// ARKit 메시로는 사람을 가를 수 없다는 결론이 나와, Vision 랜드마크에 신호가 있는지
    /// 재보기 위한 장치다. 판정에는 아직 쓰지 않는다.
    private(set) var landmarkMetrics: FaceLandmarkMetrics?

    private var isSamplingLandmarks = false
    private var lastLandmarkSample = Date.distantPast

    /// Vision은 무거워서 매 프레임 돌릴 수 없다. 초당 네 번이면 사람을 훑기에 충분하다.
    private static let landmarkInterval: TimeInterval = 0.25

    private func sampleLandmarksIfNeeded() {
        guard !isSamplingLandmarks,
              Date().timeIntervalSince(lastLandmarkSample) >= Self.landmarkInterval
        else { return }

        // 프레임을 붙들면 픽셀버퍼 풀이 마르므로, 촬영 때와 같이 복사해 두고 놓아준다.
        guard let raw = DatasetCapture.grab(from: manager, orientation: captureOrientation)
        else { return }

        isSamplingLandmarks = true
        lastLandmarkSample = Date()

        Task {
            let size = CGSize(width: raw.image.width, height: raw.image.height)
            let observation = try? await FaceDetector.detect(in: raw.image)

            landmarkMetrics = observation.flatMap {
                FaceLandmarkMetrics($0, imageSize: size)
            }
            isSamplingLandmarks = false
        }
    }

#endif

    /// 최근 프레임 중 동공간거리가 한가운데인 것.
    ///
    /// 평균이 아니라 중앙값을 고르는 이유는, 얼굴을 놓쳤다 다시 잡는 프레임에서 튀는 값이
    /// 섞여도 결과가 끌려가지 않기 때문이다. 합성한 값이 아니라 실제로 관측한 한 장이다.
    private var representativeMetrics: FaceMetrics? {
        guard !recentMetrics.isEmpty else { return nil }
        return recentMetrics
            .sorted { $0.ipdMM < $1.ipdMM }[recentMetrics.count / 2]
    }

    // MARK: - 촬영

    var quality: CaptureQuality? {
        manager.snapshot.map(CaptureQuality.init)
    }

#if DEBUG
    /// 지금 화면에 잡힌 얼굴의 판정 지표. **기준값을 실측으로 맞추기 위한 계측기다.**
    ///
    /// 촬영·라벨링을 거치지 않고 카메라를 향하기만 해도 값이 보이므로, 여러 사람을
    /// 빠르게 훑어 분포를 확인할 수 있다. 릴리스 빌드에는 들어가지 않는다.
    var liveResult: RankResult? {
        representativeMetrics.map { RankReader.preview($0, subjectID: subjectID) }
    }

    /// 피험자별로 기억해 둔 신분을 모두 지운다. 기준값을 바꿔 가며 시험할 때 쓴다.
    func forgetRanks() {
        RankMemory.forgetAll()
    }

    /// 계측기에서 지금까지 모은 프레임 수. 판정이 몇 장에 근거하는지 보여 준다.
    var collectedFrameCount: Int { recentMetrics.count }
#endif

    /// 찍어서 바로 저장하고, 참여자에게 신분 결과를 보여 준다.
    ///
    /// 라벨링 단계가 없어 셔터 한 번으로 한 장이 끝난다. 같은 사람을 여러 장 찍을 때
    /// 구분자를 다시 만질 필요도 없다.
    func capture() {
        guard !isProcessing, !isSaving, shown == nil else { return }

        // 동의 없이 찍힌 사진이 데이터셋에 섞이면 나중에 골라낼 수가 없다.
        // 셔터를 막는 대신 동의 화면을 열어 준다. 반응 없는 버튼만 남으면
        // 무엇이 막고 있는지 알 수 없다.
        guard hasConsent else {
            if subjectID.isEmpty {
                errorMessage = "피험자 구분자를 먼저 입력하세요."
            } else {
                isRequestingConsent = true
            }
            return
        }

        // 동의 시각이 없으면 저장하지 않는다. 데이터셋에 들어간 사진은 모두
        // 언제 받은 동의로 찍혔는지가 파일에 붙어 있어야 한다.
        // (바로 위에서 이미 막으므로 여기까지 오는 일은 없어야 한다)
        guard let consentedAt = ConsentLedger.consentedAt(subjectID) else {
            errorMessage = "\(subjectID)의 동의 기록이 없어 촬영하지 않았습니다. 동의부터 받아 주세요."
            return
        }

        guard let raw = DatasetCapture.grab(from: manager, orientation: captureOrientation) else {
            errorMessage = "얼굴을 찾지 못했습니다. 화면 안에 얼굴을 맞춰 주세요."
            return
        }

        isProcessing = true
        captureWarning = nil

        Task {
            // Vision 검출과 JPEG 인코딩은 무거워서 백그라운드로 넘긴다.
            let sample = await DatasetCapture.makeSample(from: raw)
            // 셔터를 누른 그 한 프레임이 아니라, 직전까지 모아 둔 값으로 확정한다.
            // 신분이 정해지고 기억되는 곳은 여기 한 곳뿐이다.
            let result = representativeMetrics.map { RankReader.decide($0, subjectID: subjectID) }
                ?? RankReader.decide(sample, subjectID: subjectID)

            await store(sample, consentedAt: consentedAt)

            // 판정을 못 하면 보여 줄 것이 없다. 시트를 띄우지 않고 다음 촬영을 받는다.
            if result != nil {
                rankResult = result
                shown = sample
            }
            isProcessing = false
        }
    }

    /// 라벨 없이 디스크에 쓴다. 눈·얼굴형은 나중에 라벨링 화면이 붙인다.
    private func store(_ sample: PendingSample, consentedAt: Date) async {
        isSaving = true
        do {
            try await FaceDatasetStore.shared.save(
                sample,
                subjectID: subjectID,
                consentedAt: consentedAt
            )
            lastSaved = "\(subjectID) · 라벨링 대기로 저장"

            if !sample.hasAllCrops {
                captureWarning = "얼굴 검출 실패 — 크롭이 비어 나중에 라벨을 못 붙입니다. 다시 찍으세요."
            }

            await refreshStats()
        } catch {
            errorMessage = "저장 실패: \(error.localizedDescription)"
        }
        isSaving = false
    }

    // MARK: - 동의

    /// 이름을 다 적었거나 다음 사람으로 넘어간 직후에 부른다.
    /// 아직 동의를 받지 않은 사람이면 동의 시트를 띄운다.
    func requestConsentIfNeeded() {
        guard !hasConsent, !subjectID.isEmpty else { return }
        isRequestingConsent = true
    }

    func grantConsent() {
        ConsentLedger.record(subjectID)
        hasConsent = true
        isRequestingConsent = false
    }

    /// 동의하지 않았다. 시트만 닫고 동의는 남기지 않으므로 셔터는 계속 막혀 있다.
    func declineConsent() {
        isRequestingConsent = false
    }

    /// 참여자가 결과를 다 봤다. 시트를 닫고 다음 촬영을 받는다.
    ///
    /// 사진은 셔터를 누른 시점에 이미 저장돼 있으므로 여기서 할 일은 화면을 비우는 것뿐이다.
    func dismissResult() {
        shown = nil
        rankResult = nil
    }

    func refreshStats() async {
        stats = await FaceDatasetStore.shared.stats()
    }

    /// 다음 사람으로 넘어간다. `S001` → `S002`처럼 숫자 부분만 올린다.
    ///
    /// 구분자가 바뀌면 카메라 앞에 선 사람도 바뀐 것이므로, 곧바로 그 사람의 동의를 받는다.
    func advanceSubject() {
        let digits = subjectID.suffix(while: \.isNumber)
        guard let number = Int(digits), !digits.isEmpty else {
            subjectID += "-2"
            requestConsentIfNeeded()
            return
        }

        let prefix = subjectID.dropLast(digits.count)
        subjectID = prefix + String(format: "%0\(digits.count)d", number + 1)
        requestConsentIfNeeded()
    }
}

private extension StringProtocol {
    /// 문자열 끝에서부터 조건을 만족하는 동안 잘라낸다. (`"S012"` → `"012"`)
    func suffix(while predicate: (Character) -> Bool) -> String {
        String(reversed().prefix(while: predicate).reversed())
    }
}
