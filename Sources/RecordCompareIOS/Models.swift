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

    enum CodingKeys: String, CodingKey {
        case id, name, url, dataUrl, size, mimetype, width, height
    }
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

    enum CodingKeys: String, CodingKey {
        case id, name, brand, tags, overview, pictures, specificationIds, reviewIds, createdTime
    }
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

    enum CodingKeys: String, CodingKey {
        case id, specName, details, order, productId, productTitle, unit, pictures
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

    enum CodingKeys: String, CodingKey {
        case id, reviewNumber, title, body, pros, cons, authorName, authorAvatar, rating, productId, productIds, productTitles, pictures, createdTime
    }
}

struct DatabaseBackup: Codable {
    var products: [Product]
    var specifications: [Specification]
    var reviews: [Review]
    var users: [User]
}

struct User: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var email: String
    var role: String
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
