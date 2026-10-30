import SwiftData
import SwiftUI

/// Версии одного ролика: открыть, сравнить, добавить, перепривязать файл, удалить.
struct VersionsScreen: View {
    let item: LibraryItem

    @EnvironmentObject private var router: Router
    @Environment(\.modelContext) private var modelContext

    @State private var importSource: VideoSource?
    /// Версия, которой ищем файл заново; nil — добавляем новую версию.
    @State private var relinkTarget: ReviewVideo?
    @State private var deletingVersion: ReviewVideo?
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        let versions = item.sortedVersions.reversed()
        List {
            ForEach(Array(versions)) { video in
                row(video)
                    .contentShape(Rectangle())
                    .onTapGesture { router.open(video) }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { deletingVersion = video }
                    }
                    .contextMenu {
                        Button("Open", systemImage: "play.rectangle") { router.open(video) }
                        Button("Relink File…", systemImage: "link") {
                            relinkTarget = video
                            // Окно выбора, показанное прямо из закрывающегося контекстного меню, iOS теряет.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { importSource = .files }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { deletingVersion = video }
                    }
                    .listRowBackground(Theme.panel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(item.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                let sorted = item.sortedVersions
                if sorted.count >= 2 {
                    Button("Compare", systemImage: "rectangle.split.2x1") {
                        router.compare(sorted[sorted.count - 2], sorted[sorted.count - 1])
                    }
                }
                Menu {
                    Button("From Files", systemImage: "folder") {
                        relinkTarget = nil
                        importSource = .files
                    }
                    Button("From Photos", systemImage: "photo.on.rectangle") {
                        relinkTarget = nil
                        importSource = .photos
                    }
                } label: {
                    Label("Add Version", systemImage: "plus")
                }
                Button("Rename", systemImage: "pencil") {
                    renameText = item.title
                    isRenaming = true
                }
            }
        }
        .videoImporter(source: $importSource) { picked in
            isWorking = true
            defer { isWorking = false }
            do {
                if let relinkTarget {
                    try await MediaLibrary.relink(relinkTarget, to: picked.url, isImportedCopy: picked.isImportedCopy,
                                                  context: modelContext)
                } else {
                    _ = try await MediaLibrary.addVideo(url: picked.url, isImportedCopy: picked.isImportedCopy,
                                                        to: item, context: modelContext)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .overlay {
            if isWorking {
                ProgressView()
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Rename", isPresented: $isRenaming) {
            TextField("Title", text: $renameText)
            Button("Save") {
                let title = renameText.trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    item.title = title
                    try? modelContext.save()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(deletingVersion?.versionLabel ?? "") and its comments?",
                            isPresented: Binding(get: { deletingVersion != nil },
                                                 set: { if !$0 { deletingVersion = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Version", role: .destructive) {
                if let deletingVersion {
                    let wasLast = item.versions.count == 1
                    MediaLibrary.delete(deletingVersion, context: modelContext)
                    if wasLast { router.path.removeLast() }
                }
                deletingVersion = nil
            }
        }
        .alert("Couldn't add the video", isPresented: Binding(get: { errorMessage != nil },
                                                              set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(_ video: ReviewVideo) -> some View {
        HStack(spacing: 14) {
            VideoThumbnail(data: video.thumbnailData)
                .frame(width: 128)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(video.versionLabel)
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                    Text(video.fileName)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if !video.frameRateLabel.isEmpty {
                        Text("\(video.frameRateLabel) fps")
                        Text("·")
                        Text(video.durationLabel)
                        Text("·")
                    }
                    Text(video.comments.count == 1 ? "1 comment" : "\(video.comments.count) comments")
                    if video.openCommentCount > 0 {
                        Text("(\(video.openCommentCount) open)").foregroundStyle(.yellow)
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 6) {
                    Text("Added \(video.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    if !video.hasFile {
                        Label("File missing — long-press to relink", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 6)
    }
}
