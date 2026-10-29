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

    var body: some View {
        NavigationStack {
            Group {
                if let info = model.info {
                    playerContent(info: info)
                } else {
                    emptyState
                }
            }
            .navigationTitle(model.fileName ?? "Comment Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Открыть видео", systemImage: "film") { openSourceButtons }
                        .disabled(isCopyingVideo)
                }
            }
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
        }
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

    private func playerContent(info: VideoTimecodeInfo) -> some View {
        VStack(spacing: 16) {
            PlayerLayerView(player: model.player)
                .aspectRatio(info.naturalSize.width > 0 ? info.naturalSize.width / info.naturalSize.height : 16 / 9,
                             contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(jogGesture)

            Text(model.currentTimecode?.description ?? "--:--:--:--")
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .monospacedDigit()

            ScrubberView(frame: model.currentFrame, frameCount: info.frameCount) { model.scrub(toFrame: $0) }

            transportControls
            timecodeEntry
            infoBar(info)
        }
        .padding()
        .background { keyboardShortcuts }
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
        HStack(spacing: 20) {
            Button("−1 секунда", systemImage: "gobackward") { model.step(seconds: -1) }
                .keyboardShortcut(.leftArrow, modifiers: .option)
            Button("−10 кадров", systemImage: "backward.end.alt") { model.step(by: -10) }
                .keyboardShortcut(.leftArrow, modifiers: .shift)
            Button("−1 кадр", systemImage: "backward.frame") { model.step(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button(model.isPlaying ? "Пауза" : "Играть",
                   systemImage: model.isPlaying ? "pause.fill" : "play.fill") { model.togglePlayPause() }
                .keyboardShortcut(.space, modifiers: [])
                .font(.title)
                .buttonRepeatBehavior(.disabled)
            Button("+1 кадр", systemImage: "forward.frame") { model.step(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("+10 кадров", systemImage: "forward.end.alt") { model.step(by: 10) }
                .keyboardShortcut(.rightArrow, modifiers: .shift)
            Button("+1 секунда", systemImage: "goforward") { model.step(seconds: 1) }
                .keyboardShortcut(.rightArrow, modifiers: .option)

            speedMenu
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .buttonStyle(.bordered)
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
                .font(.body.monospacedDigit())
                .frame(minWidth: 44)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
    }

    private static func speedLabel(_ speed: Float) -> String {
        speed.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    /// J/K/L как в монтажных программах. Кнопки невидимые — нужны только ради сочетаний клавиш.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("Назад (J)") { model.shuttle(forward: false) }
                .keyboardShortcut("j", modifiers: [])
            Button("Стоп (K)") { model.stop() }
                .keyboardShortcut("k", modifiers: [])
            Button("Вперёд (L)") { model.shuttle(forward: true) }
                .keyboardShortcut("l", modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var timecodeEntry: some View {
        HStack {
            TextField("Перейти к тайм-коду, например 01:00:10:05", text: $timecodeInput)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .font(.body.monospaced())
                .frame(maxWidth: 360)
                .onSubmit(goToTimecode)
            Button("Перейти", action: goToTimecode)
            if let timecodeInputError {
                Text(timecodeInputError)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
    }

    private func infoBar(_ info: VideoTimecodeInfo) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 20) {
                Text("\(info.rate.description) fps")
                Text("Начало \(info.startTimecode.description)")
                Text("Конец \(info.endTimecode.description)")
                Text("Кадр \(model.currentFrame + 1) / \(info.frameCount)")
                Text(info.source == .embedded ? "TC из файла" : "TC не найден — с 00:00:00:00")
                    .foregroundStyle(info.source == .embedded ? Color.secondary : Color.orange)
            }
            if info.isLikelyVariableFrameRate {
                Text("Похоже на переменную частоту кадров — тайм-код и шаг по кадрам могут быть неточными.")
                    .foregroundStyle(.orange)
            }
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func goToTimecode() {
        guard let rate = model.info?.rate else { return }
        do {
            let timecode = try Timecode(timecodeInput, rate: rate)
            timecodeInputError = model.seek(to: timecode) ? nil : "Тайм-код вне видео"
        } catch TimecodeError.droppedFrameNumber {
            timecodeInputError = "Такого номера кадра нет в drop-frame"
        } catch {
            timecodeInputError = "Неверный тайм-код"
        }
    }
}
