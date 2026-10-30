import UIKit

/// Таблица ревью в XLSX: шапка с данными о файле, затем `# | Timecode | Dept | Status | Comment | Screenshot`.
/// Скриншоты привязаны к ячейке колонки Screenshot, высота строки подогнана под картинку.
enum XLSXReportWriter {
    private static let emuPerPoint = 12_700
    private static let imagePadding: CGFloat = 4
    /// Excel не даёт строке быть выше 409 pt.
    private static let maxRowHeight: CGFloat = 400

    static func write(_ report: ReviewReport, imageWidth: CGFloat, to url: URL) throws {
        var archive = ZipWriter()
        var sheetRows: [String] = []
        var merges: [String] = []
        var pictures: [(row: Int, size: CGSize, data: Data)] = []
        var strings: [String] = []
        var stringIndex: [String: Int] = [:]

        /// Ячейка с текстом из общей таблицы строк — inline-строки понимает не каждая программа.
        func text(_ ref: String, _ value: String, style: Int = 0) -> String {
            let styleAttribute = style == 0 ? "" : " s=\"\(style)\""
            guard !value.isEmpty else { return "<c r=\"\(ref)\"\(styleAttribute)/>" }
            let index = stringIndex[value] ?? {
                strings.append(value)
                stringIndex[value] = strings.count - 1
                return strings.count - 1
            }()
            return "<c r=\"\(ref)\"\(styleAttribute) t=\"s\"><v>\(index)</v></c>"
        }

        var rowIndex = 1
        func addRow(_ cells: [String], height: CGFloat? = nil) {
            let ht = height.map { " ht=\"\(format($0))\" customHeight=\"1\"" } ?? ""
            sheetRows.append("<row r=\"\(rowIndex)\"\(ht)>\(cells.joined())</row>")
            rowIndex += 1
        }

        addRow([text("A1", report.title, style: 1)], height: 24)
        merges.append("A1:F1")
        for (name, value) in report.headerFields {
            addRow([text("B\(rowIndex)", name, style: 2), text("C\(rowIndex)", value)])
            merges.append("C\(rowIndex):F\(rowIndex)")
        }
        rowIndex += 1

        let headerRow = rowIndex
        let titles = ["#", "Timecode", "Dept", "Status", "Comment", "Screenshot"]
        addRow(zip(columnLetters, titles).map { text("\($0)\(headerRow)", $1, style: 3) }, height: 20)

        for row in report.rows {
            let r = rowIndex
            var size = row.imageSize(width: imageWidth)
            if size.height > maxRowHeight - imagePadding * 2 {
                let fit = (maxRowHeight - imagePadding * 2) / size.height
                size = CGSize(width: (size.width * fit).rounded(), height: (size.height * fit).rounded())
            }
            let lines = row.text.split(separator: "\n", omittingEmptySubsequences: false)
                .reduce(0) { $0 + max(1, ($1.count + 59) / 60) }
            let height = min(max(size.height + imagePadding * 2, CGFloat(lines) * 14 + 6, 18), maxRowHeight)
            addRow([
                "<c r=\"A\(r)\" s=\"4\"><v>\(row.number)</v></c>",
                text("B\(r)", row.timecode, style: 4),
                text("C\(r)", row.department?.label ?? "", style: 4),
                text("D\(r)", row.status, style: 4),
                text("E\(r)", row.text.isEmpty ? "(drawing)" : row.text, style: 4),
                text("F\(r)", "", style: 4),
            ], height: height)
            if let data = row.image?.jpegData(compressionQuality: 0.85) {
                pictures.append((r, size, data))
            }
        }

        let screenshotColumnWidth = max(14, (imageWidth + imagePadding * 2) * 4 / 3 / 7 + 1)
        let cols = [5, 14, 8, 16, 60, Double(screenshotColumnWidth)].enumerated().map { index, width in
            "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
        }

        let sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <sheetViews><sheetView workbookViewId="0">\
        <pane ySplit="\(headerRow)" topLeftCell="A\(headerRow + 1)" activePane="bottomLeft" state="frozen"/>\
        </sheetView></sheetViews>\
        <cols>\(cols.joined())</cols>\
        <sheetData>\(sheetRows.joined())</sheetData>\
        <mergeCells count="\(merges.count)">\(merges.map { "<mergeCell ref=\"\($0)\"/>" }.joined())</mergeCells>\
        <pageMargins left="0.5" right="0.5" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>\
        <pageSetup orientation="landscape" fitToHeight="0"/>\
        \(pictures.isEmpty ? "" : "<drawing r:id=\"rId1\"/>")\
        </worksheet>
        """

        archive.add("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Default Extension="jpeg" ContentType="image/jpeg"/>\
        <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>\
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
        \(pictures.isEmpty ? "" : "<Override PartName=\"/xl/drawings/drawing1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawing+xml\"/>")\
        <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>\
        </Types>
        """)
        archive.add("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>\
        </Relationships>
        """)
        archive.add("docProps/core.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
        xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
        <dc:title>\(escape(report.title))</dc:title><dc:creator>\(escape(report.author))</dc:creator>\
        <dcterms:created xsi:type="dcterms:W3CDTF">\(report.date.ISO8601Format())</dcterms:created>\
        </cp:coreProperties>
        """)
        archive.add("xl/workbook.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <sheets><sheet name="Review" sheetId="1" r:id="rId1"/></sheets></workbook>
        """)
        archive.add("xl/_rels/workbook.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>\
        </Relationships>
        """)
        archive.add("xl/sharedStrings.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(strings.count)" uniqueCount="\(strings.count)">\
        \(strings.map { "<si><t xml:space=\"preserve\">\(escape($0))</t></si>" }.joined())</sst>
        """)
        archive.add("xl/styles.xml", styles)
        archive.add("xl/worksheets/sheet1.xml", sheet)

        if !pictures.isEmpty {
            archive.add("xl/worksheets/_rels/sheet1.xml.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>\
            </Relationships>
            """)
            var anchors: [String] = []
            var rels: [String] = []
            let padding = Int(imagePadding) * emuPerPoint
            for (index, picture) in pictures.enumerated() {
                let id = index + 1
                let cx = Int(picture.size.width) * emuPerPoint
                let cy = Int(picture.size.height) * emuPerPoint
                archive.add("xl/media/image\(id).jpeg", picture.data)
                rels.append("<Relationship Id=\"rId\(id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/image\(id).jpeg\"/>")
                anchors.append("""
                <xdr:twoCellAnchor editAs="oneCell">\
                <xdr:from><xdr:col>5</xdr:col><xdr:colOff>\(padding)</xdr:colOff>\
                <xdr:row>\(picture.row - 1)</xdr:row><xdr:rowOff>\(padding)</xdr:rowOff></xdr:from>\
                <xdr:to><xdr:col>5</xdr:col><xdr:colOff>\(padding + cx)</xdr:colOff>\
                <xdr:row>\(picture.row - 1)</xdr:row><xdr:rowOff>\(padding + cy)</xdr:rowOff></xdr:to>\
                <xdr:pic><xdr:nvPicPr><xdr:cNvPr id="\(id + 1)" name="Screenshot \(id)"/>\
                <xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>\
                <xdr:blipFill><a:blip r:embed="rId\(id)"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>\
                <xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm>\
                <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>\
                <xdr:clientData/></xdr:twoCellAnchor>
                """)
            }
            archive.add("xl/drawings/drawing1.xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" \
            xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\(anchors.joined())</xdr:wsDr>
            """)
            archive.add("xl/drawings/_rels/drawing1.xml.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels.joined())</Relationships>
            """)
        }

        try archive.finish().write(to: url, options: .atomic)
    }

    private static let columnLetters = ["A", "B", "C", "D", "E", "F"]

    /// 0 — обычный, 1 — заголовок, 2 — подпись в шапке, 3 — заголовок колонки, 4 — ячейка таблицы.
    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
    <fonts count="3"><font><sz val="11"/><name val="Calibri"/></font>\
    <font><b/><sz val="14"/><name val="Calibri"/></font>\
    <font><b/><sz val="11"/><name val="Calibri"/></font></fonts>\
    <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>\
    <fill><patternFill patternType="solid"><fgColor rgb="FFE5E5E5"/><bgColor indexed="64"/></patternFill></fill></fills>\
    <borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>\
    <border><left style="thin"><color rgb="FFBFBFBF"/></left><right style="thin"><color rgb="FFBFBFBF"/></right>\
    <top style="thin"><color rgb="FFBFBFBF"/></top><bottom style="thin"><color rgb="FFBFBFBF"/></bottom><diagonal/></border></borders>\
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
    <cellXfs count="5">\
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>\
    <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>\
    <xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">\
    <alignment vertical="center"/></xf>\
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1">\
    <alignment horizontal="left" vertical="top" wrapText="1"/></xf>\
    </cellXfs>\
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>\
    </styleSheet>
    """

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    /// Экранирует XML и выкидывает управляющие символы, которые Excel не принимает.
    private static func escape(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "\n", "\t": result.unicodeScalars.append(scalar)
            case _ where scalar.value < 0x20: continue
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
