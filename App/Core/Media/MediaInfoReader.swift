import AVFoundation
import UniformTypeIdentifiers

/// Сведения о файле в духе MediaInfo: общие, по каждой дорожке и метаданные.
struct MediaInfoSection: Identifiable {
    struct Row: Identifiable {
        let id = UUID()
        let name: String
        let value: String
    }

    let id = UUID()
    let title: String
    let rows: [Row]
}

enum MediaInfoReader {
    static func read(asset: AVURLAsset) async -> [MediaInfoSection] {
        var sections: [MediaInfoSection] = []
        let duration = (try? await asset.load(.duration)) ?? .zero
        let fileSize = (try? asset.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize

        var general: [MediaInfoSection.Row] = []
        general.add("Файл", asset.url.lastPathComponent)
        general.add("Формат", UTType(filenameExtension: asset.url.pathExtension)?.localizedDescription)
        general.add("Размер", fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) })
        general.add("Длительность", formatDuration(duration))
        if let fileSize, duration.seconds > 0 {
            general.add("Общий битрейт", formatBitrate(Double(fileSize) * 8 / duration.seconds))
        }
        if let created = try? await asset.load(.creationDate), let date = try? await created.load(.dateValue) {
            general.add("Дата съёмки", date.formatted(date: .abbreviated, time: .standard))
        }
        sections.append(MediaInfoSection(title: "Общее", rows: general))

        let tracks = (try? await asset.load(.tracks)) ?? []
        var counters: [AVMediaType: Int] = [:]
        for track in tracks {
            counters[track.mediaType, default: 0] += 1
            let number = counters[track.mediaType]!
            switch track.mediaType {
            case .video:
                sections.append(MediaInfoSection(title: "Видео \(number)", rows: await videoRows(track)))
            case .audio:
                sections.append(MediaInfoSection(title: "Аудио \(number)", rows: await audioRows(track)))
            case .timecode:
                sections.append(MediaInfoSection(title: "Тайм-код \(number)", rows: await timecodeRows(track)))
            default:
                let rows = await commonTrackRows(track)
                sections.append(MediaInfoSection(title: "Дорожка \(track.mediaType.rawValue) \(number)", rows: rows))
            }
        }

        let metadata = await metadataRows(asset)
        if !metadata.isEmpty {
            sections.append(MediaInfoSection(title: "Метаданные", rows: metadata))
        }
        return sections
    }

    /// Текстом — чтобы скопировать и отправить.
    static func plainText(_ sections: [MediaInfoSection]) -> String {
        sections.map { section in
            ([section.title] + section.rows.map { "\($0.name.padding(toLength: 24, withPad: " ", startingAt: 0)): \($0.value)" })
                .joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    // MARK: - Дорожки

    private static func videoRows(_ track: AVAssetTrack) async -> [MediaInfoSection.Row] {
        var rows = await commonTrackRows(track)
        guard let (size, transform, fps, minFrameDuration) = try? await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .minFrameDuration) else { return rows }
        rows.add("Размер кадра", "\(Int(size.width)) × \(Int(size.height))")
        let angle = Int((atan2(transform.b, transform.a) * 180 / .pi).rounded())
        if angle != 0 {
            rows.add("Поворот", "\(angle)°")
        }
        rows.add("Частота кадров", String(format: "%.3f fps", fps))
        if minFrameDuration.isNumeric, fps > 0, abs(minFrameDuration.seconds * Double(fps) - 1) > 0.05 {
            rows.add("Режим частоты", "Переменная (VFR)")
        } else {
            rows.add("Режим частоты", "Постоянная (CFR)")
        }

        if let description = try? await track.load(.formatDescriptions).first {
            let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] ?? [:]
            if let depth = extensions[kCMFormatDescriptionExtension_Depth as String] as? Int {
                rows.add("Глубина (поле Depth)", "\(depth)")
            }
            if let bits = extensions[kCMFormatDescriptionExtension_BitsPerComponent as String] as? Int {
                rows.add("Бит на канал", "\(bits)")
            }
            if let aspect = extensions[kCMFormatDescriptionExtension_PixelAspectRatio as String] as? [String: Int],
               let h = aspect["HorizontalSpacing"], let v = aspect["VerticalSpacing"], h != v {
                rows.add("Соотношение пикселя", "\(h):\(v)")
            }
            if let fields = extensions[kCMFormatDescriptionExtension_FieldCount as String] as? Int {
                rows.add("Развёртка", fields == 2 ? "Чересстрочная" : "Прогрессивная")
            }
            rows.add("Цветовые первичные", extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String)
            rows.add("Передаточная функция", extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String)
            rows.add("Матрица YCbCr", extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String)
            if let fullRange = extensions[kCMFormatDescriptionExtension_FullRangeVideo as String] as? Bool {
                rows.add("Диапазон", fullRange ? "Полный" : "Ограниченный (video)")
            }
        }
        return rows
    }

    private static func audioRows(_ track: AVAssetTrack) async -> [MediaInfoSection.Row] {
        var rows = await commonTrackRows(track)
        guard let description = try? await track.load(.formatDescriptions).first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { return rows }
        rows.add("Каналы", "\(asbd.mChannelsPerFrame)")
        rows.add("Частота дискретизации", String(format: "%.1f кГц", asbd.mSampleRate / 1000))
        if asbd.mBitsPerChannel > 0 {
            rows.add("Разрядность", "\(asbd.mBitsPerChannel) бит")
        }
        return rows
    }

    private static func timecodeRows(_ track: AVAssetTrack) async -> [MediaInfoSection.Row] {
        var rows: [MediaInfoSection.Row] = []
        guard let description = try? await track.load(.formatDescriptions).first else { return rows }
        let frameDuration = CMTimeCodeFormatDescriptionGetFrameDuration(description)
        if frameDuration.seconds > 0 {
            rows.add("Частота", String(format: "%.3f fps", 1 / frameDuration.seconds))
        }
        let flags = CMTimeCodeFormatDescriptionGetTimeCodeFlags(description)
        rows.add("Drop-frame", flags & UInt32(kCMTimeCodeFlag_DropFrame) != 0 ? "Да" : "Нет")
        rows.add("Формат", fourCC(CMFormatDescriptionGetMediaSubType(description)))
        let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] ?? [:]
        if let source = extensions[kCMTimeCodeFormatDescriptionExtension_SourceReferenceName as String] as? [String: Any],
           let reel = source[kCMTimeCodeFormatDescriptionKey_Value as String] as? String {
            rows.add("Имя катушки (reel)", reel)
        }
        return rows
    }

    /// Кодек, битрейт, язык — общее для всех дорожек.
    private static func commonTrackRows(_ track: AVAssetTrack) async -> [MediaInfoSection.Row] {
        var rows: [MediaInfoSection.Row] = []
        if let description = try? await track.load(.formatDescriptions).first {
            let subtype = CMFormatDescriptionGetMediaSubType(description)
            let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] ?? [:]
            let formatName = extensions[kCMFormatDescriptionExtension_FormatName as String] as? String
            rows.add("Кодек", codecName(subtype) ?? formatName ?? fourCC(subtype))
            rows.add("FourCC", fourCC(subtype))
        }
        if let (rate, range, language) = try? await track.load(.estimatedDataRate, .timeRange, .languageCode) {
            if rate > 0 {
                rows.add("Битрейт", formatBitrate(Double(rate)))
            }
            rows.add("Длительность", formatDuration(range.duration))
            if let language, language != "und" {
                rows.add("Язык", Locale.current.localizedString(forLanguageCode: language) ?? language)
            }
        }
        return rows
    }

    private static func metadataRows(_ asset: AVURLAsset) async -> [MediaInfoSection.Row] {
        var rows: [MediaInfoSection.Row] = []
        let items = (try? await asset.load(.metadata)) ?? []
        for item in items {
            guard let value = try? await item.load(.stringValue), !value.isEmpty else { continue }
            let name = item.commonKey.map { commonKeyName($0) } ?? item.identifier?.rawValue ?? "—"
            rows.add(name, value)
        }
        return rows
    }

    // MARK: - Форматирование

    private static func codecName(_ code: FourCharCode) -> String? {
        switch fourCC(code) {
        case "avc1", "avc3": "H.264 / AVC"
        case "hvc1", "hev1": "H.265 / HEVC"
        case "dvh1", "dvhe": "HEVC Dolby Vision"
        case "apch": "Apple ProRes 422 HQ"
        case "apcn": "Apple ProRes 422"
        case "apcs": "Apple ProRes 422 LT"
        case "apco": "Apple ProRes 422 Proxy"
        case "ap4h": "Apple ProRes 4444"
        case "ap4x": "Apple ProRes 4444 XQ"
        case "aprn", "aprh": "Apple ProRes RAW"
        case "mp4v": "MPEG-4 Visual"
        case "jpeg": "Motion JPEG"
        case "lpcm", "sowt", "twos", "in24", "in32", "fl32": "PCM"
        case "aac ": "AAC"
        case "alac": "Apple Lossless"
        case "ac-3": "Dolby Digital (AC-3)"
        case "ec-3": "Dolby Digital Plus (E-AC-3)"
        case "tmcd": "Тайм-код QuickTime"
        default: nil
        }
    }

    private static func commonKeyName(_ key: AVMetadataKey) -> String {
        switch key {
        case .commonKeyMake: "Производитель"
        case .commonKeyModel: "Модель"
        case .commonKeySoftware: "Программа"
        case .commonKeyCreationDate: "Дата создания"
        case .commonKeyLocation: "Место"
        case .commonKeyTitle: "Название"
        case .commonKeyAuthor, .commonKeyCreator: "Автор"
        case .commonKeyCopyrights: "Авторские права"
        case .commonKeyDescription: "Описание"
        default: key.rawValue
        }
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
    }

    private static func formatDuration(_ time: CMTime) -> String {
        guard time.isNumeric else { return "—" }
        let total = time.seconds
        let hours = Int(total) / 3600, minutes = Int(total) / 60 % 60, seconds = total.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%02d:%06.3f", hours, minutes, seconds)
    }

    private static func formatBitrate(_ bitsPerSecond: Double) -> String {
        bitsPerSecond >= 1_000_000
            ? String(format: "%.1f Мбит/с", bitsPerSecond / 1_000_000)
            : String(format: "%.0f кбит/с", bitsPerSecond / 1000)
    }
}

private extension Array where Element == MediaInfoSection.Row {
    mutating func add(_ name: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        append(MediaInfoSection.Row(name: name, value: value))
    }
}
