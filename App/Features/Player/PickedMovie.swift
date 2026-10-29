import CoreTransferable
import UniformTypeIdentifiers

/// Видео из «Фото» или перетащенное в приложение — копия в Application Support,
/// чтобы его можно было открыть и после перезапуска.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // Файл от системы доступен только внутри этого замыкания — копируем к себе.
            let folder = URL.applicationSupportDirectory
                .appendingPathComponent("ImportedVideos", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}
