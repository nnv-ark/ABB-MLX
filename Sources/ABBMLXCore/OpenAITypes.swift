import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system, user, assistant, tool
}

// MARK: - Arbitrary JSON (tool schemas, tool_choice)

/// A Sendable, Codable JSON value. Used to carry OpenAI tool schemas (arbitrary
/// JSON) through our strongly-typed request without losing shape, and to convert
/// them into `[String: Any]` (`ToolSpec`) for the MLX chat template.
public enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Bridge to the untyped values the MLX chat template expects.
    public var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map(\.anyValue)
        case .object(let o): return o.mapValues(\.anyValue)
        }
    }
}

// MARK: - Tool calls (OpenAI wire shape)

public struct FunctionCall: Codable, Sendable {
    public let name: String
    /// OpenAI convention: arguments is a JSON-encoded *string*.
    public let arguments: String
    public init(name: String, arguments: String) {
        self.name = name; self.arguments = arguments
    }
}

public struct ToolCallPayload: Codable, Sendable {
    public let id: String
    public let type: String           // always "function"
    public var index: Int?            // present on streaming deltas
    public let function: FunctionCall
    public init(id: String, type: String = "function",
                index: Int? = nil, function: FunctionCall) {
        self.id = id; self.type = type; self.index = index; self.function = function
    }
}

// MARK: - Chat

public struct ChatMessage: Codable, Sendable {
    public let role: ChatRole
    public let content: String?
    public var tool_calls: [ToolCallPayload]?
    public var tool_call_id: String?
    public var name: String?
    public init(role: ChatRole, content: String?,
                tool_calls: [ToolCallPayload]? = nil,
                tool_call_id: String? = nil, name: String? = nil) {
        self.role = role; self.content = content
        self.tool_calls = tool_calls; self.tool_call_id = tool_call_id; self.name = name
    }
}

public struct StreamOptions: Codable, Sendable {
    public var include_usage: Bool?
    public init(include_usage: Bool? = nil) { self.include_usage = include_usage }
}

public struct ChatRequest: Codable, Sendable {
    public let model: String
    public let messages: [ChatMessage]
    public var stream: Bool?
    public var stream_options: StreamOptions?
    public var temperature: Float?
    public var top_p: Float?
    public var max_tokens: Int?
    public var stop: [String]?
    public var seed: UInt64?
    public var tools: [JSONValue]?
    public var tool_choice: JSONValue?
    public init(model: String, messages: [ChatMessage], stream: Bool? = nil,
                stream_options: StreamOptions? = nil,
                temperature: Float? = nil, top_p: Float? = nil,
                max_tokens: Int? = nil, stop: [String]? = nil, seed: UInt64? = nil,
                tools: [JSONValue]? = nil, tool_choice: JSONValue? = nil) {
        self.model = model; self.messages = messages; self.stream = stream
        self.stream_options = stream_options
        self.temperature = temperature; self.top_p = top_p
        self.max_tokens = max_tokens; self.stop = stop; self.seed = seed
        self.tools = tools; self.tool_choice = tool_choice
    }
}

public struct ChatChoiceMessage: Codable, Sendable {
    public let role: ChatRole
    public let content: String?
    public var tool_calls: [ToolCallPayload]?
    public init(role: ChatRole, content: String?, tool_calls: [ToolCallPayload]? = nil) {
        self.role = role; self.content = content; self.tool_calls = tool_calls
    }
}

public struct ChatChoice: Codable, Sendable {
    public let index: Int
    public let message: ChatChoiceMessage?
    public let delta: ChatChoiceMessage?
    public let finish_reason: String?
    public init(index: Int, message: ChatChoiceMessage?,
                delta: ChatChoiceMessage?, finish_reason: String?) {
        self.index = index; self.message = message
        self.delta = delta; self.finish_reason = finish_reason
    }
}

public struct ChatUsage: Codable, Sendable {
    public let prompt_tokens: Int
    public let completion_tokens: Int
    public let total_tokens: Int
    public init(prompt_tokens: Int, completion_tokens: Int, total_tokens: Int) {
        self.prompt_tokens = prompt_tokens
        self.completion_tokens = completion_tokens
        self.total_tokens = total_tokens
    }
}

public struct ChatResponse: Codable, Sendable {
    public let id: String
    public let object: String
    public let created: Int
    public let model: String
    public let choices: [ChatChoice]
    public let usage: ChatUsage?
    public init(id: String, object: String, created: Int, model: String,
                choices: [ChatChoice], usage: ChatUsage?) {
        self.id = id; self.object = object; self.created = created
        self.model = model; self.choices = choices; self.usage = usage
    }
}

public struct ModelInfo: Codable, Sendable {
    public let id: String
    public let object: String
    public let created: Int
    public let owned_by: String
    public init(id: String, object: String, created: Int, owned_by: String) {
        self.id = id; self.object = object
        self.created = created; self.owned_by = owned_by
    }
}

public struct ModelsResponse: Codable, Sendable {
    public let object: String
    public let data: [ModelInfo]
    public init(object: String, data: [ModelInfo]) {
        self.object = object; self.data = data
    }
}

public struct EmbeddingRequest: Codable, Sendable {
    public let model: String
    public let input: EmbeddingInput
    public var encoding_format: String?
    public init(model: String, input: EmbeddingInput, encoding_format: String? = nil) {
        self.model = model; self.input = input; self.encoding_format = encoding_format
    }
}

public enum EmbeddingInput: Codable, Sendable {
    case single(String)
    case batch([String])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .single(s); return }
        self = .batch(try c.decode([String].self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .single(let s): try c.encode(s)
        case .batch(let a):  try c.encode(a)
        }
    }
    public var asArray: [String] {
        switch self { case .single(let s): return [s]; case .batch(let a): return a }
    }
}

public struct EmbeddingItem: Codable, Sendable {
    public let object: String
    public let index: Int
    public let embedding: [Float]
    public init(object: String, index: Int, embedding: [Float]) {
        self.object = object; self.index = index; self.embedding = embedding
    }
}

public struct EmbeddingResponse: Codable, Sendable {
    public let object: String
    public let model: String
    public let data: [EmbeddingItem]
    public let usage: ChatUsage?
    public init(object: String, model: String, data: [EmbeddingItem], usage: ChatUsage?) {
        self.object = object; self.model = model
        self.data = data; self.usage = usage
    }
}
