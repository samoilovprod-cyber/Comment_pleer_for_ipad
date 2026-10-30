import AVFoundation
import FrameTimecode
import SwiftData
import UIKit

/// Файлы библиотеки: добавление видео, доступ к ним после перезапуска, удаление копий.
@MainActor
enum MediaLibrary {
    enum LibraryError: LocalizedError {
        case fileMissing(String)

        var errorDescription: String? {
            switch self {
            case let .fileMissing(name): "“\(name)” can't be found. Relink it from the library."
            }
        }
    }

    /// Открытый доступ к файлу версии; `stop()` — закрыть доступ, когда файл больше не нужен.
    struct FileAccess {
        let url: URL
        fileprivate let isScoped: Bool

        func stop() {
            if isScoped { url.stopAccessingSecurityScopedResource() }
        }
    }

    private static var importedRoot: URL { URL.applicationSupportDirectory }

    /// Добавляет файл в библиотеку: новым роликом (`item == nil`) или следующей версией ролика.
    /// Если у файла уже есть комментарии с прошлых запусков — они переходят в библиотеку вместе с ним.
    static func addVideo(url: URL, isImportedCopy: Bool, to item: LibraryItem?,
                         context: ModelContext) async throws -> ReviewVideo {
        let isScoped = !isImportedCopy && url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let info = try await VideoTimecodeReader.read(from: asset)
        let key = ReviewVideo.key(fileName: url.lastPathComponent, frameCount: info.frameCount)

        let existing = try? context.fetch(FetchDescriptor<ReviewVideo>(predicate: #Predicate { $0.fileKey == key })).first
        // Тот же файл уже лежит в библиотеке — не дублируем, просто обновляем путь к нему.
        let video = existing ?? ReviewVideo(fileKey: key, fileName: url.lastPathComponent)
        if existing == nil { context.insert(video) }

        if isImportedCopy {
            removeImportedCopy(of: video)
            video.importedPath = relativeImportedPath(of: url)
            video.bookmark = nil
        } else {
            video.bookmark = try url.bookmarkData()
            video.importedPath = nil
        }
        await updateMetadata(of: video, asset: asset, info: info)

        if video.item == nil {
            let target = item ?? {
                let created = LibraryItem(title: (url.lastPathComponent as NSString).deletingPathExtension)
                context.insert(created)
                return created
            }()
            let previous = target.latest
            video.versionNumber = target.nextVersionNumber
            video.item = target
            target.updatedAt = .now
            // Открытые замечания переезжают в новую версию — там их и проверяют.
            if let previous {
                carryComments(from: previous, to: video, includeResolved: false, context: context)
            }
        }
        try context.save()
        return video
    }

    /// Копирует замечания одной версии в другую на те же кадры (вместе с цехом и рисунком).
    /// Уже перенесённые раньше не дублируются. Возвращает число скопированных.
    @discardableResult
    static func carryComments(from source: ReviewVideo, to target: ReviewVideo, includeResolved: Bool,
                              context: ModelContext) -> Int {
        let alreadyThere = Set(target.comments.compactMap(\.originID))
        let lastFrame = max(target.frameCount - 1, 0)
        var count = 0
        for comment in source.comments.sorted(by: { $0.createdAt < $1.createdAt })
        where includeResolved || !comment.isResolved {
            let origin = comment.originID ?? UUID().uuidString
            comment.originID = origin
            guard !alreadyThere.contains(origin) else { continue }
            let copy = ReviewComment(frame: target.frameCount > 0 ? min(comment.frame, lastFrame) : comment.frame,
                                     text: comment.text, department: comment.department)
            copy.createdAt = comment.createdAt
            copy.annotationData = comment.annotationData
            copy.originID = origin
            // Если замечание уже переносили, помним, где его написали впервые.
            copy.carriedFromVersion = comment.carriedFromVersion ?? source.versionNumber
            context.insert(copy)
            copy.video = target
            count += 1
        }
        try? context.save()
        return count
    }

    /// Подменяет файл версии (переместили, переименовали) — комментарии остаются.
    static func relink(_ video: ReviewVideo, to url: URL, isImportedCopy: Bool, context: ModelContext) async throws {
        let isScoped = !isImportedCopy && url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let info = try await VideoTimecodeReader.read(from: asset)
        removeImportedCopy(of: video)
        if isImportedCopy {
            video.importedPath = relativeImportedPath(of: url)
            video.bookmark = nil
        } else {
            video.bookmark = try url.bookmarkData()
            video.importedPath = nil
        }
        await updateMetadata(of: video, asset: asset, info: info)
        try context.save()
    }

    /// Доступ к файлу версии. nil — файла нет (удалён, не перенесён на это устройство).
    static func access(_ video: ReviewVideo) -> FileAccess? {
        if let importedPath = video.importedPath {
            let url = importedRoot.appendingPathComponent(importedPath)
            return FileManager.default.fileExists(atPath: url.path) ? FileAccess(url: url, isScoped: false) : nil
        }
        guard let bookmark = video.bookmark else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else { return nil }
        let isScoped = url.startAccessingSecurityScopedResource()
        if isStale, let fresh = try? url.bookmarkData() {
            video.bookmark = fresh
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            if isScoped { url.stopAccessingSecurityScopedResource() }
            return nil
        }
        return FileAccess(url: url, isScoped: isScoped)
    }

    /// Превью, частота и длительность — для карточек библиотеки.
    static func updateMetadata(of video: ReviewVideo, asset: AVAsset, info: VideoTimecodeInfo) async {
        video.frameCount = info.frameCount
        video.frameRateLabel = info.rate.description
        video.durationLabel = Timecode(frameNumber: info.frameCount, rate: info.rate).description
        guard video.thumbnailData == nil else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let time = info.time(forFrame: info.frameCount / 10)
        if let image = try? await generator.image(at: time).image {
            video.thumbnailData = UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
        }
    }

    static func delete(_ video: ReviewVideo, context: ModelContext) {
        removeImportedCopy(of: video)
        let item = video.item
        context.delete(video)
        if let item, item.versions.allSatisfy({ $0 === video || $0.isDeleted }) {
            context.delete(item)
        }
        try? context.save()
    }

    static func delete(_ item: LibraryItem, context: ModelContext) {
        item.versions.forEach(removeImportedCopy)
        context.delete(item)
        try? context.save()
    }

    /// Записи с комментариями из версий приложения до библиотеки становятся роликами.
    /// Файл, открытый последним, сразу получает доступ (закладку старого «последнего видео»).
    static func migrateLegacyVideos(context: ModelContext) -> ReviewVideo? {
        let orphans = (try? context.fetch(FetchDescriptor<ReviewVideo>()))?.filter { $0.item == nil } ?? []
        var lastOpened: ReviewVideo?
        if let last = LastVideoStore.load() {
            lastOpened = orphans.first { $0.fileName == last.url.lastPathComponent }
            if let lastOpened {
                if last.isImportedCopy {
                    lastOpened.importedPath = relativeImportedPath(of: last.url)
                } else {
                    lastOpened.bookmark = try? last.url.bookmarkData()
                }
            }
            LastVideoStore.clear()
        }
        for video in orphans {
            let item = LibraryItem(title: (video.fileName as NSString).deletingPathExtension)
            item.createdAt = video.createdAt
            item.updatedAt = video.createdAt
            context.insert(item)
            video.versionNumber = 1
            video.item = item
        }
        if !orphans.isEmpty { try? context.save() }
        return lastOpened
    }

    private static func relativeImportedPath(of url: URL) -> String {
        let root = importedRoot.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
    }

    /// Копия из «Фото» живёт в своей папке — удаляем папку целиком.
    private static func removeImportedCopy(of video: ReviewVideo) {
        guard let importedPath = video.importedPath else { return }
        let url = importedRoot.appendingPathComponent(importedPath)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
