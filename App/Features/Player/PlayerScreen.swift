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
    @FocusState private var isCommentFocused: Bool
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.separator).frame(height: 1)
            if let info = model.info {
                reviewLayout(info: info)
            } else {
                emptyState
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .overlay {
            if isCopyingVideo {
                ProgressView("Копирование видео…")
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
        .task { await model.restoreLastVideo() }
        .alert("Не удалось открыть видео", isPresented: .constant(model.errorMessage != nil)) {
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
                    Label("Открыть", systemImage: "film")
                        .font(.subheadline.weight(.medium))
                }
                .disabled(isCopyingVideo)
                Spacer()
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
            Text(info.source == .embedded ? "TC из файла" : "TC не найден — с 00:00:00:00")
                .foregroundStyle(info.source == .embedded ? Theme.textSecondary : Color.orange)
            Text("·")
            Text("Кадр \(model.currentFrame + 1) / \(info.frameCount)")
            if info.isLikelyVariableFrameRate {
                Text("·")
                Label("Переменная частота кадров", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Тайм-код и шаг по кадрам могут быть неточными.")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Нет видео", systemImage: "film.stack")
        } description: {
            Text("Откройте MOV или MP4 (ProRes, H.264, HEVC) или перетащите файл сюда.")
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
        Button("Из «Файлов»", systemImage: "folder") { isImporting = true }
        Button("Из «Фото»", systemImage: "photo.on.rectangle") { isPickingFromPhotos = true }
    }

    private func openFromPhotos(_ item: PhotosPickerItem) async {
        isCopyingVideo = true
        defer { isCopyingVideo = false }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                model.errorMessage = "Выбранный объект не является видео."
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
                                     onDelete: model.deleteComment,
                                     isSearchFocused: $isSearchFocused)
        if horizontalSizeClass == .compact {
            VStack(spacing: 0) {
                playerColumn(info: info)
                comments.frame(height: 260)
            }
            .background { keyboardShortcuts }
        } else {
            HStack(spacing: 0) {
                playerColumn(info: info)
                Rectangle().fill(Theme.separator).frame(width: 1)
                comments.frame(width: 320)
            }
            .background { keyboardShortcuts }
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
            TextField("Оставьте комментарий…", text: $commentText, axis: .vertical)
                .lineLimit(1...4)
                .focused($isCommentFocused)
                .foregroundStyle(Theme.textPrimary)
                .onSubmit(submitComment)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: isCommentFocused) { _, focused in
                    if focused, model.isPlaying { model.stop() }
                }

            TimecodeChip(text: model.currentTimecode?.description ?? "--:--:--:--", isProminent: true)

            Button("Отправить", action: submitComment)
                .buttonStyle(.borderedProminent)
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(Theme.panel)
    }

    /// Пока пользователь печатает, одиночные клавиши (пробел, J/K/L, стрелки) должны попадать в текст, а не в плеер.
    private func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers) -> KeyboardShortcut? {
        isCommentFocused || isSearchFocused || isGoToTimecodeShown ? nil : KeyboardShortcut(key, modifiers: modifiers)
    }

    private func submitComment() {
        model.addComment(commentText)
        commentText = ""
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
            Button("−1 секунда", systemImage: "gobackward") { model.step(seconds: -1) }
                .keyboardShortcut(shortcut(.leftArrow, .option))
            Button("−10 кадров", systemImage: "backward.end.alt") { model.step(by: -10) }
                .keyboardShortcut(shortcut(.leftArrow, .shift))
            Button("−1 кадр", systemImage: "backward.frame") { model.step(by: -1) }
                .keyboardShortcut(shortcut(.leftArrow, []))
            Button(model.isPlaying ? "Пауза" : "Играть",
                   systemImage: model.isPlaying ? "pause.fill" : "play.fill") { model.togglePlayPause() }
                .keyboardShortcut(shortcut(.space, []))
                .font(.title)
                .frame(width: 36)
                .buttonRepeatBehavior(.disabled)
            Button("+1 кадр", systemImage: "forward.frame") { model.step(by: 1) }
                .keyboardShortcut(shortcut(.rightArrow, []))
            Button("+10 кадров", systemImage: "forward.end.alt") { model.step(by: 10) }
                .keyboardShortcut(shortcut(.rightArrow, .shift))
            Button("+1 секунда", systemImage: "goforward") { model.step(seconds: 1) }
                .keyboardShortcut(shortcut(.rightArrow, .option))
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
            Picker("Скорость", selection: Binding(get: { model.speed }, set: { model.setSpeed($0) })) {
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

    /// J/K/L как в монтажных программах. Кнопки невидимые — нужны только ради сочетаний клавиш.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("Назад (J)") { model.shuttle(forward: false) }
                .keyboardShortcut(shortcut("j", []))
            Button("Стоп (K)") { model.stop() }
                .keyboardShortcut(shortcut("k", []))
            Button("Вперёд (L)") { model.shuttle(forward: true) }
                .keyboardShortcut(shortcut("l", []))
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var timecodeEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Перейти к тайм-коду").font(.headline)
            HStack {
                TextField("01:00:10:05", text: $timecodeInput)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.body.monospaced())
                    .frame(width: 200)
                    .onSubmit(goToTimecode)
                Button("Перейти", action: goToTimecode)
                    .buttonStyle(.borderedProminent)
            }
            if let timecodeInputError {
                Text(timecodeInputError)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
        .padding()
    }

    private func goToTimecode() {
        guard let rate = model.info?.rate else { return }
        do {
            let timecode = try Timecode(timecodeInput, rate: rate)
            timecodeInputError = model.seek(to: timecode) ? nil : "Тайм-код вне видео"
            if timecodeInputError == nil { isGoToTimecodeShown = false }
        } catch TimecodeError.droppedFrameNumber {
            timecodeInputError = "Такого номера кадра нет в drop-frame"
        } catch {
            timecodeInputError = "Неверный тайм-код"
        }
    }
}
