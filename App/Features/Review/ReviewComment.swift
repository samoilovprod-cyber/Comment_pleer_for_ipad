import Foundation
import SwiftData

/// Видео, к которому пишутся комментарии. Узнаём файл по имени и числу кадров —
/// так комментарии находятся и для копии из «Фото», и для того же файла из «Файлов».
@Model
final class ReviewVideo {
    var fileKey: String
    var fileName: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ReviewComment.video)
    var comments: [ReviewComment] = []

    init(fileKey: String, fileName: String) {
        self.fileKey = fileKey
        self.fileName = fileName
        createdAt = .now
    }

    static func key(fileName: String, frameCount: Int) -> String {
        "\(fileName)#\(frameCount)"
    }
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
    var video: ReviewVideo?

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
