import SwiftUI

/// Правая панель: поиск и список комментариев. Тап по комментарию — переход к его кадру.
struct CommentsPanel: View {
    let comments: [ReviewComment]
    let currentFrame: Int
    let timecode: (Int) -> String
    let onSelect: (ReviewComment) -> Void
    let onDelete: (ReviewComment) -> Void
    var isSearchFocused: FocusState<Bool>.Binding

    @State private var query = ""

    private var filtered: [ReviewComment] {
        let sorted = comments.sorted { ($0.frame, $0.createdAt) < ($1.frame, $1.createdAt) }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(commentsCountLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                TextField("Поиск по комментариям", text: $query)
                    .focused(isSearchFocused)
                    .foregroundStyle(Theme.textPrimary)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if comments.isEmpty {
                ContentUnavailableView("Комментариев пока нет",
                                       systemImage: "text.bubble",
                                       description: Text("Поставьте видео на нужный кадр и напишите комментарий внизу."))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { comment in
                            row(comment)
                            Rectangle().fill(Theme.separator).frame(height: 1)
                        }
                    }
                }
            }
        }
        .background(Theme.sidebar)
    }

    private var commentsCountLabel: String {
        comments.isEmpty ? "Комментарии" : "Комментарии: \(comments.count)"
    }

    private func row(_ comment: ReviewComment) -> some View {
        Button { onSelect(comment) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Вы")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        TimecodeChip(text: timecode(comment.frame), isProminent: comment.frame == currentFrame)
                    }
                    Text(comment.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(comment.createdAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(comment.frame == currentFrame ? Theme.accent.opacity(0.12) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Удалить", systemImage: "trash", role: .destructive) { onDelete(comment) }
        }
    }
}
