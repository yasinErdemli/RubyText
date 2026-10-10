# Readings by meaning with a language model

A dictionary reads 辛い, 人気 or 金 the same way in every sentence. With
`.rubyModelReadings()`, a language model reads them from context: 辛い is
からい for spicy food and つらい for a hard parting, 人気 is にんき for
popularity and ひとけ for people around.

## Contents

- [How it works](#how-it-works)
- [Apple's models](#apples-models)
- [Another provider](#another-provider): Claude, and OpenAI-compatible APIs
- [Keys and privacy](#keys-and-privacy)

## How it works

```swift
RubyText(text)
    .rubyModelReadings()                       // Apple's on-device model
RubyText(longText)
    .rubyModelReadings(updates: .asAnswered)   // each reading changes as it's answered
```

- Text first shows the dictionary's readings; the model's replace them
  when it answers, all together by default.
- Only words on a built-in list of 64 are asked about, and the model only
  chooses among that list's readings, with a schema (guided generation). It
  says in a few words what the word means, then chooses, seeing the
  sentences around it.
- Readings you give in markup or segments are never changed.
- Where the model isn't available or fails, the dictionary's readings stay.
  Nothing is thrown, so no error handling is needed.
- On device it takes about a second per word on a recent iPhone, so call
  `RubyModelReadings.prewarm()` when a screen that will use it appears:

```swift
.task { RubyModelReadings.prewarm() }
```

To see which readings the model chose while developing, color them:
`.rubyWordColors(.readingSources([.model: .green]))`.

## Apple's models

- `SystemLanguageModel.default`, the default: on device, private, offline
  and free, where Apple Intelligence is on. Check
  `SystemLanguageModel.default.isAvailable` if the interface should say
  whether it's in use.
- `PrivateCloudComputeLanguageModel()`: Apple's larger model, only for apps
  with the `com.apple.developer.private-cloud-compute` entitlement. Without
  it, the system stops the app as soon as the model is asked. Don't try to
  work around the entitlement.

```swift
RubyText(text)
    .rubyModelReadings(model: PrivateCloudComputeLanguageModel())
```

## Another provider

`model:` takes any FoundationModels `LanguageModel`, so a model from another
provider works once it conforms. It must declare `.guidedGeneration` and
honor the request's schema, which becomes the provider's structured output.

Two details providers trip over:

- **Property order.** RubyText's schema asks for a reason before the
  meaning, and models write properties in the order they're given.
  FoundationModels lists that order in `x-order`; write the schema with its
  properties in that order. Some providers' validators reject `x-` keys, so
  leave them out.
- **No temperature.** Recent Claude models and reasoning models reject
  `temperature`; the request's sampling is greedy, but don't send it.

### Shared pieces

```swift
import Foundation
import FoundationModels

/// The instructions and messages of a FoundationModels transcript, as chat
/// APIs take them.
nonisolated struct ProviderConversation {
    var instructions = ""
    var messages: [(role: String, content: String)] = []

    init(_ transcript: Transcript) {
        for entry in transcript {
            switch entry {
            case .instructions(let instructions):
                self.instructions += Self.text(of: instructions.segments)
            case .prompt(let prompt):
                messages.append(("user", Self.text(of: prompt.segments)))
            case .response(let response):
                messages.append(("assistant", Self.text(of: response.segments)))
            default:
                // RubyText doesn't give models tools.
                break
            }
        }
    }

    private static func text(of segments: [Transcript.Segment]) -> String {
        segments.map { (segment: Transcript.Segment) -> String in
            switch segment {
            case .text(let text): text.content
            case .structure(let structure): structure.content.jsonString
            default: ""
            }
        }.joined()
    }
}

/// JSON for providers' APIs.
nonisolated enum ProviderJSON {
    /// `schema` as a JSON Schema object for a provider's structured output.
    static func object(for schema: GenerationSchema) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(schema))
    }

    /// `value`, made of JSONSerialization's types, as JSON, with each
    /// schema's properties in the order `x-order` lists, and keys starting
    /// with `x-` left out.
    static func data(_ value: Any) throws -> Data {
        Data(try text(value, order: nil).utf8)
    }

    private static func text(_ value: Any, order: [String]?) throws -> String {
        switch value {
        case let object as [String: Any]:
            let keys = object.keys.filter { !$0.hasPrefix("x-") }
            let first = (order ?? []).filter(keys.contains)
            let rest = keys.filter { !first.contains($0) }.sorted()
            let propertyOrder = object["x-order"] as? [String]
            let members = try (first + rest).map { key in
                try text(key, order: nil) + ":" + text(object[key]!, order: key == "properties" ? propertyOrder : nil)
            }
            return "{" + members.joined(separator: ",") + "}"
        case let array as [Any]:
            return "[" + (try array.map { try text($0, order: nil) }).joined(separator: ",") + "]"
        default:
            return String(decoding: try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed), as: UTF8.self)
        }
    }
}

/// A provider's API refused a request.
nonisolated struct ProviderError: LocalizedError {
    let status: Int
    let message: String

    var errorDescription: String? { "\(status): \(message)" }

    static func check(_ response: URLResponse, _ data: Data) throws {
        guard let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) else { return }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = (json?["error"] as? [String: Any])?["message"] as? String
            ?? String(decoding: data, as: UTF8.self)
        if response.statusCode == 429 {
            throw LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: message))
        }
        throw ProviderError(status: response.statusCode, message: message)
    }
}
```

### Claude

Anthropic's Messages API, with the schema as structured output:

```swift
/// Claude as a FoundationModels `LanguageModel`:
///
///     RubyText(text)
///         .rubyModelReadings(model: ClaudeModel(name: "claude-haiku-5-5", apiKey: apiKey))
nonisolated struct ClaudeModel: LanguageModel {
    typealias Executor = ClaudeExecutor

    var name: String
    var apiKey: String
    var endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration])
    }

    var executorConfiguration: ClaudeExecutor.Configuration {
        ClaudeExecutor.Configuration(name: name, apiKey: apiKey, endpoint: endpoint)
    }
}

nonisolated struct ClaudeExecutor: LanguageModelExecutor {
    struct Configuration: Hashable, Sendable {
        var name: String
        var apiKey: String
        var endpoint: URL
    }

    typealias Model = ClaudeModel

    let configuration: Configuration

    init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    nonisolated(nonsending) func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: ClaudeModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let conversation = ProviderConversation(request.transcript)
        var body: [String: Any] = [
            "model": configuration.name,
            "max_tokens": request.generationOptions.maximumResponseTokens ?? 1024,
            "messages": conversation.messages.map { ["role": $0.role, "content": $0.content] },
        ]
        if !conversation.instructions.isEmpty {
            body["system"] = conversation.instructions
        }
        if let schema = request.schema {
            body["output_config"] = ["format": ["type": "json_schema", "schema": try ProviderJSON.object(for: schema)]]
        }

        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try ProviderJSON.data(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try ProviderError.check(response, data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = (json?["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        let tokens = (json?["usage"] as? [String: Any])?["output_tokens"] as? Int ?? 0
        await channel.send(.response(action: .appendText(text, tokenCount: tokens)))
    }
}
```

Claude Haiku 5.5 read all 96 words of RubyText Demo's model benchmark right.

### OpenAI-compatible APIs

OpenAI's Chat Completions API, which Gemini, OpenRouter, Ollama, LM Studio
and many others also offer. The model is the same shape as `ClaudeModel`,
with a `baseURL` such as `https://api.openai.com/v1` (or
`http://localhost:11434/v1` for Ollama) and an optional key:

```swift
nonisolated struct OpenAICompatibleModel: LanguageModel {
    typealias Executor = OpenAICompatibleExecutor

    var baseURL: URL
    var name: String
    var apiKey: String  // empty for local servers

    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration])
    }

    var executorConfiguration: OpenAICompatibleExecutor.Configuration {
        OpenAICompatibleExecutor.Configuration(baseURL: baseURL, name: name, apiKey: apiKey)
    }
}

nonisolated struct OpenAICompatibleExecutor: LanguageModelExecutor {
    struct Configuration: Hashable, Sendable {
        var baseURL: URL
        var name: String
        var apiKey: String
    }

    typealias Model = OpenAICompatibleModel

    let configuration: Configuration

    init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    nonisolated(nonsending) func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: OpenAICompatibleModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let conversation = ProviderConversation(request.transcript)
        var messages: [[String: Any]] = []
        if !conversation.instructions.isEmpty {
            messages.append(["role": "system", "content": conversation.instructions])
        }
        messages += conversation.messages.map { ["role": $0.role, "content": $0.content] }
        var body: [String: Any] = ["model": configuration.name, "messages": messages]
        if let schema = request.schema {
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": "response", "strict": true, "schema": try ProviderJSON.object(for: schema)],
            ]
        }

        var urlRequest = URLRequest(url: configuration.baseURL.appending(path: "chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        if !configuration.apiKey.isEmpty {
            urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "authorization")
        }
        urlRequest.httpBody = try ProviderJSON.data(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try ProviderError.check(response, data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = ((json?["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any]
        if let refusal = message?["refusal"] as? String {
            throw LanguageModelError.refusal(.init(explanation: refusal, debugDescription: refusal))
        }
        let text = message?["content"] as? String ?? ""
        let tokens = (json?["usage"] as? [String: Any])?["completion_tokens"] as? Int ?? 0
        await channel.send(.response(action: .appendText(text, tokenCount: tokens)))
    }
}
```

A local server must support structured outputs for the schema to hold the
model to the listed meanings.

## Keys and privacy

- An app you ship must not contain a provider's API key: anyone can extract
  it. Point the model's endpoint at your own server, which adds the key and
  forwards the request. For trying RubyText, read a key the developer
  enters at run time and keep it in the Keychain, never in source code or
  `Info.plist`.
- Models off the device receive each sentence they're asked about. Say so
  in the app's privacy disclosures, or keep to Apple's on-device model.
