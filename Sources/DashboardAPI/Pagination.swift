/// kanban-api `Page` / `PageParams` wire shapes.
public struct Page<T: Codable & Sendable>: Codable, Sendable {
    public let items: [T]
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case page
        case pageSize = "page_size"
        case totalPages = "total_pages"
    }

    public init(items: [T], total: Int, page: Int, pageSize: Int, totalPages: Int) {
        self.items = items
        self.total = total
        self.page = page
        self.pageSize = pageSize
        self.totalPages = totalPages
    }
}

public struct PageParams: Codable, Sendable, Equatable {
    public static let defaultPageSize = 50
    public static let maxPageSize = 500

    public var page: Int?
    public var pageSize: Int?

    enum CodingKeys: String, CodingKey {
        case page
        case pageSize = "page_size"
    }

    public init(page: Int? = nil, pageSize: Int? = nil) {
        self.page = page
        self.pageSize = pageSize
    }

    public func paginate<T>(_ all: [T]) -> Page<T> {
        let size = min(max(pageSize ?? Self.defaultPageSize, 1), Self.maxPageSize)
        let totalPages = max(1, Int((Double(all.count) / Double(size)).rounded(.up)))
        let page = min(max(page ?? 1, 1), totalPages)
        let start = (page - 1) * size
        let slice = start < all.count ? Array(all[start ..< min(start + size, all.count)]) : []
        return Page(items: slice, total: all.count, page: page, pageSize: size, totalPages: totalPages)
    }
}
