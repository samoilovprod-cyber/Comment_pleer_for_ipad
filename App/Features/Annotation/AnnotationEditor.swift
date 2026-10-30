import PencilKit
import SwiftUI

/// Состояние режима рисования: инструмент, цвет, толщина, рисунок и история для отмены.
@MainActor
final class AnnotationEditor: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case pen, marker, eraser, arrow, rectangle, ellipse, text

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pen: "Pen"
            case .marker: "Marker"
            case .eraser: "Eraser"
            case .arrow: "Arrow"
            case .rectangle: "Rectangle"
            case .ellipse: "Ellipse"
            case .text: "Text"
            }
        }

        var systemImage: String {
            switch self {
            case .pen: "pencil.tip"
            case .marker: "highlighter"
            case .eraser: "eraser"
            case .arrow: "arrow.up.right"
            case .rectangle: "rectangle"
            case .ellipse: "circle"
            case .text: "textformat"
            }
        }

        /// Рисуется самим PencilKit; остальные инструменты — наши жесты поверх холста.
        var isFreehand: Bool { self == .pen || self == .marker || self == .eraser }

        var shape: ShapeStrokes.Kind? {
            switch self {
            case .arrow: .arrow
            case .rectangle: .rectangle
            case .ellipse: .ellipse
            default: nil
            }
        }
    }

    /// Толщина в точках экрана: тонко, средне, толсто.
    static let widths: [CGFloat] = [2, 4, 8]

    @Published var tool = Tool.pen
    @Published var colorHex = AnnotationPalette.colors[0]
    @Published var width = AnnotationEditor.widths[1]
    @Published private(set) var annotation = Annotation()
    /// Меняется, когда холст должен заново взять рисунок (отмена, фигура, очистка).
    @Published private(set) var revision = 0
    @Published private(set) var isActive = false

    /// Кадр, на котором рисуем, и его размер в пикселях.
    private(set) var frame = 0
    private(set) var frameSize = CGSize(width: 1920, height: 1080)
    /// Если правим рисунок уже сохранённого комментария.
    private(set) var comment: ReviewComment?

    private var undoStack: [Annotation] = []
    private var redoStack: [Annotation] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var color: UIColor { UIColor(hex: colorHex) }

    func begin(frame: Int, frameSize: CGSize, annotation: Annotation? = nil, comment: ReviewComment? = nil) {
        self.frame = frame
        self.frameSize = frameSize
        self.comment = comment
        self.annotation = annotation ?? Annotation()
        undoStack = []
        redoStack = []
        revision += 1
        isActive = true
    }

    func end() {
        isActive = false
        comment = nil
        annotation = Annotation()
        undoStack = []
        redoStack = []
        revision += 1
    }

    /// Пользователь провёл штрих или стёр его на холсте — холст уже показывает изменение.
    func canvasChanged(_ drawing: PKDrawing) {
        pushUndo()
        annotation.drawing = drawing
    }

    func addShape(_ kind: ShapeStrokes.Kind, from start: CGPoint, to end: CGPoint, width: CGFloat) {
        guard hypot(end.x - start.x, end.y - start.y) > width else { return }
        pushUndo()
        annotation.drawing.strokes += ShapeStrokes.make(kind, from: start, to: end, color: color, width: width)
        revision += 1
    }

    func addLabel(_ text: String, at position: CGPoint, fontSize: CGFloat) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        pushUndo()
        annotation.labels.append(TextLabel(text: text, x: position.x, y: position.y,
                                           colorHex: colorHex, fontSize: fontSize))
    }

    func removeLabel(_ id: TextLabel.ID) {
        pushUndo()
        annotation.labels.removeAll { $0.id == id }
    }

    func clear() {
        guard !annotation.isEmpty else { return }
        pushUndo()
        annotation = Annotation()
        revision += 1
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotation)
        annotation = previous
        revision += 1
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotation)
        annotation = next
        revision += 1
    }

    private func pushUndo() {
        undoStack.append(annotation)
        if undoStack.count > 200 {
            undoStack.removeFirst()
        }
        redoStack = []
    }
}
