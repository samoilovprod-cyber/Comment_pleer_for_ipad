import SwiftData
import SwiftUI

/// Главный экран: ролики карточками. Тап — последняя версия в плеере; перетащить файл на карточку — новая версия.
struct LibraryScreen: View {
    @Query(sort: \LibraryItem.updatedAt, order: .reverse) private var items: [LibraryItem]
    @EnvironmentObject private var router: Router
    @Environment(\.modelContext) private var modelContext

    @State private var importSource: VideoSource?
    /// Куда добавить выбранный файл: nil — новым роликом.
    @State private var importTarget: LibraryItem?
    @State private var renamingItem: LibraryItem?
    @State private var renameText = ""
    @State private var deletingItem: LibraryItem?
    @State private var isDropTargeted = false
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                addMenu(to: nil) {
                    Label("Add Video", systemImage: "plus")
                }
            }
        }
        .videoImporter(source: $importSource) { picked in
            await add(picked, to: importTarget)
        }
        .dropDestination(for: PickedMovie.self) { movies, _ in
            Task {
                for movie in movies {
                    await add(PickedVideo(url: movie.url, isImportedCopy: true), to: nil)
                }
            }
            return !movies.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isAdding {
                ProgressView("Adding video…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if isDropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 4, dash: [12]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .alert("Rename", isPresented: Binding(get: { renamingItem != nil },
                                              set: { if !$0 { renamingItem = nil } })) {
            TextField("Title", text: $renameText)
            Button("Save") {
                let title = renameText.trimmingCharacters(in: .whitespaces)
                if let renamingItem, !title.isEmpty {
                    renamingItem.title = title
                    try? modelContext.save()
                }
                renamingItem = nil
            }
            Button("Cancel", role: .cancel) { renamingItem = nil }
        }
        .confirmationDialog("Delete “\(deletingItem?.title ?? "")”?",
                            isPresented: Binding(get: { deletingItem != nil },
                                                 set: { if !$0 { deletingItem = nil } }),
                            titleVisibility: .visible) {
            Button("Delete All Versions and Comments", role: .destructive) {
                if let deletingItem { MediaLibrary.delete(deletingItem, context: modelContext) }
                deletingItem = nil
            }
        } message: {
            Text("Files in the Files app are not deleted. Copies imported from Photos are removed.")
        }
        .alert("Couldn't add the video", isPresented: Binding(get: { errorMessage != nil },
                                                              set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 400), spacing: 20)], spacing: 24) {
                ForEach(items) { item in
                    LibraryCard(item: item)
                        .onTapGesture {
                            if let latest = item.latest { router.open(latest) }
                        }
                        .contextMenu { contextMenu(for: item) }
                        // Файл, брошенный на карточку, — новая версия этого ролика.
                        .dropDestination(for: PickedMovie.self) { movies, _ in
                            guard let movie = movies.first else { return false }
                            Task { await add(PickedVideo(url: movie.url, isImportedCopy: true), to: item) }
                            return true
                        }
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func contextMenu(for item: LibraryItem) -> some View {
        if let latest = item.latest {
            Button("Open \(latest.versionLabel)", systemImage: "play.rectangle") { router.open(latest) }
        }
        Button("Versions", systemImage: "square.stack") { router.path.append(.versions(item.persistentModelID)) }
        let versions = item.sortedVersions
        if versions.count >= 2 {
            Button("Compare \(versions[versions.count - 2].versionLabel) / \(versions[versions.count - 1].versionLabel)",
                   systemImage: "rectangle.split.2x1") {
                router.compare(versions[versions.count - 2], versions[versions.count - 1])
            }
        }
        // Подменю внутри контекстного меню окно выбора не открывает — пункты плоские.
        Button("Add Version from Files", systemImage: "folder.badge.plus") { startImport(.files, into: item) }
        Button("Add Version from Photos", systemImage: "photo.badge.plus") { startImport(.photos, into: item) }
        Divider()
        Button("Rename", systemImage: "pencil") {
            renameText = item.title
            renamingItem = item
        }
        Button("Delete", systemImage: "trash", role: .destructive) { deletingItem = item }
    }

    private func addMenu<Label: View>(to item: LibraryItem?, @ViewBuilder label: () -> Label) -> some View {
        Menu {
            Button("From Files", systemImage: "folder") { startImport(.files, into: item) }
            Button("From Photos", systemImage: "photo.on.rectangle") { startImport(.photos, into: item) }
        } label: {
            label()
        }
    }

    /// Окно выбора открываем чуть позже: показанное прямо из контекстного меню, пока оно закрывается, iOS теряет.
    private func startImport(_ source: VideoSource, into item: LibraryItem?) {
        importTarget = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { importSource = source }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Videos Yet", systemImage: "film.stack")
        } description: {
            Text("Add a MOV or MP4 (ProRes, H.264, HEVC) or drop files here. New cuts of the same video become versions.")
        } actions: {
            HStack {
                Button("From Files", systemImage: "folder") {
                    importTarget = nil
                    importSource = .files
                }
                Button("From Photos", systemImage: "photo.on.rectangle") {
                    importTarget = nil
                    importSource = .photos
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func add(_ picked: PickedVideo, to item: LibraryItem?) async {
        isAdding = true
        defer { isAdding = false }
        do {
            _ = try await MediaLibrary.addVideo(url: picked.url, isImportedCopy: picked.isImportedCopy,
                                                to: item, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Карточка ролика: превью последней версии, номер версии, число версий и открытых замечаний.
private struct LibraryCard: View {
    let item: LibraryItem

    var body: some View {
        let latest = item.latest
        VStack(alignment: .leading, spacing: 10) {
            VideoThumbnail(data: latest?.thumbnailData)
                .overlay(alignment: .topLeading) {
                    if let latest {
                        Text(latest.versionLabel)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5))
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if item.versions.count > 1 {
                        Image(systemName: "square.stack.fill")
                            .font(.caption)
                            .padding(6)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.versions.count == 1 ? "1 version" : "\(item.versions.count) versions")
                    if item.openCommentCount > 0 {
                        Text("·")
                        Text("\(item.openCommentCount) open")
                            .foregroundStyle(.yellow)
                    }
                    Spacer()
                    Text(item.updatedAt, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("libraryCard")
    }
}

/// Превью кадра 16:9 на чёрном фоне.
struct VideoThumbnail: View {
    let data: Data?

    var body: some View {
        Rectangle()
            .fill(.black)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
