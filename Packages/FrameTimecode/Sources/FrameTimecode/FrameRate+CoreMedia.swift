#if canImport(CoreMedia)
import CoreMedia

public extension FrameRate {
    /// Длительность одного кадра, точно (например, 1001/24000 с).
    var frameDuration: CMTime {
        CMTime(value: CMTimeValue(denominator), timescale: CMTimeScale(numerator))
    }

    /// Время начала кадра с индексом `index`, отсчитанное от первого кадра видео.
    func time(forFrame index: Int) -> CMTime {
        CMTime(value: CMTimeValue(index) * CMTimeValue(denominator), timescale: CMTimeScale(numerator))
    }

    /// Индекс кадра, который показывается в момент `time` (время от первого кадра видео).
    /// Небольшой допуск убирает ошибку округления, когда время чуть меньше начала кадра.
    func frameIndex(at time: CMTime) -> Int {
        guard time.isNumeric else { return 0 }
        let exact = time.seconds * fps
        return max(0, Int((exact + 0.001).rounded(.down)))
    }
}
#endif
