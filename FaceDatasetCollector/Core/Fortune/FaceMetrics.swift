//
//  FaceMetrics.swift
//  FaceDatasetCollector
//

import simd

/// 얼굴 메시에서 뽑은, **표정과 자세에 흔들리지 않는** 비율 지표.
///
/// ## 왜 이 값들만 쓰나
/// 같은 사람이 다시 찍었을 때 같은 신분이 나와야 재미가 성립한다. 그래서 판정에는
/// 촬영할 때마다 달라지는 값을 쓰면 안 된다.
///
/// - 쓰는 것: `anchor.geometry.vertices` — **얼굴 앵커 로컬 좌표**라 고개 방향이 이미
///   제거돼 있다. 미터 단위이고, 웃거나 고개를 돌려도 골격 비율은 거의 그대로다.
/// - 안 쓰는 것: `blendShapes`(표정), `headPose`(촬영 자세). 웃기만 해도 값이 바뀐다.
///
/// 모든 값은 **얼굴 너비로 나눈 비율**이라 얼굴이 크든 작든, 카메라에서 멀든 가깝든
/// 같은 사람이면 같은 값이 나온다.
nonisolated struct FaceMetrics: Sendable, Equatable {

    /// 얼굴 너비 (mm). 성인은 대략 130~160mm.
    let widthMM: Float

    /// 얼굴 높이 (mm).
    let heightMM: Float

    /// 동공간거리 (mm). 성인은 대략 55~70mm.
    let ipdMM: Float

    /// 세로/가로.
    ///
    /// - Warning: **사람이 달라져도 거의 안 변한다** (실측 1.201 vs 1.198). ARKit 얼굴 메시는
    ///   표정 추적용이라 정해진 형태를 거의 균일하게 확대·축소해 맞춘다. 그래서 비율은 고정에
    ///   가깝고 **크기만 사람마다 다르다.** 판정 축으로 쓰지 말 것.
    let aspectRatio: Float

    /// 앞뒤 깊이/가로. 클수록 이목구비가 입체적이다.
    let depthRatio: Float

    /// 동공간거리/가로.
    ///
    /// - Warning: 눈이 넓은 사람은 얼굴도 큰 경향이라, 너비로 나누면 차이가 상쇄된다
    ///   (실측 0.414 vs 0.407). 눈 간격을 보려면 `ipdMM`을 그대로 쓸 것.
    let eyeSpacing: Float

    /// 아래 1/3 폭 / 위 1/3 폭. 1보다 크면 턱이 발달했고, 작으면 갸름하게 좁아진다.
    ///
    /// - Warning: **떨림이 심해 판정에 쓸 수 없다.** 같은 사람을 재는 동안 ±0.021까지
    ///   흔들렸는데, 이는 서로 다른 두 측정의 차이(0.038)와 맞먹는다. 실제로 이 값이
    ///   기준선에 걸터앉으면서 같은 사람이 장군과 암행어사를 오갔다.
    ///   구간 경계에 걸친 정점이 프레임마다 들락거리는 게 원인이다.
    let jawRatio: Float

    // MARK: - 삼정(三停)

    /// 하정 비율. 코끝부터 턱끝까지가 얼굴 전체 높이에서 차지하는 몫.
    ///
    /// 관상에서 얼굴을 이마(상정)·중안(중정)·하관(하정)으로 나누는 그 삼정이다.
    /// 바운딩 박스와 달리 **턱끝·코끝이라는 뚜렷한 한 점**을 기준으로 삼으므로,
    /// 경계에 걸친 정점이 드나들며 생기는 떨림이 없다.
    let lowerThirdRatio: Float

    /// 코가 얼굴 평면에서 앞으로 나온 정도를 너비로 나눈 값.
    let noseProjection: Float

    /// - Parameters:
    ///   - vertices: 얼굴 로컬 좌표 정점 (미터)
    ///   - interpupillaryDistanceMM: 동공간거리 (밀리미터)
    init?(vertices: [SIMD3<Float>], interpupillaryDistanceMM: Float) {
        guard vertices.count > 2 else { return nil }

        var minimum = vertices[0]
        var maximum = vertices[0]
        for vertex in vertices {
            minimum = simd_min(minimum, vertex)
            maximum = simd_max(maximum, vertex)
        }

        let size = maximum - minimum
        // 얼굴을 못 잡은 프레임에서 0에 가까운 폭이 들어오면 비율이 발산한다.
        guard size.x > 0.01 else { return nil }

        widthMM = size.x * 1000
        heightMM = size.y * 1000
        ipdMM = interpupillaryDistanceMM

        aspectRatio = size.y / size.x
        depthRatio = size.z / size.x
        eyeSpacing = (interpupillaryDistanceMM / 1000) / size.x

        // 턱과 이마 근처만 따로 재려면 정점 인덱스를 알아야 하는데, ARKit은 그 의미를
        // 공개하지 않는다. 대신 높이를 3등분해 아래·위 구간의 좌우 폭을 비교한다.
        // 인덱스에 의존하지 않으므로 ARKit이 메시를 바꿔도 깨지지 않는다.
        let lowerBound = minimum.y + size.y / 3
        let upperBound = maximum.y - size.y / 3

        let lowerWidth = Self.horizontalSpan(of: vertices) { $0.y < lowerBound }
        let upperWidth = Self.horizontalSpan(of: vertices) { $0.y > upperBound }

        jawRatio = upperWidth > 0.001 ? lowerWidth / upperWidth : 1

        // 코끝은 얼굴에서 가장 앞으로 나온 한 점이라 프레임이 바뀌어도 같은 자리를 짚는다.
        // 구간 경계로 정점을 나누는 방식과 달리 떨림이 생길 여지가 없다.
        var noseTip = vertices[0]
        for vertex in vertices where vertex.z > noseTip.z {
            noseTip = vertex
        }

        lowerThirdRatio = (noseTip.y - minimum.y) / size.y

        let meanZ = vertices.reduce(Float.zero) { $0 + $1.z } / Float(vertices.count)
        noseProjection = (noseTip.z - meanZ) / size.x
    }

    private static func horizontalSpan(
        of vertices: [SIMD3<Float>],
        where predicate: (SIMD3<Float>) -> Bool
    ) -> Float {
        var minimumX = Float.greatestFiniteMagnitude
        var maximumX = -Float.greatestFiniteMagnitude

        for vertex in vertices where predicate(vertex) {
            minimumX = min(minimumX, vertex.x)
            maximumX = max(maximumX, vertex.x)
        }

        return maximumX > minimumX ? maximumX - minimumX : 0
    }
}
