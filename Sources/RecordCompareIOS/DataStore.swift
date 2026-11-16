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
    @Published var comparedProductOrder: [String] = []
    @Published var catalogSort: CatalogSort = .nameAscending
    @Published var statusMessage: String?

    enum CatalogSort: String, CaseIterable, Identifiable {
        case nameAscending
        case nameDescending
        case brand
        case newest
        case oldest

        var id: String { rawValue }
        var title: String {
            switch self {
            case .nameAscending: "Name A–Z"
            case .nameDescending: "Name Z–A"
            case .brand: "Brand"
            case .newest: "Newest first"
            case .oldest: "Oldest first"
            }
        }
    }

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
        let filtered = products.filter { product in
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let specs = specifications.filter { $0.productId == product.id || $0.productTitle == product.name }
            let searchable = ([product.name, product.brand, product.overview] + product.tags + specs.flatMap { [$0.specName, $0.details, $0.unit ?? ""] })
                .joined(separator: " ").lowercased()
            let matchesQuery = q.isEmpty || searchable.contains(q)
            let filterValue = selectedTag ?? ""
            let matchesTag = selectedTag == nil || selectedTag == "All" ||
                product.tags.contains { $0.caseInsensitiveCompare(filterValue) == .orderedSame } ||
                product.brand.caseInsensitiveCompare(filterValue) == .orderedSame ||
                product.name.caseInsensitiveCompare(filterValue) == .orderedSame
            let matchesBrand = selectedBrand == "All" || product.brand.caseInsensitiveCompare(selectedBrand) == .orderedSame
            return matchesQuery && matchesTag && matchesBrand
        }
        switch catalogSort {
        case .nameAscending:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDescending:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .brand:
            return filtered.sorted {
                let comparison = $0.brand.localizedCaseInsensitiveCompare($1.brand)
                return comparison == .orderedSame
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : comparison == .orderedAscending
            }
        case .newest:
            return filtered.sorted { ($0.createdTime ?? "") > ($1.createdTime ?? "") }
        case .oldest:
            return filtered.sorted { ($0.createdTime ?? "") < ($1.createdTime ?? "") }
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
            guard !filename.isEmpty, URL(fileURLWithPath: filename).lastPathComponent == filename else { return nil }
            let url = mediaURL.appendingPathComponent(filename)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if raw.hasPrefix("file://"), let url = URL(string: raw), FileManager.default.fileExists(atPath: url.path) { return url }
        if raw.hasPrefix("/"), FileManager.default.fileExists(atPath: raw) { return URL(fileURLWithPath: raw) }
        let decodedName = URL(string: raw)?.lastPathComponent ?? URL(fileURLWithPath: raw).lastPathComponent
        for candidate in [attachment.id, decodedName, attachment.name] where !candidate.isEmpty {
            let exact = mediaURL.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: exact.path) { return exact }
            if let found = (try? FileManager.default.contentsOfDirectory(at: mediaURL, includingPropertiesForKeys: nil))?.first(where: {
                Self.matchesMediaName($0.lastPathComponent, candidate: candidate)
            }) { return found }
        }
        return nil
    }

    var localMediaDirectoryURL: URL { mediaURL }

    func normalizeReviewHTMLForStorage(_ html: String) -> String {
        guard let imageSourceRegex = try? NSRegularExpression(
            pattern: #"(?i)(src\s*=\s*["'])([^"']+)(["'])"#
        ) else { return html }
        let matches = imageSourceRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var result = html
        for match in matches.reversed() {
            guard let sourceRange = Range(match.range(at: 2), in: html),
                  let fullRange = Range(match.range, in: result),
                  let prefixRange = Range(match.range(at: 1), in: result),
                  let suffixRange = Range(match.range(at: 3), in: result) else { continue }
            let source = String(html[sourceRange])
            guard let url = URL(string: source), url.isFileURL,
                  url.standardizedFileURL.path.hasPrefix(mediaURL.standardizedFileURL.path + "/") else { continue }
            let filename = url.lastPathComponent
            result.replaceSubrange(
                fullRange,
                with: String(result[prefixRange]) + "app-media://\(filename)" + String(result[suffixRange])
            )
        }
        guard let remoteImageRegex = try? NSRegularExpression(
            pattern: #"(?i)(<img\b[^>]*?)\s+src\s*=\s*(["'])(?:https?:)?//[^"']*\2([^>]*>)"#
        ) else { return result }
        return remoteImageRegex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1$3"
        )
    }

    func reviewAttachments(in html: String, preserving existing: [MediaAttachment] = []) -> [MediaAttachment] {
        let filenames = Self.localMediaFilenames(in: html)
        var attachments = existing
        for filename in filenames where !attachments.contains(where: {
            localURL(for: $0)?.lastPathComponent == filename
        }) {
            attachments.append(MediaAttachment(
                id: UUID().uuidString,
                name: filename,
                url: "app-media://\(filename)"
            ))
        }
        return attachments
    }

    private static func reviewFallbackTitle(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let filename = url.deletingPathExtension().lastPathComponent
        if filename.caseInsensitiveCompare("note") == .orderedSame ||
            filename.caseInsensitiveCompare("index") == .orderedSame {
            return url.deletingLastPathComponent().lastPathComponent
        }
        return filename
    }

    private static func suggestedProductTitles(title: String, body: String, products: [Product]) -> [String] {
        let cleanTitle = title.lowercased()
        let cleanBody = body
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .lowercased()
        if let match = products.first(where: { cleanTitle.contains($0.name.lowercased()) }) {
            return [match.name]
        }
        if let match = products.first(where: { !$0.brand.isEmpty && cleanTitle.contains($0.brand.lowercased()) }) {
            return [match.name]
        }
        if let match = products.first(where: { cleanBody.contains($0.name.lowercased()) }) {
            return [match.name]
        }
        return []
    }

    private static func cleanImportedReviewHTML(_ html: String, title: String) -> String {
        var content = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bodyRegex = try? NSRegularExpression(pattern: #"(?is)<body[^>]*>(.*?)</body>"#),
           let match = bodyRegex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
           let bodyRange = Range(match.range(at: 1), in: content) {
            content = String(content[bodyRange])
        } else {
            content = content
                .replacingOccurrences(of: #"(?is)<head[^>]*>.*?</head>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?is)<!DOCTYPE[^>]*>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?is)</?html[^>]*>"#, with: "", options: .regularExpression)
        }
        content = content
            .replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<link\b[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+on[a-z]+\s*=\s*(["']).*?\1"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<img\b[^>]*\bsrc\s*=\s*["'](?:https?:)?//[^"']*["'][^>]*>"#, with: "", options: .regularExpression)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTitle.isEmpty,
              let headingRegex = try? NSRegularExpression(pattern: #"(?is)^\s*<h[12][^>]*>(.*?)</h[12]>\s*"#),
              let match = headingRegex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let headingRange = Range(match.range(at: 1), in: content),
              let fullRange = Range(match.range, in: content) else {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let heading = String(content[headingRange])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if heading == normalizedTitle || heading.contains(normalizedTitle) || normalizedTitle.contains(heading) {
            content.removeSubrange(fullRange)
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func toggleCompare(_ id: String) {
        if comparedProductIDs.contains(id) {
            setComparedProductOrder(comparedProductOrder.filter { $0 != id })
        }
        else if comparedProductOrder.count < 5 {
            setComparedProductOrder(comparedProductOrder + [id])
        }
        else { statusMessage = "You can compare up to 5 products." }
    }

    func setComparedProductOrder(_ order: [String]) {
        var unique: [String] = []
        for id in order where products.contains(where: { $0.id == id }) && !unique.contains(id) {
            guard unique.count < 5 else { break }
            unique.append(id)
        }
        comparedProductOrder = unique
        comparedProductIDs = Set(unique)
    }

    func moveComparedProduct(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < comparedProductOrder.count,
              destination >= 0, destination < comparedProductOrder.count else { return }
        var order = comparedProductOrder
        let item = order.remove(at: source)
        order.insert(item, at: destination)
        setComparedProductOrder(order)
    }

    func clearComparison() {
        setComparedProductOrder([])
    }

    func removeComparedProduct(_ id: String) {
        setComparedProductOrder(comparedProductOrder.filter { $0 != id })
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

    func saveProduct(_ product: Product, specifications productSpecs: [Specification]) {
        isRestoring = true
        let previousProduct = products.first(where: { $0.id == product.id })
        if let index = products.firstIndex(where: { $0.id == product.id }) {
            products[index] = product
        } else {
            products.insert(product, at: 0)
        }
        let otherSpecs = specifications.filter { specification in
            specification.productId != product.id &&
                (previousProduct == nil || specification.productTitle != previousProduct?.name)
        }
        specifications = otherSpecs + productSpecs.enumerated().map { index, specification in
            var value = specification
            value.productId = product.id
            value.productTitle = product.name
            value.order = index + 1
            return value
        }
        for index in reviews.indices {
            let hadIDLink = reviews[index].productIds.contains(product.id)
            let hadTitleLink = previousProduct.map { old in reviews[index].productTitles.contains(old.name) } ?? false
            guard hadIDLink || hadTitleLink else { continue }
            if let previousProduct {
                reviews[index].productTitles = reviews[index].productTitles.map {
                    $0 == previousProduct.name ? product.name : $0
                }
            }
            for id in reviews[index].productIds {
                if let linkedName = products.first(where: { $0.id == id })?.name,
                   !reviews[index].productTitles.contains(linkedName) {
                    reviews[index].productTitles.append(linkedName)
                }
            }
        }
        isRestoring = false
        persist()
    }

    func saveProducts(_ entries: [(product: Product, specifications: [Specification])]) {
        guard !entries.isEmpty else { return }
        isRestoring = true
        let newProducts = entries.map(\.product)
        products.insert(contentsOf: newProducts, at: 0)
        let newSpecifications = entries.flatMap { entry in
            entry.specifications.enumerated().map { index, specification in
                var value = specification
                value.productId = entry.product.id
                value.productTitle = entry.product.name
                value.order = index + 1
                return value
            }
        }
        specifications.append(contentsOf: newSpecifications)
        isRestoring = false
        persist()
    }

    func createAndCompare(name: String, inheritedSpecNames: [String]) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        guard comparedProductOrder.count < 5 else {
            statusMessage = "You can compare up to 5 products."
            return
        }
        let id = "rec_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17))
        let product = Product(
            id: id,
            name: cleanName,
            brand: "Generic",
            tags: ["Smart Add", "IT product"],
            overview: "Created from the Smart Add comparison matrix.",
            pictures: [],
            createdTime: ISO8601DateFormatter().string(from: Date())
        )
        let uniqueNames = inheritedSpecNames.reduce(into: [String]()) { names, name in
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = specificationNameKey(clean)
            if !key.isEmpty && !names.contains(where: { specificationNameKey($0) == key }) {
                names.append(clean)
            }
        }
        let inheritedSpecs = uniqueNames.enumerated().map { index, name in
            let reference = specifications.first {
                specificationNameKey($0.specName) == specificationNameKey(name) &&
                    (($0.unit?.isEmpty == false) || $0.isNumeric != nil)
            }
            return Specification(
                id: "spec_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17)),
                specName: name,
                details: "",
                order: index + 1,
                productId: id,
                productTitle: cleanName,
                unit: reference?.unit,
                pictures: [],
                isNumeric: reference?.isNumeric
            )
        }
        isRestoring = true
        products.insert(product, at: 0)
        specifications.append(contentsOf: inheritedSpecs)
        isRestoring = false
        setComparedProductOrder(comparedProductOrder + [id])
        persist()
        statusMessage = "Product “\(cleanName)” created with \(inheritedSpecs.count) specifications and added to comparison."
    }

    func updateProductBrand(_ productID: String, brand: String) {
        guard let index = products.firstIndex(where: { $0.id == productID }) else { return }
        products[index].brand = brand
    }

    func updateProductTags(_ productID: String, tags: [String]) {
        guard let index = products.firstIndex(where: { $0.id == productID }) else { return }
        products[index].tags = tags
    }

    func updateInlineSpec(
        productID: String,
        specName: String,
        details: String,
        pictures: [MediaAttachment],
        unit: String?,
        isNumeric: Bool?
    ) {
        guard let product = products.first(where: { $0.id == productID }) else { return }
        let cleanName = specName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        if let index = specifications.firstIndex(where: {
            ($0.productId == productID || $0.productTitle == product.name) &&
                $0.specName.caseInsensitiveCompare(cleanName) == .orderedSame
        }) {
            specifications[index].details = details
            specifications[index].pictures = pictures
            let cleanUnit = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
            specifications[index].unit = cleanUnit?.isEmpty == true ? nil : cleanUnit
            specifications[index].isNumeric = isNumeric
        } else {
            let cleanUnit = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
            specifications.append(Specification(
                id: "spec_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17)),
                specName: cleanName,
                details: details,
                order: (specifications.filter { $0.productId == productID }.map(\.order).max() ?? 0) + 1,
                productId: productID,
                productTitle: product.name,
                unit: cleanUnit?.isEmpty == true ? nil : cleanUnit,
                pictures: pictures,
                isNumeric: isNumeric
            ))
        }
    }

    func saveSpecification(_ specification: Specification) {
        guard let product = products.first(where: { $0.id == specification.productId }) else { return }
        let name = specification.specName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var saved = specification
        saved.specName = name
        saved.productTitle = product.name
        if let index = specifications.firstIndex(where: { $0.id == saved.id }) {
            saved.order = specifications[index].order
            specifications[index] = saved
        } else {
            saved.order = (specifications.filter { $0.productId == product.id }.map(\.order).max() ?? 0) + 1
            specifications.append(saved)
        }
    }

    func deleteInlineSpec(productID: String, specName: String) {
        guard let product = products.first(where: { $0.id == productID }) else { return }
        specifications.removeAll {
            ($0.productId == productID || $0.productTitle == product.name) &&
                $0.specName.caseInsensitiveCompare(specName) == .orderedSame
        }
        let remainingIDs = specifications
            .filter { $0.productId == productID }
            .sorted { $0.order < $1.order }
            .map(\.id)
        for (order, id) in remainingIDs.enumerated() {
            if let index = specifications.firstIndex(where: { $0.id == id }) {
                specifications[index].order = order + 1
            }
        }
    }

    func moveProductSpec(productID: String, specID: String, offset: Int) {
        var productSpecs = specifications
            .filter { $0.productId == productID }
            .sorted { $0.order < $1.order }
        guard let index = productSpecs.firstIndex(where: { $0.id == specID }) else { return }
        let destination = index + offset
        guard productSpecs.indices.contains(destination) else { return }
        productSpecs.swapAt(index, destination)
        for (order, spec) in productSpecs.enumerated() {
            if let storeIndex = specifications.firstIndex(where: { $0.id == spec.id }) {
                specifications[storeIndex].order = order + 1
            }
        }
    }

    func canCompareAdding(_ count: Int) -> Bool {
        count >= 0 && comparedProductOrder.count + count <= 5
    }

    func saveLocalPhoto(_ data: Data, originalName: String) throws -> MediaAttachment {
        try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        let safeName = URL(fileURLWithPath: originalName).lastPathComponent
            .replacingOccurrences(of: "/", with: "_")
        let filename = "photo_\(UUID().uuidString)_\(safeName.isEmpty ? "image.jpg" : safeName)"
        try data.write(to: mediaURL.appendingPathComponent(filename), options: .atomic)
        return MediaAttachment(
            id: UUID().uuidString,
            name: safeName.isEmpty ? filename : safeName,
            url: "app-media://\(filename)",
            size: data.count,
            mimetype: filename.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg"
        )
    }

    func deleteProduct(_ id: String) {
        let deletedName = products.first(where: { $0.id == id })?.name
        products.removeAll { $0.id == id }
        specifications.removeAll { $0.productId == id || (deletedName != nil && $0.productTitle == deletedName) }
        for index in reviews.indices where reviews[index].productIds.contains(id) || (deletedName.map { reviews[index].productTitles.contains($0) } ?? false) {
            reviews[index].productIds.removeAll { $0 == id }
            reviews[index].productTitles.removeAll { $0 == deletedName }
        }
        comparedProductIDs.remove(id)
        comparedProductOrder.removeAll { $0 == id }
    }

    func saveReview(title: String, body: String, author: String, rating: Int, productIDs: [String]) {
        let linked = products.filter { productIDs.contains($0.id) }
        let review = Review(id: "rev_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17), reviewNumber: (reviews.map(\.reviewNumber).max() ?? 0) + 1, title: title, body: body, authorName: author.isEmpty ? "Verified Reviewer" : author, rating: rating, productIds: linked.map(\.id), productTitles: linked.map(\.name), pictures: [], createdTime: ISO8601DateFormatter().string(from: Date()))
        reviews.insert(review, at: 0)
    }

    func setReviewProducts(reviewID: String, productIDs: Set<String>) {
        guard let index = reviews.firstIndex(where: { $0.id == reviewID }) else { return }
        let linked = products.filter { productIDs.contains($0.id) }
        reviews[index].productIds = linked.map(\.id)
        reviews[index].productTitles = linked.map(\.name)
    }

    func importBackup(from url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let lower = url.lastPathComponent.lowercased()
        let isArchiveBackup = lower.hasSuffix(".zip")
        let jsonData: Data
        var manifestPictureCount: Int?
        var extractedFiles: [(archivePath: String, originalName: String, url: URL)] = []
        if isArchiveBackup {
            let archive = try Archive(url: url, accessMode: .read)
            var databaseEntry: Entry?
            for entry in archive {
                let archivePath = entry.path.replacingOccurrences(of: "\\", with: "/")
                let components = archivePath.split(separator: "/")
                guard !archivePath.hasPrefix("/"), !components.contains("..") else { continue }
                guard let name = components.last?.lowercased() else { continue }
                if name == "database.json" { databaseEntry = entry; continue }
                if name == "manifest.json", entry.type == .file {
                    let target = staging.appendingPathComponent("manifest.json")
                    _ = try archive.extract(entry, to: target)
                    if let data = try? Data(contentsOf: target),
                       let jsonObject = try? JSONSerialization.jsonObject(with: data),
                       let manifest = jsonObject as? [String: Any] {
                        manifestPictureCount = manifest["pictureCount"] as? Int
                    }
                    continue
                }
                guard entry.type == .file, Self.isMediaPath(entry.path) else { continue }
                let originalName = String(components.last!)
                let target = staging.appendingPathComponent("\(UUID().uuidString)_\(originalName)")
                _ = try archive.extract(entry, to: target)
                extractedFiles.append((archivePath, originalName, target))
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
        var importedMedia: [(archivePath: String, originalName: String, localName: String)] = []
        for file in extractedFiles {
            var localName = file.originalName
            var destination = mediaURL.appendingPathComponent(localName)
            if FileManager.default.fileExists(atPath: destination.path) {
                if FileManager.default.contentsEqual(atPath: file.url.path, andPath: destination.path) {
                    importedMedia.append((file.archivePath, file.originalName, localName))
                    continue
                }
                let ext = destination.pathExtension
                let stem = destination.deletingPathExtension().lastPathComponent
                localName = "\(stem)_\(UUID().uuidString.prefix(8))" + (ext.isEmpty ? "" : ".\(ext)")
                destination = mediaURL.appendingPathComponent(localName)
            }
            try FileManager.default.copyItem(at: file.url, to: destination)
            importedMedia.append((file.archivePath, file.originalName, localName))
        }

        let mediaFiles = (try? FileManager.default.contentsOfDirectory(at: mediaURL, includingPropertiesForKeys: nil)) ?? []
        var missingMediaReferences: [String] = []
        func remap(_ picture: MediaAttachment) -> MediaAttachment {
            let candidates = Self.mediaCandidates(id: picture.id, name: picture.name, url: picture.url)
            let sourceFolder = Self.mediaFolder(in: picture.url)
            if let imported = importedMedia.first(where: { file in
                let folderMatches = sourceFolder.map { file.archivePath.lowercased().contains("/\($0)/") || file.archivePath.lowercased().hasPrefix("\($0)/") } ?? false
                return candidates.contains(where: { Self.matchesMediaName(file.originalName, candidate: $0) }) && (folderMatches || sourceFolder == nil)
            }) ?? importedMedia.first(where: { file in
                candidates.contains(where: { Self.matchesMediaName(file.originalName, candidate: $0) })
            }) {
                var mapped = picture
                mapped.url = "app-media://\(imported.localName)"
                return mapped
            }
            if !isArchiveBackup, let file = mediaFiles.first(where: { file in
                candidates.contains(where: { Self.matchesMediaName(file.lastPathComponent, candidate: $0) })
            }) {
                var mapped = picture
                mapped.url = "app-media://\(file.lastPathComponent)"
                return mapped
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
            let remappedBody = Self.remapReviewHTML(importedReviews[index].body, assets: importedMedia)
            importedReviews[index].body = remappedBody.html
            let title = importedReviews[index].title ?? "Review #\(importedReviews[index].reviewNumber)"
            missingMediaReferences += remappedBody.missingFilenames.map { "\(title): \($0)" }
        }
        func isResolved(_ attachment: MediaAttachment) -> Bool {
            let resolvesToImportedFile = attachment.url.hasPrefix("app-media://") &&
                localURL(for: attachment) != nil
            return isArchiveBackup ? resolvesToImportedFile : localURL(for: attachment) != nil
        }
        var unresolvedAttachments: [String] = []
        for product in importedProducts {
            for picture in product.pictures where !isResolved(picture) {
                unresolvedAttachments.append("\(product.name): \(picture.name)")
            }
        }
        for specification in importedSpecs {
            for picture in specification.pictures where !isResolved(picture) {
                let productTitle = specification.productTitle ?? specification.productId
                unresolvedAttachments.append("\(productTitle) / \(specification.specName): \(picture.name)")
            }
        }
        for review in importedReviews {
            let title = review.title ?? "Review #\(review.reviewNumber)"
            for picture in review.pictures where !isResolved(picture) {
                unresolvedAttachments.append("\(title): \(picture.name)")
            }
        }
        missingMediaReferences.append(contentsOf: unresolvedAttachments)
        let uniqueMissingReferences = missingMediaReferences.reduce(into: [String]()) { result, reference in
            if !result.contains(reference) { result.append(reference) }
        }
        isRestoring = true
        products = importedProducts; specifications = importedSpecs; reviews = importedReviews; users = backup.users
        comparedProductIDs = []
        comparedProductOrder = []
        isRestoring = false
        persist()
        let summary = "Restored \(products.count) products, \(specifications.count) specifications, and \(reviews.count) reviews."
        let uniqueMediaCount = Set(importedMedia.map(\.originalName)).count
        let manifestNote = manifestPictureCount.map {
            $0 == uniqueMediaCount
                ? ""
                : " The manifest declares \($0) pictures; the archive contains \(uniqueMediaCount) distinct media filenames across \(importedMedia.count) entries."
        } ?? ""
        if !uniqueMissingReferences.isEmpty {
            let shown = uniqueMissingReferences.prefix(5).joined(separator: "; ")
            let remaining = uniqueMissingReferences.count - min(uniqueMissingReferences.count, 5)
            let more = remaining > 0 ? "; and \(remaining) more" : ""
            return "\(summary) \(uniqueMissingReferences.count) referenced image(s) are missing from the backup and unavailable offline: \(shown)\(more).\(manifestNote)"
        }
        return summary + manifestNote
    }

    func importReviewNotes(from url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        var reviewFiles: [(name: String, url: URL, isMarkdown: Bool)] = []
        var imageFiles: [(archivePath: String, name: String, url: URL)] = []
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                throw BackupError.unsupportedReviewImport
            }
            for case let fileURL as URL in enumerator {
                guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let relativePath = String(fileURL.path.dropFirst(url.path.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    .replacingOccurrences(of: "\\", with: "/")
                guard !relativePath.split(separator: "/").contains("__MACOSX"),
                      !fileURL.lastPathComponent.hasPrefix("._"),
                      fileURL.lastPathComponent != ".DS_Store" else { continue }
                let ext = fileURL.pathExtension.lowercased()
                let target = staging.appendingPathComponent("\(UUID().uuidString)_\(fileURL.lastPathComponent)")
                if ["html", "htm", "md", "markdown"].contains(ext) {
                    try FileManager.default.copyItem(at: fileURL, to: target)
                    reviewFiles.append((relativePath, target, ["md", "markdown"].contains(ext)))
                } else if Self.isMediaPath(relativePath) {
                    try FileManager.default.copyItem(at: fileURL, to: target)
                    imageFiles.append((relativePath, fileURL.lastPathComponent, target))
                }
            }
        } else if url.pathExtension.lowercased() == "zip" {
            let archive = try Archive(url: url, accessMode: .read)
            for entry in archive where entry.type == .file {
                let path = entry.path.replacingOccurrences(of: "\\", with: "/")
                let components = path.split(separator: "/")
                guard !path.hasPrefix("/"), !components.contains(".."), let last = components.last else { continue }
                let filename = String(last)
                guard !components.contains("__MACOSX"),
                      !filename.hasPrefix("._"),
                      filename != ".DS_Store" else { continue }
                let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
                if ["html", "htm", "md", "markdown"].contains(ext) {
                    let target = staging.appendingPathComponent("\(UUID().uuidString)_\(filename)")
                    _ = try archive.extract(entry, to: target)
                    reviewFiles.append((path, target, ["md", "markdown"].contains(ext)))
                } else if Self.isMediaPath(path) {
                    let target = staging.appendingPathComponent("\(UUID().uuidString)_\(filename)")
                    _ = try archive.extract(entry, to: target)
                    imageFiles.append((path, filename, target))
                }
            }
        } else if ["html", "htm"].contains(url.pathExtension.lowercased()) {
            reviewFiles.append((url.lastPathComponent, url, false))
        } else if ["md", "markdown"].contains(url.pathExtension.lowercased()) {
            reviewFiles.append((url.lastPathComponent, url, true))
        } else {
            throw BackupError.unsupportedReviewImport
        }

        guard !reviewFiles.isEmpty else { throw BackupError.noReviewNotes }
        var knownReviewIDs = Set(reviews.map(\.id))
        var skippedExistingReviews = 0
        reviewFiles = try reviewFiles.filter { reviewFile in
            guard reviewFile.isMarkdown else { return true }
            let source = try String(contentsOf: reviewFile.url, encoding: .utf8)
            let note = Self.parseMarkdownReview(
                source,
                fallbackTitle: Self.reviewFallbackTitle(reviewFile.name)
            )
            guard let id = note.id, knownReviewIDs.contains(id) else { return true }
            skippedExistingReviews += 1
            return false
        }
        guard !reviewFiles.isEmpty else {
            let message = "Skipped \(skippedExistingReviews) Markdown review note(s) whose review IDs already exist."
            statusMessage = message
            return message
        }
        try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        var importedFiles: [(archivePath: String, name: String, localName: String)] = []
        for image in imageFiles {
            var localName = image.name
            var destination = mediaURL.appendingPathComponent(localName)
            if FileManager.default.fileExists(atPath: destination.path) {
                if FileManager.default.contentsEqual(atPath: image.url.path, andPath: destination.path) {
                    importedFiles.append((image.archivePath, image.name, localName))
                    continue
                }
                let ext = destination.pathExtension
                let stem = destination.deletingPathExtension().lastPathComponent
                localName = "\(stem)_\(UUID().uuidString.prefix(8))" + (ext.isEmpty ? "" : ".\(ext)")
                destination = mediaURL.appendingPathComponent(localName)
            }
            try FileManager.default.copyItem(at: image.url, to: destination)
            importedFiles.append((image.archivePath, image.name, localName))
        }

        var nextReviewNumber = (reviews.map(\.reviewNumber).max() ?? 0) + 1
        var usedReviewNumbers = Set(reviews.map(\.reviewNumber))
        var importedReviews: [Review] = []
        for reviewFile in reviewFiles {
            let source = try String(contentsOf: reviewFile.url, encoding: .utf8)
            let parsed = reviewFile.isMarkdown
                ? Self.parseMarkdownReview(source, fallbackTitle: Self.reviewFallbackTitle(reviewFile.name))
                : ImportedReviewNote(
                    id: nil,
                    reviewNumber: nil,
                    title: Self.htmlTitle(from: source) ?? Self.reviewFallbackTitle(reviewFile.name),
                    author: "Imported",
                    rating: 5,
                    productTitles: Self.suggestedProductTitles(
                        title: Self.htmlTitle(from: source) ?? reviewFile.name,
                        body: source,
                        products: products
                    ),
                    body: source
                )
            if let id = parsed.id, knownReviewIDs.contains(id) { continue }
            let proposedNumber = parsed.reviewNumber.flatMap { usedReviewNumbers.contains($0) ? nil : $0 }
            let reviewNumber = proposedNumber ?? nextReviewNumber
            usedReviewNumbers.insert(reviewNumber)
            nextReviewNumber = max(nextReviewNumber, reviewNumber + 1)
            let body: String
            if reviewFile.isMarkdown {
                body = Self.remapImportedReviewMarkdown(parsed.body, assets: importedFiles)
            } else {
                let remappedHTML = Self.remapImportedReviewHTML(parsed.body, assets: importedFiles)
                body = Self.cleanImportedReviewHTML(remappedHTML, title: parsed.title)
            }
            let matchedProducts = products.filter { product in
                parsed.productTitles.contains { $0.caseInsensitiveCompare(product.name) == .orderedSame } ||
                    (parsed.productTitles.isEmpty && product.name.caseInsensitiveCompare(parsed.title) == .orderedSame)
            }
            let id = parsed.id ?? ("rev_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(17))
            knownReviewIDs.insert(id)
            importedReviews.append(Review(
                id: id,
                reviewNumber: reviewNumber,
                title: parsed.title,
                body: body,
                bodyFormat: reviewFile.isMarkdown ? "markdown" : nil,
                authorName: parsed.author,
                rating: parsed.rating,
                productIds: matchedProducts.map(\.id),
                productTitles: matchedProducts.map(\.name).isEmpty ? parsed.productTitles : matchedProducts.map(\.name),
                pictures: Self.reviewImageAttachments(in: body),
                createdTime: ISO8601DateFormatter().string(from: Date())
            ))
        }

        reviews.insert(contentsOf: importedReviews.reversed(), at: 0)
        let skipped = skippedExistingReviews + reviewFiles.count - importedReviews.count
        statusMessage = "Imported \(importedReviews.count) review note\(importedReviews.count == 1 ? "" : "s")." +
            (skipped > 0 ? " Skipped \(skipped) note(s) whose review IDs already exist." : "")
        return statusMessage ?? "Imported \(importedReviews.count) review notes."
    }

    func displayableReviewHTML(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(src\s*=\s*["'])app-media://([^"']+)(["'])"#) else {
            return html
        }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        var result = html
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let filenameRange = Range(match.range(at: 2), in: result),
                  let prefixRange = Range(match.range(at: 1), in: result),
                  let suffixRange = Range(match.range(at: 3), in: result) else { continue }
            let filename = String(html[filenameRange])
            let encodedName = filename.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? filename
            result.replaceSubrange(
                fullRange,
                with: String(result[prefixRange]) + "app-media://\(encodedName)" + String(result[suffixRange])
            )
        }
        guard let remoteImageRegex = try? NSRegularExpression(
            pattern: #"(?i)(<img\b[^>]*?)\s+src\s*=\s*(["'])(?:https?:)?//[^"']*\2([^>]*>)"#
        ) else { return result }
        return remoteImageRegex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1$3"
        )
    }

    func displayableReviewMarkdown(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: #"(?is)<img\b[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    func makeBackup() throws -> URL {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("ProductCompare_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let reviewNotes = staging.appendingPathComponent("reviews", isDirectory: true)
        try FileManager.default.createDirectory(at: reviewNotes, withIntermediateDirectories: true)
        let media = staging.appendingPathComponent("review_images", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let database = makeDatabaseBackup()
        try encoder.encode(database).write(to: staging.appendingPathComponent("database.json"))
        for (index, review) in reviews.enumerated() {
            let title = review.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let displayTitle = title.isEmpty ? "Review #\(review.reviewNumber)" : title
            let filenameTitle = Self.filenameSlug(displayTitle)
            let filename = "review_\(review.reviewNumber)_\(filenameTitle.isEmpty ? String(index + 1) : filenameTitle).md"
            let linkedProducts = review.productTitles.isEmpty ? "None" : review.productTitles.joined(separator: ", ")
            let body = Self.archiveCompatibleReviewBody(review.body)
            let note = """
            # Review #\(review.reviewNumber): \(displayTitle)

            - **Author:** \(review.authorName ?? "Verified Reviewer")
            - **Rating:** \(review.rating ?? 0) / 5
            - **Linked Products:** \(linkedProducts)
            - **Review ID:** `\(review.id)`

            ---

            ## Notes & Review Content

            \(body)
            """
            try note.write(to: reviewNotes.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        }
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
        let archive = try Archive(url: archiveURL, accessMode: .create)
        for name in ["database.json", "manifest.json"] {
            let file = staging.appendingPathComponent(name)
            try archive.addEntry(with: name, fileURL: file, compressionMethod: .deflate)
        }
        for file in try FileManager.default.contentsOfDirectory(at: reviewNotes, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            try archive.addEntry(with: "reviews/\(file.lastPathComponent)", fileURL: file, compressionMethod: .deflate)
        }
        let mediaFiles = (try? FileManager.default.contentsOfDirectory(at: media, includingPropertiesForKeys: nil)) ?? []
        for file in mediaFiles {
            for folder in ["images", "pictures", "review_images"] {
                try archive.addEntry(with: "\(folder)/\(file.lastPathComponent)", fileURL: file, compressionMethod: .deflate)
            }
        }
        return archiveURL
    }

    func makeJSONBackup() throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = documentsURL.appendingPathComponent("ProductCompare_Backup_\(Int(Date().timeIntervalSince1970)).json")
        try encoder.encode(makeDatabaseBackup()).write(to: url, options: .atomic)
        return url
    }

    func clearAllData() throws {
        if FileManager.default.fileExists(atPath: mediaURL.path) {
            try FileManager.default.removeItem(at: mediaURL)
        }
        isRestoring = true
        products = []
        specifications = []
        reviews = []
        users = []
        comparedProductIDs = []
        comparedProductOrder = []
        isRestoring = false
        persist()
        statusMessage = "All catalog data and local media were cleared."
    }

    func removeOrphanedMedia() throws -> Int {
        guard FileManager.default.fileExists(atPath: mediaURL.path) else { return 0 }
        let files = try FileManager.default.contentsOfDirectory(at: mediaURL, includingPropertiesForKeys: nil)
        var referenced = Set<String>()
        let attachments = products.flatMap(\.pictures) + specifications.flatMap(\.pictures) + reviews.flatMap(\.pictures)
        for attachment in attachments {
            if let url = localURL(for: attachment) {
                referenced.insert(url.standardizedFileURL.path)
            }
        }
        for review in reviews {
            for filename in Self.localMediaFilenames(in: review.body) {
                referenced.insert(mediaURL.appendingPathComponent(filename).standardizedFileURL.path)
            }
        }
        let orphaned = files.filter { !referenced.contains($0.standardizedFileURL.path) }
        for file in orphaned {
            try FileManager.default.removeItem(at: file)
        }
        return orphaned.count
    }

    private func makeDatabaseBackup() -> DatabaseBackup {
        DatabaseBackup(
            shareId: "",
            baseId: "",
            sourceUrl: "local",
            lastSynced: ISO8601DateFormatter().string(from: Date()),
            products: products.map { product in
                var product = product
                product.pictures = product.pictures.map { sanitized($0) }
                return product
            },
            specifications: specifications.map { specification in
                var specification = specification
                specification.pictures = specification.pictures.map { sanitized($0) }
                return specification
            },
            reviews: reviews.map { review in
                var review = review
                review.pictures = review.pictures.map { sanitized($0) }
                review.body = Self.archiveCompatibleReviewHTML(review.body)
                return review
            },
            users: users
        )
    }

    private func sanitized(_ attachment: MediaAttachment) -> MediaAttachment {
        var value = attachment
        if let url = localURL(for: value) { value.url = url.lastPathComponent }
        else if value.url.hasPrefix("app-media://") { value.url = value.name }
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

    private static func mediaCandidates(id: String, name: String, url: String) -> [String] {
        let decodedURL = url.removingPercentEncoding ?? url
        let urlName = URLComponents(string: decodedURL)?.path.split(separator: "/").last.map(String.init)
            ?? URL(fileURLWithPath: decodedURL).lastPathComponent
        return [id, urlName, name]
            .map { $0.removingPercentEncoding ?? $0 }
            .filter { !$0.isEmpty }
    }

    private static func mediaFolder(in url: String) -> String? {
        let path = (url.removingPercentEncoding ?? url).lowercased()
        return ["review_images", "pictures", "images", "attachments", "media", "files", "assets", "_files", "pics", "img"].first {
            path.contains("/\($0)/")
        }
    }

    private static func importedAsset(
        for source: String,
        assets: [(archivePath: String, name: String, localName: String)]
    ) -> (archivePath: String, name: String, localName: String)? {
        let decoded = source.removingPercentEncoding ?? source
        guard !decoded.lowercased().hasPrefix("http://"),
              !decoded.lowercased().hasPrefix("https://"),
              !decoded.lowercased().hasPrefix("data:") else { return nil }
        let sourcePath = URLComponents(string: decoded)?.path ?? decoded
        let normalizedPath = sourcePath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: #"^\./"#, with: "", options: .regularExpression)
            .lowercased()
        if !normalizedPath.isEmpty,
           let exactPath = assets.first(where: {
               let candidate = $0.archivePath.lowercased()
               return candidate == normalizedPath || candidate.hasSuffix("/" + normalizedPath)
           }) {
            return exactPath
        }
        let filename = URL(fileURLWithPath: sourcePath).lastPathComponent
        let sourceFolder = mediaFolder(in: sourcePath)
        if let sourceFolder,
           let folderMatch = assets.first(where: { asset in
               matchesMediaName(asset.name, candidate: filename) &&
                   (asset.archivePath.lowercased().contains("/\(sourceFolder)/") ||
                       asset.archivePath.lowercased().hasPrefix("\(sourceFolder)/"))
           }) {
            return folderMatch
        }
        return assets.first { matchesMediaName($0.name, candidate: filename) }
    }

    private static func matchesMediaName(_ filename: String, candidate: String) -> Bool {
        let name = URL(fileURLWithPath: filename).lastPathComponent.lowercased()
        let target = URL(fileURLWithPath: candidate).lastPathComponent.lowercased()
        guard !target.isEmpty else { return false }
        let nameStem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let targetStem = URL(fileURLWithPath: target).deletingPathExtension().lastPathComponent
        return name == target || name.hasPrefix(target + "_") || nameStem == targetStem
    }

    private static func htmlTitle(from html: String) -> String? {
        for tag in ["title", "h1"] {
            guard let regex = try? NSRegularExpression(pattern: "(?is)<\(tag)[^>]*>(.*?)</\(tag)>"),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            let value = String(html[range])
                .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func remapImportedReviewHTML(
        _ html: String,
        assets: [(archivePath: String, name: String, localName: String)]
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(src\s*=\s*["'])([^"']+)(["'])"#) else {
            return html
        }
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var result = html
        for match in matches.reversed() {
            let source = nsHTML.substring(with: match.range(at: 2))
            guard let asset = importedAsset(for: source, assets: assets),
                  let fullRange = Range(match.range, in: result),
                  let prefixRange = Range(match.range(at: 1), in: result),
                  let suffixRange = Range(match.range(at: 3), in: result) else { continue }
            result.replaceSubrange(fullRange, with: String(result[prefixRange]) + "app-media://\(asset.localName)" + String(result[suffixRange]))
        }
        return result
    }

    private static func reviewImageAttachments(in html: String) -> [MediaAttachment] {
        let patterns = [
            #"(?i)src\s*=\s*["']app-media://([^"']+)["']"#,
            #"!\[[^\]]*\]\(app-media://([^)]+)\)"#
        ]
        var filenames: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            for match in regex.matches(in: html, range: range) {
                guard let filenameRange = Range(match.range(at: 1), in: html) else { continue }
                let filename = String(html[filenameRange])
                if !filenames.contains(filename) { filenames.append(filename) }
            }
        }
        return filenames.map {
            MediaAttachment(id: UUID().uuidString, name: $0, url: "app-media://\($0)")
        }
    }

    private static func remapImportedReviewMarkdown(
        _ markdown: String,
        assets: [(archivePath: String, name: String, localName: String)]
    ) -> String {
        var result = remapImportedReviewHTML(markdown, assets: assets)
        guard let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) else {
            return result
        }
        let sourceText = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: sourceText.length))
        for match in matches.reversed() {
            let source = sourceText.substring(with: match.range(at: 2))
            guard let asset = importedAsset(for: source, assets: assets),
                  let altRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(fullRange, with: "![\(result[altRange])](app-media://\(asset.localName))")
        }
        return result
    }

    private static func parseMarkdownReview(_ markdown: String, fallbackTitle: String) -> ImportedReviewNote {
        func firstMatch(_ pattern: String, in text: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            return (1..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
        }
        let titleMatch = firstMatch(#"(?m)^#\s*Review\s*#(\d+)\s*:\s*(.+?)\s*$"#, in: markdown)
        let title = titleMatch?.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallbackTitle
        let reviewNumber = titleMatch?.first.flatMap(Int.init)
        let author = firstMatch(#"(?m)^-\s*\*\*Author:\*\*\s*(.+?)\s*$"#, in: markdown)?.first ?? "Imported"
        let rating = firstMatch(#"(?m)^-\s*\*\*Rating:\*\*\s*(\d+)"#, in: markdown)?.first.flatMap(Int.init) ?? 5
        let linkedText = firstMatch(#"(?m)^-\s*\*\*Linked Products:\*\*\s*(.*?)\s*$"#, in: markdown)?.first ?? ""
        let productTitles = linkedText.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let id = firstMatch(#"(?m)^-\s*\*\*Review ID:\*\*\s*`([^`]+)`"#, in: markdown)?.first
        let body: String
        if let range = markdown.range(of: "## Notes & Review Content", options: [.caseInsensitive]) {
            body = String(markdown[range.upperBound...])
                .replacingOccurrences(of: #"(?m)^\s*---\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            body = markdown
        }
        return ImportedReviewNote(
            id: id,
            reviewNumber: reviewNumber,
            title: title,
            author: author,
            rating: min(5, max(0, rating)),
            productTitles: productTitles,
            body: body
        )
    }

    private static func archiveCompatibleReviewHTML(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(src\s*=\s*["'])app-media://([^"']+)(["'])"#
        ) else { return html }
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(
            in: html,
            range: range,
            withTemplate: "$1review_images/$2$3"
        )
    }

    private static func archiveCompatibleReviewBody(_ body: String) -> String {
        let htmlCompatible = archiveCompatibleReviewHTML(body)
        guard let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(app-media://([^)]+)\)"#) else {
            return htmlCompatible
        }
        let nsBody = htmlCompatible as NSString
        let matches = regex.matches(in: htmlCompatible, range: NSRange(location: 0, length: nsBody.length))
        var result = htmlCompatible
        for match in matches.reversed() {
            guard let altRange = Range(match.range(at: 1), in: result),
                  let filenameRange = Range(match.range(at: 2), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(fullRange, with: "![\(result[altRange])](review_images/\(result[filenameRange]))")
        }
        return result
    }

    private static func filenameSlug(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func localMediaFilenames(in html: String) -> [String] {
        let patterns = [
            #"(?i)src\s*=\s*["']app-media://([^"']+)["']"#,
            #"!\[[^\]]*\]\(app-media://([^)]+)\)"#
        ]
        var filenames: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                guard let valueRange = Range(match.range(at: 1), in: html) else { continue }
                let filename = String(html[valueRange])
                if !filenames.contains(filename) { filenames.append(filename) }
            }
        }
        return filenames
    }

    private static func remapReviewHTML(
        _ html: String,
        assets: [(archivePath: String, originalName: String, localName: String)]
    ) -> (html: String, missingFilenames: [String]) {
        guard let imageRegex = try? NSRegularExpression(pattern: #"(?is)<img\b[^>]*>"#),
              let sourceRegex = try? NSRegularExpression(pattern: #"(?i)\bsrc\s*=\s*(["'])([^"']+)\1"#) else {
            return (html, [])
        }
        let nsHTML = html as NSString
        let matches = imageRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var result = html
        var missingFilenames: [String] = []
        for match in matches.reversed() {
            let originalTag = nsHTML.substring(with: match.range)
            let tagNSString = originalTag as NSString
            guard let sourceMatch = sourceRegex.firstMatch(
                in: originalTag,
                range: NSRange(location: 0, length: tagNSString.length)
            ) else { continue }
            let source = tagNSString.substring(with: sourceMatch.range(at: 2))
            guard !source.lowercased().hasPrefix("data:") else { continue }
            let filename = URLComponents(string: source.removingPercentEncoding ?? source)?.path
                .split(separator: "/").last.map(String.init)
                ?? URL(fileURLWithPath: source).lastPathComponent
            let sourceFolder = mediaFolder(in: source)
            let asset = assets.first { item in
                let folderMatches = sourceFolder.map {
                    item.archivePath.lowercased().contains("/\($0)/") ||
                        item.archivePath.lowercased().hasPrefix("\($0)/")
                } ?? false
                return matchesMediaName(item.originalName, candidate: filename) &&
                    (sourceFolder == nil || folderMatches)
            } ?? assets.first { matchesMediaName($0.originalName, candidate: filename) }
            guard let asset else {
                if !filename.isEmpty { missingFilenames.append(filename) }
                continue
            }
            guard let sourceRange = Range(sourceMatch.range, in: originalTag),
                  let fullRange = Range(match.range, in: result) else { continue }
            var remappedTag = originalTag
            remappedTag.replaceSubrange(sourceRange, with: "src=\"app-media://\(asset.localName)\"")
            result.replaceSubrange(fullRange, with: remappedTag)
        }
        return (result, missingFilenames)
    }

    enum BackupError: LocalizedError {
        case missingDatabase, archiveCreation, unsupportedReviewImport, noReviewNotes
        var errorDescription: String? {
            switch self {
            case .missingDatabase: "The ZIP does not contain database.json."
            case .archiveCreation: "Could not create the backup archive."
            case .unsupportedReviewImport: "Choose an HTML or Markdown note, or a ZIP containing review notes and image attachments."
            case .noReviewNotes: "The selected archive does not contain any supported review notes."
            }
        }
    }

    private struct ImportedReviewNote {
        let id: String?
        let reviewNumber: Int?
        let title: String
        let author: String
        let rating: Int
        let productTitles: [String]
        let body: String
    }
}
