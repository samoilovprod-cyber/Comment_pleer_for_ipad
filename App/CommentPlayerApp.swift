import SwiftData
import SwiftUI

@main
struct CommentPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // Интерфейс на английском независимо от языка устройства (даты, «2 minutes ago» и т.п.).
                .environment(\.locale, Locale(identifier: "en_US"))
        }
        .modelContainer(for: [LibraryItem.self, ReviewVideo.self, ReviewComment.self])
    }
}
