# 백로그

다음에 해볼 일. 각 항목에 **왜 해야 하는지**를 붙여 둡니다 — 근거 없는 TODO는 나중에 지울지 말지 판단이 안 됩니다.

끝낸 항목은 지우거나 `~~취소선~~`으로 남깁니다.

## 코드 정리

### 1. `Coordinator` 클래스명이 너무 일반적이다

`FaceMeshCoordinator.swift:12`의 `Coordinator`는 **전역 이름**입니다. 나중에 `UIViewRepresentable`을 하나 더 만들면 그쪽 Coordinator와 이름이 부딪힙니다.

- `DatasetCameraPreview.Coordinator`로 중첩하거나
- `FaceMeshCoordinator`로 rename (파일명과도 맞음)

### 2. 파일 상단 주석이 옛 이름 그대로다

`FaceMeshCoordinator.swift:2`가 아직 `// FaceMeshView.swift`입니다. 파일명만 바꾸고 헤더는 안 고쳤습니다.

### 3. `didRemove`가 비어 있다

얼굴이 화면에서 벗어났을 때 처리가 없습니다. 지금은 메시가 그대로 남는지, 사라지는지 확인해 보고 필요하면 `renderer(_:didRemove:for:)`를 구현합니다.

### 4. `EyeCropper`의 배수가 매직 넘버다

눈 2배(`EyeCropper.swift:37`), 얼굴 1.5배(`:52`)가 리터럴로 박혀 있습니다.

이 값은 **본 앱(Vultus)의 `EyeReader`와 손으로 맞춰야 하는 값**입니다. 한쪽만 바뀌면 학습 때와 추론 때 구도가 어긋나 정확도가 떨어집니다. 이름 있는 상수로 올려 두면 "여기는 함부로 못 바꾸는 값"이라는 신호가 됩니다.

### 5. `FlowLayout`이 뷰 파일에 얹혀 있다

`DatasetLabelingView.swift:206-267`에 `FlowLayout: Layout` 전체 구현이 같이 들어 있습니다. 라벨 칩 말고도 쓸 수 있는 범용 타입이라 분리 후보입니다. (급하지 않음 — 지금은 쓰는 곳이 하나뿐)

## 확인 필요

### 6. iPad 실기기 검증

[PR #5](https://github.com/konghee/FaceDatasetCollector/pull/5)에서 설정만 바꿨고 실기기 확인은 아직입니다. TrueDepth가 있는 iPad Pro에서:

- [ ] 가로로 돌려도 화면이 **안 돌아가는지** (세로 고정 확인)
- [ ] 얼굴 메시가 iPhone과 동일하게 그려지는지
- [ ] **저장된 이미지가 똑바로 서 있는지** — 라이브러리 화면에서 확인

셋 중 마지막이 핵심입니다. 누워서 저장되면 `CaptureOrientation`의 자동 역산이 iPad에서 다르게 나온다는 뜻입니다.

### 7. 빌드 경고가 남아 있는지

`FaceAnchorSnapshot`은 `nonisolated`가 아닙니다. `SampleGeometry.init`은 `nonisolated`인데 거기서 `snapshot.headPose` 등을 부르므로, 기본 액터 격리(`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) 때문에 경고가 뜰 수 있습니다.

빌드해서 실제 경고 개수를 확인하고, 있으면 `FaceAnchorSnapshot`을 `nonisolated struct`로 선언해 해결합니다. 없으면 이 항목을 지웁니다.

## 기능

### 8. 메시 표시 on/off 토글

지금은 항상 그려집니다. 피험자가 자기 얼굴 위의 와이어프레임에 신경 쓰면 표정이 굳을 수 있어, 껐다 켤 수 있으면 좋습니다.

## 장기

### 9. `ARSCNView` deprecated 대응

Xcode에서 `ARSCNView`에 "Use RealityView instead" 경고가 뜹니다. 아직 제거된 건 아니고 잘 동작하지만, 언젠가는 옮겨야 합니다.

`RealityView`는 API 구조가 완전히 다릅니다(`SCNNode` 대신 Entity-Component). 지금 이 프로젝트의 학습 목적에는 `ARSCNView` 쪽 자료가 훨씬 많으므로, **당장은 하지 않습니다.** 여기 적어 두는 건 "모르고 지나친 게 아니라 알고 미룬 것"을 남기기 위해서입니다.

---

[ARCHITECTURE.md](ARCHITECTURE.md) · [학습 로그](learning/)
