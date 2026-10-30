import SwiftUI

/// Сравнение двух версий: шторка, плавный переход или полупрозрачное наложение.
struct CompareScreen: View {
    enum Mode: String, CaseIterable, Identifiable {
        case wipe, dissolve, overlay

        var id: Self { self }
        var title: String {
            switch self {
            case .wipe: "Wipe"
            case .dissolve: "Dissolve"
            case .overlay: "Overlay"
            }
        }
    }

    let a: ReviewVideo
    let b: ReviewVideo

    @StateObject private var model = CompareModel()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("compare.mode") private var mode: Mode = .wipe
    /// Положение шторки: 0 — слева вся B, 1 — вся A.
    @State private var wipePosition: CGFloat = 0.5
    /// Dissolve: 0 — только A, 1 — только B.
    @State private var mix: Double = 0.5
    @State private var isAutoDissolve = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.separator).frame(height: 1)
            if let sideA = model.a, let sideB = model.b {
                viewer(sideA, sideB)
                    .padding(16)
                controls
            } else {
                Group {
                    if let error = model.errorMessage {
                        ContentUnavailableView("Can't Compare", systemImage: "exclamationmark.triangle",
                                               description: Text(error))
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            // Клавиши (пробел, ←/→) ловит непрозрачный фон — прозрачному SwiftUI фокус не даёт.
            Theme.background
                .ignoresSafeArea()
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                .onKeyPress(phases: [.down, .repeat], action: handleKey)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await model.load(a: a, b: b)
            isFocused = true
        }
        .onDisappear { model.close() }
    }

    // MARK: - Шапка

    private var header: some View {
        ZStack {
            Text(a.item?.title ?? "Compare")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 260)
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                versionMenu(label: "A", current: model.a?.video ?? a) { version in
                    Task { await model.load(a: version, b: model.b?.video ?? b) }
                }
                Button("Swap A and B", systemImage: "arrow.left.arrow.right") {
                    guard let sideA = model.a, let sideB = model.b else { return }
                    Task { await model.load(a: sideB.video, b: sideA.video) }
                }
                .labelStyle(.iconOnly)
                versionMenu(label: "B", current: model.b?.video ?? b) { version in
                    Task { await model.load(a: model.a?.video ?? a, b: version) }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 52)
        .background(Theme.panel)
    }

    private func versionMenu(label: String, current: ReviewVideo,
                             onSelect: @escaping (ReviewVideo) -> Void) -> some View {
        Menu {
            ForEach(current.item?.sortedVersions.reversed() ?? []) { version in
                Button {
                    onSelect(version)
                } label: {
                    if version === current {
                        Label("\(version.versionLabel) · \(version.fileName)", systemImage: "checkmark")
                    } else {
                        Text("\(version.versionLabel) · \(version.fileName)")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(label): \(current.versionLabel)").font(.subheadline.weight(.bold))
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Картинка

    private func viewer(_ sideA: CompareModel.Side, _ sideB: CompareModel.Side) -> some View {
        let size = sideA.info.naturalSize
        return ZStack {
            PlayerLayerView(player: sideA.player)
            PlayerLayerView(player: sideB.player)
                .opacity(opacityOfB)
                .mask {
                    GeometryReader { geometry in
                        Rectangle()
                            .frame(width: mode == .wipe ? geometry.size.width * (1 - wipePosition) : geometry.size.width)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            if mode == .wipe {
                wipeHandle
            }
        }
        .aspectRatio(size.width > 0 ? size.width / size.height : 16 / 9, contentMode: .fit)
        .overlay(alignment: .bottomLeading) { badge("A · \(sideA.video.versionLabel)", visible: showsA) }
        .overlay(alignment: .bottomTrailing) { badge("B · \(sideB.video.versionLabel)", visible: showsB) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var opacityOfB: Double {
        switch mode {
        case .wipe: 1
        case .dissolve: mix
        case .overlay: 0.5
        }
    }

    private var showsA: Bool { mode != .dissolve || mix < 1 }
    private var showsB: Bool { mode != .dissolve || mix > 0 }

    /// Вертикальная линия с ручкой; тянуть можно в любом месте кадра.
    private var wipeHandle: some View {
        GeometryReader { geometry in
            let x = geometry.size.width * wipePosition
            ZStack {
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .shadow(radius: 2)
                    .position(x: x, y: geometry.size.height / 2)
                    .frame(height: geometry.size.height)
                Circle()
                    .fill(.white)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "arrow.left.and.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.black)
                    }
                    .shadow(radius: 3)
                    .position(x: x, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        wipePosition = min(max(value.location.x / max(geometry.size.width, 1), 0), 1)
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Wipe position")
        .accessibilityValue("\(Int(wipePosition * 100)) percent")
    }

    private func badge(_ text: String, visible: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(.white)
            .padding(10)
            .opacity(visible ? 1 : 0.35)
            .allowsHitTesting(false)
    }

    // MARK: - Управление

    private var controls: some View {
        VStack(spacing: 10) {
            ScrubberView(frame: model.currentFrame, frameCount: max(model.frameCount, 1)) { model.scrub(toFrame: $0) }
            HStack(spacing: 18) {
                Button("Previous Frame", systemImage: "backward.frame") { model.step(by: -1) }
                Button(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                    model.togglePlayPause()
                }
                .font(.title2)
                Button("Next Frame", systemImage: "forward.frame") { model.step(by: 1) }
                Text(model.timecode)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize()
                Spacer(minLength: 12)
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.textPrimary)
            modeControls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.panel)
        .onChange(of: mode) { _, _ in stopAutoDissolve() }
    }

    @ViewBuilder
    private var modeControls: some View {
        if mode == .dissolve {
            HStack(spacing: 8) {
                Text("A").font(.caption.weight(.bold))
                Slider(value: $mix, in: 0...1)
                    .frame(maxWidth: 360)
                    .disabled(isAutoDissolve)
                Text("B").font(.caption.weight(.bold))
                Button(isAutoDissolve ? "Stop" : "Auto",
                       systemImage: isAutoDissolve ? "stop.circle" : "arrow.triangle.2.circlepath") {
                    isAutoDissolve ? stopAutoDissolve() : startAutoDissolve()
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .fixedSize()
            }
            .foregroundStyle(Theme.textPrimary)
        }
    }

    /// Авто-дизолв: A → B → A по кругу, чтобы разница «мигала».
    private func startAutoDissolve() {
        isAutoDissolve = true
        mix = 0
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            mix = 1
        }
    }

    private func stopAutoDissolve() {
        guard isAutoDissolve else { return }
        isAutoDissolve = false
        withAnimation(.easeOut(duration: 0.2)) { mix = 0.5 }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let step = press.modifiers.contains(.shift) ? 10 : 1
        switch press.key {
        case .space:
            if press.phase == .down { model.togglePlayPause() }
            return .handled
        case .leftArrow:
            model.step(by: -step)
            return .handled
        case .rightArrow:
            model.step(by: step)
            return .handled
        default:
            return .ignored
        }
    }
}
