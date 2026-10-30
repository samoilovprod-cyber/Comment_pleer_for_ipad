import SwiftData
import SwiftUI

/// Экраны поверх библиотеки.
enum Route: Hashable {
    case versions(PersistentIdentifier)
    case player(PersistentIdentifier)
    case compare(PersistentIdentifier, PersistentIdentifier)
}

@MainActor
final class Router: ObservableObject {
    @Published var path: [Route] = []

    func open(_ video: ReviewVideo) {
        path.append(.player(video.persistentModelID))
    }

    func compare(_ a: ReviewVideo, _ b: ReviewVideo) {
        path.append(.compare(a.persistentModelID, b.persistentModelID))
    }
}

/// Библиотека, из неё — версии, плеер и сравнение. После перезапуска открывается последний плеер.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var router = Router()
    /// Последняя открытая версия (PersistentIdentifier в JSON).
    @AppStorage("library.lastVideo") private var lastVideoData = Data()
    @State private var isRestored = false

    var body: some View {
        NavigationStack(path: $router.path) {
            LibraryScreen()
                .navigationDestination(for: Route.self, destination: destination)
        }
        .environmentObject(router)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .task {
            guard !isRestored else { return }
            isRestored = true
            let migrated = MediaLibrary.migrateLegacyVideos(context: modelContext)
            if let video = migrated ?? lastVideo() {
                router.open(video)
            }
        }
        .onChange(of: router.path) { _, path in
            guard case let .player(id) = path.last else { return }
            lastVideoData = (try? JSONEncoder().encode(id)) ?? Data()
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case let .versions(id):
            if let item = model(LibraryItem.self, id) {
                VersionsScreen(item: item)
            }
        case let .player(id):
            if let video = model(ReviewVideo.self, id) {
                PlayerScreen(video: video)
            }
        case let .compare(a, b):
            if let a = model(ReviewVideo.self, a), let b = model(ReviewVideo.self, b) {
                CompareScreen(a: a, b: b)
            }
        }
    }

    private func model<T: PersistentModel>(_ type: T.Type, _ id: PersistentIdentifier) -> T? {
        // model(for:) отдаёт «пустышку» и для удалённой записи — ищем честным запросом.
        var descriptor = FetchDescriptor<T>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func lastVideo() -> ReviewVideo? {
        guard let id = try? JSONDecoder().decode(PersistentIdentifier.self, from: lastVideoData),
              let video = model(ReviewVideo.self, id), video.item != nil else { return nil }
        return video
    }
}
