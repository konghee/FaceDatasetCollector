//
//  SIMDHelpers.swift
//  FaceDatasetCollector
//

import simd

extension simd_float4x4 {
    /// transform의 평행이동 성분.
    var translation: SIMD3<Float> {
        SIMD3(columns.3.x, columns.3.y, columns.3.z)
    }
}

extension Float {
    /// ARKit은 미터를 쓰지만 인체계측 값은 밀리미터가 익숙하다.
    var inMillimeters: Float { self * 1000 }
}
