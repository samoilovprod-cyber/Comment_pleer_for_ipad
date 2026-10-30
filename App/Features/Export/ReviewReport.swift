import UIKit

/// Таблица ревью: шапка с данными о файле и строки комментариев со скриншотами.
/// Из неё собираются и предпросмотр, и XLSX, и PDF.
struct ReviewReport {
    struct Row: Identifiable {
        let id: Int
        let number: Int
        let timecode: String
        let department: Department?
        let isResolved: Bool
        let text: String
        let hasDrawing: Bool
        /// Кадр с пометками; nil — скриншот для этой строки не нужен.
        let image: UIImage?

        var status: String { isResolved ? "Resolved" : "Open" }
    }

    var fileName: String
    var frameRate: String
    var startTimecode: String
    var duration: String
    var date: Date
    var author: String
    var rows: [Row]

    var title: String { "Review: \(fileName)" }
    var baseName: String { (fileName as NSString).deletingPathExtension }
    var openCount: Int { rows.filter { !$0.isResolved }.count }

    /// Строки шапки «название — значение», одинаковые для всех форматов.
    var headerFields: [(String, String)] {
        var fields = [
            ("File", fileName),
            ("FPS", frameRate),
            ("Start TC", startTimecode),
            ("Duration", duration),
            ("Date", date.formatted(date: .abbreviated, time: .shortened)),
        ]
        if !author.isEmpty { fields.append(("Author", author)) }
        fields.append(("Comments", "\(rows.count) (\(openCount) open)"))
        return fields
    }
}

enum ReportFormat: String, CaseIterable, Identifiable {
    case xlsx, pdf

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
}

/// Ширина скриншота в таблице, в точках. Сами картинки — вдвое больше, чтобы были чёткими.
enum ScreenshotSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var displayWidth: CGFloat {
        switch self {
        case .small: 160
        case .medium: 240
        case .large: 360
        }
    }
    var pixelWidth: CGFloat { displayWidth * 2 }
}

/// Для каких строк вставлять скриншот.
enum ScreenshotScope: String, CaseIterable, Identifiable {
    case all, drawingsOnly, none

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Every comment"
        case .drawingsOnly: "Drawings only"
        case .none: "None"
        }
    }
}

struct ReportOptions: Equatable {
    var includeResolved = true
    var screenshots: ScreenshotScope = .all
    var size: ScreenshotSize = .medium
}

extension ReviewReport.Row {
    /// Размер картинки в таблице при заданной ширине колонки.
    func imageSize(width: CGFloat) -> CGSize {
        guard let image, image.size.width > 0 else { return .zero }
        return CGSize(width: width, height: (width * image.size.height / image.size.width).rounded())
    }
}
