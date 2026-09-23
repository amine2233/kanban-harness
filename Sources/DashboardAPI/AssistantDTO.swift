import DashboardDomain
import Foundation

public struct DraftTicketRequest: Codable, Sendable {
    public var idea: String
    public var boardId: UUID
    public var provider: String?

    enum CodingKeys: String, CodingKey {
        case idea
        case provider
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
        public let estimated: Bool

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case costUSD = "cost_usd"
            case estimated
        }

        public init(inputTokens: Int?, outputTokens: Int?, costUSD: Double?, estimated: Bool = false) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.costUSD = costUSD
            self.estimated = estimated
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens)
            self.outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens)
            self.costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD)
            self.estimated = try c.decodeIfPresent(Bool.self, forKey: .estimated) ?? false
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(inputTokens, forKey: .inputTokens)
            try c.encode(outputTokens, forKey: .outputTokens)
            try c.encode(costUSD, forKey: .costUSD)
            try c.encode(estimated, forKey: .estimated)
        }
    }

    public init(draft: TicketDraft, provider: String, model: String, usage: UsageDTO) {
        self.draft = draft
        self.provider = provider
        self.model = model
        self.usage = usage
    }
}

/// One server-sent event of a streamed draft (`Accept: text/event-stream`).
/// The `event:` name selects the `data:` shape; the JSON client and the CLI
/// share this so the frames are the contract.
public enum AssistantFrame: Sendable, Equatable {
    case stage(StageDTO)
    case text(TextDTO)
    case partial(PartialTicketDraft)
    case usage(DraftTicketResponse.UsageDTO)
    case result(DraftTicketResponse)
    case error(ApiError)

    /// `step` is one of resolve, context, wait, stream, validate, done.
    public struct StageDTO: Codable, Sendable, Equatable {
        public let step: String
        public let detail: String?
        public let elapsedMs: Int

        enum CodingKeys: String, CodingKey {
            case step
            case detail
            case elapsedMs = "elapsed_ms"
        }

        public init(step: String, detail: String?, elapsedMs: Int) {
            self.step = step
            self.detail = detail
            self.elapsedMs = elapsedMs
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(step, forKey: .step)
            try c.encode(detail, forKey: .detail)
            try c.encode(elapsedMs, forKey: .elapsedMs)
        }
    }

    public struct TextDTO: Codable, Sendable, Equatable {
        public let delta: String

        public init(delta: String) {
            self.delta = delta
        }
    }

    public var event: String {
        switch self {
        case .stage: "stage"
        case .text: "text"
        case .partial: "partial"
        case .usage: "usage"
        case .result: "result"
        case .error: "error"
        }
    }

    /// `event: …\ndata: …\n\n`, ready to write on the wire.
    public func encoded(with encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        let data = switch self {
        case let .stage(s): try encoder.encode(s)
        case let .text(t): try encoder.encode(t)
        case let .partial(p): try encoder.encode(p)
        case let .usage(u): try encoder.encode(u)
        case let .result(r): try encoder.encode(r)
        case let .error(e): try encoder.encode(e)
        }
        return Data("event: \(event)\ndata: ".utf8) + data + Data("\n\n".utf8)
    }

    /// Nil for event names this version does not know (forward compatible).
    public static func decode(
        event: String,
        data: Data,
        with decoder: JSONDecoder = JSONDecoder()
    ) throws -> AssistantFrame? {
        switch event {
        case "stage": try .stage(decoder.decode(StageDTO.self, from: data))
        case "text": try .text(decoder.decode(TextDTO.self, from: data))
        case "partial": try .partial(decoder.decode(PartialTicketDraft.self, from: data))
        case "usage": try .usage(decoder.decode(DraftTicketResponse.UsageDTO.self, from: data))
        case "result": try .result(decoder.decode(DraftTicketResponse.self, from: data))
        case "error": try .error(decoder.decode(ApiError.self, from: data))
        default: nil
        }
    }
}

/// Minimal server-sent-events reader: feed it lines, it hands back complete
/// `(event, data)` pairs. Comments and unknown fields are ignored.
public struct SSEParser: Sendable {
    private var event = "message"
    private var data: [String] = []

    public init() {}

    public mutating func feed(line: String) -> (event: String, data: Data)? {
        if line.isEmpty {
            defer { event = "message"; data = [] }
            return data.isEmpty ? nil : (event, Data(data.joined(separator: "\n").utf8))
        }
        guard !line.hasPrefix(":") else { return nil }

        let field = line.prefix { $0 != ":" }
        var value = line.dropFirst(field.count)
        if value.hasPrefix(":") { value = value.dropFirst() }
        if value.hasPrefix(" ") { value = value.dropFirst() }
        switch field {
        case "event": event = String(value)
        case "data": data.append(String(value))
        default: break
        }
        return nil
    }
}
