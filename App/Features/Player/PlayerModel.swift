import AVFoundation
import FrameTimecode

@MainActor
final class PlayerModel: ObservableObject {
    @Published private(set) var info: VideoTimecodeInfo?
    @Published private(set) var currentFrame = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var fileName: String?
    @Published var errorMessage: String?

    let player = AVPlayer()

    private var timeObserver: Any?
    private var rateObserver: NSKeyValueObservation?
    private var accessedURL: URL?
    private var pendingSeeks = 0

    var currentTimecode: Timecode? {
        info.map { $0.startTimecode + currentFrame }
    }

    func open(url: URL) async {
        close()
        if url.startAccessingSecurityScopedResource() {
            accessedURL = url
        }
        fileName = url.lastPathComponent

        // Точная длительность и тайминг важны для покадровой навигации.
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        do {
            let info = try await VideoTimecodeReader.read(from: asset)
            self.info = info
            currentFrame = 0
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            observePlayer(frameDuration: info.rate.frameDuration)
        } catch {
            errorMessage = error.localizedDescription
            close()
        }
    }

    func close() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        rateObserver = nil
        pendingSeeks = 0
        player.pause()
        player.replaceCurrentItem(with: nil)
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        info = nil
        fileName = nil
        currentFrame = 0
    }

    func togglePlayPause() {
        isPlaying ? player.pause() : player.play()
    }

    /// Шаг на `count` кадров вперёд (> 0) или назад (< 0).
    func step(by count: Int) {
        guard let info else { return }
        let base = isPlaying ? info.frameIndex(at: player.currentTime()) : currentFrame
        player.pause()
        seek(toFrame: base + count, info: info)
    }

    func seek(to timecode: Timecode) -> Bool {
        guard let info, let frame = info.frameIndex(for: timecode) else { return false }
        player.pause()
        seek(toFrame: frame, info: info)
        return true
    }

    private func seek(toFrame frame: Int, info: VideoTimecodeInfo) {
        let target = min(max(frame, 0), info.frameCount - 1)
        currentFrame = target
        // Нулевой допуск — плеер встаёт ровно на нужный кадр, а не на ближайший ключевой.
        pendingSeeks += 1
        player.seek(to: info.time(forFrame: target), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pendingSeeks = max(0, self.pendingSeeks - 1)
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
                // После паузы сверяем кадр с плеером, если мы сами сейчас никуда не перематываем.
                if !playing, self.pendingSeeks == 0, let info = self.info {
                    self.currentFrame = info.frameIndex(at: self.player.currentTime())
                }
            }
        }
    }
}
