import FrameTimecode
import Foundation

/// Начальный тайм-код, заданный вручную, — запоминается для файла (по имени и числу кадров).
enum StartTimecodeStore {
    private static let key = "startTimecodeOverrides"

    static func load(fileName: String, frameCount: Int, rate: FrameRate) -> Timecode? {
        guard let frameNumber = overrides[id(fileName, frameCount)] else { return nil }
        return Timecode(frameNumber: frameNumber, rate: rate)
    }

    static func save(_ timecode: Timecode?, fileName: String, frameCount: Int) {
        var all = overrides
        all[id(fileName, frameCount)] = timecode?.frameNumber
        UserDefaults.standard.set(all, forKey: key)
    }

    private static var overrides: [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    private static func id(_ fileName: String, _ frameCount: Int) -> String {
        "\(fileName)#\(frameCount)"
    }
}
