import FrameTimecode
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PlayerScreen: View {
    /// Сколько точек горизонтального свайпа по видео — один кадр.
    private static let jogPointsPerFrame: CGFloat = 8

    @StateObject private var model = PlayerModel()
    @State private var isImporting = false
    @State private var isPickingFromPhotos = false
    @State private var photosSelection: PhotosPickerItem?
    @State private var isCopyingVideo = false
    @State private var isDropTargeted = false
    @State private var jogStartFrame: Int?
    @State private var timecodeInput = ""
    @State private var timecodeInputError: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var commentText = ""
    @State private var isGoToTimecodeShown = false
    @State private var isMediaInfoShown = false
    @State private var startTimecodeInput = ""
    @State private var startTimecodeError: String?
    @FocusState private var isCommentFocused: Bool
    /// Плеер держит фокус клавиатуры, когда не идёт ввод текста, — так клавиши не уводят курсор в поля.
    @FocusState private var isPlayerFocused: Bool
    /// K зажата: J/L шагают по кадру, как в монтажных программах.
    @State private var isKHeld = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.separator).frame(height: 1)
            if let info = model.info {
                keyHandling(reviewLayout(info: info))
            } else {
                emptyState
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .overlay {
            if isCopyingVideo {
                ProgressView("Copying video…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if isDropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 4, dash: [12]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        // Перетаскивание из «Файлов», «Фото» и других приложений в Split View / Stage Manager.
        .dropDestination(for: PickedMovie.self) { movies, _ in
            guard let movie = movies.first else { return false }
            Task { await model.open(url: movie.url, isImportedCopy: true) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.movie, .quickTimeMovie, .mpeg4Movie]) { result in
            if case let .success(url) = result {
                Task { await model.open(url: url) }
            }
        }
        // .current — без перекодирования: сохраняем исходные кадры, частоту и трек тайм-кода.
        .photosPicker(isPresented: $isPickingFromPhotos, selection: $photosSelection,
                      matching: .videos, preferredItemEncoding: .current)
        .onChange(of: photosSelection) { _, item in
            guard let item else { return }
            photosSelection = nil
            Task { await openFromPhotos(item) }
        }
        .sheet(isPresented: $isMediaInfoShown) {
            if let asset = model.asset {
                MediaInfoSheet(asset: asset, timecode: model.info)
            }
        }
        .onChange(of: isMediaInfoShown) { _, shown in
            if !shown { isPlayerFocused = true }
        }
        .task { await model.restoreLastVideo() }
        .alert("Couldn't open the video", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// Шапка: кнопка открытия слева, имя файла и параметры видео по центру.
    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(model.fileName ?? "Comment Player")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let info = model.info {
                    headerSubtitle(info)
                }
            }
            .padding(.horizontal, 140)

            HStack {
                Menu {
                    openSourceButtons
                } label: {
                    Label("Open", systemImage: "film")
                        .font(.subheadline.weight(.medium))
                }
                .disabled(isCopyingVideo)
                Spacer()
                if model.asset != nil {
                    Button("File info", systemImage: "info.circle") { isMediaInfoShown = true }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 52)
        .background(Theme.panel)
    }

    private func headerSubtitle(_ info: VideoTimecodeInfo) -> some View {
        HStack(spacing: 6) {
            Text("\(info.rate.description) fps")
            Text("·")
            Text(Self.sourceLabel(info.source))
                .foregroundStyle(info.source == .assumedZero ? Color.orange : Theme.textSecondary)
            Text("·")
            Text("Frame \(model.currentFrame + 1) / \(info.frameCount)")
            if info.isLikelyVariableFrameRate {
                Text("·")
                Label("Variable frame rate", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Timecode and frame stepping may be inaccurate.")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
    }

    private static func sourceLabel(_ source: VideoTimecodeInfo.Source) -> String {
        switch source {
        case .embedded: "TC from file"
        case .assumedZero: "No TC — starting at 00:00:00:00"
        case .manual: "TC set manually"
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Video", systemImage: "film.stack")
        } description: {
            Text("Open a MOV or MP4 (ProRes, H.264, HEVC) or drop a file here.")
        } actions: {
            HStack {
                openSourceButtons
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCopyingVideo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var openSourceButtons: some View {
        Button("From Files", systemImage: "folder") { isImporting = true }
        Button("From Photos", systemImage: "photo.on.rectangle") { isPickingFromPhotos = true }
    }

    private func openFromPhotos(_ item: PhotosPickerItem) async {
        isCopyingVideo = true
        defer { isCopyingVideo = false }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                model.errorMessage = "The selected item is not a video."
                return
            }
            await model.open(url: movie.url, isImportedCopy: true)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    /// Видео с панелью управления и полем комментария; справа — список комментариев
    /// (в узком окне Split View — снизу).
    @ViewBuilder
    private func reviewLayout(info: VideoTimecodeInfo) -> some View {
        let comments = CommentsPanel(comments: model.comments,
                                     currentFrame: model.currentFrame,
                                     timecode: model.timecode(forFrame:),
                                     onSelect: { model.scrub(toFrame: $0.frame) },
                                     onDelete: model.deleteComment)
        if horizontalSizeClass == .compact {
            VStack(spacing: 0) {
                playerColumn(info: info)
                comments.frame(height: 260)
            }
        } else {
            HStack(spacing: 0) {
                playerColumn(info: info)
                Rectangle().fill(Theme.separator).frame(width: 1)
                comments.frame(width: 320)
            }
        }
    }

    /// Всё, что ловит клавиши плеера, когда фокус не в текстовом поле.
    private func keyHandling<Content: View>(_ content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($isPlayerFocused)
            .onKeyPress(phases: [.down, .repeat, .up], action: handleKey)
            .onAppear { isPlayerFocused = true }
            .onChange(of: isCommentFocused) { _, focused in
                if !focused { isPlayerFocused = true }
            }
            .onChange(of: isGoToTimecodeShown) { _, shown in
                if !shown { isPlayerFocused = true }
            }
    }

    private func playerColumn(info: VideoTimecodeInfo) -> some View {
        VStack(spacing: 0) {
            PlayerLayerView(player: model.player)
                .aspectRatio(info.naturalSize.width > 0 ? info.naturalSize.width / info.naturalSize.height : 16 / 9,
                             contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(jogGesture)
                .onTapGesture { isCommentFocused = false; isPlayerFocused = true }
                .padding(16)

            controlBar(info: info)
            Rectangle().fill(Theme.separator).frame(height: 1)
            commentComposer
        }
    }

    /// Панель под видео: таймлайн, транспорт, тайм-код, скорость.
    private func controlBar(info: VideoTimecodeInfo) -> some View {
        VStack(spacing: 4) {
            ScrubberView(frame: model.currentFrame, frameCount: info.frameCount,
                         markers: model.comments.map(\.frame)) { model.scrub(toFrame: $0) }

            HStack(spacing: 12) {
                transportControls
                Spacer(minLength: 8)
                timecodeButton(info: info)
                Spacer(minLength: 8)
                speedMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Theme.panel)
    }

    /// Текущий тайм-код; тап — переход к введённому тайм-коду.
    private func timecodeButton(info: VideoTimecodeInfo) -> some View {
        Button {
            timecodeInput = ""
            timecodeInputError = nil
            startTimecodeInput = ""
            startTimecodeError = nil
            isGoToTimecodeShown = true
        } label: {
            HStack(spacing: 6) {
                Text(model.currentTimecode?.description ?? "--:--:--:--")
                    .foregroundStyle(Theme.textPrimary)
                Text("/ \(info.endTimecode.description)")
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.system(.body, design: .monospaced).weight(.medium))
            .lineLimit(1)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isGoToTimecodeShown) { timecodeEntry }
    }

    /// Поле комментария: тайм-код текущего кадра, видео ставится на паузу, как только начинаете писать.
    private var commentComposer: some View {
        HStack(spacing: 10) {
            TextField("Leave a comment…", text: $commentText, axis: .vertical)
                .lineLimit(1...4)
                .focused($isCommentFocused)
                .foregroundStyle(Theme.textPrimary)
                .onSubmit(submitComment)
                .onKeyPress(.escape) {
                    isCommentFocused = false
                    return .handled
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: isCommentFocused) { _, focused in
                    if focused, model.isPlaying { model.stop() }
                }

            TimecodeChip(text: model.currentTimecode?.description ?? "--:--:--:--", isProminent: true)

            Button("Submit", action: submitComment)
                .buttonStyle(.borderedProminent)
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(Theme.panel)
    }

    private func submitComment() {
        model.addComment(commentText)
        commentText = ""
        isCommentFocused = false
    }

    /// Jog: горизонтальный свайп по видео — покадровый скраб от кадра, где начался жест.
    private var jogGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let start = jogStartFrame ?? model.currentFrame
                jogStartFrame = start
                model.scrub(toFrame: start + Int(value.translation.width / Self.jogPointsPerFrame))
            }
            .onEnded { _ in jogStartFrame = nil }
    }

    private var transportControls: some View {
        HStack(spacing: 14) {
            Button("Back 1 second", systemImage: "gobackward") { model.step(seconds: -1) }
            Button("Back 10 frames", systemImage: "backward.end.alt") { model.step(by: -10) }
            Button("Back 1 frame", systemImage: "backward.frame") { model.step(by: -1) }
            Button(model.isPlaying ? "Pause" : "Play",
                   systemImage: model.isPlaying ? "pause.fill" : "play.fill") { model.togglePlayPause() }
                .font(.title)
                .frame(width: 36)
                .buttonRepeatBehavior(.disabled)
            Button("Forward 1 frame", systemImage: "forward.frame") { model.step(by: 1) }
            Button("Forward 10 frames", systemImage: "forward.end.alt") { model.step(by: 10) }
            Button("Forward 1 second", systemImage: "goforward") { model.step(seconds: 1) }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .foregroundStyle(Theme.textPrimary)
        .buttonStyle(.borderless)
        // Удержание кнопки шага — кадры «прокручиваются», пока палец на кнопке.
        .buttonRepeatBehavior(.enabled)
    }

    private var speedMenu: some View {
        Menu {
            Picker("Speed", selection: Binding(get: { model.speed }, set: { model.setSpeed($0) })) {
                ForEach(PlayerModel.speeds, id: \.self) { speed in
                    Text(Self.speedLabel(speed)).tag(speed)
                }
            }
        } label: {
            Text(Self.speedLabel(model.speed))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 4))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private static func speedLabel(_ speed: Float) -> String {
        speed.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    /// Клавиатура: пробел, ←/→ (⇧ — 10 кадров, ⌥ — секунда), J/K/L; K+J/L — шаг по кадру.
    /// Русская раскладка тоже работает: О/Л/Д на месте J/K/L.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let isPressed = press.phase != .up
        switch press.key {
        case .space:
            if press.phase == .down { model.togglePlayPause() }
            return .handled
        case .leftArrow, .rightArrow:
            guard isPressed else { return .handled }
            let direction = press.key == .rightArrow ? 1 : -1
            if press.modifiers.contains(.option) {
                model.step(seconds: direction)
            } else if press.modifiers.contains(.shift) {
                model.step(by: direction * 10)
            } else {
                model.step(by: direction)
            }
            return .handled
        default:
            break
        }
        switch press.characters.lowercased() {
        case "k", "л":
            isKHeld = isPressed
            if press.phase == .down { model.stop() }
            return .handled
        case "j", "о", "l", "д":
            let forward = ["l", "д"].contains(press.characters.lowercased())
            if isKHeld {
                // Удержание K + J/L с автоповтором — покадровая «прокрутка».
                if isPressed { model.step(by: forward ? 1 : -1) }
            } else if press.phase == .down {
                model.shuttle(forward: forward)
            }
            return .handled
        default:
            return .ignored
        }
    }

    private var timecodeEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Go to Timecode").font(.headline)
            HStack {
                TextField("01:00:10:05", text: $timecodeInput)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.body.monospaced())
                    .frame(width: 200)
                    .onSubmit(goToTimecode)
                Button("Go", action: goToTimecode)
                    .buttonStyle(.borderedProminent)
            }
            if let timecodeInputError {
                Text(timecodeInputError)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Divider().padding(.vertical, 6)

            Text("Start Timecode").font(.headline)
            Text("If the file has no timecode or it's wrong, set the first frame's timecode here. Remembered for this file.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField(model.info?.startTimecode.description ?? "00:00:00:00", text: $startTimecodeInput)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.body.monospaced())
                    .frame(width: 200)
                    .onSubmit(applyStartTimecode)
                Button("Set", action: applyStartTimecode)
                    .buttonStyle(.bordered)
            }
            if let startTimecodeError {
                Text(startTimecodeError)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
            if model.info?.source == .manual {
                Button("Reset to File Timecode", systemImage: "arrow.uturn.backward") {
                    model.resetStartTimecode()
                }
                .font(.footnote)
            }
        }
        .padding()
        .frame(width: 340)
    }

    private func applyStartTimecode() {
        guard let rate = model.info?.rate else { return }
        do {
            model.setStartTimecode(try Timecode(startTimecodeInput, rate: rate))
            startTimecodeInput = ""
            startTimecodeError = nil
        } catch TimecodeError.droppedFrameNumber {
            startTimecodeError = "This frame number doesn't exist in drop-frame"
        } catch {
            startTimecodeError = "Invalid timecode"
        }
    }

    private func goToTimecode() {
        guard let rate = model.info?.rate else { return }
        do {
            let timecode = try Timecode(timecodeInput, rate: rate)
            timecodeInputError = model.seek(to: timecode) ? nil : "Timecode is outside the video"
            if timecodeInputError == nil { isGoToTimecodeShown = false }
        } catch TimecodeError.droppedFrameNumber {
            timecodeInputError = "This frame number doesn't exist in drop-frame"
        } catch {
            timecodeInputError = "Invalid timecode"
        }
    }
}
