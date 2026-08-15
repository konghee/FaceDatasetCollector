# 코드 구조

코드를 따라가며 설명합니다. 아래로 갈수록 세부로 들어가니, 1~2번만 읽어도 전체 그림은 잡힙니다.

데이터 산출물(저장 폴더 구조, Create ML 학습법)은 [README](../README.md)에 따로 있습니다. 이 문서는 **코드가 어떻게 짜여 있는가**만 다룹니다.

## 1. 파일 지도

```
FaceDatasetCollectorApp     진입점. DatasetCollectionView 하나만 띄운다.

Views/
  DatasetCollectionView     카메라 화면 + 셔터 (보이는 것)
  DatasetCollectionModel    촬영→라벨링→저장 한 사이클의 상태 (판단하는 것)
  FaceMeshCoordinator       얼굴 위에 와이어프레임 메시를 그리는 델리게이트
  DatasetLabelingView       라벨 붙이는 시트
  DatasetLibraryView        통계 / zip 내보내기 / 방향 설정

Core/FaceGeometry/          ARKit에서 값을 꺼내는 층
  ARFaceCaptureManager      세션 관리, 매 프레임 스냅샷 발행
  FaceAnchorSnapshot        한 프레임의 얼굴 값 복사본 + 자세(yaw/pitch/roll) 계산
  SIMDHelpers               행렬에서 위치 뽑기, 미터→밀리미터

Core/Dataset/               데이터셋을 만드는 층
  CaptureOrientation        저장 이미지를 어느 방향으로 세울지
  DatasetCapture            프레임 → 표본 파이프라인
  FaceDetector / EyeCropper Vision 검출 + 크롭 규칙
  DatasetLabel              라벨 정의 (rawValue = 폴더명 = 클래스명)
  FaceSampleRecord          표본/기록 타입
  FaceDatasetStore          디스크 저장 (actor)
```

핵심 분업은 **`FaceGeometry`는 ARKit만 알고, `Dataset`은 파일만 안다**는 것입니다. 화면(`Views`)은 둘을 이어 붙이기만 합니다.

## 2. 앱이 켜지고 화면이 뜨기까지

여기서 일어나는 일은 전부 **딱 한 번씩만** 일어납니다. 순서가 중요한 이유는 뒤 단계가 앞 단계에서 만들어 둔 것을 쓰기 때문입니다.

| # | 무엇이 | 누가 부르나 |
|---|---|---|
| 1 | [`@main FaceDatasetCollectorApp`](../FaceDatasetCollector/FaceDatasetCollectorApp.swift#L11) | SwiftUI 런타임 |
| 2 | `DatasetCollectionView()` 생성 | SwiftUI 런타임 |
| 3 | [`@State model = DatasetCollectionModel()`](../FaceDatasetCollector/Views/DatasetCollectionView.swift#L15) | SwiftUI 런타임 |
| 4 | `ARFaceCaptureManager()` → `ARSession()` **생성** | 3번에 딸려서 |
| 5 | `body` 평가 → [`DatasetCameraPreview(session:)`](../FaceDatasetCollector/Views/DatasetCollectionView.swift#L57) | SwiftUI 런타임 |
| 6 | [`makeCoordinator()`](../FaceDatasetCollector/Views/DatasetCollectionView.swift#L183) | SwiftUI 런타임 |
| 7 | [`makeUIView(context:)`](../FaceDatasetCollector/Views/DatasetCollectionView.swift#L187) | SwiftUI 런타임 |
| 8 | [`.onAppear` → `manager.start()`](../FaceDatasetCollector/Views/DatasetCollectionView.swift#L31) | SwiftUI 런타임 |

**4번과 8번을 헷갈리면 안 됩니다.** 4번은 `ARSession` 객체를 만들 뿐이고, 카메라는 아직 꺼져 있습니다. 실제로 전면 카메라가 켜지는 건 8번의 [`session.run(...)`](../FaceDatasetCollector/Core/FaceGeometry/ARFaceCaptureManager.swift#L29)입니다.

**6번이 7번보다 먼저**인 것도 우연이 아닙니다. 7번 안에서 `view.delegate = context.coordinator`를 쓰려면 그 시점에 코디네이터가 이미 있어야 합니다. `context.coordinator`의 타입은 `makeCoordinator()`의 **반환 타입**으로 결정되므로, 여기를 `-> ()`처럼 잘못 쓰면 델리게이트 대입에서 컴파일이 깨집니다.

`DatasetCollectionView`는 struct라 상태가 바뀔 때마다 새로 만들어졌다 버려집니다. 그런데 `@State`가 붙은 모델과 `makeCoordinator()`가 만든 코디네이터는 SwiftUI가 struct 바깥에 보관해 **계속 살려 둡니다.** 화면을 벗어나면 [`.onDisappear`](../FaceDatasetCollector/Views/DatasetCollectionView.swift#L35)가 `manager.stop()`으로 세션을 정지합니다.

## 3. 얼굴 메시는 어떻게 그려지나

가장 헷갈리기 쉬운 지점입니다. **같은 `ARSession` 하나에 델리게이트 자리가 둘** 있고, 서로 다른 일을 합니다.

```
ARSession ── 매 프레임 ARFrame 생성 (초당 약 60회)
   │
   ├── ARSession.delegate ──→ ARSessionProxy      데이터 담당
   │                          얼굴 값을 스냅샷으로 복사 → 화면의 각도 표시 갱신
   │
   └── ARSCNView.delegate ──→ Coordinator          렌더링 담당
                              얼굴 위에 그릴 3D 노드를 결정
```

둘은 서로를 전혀 모르고 각자 독립적으로 돕니다.

### 데이터 쪽 — ARSessionProxy

[`ARSessionProxy`](../FaceDatasetCollector/Core/FaceGeometry/ARFaceCaptureManager.swift#L76)를 별도 객체로 둔 이유는 하나입니다. `ARSessionDelegate`는 옛날 프로토콜이라 `@MainActor`를 모릅니다. 그래서 델리게이트 수신만 프록시로 떼어내고, `delegateQueue = .main`으로 고정한 뒤 `MainActor.assumeIsolated`로 "이건 확실히 메인 스레드다"라고 컴파일러에 알려 줍니다.

매 프레임 [`session(_:didUpdate:)`](../FaceDatasetCollector/Core/FaceGeometry/ARFaceCaptureManager.swift#L83)가 `FaceAnchorSnapshot`을 새로 만들어 `manager.snapshot`에 꽂습니다. `@Observable`이라 화면의 yaw/pitch/roll 표시가 저절로 따라 갱신됩니다.

### 렌더링 쪽 — Coordinator

[`FaceMeshCoordinator.swift`](../FaceDatasetCollector/Views/FaceMeshCoordinator.swift)의 `Coordinator`가 `ARSCNViewDelegate`를 채택합니다. **struct가 아니라 class여야 합니다.** `ARSCNViewDelegate`는 `@objc` 프로토콜이고, Objective-C 런타임은 class에만 있는 메타데이터로 메서드를 찾아 호출하기 때문입니다.

함수가 둘인데, **어느 쪽을 부를지는 ARKit이 앵커의 UUID를 보고 정합니다.**

| 함수 | 언제 | 하는 일 |
|---|---|---|
| [`renderer(_:nodeFor:)`](../FaceDatasetCollector/Views/FaceMeshCoordinator.swift#L14) | 처음 보는 UUID (얼굴당 1회) | `ARSCNFaceGeometry`에 `fillMode = .lines` 재질을 입혀 `SCNNode`로 반환 |
| [`renderer(_:didUpdate:for:)`](../FaceDatasetCollector/Views/FaceMeshCoordinator.swift#L34) | 이미 아는 UUID (매 프레임) | `faceGeometry.update(from: faceAnchor.geometry)` |

`didUpdate`에 반환값이 없는 게 이상해 보이지만, 새로 그리는 게 아니라 **이미 씬에 올라가 있는 객체의 정점을 제자리에서 바꿔치기**하는 것이라 필요가 없습니다. `SCNNode`와 `SCNGeometry`가 참조 타입(class)이라 가능한 일이고, SceneKit은 매 프레임 씬을 그대로 다시 그리므로 바뀐 내용이 다음 프레임에 자동 반영됩니다.

> 메시는 미리보기 화면에만 겹쳐 그려집니다. 저장되는 이미지는 `frame.capturedImage`(카메라 원본)에서 뽑으므로 메시가 찍히지 않습니다.

## 4. 셔터를 한 번 누르면 벌어지는 일

### ① 왜 두 단계로 쪼갰나

[`DatasetCollectionModel.capture()`](../FaceDatasetCollector/Views/DatasetCollectionModel.swift#L67)는 일부러 두 번에 나눠 일합니다.

```
grab()        메인 스레드, 동기, 아주 짧게   프레임 → CGImage 복사
   ↓
makeSample()  백그라운드, async, 무겁게      Vision 검출 + 크롭 + JPEG 인코딩
```

이유는 **`ARFrame`을 오래 붙들면 세션이 멈추기 때문**입니다. ARKit은 픽셀버퍼를 정해진 개수의 풀에서 돌려 씁니다. 라벨링 화면에 머무는 30초 동안 프레임 하나를 쥐고 있으면 풀이 고갈되어 카메라가 그대로 얼어붙습니다.

그래서 [`grab()`](../FaceDatasetCollector/Core/Dataset/DatasetCapture.swift#L39)은 `context.createCGImage(...)`로 **픽셀을 복사**한 뒤 즉시 프레임을 놓습니다. 이 시점부터 ARKit 객체는 하나도 참조하지 않습니다. 그 결과가 `RawFrame`이고, `CGImage`가 `Sendable`이 아니라서 `@unchecked Sendable`을 붙였습니다 — 생성 후 불변이라 백그라운드로 넘겨도 안전하다는 뜻입니다.

### ② 크롭

[`makeSample()`](../FaceDatasetCollector/Core/Dataset/DatasetCapture.swift#L65)이 백그라운드에서 [`FaceDetector.detect`](../FaceDatasetCollector/Core/Dataset/FaceDetector.swift#L21)로 얼굴·랜드마크를 찾고, [`EyeCropper`](../FaceDatasetCollector/Core/Dataset/EyeCropper.swift)로 얼굴 1장 + 눈 2장을 잘라 JPEG 0.95로 인코딩합니다.

`EyeCropper`가 독립 타입인 이유가 중요합니다. **학습 데이터를 자르는 규칙과 본 앱이 추론할 때 자르는 규칙이 다르면 정확도가 떨어집니다.** 모델이 "눈 주변 2배 정사각형"을 보고 배웠는데 실전에서 1.5배가 들어오면 구도가 어긋나니까요.

배수의 근거도 각각 있습니다.

- **눈 2배** ([`:37`](../FaceDatasetCollector/Core/Dataset/EyeCropper.swift#L37)) — 눈꼬리·쌍꺼풀 주변 맥락이 있어야 모양을 구분합니다
- **얼굴 1.5배** ([`:52`](../FaceDatasetCollector/Core/Dataset/EyeCropper.swift#L52)) — Vision의 `boundingBox`는 턱과 이마를 바싹 자르는데, 얼굴형 판정에 필요한 정보가 바로 그 턱선과 이마 폭입니다

Vision이 얼굴을 못 찾아도 표본은 만듭니다. 전체 프레임과 기하값은 이미 유효하고, 크롭은 나중에 `raw/`에서 다시 뜰 수 있으니까요. 대신 `hasAllCrops`가 false가 되어 라벨링 화면에 경고가 뜹니다.

### ③ 라벨링 시트

시트를 여닫는 방식이 조금 특이합니다.

```swift
.sheet(item: $model.pending) { sample in ... }
```

`pending`에 값이 생기면 시트가 뜨고, **`nil`이 되면 저절로 닫힙니다.** 그래서 저장 버튼도 `버리기` 버튼도 `dismiss()`를 부르지 않고 `pending`만 건드립니다. `dismiss()`를 직접 부르면 아직 `pending`이 남아 있는 찰나에 시트가 다시 떠오르는 버그가 납니다.

[`DatasetLabelingView`](../FaceDatasetCollector/Views/DatasetLabelingView.swift)의 [`labelSection`](../FaceDatasetCollector/Views/DatasetLabelingView.swift#L130)은 제네릭 함수라, 같은 함수를 눈 두 번 + 얼굴형 한 번 호출하면 끝입니다. 각 섹션 옆에 그 크롭을 붙여 어느 쪽을 고르는 중인지 보이게 했습니다.

### ④ 저장

[`FaceDatasetStore`](../FaceDatasetCollector/Core/Dataset/FaceDatasetStore.swift#L24)는 `actor`입니다. 디스크 쓰기가 메인 스레드를 막으면 촬영 중 화면이 끊기기 때문입니다. 한 표본이 남기는 것은 [README의 저장 구조](../README.md#저장-구조)에 있습니다.

두 가지만 코드 관점에서 덧붙이면:

- [`appendToIndex`](../FaceDatasetCollector/Core/Dataset/FaceDatasetStore.swift#L133)가 `index.csv`의 **헤더 첫 줄을 읽어 현재 13열 구성과 비교**하고, 다르면 옛 파일을 `index-legacy-<시각>.csv`로 밀어 둡니다. 열 수가 다른 줄이 섞이면 CSV 전체를 못 읽게 되기 때문입니다
- [`exportArchive()`](../FaceDatasetCollector/Core/Dataset/FaceDatasetStore.swift#L204)는 zip 라이브러리 없이 `NSFileCoordinator`의 `.forUploading` 옵션만으로 압축합니다

## 5. 방향은 어떻게 정해지나

### 문제

카메라 센서 원본은 **항상 가로**입니다. 세로로 들고 찍어도 버퍼는 눕혀진 채로 나옵니다. 이걸 세우는 방법이 EXIF 방향 8가지(회전 4가지 × 좌우반전 여부)인데, **전면 카메라가 어느 것인지는 문서만 보고 확정할 수 없습니다.**

### 해법 — ARKit에게 물어본다

미리보기 화면은 처음부터 똑바로 보였습니다. 즉 ARKit은 정답을 알고 있습니다. 그 정답이 `ARFrame.displayTransform(for:viewportSize:)`이고, [`CaptureOrientation.derived`](../FaceDatasetCollector/Core/Dataset/CaptureOrientation.swift#L38)는 그 행렬을 **거꾸로 읽어** EXIF 값으로 바꿉니다.

```swift
let transform = frame.displayTransform(
    for: .portrait,
    viewportSize: CGSize(width: resolution.height, height: resolution.width)  // 세로로 눕힌 크기
)
```

뷰포트를 "원본을 세로로 눕힌 크기"로 주는 게 요령입니다. 비율이 원본과 정확히 같아지므로 ARKit이 화면을 꽉 채우려고 넣는 **확대·잘라내기 성분이 사라지고 회전과 반전만 남습니다.**

> ⚠️ 여기 `.portrait`는 **화면 방향이 세로로 고정돼 있다는 전제**입니다. 그래서 빌드 설정에서 `UISupportedInterfaceOrientations`를 세로 하나로 잠가 두었습니다. 이 잠금을 풀면 가로로 든 채 찍은 사진이 **경고 없이** 누운 채로 저장됩니다.

### 행렬에서 회전을 읽는 법

```swift
let isMirrored = transform.a * transform.d - transform.b * transform.c < 0   // 행렬식
```

**행렬식이 음수면 좌우가 뒤집혔다**는 뜻입니다. 뒤집기는 방향을 보존하지 않으니까요. 반전이 섞여 있으면 각도를 바로 잴 수 없으므로, 먼저 걷어내서 순수 회전만 남깁니다.

```swift
let rotation = isMirrored ? CGAffineTransform(scaleX: -1, y: 1).concatenating(transform) : transform
let quarterTurns = Int((atan2(rotation.b, rotation.a) / (.pi / 2)).rounded())
```

`atan2(b, a)`는 "원래 오른쪽을 향하던 방향이 어디로 갔는가"입니다. 화면 좌표계는 y가 **아래로** 향하므로 시계방향이 양수입니다. 90°로 나눠 반올림하면 0~3의 정수가 떨어지고, 표에서 EXIF 값을 꺼냅니다.

```
0 → .up (1)      회전 없음
1 → .right (6)   시계 90°
2 → .down (3)    180°
3 → .left (8)    반시계 90°
              + 반전이면 각각 .upMirrored / .rightMirrored / ... 로
```

`.fixed(...)` 선택지를 남겨 둔 건 보험입니다. 자동이 실패하는 기기를 만났을 때 전부 다시 찍는 대신 화면에서 덮어쓸 수 있게요. `UserDefaults`에 0이 저장되면 `.automatic`인데, 이건 "설정한 적 없음"과 "자동"이 자연스럽게 같은 값이 되도록 노린 것입니다(EXIF에는 0이 없습니다).

## 6. 좌표계 세 개 — 여기가 제일 헷갈립니다

| 좌표계 | 정체 | 어디에 쓰나 |
|---|---|---|
| 얼굴 로컬 | `anchor.geometry.vertices`. 원점이 얼굴 자신 | `geometry/*.bin`. 고개 방향이 이미 제거돼 있어 각도가 달라도 값이 안 흔들린다 |
| 카메라 | `faceInCamera = camera.transform.inverse * anchor.transform` | yaw·pitch. "카메라에서 본 얼굴" |
| 월드 | 세션 시작 위치가 원점, +Y가 중력 반대 | roll의 기준 |

### 자세 계산의 원리

[`headPose`](../FaceDatasetCollector/Core/FaceGeometry/FaceAnchorSnapshot.swift#L94)의 첫 두 줄이 전부입니다.

```swift
let forward = faceInCamera.columns.2  // 얼굴 정면 (+Z)
let up      = faceInCamera.columns.1  // 얼굴 위쪽 (+Y)
```

4×4 변환 행렬의 **각 열은 그 좌표계의 축을 부모 좌표계로 표현한 것**입니다. 그러니 `faceInCamera`의 2번 열은 "카메라에서 본 얼굴의 정면 방향"이 됩니다. 이 벡터 하나로 yaw와 pitch가 나옵니다.

### roll만 기준이 다른 이유

`roll`은 원래 카메라의 위쪽 축 기준이었습니다. 그런데 **ARKit의 카메라 좌표계는 기기가 가로로 누운 상태를 기준으로 정의돼 있습니다.** 그래서 폰을 세로로 들고 똑바로 앉은 사람을 찍으면 roll이 ±90°로 나오고, `12° 이내`라는 정면 판정이 절대 통과할 수 없었습니다.

지금은 중력을 기준으로 잽니다.

```swift
let up = camera.transform.inverse * SIMD4(0, 1, 0, 0)   // 월드 +Y를 카메라 좌표로
```

얼굴 추적 세션은 중력 정렬이라 월드 +Y가 곧 실제 "위"입니다. 이걸 카메라 좌표로 옮겨 두면, **폰을 어떻게 들었든 "저장된 사진에서 고개가 얼마나 기울었나"와 같은 값**이 됩니다. 폰을 완전히 눕히면 중력의 투영이 0에 가까워져 각이 무의미해지므로, 그때는 카메라 축으로 돌아가는 예외를 뒀습니다.

## 7. 프로젝트 전체에 걸린 관례 두 가지

### 폴더명 = 클래스명

[`DatasetLabel`](../FaceDatasetCollector/Core/Dataset/DatasetLabel.swift#L13) 프로토콜의 `rawValue`가 그대로 폴더 이름이 됩니다([`:31`](../FaceDatasetCollector/Core/Dataset/DatasetLabel.swift#L31)). Create ML 이미지 분류기가 "폴더명 = 클래스명" 규약을 쓰기 때문에, 내보낸 `images/eye` 폴더를 창에 끌어다 놓으면 바로 학습이 됩니다.

여기에 사슬이 하나 더 걸려 있습니다. **폴더 이름 → CoreML 출력 레이블 → 본 앱의 `EyeShape.EyeType(label:)`.** 본 앱에 케이스를 추가하면 여기에도 같은 `rawValue`로 추가해야 그 사슬이 끊기지 않습니다. (눈 9종 · 얼굴형 5종)

### 기본 액터 격리가 MainActor

빌드 설정에 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`가 켜져 있습니다. **아무것도 안 붙인 타입은 전부 MainActor에 격리된다**는 뜻입니다. UI 코드는 편해지지만, `FaceDatasetStore` 액터로 넘길 값 타입들은 그러면 곤란합니다.

그래서 `nonisolated`가 붙어 있습니다.

- 타입 통째로: `PendingSample`([`:15`](../FaceDatasetCollector/Core/Dataset/FaceSampleRecord.swift#L15)), `SampleGeometry`([`:39`](../FaceDatasetCollector/Core/Dataset/FaceSampleRecord.swift#L39)), `FaceSampleRecord`([`:68`](../FaceDatasetCollector/Core/Dataset/FaceSampleRecord.swift#L68))
- 멤버 단위: `DatasetLabel`의 `folderName` / `id` / `axisName` / `axisTitle` / `pickerTitle`

`FaceSampleRecord`의 `schemaVersion`은 현재 **2**입니다([`:97`](../FaceDatasetCollector/Core/Dataset/FaceSampleRecord.swift#L97)). 버전 2에서 단일 `eyeLabel`이 좌/우로 갈라졌고, roll이 중력 기준으로 바뀌었습니다.

---

**관련 문서** · [학습 로그](learning/) · [백로그](BACKLOG.md) · [README](../README.md)
