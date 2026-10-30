import PhotosUI
import SwiftUI

/// Откуда брать видео: «Файлы» (по закладке, без копирования) или «Фото» (копия к себе).
enum VideoSource: Identifiable {
    case files, photos

    var id: Self { self }
}

/// Выбранный файл: `isImportedCopy` — копия в Application Support (из «Фото» или перетаскивания).
struct PickedVideo {
    let url: URL
    let isImportedCopy: Bool
}

extension View {
    /// Показывает выбор видео из «Файлов» или «Фото» и отдаёт выбранный файл.
    func videoImporter(source: Binding<VideoSource?>, onPick: @escaping (PickedVideo) async -> Void) -> some View {
        modifier(VideoImporterModifier(source: source, onPick: onPick))
    }
}

private struct VideoImporterModifier: ViewModifier {
    @Binding var source: VideoSource?
    let onPick: (PickedVideo) async -> Void

    @State private var photosSelection: PhotosPickerItem?
    @State private var isCopying = false
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: binding(for: .files),
                          allowedContentTypes: [.movie, .quickTimeMovie, .mpeg4Movie]) { result in
                if case let .success(url) = result {
                    Task { await onPick(PickedVideo(url: url, isImportedCopy: false)) }
                }
            }
            // .current — без перекодирования: сохраняем исходные кадры, частоту и трек тайм-кода.
            .photosPicker(isPresented: binding(for: .photos), selection: $photosSelection,
                          matching: .videos, preferredItemEncoding: .current)
            .onChange(of: photosSelection) { _, item in
                guard let item else { return }
                photosSelection = nil
                Task { await copyFromPhotos(item) }
            }
            .overlay {
                if isCopying {
                    ProgressView("Copying video…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Couldn't add the video", isPresented: Binding(get: { errorMessage != nil },
                                                                  set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func binding(for value: VideoSource) -> Binding<Bool> {
        Binding(get: { source == value }, set: { if !$0, source == value { source = nil } })
    }

    private func copyFromPhotos(_ item: PhotosPickerItem) async {
        isCopying = true
        defer { isCopying = false }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                errorMessage = "The selected item is not a video."
                return
            }
            await onPick(PickedVideo(url: movie.url, isImportedCopy: true))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
