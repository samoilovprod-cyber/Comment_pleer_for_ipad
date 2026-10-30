import Foundation

/// Минимальный ZIP без сжатия (метод «store») — его достаточно, чтобы собрать XLSX.
struct ZipWriter {
    private var data = Data()
    private var centralDirectory = Data()
    private var entryCount: UInt16 = 0

    mutating func add(_ path: String, _ contents: Data) {
        let name = Data(path.utf8)
        let crc = Self.crc32(contents)
        let offset = UInt32(data.count)
        let size = UInt32(contents.count)
        // 1 января 2025, 00:00 в формате DOS.
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = UInt16((2025 - 1980) << 9 | 1 << 5 | 1)

        data.append(le32: 0x0403_4B50)
        data.append(le16: 20)                  // версия для распаковки
        data.append(le16: 0x0800)              // имена в UTF-8
        data.append(le16: 0)                   // без сжатия
        data.append(le16: dosTime)
        data.append(le16: dosDate)
        data.append(le32: crc)
        data.append(le32: size)
        data.append(le32: size)
        data.append(le16: UInt16(name.count))
        data.append(le16: 0)
        data.append(name)
        data.append(contents)

        centralDirectory.append(le32: 0x0201_4B50)
        centralDirectory.append(le16: 20)
        centralDirectory.append(le16: 20)
        centralDirectory.append(le16: 0x0800)
        centralDirectory.append(le16: 0)
        centralDirectory.append(le16: dosTime)
        centralDirectory.append(le16: dosDate)
        centralDirectory.append(le32: crc)
        centralDirectory.append(le32: size)
        centralDirectory.append(le32: size)
        centralDirectory.append(le16: UInt16(name.count))
        centralDirectory.append(le16: 0)       // extra
        centralDirectory.append(le16: 0)       // комментарий
        centralDirectory.append(le16: 0)       // номер диска
        centralDirectory.append(le16: 0)       // внутренние атрибуты
        centralDirectory.append(le32: 0)       // внешние атрибуты
        centralDirectory.append(le32: offset)
        centralDirectory.append(name)
        entryCount += 1
    }

    mutating func add(_ path: String, _ text: String) {
        add(path, Data(text.utf8))
    }

    func finish() -> Data {
        var result = data
        result.append(centralDirectory)
        result.append(le32: 0x0605_4B50)
        result.append(le16: 0)
        result.append(le16: 0)
        result.append(le16: entryCount)
        result.append(le16: entryCount)
        result.append(le32: UInt32(centralDirectory.count))
        result.append(le32: UInt32(data.count))
        result.append(le16: 0)
        return result
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(le32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
