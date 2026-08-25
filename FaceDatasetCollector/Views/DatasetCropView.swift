//
//  DatasetCropView.swift
//  FaceDatasetCollector
//

import SwiftUI
import UIKit

/// 디스크에 저장된 크롭 한 장을 읽어 보여 준다.
///
/// 라벨링은 촬영이 다 끝난 뒤에 하므로, 그릴 그림이 메모리에 없고 파일로만 있다.
/// 저장소가 액터라 읽기가 비동기여서, 뷰가 스스로 읽어 오는 편이 호출부보다 간단하다.
/// 목록에서 수십 장이 한꺼번에 보이는데 `.task`는 화면에 실제로 뜬 행만 실행한다.
struct DatasetCropView: View {
    let path: String?
    var side: CGFloat
    var cornerRadius: CGFloat = 10

    @State private var data: Data?

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // 경로가 없으면 Vision이 크롭을 못 만든 것이고, 경로가 있는데 못 읽으면
                // 아직 읽는 중이다. 둘을 구분해야 "다시 찍어야 하는 사진"을 알아본다.
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: path == nil ? "xmark" : "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: path) {
            guard let path else {
                data = nil
                return
            }
            data = await FaceDatasetStore.shared.imageData(at: path)
        }
    }
}
