import Foundation

public enum TimecodeError: Error, Equatable, Sendable {
    case invalidFormat(String)
    case outOfRange
    /// Номер кадра, которого не существует в drop-frame (например, 00:01:00;00 при 29.97 DF).
    case droppedFrameNumber
}

/// SMPTE тайм-код. Внутри хранится номер кадра от 00:00:00:00 — так проще сравнивать и складывать.
public struct Timecode: Hashable, Comparable, Sendable, CustomStringConvertible {
    public struct Components: Hashable, Sendable {
        public var hours: Int
        public var minutes: Int
        public var seconds: Int
        public var frames: Int

        public init(hours: Int, minutes: Int, seconds: Int, frames: Int) {
            self.hours = hours
            self.minutes = minutes
            self.seconds = seconds
            self.frames = frames
        }
    }

    public let rate: FrameRate
    /// Номер кадра в сутках, 0 ..< rate.framesPerDay.
    public let frameNumber: Int

    /// Номер кадра переносится через 24 часа в обе стороны.
    public init(frameNumber: Int, rate: FrameRate) {
        let day = rate.framesPerDay
        self.rate = rate
        self.frameNumber = ((frameNumber % day) + day) % day
    }

    public init(_ components: Components, rate: FrameRate) throws {
        let (h, m, s, f) = (components.hours, components.minutes, components.seconds, components.frames)
        guard (0..<24).contains(h), (0..<60).contains(m), (0..<60).contains(s),
              (0..<rate.timecodeBase).contains(f) else {
            throw TimecodeError.outOfRange
        }
        let drop = rate.droppedFramesPerMinute
        if drop > 0, s == 0, m % 10 != 0, f < drop {
            throw TimecodeError.droppedFrameNumber
        }
        let totalMinutes = h * 60 + m
        let nominal = (h * 3600 + m * 60 + s) * rate.timecodeBase + f
        self.init(frameNumber: nominal - drop * (totalMinutes - totalMinutes / 10), rate: rate)
    }

    public init(hours: Int, minutes: Int, seconds: Int, frames: Int, rate: FrameRate) throws {
        try self.init(Components(hours: hours, minutes: minutes, seconds: seconds, frames: frames), rate: rate)
    }

    /// Разбор строки: `01:00:10:05`, `01:00:10;05`, `01.00.10.05`, а также ввод цифрами
    /// без разделителей, выровненный вправо, как в Resolve/Premiere: `1005` → 00:00:10:05.
    public init(_ string: String, rate: FrameRate) throws {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let separators: Set<Character> = [":", ";", ".", ","]
        var fields: [Int]

        if trimmed.contains(where: { separators.contains($0) }) {
            let parts = trimmed.split(omittingEmptySubsequences: false, whereSeparator: { separators.contains($0) })
            guard (1...4).contains(parts.count) else { throw TimecodeError.invalidFormat(string) }
            fields = try parts.map { part in
                guard !part.isEmpty, part.count <= 3, part.allSatisfy(isDigit), let value = Int(part) else {
                    throw TimecodeError.invalidFormat(string)
                }
                return value
            }
        } else {
            guard !trimmed.isEmpty, trimmed.count <= 8, trimmed.allSatisfy(isDigit) else {
                throw TimecodeError.invalidFormat(string)
            }
            let padded = String(repeating: "0", count: 8 - trimmed.count) + trimmed
            let digits = Array(padded)
            fields = stride(from: 0, to: 8, by: 2).map { Int(String(digits[$0...$0 + 1]))! }
        }

        while fields.count < 4 { fields.insert(0, at: 0) }
        try self.init(hours: fields[0], minutes: fields[1], seconds: fields[2], frames: fields[3], rate: rate)
    }

    public var components: Components {
        let base = rate.timecodeBase
        var n = frameNumber
        let drop = rate.droppedFramesPerMinute
        if drop > 0 {
            let framesPer10Minutes = base * 600 - drop * 9
            let framesPerMinute = base * 60 - drop
            let tens = n / framesPer10Minutes
            let remainder = n % framesPer10Minutes
            n += drop * 9 * tens
            if remainder > drop {
                n += drop * ((remainder - drop) / framesPerMinute)
            }
        }
        let totalSeconds = n / base
        return Components(hours: totalSeconds / 3600,
                          minutes: (totalSeconds / 60) % 60,
                          seconds: totalSeconds % 60,
                          frames: n % base)
    }

    /// `HH:MM:SS:FF`, для drop-frame — `HH:MM:SS;FF`.
    public var description: String {
        let c = components
        let frameDigits = rate.timecodeBase > 100 ? 3 : 2
        let separator = rate.isDropFrame ? ";" : ":"
        return pad(c.hours) + ":" + pad(c.minutes) + ":" + pad(c.seconds) + separator + pad(c.frames, width: frameDigits)
    }

    public func adding(frames: Int) -> Timecode {
        Timecode(frameNumber: frameNumber + frames, rate: rate)
    }

    public static func + (lhs: Timecode, rhs: Int) -> Timecode { lhs.adding(frames: rhs) }
    public static func - (lhs: Timecode, rhs: Int) -> Timecode { lhs.adding(frames: -rhs) }

    public static func < (lhs: Timecode, rhs: Timecode) -> Bool { lhs.frameNumber < rhs.frameNumber }

    public static func zero(rate: FrameRate) -> Timecode { Timecode(frameNumber: 0, rate: rate) }
}

private func isDigit(_ character: Character) -> Bool {
    character.isASCII && character.isNumber
}

private func pad(_ value: Int, width: Int = 2) -> String {
    let text = String(value)
    return text.count >= width ? text : String(repeating: "0", count: width - text.count) + text
}
