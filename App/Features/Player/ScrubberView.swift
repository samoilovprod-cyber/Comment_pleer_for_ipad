import SwiftUI

/// Таймлайн: тап или перетаскивание ставит видео ровно на кадр под пальцем.
struct ScrubberView: View {
    let frame: Int
    let frameCount: Int
    let onScrub: (Int) -> Void

    @State private var isDragging = false

    private let trackHeight: CGFloat = 6
    private let thumbSize: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - thumbSize, 1)
            let thumbX = CGFloat(progress) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: trackHeight)
                Capsule()
                    .fill(.tint)
                    .frame(width: thumbX + thumbSize / 2, height: trackHeight)
                Circle()
                    .fill(.white)
                    .shadow(radius: isDragging ? 4 : 2)
                    .frame(width: thumbSize, height: thumbSize)
                    .scaleEffect(isDragging ? 1.2 : 1)
                    .offset(x: thumbX)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        onScrub(frame(atX: value.location.x - thumbSize / 2, width: width))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .animation(.easeOut(duration: 0.15), value: isDragging)
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Таймлайн")
        .accessibilityValue("Кадр \(frame + 1) из \(frameCount)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onScrub(frame + 1)
            case .decrement: onScrub(frame - 1)
            @unknown default: break
            }
        }
    }

    private var progress: Double {
        frameCount > 1 ? Double(frame) / Double(frameCount - 1) : 0
    }

    private func frame(atX x: CGFloat, width: CGFloat) -> Int {
        let fraction = min(max(x / width, 0), 1)
        return Int((fraction * CGFloat(frameCount - 1)).rounded())
    }
}
