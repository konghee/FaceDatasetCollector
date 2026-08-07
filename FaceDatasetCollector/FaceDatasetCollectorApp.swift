//
//  FaceDatasetCollectorApp.swift
//  FaceDatasetCollector
//

// 관상 모델(눈 9종 / 얼굴형 5종) 학습용 얼굴 데이터를 모으는 수집 전용 앱.
// 본 앱(Vultus)과는 완전히 분리된 별도 프로젝트다.

import SwiftUI

@main
struct FaceDatasetCollectorApp: App {
    var body: some Scene {
        WindowGroup {
            DatasetCollectionView()
        }
    }
}
