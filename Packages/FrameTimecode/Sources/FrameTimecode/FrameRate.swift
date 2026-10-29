import Foundation

/// Частота кадров видео и правила счёта тайм-кода для неё.
///
/// Точная частота хранится дробью `numerator / denominator` (например, 24000/1001 для 23.976),
/// а `timecodeBase` — сколько кадров в одной «секунде» тайм-кода (24 для 23.976, 30 для 29.97).
public struct FrameRate: Hashable, Sendable, CustomStringConvertible {
    public let timecodeBase: Int
    public let numerator: Int
    public let denominator: Int
    public let isDropFrame: Bool

    public init(timecodeBase: Int, numerator: Int, denominator: Int, isDropFrame: Bool = false) {
        precondition(timecodeBase > 0 && numerator > 0 && denominator > 0, "Invalid frame rate")
        // Drop-frame определён только для 29.97 и 59.94 (база кратна 30).
        self.timecodeBase = timecodeBase
        self.numerator = numerator
        self.denominator = denominator
        self.isDropFrame = isDropFrame && timecodeBase % 30 == 0
    }

    public static let fps23_976 = FrameRate(timecodeBase: 24, numerator: 24000, denominator: 1001)
    public static let fps24 = FrameRate(timecodeBase: 24, numerator: 24, denominator: 1)
    public static let fps25 = FrameRate(timecodeBase: 25, numerator: 25, denominator: 1)
    public static let fps29_97 = FrameRate(timecodeBase: 30, numerator: 30000, denominator: 1001)
    public static let fps29_97DF = FrameRate(timecodeBase: 30, numerator: 30000, denominator: 1001, isDropFrame: true)
    public static let fps30 = FrameRate(timecodeBase: 30, numerator: 30, denominator: 1)
    public static let fps47_952 = FrameRate(timecodeBase: 48, numerator: 48000, denominator: 1001)
    public static let fps48 = FrameRate(timecodeBase: 48, numerator: 48, denominator: 1)
    public static let fps50 = FrameRate(timecodeBase: 50, numerator: 50, denominator: 1)
    public static let fps59_94 = FrameRate(timecodeBase: 60, numerator: 60000, denominator: 1001)
    public static let fps59_94DF = FrameRate(timecodeBase: 60, numerator: 60000, denominator: 1001, isDropFrame: true)
    public static let fps60 = FrameRate(timecodeBase: 60, numerator: 60, denominator: 1)

    public static let standard: [FrameRate] = [
        .fps23_976, .fps24, .fps25, .fps29_97, .fps29_97DF, .fps30,
        .fps47_952, .fps48, .fps50, .fps59_94, .fps59_94DF, .fps60,
    ]

    /// Кадров в секунду (точное значение, например 23.976023…).
    public var fps: Double { Double(numerator) / Double(denominator) }

    /// Сколько номеров кадров пропускается в начале каждой минуты (кроме каждой десятой).
    public var droppedFramesPerMinute: Int { isDropFrame ? timecodeBase / 15 : 0 }

    /// Количество кадров в сутках тайм-кода (00:00:00:00 … 23:59:59:xx).
    public var framesPerDay: Int {
        if isDropFrame {
            let framesPer10Minutes = timecodeBase * 600 - droppedFramesPerMinute * 9
            return framesPer10Minutes * 144
        }
        return timecodeBase * 86_400
    }

    /// Ближайшая стандартная частота к измеренной (например, `nominalFrameRate` у видеотрека).
    public static func detect(fps: Double, dropFrame: Bool = false) -> FrameRate {
        guard fps.isFinite, fps > 0 else { return .fps25 }
        let candidates = standard.filter { !$0.isDropFrame }
        let closest = candidates.min { abs($0.fps - fps) < abs($1.fps - fps) }!
        if abs(closest.fps - fps) / fps > 0.01 {
            // Нестандартная частота — считаем по округлённому целому.
            let base = max(1, Int(fps.rounded()))
            return FrameRate(timecodeBase: base, numerator: base, denominator: 1)
        }
        if dropFrame {
            return FrameRate(timecodeBase: closest.timecodeBase, numerator: closest.numerator,
                             denominator: closest.denominator, isDropFrame: true)
        }
        return closest
    }

    /// Частота из описания трека тайм-кода: длительность кадра `value / timescale` секунд
    /// (например, 1001/24000) и `quanta` — кадров в секунде тайм-кода.
    public static func fromFrameDuration(value: Int64, timescale: Int32, quanta: Int, dropFrame: Bool) -> FrameRate {
        guard value > 0, timescale > 0 else { return detect(fps: Double(quanta), dropFrame: dropFrame) }
        let divisor = gcd(Int(timescale), Int(value))
        let numerator = Int(timescale) / divisor
        let denominator = Int(value) / divisor
        let exactFPS = Double(numerator) / Double(denominator)
        let base = quanta > 0 ? quanta : max(1, Int(exactFPS.rounded()))
        return FrameRate(timecodeBase: base, numerator: numerator, denominator: denominator, isDropFrame: dropFrame)
    }

    public var description: String {
        let value: String
        if denominator == 1 {
            value = String(numerator)
        } else {
            // 23.976, 29.97, 59.94 — как принято в монтажных программах.
            let thousandths = (fps * 1000).rounded() / 1000
            var text = String(format: "%.3f", thousandths)
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
            value = text
        }
        return isDropFrame ? "\(value) DF" : value
    }
}

private func gcd(_ a: Int, _ b: Int) -> Int {
    var (a, b) = (abs(a), abs(b))
    while b != 0 { (a, b) = (b, a % b) }
    return max(a, 1)
}
