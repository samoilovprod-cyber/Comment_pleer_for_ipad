import SwiftUI

/// Выгрузка таблицы ревью: настройки слева, предпросмотр таблицы справа, затем Share Sheet.
struct ExportSheet: View {
    @ObservedObject var model: PlayerModel

    @Environment(\.dismiss) private var dismiss
    @AppStorage("report.author") private var author = ""
    @AppStorage("report.format") private var format: ReportFormat = .pdf
    @AppStorage("report.includeResolved") private var includeResolved = true
    @AppStorage("report.screenshots") private var screenshots: ScreenshotScope = .all
    @AppStorage("report.screenshotSize") private var size: ScreenshotSize = .medium

    @State private var report: ReviewReport?
    @State private var isBuilding = false
    @State private var isWriting = false
    @State private var buildError: String?
    @State private var errorMessage: String?
    @State private var sharedFile: SharedFile?

    private var options: ReportOptions {
        ReportOptions(includeResolved: includeResolved, screenshots: screenshots, size: size)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                settings
                Divider()
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.96))
                    // Предпросмотр как на бумаге — всегда светлый.
                    .environment(\.colorScheme, .light)
            }
            .navigationTitle("Export Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export \(format.rawValue.uppercased())", action: export)
                        .disabled(report == nil || isBuilding || isWriting)
                }
            }
            .task(id: options) { await buildReport() }
            .modifier(PageSizing())
            .sheet(item: $sharedFile) { file in
                ShareSheet(items: [file.url])
            }
            .alert("Export Failed", isPresented: Binding(get: { errorMessage != nil },
                                                         set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Picker("Format", selection: $format) {
                    ForEach(ReportFormat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                Toggle("Include resolved", isOn: $includeResolved)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            HStack(spacing: 16) {
                Picker("Screenshots", selection: $screenshots) {
                    ForEach(ScreenshotScope.allCases) { Text("Screenshots: \($0.title)").tag($0) }
                }
                .fixedSize()
                Picker("Size", selection: $size) {
                    ForEach(ScreenshotSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .disabled(screenshots == .none)
                TextField("Author", text: $author)
                    .textContentType(.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var preview: some View {
        if let report {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.title).font(.title3.bold())
                        ForEach(withAuthor(report).headerFields, id: \.0) { name, value in
                            HStack(alignment: .firstTextBaseline) {
                                Text(name).font(.caption.bold()).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                                Text(value).font(.caption)
                            }
                        }
                    }
                    if report.rows.isEmpty {
                        Text("No comments to export.").foregroundStyle(.secondary)
                    } else {
                        table(report)
                    }
                }
                .padding(20)
            }
            .overlay(alignment: .top) {
                if isBuilding { ProgressView().padding(8) }
            }
        } else if let buildError {
            ContentUnavailableView("Couldn't build the table", systemImage: "exclamationmark.triangle",
                                   description: Text(buildError))
        } else {
            ProgressView("Rendering screenshots…")
        }
    }

    private func table(_ report: ReviewReport) -> some View {
        let imageWidth = min(size.displayWidth, 200)
        return Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                ForEach(["#", "Timecode", "Dept", "Status", "Comment", "Screenshot"], id: \.self) {
                    Text($0).font(.caption.bold()).foregroundStyle(.secondary)
                }
            }
            Divider()
            ForEach(report.rows) { row in
                GridRow {
                    Text("\(row.number)").fixedSize()
                    Text(row.timecode).monospacedDigit().fixedSize()
                    Text(row.department?.label ?? "–").fixedSize()
                    Text(row.status).foregroundStyle(row.isResolved ? .green : .orange).fixedSize()
                    Text(row.text.isEmpty ? "(drawing)" : row.text)
                        .foregroundStyle(row.text.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let image = row.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageWidth)
                    } else {
                        Color.clear.frame(width: 1, height: 1)
                    }
                }
                .font(.callout)
                Divider()
            }
        }
    }

    private func withAuthor(_ report: ReviewReport) -> ReviewReport {
        var report = report
        report.author = author.trimmingCharacters(in: .whitespaces)
        return report
    }

    private func buildReport() async {
        isBuilding = true
        defer { isBuilding = false }
        do {
            let built = try await model.makeReport(options: options, author: author)
            guard !Task.isCancelled else { return }
            report = built
            buildError = nil
        } catch is CancellationError {
        } catch {
            report = nil
            buildError = error.localizedDescription
        }
    }

    private func export() {
        guard let report else { return }
        isWriting = true
        defer { isWriting = false }
        do {
            let folder = URL.temporaryDirectory.appendingPathComponent("Reports", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("\(report.baseName)_review.\(format.fileExtension)")
            let final = withAuthor(report)
            let imageWidth = screenshots == .none ? 0 : size.displayWidth
            switch format {
            case .pdf: try PDFReportWriter.write(final, imageWidth: imageWidth, to: url)
            case .xlsx: try XLSXReportWriter.write(final, imageWidth: imageWidth, to: url)
            }
            sharedFile = SharedFile(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// На iOS 18+ — окно во весь «лист», чтобы таблица не была зажата в узкой форме.
private struct PageSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}
