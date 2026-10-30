import SwiftUI

/// Правая панель: поиск и список комментариев. Тап по комментарию — переход к его кадру.
struct CommentsPanel: View {
    let comments: [ReviewComment]
    let currentFrame: Int
    let timecode: (Int) -> String
    let onSelect: (ReviewComment) -> Void
    let onToggleResolved: (ReviewComment) -> Void
    let onSetDepartment: (ReviewComment, Department?) -> Void
    let onEdit: (ReviewComment) -> Void
    let onEditDrawing: (ReviewComment) -> Void
    let onShareImage: (ReviewComment) -> Void
    let onDelete: (ReviewComment) -> Void

    enum Filter: String, CaseIterable {
        case all = "All"
        case open = "Open"
        case resolved = "Resolved"
    }

    @State private var query = ""
    @State private var filter = Filter.all
    /// Показывать только эти цеха; пусто — все.
    @State private var departments: Set<Department> = []

    private var filtered: [ReviewComment] {
        comments.filter { comment in
            switch filter {
            case .all: true
            case .open: !comment.isResolved
            case .resolved: comment.isResolved
            }
        }
        .filter { departments.isEmpty || $0.department.map(departments.contains) == true }
        .filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }
    }

    private var openCount: Int { comments.filter { !$0.isResolved }.count }

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
                TextField("Search comments", text: $query)
                    .foregroundStyle(Theme.textPrimary)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            departmentFilter
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if comments.isEmpty {
                ContentUnavailableView("No comments yet",
                                       systemImage: "text.bubble",
                                       description: Text("Pause on a frame and type a comment below."))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView("No matching comments",
                                       systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("Change the status, department or search filter."))
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

    /// Плашки цехов: тап включает/выключает фильтр, рядом — сколько открытых замечаний у цеха.
    private var departmentFilter: some View {
        HStack(spacing: 6) {
            ForEach(Department.allCases) { department in
                let openCount = comments.filter { $0.department == department && !$0.isResolved }.count
                Button {
                    if departments.contains(department) {
                        departments.remove(department)
                    } else {
                        departments.insert(department)
                    }
                } label: {
                    HStack(spacing: 3) {
                        DepartmentChip(department: department, isSelected: departments.contains(department))
                        if openCount > 0 {
                            Text("\(openCount)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(department.title), \(openCount) open")
                .accessibilityAddTraits(departments.contains(department) ? .isSelected : [])
            }
            Spacer(minLength: 0)
            if !departments.isEmpty {
                Button("Clear") { departments.removeAll() }
                    .font(.caption)
            }
        }
    }

    private var commentsCountLabel: String {
        comments.isEmpty ? "Comments" : "\(comments.count) \(comments.count == 1 ? "Comment" : "Comments") · \(openCount) open"
    }

    private func row(_ comment: ReviewComment) -> some View {
        Button { onSelect(comment) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary)
                    .opacity(comment.isResolved ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("You")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        TimecodeChip(text: timecode(comment.frame), isProminent: comment.frame == currentFrame)
                        if let department = comment.department {
                            DepartmentChip(department: department)
                        }
                        if comment.hasAnnotation {
                            Image(systemName: "pencil.tip.crop.circle")
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                                .accessibilityLabel("Has drawing")
                        }
                        if let version = comment.carriedFromVersion {
                            Text("from v\(version)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.field, in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(Theme.textSecondary)
                                .help("Carried over from v\(version)")
                        }
                    }
                    Text(comment.text.isEmpty ? "Drawing" : comment.text)
                        .italic(comment.text.isEmpty)
                        .font(.subheadline)
                        .foregroundStyle(comment.isResolved ? Theme.textSecondary : Theme.textPrimary)
                        .strikethrough(comment.isResolved)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Text(comment.createdAt, format: .relative(presentation: .named))
                        if comment.editedAt != nil {
                            Text("· edited")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Button {
                    onToggleResolved(comment)
                } label: {
                    Image(systemName: comment.isResolved ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(comment.isResolved ? Color.green : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(comment.isResolved ? "Reopen" : "Mark as resolved")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(comment.frame == currentFrame ? Theme.accent.opacity(0.12) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit", systemImage: "pencil") { onEdit(comment) }
            Button(comment.hasAnnotation ? "Edit Drawing" : "Add Drawing", systemImage: "pencil.tip.crop.circle") {
                onEditDrawing(comment)
            }
            Button("Share Frame Image", systemImage: "square.and.arrow.up") { onShareImage(comment) }
            Menu("Department", systemImage: "person.2") {
                Picker("Department", selection: Binding(get: { comment.department },
                                                        set: { onSetDepartment(comment, $0) })) {
                    Text("No Department").tag(Department?.none)
                    ForEach(Department.allCases) { department in
                        Text("\(department.label) — \(department.title)").tag(Optional(department))
                    }
                }
            }
            Button(comment.isResolved ? "Reopen" : "Mark as Resolved",
                   systemImage: comment.isResolved ? "arrow.uturn.backward.circle" : "checkmark.circle") {
                onToggleResolved(comment)
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(comment) }
        }
    }
}
