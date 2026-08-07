//
//  FaceDatasetStore.swift
//  FaceDatasetCollector
//

import Foundation

/// 촬영한 표본을 라벨별 폴더로 저장하고, 통째로 내보내는 저장소.
///
/// ## 폴더 구조 (앱 Documents/FaceDataset)
/// ```
/// images/eye/<라벨>/<id>_L.jpg, <id>_R.jpg   ← Create ML 이미지 분류기에 그대로 투입
/// images/faceShape/<라벨>/<id>.jpg           ← 〃
/// raw/<id>.jpg                               ← 전체 프레임 (크롭 규칙 바꿀 때 재사용)
/// meta/<id>.json                             ← 라벨 + 각도 + 블렌드셰이프
/// geometry/<id>.bin                          ← 얼굴 메시 1220정점 (Float32 x,y,z)
/// index.csv                                  ← 한 줄 = 한 표본
/// ```
///
/// "폴더명 = 클래스명"은 Create ML 이미지 분류기의 입력 규약이라,
/// 내보낸 `images/eye` 폴더를 Create ML 창에 그대로 끌어다 놓으면 학습이 시작된다.
///
/// 파일 I/O를 액터로 격리해 촬영 중 메인 스레드가 디스크에서 막히지 않게 한다.
actor FaceDatasetStore {

    static let shared = FaceDatasetStore()

    let root: URL

    private let indexURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(root: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.root = root ?? documents.appending(path: "FaceDataset")
        self.indexURL = self.root.appending(path: "index.csv")
    }

    // MARK: - 저장

    /// 라벨을 붙여 한 표본을 디스크에 쓴다.
    ///
    /// 좌·우 눈은 각자의 라벨 폴더로 들어간다. 한 표본이 서로 다른 두 클래스에 한 장씩
    /// 기여할 수 있고, 그게 맞다. 사람의 두 눈이 늘 같은 모양은 아니다.
    @discardableResult
    func save(
        _ sample: PendingSample,
        leftEye: EyeLabel,
        rightEye: EyeLabel,
        faceShape: FaceShapeLabel,
        subjectID: String
    ) throws -> FaceSampleRecord {
        let name = sample.id.uuidString

        let fullFramePath = "raw/\(name).jpg"
        try write(sample.fullFrame, to: fullFramePath)

        let faceCropPath = try sample.faceCrop.map { data -> String in
            let path = "images/\(FaceShapeLabel.axisName)/\(faceShape.folderName)/\(name).jpg"
            try write(data, to: path)
            return path
        }

        let leftPath = try sample.leftEyeCrop.map { data -> String in
            let path = "images/\(EyeLabel.axisName)/\(leftEye.folderName)/\(name)_L.jpg"
            try write(data, to: path)
            return path
        }
        let rightPath = try sample.rightEyeCrop.map { data -> String in
            let path = "images/\(EyeLabel.axisName)/\(rightEye.folderName)/\(name)_R.jpg"
            try write(data, to: path)
            return path
        }

        let verticesPath = "geometry/\(name).bin"
        try write(Self.encodeVertices(sample.vertices), to: verticesPath)

        let record = FaceSampleRecord(
            id: sample.id,
            capturedAt: sample.capturedAt,
            subjectID: subjectID,
            leftEyeLabel: leftEye.folderName,
            rightEyeLabel: rightEye.folderName,
            faceShapeLabel: faceShape.folderName,
            geometry: sample.geometry,
            fullFramePath: fullFramePath,
            faceCropPath: faceCropPath,
            leftEyeCropPath: leftPath,
            rightEyeCropPath: rightPath,
            verticesPath: verticesPath,
            deviceModel: Self.deviceModel,
            schemaVersion: FaceSampleRecord.currentSchemaVersion
        )

        try write(try encoder.encode(record), to: "meta/\(name).json")
        try appendToIndex(record)

        return record
    }

    /// 정점을 x,y,z 순서의 Float32 리틀엔디안으로 눕힌다.
    ///
    /// JSON으로 1220개를 담으면 표본당 50KB가 넘는다. 바이너리로 두면 14KB이고,
    /// 파이썬에서 `np.fromfile(path, dtype='<f4').reshape(-1, 3)` 한 줄로 읽힌다.
    private static func encodeVertices(_ vertices: [SIMD3<Float>]) -> Data {
        var data = Data(capacity: vertices.count * 3 * 4)
        for vertex in vertices {
            for value in [vertex.x, vertex.y, vertex.z] {
                withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            }
        }
        return data
    }

    private func write(_ data: Data, to relativePath: String) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// 표본 한 건을 CSV 한 줄로 덧붙인다.
    ///
    /// 사람 단위 split, 각도 분포 확인 같은 작업은 JSON 1000개를 여는 것보다
    /// CSV 한 장을 pandas로 읽는 편이 훨씬 빠르다.
    private func appendToIndex(_ record: FaceSampleRecord) throws {
        let header = "id,capturedAt,subjectID,leftEyeLabel,rightEyeLabel,faceShapeLabel,yaw,pitch,roll,ipdMM,opennessL,opennessR,device\n"
        let line = [
            record.id.uuidString,
            ISO8601DateFormatter().string(from: record.capturedAt),
            record.subjectID,
            record.leftEyeLabel,
            record.rightEyeLabel,
            record.faceShapeLabel,
            String(format: "%.2f", record.geometry.yaw),
            String(format: "%.2f", record.geometry.pitch),
            String(format: "%.2f", record.geometry.roll),
            String(format: "%.2f", record.geometry.interpupillaryDistance),
            String(format: "%.3f", record.geometry.leftEyeOpenness),
            String(format: "%.3f", record.geometry.rightEyeOpenness),
            record.deviceModel,
        ].joined(separator: ",") + "\n"

        // 스키마가 바뀐 뒤에도 그냥 이어 쓰면 열 수가 다른 줄이 한 파일에 섞여 통째로 못 읽는다.
        // 헤더가 다르면 예전 파일을 옆으로 밀어 두고 새로 시작한다. (사진과 meta는 그대로 남는다)
        if FileManager.default.fileExists(atPath: indexURL.path), try !hasCurrentHeader(header) {
            try FileManager.default.moveItem(
                at: indexURL,
                to: root.appending(path: "index-legacy-\(Int(Date().timeIntervalSince1970)).csv")
            )
        }

        if FileManager.default.fileExists(atPath: indexURL.path) {
            let handle = try FileHandle(forWritingTo: indexURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } else {
            try write(Data((header + line).utf8), to: "index.csv")
        }
    }

    private func hasCurrentHeader(_ header: String) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: indexURL)
        defer { try? handle.close() }
        return try handle.read(upToCount: header.utf8.count) == Data(header.utf8)
    }

    // MARK: - 집계

    /// 라벨별 장수. 어떤 클래스가 모자라는지 보고 다음 촬영을 정하라고 화면에 띄운다.
    func stats() -> DatasetStats {
        DatasetStats(
            eyeCounts: counts(axis: EyeLabel.axisName, labels: EyeLabel.allCases.map(\.folderName)),
            faceShapeCounts: counts(axis: FaceShapeLabel.axisName, labels: FaceShapeLabel.allCases.map(\.folderName)),
            totalSamples: (try? FileManager.default.contentsOfDirectory(
                at: root.appending(path: "meta"),
                includingPropertiesForKeys: nil
            ).count) ?? 0
        )
    }

    private func counts(axis: String, labels: [String]) -> [String: Int] {
        labels.reduce(into: [:]) { result, label in
            let url = root.appending(path: "images/\(axis)/\(label)")
            let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            result[label] = files.count
        }
    }

    // MARK: - 내보내기 / 삭제

    /// 데이터셋 폴더를 zip 하나로 묶어 임시 파일 경로를 돌려준다.
    ///
    /// `NSFileCoordinator`의 `.forUploading`은 폴더를 zip으로 압축해 준다.
    /// (Foundation에 공개 zip API가 없어 쓰는, iOS에서 표준적인 방법이다.)
    func exportArchive() throws -> URL {
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw DatasetStoreError.empty
        }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "FaceDataset-\(stamp).zip")

        var coordinatorError: NSError?
        var copyError: Error?

        NSFileCoordinator().coordinate(
            readingItemAt: root,
            options: [.forUploading],
            error: &coordinatorError
        ) { zippedURL in
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zippedURL, to: destination)
            } catch {
                copyError = error
            }
        }

        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        return destination
    }

    func deleteAll() throws {
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        let identifier = withUnsafeBytes(of: &info.machine) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return identifier
    }
}

// MARK: - 부속 타입

struct DatasetStats: Sendable {
    var eyeCounts: [String: Int] = [:]
    var faceShapeCounts: [String: Int] = [:]
    var totalSamples: Int = 0
}

enum DatasetStoreError: LocalizedError {
    case empty

    var errorDescription: String? {
        "아직 저장된 표본이 없습니다."
    }
}
