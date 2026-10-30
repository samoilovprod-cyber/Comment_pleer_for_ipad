import SwiftUI

/// Панель режима рисования: инструменты, цвет, толщина, отмена/повтор, очистка, выход.
struct AnnotationToolbar: View {
    @ObservedObject var editor: AnnotationEditor
    /// Правка рисунка сохранённого комментария — показываем «Save».
    let onSave: (() -> Void)?
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(AnnotationEditor.Tool.allCases) { tool in
                    Button {
                        editor.tool = tool
                    } label: {
                        Image(systemName: tool.systemImage)
                            .frame(width: 34, height: 30)
                            .background(editor.tool == tool ? Theme.accent.opacity(0.35) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .accessibilityLabel(tool.title)
                    .accessibilityAddTraits(editor.tool == tool ? .isSelected : [])
                }
            }

            divider

            HStack(spacing: 6) {
                ForEach(AnnotationPalette.colors, id: \.self) { hex in
                    Button {
                        editor.colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 20, height: 20)
                            .overlay {
                                Circle().strokeBorder(Color.white.opacity(editor.colorHex == hex ? 1 : 0.25),
                                                      lineWidth: editor.colorHex == hex ? 2 : 1)
                            }
                    }
                    .accessibilityLabel("Color")
                }
            }

            divider

            HStack(spacing: 4) {
                ForEach(AnnotationEditor.widths, id: \.self) { width in
                    Button {
                        editor.width = width
                    } label: {
                        Capsule()
                            .fill(Theme.textPrimary)
                            .frame(width: 16, height: width + 1)
                            .frame(width: 28, height: 30)
                            .background(editor.width == width ? Theme.accent.opacity(0.35) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .accessibilityLabel("Line width \(Int(width))")
                }
            }

            divider

            Button("Undo", systemImage: "arrow.uturn.backward") { editor.undo() }
                .disabled(!editor.canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward") { editor.redo() }
                .disabled(!editor.canRedo)
            Button("Clear", systemImage: "trash") { editor.clear() }
                .disabled(editor.annotation.isEmpty)

            Spacer(minLength: 4)

            Button("Cancel", action: onCancel)
            if let onSave {
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.textPrimary)
        .font(.body)
    }

    private var divider: some View {
        Rectangle().fill(Theme.separator).frame(width: 1, height: 22)
    }
}
