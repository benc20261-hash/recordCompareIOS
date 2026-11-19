import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip, .json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct BackupShareFile: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct BackupActivitySheet: UIViewControllerRepresentable {
    let url: URL
    let onCompletion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onCompletion(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private enum BackupOperation: Equatable {
    case creatingZIP
    case restoring

    var title: String {
        switch self {
        case .creatingZIP: "Creating ZIP backup"
        case .restoring: "Restoring ZIP backup"
        }
    }

    var initialMessage: String {
        switch self {
        case .creatingZIP: "Preparing backup contents…"
        case .restoring: "Opening selected backup…"
        }
    }
}

struct DataBackupView: View {
    @EnvironmentObject var store: ProductStore
    @State private var importPresented = false
    @State private var exportPresented = false
    @State private var shareFile: BackupShareFile?
    @State private var temporaryShareURL: URL?
    @State private var document = BackupFileDocument()
    @State private var filename = "ProductCompare_Backup.zip"
    @State private var exportContentType: UTType = .zip
    @State private var errorText: String?
    @State private var confirmRestore = false
    @State private var confirmClear = false
    @State private var confirmCleanup = false
    @State private var pendingURL: URL?
    @State private var activeOperation: BackupOperation?

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
                .disabled(activeOperation != nil)
                Text("When the ZIP is ready, choose Save to Files to select On My iPhone, iCloud Drive, or another available file provider.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(action: exportJSON) {
                    Label("Export Database JSON (no photos)", systemImage: "doc.text")
                        .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .foregroundStyle(Color.indigo).background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                }
                .disabled(activeOperation != nil)
                Button { importPresented = true } label: {
                    Label("Restore Android / iOS ZIP", systemImage: "square.and.arrow.down")
                        .font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .foregroundStyle(Color.indigo).background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                }
                .disabled(activeOperation != nil)
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
            .pointerDragScrolling()
        }
        .fileImporter(isPresented: $importPresented, allowedContentTypes: [.zip, .json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): pendingURL = urls.first; confirmRestore = pendingURL != nil
            case .failure(let error):
                let nsError = error as NSError
                if nsError.code != NSUserCancelledError {
                    errorText = "Could not open the selected backup: \(error.localizedDescription)"
                }
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
            switch result {
            case .success:
                store.statusMessage = exportContentType == .zip
                    ? "ZIP backup exported successfully."
                    : "Database JSON exported successfully."
                errorText = nil
            case .failure(let error):
                let nsError = error as NSError
                if nsError.code != NSUserCancelledError {
                    errorText = "Could not export the backup: \(error.localizedDescription)"
                }
            }
        }
        .sheet(item: $shareFile, onDismiss: removeTemporaryShareFile) { file in
            BackupActivitySheet(url: file.url) { completed in
                DispatchQueue.main.async {
                    if completed {
                        store.statusMessage = "ZIP backup saved or shared."
                        errorText = nil
                    }
                    shareFile = nil
                }
            }
            .ignoresSafeArea()
        }
        .overlay {
            if let activeOperation {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(Color.indigo)
                        Text(activeOperation.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(store.backupProgressMessage ?? activeOperation.initialMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: 300)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                }
                .transition(.opacity)
                .accessibilityAddTraits(.isModal)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activeOperation)
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
        guard activeOperation == nil else { return }
        activeOperation = .creatingZIP
        store.backupProgressMessage = "Preparing backup contents…"
        store.statusMessage = nil
        errorText = nil
        Task {
            do {
                let url = try await store.makeBackup()
                store.backupProgressMessage = nil
                activeOperation = nil
                temporaryShareURL = url
                shareFile = BackupShareFile(url: url)
            } catch {
                activeOperation = nil
                store.backupProgressMessage = nil
                errorText = "ZIP backup failed: \(error.localizedDescription)"
            }
        }
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
        guard activeOperation == nil, let pendingURL else { return }
        activeOperation = .restoring
        store.backupProgressMessage = "Opening the selected backup…"
        store.statusMessage = nil
        errorText = nil
        Task {
            do {
                store.statusMessage = try await store.importBackup(from: pendingURL)
            } catch {
                errorText = "Restore failed: \(error.localizedDescription)"
            }
            self.pendingURL = nil
            activeOperation = nil
            store.backupProgressMessage = nil
        }
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

    private func removeTemporaryShareFile() {
        if let temporaryShareURL {
            try? FileManager.default.removeItem(at: temporaryShareURL)
        }
        temporaryShareURL = nil
        shareFile = nil
    }
}
