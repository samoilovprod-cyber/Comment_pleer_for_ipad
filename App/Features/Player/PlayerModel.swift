import AVFoundation
import FrameTimecode
import SwiftData

@MainActor
final class PlayerModel: ObservableObject {
    static let speeds: [Float] = [0.25, 0.5, 1, 1.5, 2]

    @Published private(set) var info: VideoTimecodeInfo?
    @Published private(set) var currentFrame = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var fileName: String?
    @Published private(set) var speed: Float = 1
    @Published private(set) var comments: [ReviewComment] = []
    @Published var errorMessage: String?

    let player = AVPlayer()

    /// Начало тайм-кода, прочитанное из файла, — чтобы вернуться к нему после ручной правки.
    private var detectedStart: (timecode: Timecode, source: VideoTimecodeInfo.Source)?
    private(set) var asset: AVURLAsset?

    private var modelContext: ModelContext?
    private var video: ReviewVideo?

    private var timeObserver: Any?
    private var rateObserver: NSKeyValueObservation?
    private var accessedURL: URL?
    /// Наша копия видео из «Фото» или перетащенного файла — удаляем её при закрытии.
    private var importedCopyURL: URL?
    private var isSeekInFlight = false
    /// Куда перемотать, когда закончится текущая перемотка: при скрабе и удержании кнопок важна только последняя цель.
    private var queuedSeekFrame: Int?
    /// Множитель J/L: 1, 2, 4… со знаком направления; 0 — не в режиме J/L.
    private var shuttleRate: Float = 0

    var currentTimecode: Timecode? {
        info.map { $0.startTimecode + currentFrame }
    }

    /// Хранилище комментариев — подключается из View, где доступен `modelContext`.
    func attach(_ context: ModelContext) {
        modelContext = context
    }

    func open(url: URL, isImportedCopy: Bool = false) async {
        close()
        if isImportedCopy {
            importedCopyURL = url
        } else if url.startAccessingSecurityScopedResource() {
            accessedURL = url
        }
        fileName = url.lastPathComponent

        // Точная длительность и тайминг важны для покадровой навигации.
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        do {
            var info = try await VideoTimecodeReader.read(from: asset)
            detectedStart = (info.startTimecode, info.source)
            if let manual = StartTimecodeStore.load(fileName: url.lastPathComponent, frameCount: info.frameCount, rate: info.rate) {
                info.startTimecode = manual
                info.source = .manual
            }
            self.info = info
            self.asset = asset
            loadComments(fileName: url.lastPathComponent, frameCount: info.frameCount)
            currentFrame = 0
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            player.defaultRate = speed
            observePlayer(frameDuration: info.rate.frameDuration)
            LastVideoStore.save(url: url, isImportedCopy: isImportedCopy)
        } catch {
            errorMessage = error.localizedDescription
            close()
        }
    }

    /// Открывает видео, которое было открыто при прошлом запуске.
    func restoreLastVideo() async {
        guard info == nil, let last = LastVideoStore.load() else { return }
        await open(url: last.url, isImportedCopy: last.isImportedCopy)
        if info == nil {
            // Файл удалён или недоступен — молча забываем его.
            errorMessage = nil
            LastVideoStore.clear()
        }
    }

    func close() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        rateObserver = nil
        isSeekInFlight = false
        queuedSeekFrame = nil
        shuttleRate = 0
        player.pause()
        player.replaceCurrentItem(with: nil)
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        if let importedCopyURL {
            try? FileManager.default.removeItem(at: importedCopyURL.deletingLastPathComponent())
        }
        importedCopyURL = nil
        info = nil
        asset = nil
        detectedStart = nil
        fileName = nil
        currentFrame = 0
        comments = []
        video = nil
    }

    /// Задаёт тайм-код первого кадра вручную. Комментарии привязаны к кадрам и остаются на месте.
    func setStartTimecode(_ timecode: Timecode) {
        guard var info, let fileName else { return }
        info.startTimecode = timecode
        info.source = .manual
        self.info = info
        StartTimecodeStore.save(timecode, fileName: fileName, frameCount: info.frameCount)
    }

    /// Возвращает тайм-код из файла (или 00:00:00:00, если в файле его нет).
    func resetStartTimecode() {
        guard var info, let fileName, let detectedStart else { return }
        info.startTimecode = detectedStart.timecode
        info.source = detectedStart.source
        self.info = info
        StartTimecodeStore.save(nil, fileName: fileName, frameCount: info.frameCount)
    }

    func addComment(_ text: String, department: Department?) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard info != nil, !text.isEmpty else { return }
        let comment = ReviewComment(frame: currentFrame, text: text, department: department)
        if let video, let modelContext {
            modelContext.insert(comment)
            comment.video = video
        }
        saveAndRefresh(adding: comment)
    }

    func updateComment(_ comment: ReviewComment, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != comment.text else { return }
        comment.text = text
        comment.editedAt = .now
        saveAndRefresh()
    }

    func setDepartment(_ department: Department?, for comment: ReviewComment) {
        comment.department = department
        saveAndRefresh()
    }

    func toggleResolved(_ comment: ReviewComment) {
        comment.isResolved.toggle()
        saveAndRefresh()
    }

    func deleteComment(_ comment: ReviewComment) {
        comments.removeAll { $0 === comment }
        if let video = comment.video {
            video.comments.removeAll { $0 === comment }
            modelContext?.delete(comment)
        }
        saveAndRefresh()
    }

    /// Находит (или заводит) запись видео и подгружает его комментарии.
    private func loadComments(fileName: String, frameCount: Int) {
        guard let modelContext else { return }
        let key = ReviewVideo.key(fileName: fileName, frameCount: frameCount)
        let descriptor = FetchDescriptor<ReviewVideo>(predicate: #Predicate { $0.fileKey == key })
        if let existing = try? modelContext.fetch(descriptor).first {
            video = existing
        } else {
            let created = ReviewVideo(fileKey: key, fileName: fileName)
            modelContext.insert(created)
            video = created
        }
        comments = Self.sorted(video?.comments ?? [])
    }

    private func saveAndRefresh(adding comment: ReviewComment? = nil) {
        do {
            try modelContext?.save()
        } catch {
            errorMessage = "Couldn't save comments: \(error.localizedDescription)"
        }
        var all = (video?.comments ?? comments).filter { !$0.isDeleted }
        if let comment, !all.contains(where: { $0 === comment }) {
            all.append(comment)
        }
        comments = Self.sorted(all)
    }

    private static func sorted(_ comments: [ReviewComment]) -> [ReviewComment] {
        comments.sorted { ($0.frame, $0.createdAt) < ($1.frame, $1.createdAt) }
    }

    func timecode(forFrame frame: Int) -> String {
        info.map { ($0.startTimecode + frame).description } ?? "--:--:--:--"
    }

    func togglePlayPause() {
        shuttleRate = 0
        if isPlaying {
            player.pause()
        } else {
            player.playImmediately(atRate: speed)
        }
    }

    func setSpeed(_ newSpeed: Float) {
        speed = newSpeed
        player.defaultRate = newSpeed
        shuttleRate = 0
        if isPlaying {
            player.rate = newSpeed
        }
    }

    /// J/L: каждое нажатие в ту же сторону удваивает скорость (до 8×), в другую — начинает с 1×.
    func shuttle(forward: Bool) {
        guard info != nil else { return }
        let direction: Float = forward ? 1 : -1
        if !forward, player.currentItem?.canPlayReverse != true {
            return
        }
        if shuttleRate * direction > 0 {
            shuttleRate = direction * min(abs(shuttleRate) * 2, 8)
        } else {
            shuttleRate = direction
        }
        player.playImmediately(atRate: shuttleRate)
    }

    /// K — стоп.
    func stop() {
        shuttleRate = 0
        player.pause()
    }

    /// Шаг на `count` кадров вперёд (> 0) или назад (< 0).
    func step(by count: Int) {
        guard let info else { return }
        let base = isPlaying ? info.frameIndex(at: player.currentTime()) : currentFrame
        stop()
        seek(toFrame: base + count, info: info)
    }

    /// Шаг на `count` секунд — в кадрах тайм-кода, чтобы попадать в тот же номер кадра.
    func step(seconds count: Int) {
        guard let info else { return }
        step(by: count * info.rate.timecodeBase)
    }

    func seek(to timecode: Timecode) -> Bool {
        guard let info, let frame = info.frameIndex(for: timecode) else { return false }
        stop()
        seek(toFrame: frame, info: info)
        return true
    }

    /// Перемотка ползунком или jog-жестом — плеер встаёт на паузу.
    func scrub(toFrame frame: Int) {
        guard let info else { return }
        if isPlaying {
            stop()
        }
        seek(toFrame: frame, info: info)
    }

    private func seek(toFrame frame: Int, info: VideoTimecodeInfo) {
        let target = min(max(frame, 0), info.frameCount - 1)
        currentFrame = target
        if isSeekInFlight {
            queuedSeekFrame = target
        } else {
            performSeek(toFrame: target, info: info)
        }
    }

    private func performSeek(toFrame frame: Int, info: VideoTimecodeInfo) {
        isSeekInFlight = true
        // Нулевой допуск — плеер встаёт ровно на нужный кадр, а не на ближайший ключевой.
        player.seek(to: info.time(forFrame: frame), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isSeekInFlight = false
                if let next = self.queuedSeekFrame, let info = self.info {
                    self.queuedSeekFrame = nil
                    self.performSeek(toFrame: next, info: info)
                }
            }
        }
    }

    private func observePlayer(frameDuration: CMTime) {
        timeObserver = player.addPeriodicTimeObserver(forInterval: frameDuration, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let info = self.info, self.isPlaying else { return }
                self.currentFrame = info.frameIndex(at: time)
            }
        }
        rateObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = playing
                if !playing {
                    self.shuttleRate = 0
                }
                // После паузы сверяем кадр с плеером, если мы сами сейчас никуда не перематываем.
                if !playing, !self.isSeekInFlight, self.queuedSeekFrame == nil, let info = self.info {
                    self.currentFrame = info.frameIndex(at: self.player.currentTime())
                }
            }
        }
    }
}
