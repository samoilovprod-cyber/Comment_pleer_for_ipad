import PencilKit
import UIKit

/// Пометки на кадре. Всё хранится в координатах кадра (пиксели видео), а не экрана,
/// поэтому рисунок не «съезжает» при повороте iPad и рендерится в полном разрешении.
struct Annotation: Codable {
    var drawing = PKDrawing()
    var labels: [TextLabel] = []

    var isEmpty: Bool { drawing.strokes.isEmpty && labels.isEmpty }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case drawing, labels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        drawing = try PKDrawing(data: container.decode(Data.self, forKey: .drawing))
        labels = try container.decode([TextLabel].self, forKey: .labels)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(drawing.dataRepresentation(), forKey: .drawing)
        try container.encode(labels, forKey: .labels)
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data) -> Annotation? { try? JSONDecoder().decode(Annotation.self, from: data) }
}

/// Текстовая подпись на кадре: позиция и размер шрифта — в пикселях кадра.
struct TextLabel: Codable, Identifiable {
    var id = UUID()
    var text: String
    var x: Double
    var y: Double
    var colorHex: UInt32
    var fontSize: Double

    var position: CGPoint { CGPoint(x: x, y: y) }
}

/// Цвета пометок.
enum AnnotationPalette {
    static let colors: [UInt32] = [0xFF3B30, 0xFFCC00, 0x34C759, 0x0A84FF, 0xFFFFFF, 0x000000]
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Фигуры (стрелка, прямоугольник, эллипс) собираем из штрихов PencilKit:
/// так их можно стирать ластиком, отменять и рендерить вместе с рисунком от руки.
enum ShapeStrokes {
    enum Kind {
        case arrow, rectangle, ellipse
    }

    static func make(_ kind: Kind, from start: CGPoint, to end: CGPoint, color: UIColor, width: CGFloat) -> [PKStroke] {
        switch kind {
        case .arrow:
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = hypot(end.x - start.x, end.y - start.y)
            let head = min(max(width * 5, length * 0.25), length * 0.6)
            let left = CGPoint(x: end.x - head * cos(angle - .pi / 7), y: end.y - head * sin(angle - .pi / 7))
            let right = CGPoint(x: end.x - head * cos(angle + .pi / 7), y: end.y - head * sin(angle + .pi / 7))
            return [stroke(polyline: [start, end], color: color, width: width),
                    stroke(polyline: [left, end, right], color: color, width: width)]
        case .rectangle:
            let a = start, c = end
            let b = CGPoint(x: c.x, y: a.y), d = CGPoint(x: a.x, y: c.y)
            return [stroke(polyline: [a, b, c, d, a], color: color, width: width)]
        case .ellipse:
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                              width: abs(end.x - start.x), height: abs(end.y - start.y))
            let points = (0...96).map { index -> CGPoint in
                let t = CGFloat(index) / 96 * 2 * .pi
                return CGPoint(x: rect.midX + rect.width / 2 * cos(t), y: rect.midY + rect.height / 2 * sin(t))
            }
            return [stroke(points: points, color: color, width: width)]
        }
    }

    /// Ломаная с острыми углами: PencilKit сглаживает путь сплайном, поэтому
    /// точки ставим часто, а вершины повторяем — тогда углы не скругляются.
    private static func stroke(polyline vertices: [CGPoint], color: UIColor, width: CGFloat) -> PKStroke {
        var points: [CGPoint] = []
        let step = max(width / 2, 1)
        for (from, to) in zip(vertices, vertices.dropFirst()) {
            points += [from, from, from]
            let count = max(Int(hypot(to.x - from.x, to.y - from.y) / step), 1)
            for index in 1..<count {
                let t = CGFloat(index) / CGFloat(count)
                points.append(CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
            }
        }
        if let last = vertices.last {
            points += [last, last, last]
        }
        return stroke(points: points, color: color, width: width)
    }

    private static func stroke(points: [CGPoint], color: UIColor, width: CGFloat) -> PKStroke {
        let strokePoints = points.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: TimeInterval(index) * 0.001,
                          size: CGSize(width: width, height: width), opacity: 1, force: 1,
                          azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: color),
                        path: PKStrokePath(controlPoints: strokePoints, creationDate: Date()))
    }
}

/// Рисует пометки поверх кадра — для просмотра в плеере и для экспорта в полном разрешении.
enum AnnotationRenderer {
    /// Прозрачная картинка с пометками размером `frameSize × scale`.
    static func overlayImage(_ annotation: Annotation, frameSize: CGSize, scale: CGFloat,
                             includeLabels: Bool = true) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: frameSize, format: format).image { context in
            draw(annotation, frameSize: frameSize, scale: scale, includeLabels: includeLabels, in: context.cgContext)
        }
    }

    /// Кадр видео + пометки, в разрешении самого кадра.
    static func composite(frame: CGImage, annotation: Annotation, frameSize: CGSize) -> UIImage {
        let imageSize = CGSize(width: frame.width, height: frame.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: imageSize, format: format).image { context in
            UIImage(cgImage: frame).draw(in: CGRect(origin: .zero, size: imageSize))
            // Если генератор отдал кадр другого размера — подгоняем пометки под него.
            let fit = CGAffineTransform(scaleX: imageSize.width / frameSize.width, y: imageSize.height / frameSize.height)
            context.cgContext.concatenate(fit)
            draw(annotation, frameSize: frameSize, scale: max(fit.a, 1), includeLabels: true, in: context.cgContext)
        }
    }

    private static func draw(_ annotation: Annotation, frameSize: CGSize, scale: CGFloat,
                             includeLabels: Bool, in context: CGContext) {
        let rect = CGRect(origin: .zero, size: frameSize)
        // Светлая тема: иначе PencilKit «инвертирует» чёрные и белые штрихи.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            annotation.drawing.image(from: rect, scale: scale).draw(in: rect)
        }
        for label in includeLabels ? annotation.labels : [] {
            let font = UIFont.systemFont(ofSize: label.fontSize, weight: .semibold)
            let text = NSAttributedString(string: label.text, attributes: [
                .font: font,
                .foregroundColor: UIColor(hex: label.colorHex),
            ])
            let size = text.size()
            let padding = label.fontSize * 0.3
            let box = CGRect(x: label.x - size.width / 2 - padding, y: label.y - size.height / 2 - padding / 2,
                             width: size.width + padding * 2, height: size.height + padding)
            context.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
            context.addPath(UIBezierPath(roundedRect: box, cornerRadius: padding).cgPath)
            context.fillPath()
            text.draw(at: CGPoint(x: box.minX + padding, y: box.minY + padding / 2))
        }
    }
}
