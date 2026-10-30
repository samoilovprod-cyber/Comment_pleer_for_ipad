import Foundation

/// Комментарий к кадру. Пока живёт только в памяти — сохранение в SwiftData на этапе 3.
struct ReviewComment: Identifiable, Hashable {
    let id = UUID()
    let frame: Int
    var text: String
    let createdAt = Date()
}
