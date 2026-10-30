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

/// Комментарий к кадру: номер кадра (не тайм-код — он может поменяться), текст и статус.
@Model
final class ReviewComment {
    var frame: Int
    var text: String
    var createdAt: Date
    var editedAt: Date?
    var isResolved: Bool
    var video: ReviewVideo?

    init(frame: Int, text: String) {
        self.frame = frame
        self.text = text
        createdAt = .now
        isResolved = false
    }
}
