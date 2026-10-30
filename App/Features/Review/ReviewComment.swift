import Foundation
import SwiftData

/// Одна версия ролика в библиотеке — конкретный файл со своими комментариями.
/// `fileKey` (имя + число кадров) нужен, чтобы узнать файл, у которого уже есть комментарии.
@Model
final class ReviewVideo {
    var fileKey: String
    var fileName: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ReviewComment.video)
    var comments: [ReviewComment] = []

    /// Ролик, к которому относится версия; nil — запись из прошлых версий приложения (до библиотеки).
    var item: LibraryItem?
    /// Номер версии внутри ролика: v1, v2…
    var versionNumber: Int = 1
    /// Security-scoped закладка на файл из «Файлов».
    var bookmark: Data?
    /// Копия из «Фото» — путь относительно Application Support (абсолютный меняется при переустановке).
    var importedPath: String?
    @Attribute(.externalStorage) var thumbnailData: Data?
    var frameCount: Int = 0
    var frameRateLabel: String = ""
    var durationLabel: String = ""

    init(fileKey: String, fileName: String) {
        self.fileKey = fileKey
        self.fileName = fileName
        createdAt = .now
    }

    static func key(fileName: String, frameCount: Int) -> String {
        "\(fileName)#\(frameCount)"
    }

    var versionLabel: String { "v\(versionNumber)" }
    var openCommentCount: Int { comments.filter { !$0.isResolved }.count }
    var hasFile: Bool { bookmark != nil || importedPath != nil }
}

/// Цех, которому адресован комментарий.
enum Department: String, CaseIterable, Identifiable {
    case edit, snd, cg, di, cc

    var id: String { rawValue }
    /// Короткая метка на плашке.
    var label: String { rawValue.uppercased() }
    var title: String {
        switch self {
        case .edit: "Edit"
        case .snd: "Sound"
        case .cg: "CG / VFX"
        case .di: "DI"
        case .cc: "Color Correction"
        }
    }
}

/// Комментарий к кадру: номер кадра (не тайм-код — он может поменяться), текст, цех и статус.
@Model
final class ReviewComment {
    var frame: Int
    var text: String
    var createdAt: Date
    var editedAt: Date?
    var isResolved: Bool
    /// `Department.rawValue`; nil — цех не назначен.
    var departmentRaw: String?
    /// Пометки на кадре (`Annotation` в JSON); nil — без рисунка.
    @Attribute(.externalStorage) var annotationData: Data?
    var video: ReviewVideo?
    /// Общий id замечания во всех версиях: копия в новой версии получает id оригинала,
    /// так одно и то же замечание не переносится дважды.
    var originID: String?
    /// Из какой версии перенесено (номер); nil — написано в этой версии.
    var carriedFromVersion: Int?

    var annotation: Annotation? {
        get { annotationData.flatMap(Annotation.decode) }
        set { annotationData = newValue.flatMap { $0.isEmpty ? nil : $0.encoded() } }
    }

    var hasAnnotation: Bool { annotationData != nil }

    var department: Department? {
        get { departmentRaw.flatMap(Department.init(rawValue:)) }
        set { departmentRaw = newValue?.rawValue }
    }

    init(frame: Int, text: String, department: Department? = nil) {
        self.frame = frame
        self.text = text
        departmentRaw = department?.rawValue
        createdAt = .now
        isResolved = false
    }
}
