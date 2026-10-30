import Foundation
import SwiftData

/// Ролик в библиотеке — стопка версий одного и того же монтажа/шота.
@Model
final class LibraryItem {
    var title: String
    var createdAt: Date
    /// Когда добавили последнюю версию — по нему сортируется библиотека.
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ReviewVideo.item)
    var versions: [ReviewVideo] = []

    init(title: String) {
        self.title = title
        createdAt = .now
        updatedAt = .now
    }

    var sortedVersions: [ReviewVideo] {
        versions.sorted { $0.versionNumber < $1.versionNumber }
    }

    var latest: ReviewVideo? { sortedVersions.last }
    var nextVersionNumber: Int { (versions.map(\.versionNumber).max() ?? 0) + 1 }
    var openCommentCount: Int { versions.reduce(0) { $0 + $1.openCommentCount } }
}
