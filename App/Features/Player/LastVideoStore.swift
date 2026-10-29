import Foundation

/// Помнит последнее открытое видео, чтобы открыть его после перезапуска.
/// Для файлов из «Файлов» закладка хранит доступ security-scoped; копии из «Фото» лежат в Application Support.
enum LastVideoStore {
    private static let bookmarkKey = "lastVideo.bookmark"
    private static let isImportedCopyKey = "lastVideo.isImportedCopy"

    static func save(url: URL, isImportedCopy: Bool) {
        guard let bookmark = try? url.bookmarkData() else { return }
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(isImportedCopy, forKey: isImportedCopyKey)
    }

    static func load() -> (url: URL, isImportedCopy: Bool)? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else {
            clear()
            return nil
        }
        let isImportedCopy = UserDefaults.standard.bool(forKey: isImportedCopyKey)
        if isStale {
            save(url: url, isImportedCopy: isImportedCopy)
        }
        return (url, isImportedCopy)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: isImportedCopyKey)
    }
}
