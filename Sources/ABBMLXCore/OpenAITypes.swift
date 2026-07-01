import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system, user, assistant, tool
}

public struct ChatMessage: Codable, Sendable {
    public let role: ChatRole
    public let content: String
    public init(role: ChatRole, content: String) {
        self.role = role; self.content = content
    }
}

public struct ChatRequest: Codable, Sendable {
    public let model: String
    public let messages: [ChatMessage]
    public var stream: Bool?
    public var temperature: Float?
    public var top_p: Float?
    public var max_tokens: Int?
    public var stop: [String]?
    public var seed: UInt64?
    public init(model: String, messages: [ChatMessage], stream: Bool? = nil,
                temperature: Float? = nil, top_p: Float? = nil,
                max_tokens: Int? = nil, stop: [String]? = nil, seed: UInt64? = nil) {
        self.model = model; self.messages = messages; self.stream = stream
        self.temperature = temperature; self.top_p = top_p
        self.max_tokens = max_tokens; self.stop = stop; self.seed = seed
    }
}

public struct ChatChoiceMessage: Codable, Sendable {
    public let role: ChatRole
    public let content: String
    public init(role: ChatRole, content: String) {
        self.role = role; self.content = content
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
