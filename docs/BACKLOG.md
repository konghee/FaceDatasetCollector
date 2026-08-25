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

`DatasetLabelingView.swift` 아래쪽에 `FlowLayout: Layout` 전체 구현이 같이 들어 있습니다.

**쓰는 곳이 둘로 늘었습니다** — `RankResultView`의 근거 칩도 이걸 씁니다. 라벨링 화면을 열지 않아도 되는 타입이 라벨링 파일에 숨어 있는 상태라, 이제는 `Views/FlowLayout.swift`로 빼는 편이 낫습니다.

## 확인 필요

### 6. iPad 실기기 검증

[PR #5](https://github.com/konghee/FaceDatasetCollector/pull/5)에서 설정만 바꿨고 실기기 확인은 아직입니다. TrueDepth가 있는 iPad Pro에서:

- [ ] 가로로 돌려도 화면이 **안 돌아가는지** (세로 고정 확인)
- [ ] 얼굴 메시가 iPhone과 동일하게 그려지는지
- [ ] **저장된 이미지가 똑바로 서 있는지** — 라이브러리 화면에서 확인

셋 중 마지막이 핵심입니다. 누워서 저장되면 `CaptureOrientation`의 자동 역산이 iPad에서 다르게 나온다는 뜻입니다.

### 7. 빌드 경고 6개 — 확인됨

`FaceSampleRecord.swift`에 아래 경고가 실제로 뜹니다. (`xcodebuild ... -destination 'generic/platform=iOS'`)

```
:53  main actor-isolated property 'headPose' can not be referenced from a nonisolated context
:58  translation
:59  translation
:60  inMillimeters
:61  leftEyeOpenness
:62  rightEyeOpenness
```

`SampleGeometry.init`은 `nonisolated`인데, 거기서 부르는 `FaceAnchorSnapshot`의 프로퍼티들이 기본 액터 격리(`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) 때문에 MainActor에 묶여 있어서 나는 경고입니다.

`FaceAnchorSnapshot`을 `nonisolated struct`로 선언하면 6개가 한 번에 사라집니다. `SIMDHelpers`의 `translation` / `inMillimeters` 확장도 같이 봐야 합니다.

## 기능

### 8-1. 신분 판정 기준값 실측 보정

`RankReader.Threshold`의 네 기준값은 **실측 전 추정치**입니다. 사람들을 실제로 찍어 보면 결과가 한쪽 분면으로 쏠릴 수 있습니다.

결과 화면의 근거 칩을 보면서 여러 명을 찍어 보고, 12신분이 골고루 나오게 중앙값으로 다시 맞춰야 합니다. 부스에서 다들 같은 신분이 나오면 재미가 죽습니다.

### 8-2. 얼굴 합성 (face-swap) — v2

MVP에서는 뺐습니다. `Alissonerdx/BFS-Best-Face-Swap`은 단독 모델이 아니라 **Flux 2 Klein 4b/9b · Qwen Image Edit · Krea 2 위에 올리는 LoRA**라, iOS 온디바이스 실행이 불가능합니다.

서버를 두면 가능하지만 부스 환경에서는 네트워크 의존 · 대기시간 · 얼굴 사진 외부 전송이 모두 부담입니다. 먼저 MVP로 재미 요소가 실제로 참여를 끌어내는지 확인하고, 그 다음에 판단합니다.

### 8-3. 동의 철회에 대응할 길이 없다

동의 화면에서 "촬영 도중 언제든 말해 주세요"라고 약속하지만, **저장이 끝난 뒤에 연락이 오면 지울 방법이 앱에 없습니다.** 라벨링 대기 화면에서는 미분류 표본만 지울 수 있고, 이미 라벨이 붙은 사람은 목록에 뜨지 않습니다.

`구분자로 찾아 그 사람 것 전부 삭제`가 데이터셋 화면에 있어야 합니다. 지금은 zip을 풀어 손으로 지우는 수밖에 없습니다.

### 8-4. 메시 표시 on/off 토글

지금은 항상 그려집니다. 피험자가 자기 얼굴 위의 와이어프레임에 신경 쓰면 표정이 굳을 수 있어, 껐다 켤 수 있으면 좋습니다.

## 장기

### 9. `ARSCNView` deprecated 대응

Xcode에서 `ARSCNView`에 "Use RealityView instead" 경고가 뜹니다. 아직 제거된 건 아니고 잘 동작하지만, 언젠가는 옮겨야 합니다.

`RealityView`는 API 구조가 완전히 다릅니다(`SCNNode` 대신 Entity-Component). 지금 이 프로젝트의 학습 목적에는 `ARSCNView` 쪽 자료가 훨씬 많으므로, **당장은 하지 않습니다.** 여기 적어 두는 건 "모르고 지나친 게 아니라 알고 미룬 것"을 남기기 위해서입니다.

---

[ARCHITECTURE.md](ARCHITECTURE.md) · [학습 로그](learning/)
