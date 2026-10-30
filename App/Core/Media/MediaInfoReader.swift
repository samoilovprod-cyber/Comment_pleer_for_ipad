import AVFoundation

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
        general.add("File", asset.url.lastPathComponent)
        general.add("Format", containerName(asset.url.pathExtension))
        general.add("File size", fileSize.map(formatFileSize))
        general.add("Duration", formatDuration(duration))
        if let fileSize, duration.seconds > 0 {
            general.add("Overall bit rate", formatBitrate(Double(fileSize) * 8 / duration.seconds))
        }
        if let created = try? await asset.load(.creationDate), let date = try? await created.load(.dateValue) {
            general.add("Recorded date", date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(Locale(identifier: "en_US"))))
        }
        sections.append(MediaInfoSection(title: "General", rows: general))

        let tracks = (try? await asset.load(.tracks)) ?? []
        var counters: [AVMediaType: Int] = [:]
        for track in tracks {
            counters[track.mediaType, default: 0] += 1
            let number = counters[track.mediaType]!
            switch track.mediaType {
            case .video:
                sections.append(MediaInfoSection(title: "Video \(number)", rows: await videoRows(track)))
            case .audio:
                sections.append(MediaInfoSection(title: "Audio \(number)", rows: await audioRows(track)))
            case .timecode:
                sections.append(MediaInfoSection(title: "Timecode \(number)", rows: await timecodeRows(track)))
            default:
                let rows = await commonTrackRows(track)
                sections.append(MediaInfoSection(title: "Track \(track.mediaType.rawValue) \(number)", rows: rows))
            }
        }

        let metadata = await metadataRows(asset)
        if !metadata.isEmpty {
            sections.append(MediaInfoSection(title: "Metadata", rows: metadata))
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
        rows.add("Frame size", "\(Int(size.width)) × \(Int(size.height))")
        let angle = Int((atan2(transform.b, transform.a) * 180 / .pi).rounded())
        if angle != 0 {
            rows.add("Rotation", "\(angle)°")
        }
        rows.add("Frame rate", String(format: "%.3f fps", fps))
        if minFrameDuration.isNumeric, fps > 0, abs(minFrameDuration.seconds * Double(fps) - 1) > 0.05 {
            rows.add("Frame rate mode", "Variable (VFR)")
        } else {
            rows.add("Frame rate mode", "Constant (CFR)")
        }

        if let description = try? await track.load(.formatDescriptions).first {
            let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] ?? [:]
            if let depth = extensions[kCMFormatDescriptionExtension_Depth as String] as? Int {
                rows.add("Depth", "\(depth)")
            }
            if let bits = extensions[kCMFormatDescriptionExtension_BitsPerComponent as String] as? Int {
                rows.add("Bit depth", "\(bits)")
            }
            if let aspect = extensions[kCMFormatDescriptionExtension_PixelAspectRatio as String] as? [String: Int],
               let h = aspect["HorizontalSpacing"], let v = aspect["VerticalSpacing"], h != v {
                rows.add("Pixel aspect ratio", "\(h):\(v)")
            }
            if let fields = extensions[kCMFormatDescriptionExtension_FieldCount as String] as? Int {
                rows.add("Scan type", fields == 2 ? "Interlaced" : "Progressive")
            }
            rows.add("Color primaries", extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String)
            rows.add("Transfer characteristics", extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String)
            rows.add("Matrix coefficients", extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String)
            if let fullRange = extensions[kCMFormatDescriptionExtension_FullRangeVideo as String] as? Bool {
                rows.add("Color range", fullRange ? "Full" : "Limited")
            }
        }
        return rows
    }

    private static func audioRows(_ track: AVAssetTrack) async -> [MediaInfoSection.Row] {
        var rows = await commonTrackRows(track)
        guard let description = try? await track.load(.formatDescriptions).first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { return rows }
        rows.add("Channels", "\(asbd.mChannelsPerFrame)")
        rows.add("Sampling rate", String(format: "%.1f kHz", asbd.mSampleRate / 1000))
        if asbd.mBitsPerChannel > 0 {
            rows.add("Bit depth", "\(asbd.mBitsPerChannel) bits")
        }
        return rows
    }

    private static func timecodeRows(_ track: AVAssetTrack) async -> [MediaInfoSection.Row] {
        var rows: [MediaInfoSection.Row] = []
        guard let description = try? await track.load(.formatDescriptions).first else { return rows }
        let frameDuration = CMTimeCodeFormatDescriptionGetFrameDuration(description)
        if frameDuration.seconds > 0 {
            rows.add("Frame rate", String(format: "%.3f fps", 1 / frameDuration.seconds))
        }
        let flags = CMTimeCodeFormatDescriptionGetTimeCodeFlags(description)
        rows.add("Drop-frame", flags & UInt32(kCMTimeCodeFlag_DropFrame) != 0 ? "Yes" : "No")
        rows.add("Format", fourCC(CMFormatDescriptionGetMediaSubType(description)))
        let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] ?? [:]
        if let source = extensions[kCMTimeCodeFormatDescriptionExtension_SourceReferenceName as String] as? [String: Any],
           let reel = source[kCMTimeCodeFormatDescriptionKey_Value as String] as? String {
            rows.add("Reel name", reel)
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
            rows.add("Codec", codecName(subtype) ?? formatName ?? fourCC(subtype))
            rows.add("FourCC", fourCC(subtype))
        }
        if let (rate, range, language) = try? await track.load(.estimatedDataRate, .timeRange, .languageCode) {
            if rate > 0 {
                rows.add("Bit rate", formatBitrate(Double(rate)))
            }
            rows.add("Duration", formatDuration(range.duration))
            if let language, language != "und" {
                rows.add("Language", Locale(identifier: "en_US").localizedString(forLanguageCode: language) ?? language)
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
        case "tmcd": "QuickTime timecode"
        default: nil
        }
    }

    private static func commonKeyName(_ key: AVMetadataKey) -> String {
        switch key {
        case .commonKeyMake: "Make"
        case .commonKeyModel: "Model"
        case .commonKeySoftware: "Software"
        case .commonKeyCreationDate: "Creation date"
        case .commonKeyLocation: "Location"
        case .commonKeyTitle: "Title"
        case .commonKeyAuthor, .commonKeyCreator: "Author"
        case .commonKeyCopyrights: "Copyright"
        case .commonKeyDescription: "Description"
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

    private static func containerName(_ pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "mov", "qt": "QuickTime (MOV)"
        case "mp4": "MPEG-4 (MP4)"
        case "m4v": "MPEG-4 (M4V)"
        default: pathExtension.uppercased()
        }
    }

    private static func formatFileSize(_ bytes: Int) -> String {
        let value = Double(bytes)
        return value >= 1_000_000_000 ? String(format: "%.2f GB", value / 1_000_000_000)
            : value >= 1_000_000 ? String(format: "%.1f MB", value / 1_000_000)
            : String(format: "%.0f KB", value / 1000)
    }

    private static func formatBitrate(_ bitsPerSecond: Double) -> String {
        bitsPerSecond >= 1_000_000
            ? String(format: "%.1f Mb/s", bitsPerSecond / 1_000_000)
            : String(format: "%.0f kb/s", bitsPerSecond / 1000)
    }
}

private extension Array where Element == MediaInfoSection.Row {
    mutating func add(_ name: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        append(MediaInfoSection.Row(name: name, value: value))
    }
}
