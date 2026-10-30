import PencilKit
import SwiftUI

/// Холст поверх видео в режиме рисования. Размер — ровно прямоугольник кадра на экране.
struct AnnotationCanvas: View {
    @ObservedObject var editor: AnnotationEditor

    @State private var shapeStart: CGPoint?
    @State private var shapeEnd: CGPoint?
    @State private var pendingTextPosition: CGPoint?
    @State private var pendingText = ""

    var body: some View {
        GeometryReader { geometry in
            // Точек экрана на пиксель кадра.
            let scale = geometry.size.width / max(editor.frameSize.width, 1)
            ZStack {
                PencilCanvas(editor: editor, scale: scale)

                if let shape = editor.tool.shape {
                    shapeLayer(shape, scale: scale)
                } else if editor.tool == .text {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            pendingText = ""
                            pendingTextPosition = CGPoint(x: location.x / scale, y: location.y / scale)
                        }
                }

                labelsLayer(scale: scale)
            }
            .alert("Add Text", isPresented: Binding(get: { pendingTextPosition != nil },
                                                    set: { if !$0 { pendingTextPosition = nil } })) {
                TextField("Text", text: $pendingText)
                Button("Add") {
                    if let position = pendingTextPosition {
                        editor.addLabel(pendingText, at: position, fontSize: 20 / scale)
                    }
                    pendingTextPosition = nil
                }
                Button("Cancel", role: .cancel) { pendingTextPosition = nil }
            }
        }
    }

    /// Стрелка / прямоугольник / эллипс: тянем пальцем или Pencil, видим предпросмотр.
    private func shapeLayer(_ kind: ShapeStrokes.Kind, scale: CGFloat) -> some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
            if let shapeStart, let shapeEnd {
                ShapePreview(kind: kind, start: shapeStart, end: shapeEnd)
                    .stroke(Color(uiColor: editor.color),
                            style: StrokeStyle(lineWidth: editor.width, lineCap: .round, lineJoin: .round))
                    .allowsHitTesting(false)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    shapeStart = value.startLocation
                    shapeEnd = value.location
                }
                .onEnded { value in
                    editor.addShape(kind,
                                    from: CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale),
                                    to: CGPoint(x: value.location.x / scale, y: value.location.y / scale),
                                    width: editor.width / scale)
                    shapeStart = nil
                    shapeEnd = nil
                }
        )
    }

    /// Подписи. Ластиком подпись удаляется тапом по ней.
    private func labelsLayer(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(editor.annotation.labels) { label in
                TextLabelView(label: label, scale: scale)
                    .position(x: label.x * scale, y: label.y * scale)
                    .onTapGesture { editor.removeLabel(label.id) }
                    .allowsHitTesting(editor.tool == .eraser)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Подпись на кадре — так же, как она будет нарисована при экспорте.
struct TextLabelView: View {
    let label: TextLabel
    let scale: CGFloat

    var body: some View {
        let size = label.fontSize * scale
        Text(label.text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color(uiColor: UIColor(hex: label.colorHex)))
            .padding(.horizontal, size * 0.3)
            .padding(.vertical, size * 0.15)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: size * 0.3))
            .fixedSize()
    }
}

private struct ShapePreview: Shape {
    let kind: ShapeStrokes.Kind
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch kind {
        case .arrow:
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = hypot(end.x - start.x, end.y - start.y)
            let head = min(max(20, length * 0.25), length * 0.6)
            path.move(to: start)
            path.addLine(to: end)
            path.move(to: CGPoint(x: end.x - head * cos(angle - .pi / 7), y: end.y - head * sin(angle - .pi / 7)))
            path.addLine(to: end)
            path.addLine(to: CGPoint(x: end.x - head * cos(angle + .pi / 7), y: end.y - head * sin(angle + .pi / 7)))
        case .rectangle:
            path.addRect(CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                width: abs(end.x - start.x), height: abs(end.y - start.y)))
        case .ellipse:
            path.addEllipse(in: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                       width: abs(end.x - start.x), height: abs(end.y - start.y)))
        }
        return path
    }
}

/// PKCanvasView: рисует в координатах экрана, а редактор хранит рисунок в координатах кадра.
private struct PencilCanvas: UIViewRepresentable {
    @ObservedObject var editor: AnnotationEditor
    let scale: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.isScrollEnabled = false
        // Светлая тема: в тёмной PencilKit подменяет чёрный на белый и наоборот.
        canvas.overrideUserInterfaceStyle = .light
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.scale = scale
        canvas.isUserInteractionEnabled = editor.tool.isFreehand
        switch editor.tool {
        case .pen: canvas.tool = PKInkingTool(.pen, color: editor.color, width: editor.width)
        case .marker: canvas.tool = PKInkingTool(.marker, color: editor.color, width: editor.width * 4)
        case .eraser: canvas.tool = PKEraserTool(.vector)
        default: break
        }
        if coordinator.appliedRevision != editor.revision || coordinator.appliedScale != scale {
            coordinator.appliedRevision = editor.revision
            coordinator.appliedScale = scale
            coordinator.isApplying = true
            canvas.drawing = editor.annotation.drawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
            coordinator.isApplying = false
        }
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let editor: AnnotationEditor
        var scale: CGFloat = 1
        var appliedRevision = -1
        var appliedScale: CGFloat = 0
        var isApplying = false

        init(editor: AnnotationEditor) {
            self.editor = editor
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplying, scale > 0 else { return }
            editor.canvasChanged(canvasView.drawing.transformed(using: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)))
        }
    }
}

/// Сохранённые пометки поверх видео (только просмотр).
struct AnnotationOverlay: View {
    let annotations: [Annotation]
    let frameSize: CGSize

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / max(frameSize.width, 1)
            ZStack(alignment: .topLeading) {
                ForEach(annotations.indices, id: \.self) { index in
                    let annotation = annotations[index]
                    // Подписи рисуем SwiftUI-текстом — они чётче растровых.
                    Image(uiImage: AnnotationRenderer.overlayImage(annotation, frameSize: frameSize,
                                                                   scale: scale * displayScale, includeLabels: false))
                        .resizable()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    ForEach(annotation.labels) { label in
                        TextLabelView(label: label, scale: scale)
                            .position(x: label.x * scale, y: label.y * scale)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
