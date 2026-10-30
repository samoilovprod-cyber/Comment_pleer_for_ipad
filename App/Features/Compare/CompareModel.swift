import AVFoundation
import FrameTimecode

/// Две версии ролика с общим транспортом. Версии выравниваются по номеру кадра от начала файла.
@MainActor
final class CompareModel: ObservableObject {
    struct Side {
        let video: ReviewVideo
        let info: VideoTimecodeInfo
        let player: AVPlayer
        fileprivate let access: MediaLibrary.FileAccess
    }

    @Published private(set) var a: Side?
    @Published private(set) var b: Side?
    @Published private(set) var currentFrame = 0
    @Published private(set) var isPlaying = false
    @Published var errorMessage: String?

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var isSeekInFlight = false
    private var queuedSeekFrame: Int?
    private var lastDriftCheck = Date.distantPast

    /// Длина общего таймлайна — по более длинной версии; короткая стоит на последнем кадре.
    var frameCount: Int { max(a?.info.frameCount ?? 0, b?.info.frameCount ?? 0) }

    var timecode: String {
        guard let a else { return "--:--:--:--" }
        return (a.info.startTimecode + min(currentFrame, a.info.frameCount - 1)).description
    }

    func load(a videoA: ReviewVideo, b videoB: ReviewVideo) async {
        let frame = currentFrame
        close()
        do {
            let sideA = try await makeSide(videoA)
            let sideB = try await makeSide(videoB)
            sideB.player.isMuted = true
            a = sideA
            b = sideB
            observe(sideA)
            seek(toFrame: min(frame, max(frameCount - 1, 0)))
        } catch {
            errorMessage = error.localizedDescription
            close()
        }
    }

    func close() {
        if let timeObserver, let a { a.player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObserver = nil
        for side in [a, b].compactMap({ $0 }) {
            side.player.pause()
            side.player.replaceCurrentItem(with: nil)
            side.access.stop()
        }
        a = nil
        b = nil
        isPlaying = false
        isSeekInFlight = false
        queuedSeekFrame = nil
    }

    func togglePlayPause() {
        guard let a, let b else { return }
        if isPlaying {
            a.player.pause()
            b.player.pause()
            return
        }
        // Обе версии стартуют в один и тот же момент по часам хоста.
        var frame = currentFrame
        if frame >= frameCount - 1 { frame = 0 }
        let start = CMClockGetTime(CMClockGetHostTimeClock()) + CMTime(value: 1, timescale: 10)
        a.player.setRate(1, time: a.info.time(forFrame: min(frame, a.info.frameCount - 1)), atHostTime: start)
        b.player.setRate(1, time: b.info.time(forFrame: min(frame, b.info.frameCount - 1)), atHostTime: start)
    }

    func step(by count: Int) {
        pause()
        seek(toFrame: currentFrame + count)
    }

    func scrub(toFrame frame: Int) {
        pause()
        seek(toFrame: frame)
    }

    private func pause() {
        a?.player.pause()
        b?.player.pause()
    }

    private func seek(toFrame frame: Int) {
        let target = min(max(frame, 0), max(frameCount - 1, 0))
        currentFrame = target
        if isSeekInFlight {
            queuedSeekFrame = target
            return
        }
        guard let a, let b else { return }
        isSeekInFlight = true
        let group = DispatchGroup()
        for side in [a, b] {
            group.enter()
            let time = side.info.time(forFrame: min(target, side.info.frameCount - 1))
            side.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isSeekInFlight = false
                if let next = self.queuedSeekFrame {
                    self.queuedSeekFrame = nil
                    self.seek(toFrame: next)
                }
            }
        }
    }

    private func makeSide(_ video: ReviewVideo) async throws -> Side {
        guard let access = MediaLibrary.access(video) else {
            throw MediaLibrary.LibraryError.fileMissing(video.fileName)
        }
        let asset = AVURLAsset(url: access.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        do {
            var info = try await VideoTimecodeReader.read(from: asset)
            if let manual = StartTimecodeStore.load(fileName: video.fileName, frameCount: info.frameCount, rate: info.rate) {
                info.startTimecode = manual
                info.source = .manual
            }
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            player.automaticallyWaitsToMinimizeStalling = false
            return Side(video: video, info: info, player: player, access: access)
        } catch {
            access.stop()
            throw error
        }
    }

    /// Кадр берём с A; раз в полсекунды подтягиваем B, если она разошлась больше чем на кадр.
    private func observe(_ side: Side) {
        timeObserver = side.player.addPeriodicTimeObserver(forInterval: side.info.rate.frameDuration,
                                                           queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, let a = self.a, let b = self.b else { return }
                self.currentFrame = a.info.frameIndex(at: time)
                guard Date.now.timeIntervalSince(self.lastDriftCheck) > 0.5 else { return }
                self.lastDriftCheck = .now
                // У версий может быть разный сдвиг начала видео — сравниваем относительно первого кадра.
                let expected = b.info.time(forFrame: 0) + (time - a.info.time(forFrame: 0))
                let drift = abs((b.player.currentTime() - expected).seconds)
                if drift > b.info.rate.frameDuration.seconds, self.currentFrame < b.info.frameCount - 1 {
                    b.player.seek(to: expected, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }
        statusObserver = side.player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = playing
                if !playing {
                    self.b?.player.pause()
                    if !self.isSeekInFlight, self.queuedSeekFrame == nil, let a = self.a {
                        self.currentFrame = a.info.frameIndex(at: a.player.currentTime())
                    }
                }
            }
        }
    }
}
