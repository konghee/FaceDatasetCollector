//
//  FaceDatasetStore.swift
//  FaceDatasetCollector
//

import Foundation

/// 촬영한 표본을 저장하고, 라벨이 붙으면 라벨별 폴더로 옮기고, 통째로 내보내는 저장소.
///
/// ## 폴더 구조 (앱 Documents/FaceDataset)
/// ```
/// pending/<id>_L.jpg, <id>_R.jpg, <id>_face.jpg  ← 아직 라벨이 없는 크롭
/// images/eye/<라벨>/<id>_L.jpg, <id>_R.jpg       ← 라벨이 붙으면 여기로 옮겨진다
/// images/faceShape/<라벨>/<id>.jpg               ← 〃
/// raw/<id>.jpg                                   ← 전체 프레임 (크롭 규칙 바꿀 때 재사용)
/// meta/<id>.json                                 ← 라벨 + 각도 + 블렌드셰이프 + 동의 시각
/// geometry/<id>.bin                              ← 얼굴 메시 1220정점 (Float32 x,y,z)
/// index.csv                                      ← 한 줄 = 한 표본
/// ```
///
/// "폴더명 = 클래스명"은 Create ML 이미지 분류기의 입력 규약이라,
/// 내보낸 `images/eye` 폴더를 Create ML 창에 그대로 끌어다 놓으면 학습이 시작된다.
///
/// ## 미분류 크롭을 `images/` 밖에 두는 이유
/// 같은 규약 때문이다. `images/eye/_unlabeled/`처럼 안쪽에 두면 Create ML이 그 폴더를
/// **10번째 눈 클래스로 학습해 버린다.** 라벨이 붙기 전까지는 `images/` 바깥에 둬야
/// 폴더를 통째로 끌어다 놓는 방식이 계속 안전하다.
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

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(root: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.root = root ?? documents.appending(path: "FaceDataset")
        self.indexURL = self.root.appending(path: "index.csv")
    }

    // MARK: - 저장

    /// 라벨 없이 한 표본을 디스크에 쓴다.
    ///
    /// 부스에서는 참여자가 앞에 서 있다. 여기서 눈 9종·얼굴형 5종을 고르게 하면 한 사람당
    /// 수십 초가 더 걸리고, 급하게 고른 라벨은 어차피 나중에 다시 봐야 한다.
    /// 그래서 촬영은 사진만 남기고, 라벨은 `applyLabels(to:...)`가 나중에 붙인다.
    @discardableResult
    func save(
        _ sample: PendingSample,
        subjectID: String,
        consentedAt: Date
    ) throws -> FaceSampleRecord {
        let name = sample.id.uuidString

        let fullFramePath = "raw/\(name).jpg"
        try write(sample.fullFrame, to: fullFramePath)

        let faceCropPath = try sample.faceCrop.map { data -> String in
            let path = "pending/\(name)_face.jpg"
            try write(data, to: path)
            return path
        }

        let leftPath = try sample.leftEyeCrop.map { data -> String in
            let path = "pending/\(name)_L.jpg"
            try write(data, to: path)
            return path
        }
        let rightPath = try sample.rightEyeCrop.map { data -> String in
            let path = "pending/\(name)_R.jpg"
            try write(data, to: path)
            return path
        }

        let verticesPath = "geometry/\(name).bin"
        try write(Self.encodeVertices(sample.vertices), to: verticesPath)

        let record = FaceSampleRecord(
            id: sample.id,
            capturedAt: sample.capturedAt,
            subjectID: subjectID,
            consentedAt: consentedAt,
            leftEyeLabel: nil,
            rightEyeLabel: nil,
            faceShapeLabel: nil,
            geometry: sample.geometry,
            fullFramePath: fullFramePath,
            faceCropPath: faceCropPath,
            leftEyeCropPath: leftPath,
            rightEyeCropPath: rightPath,
            verticesPath: verticesPath,
            deviceModel: Self.deviceModel,
            schemaVersion: FaceSampleRecord.currentSchemaVersion
        )

        try writeRecord(record)
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

    // MARK: - 라벨 붙이기

    /// 표본 여러 건에 같은 라벨을 붙이고, 크롭을 라벨 폴더로 옮긴다.
    ///
    /// 한 사람의 사진 여러 장을 한 번에 넘기는 것을 전제한다. 같은 사람의 눈 모양과
    /// 얼굴형은 사진이 바뀐다고 달라지지 않으므로, 사람당 한 번만 고르면 된다.
    ///
    /// 이미 라벨이 붙은 표본을 다시 넘기면 라벨을 **고친다.** 크롭은 예전 라벨 폴더에서
    /// 새 라벨 폴더로 옮겨 간다. 잘못 붙인 라벨을 되돌릴 길이 있어야 한다.
    func applyLabels(
        to ids: [UUID],
        leftEye: EyeLabel,
        rightEye: EyeLabel,
        faceShape: FaceShapeLabel
    ) throws {
        for id in ids {
            guard var record = loadRecord(id) else { continue }
            let name = id.uuidString

            record.leftEyeCropPath = try move(
                record.leftEyeCropPath,
                to: "images/\(EyeLabel.axisName)/\(leftEye.folderName)/\(name)_L.jpg"
            )
            record.rightEyeCropPath = try move(
                record.rightEyeCropPath,
                to: "images/\(EyeLabel.axisName)/\(rightEye.folderName)/\(name)_R.jpg"
            )
            record.faceCropPath = try move(
                record.faceCropPath,
                to: "images/\(FaceShapeLabel.axisName)/\(faceShape.folderName)/\(name).jpg"
            )

            record.leftEyeLabel = leftEye.folderName
            record.rightEyeLabel = rightEye.folderName
            record.faceShapeLabel = faceShape.folderName

            try writeRecord(record)
        }

        // 라벨이 바뀌면 이미 써 둔 CSV 줄의 내용이 틀려진다. 덧붙이기로는 고칠 수 없어
        // meta를 진실의 원본으로 삼아 통째로 다시 쓴다.
        try rebuildIndex()
    }

    /// 파일 한 개를 새 경로로 옮기고 새 상대 경로를 돌려준다.
    ///
    /// 원본이 없으면(이미 옮겨졌거나 Vision이 크롭을 못 만들었으면) 옮길 것이 없다.
    private func move(_ source: String?, to destination: String) throws -> String? {
        guard let source else { return nil }
        guard source != destination else { return destination }

        let from = root.appending(path: source)
        let to = root.appending(path: destination)

        guard FileManager.default.fileExists(atPath: from.path) else {
            return FileManager.default.fileExists(atPath: to.path) ? destination : nil
        }

        try FileManager.default.createDirectory(
            at: to.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: to)
        try FileManager.default.moveItem(at: from, to: to)
        return destination
    }

    // MARK: - 읽기

    /// 저장된 기록 전부. 촬영 시각 순으로 정렬해 돌려준다.
    ///
    /// 스키마가 다른 옛 기록은 건너뛴다. 한 건이 못 읽힌다고 목록 전체가 비면
    /// 남은 데이터를 라벨링할 길이 없어진다.
    func allRecords() -> [FaceSampleRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root.appending(path: "meta"),
            includingPropertiesForKeys: nil
        )) ?? []

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(FaceSampleRecord.self, from: data)
            }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    /// 라벨이 아직 안 붙은 표본을 사람별로 묶는다. 라벨링 대기 화면이 이걸 그린다.
    func unlabeledSubjects() -> [UnlabeledSubject] {
        Dictionary(grouping: allRecords().filter { !$0.isLabeled }, by: \.subjectID)
            .map { UnlabeledSubject(subjectID: $0.key, records: $0.value) }
            .sorted { $0.subjectID < $1.subjectID }
    }

    /// 크롭 한 장을 읽어 온다. 화면에 미리보기를 그릴 때 쓴다.
    func imageData(at relativePath: String) -> Data? {
        try? Data(contentsOf: root.appending(path: relativePath))
    }

    private func loadRecord(_ id: UUID) -> FaceSampleRecord? {
        guard let data = try? Data(contentsOf: metaURL(id)) else { return nil }
        return try? decoder.decode(FaceSampleRecord.self, from: data)
    }

    private func writeRecord(_ record: FaceSampleRecord) throws {
        try write(try encoder.encode(record), to: "meta/\(record.id.uuidString).json")
    }

    private func metaURL(_ id: UUID) -> URL {
        root.appending(path: "meta/\(id.uuidString).json")
    }

    // MARK: - index.csv

    private static let csvHeader = "id,capturedAt,subjectID,consentedAt,leftEyeLabel,rightEyeLabel,faceShapeLabel,yaw,pitch,roll,ipdMM,opennessL,opennessR,device\n"

    /// 표본 한 건을 CSV 한 줄로. 라벨이 아직 없으면 그 칸은 빈 문자열이다.
    ///
    /// 사람 단위 split, 각도 분포 확인 같은 작업은 JSON 1000개를 여는 것보다
    /// CSV 한 장을 pandas로 읽는 편이 훨씬 빠르다.
    private static func csvLine(_ record: FaceSampleRecord) -> String {
        let iso = ISO8601DateFormatter()
        return [
            record.id.uuidString,
            iso.string(from: record.capturedAt),
            record.subjectID,
            iso.string(from: record.consentedAt),
            record.leftEyeLabel ?? "",
            record.rightEyeLabel ?? "",
            record.faceShapeLabel ?? "",
            String(format: "%.2f", record.geometry.yaw),
            String(format: "%.2f", record.geometry.pitch),
            String(format: "%.2f", record.geometry.roll),
            String(format: "%.2f", record.geometry.interpupillaryDistance),
            String(format: "%.3f", record.geometry.leftEyeOpenness),
            String(format: "%.3f", record.geometry.rightEyeOpenness),
            record.deviceModel,
        ].joined(separator: ",") + "\n"
    }

    /// 촬영 직후에는 줄 하나만 덧붙인다. 표본이 수백 건이어도 셔터가 느려지지 않는다.
    private func appendToIndex(_ record: FaceSampleRecord) throws {
        // 스키마가 바뀐 뒤에도 그냥 이어 쓰면 열 수가 다른 줄이 한 파일에 섞여 통째로 못 읽는다.
        // 헤더가 다르면 예전 파일을 옆으로 밀어 두고 새로 시작한다. (사진과 meta는 그대로 남는다)
        if FileManager.default.fileExists(atPath: indexURL.path), try !hasCurrentHeader() {
            try FileManager.default.moveItem(
                at: indexURL,
                to: root.appending(path: "index-legacy-\(Int(Date().timeIntervalSince1970)).csv")
            )
        }

        let line = Self.csvLine(record)

        if FileManager.default.fileExists(atPath: indexURL.path) {
            let handle = try FileHandle(forWritingTo: indexURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } else {
            try write(Data((Self.csvHeader + line).utf8), to: "index.csv")
        }
    }

    /// meta 전체에서 CSV를 다시 만든다. 라벨을 붙이거나 표본을 지운 뒤에 부른다.
    func rebuildIndex() throws {
        let rows = allRecords().map(Self.csvLine).joined()
        try write(Data((Self.csvHeader + rows).utf8), to: "index.csv")
    }

    private func hasCurrentHeader() throws -> Bool {
        let handle = try FileHandle(forReadingFrom: indexURL)
        defer { try? handle.close() }
        return try handle.read(upToCount: Self.csvHeader.utf8.count) == Data(Self.csvHeader.utf8)
    }

    // MARK: - 집계

    /// 라벨별 장수. 어떤 클래스가 모자라는지 보고 다음 촬영을 정하라고 화면에 띄운다.
    ///
    /// 막대는 **라벨이 붙은 사진만** 센다. 미분류가 쌓여 있으면 균형은 아직 알 수 없으므로,
    /// 미분류 장수를 따로 돌려줘 화면에서 같이 보여 준다.
    func stats() -> DatasetStats {
        let unlabeled = allRecords().filter { !$0.isLabeled }

        return DatasetStats(
            eyeCounts: counts(axis: EyeLabel.axisName, labels: EyeLabel.allCases.map(\.folderName)),
            faceShapeCounts: counts(axis: FaceShapeLabel.axisName, labels: FaceShapeLabel.allCases.map(\.folderName)),
            totalSamples: (try? FileManager.default.contentsOfDirectory(
                at: root.appending(path: "meta"),
                includingPropertiesForKeys: nil
            ).count) ?? 0,
            unlabeledSamples: unlabeled.count,
            unlabeledSubjects: Set(unlabeled.map(\.subjectID)).count
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

    /// 표본 몇 건을 지운다. 잘못 찍힌 사진을 라벨링하다 골라내는 용도다.
    func delete(ids: [UUID]) throws {
        for id in ids {
            if let record = loadRecord(id) {
                let paths = [
                    record.fullFramePath,
                    record.verticesPath,
                    record.faceCropPath,
                    record.leftEyeCropPath,
                    record.rightEyeCropPath,
                ].compactMap { $0 }

                for path in paths {
                    try? FileManager.default.removeItem(at: root.appending(path: path))
                }
            }

            try? FileManager.default.removeItem(at: metaURL(id))
        }

        try rebuildIndex()
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

    /// 아직 라벨이 안 붙은 장수와 사람 수. 수집 화면과 데이터셋 화면에 같이 띄운다.
    var unlabeledSamples: Int = 0
    var unlabeledSubjects: Int = 0
}

/// 라벨링을 기다리는 한 사람. 사진 여러 장이 한 묶음으로 뜬다.
///
/// 사람 단위로 묶는 이유는 라벨이 사람의 속성이기 때문이다. 같은 사람을 세 장 찍었으면
/// 눈 모양도 얼굴형도 세 장 모두 같다. 장당 고르면 같은 답을 세 번 고르게 된다.
nonisolated struct UnlabeledSubject: Identifiable, Sendable {
    var id: String { subjectID }

    let subjectID: String

    /// 이 사람의 미분류 표본. 촬영 시각 순이다.
    let records: [FaceSampleRecord]

    var count: Int { records.count }

    var capturedAt: Date? { records.first?.capturedAt }
}

enum DatasetStoreError: LocalizedError {
    case empty

    var errorDescription: String? {
        "아직 저장된 표본이 없습니다."
    }
}
