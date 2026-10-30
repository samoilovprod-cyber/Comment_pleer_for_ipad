import UIKit

/// Таблица ревью в PDF: A4 альбомом, шапка на первой странице, заголовок колонок — на каждой.
enum PDFReportWriter {
    private static let pageSize = CGSize(width: 842, height: 595)
    private static let margin: CGFloat = 32
    private static let cellPadding: CGFloat = 6

    private struct Column {
        let title: String
        let width: CGFloat
    }

    static func write(_ report: ReviewReport, imageWidth: CGFloat, to url: URL) throws {
        let contentWidth = pageSize.width - margin * 2
        let hasImages = report.rows.contains { $0.image != nil }
        let shotWidth = hasImages ? imageWidth + cellPadding * 2 : 0
        let fixed: [Column] = [
            Column(title: "#", width: 30),
            Column(title: "Timecode", width: 92),
            Column(title: "Dept", width: 48),
            Column(title: "Status", width: 62),
        ]
        let commentWidth = contentWidth - fixed.reduce(0) { $0 + $1.width } - shotWidth
        var columns = fixed + [Column(title: "Comment", width: commentWidth)]
        if hasImages { columns.append(Column(title: "Screenshot", width: shotWidth)) }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: {
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = [kCGPDFContextTitle as String: report.title,
                                   kCGPDFContextAuthor as String: report.author]
            return format
        }())

        try renderer.writePDF(to: url) { context in
            var page = 0
            var y: CGFloat = 0

            func startPage() {
                context.beginPage()
                page += 1
                y = margin
                draw("Page \(page)", font: .systemFont(ofSize: 9), color: .gray,
                     in: CGRect(x: margin, y: pageSize.height - margin + 8, width: contentWidth, height: 14),
                     alignment: .right)
            }

            func drawColumnHeader() {
                let height: CGFloat = 22
                UIColor(white: 0.9, alpha: 1).setFill()
                UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: height))
                var x = margin
                for column in columns {
                    draw(column.title, font: .boldSystemFont(ofSize: 10), color: .black,
                         in: CGRect(x: x + cellPadding, y: y + 5, width: column.width - cellPadding * 2, height: 14))
                    x += column.width
                }
                y += height
            }

            startPage()
            draw(report.title, font: .boldSystemFont(ofSize: 18), color: .black,
                 in: CGRect(x: margin, y: y, width: contentWidth, height: 24))
            y += 30
            for (name, value) in report.headerFields {
                draw(name, font: .boldSystemFont(ofSize: 10), color: .darkGray,
                     in: CGRect(x: margin, y: y, width: 80, height: 14))
                draw(value, font: .systemFont(ofSize: 10), color: .black,
                     in: CGRect(x: margin + 80, y: y, width: contentWidth - 80, height: 14))
                y += 15
            }
            y += 12
            drawColumnHeader()

            let bodyFont = UIFont.systemFont(ofSize: 10)
            for row in report.rows {
                let comment = row.text.isEmpty ? "(drawing)" : row.text
                let textHeight = height(of: comment, font: bodyFont, width: commentWidth - cellPadding * 2)
                let image = row.imageSize(width: imageWidth)
                let maxRowHeight = pageSize.height - margin * 2 - 22
                let rowHeight = min(max(textHeight, image.height, 14) + cellPadding * 2, maxRowHeight)
                if y + rowHeight > pageSize.height - margin {
                    startPage()
                    drawColumnHeader()
                }

                let values = [String(row.number), row.timecode, row.department?.label ?? "", row.status, comment]
                var x = margin
                for (column, value) in zip(columns, values) {
                    let color: UIColor = column.title == "Status" && !row.isResolved ? .systemOrange : .black
                    draw(value, font: column.title == "Timecode" ? .monospacedDigitSystemFont(ofSize: 10, weight: .regular) : bodyFont,
                         color: row.text.isEmpty && column.title == "Comment" ? .gray : color,
                         in: CGRect(x: x + cellPadding, y: y + cellPadding,
                                    width: column.width - cellPadding * 2, height: rowHeight - cellPadding * 2))
                    x += column.width
                }
                if let uiImage = row.image {
                    uiImage.draw(in: CGRect(origin: CGPoint(x: x + cellPadding, y: y + cellPadding), size: image))
                }

                UIColor(white: 0.8, alpha: 1).setFill()
                UIRectFill(CGRect(x: margin, y: y + rowHeight - 0.5, width: contentWidth, height: 0.5))
                y += rowHeight
            }
        }
    }

    private static func attributes(font: UIFont, color: UIColor,
                                   alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    private static func draw(_ text: String, font: UIFont, color: UIColor, in rect: CGRect,
                             alignment: NSTextAlignment = .left) {
        NSAttributedString(string: text, attributes: attributes(font: font, color: color, alignment: alignment))
            .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    private static func height(of text: String, font: UIFont, width: CGFloat) -> CGFloat {
        NSAttributedString(string: text, attributes: attributes(font: font, color: .black))
            .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                          options: .usesLineFragmentOrigin, context: nil)
            .height.rounded(.up)
    }
}
