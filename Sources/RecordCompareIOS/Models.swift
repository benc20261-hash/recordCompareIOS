import Foundation

struct MediaAttachment: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var url: String
    var dataUrl: String?
    var size: Int?
    var mimetype: String?
    var width: Int?
    var height: Int?
}

struct Product: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var brand: String
    var tags: [String]
    var overview: String
    var pictures: [MediaAttachment]
    var specificationIds: [String]?
    var reviewIds: [String]?
    var createdTime: String?
}

struct Specification: Codable, Identifiable, Equatable {
    var id: String
    var specName: String
    var details: String
    var order: Int
    var productId: String
    var productTitle: String?
    var unit: String?
    var pictures: [MediaAttachment]
    var isNumeric: Bool?

    enum CodingKeys: String, CodingKey {
        case id, specName, details, order, productId, productTitle, unit, pictures, isNumeric
    }
}

struct Review: Codable, Identifiable, Equatable {
    var id: String
    var reviewNumber: Int
    var title: String?
    var body: String
    var pros: [String]?
    var cons: [String]?
    var authorName: String?
    var authorAvatar: String?
    var rating: Int?
    var productId: String?
    var productIds: [String]
    var productTitles: [String]
    var pictures: [MediaAttachment]
    var createdTime: String?
}

struct User: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var email: String
    var role: String
}

struct DatabaseBackup: Codable {
    var shareId: String?
    var baseId: String?
    var sourceUrl: String?
    var lastSynced: String?
    var lastPushed: String?
    var products: [Product]
    var specifications: [Specification]
    var reviews: [Review]
    var users: [User]

    enum CodingKeys: String, CodingKey {
        case shareId, baseId, sourceUrl, lastSynced, lastPushed, products, specifications, reviews, users
    }

    init(shareId: String? = nil, baseId: String? = nil, sourceUrl: String? = "local", lastSynced: String? = nil, lastPushed: String? = nil, products: [Product], specifications: [Specification], reviews: [Review], users: [User] = []) {
        self.shareId = shareId
        self.baseId = baseId
        self.sourceUrl = sourceUrl
        self.lastSynced = lastSynced
        self.lastPushed = lastPushed
        self.products = products
        self.specifications = specifications
        self.reviews = reviews
        self.users = users
    }
}

struct ManifestFile: Codable {
    var appName: String
    var exportDate: String
    var productCount: Int
    var specificationCount: Int
    var reviewCount: Int
    var userCount: Int
    var pictureCount: Int
    var version: String
}
