# Reverse-engineering Ollama → making ABB-MLX stronger, faster, lighter

_Written 2026-07-01. Ollama mechanisms from its docs/blog + public engine behavior.
ABB-MLX facts from source (commit `7522e13`). The MLX APIs cited are from the
**pinned dependency** `mlx-swift-examples` **2.29.1** in this repo's checkout, so the
port sketches target the version you already link. Sketches are illustrative, not
drop-in._

Scope (as requested): only the Ollama subsystems worth porting, plus tool calling in
depth — and only insofar as they make ABB-MLX **stronger** (features), **faster**
(throughput/latency), or **lighter** (memory). No broad reference material.

**The central discovery:** most of what you'd "reverse engineer" from Ollama is
*already implemented inside the MLX library you depend on* — you just aren't calling
the modern API. Your `MLXEngine` uses the **deprecated** callback `generate` and
manually re-decodes cumulative text. The current `generate(...) -> AsyncStream<Generation>`
gives you incremental chunks, token-accurate `usage`, **and tool calls** for free.

---

## 0. The one change that unlocks three wins — switch to the streaming `Generation` API

Today (`MLXEngine.swift`): deprecated `MLXLMCommon.generate(input:parameters:context:) { tokens in … }`,
decoding the whole token array each step; `Server.swift` then diffs by prefix-stripping.
That is O(n²) detokenization and fragile.

The pinned 2.29.1 API:

```swift
public func generate(
    input: LMInput, cache: [KVCache]? = nil,
    parameters: GenerateParameters, context: ModelContext
) throws -> AsyncStream<Generation>

public enum Generation: Sendable {
    case chunk(String)                 // incremental text (NaiveStreamingDetokenizer)
    case info(GenerateCompletionInfo)  // promptTokenCount, generationTokenCount, tokens/s
    case toolCall(ToolCall)            // parsed by an internal ToolCallProcessor
}
```

Rewriting `MLXEngine.generate` around this **simultaneously**:
- **Faster/lighter:** proper incremental detokenization instead of re-decoding + prefix-strip.
- **Stronger (correctness):** `GenerateCompletionInfo` → fill in the `usage` you currently return as `null`.
- **Stronger (feature):** `.toolCall` gives you tool calling (§1).

Sketch:

```swift
public enum Event: Sendable {
    case text(String)
    case toolCall(ToolCall)
    case done(GenerateCompletionInfo)
}

public func generateEvents(
    modelId: String, messages: [ChatMessage], tools: [ToolSpec]?,
    parameters: GenerationParameters
) -> AsyncThrowingStream<Event, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                try await load(modelId: modelId)
                guard let container else { throw EngineError.notLoaded }
                if let seed = parameters.seed { MLXRandom.seed(seed) }
                let gp = GenerateParameters(temperature: parameters.temperature, topP: parameters.topP)

                try await container.perform { ctx in
                    let userInput = UserInput(
                        messages: messages.map { ["role": $0.role.rawValue, "content": $0.content] },
                        tools: tools                       // <-- rendered by the chat template
                    )
                    let lm = try await ctx.processor.prepare(input: userInput)
                    var produced = 0
                    for await g in try MLXLMCommon.generate(
                        input: lm, parameters: gp, context: ctx
                    ) {
                        if Task.isCancelled { break }
                        switch g {
                        case .chunk(let s): continuation.yield(.text(s))
                        case .toolCall(let tc): continuation.yield(.toolCall(tc))
                        case .info(let info): continuation.yield(.done(info))
                        }
                        produced += 1
                        if produced >= parameters.maxTokens { break }   // real stop handling, §5
                    }
                }
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
```

`Server.streamChat` then stops prefix-diffing and just forwards `.text` deltas, maps
`.toolCall` to OpenAI `tool_calls` (§1), and uses `.done(info)` to emit `usage`.

---

## 1. Tool calling (in depth)

### How Ollama does it
1. Client sends OpenAI-style `tools: [{type:"function", function:{name, description, parameters(JSON Schema)}}]`.
2. Ollama renders those tool definitions **into the prompt via the model's chat
   template** (each model ships a template that knows how to present tools).
3. The model emits tool-call syntax in its output; Ollama **parses `tool_calls` out of
   the generated text** (model-specific parsing) and returns them under
   `message.tool_calls` instead of/alongside `content`.
4. The caller executes the tool and sends the result back as a `{role:"tool", ...}`
   message; the loop repeats.

### How ABB-MLX ports it — mostly already done inside MLX
- Step 2 is handled by `ctx.processor.prepare(input: UserInput(..., tools:))` — the
  tokenizer's chat template renders the tools. `ToolSpec` is just `[String: Any]`
  (from swift-transformers), i.e. the OpenAI function-schema dict passed through.
- Step 3 is handled by the `ToolCallProcessor` inside streaming `generate`, which
  yields `.toolCall(ToolCall)` where
  `ToolCall.function = (name: String, arguments: [String: JSONValue])`.
- Step 4: your `ChatRole` already has `.tool`. You just need it to carry the
  `tool_call_id`.

### The actual work (small)
1. **Extend `OpenAITypes`** to match the OpenAI tool schema:
   - `ChatRequest.tools: [ToolSpec]?` and `tool_choice` (carry tools as an
     Any-JSON value — add a small `AnyCodable`/reuse the lib's `JSONValue` — because
     your structs are strongly typed and tool schemas are arbitrary JSON).
   - `ChatMessage`: add optional `tool_calls` (assistant turn) and `tool_call_id`
     (tool turn), and allow `content` to be null on tool-call turns.
   - Response `tool_calls` shape:
     ```json
     {"id":"call_x","type":"function",
      "function":{"name":"get_weather","arguments":"{\"city\":\"Reykjavik\"}"}}
     ```
     Note OpenAI wants `arguments` as a **JSON string**; MLX gives you
     `[String: JSONValue]`, so `String(data: JSONEncoder().encode(tc.function.arguments), …)`.
2. **Pass `tools` into `UserInput`** (§0 sketch).
3. **Map `.toolCall` → OpenAI**: on the streaming path, emit a `tool_calls` delta and
   set `finish_reason:"tool_calls"`; on the sync path, put them on the message.
4. **Accept `tool`-role messages** back — already flow through as role+content; keep
   `tool_call_id` so multi-tool turns line up.

Result: **stronger** — agentic clients (and Xcode's tool use) work — with maybe ~100
lines, because the template rendering and parsing already ship in 2.29.1.

Caveat to verify empirically: tool-call *streaming* quality depends on the model's
template; test with a known-good tools model (e.g. a Qwen2.5-Instruct / Llama-3.1 MLX build).

---

## 2. Model download (stronger)

### How Ollama does it
`ollama pull` fetches an **OCI-style manifest** from its registry, then pulls content
-addressed **blobs** (weights, params, template) deduplicated by sha256, streaming
progress. `/api/pull` reports progress; `/api/blobs/:digest` manages layers.

### Don't clone the registry — adapt to the platform
Your models come from Hugging Face (`mlx-community`), not ollama.com. The right port is
**not** an OCI registry; it's a Hub snapshot download:

- Use swift-transformers' `Hub` (already transitively present) to
  `snapshot(from: repoId, matching: globs, progressHandler:)` into
  `~/.cache/huggingface/hub` — exactly where `ModelRegistry.scan()` already looks.
- Add a curated model list (mirror Ollama's "curated library" idea) — a small JSON of
  recommended `mlx-community` repos with sizes/quant.
- Surface it two ways: a menu-bar **download UI** with progress, and optionally an
  `/api/pull`-style endpoint for parity.

This closes your single biggest usability gap while staying Apple-native and reusing
your existing cache convention.

---

## 3. Keep-alive scheduler (lighter)

### How Ollama does it
A model stays resident after its last request for **`keep_alive` (default 5m)**, then a
timer fires and the runner is closed, freeing VRAM. Per-request `keep_alive` overrides
the global; `keep_alive: 0` unloads immediately; negative keeps forever.
`OLLAMA_MAX_LOADED_MODELS` (default 3) bounds concurrency.

### ABB-MLX port (trivial, single-model)
You hold exactly one text model. Add an idle timer to `MLXEngine`:

```swift
private var idleTimer: Task<Void, Never>?
private var keepAlive: Duration = .seconds(300)

private func touch() {
    idleTimer?.cancel()
    idleTimer = Task { [weak self] in
        try? await Task.sleep(for: self?.keepAlive ?? .seconds(300))
        if !Task.isCancelled { await self?.unload() }
    }
}
```

Call `touch()` at the end of each generation; honor a `keep_alive` field on
`ChatRequest` (per-request override). **Lighter:** unified memory is released when idle
instead of pinned until the next model switch. You don't need `MAX_LOADED_MODELS` —
your design is deliberately single-resident, which is itself a lightness advantage.

---

## 4. GPU cache limit — a direct faster⇄lighter knob (currently mis-set)

`MLXEngine.load` sets `MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)` — **20 MB**. That is
very aggressive; it minimizes idle memory but forces Metal to reallocate buffers
constantly during generation, which can *hurt* throughput. Ollama's new engine instead
does exact memory *measurement* and keeps working buffers.

Recommendation: make it a setting, not a constant.
- **Faster profile:** raise the cache limit (e.g. hundreds of MB) so buffers are reused.
- **Lighter profile:** keep it low + rely on the §3 keep-alive to fully release when idle.

Benchmark both on your target Macs; publish the numbers (§ comparison doc, "benchmark
honestly").

---

## 5. Cheap correctness the switch enables (stronger)

- **`usage`:** stop returning `null`. From `.done(info)` build
  `ChatUsage(prompt_tokens: info.promptTokenCount, completion_tokens: info.generationTokenCount,
  total_tokens: sum)`. Many clients (and cost meters) expect it.
- **`stop` sequences:** you accept `stop` in `ChatRequest` and ignore it. Either pass
  extra EOS tokens through the model configuration, or buffer output and cut at the
  first stop string before yielding. Small, expected behavior.

---

## 6. KV cache / prompt reuse (faster) — optional, higher effort

Streaming `generate` takes `cache: [KVCache]?`. For multi-turn chat where the new
prompt extends the previous one, reusing the KV cache avoids reprocessing the shared
prefix — the same reason Ollama keeps the runner's context warm. MLX also supports
`RotatingKVCache` and **quantized KV** (`kvBits`) for *lighter* long-context memory.

Caveats: the cache is only valid if the new prompt is a strict extension of what
produced it (same model, same prefix tokens); otherwise you must rebuild it. Worth it
for a chat/coding session with a stable system prompt; not worth it for one-shot calls.
Treat as a later optimization after §0–§5 land.

---

## Priority (mapped to your three axes)

| # | Change | Stronger | Faster | Lighter | Effort |
|---|--------|:---:|:---:|:---:|---|
| 0 | Switch to streaming `Generation` API | ✓ | ✓ | ✓ | S |
| 5 | `usage` + `stop` | ✓ | | | S |
| 1 | Tool calling | ✓✓ | | | S–M (lib does the hard part) |
| 3 | Keep-alive unload | | | ✓ | S |
| 4 | GPU cache limit as a setting | | ✓ | ✓ | S |
| 2 | Model download (Hub snapshot + UI) | ✓✓ | | | M |
| 6 | KV cache reuse | | ✓ | ✓ | M–L |

Recommended order: **0 → 5 → 1 → 3 → 4 → 2 → 6**. Items 0/5/1 are one coherent engine
rewrite that delivers the biggest "stronger + faster" jump against ABB-MLX's current
state, and 3/4 are tiny "lighter" follow-ons.

## Where Ollama stays ahead (not recommended to chase)
Structured outputs via true grammar-constrained decoding (Ollama compiles JSON Schema →
GBNF for llama.cpp). 2.29.1 has no built-in grammar sampler; a faithful port means a
custom logit processor — large effort. Pragmatic interim: inject the schema into the
prompt + validate/retry. Also: multi-platform/multi-GPU and the model registry are
Ollama's domain by design; competing there dilutes ABB-MLX's focus.
```
