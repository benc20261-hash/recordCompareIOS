import Foundation
import SwiftUI
import ZIPFoundation

@MainActor
final class ProductStore: ObservableObject {
    @Published var products: [Product] = [] { didSet { persist() } }
    @Published var specifications: [Specification] = [] { didSet { persist() } }
    @Published var reviews: [Review] = [] { didSet { persist() } }
    @Published var users: [User] = [] { didSet { persist() } }
    @Published var selectedTab: Tab = .catalog
    @Published var searchText = ""
    @Published var selectedTag: String? = "All"
    @Published var selectedBrand = "All"
    @Published var comparedProductIDs: Set<String> = []
    @Published var statusMessage: String?

    enum Tab: String, CaseIterable, Identifiable {
        case catalog = "Catalog"
        case compare = "Compare Products"
        case smartAdd = "Smart Add Product"
        case reviews = "Product Reviews"
        case backup = "Data & Backup"
        var id: String { rawValue }
    }

    private var isRestoring = false
    private var documentsURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var mediaURL: URL { documentsURL.appendingPathComponent("media", isDirectory: true) }
    private var databaseURL: URL { documentsURL.appendingPathComponent("database.json") }

    var allTags: [String] { Array(Set(products.flatMap(\.tags).filter { !$0.isEmpty })).sorted() }
    var allBrands: [String] { Array(Set(products.map(\.brand).filter { !$0.isEmpty })).sorted() }
    var filteredProducts: [Product] {
        products.filter { product in
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesQuery = q.isEmpty || [product.name, product.brand, product.overview, product.tags.joined(separator: " ")].joined(separator: " ").lowercased().contains(q)
            let matchesTag = selectedTag == nil || selectedTag == "All" || product.tags.contains(selectedTag!)
            let matchesBrand = selectedBrand == "All" || product.brand.caseInsensitiveCompare(selectedBrand) == .orderedSame
            return matchesQuery && matchesTag && matchesBrand
        }
    }

    func loadIfNeeded() {
        try? FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: databaseURL),
              let backup = try? JSONDecoder().decode(DatabaseBackup.self, from: data) else { return }
        isRestoring = true
        products = backup.products
        specifications = backup.specifications
        reviews = backup.reviews
        users = backup.users
        isRestoring = false
    }

    func localURL(for attachment: MediaAttachment) -> URL? {
        let raw = attachment.url
        if raw.hasPrefix("app-media://") {
            let filename = String(raw.dropFirst("app-media://".count))
            return mediaURL.appendingPathComponent(filename)
        }
        if raw.hasPrefix("file://"), let url = URL(string: raw), FileManager.default.fileExists(atPath: url.path) { return url }
        if raw.hasPrefix("/"), FileManager.default.fileExists(atPath: raw) { return URL(fileURLWithPath: raw) }
        let decodedName = URL(string: raw)?.lastPathComponent ?? URL(fileURLWithPath: raw).lastPathComponent
        for candidate in [attachment.id, decodedName, attachment.name] where !candidate.isEmpty {
            let exact = mediaURL.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: exact.path) { return exact }
            if let found = (try? FileManager.default.contentsOfDirectory(at: mediaURL, includingPropertiesForKeys: nil))?.first(where: { $0.lastPathComponent.lowercased().hasPrefix(candidate.lowercased()) || candidate.lowercased().hasPrefix($0.deletingPathExtension().lastPathComponent.lowercased()) }) { return found }
        }
        return nil
    }

    func toggleCompare(_ id: String) {
        if comparedProductIDs.contains(id) { comparedProductIDs.remove(id) }
        else if comparedProductIDs.count < 5 { comparedProductIDs.insert(id) }
        else { statusMessage = "You can compare up to 5 products." }
    }

    func addProduct(name: String, brand: String, tags: [String], overview: String, pictures: [MediaAttachment] = []) {
        let product = Product(id: "rec_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17), name: name.trimmingCharacters(in: .whitespacesAndNewlines), brand: brand, tags: tags, overview: overview, pictures: pictures, createdTime: ISO8601DateFormatter().string(from: Date()))
        products.insert(product, at: 0)
        statusMessage = "Product added."
    }

    func upsert(_ product: Product) {
        if let index = products.firstIndex(where: { $0.id == product.id }) { products[index] = product }
        else { products.insert(product, at: 0) }
    }

    func deleteProduct(_ id: String) {
        products.removeAll { $0.id == id }
        specifications.removeAll { $0.productId == id }
        reviews.removeAll { $0.productIds.contains(id) }
        comparedProductIDs.remove(id)
    }

    func saveReview(title: String, body: String, author: String, rating: Int, productIDs: [String]) {
        let linked = products.filter { productIDs.contains($0.id) }
        let review = Review(id: "rev_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17), reviewNumber: (reviews.map(\.reviewNumber).max() ?? 0) + 1, title: title, body: body, authorName: author.isEmpty ? "Verified Reviewer" : author, rating: rating, productIds: linked.map(\.id), productTitles: linked.map(\.name), pictures: [], createdTime: ISO8601DateFormatter().string(from: Date()))
        reviews.insert(review, at: 0)
    }

    func importBackup(from url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let lower = url.lastPathComponent.lowercased()
        let jsonData: Data
        var extractedFiles: [URL] = []
        if lower.hasSuffix(".zip") {
            let archive = try Archive(url: url, accessMode: .read)
            var databaseEntry: Entry?
            for entry in archive {
                let components = entry.path.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
                guard let name = components.last?.lowercased() else { continue }
                if name == "database.json" { databaseEntry = entry; continue }
                guard entry.type == .file, Self.isMediaPath(entry.path) else { continue }
                let safeName = String(components.last!)
                let target = staging.appendingPathComponent(safeName)
                _ = try archive.extract(entry, to: target)
                extractedFiles.append(target)
            }
            guard let entry = databaseEntry else { throw BackupError.missingDatabase }
            let target = staging.appendingPathComponent("database.json")
            _ = try archive.extract(entry, to: target)
            jsonData = try Data(contentsOf: target)
        } else {
            jsonData = try Data(contentsOf: url)
        }

        let decoder = JSONDecoder()
        let backup = try decoder.decode(DatabaseBackup.self, from: jsonData)
        try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        for file in extractedFiles {
            let destination = mediaURL.appendingPathComponent(file.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: file, to: destination)
        }

        let mediaFiles = (try? FileManager.default.contentsOfDirectory(at: mediaURL, includingPropertiesForKeys: nil)) ?? []
        func remap(_ picture: MediaAttachment) -> MediaAttachment {
            let candidates = [picture.id, URL(string: picture.url)?.lastPathComponent ?? "", picture.name].filter { !$0.isEmpty }
            if let file = mediaFiles.first(where: { file in candidates.contains(where: { candidate in file.lastPathComponent.caseInsensitiveCompare(candidate) == .orderedSame || file.lastPathComponent.lowercased().hasPrefix(candidate.lowercased() + "_") || file.deletingPathExtension().lastPathComponent.lowercased().hasPrefix(candidate.lowercased()) }) }) {
                var mapped = picture; mapped.url = "app-media://\(file.lastPathComponent)"; return mapped
            }
            return picture
        }
        var importedProducts = backup.products
        for index in importedProducts.indices { importedProducts[index].pictures = importedProducts[index].pictures.map(remap) }
        var importedSpecs = backup.specifications
        for index in importedSpecs.indices { importedSpecs[index].pictures = importedSpecs[index].pictures.map(remap) }
        var importedReviews = backup.reviews
        for index in importedReviews.indices {
            importedReviews[index].pictures = importedReviews[index].pictures.map(remap)
            importedReviews[index].body = Self.remapReviewHTML(importedReviews[index].body, files: mediaFiles)
        }
        isRestoring = true
        products = importedProducts; specifications = importedSpecs; reviews = importedReviews; users = backup.users
        comparedProductIDs = []
        isRestoring = false
        persist()
        return "Restored \(products.count) products, \(specifications.count) specifications, and \(reviews.count) reviews."
    }

    func makeBackup() throws -> URL {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("ProductCompare_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let media = staging.appendingPathComponent("review_images", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let database = DatabaseBackup(shareId: "", baseId: "", sourceUrl: "local", lastSynced: ISO8601DateFormatter().string(from: Date()), products: products.map { p in var p = p; p.pictures = p.pictures.map { sanitized($0) }; return p }, specifications: specifications.map { s in var s = s; s.pictures = s.pictures.map { sanitized($0) }; return s }, reviews: reviews.map { r in var r = r; r.pictures = r.pictures.map { sanitized($0) }; return r }, users: users)
        try encoder.encode(database).write(to: staging.appendingPathComponent("database.json"))
        let allAttachments = products.flatMap(\.pictures) + specifications.flatMap(\.pictures) + reviews.flatMap(\.pictures)
        var copied = Set<String>()
        for attachment in allAttachments {
            guard let source = localURL(for: attachment), FileManager.default.fileExists(atPath: source.path) else { continue }
            let filename = source.lastPathComponent
            guard copied.insert(filename).inserted else { continue }
            try FileManager.default.copyItem(at: source, to: media.appendingPathComponent(filename))
        }
        let manifest = ManifestFile(appName: "ProductCompare", exportDate: ISO8601DateFormatter().string(from: Date()), productCount: products.count, specificationCount: specifications.count, reviewCount: reviews.count, userCount: users.count, pictureCount: copied.count, version: "1.0")
        try encoder.encode(manifest).write(to: staging.appendingPathComponent("manifest.json"))
        let archiveURL = documentsURL.appendingPathComponent("ProductCompare_Backup_\(Int(Date().timeIntervalSince1970)).zip")
        try? FileManager.default.removeItem(at: archiveURL)
        guard let archive = Archive(url: archiveURL, accessMode: .create) else { throw BackupError.archiveCreation }
        for file in (try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) {
            try archive.addEntry(with: file.lastPathComponent, fileURL: file, compressionMethod: .deflate)
        }
        let mediaFiles = (try? FileManager.default.contentsOfDirectory(at: media, includingPropertiesForKeys: nil)) ?? []
        for file in mediaFiles { try archive.addEntry(with: "review_images/\(file.lastPathComponent)", fileURL: file, compressionMethod: .deflate) }
        return archiveURL
    }

    private func sanitized(_ attachment: MediaAttachment) -> MediaAttachment {
        var value = attachment
        if value.url.hasPrefix("app-media://") { value.url = value.name }
        else if let url = localURL(for: value) { value.url = url.lastPathComponent }
        return value
    }

    private func persist() {
        guard !isRestoring else { return }
        let backup = DatabaseBackup(shareId: "", baseId: "", sourceUrl: "local", lastSynced: ISO8601DateFormatter().string(from: Date()), products: products, specifications: specifications, reviews: reviews, users: users)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(backup) { try? data.write(to: databaseURL, options: .atomic) }
    }

    private static func isMediaPath(_ path: String) -> Bool {
        let lower = path.lowercased().replacingOccurrences(of: "\\", with: "/")
        let ext = URL(fileURLWithPath: lower).pathExtension
        return ["images/", "pictures/", "review_images/", "attachments/", "media/", "files/"].contains(where: { lower.contains($0) }) || ["jpg", "jpeg", "png", "webp", "gif", "svg", "bmp", "avif", "ico"].contains(ext)
    }

    private static func remapReviewHTML(_ html: String, files: [URL]) -> String {
        var result = html
        for file in files {
            let escaped = NSRegularExpression.escapedPattern(for: file.lastPathComponent)
            for pattern in ["https://local\\.review/review_images/", "file:(?:/{1,3})?[^\\\"']*/", "(?:\\./)?(?:images|pictures|review_images)/"] {
                if let regex = try? NSRegularExpression(pattern: "(?i)(src=[\\\"'])" + pattern + "[^\\\"']*" + escaped + "([\\\"'])") {
                    let range = NSRange(result.startIndex..., in: result)
                    result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1app-media://" + file.lastPathComponent + "$2")
                }
            }
        }
        return result
    }

    enum BackupError: LocalizedError {
        case missingDatabase, archiveCreation
        var errorDescription: String? {
            switch self { case .missingDatabase: "The ZIP does not contain database.json."; case .archiveCreation: "Could not create the backup archive." }
        }
    }
}
