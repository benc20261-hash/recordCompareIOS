import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip, .json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct DataBackupView: View {
    @EnvironmentObject var store: ProductStore
    @State private var importPresented = false
    @State private var exportPresented = false
    @State private var document = BackupFileDocument()
    @State private var filename = "ProductCompare_Backup.zip"
    @State private var exportContentType: UTType = .zip
    @State private var errorText: String?
    @State private var confirmRestore = false
    @State private var confirmClear = false
    @State private var confirmCleanup = false
    @State private var pendingURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Data & Backup").font(.system(size: 27, weight: .bold))
                Text("Your catalog stays on this iPhone. No online account or sync is used.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    countCard("Products", value: store.products.count, icon: "shippingbox")
                    countCard("Specs", value: store.specifications.count, icon: "list.bullet.rectangle")
                    countCard("Reviews", value: store.reviews.count, icon: "text.bubble")
                }
                Button(action: exportBackup) {
                    Label("Create ZIP Backup", systemImage: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .foregroundStyle(.white).background(Color.indigo, in: RoundedRectangle(cornerRadius: 15))
                }
                Button(action: exportJSON) {
                    Label("Export Database JSON (no photos)", systemImage: "doc.text")
                        .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .foregroundStyle(Color.indigo).background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                }
                Button { importPresented = true } label: {
                    Label("Restore Android / iOS ZIP", systemImage: "square.and.arrow.down")
                        .font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .foregroundStyle(Color.indigo).background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                }
                Text("Restore replaces the current catalog. Android archive folders such as pictures, review_images, images, and attachments are supported.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Local storage").font(.headline)
                    Button { confirmCleanup = true } label: {
                        Label("Remove unused media files", systemImage: "externaldrive.badge.minus")
                    }
                    Button(role: .destructive) { confirmClear = true } label: {
                        Label("Clear all app data and photos", systemImage: "trash")
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                if let message = store.statusMessage {
                    let isRestoreWarning = message.contains("missing from the backup") ||
                        message.contains("manifest declares")
                    Text(message)
                        .font(.footnote.weight(isRestoreWarning ? .semibold : .regular))
                        .foregroundStyle(isRestoreWarning ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let errorText { Text(errorText).font(.footnote).foregroundStyle(.red) }
            }
            .padding(18)
        }
        .fileImporter(isPresented: $importPresented, allowedContentTypes: [.zip, .json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): pendingURL = urls.first; confirmRestore = pendingURL != nil
            case .failure(let error): errorText = error.localizedDescription
            }
        }
        .confirmationDialog("Replace this iPhone’s current data with the selected backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore and Replace", role: .destructive) { restore() }
            Button("Cancel", role: .cancel) { pendingURL = nil }
        }
        .confirmationDialog("Delete the entire local catalog and all saved photos?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear All Data", role: .destructive) { clearAllData() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove media files not referenced by any product, specification, or review?", isPresented: $confirmCleanup, titleVisibility: .visible) {
            Button("Remove Unused Media", role: .destructive) { removeUnusedMedia() }
            Button("Cancel", role: .cancel) {}
        }
        .fileExporter(isPresented: $exportPresented, document: document, contentType: exportContentType, defaultFilename: filename) { result in
            if case .failure(let error) = result { errorText = error.localizedDescription }
        }
    }

    private func countCard(_ title: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.indigo)
            Text("\(value)").font(.system(size: 20, weight: .bold))
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func exportBackup() {
        do {
            let url = try store.makeBackup()
            document = BackupFileDocument(data: try Data(contentsOf: url))
            filename = url.deletingPathExtension().lastPathComponent
            exportContentType = .zip
            exportPresented = true
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    private func exportJSON() {
        do {
            let url = try store.makeJSONBackup()
            document = BackupFileDocument(data: try Data(contentsOf: url))
            filename = url.deletingPathExtension().lastPathComponent
            exportContentType = .json
            exportPresented = true
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    private func restore() {
        guard let pendingURL else { return }
        do { store.statusMessage = try store.importBackup(from: pendingURL); errorText = nil }
        catch { errorText = error.localizedDescription }
        self.pendingURL = nil
    }

    private func clearAllData() {
        do { try store.clearAllData(); errorText = nil }
        catch { errorText = error.localizedDescription }
    }

    private func removeUnusedMedia() {
        do {
            let count = try store.removeOrphanedMedia()
            store.statusMessage = "Removed \(count) unused media file\(count == 1 ? "" : "s")."
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }
}
