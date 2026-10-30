import AVFoundation
import FrameTimecode

/// Всё, что нужно плееру, чтобы переводить время воспроизведения в тайм-код и обратно.
struct VideoTimecodeInfo {
    enum Source {
        /// Тайм-код прочитан из трека `tmcd` файла.
        case embedded
        /// В файле нет тайм-кода — отсчёт с 00:00:00:00.
        case assumedZero
        /// Начало задано пользователем вручную.
        case manual
    }

    let rate: FrameRate
    var startTimecode: Timecode
    var source: Source
    /// Время первого кадра видеотрека (обычно ноль).
    let videoStart: CMTime
    let duration: CMTime
    let frameCount: Int
    /// Размер кадра на экране в пикселях — с учётом поворота (вертикальное видео с iPhone).
    let naturalSize: CGSize
    /// Похоже на переменную частоту кадров (часто у записей с телефона) — покадровый шаг может быть неточным.
    let isLikelyVariableFrameRate: Bool

    var endTimecode: Timecode { startTimecode + max(frameCount - 1, 0) }

    func frameIndex(at time: CMTime) -> Int {
        min(rate.frameIndex(at: time - videoStart), max(frameCount - 1, 0))
    }

    func timecode(at time: CMTime) -> Timecode {
        startTimecode + frameIndex(at: time)
    }

    func time(forFrame index: Int) -> CMTime {
        videoStart + rate.time(forFrame: index)
    }

    /// Индекс кадра для тайм-кода, введённого пользователем; nil, если он вне видео.
    func frameIndex(for timecode: Timecode) -> Int? {
        let day = rate.framesPerDay
        let offset = ((timecode.frameNumber - startTimecode.frameNumber) % day + day) % day
        return offset < frameCount ? offset : nil
    }
}

enum VideoTimecodeReaderError: LocalizedError {
    case noVideoTrack

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "The file has no video track."
        }
    }
}

enum VideoTimecodeReader {
    static func read(from asset: AVAsset) async throws -> VideoTimecodeInfo {
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoTimecodeReaderError.noVideoTrack
        }
        let (nominalFrameRate, minFrameDuration, timeRange, encodedSize, transform) =
            try await video.load(.nominalFrameRate, .minFrameDuration, .timeRange, .naturalSize, .preferredTransform)
        let rotated = encodedSize.applying(transform)
        let naturalSize = CGSize(width: abs(rotated.width), height: abs(rotated.height))

        let videoRate = FrameRate.detect(fps: Double(nominalFrameRate))
        var rate = videoRate
        var start = Timecode.zero(rate: videoRate)
        var source = VideoTimecodeInfo.Source.assumedZero

        if let timecodeTrack = try await asset.loadTracks(withMediaType: .timecode).first,
           let embedded = try? await readEmbeddedTimecode(track: timecodeTrack, asset: asset) {
            source = .embedded
            if abs(embedded.rate.fps - videoRate.fps) / videoRate.fps < 0.005 {
                rate = embedded.rate
                start = embedded.start
            } else {
                // Трек тайм-кода с другой частотой — оставляем частоту видео, переносим ЧЧ:ММ:СС:КК.
                start = (try? Timecode(embedded.start.components, rate: videoRate)) ?? start
            }
        }

        let frameDurationSeconds = minFrameDuration.isNumeric ? minFrameDuration.seconds : 0
        let isLikelyVFR = nominalFrameRate > 0 && frameDurationSeconds > 0
            && abs(frameDurationSeconds * Double(nominalFrameRate) - 1) > 0.05

        return VideoTimecodeInfo(
            rate: rate,
            startTimecode: start,
            source: source,
            videoStart: timeRange.start.isNumeric ? timeRange.start : .zero,
            duration: timeRange.duration,
            frameCount: max(1, rate.frameIndex(at: timeRange.duration + CMTime(value: 1, timescale: 1000))),
            naturalSize: naturalSize,
            isLikelyVariableFrameRate: isLikelyVFR
        )
    }

    /// Читает первый сэмпл трека `tmcd`: в нём записан номер кадра начала тайм-кода.
    private static func readEmbeddedTimecode(track: AVAssetTrack, asset: AVAsset) async throws -> (rate: FrameRate, start: Timecode)? {
        guard let description = try await track.load(.formatDescriptions).first else { return nil }

        let frameDuration = CMTimeCodeFormatDescriptionGetFrameDuration(description)
        let quanta = Int(CMTimeCodeFormatDescriptionGetFrameQuanta(description))
        let flags = CMTimeCodeFormatDescriptionGetTimeCodeFlags(description)
        let isDropFrame = (flags & UInt32(kCMTimeCodeFlag_DropFrame)) != 0
        let rate = FrameRate.fromFrameDuration(value: frameDuration.value, timescale: frameDuration.timescale,
                                               quanta: quanta, dropFrame: isDropFrame)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }

        // Первыми могут прийти служебные буферы без сэмплов (например, на границе edit list) — пропускаем их.
        var dataBlock: CMBlockBuffer?
        while dataBlock == nil, let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(sample) > 0 {
                dataBlock = CMSampleBufferGetDataBuffer(sample)
            }
        }
        guard let block = dataBlock else { return nil }

        let frameNumber: Int
        switch CMFormatDescriptionGetMediaSubType(description) {
        case kCMTimeCodeFormatType_TimeCode32:
            guard let value = readBigEndian(Int32.self, from: block) else { return nil }
            frameNumber = Int(value)
        case kCMTimeCodeFormatType_TimeCode64:
            guard let value = readBigEndian(Int64.self, from: block) else { return nil }
            frameNumber = Int(value)
        default:
            return nil
        }
        return (rate, Timecode(frameNumber: frameNumber, rate: rate))
    }

    private static func readBigEndian<T: FixedWidthInteger>(_ type: T.Type, from block: CMBlockBuffer) -> T? {
        let size = MemoryLayout<T>.size
        guard CMBlockBufferGetDataLength(block) >= size else { return nil }
        var value = T.zero
        let status = withUnsafeMutableBytes(of: &value) { buffer in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: buffer.baseAddress!)
        }
        return status == kCMBlockBufferNoErr ? T(bigEndian: value) : nil
    }
}
