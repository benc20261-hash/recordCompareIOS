import Foundation
import SwiftUI

final class ProductStore: ObservableObject {
    @Published var products: [Product] = []
    @Published var specifications: [Specification] = []
    @Published var reviews: [Review] = []
    @Published var selectedTab: Tab = .catalog
    @Published var searchText: String = ""
    @Published var selectedTag: String? = "All"
    @Published var comparedProductIDs: Set<String> = []

    enum Tab: String, CaseIterable {
        case catalog = "Catalog"
        case compare = "Compare"
        case smartAdd = "Smart Add"
        case reviews = "Reviews"
        case backup = "Data & Backup"
    }

    var allTags: [String] {
        let tags = products.flatMap { $0.tags }
        return Array(Set(tags)).sorted()
    }

    var filteredProducts: [Product] {
        products.filter { product in
            let matchesText = searchText.isEmpty ||
                product.name.lowercased().contains(searchText.lowercased()) ||
                product.brand.lowercased().contains(searchText.lowercased()) ||
                product.tags.joined(separator: " ").lowercased().contains(searchText.lowercased())

            let matchesTag = selectedTag == nil || selectedTag == "All" || product.tags.contains(selectedTag ?? "")
            return matchesText && matchesTag
        }
    }

    func loadIfNeeded() {
        guard products.isEmpty else { return }

        let fallbackProducts = [
            Product(
                id: "prod_1",
                name: "ROG Xbox Ally X",
                brand: "Asus",
                tags: ["asus", "xbox"],
                overview: "A gaming handheld from Asus.",
                pictures: []
            ),
            Product(
                id: "prod_2",
                name: "Plaud Note",
                brand: "Plaud",
                tags: ["Ai voice recorder", "Plaud"],
                overview: "A voice recorder using AI to summarise conversations.",
                pictures: []
            ),
            Product(
                id: "prod_3",
                name: "Amazfit Active 2",
                brand: "Amazfit",
                tags: ["Smart wear", "amazfit"],
                overview: "A smartwatch focused on training and insights.",
                pictures: []
            )
        ]

        let fallbackSpecs: [Specification] = [
            Specification(id: "spec_1", specName: "cpu", details: "Ryzen AI z2 extreme", order: 1, productId: "prod_1", productTitle: "ROG Xbox Ally X", pictures: []),
            Specification(id: "spec_2", specName: "barometer", details: "yes", order: 1, productId: "prod_3", productTitle: "Amazfit Active 2", pictures: []),
            Specification(id: "spec_3", specName: "weight", details: "30g", order: 1, productId: "prod_2", productTitle: "Plaud Note", pictures: [])
        ]

        let fallbackReviews: [Review] = [
            Review(id: "rev_1", reviewNumber: 1, title: "ROG Xbox Ally X", body: "Gaming handheld review", pros: ["Portable", "Strong performance"], cons: ["Battery may vary"], authorName: "Verified Reviewer", rating: 5, productIds: ["prod_1"], productTitles: ["ROG Xbox Ally X"], pictures: []),
            Review(id: "rev_2", reviewNumber: 2, title: "Amazfit Active 2", body: "Fitness focused review", pros: ["Great insights"], cons: ["Display smaller"], authorName: "Verified Reviewer", rating: 5, productIds: ["prod_3"], productTitles: ["Amazfit Active 2"], pictures: [])
        ]

        products = fallbackProducts
        specifications = fallbackSpecs
        reviews = fallbackReviews
    }

    func saveBackupToDocuments() {
        let backup = DatabaseBackup(products: products, specifications: specifications, reviews: reviews, users: [])
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("backup.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(backup) {
            try? data.write(to: url)
        }
    }

    func importAndroidBackup(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(DatabaseBackup.self, from: data)
            products = decoded.products
            specifications = decoded.specifications
            reviews = decoded.reviews
        } catch {
            print("Failed to import Android backup: \(error)")
        }
    }

    func exportZipArchive() -> Data? {
        let manifest = ManifestFile(
            appName: "ProductCompare",
            exportDate: ISO8601DateFormatter().string(from: Date()),
            productCount: products.count,
            specificationCount: specifications.count,
            reviewCount: reviews.count,
            userCount: 0,
            pictureCount: 0,
            version: "1.0"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let manifestData = try? encoder.encode(manifest),
              let backupData = try? encoder.encode(DatabaseBackup(products: products, specifications: specifications, reviews: reviews, users: [])) else {
            return nil
        }

        let zipData = NSMutableData()
        zipData.append(manifestData)
        zipData.append(backupData)
        return zipData as Data
    }
}

struct ProductSummary: Identifiable {
    let id: String
    let name: String
    let brand: String
    let tags: [String]
    let overview: String
    let specs: [Specification]
}
