import AVFoundation
import SwiftUI

/// Окно «Информация о файле»: кодеки, битрейты, цвет, тайм-код, метаданные.
struct MediaInfoSheet: View {
    let asset: AVURLAsset

    @Environment(\.dismiss) private var dismiss
    @State private var sections: [MediaInfoSection]?

    var body: some View {
        NavigationStack {
            Group {
                if let sections {
                    List(sections) { section in
                        Section(section.title) {
                            ForEach(section.rows) { row in
                                LabeledContent(row.name) {
                                    Text(row.value)
                                        .textSelection(.enabled)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("File Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let sections {
                        ShareLink(item: MediaInfoReader.plainText(sections)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .task { sections = await MediaInfoReader.read(asset: asset) }
    }
}
