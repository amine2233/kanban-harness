import DashboardDomain
import Foundation

public struct DraftTicketRequest: Codable, Sendable {
    public var idea: String
    public var boardId: UUID
    public var provider: String?

    enum CodingKeys: String, CodingKey {
        case idea, provider
        case boardId = "board_id"
    }

    public init(idea: String, boardId: UUID, provider: String? = nil) {
        self.idea = idea
        self.boardId = boardId
        self.provider = provider
    }
}

public struct DraftTicketResponse: Codable, Sendable, Equatable {
    public let draft: TicketDraft
    public let provider: String
    public let model: String
    public let usage: UsageDTO

    public struct UsageDTO: Codable, Sendable, Equatable {
        public let inputTokens: Int?
        public let outputTokens: Int?
        public let costUSD: Double?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case costUSD = "cost_usd"
        }

        public init(inputTokens: Int?, outputTokens: Int?, costUSD: Double?) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.costUSD = costUSD
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(inputTokens, forKey: .inputTokens)
            try c.encode(outputTokens, forKey: .outputTokens)
            try c.encode(costUSD, forKey: .costUSD)
        }
    }

    public init(draft: TicketDraft, provider: String, model: String, usage: UsageDTO) {
        self.draft = draft
        self.provider = provider
        self.model = model
        self.usage = usage
    }
}
