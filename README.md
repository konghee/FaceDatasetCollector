# FaceDatasetCollector

관상 모델(눈 9종 / 얼굴형 5종) 학습용 얼굴 데이터를 현장에서 모으는 **수집 전용 앱**입니다.
전면 TrueDepth 카메라(ARFaceAnchor)로 얼굴을 잡고 → 그 자리에서 눈·얼굴형을 손으로 라벨링 →
라벨별 폴더에 저장합니다.

본 앱(Vultus / 상상이상)과 **완전히 분리된 별도 Xcode 프로젝트**입니다.
팀 레포에는 아무것도 넣지 않았으니 팀원들이 헷갈릴 일은 없습니다.

- 번들 ID: `com.ElenaLee.facedatasetcollector`
- 앱 이름: 얼굴 데이터
- 최소 버전: iOS 18.0 / iPhone · iPad (세로 고정)

iPad는 **TrueDepth(Face ID)가 있는 iPad Pro에서만** 얼굴 추적이 됩니다.
Air / mini / 일반 iPad는 설치는 되지만 안내 화면만 뜹니다.

코드가 어떻게 짜여 있는지는 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)를 보세요.

```bash
open /Users/jeonghee/Desktop/AppleDeveloperAcademy/C3/FaceDatasetCollector/FaceDatasetCollector.xcodeproj
```

## 쓰는 법

**실기기(TrueDepth 탑재)에서만 동작합니다. 시뮬레이터는 얼굴 추적을 지원하지 않습니다.**

1. 앱을 켜면 바로 수집 화면입니다.
2. 얼굴을 화면에 맞추면 `촬영 가능`으로 바뀝니다. (yaw/pitch/roll 12° 이내, 두 눈 다 뜬 상태)
3. 셔터 → 라벨링 시트에서 실제로 저장될 크롭을 보고 **왼쪽 눈 / 오른쪽 눈 / 얼굴형**을 각각 선택
   → `저장하고 다음 촬영`. (두 눈이 다른 모양일 수 있어 한쪽씩 고릅니다)
4. 사람이 바뀌면 왼쪽 위 `다음 사람`을 눌러 피험자 번호를 올립니다. (`S001` → `S002`)
5. 다 모았으면 폴더 아이콘 → `zip으로 내보내기` (AirDrop / 파일 앱).

파일 앱의 "나의 iPhone → 얼굴 데이터"에서도 폴더를 그대로 꺼낼 수 있습니다.

### 이미지 방향

기본값 `자동`은 ARKit이 **미리보기를 그릴 때 쓰는 변환**(`ARFrame.displayTransform`)에서
90° 단위 회전과 좌우반전을 되읽어 적용합니다. 화면에서 똑바로 보이는 그림이 그대로 저장되므로
전면 카메라의 센서 방향 규약을 추측할 필요가 없습니다.

그래도 첫 촬영에서 라벨링 화면의 크롭이 **똑바로 서 있는지** 한 번은 확인하세요.
어긋나면 `데이터셋 → 촬영 설정 → 이미지 방향`에서 고정 방향으로 덮어쓸 수 있습니다.
**중간에 바꾸면 방향이 섞이니 초반에 확인하세요.**

## 저장 구조

앱 Documents 아래 `FaceDataset/`:

```
images/eye/<라벨>/<uuid>_L.jpg                 왼쪽 눈 크롭 (눈 바운딩박스 2배 정사각형)
images/eye/<라벨>/<uuid>_R.jpg                 오른쪽 눈 크롭 — 왼쪽과 다른 라벨 폴더일 수 있음
images/faceShape/<라벨>/<uuid>.jpg             얼굴 크롭 (얼굴 바운딩박스 1.5배 정사각형)
raw/<uuid>.jpg                                 전체 프레임 원본
meta/<uuid>.json                               라벨 + 각도 + 블렌드셰이프 52종
geometry/<uuid>.bin                            얼굴 메시 1220정점 (Float32 x,y,z 리틀엔디안)
index.csv                                      한 줄 = 한 표본
```

**한 표본이 서로 다른 두 눈 클래스에 한 장씩 들어갈 수 있습니다.** 왼쪽/오른쪽 눈을 따로
라벨링하기 때문이고, 그게 맞습니다. 사람의 두 눈이 늘 같은 모양은 아닙니다.
`index.csv`에는 `leftEyeLabel`, `rightEyeLabel`이 각각 남습니다.
기기에 예전 열 구성(`eyeLabel` 하나)으로 쓰던 `index.csv`가 남아 있으면, 열 수가 다른 줄이
섞이지 않도록 `index-legacy-<시각>.csv`로 밀어 두고 새로 시작합니다. (사진·meta는 그대로입니다)

`roll`은 **중력 기준**입니다(0° = 고개가 똑바로 선 상태). 카메라 좌표계는 기기가 가로로 누운
상태를 기준으로 정의돼 있어서, 카메라 축 기준으로 재면 세로로 들고 찍을 때 항상 ±90°가 나옵니다.

## 본 앱(Vultus)과 맞춰야 하는 것 두 가지

이 앱은 별도 프로젝트라 코드를 공유하지 않습니다. 대신 아래 두 가지는 **손으로 맞춰야** 합니다.

### 1. 라벨 이름

`Core/Dataset/DatasetLabel.swift`의 `EyeLabel` / `FaceShapeLabel` rawValue는
본 앱의 `EyeShape.EyeType` / `FaceShape` rawValue와 같아야 합니다.
폴더 이름이 곧 CoreML 모델의 출력 레이블이 되고, 본 앱은 그 문자열로
`EyeShape.EyeType(label:)`을 만들기 때문입니다. 본 앱에 케이스를 추가하면 여기에도 추가하세요.

### 2. 크롭 규칙

`Core/Dataset/EyeCropper.swift`의 눈 크롭은 본 앱 `EyeReader`의 `crop(_:from:)`과
같은 규칙(랜드마크 바운딩박스의 2배 정사각형)입니다.
**한쪽만 바꾸면 학습 때와 추론 때 구도가 어긋나 정확도가 떨어집니다.**
바꿀 일이 생기면 양쪽을 같이 고치고, 이미 모은 데이터는 `raw/`에서 다시 자르세요.

## 학습

### Create ML (이미지 분류기)

zip을 풀면 `images/eye`, `images/faceShape`가 그대로 "폴더명 = 클래스명" 구조입니다.
Create ML → Image Classification → Training Data에 폴더를 끌어다 놓으면 됩니다.
본 앱의 `EyeShapeClassifier.mlmodel`을 이렇게 교체합니다.

**학습/검증을 자동 분할(Automatic)로 두지 마세요.** 같은 사람의 왼눈·오른눈이 양쪽에 나뉘어
들어가면 정확도가 실제보다 높게 나옵니다. `index.csv`의 `subjectID`로 **사람 단위로 나눠**
Training / Validation 폴더를 따로 만드세요.

```python
import pandas as pd
df = pd.read_csv("FaceDataset/index.csv")
subjects = df.subjectID.unique()
val = set(subjects[::5])          # 사람의 20%를 검증용으로
df["split"] = df.subjectID.map(lambda s: "val" if s in val else "train")
```

### 기하값으로 학습할 때

`geometry/<uuid>.bin`은 얼굴 앵커 로컬 좌표계(미터)라 **고개 방향이 이미 제거**돼 있습니다.
2D 랜드마크와 달리 촬영 각도에 값이 흔들리지 않아, 이미지 대신 수치로 분류기를 만들 수도 있습니다.

```python
import numpy as np
v = np.fromfile("FaceDataset/geometry/<uuid>.bin", dtype="<f4").reshape(-1, 3)  # (1220, 3)
```

`index.csv`의 `ipdMM`(동공간거리)으로 나누면 얼굴 크기 차이를 정규화할 수 있습니다.

## 수집할 때 유의할 것

- **클래스 균형**: 라이브러리 화면의 막대가 한쪽으로 기울면 모델이 많은 쪽으로만 답합니다.
  적은 라벨을 가진 사람을 우선 찾으세요.
- **자세 고정**: 각도가 제각각이면 모델이 얼굴이 아니라 자세를 배웁니다. 경고가 뜨면 다시 찍으세요.
- **라벨 일관성**: 같은 얼굴을 두 사람이 다르게 라벨링하면 그 클래스는 학습이 안 됩니다.
  기준 사진을 정해 두고 여럿이 나눠 찍기 전에 맞추세요.
- **한 사람당 여러 장**: 조명·거리를 바꿔 3~5장 찍되, `subjectID`는 반드시 같게 두세요.
- **개인정보**: 얼굴 사진입니다. 촬영 전 동의를 받고, 기기 밖으로 옮긴 뒤에는
  라이브러리 화면의 `전체 삭제`로 기기에서 지우세요.

## 코드 출처

`Core/FaceGeometry/`(ARFaceCaptureManager, FaceAnchorSnapshot)는 본 앱 작업 중이던
`Vultus/Core/FaceGeometry/`에서 복사해 왔습니다. 본 앱 쪽을 고치면 여기도 같이 보세요.

## 문서

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — 코드 구조. 실행 순서를 따라가며 설명합니다
- [`docs/learning/`](docs/learning/) — 날짜별 학습 기록
- [`docs/BACKLOG.md`](docs/BACKLOG.md) — 다음에 해볼 일
