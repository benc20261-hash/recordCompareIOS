import Foundation

struct MediaAttachment: Codable, Identifiable, Equatable, Sendable {
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

    init(id: String, name: String, url: String, dataUrl: String? = nil, size: Int? = nil, mimetype: String? = nil, width: Int? = nil, height: Int? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.dataUrl = dataUrl
        self.size = size
        self.mimetype = mimetype
        self.width = width
        self.height = height
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try values.decodeIfPresent(String.self, forKey: .url) ?? ""
        dataUrl = try values.decodeIfPresent(String.self, forKey: .dataUrl)
        size = try values.decodeIfPresent(Int.self, forKey: .size)
        mimetype = try values.decodeIfPresent(String.self, forKey: .mimetype)
        width = try values.decodeIfPresent(Int.self, forKey: .width)
        height = try values.decodeIfPresent(Int.self, forKey: .height)
    }
}

struct Product: Codable, Identifiable, Equatable, Sendable {
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

    init(id: String, name: String, brand: String, tags: [String], overview: String, pictures: [MediaAttachment], specificationIds: [String]? = nil, reviewIds: [String]? = nil, createdTime: String? = nil) {
        self.id = id
        self.name = name
        self.brand = brand
        self.tags = tags
        self.overview = overview
        self.pictures = pictures
        self.specificationIds = specificationIds
        self.reviewIds = reviewIds
        self.createdTime = createdTime
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        brand = try values.decodeIfPresent(String.self, forKey: .brand) ?? ""
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        overview = try values.decodeIfPresent(String.self, forKey: .overview) ?? ""
        pictures = try values.decodeIfPresent([MediaAttachment].self, forKey: .pictures) ?? []
        specificationIds = try values.decodeIfPresent([String].self, forKey: .specificationIds)
        reviewIds = try values.decodeIfPresent([String].self, forKey: .reviewIds)
        createdTime = try values.decodeIfPresent(String.self, forKey: .createdTime)
    }
}

struct Specification: Codable, Identifiable, Equatable, Sendable {
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

    init(id: String, specName: String, details: String, order: Int, productId: String, productTitle: String? = nil, unit: String? = nil, pictures: [MediaAttachment] = [], isNumeric: Bool? = nil) {
        self.id = id
        self.specName = specName
        self.details = details
        self.order = order
        self.productId = productId
        self.productTitle = productTitle
        self.unit = unit
        self.pictures = pictures
        self.isNumeric = isNumeric
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        specName = try values.decodeIfPresent(String.self, forKey: .specName) ?? ""
        details = try values.decodeIfPresent(String.self, forKey: .details) ?? ""
        order = try values.decodeIfPresent(Int.self, forKey: .order) ?? 0
        productId = try values.decodeIfPresent(String.self, forKey: .productId) ?? ""
        productTitle = try values.decodeIfPresent(String.self, forKey: .productTitle)
        unit = try values.decodeIfPresent(String.self, forKey: .unit)
        pictures = try values.decodeIfPresent([MediaAttachment].self, forKey: .pictures) ?? []
        isNumeric = try values.decodeIfPresent(Bool.self, forKey: .isNumeric)
    }
}

func specificationNameKey(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

func specificationBelongs(_ specification: Specification, to product: Product) -> Bool {
    specification.productId == product.id ||
        (specification.productTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(product.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame)
}

func orderedSpecificationNames(for products: [Product], specifications: [Specification]) -> [String] {
    var names: [String] = []
    var seen = Set<String>()
    for product in products {
        let ordered = specifications.enumerated()
            .filter { specificationBelongs($0.element, to: product) }
            .sorted {
                $0.element.order == $1.element.order
                    ? $0.offset < $1.offset
                    : $0.element.order < $1.element.order
            }
        for (_, specification) in ordered {
            let name = specification.specName.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = specificationNameKey(name)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            names.append(name)
        }
    }
    return names
}

struct Review: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var reviewNumber: Int
    var title: String?
    var body: String
    var bodyFormat: String?
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
        case id, reviewNumber, title, body, bodyFormat, pros, cons, authorName, authorAvatar, rating, productId, productIds, productTitles, pictures, createdTime
    }

    init(id: String, reviewNumber: Int, title: String? = nil, body: String, bodyFormat: String? = nil, pros: [String]? = nil, cons: [String]? = nil, authorName: String? = nil, authorAvatar: String? = nil, rating: Int? = nil, productId: String? = nil, productIds: [String], productTitles: [String], pictures: [MediaAttachment], createdTime: String? = nil) {
        self.id = id
        self.reviewNumber = reviewNumber
        self.title = title
        self.body = body
        self.bodyFormat = bodyFormat
        self.pros = pros
        self.cons = cons
        self.authorName = authorName
        self.authorAvatar = authorAvatar
        self.rating = rating
        self.productId = productId
        self.productIds = productIds
        self.productTitles = productTitles
        self.pictures = pictures
        self.createdTime = createdTime
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        reviewNumber = try values.decodeIfPresent(Int.self, forKey: .reviewNumber) ?? 0
        title = try values.decodeIfPresent(String.self, forKey: .title)
        body = try values.decodeIfPresent(String.self, forKey: .body) ?? ""
        bodyFormat = try values.decodeIfPresent(String.self, forKey: .bodyFormat)
        pros = try values.decodeIfPresent([String].self, forKey: .pros)
        cons = try values.decodeIfPresent([String].self, forKey: .cons)
        authorName = try values.decodeIfPresent(String.self, forKey: .authorName)
        authorAvatar = try values.decodeIfPresent(String.self, forKey: .authorAvatar)
        rating = try values.decodeIfPresent(Int.self, forKey: .rating)
        productId = try values.decodeIfPresent(String.self, forKey: .productId)
        productIds = try values.decodeIfPresent([String].self, forKey: .productIds) ?? productId.map { [$0] } ?? []
        productTitles = try values.decodeIfPresent([String].self, forKey: .productTitles) ?? []
        pictures = try values.decodeIfPresent([MediaAttachment].self, forKey: .pictures) ?? []
        createdTime = try values.decodeIfPresent(String.self, forKey: .createdTime)
    }
}

struct User: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var email: String
    var role: String

    enum CodingKeys: String, CodingKey {
        case id, name, email, role
    }

    init(id: String, name: String, email: String, role: String) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try values.decodeIfPresent(String.self, forKey: .email) ?? ""
        role = try values.decodeIfPresent(String.self, forKey: .role) ?? ""
    }
}

struct DatabaseBackup: Codable, Sendable {
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

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        shareId = try values.decodeIfPresent(String.self, forKey: .shareId)
        baseId = try values.decodeIfPresent(String.self, forKey: .baseId)
        sourceUrl = try values.decodeIfPresent(String.self, forKey: .sourceUrl) ?? "local"
        lastSynced = try values.decodeIfPresent(String.self, forKey: .lastSynced)
        lastPushed = try values.decodeIfPresent(String.self, forKey: .lastPushed)
        products = try values.decodeIfPresent([Product].self, forKey: .products) ?? []
        specifications = try values.decodeIfPresent([Specification].self, forKey: .specifications) ?? []
        reviews = try values.decodeIfPresent([Review].self, forKey: .reviews) ?? []
        users = try values.decodeIfPresent([User].self, forKey: .users) ?? []
    }
}

struct ManifestFile: Codable, Sendable {
    var appName: String
    var exportDate: String
    var productCount: Int
    var specificationCount: Int
    var reviewCount: Int
    var userCount: Int
    var pictureCount: Int
    var version: String
}
