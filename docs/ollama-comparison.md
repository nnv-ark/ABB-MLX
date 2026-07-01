# ABB-MLX vs. Ollama — Comparison

_Written 2026-07-01. ABB-MLX facts are from direct source reading (commit `7522e13`);
Ollama facts are from Ollama's official docs and blog (sources listed at the end).
This supersedes the earlier `ABB-MLX_vs_Ollama_Analysis.md`, which contained
factual errors (see "Corrections" at the end)._

---

## 1. One-line framing

- **ABB-MLX** — an 870-line Swift package: a menu-bar app that runs **one** local MLX
  text model at a time and exposes a **minimal OpenAI-compatible** HTTP API, aimed
  squarely at Xcode's Coding Intelligence panel.
- **Ollama** — a Go platform (with a C/C++ llama.cpp core) for running *many* local
  models across macOS/Linux/Windows and many GPUs, with model distribution, three
  API dialects, tools, vision, structured output, and a large client ecosystem.

They are not the same class of thing. ABB-MLX is a focused single-purpose server;
Ollama is a general-purpose local-inference platform.

---

## 2. Snapshot

| | ABB-MLX | Ollama |
|---|---|---|
| Language | Swift 6 (~870 LOC) | Go + C/C++ (llama.cpp) |
| Platforms | macOS 14+, Apple Silicon only | macOS / Linux / Windows |
| Inference backend | MLX (mlx-swift) directly | ggml/llama.cpp default; **preview MLX backend since v0.19 (~Mar 2026)** on Apple Silicon (M5-family, 32 GB+, limited archs) |
| GPU support | Apple Metal (via MLX) | Metal, NVIDIA CUDA, AMD ROCm; multi-GPU |
| Models resident | Exactly 1 (text) + 1 (embed) | Multiple, scheduler-managed |
| Model acquisition | **None** — read-only scan of `~/.cache/huggingface/hub` | `pull`/`push` from registry, Modelfile, HF, local GGUF |
| API dialects | OpenAI subset (4 routes) | Native `/api/*` + OpenAI `/v1/*` + **Anthropic `/v1/messages`** |
| Tool / function calling | Declared (`.tool` role) but **not implemented** | Yes (native + OpenAI + Anthropic), streaming |
| Vision / VLM | Filtered out | Yes |
| Structured output (JSON schema) | No | Yes (`format` param) |
| Embeddings | Yes (`/v1/embeddings`) | Yes (`/api/embed`, `/v1/embeddings`) |
| Web search | No | Yes (REST API, v0.11, Sept 2025) |
| Memory mgmt | Manual `unload()` only | Auto load/unload, keep-alive (default 5m), multi-model |
| Auth | None | API-key style via env / proxy patterns |
| Client ecosystem | Xcode + any OpenAI client | 100+ integrations |

---

## 3. API surface, endpoint by endpoint

### ABB-MLX (4 routes, all verified in `Server.swift`)
- `GET  /health` → `{status, service}`
- `GET  /v1/models` → installed HF-cache models (vision filtered out); no metadata beyond id
- `POST /v1/chat/completions` → sync JSON **and** streaming SSE (`temperature`, `top_p`,
  `max_tokens`, `seed`). Note: `stop` is accepted but **ignored**; `usage` is always `null`.
- `POST /v1/embeddings` → mean-pooled, normalized vectors

### Ollama native `/api/*`
`/api/generate`, `/api/chat` (tools, `format`, images, thinking), `/api/create`,
`/api/tags`, `/api/show`, `/api/copy`, `/api/delete`, `/api/pull`, `/api/push`,
`/api/embed`, `/api/ps`, `/api/version`, `/api/blobs/:digest` (HEAD/POST),
`/api/embeddings` (deprecated).

### Ollama OpenAI `/v1/*`
`/v1/chat/completions`, `/v1/completions`, `/v1/embeddings`, `/v1/models`,
`/v1/responses`, `/v1/images/generations` (experimental). Supports tools, vision
(base64 images), JSON mode / structured output, streaming. No logprobs.

### Ollama Anthropic (since v0.14.0)
`/v1/messages` (Anthropic Messages API) — tools, extended thinking, vision. Lets
Claude Code and other Anthropic-native tools target local models.

---

## 4. The backend/performance reality (the part that changed)

Historically the clean pitch for ABB-MLX was "native MLX vs. Ollama's llama.cpp."
That pitch is now **contested at the source**:

- Ollama's default remains ggml/llama.cpp with a Metal backend.
- **As of v0.19 (~March 30, 2026) Ollama ships a preview MLX backend** on Apple
  Silicon. It's currently limited (M5-family chips, 32 GB+ unified memory, a small
  set of model architectures), but the direction is clear: Ollama is adopting the
  exact runtime ABB-MLX is built on.
- Third-party benchmarks cited around the switch (e.g. Qwen3-Coder-30B on an M4 Pro)
  showed MLX ~130 tok/s vs. llama.cpp ~43 tok/s — a large gap that motivated the move.

**Implication for ABB-MLX:** "we use MLX and they don't" is no longer durable. The
honest, defensible advantages are now (a) MLX on *all* Apple Silicon today, not just
M5/32 GB preview, (b) zero translation layers / tiny surface, and (c) Xcode-native
onboarding. Any performance claim should be **benchmarked**, not asserted.

---

## 5. What ABB-MLX lacks vs. Ollama (gap list, in rough priority order)

1. **Model download** — the single biggest UX gap. Ollama's `pull` is one command;
   ABB-MLX requires you to pre-populate the HF cache yourself.
2. **Tool / function calling** — the schema even has a `.tool` role, but nothing
   parses `tools` or emits `tool_calls`. High leverage: unblocks agentic clients.
3. **Structured outputs** — no `format`/JSON-schema-constrained decoding.
4. **`stop` sequences + token `usage`** — both are stubs today; cheap correctness wins.
5. **Memory scheduler** — no keep-alive / auto-unload; a single manual `unload()`.
6. **Model metadata** — no parameter count, quantization, family, context length.
7. **Vision (VLM)** — deliberately filtered; needs MLXVLM.
8. **Multiple concurrent models / queuing.**

## 6. What ABB-MLX does better (honest version)

- **MLX on all Apple Silicon, now** — no M5/32 GB preview gate.
- **Minimal, auditable surface** — ~870 lines vs. a large Go+C codebase; easy to
  reason about, embed, and ship.
- **Xcode-first onboarding** — the guided "Connect to Xcode…" flow beats "point a
  generic client at localhost."
- **No daemon sprawl** — one menu-bar process, one resident model, predictable memory.

## 7. Strategic take

Don't fight Ollama on breadth — it wins platforms, models, GPUs, and ecosystem.
Compete on **focus and Apple-native depth**:

1. Close the two gaps that block real use as a coding backend: **model download** and
   **tool calling**. (Fix the `stop`/`usage` stubs while you're in there.)
2. Keep the surface tiny and the Xcode flow excellent.
3. Benchmark honestly against Ollama's MLX preview *and* its llama.cpp default on the
   same Apple Silicon, and publish real numbers.

---

## Sources
- Ollama API reference — https://docs.ollama.com/api (endpoints, tools, `format`)
- Ollama OpenAI compatibility — https://docs.ollama.com/api/openai-compatibility
- Ollama Anthropic compatibility — https://docs.ollama.com/api/anthropic-compatibility ; https://ollama.com/blog/claude
- Ollama MLX backend (preview) — https://ollama.com/blog/mlx
- Ollama Web search — https://ollama.com/blog/web-search ; https://docs.ollama.com/capabilities/web-search
- ABB-MLX: this repo, commit `7522e13` (`Sources/ABBMLXServer/Server.swift`,
  `Sources/ABBMLXCore/{MLXEngine,ModelRegistry,OpenAITypes,EmbeddingEngine}.swift`).

## Corrections to the prior `ABB-MLX_vs_Ollama_Analysis.md`
- **"AI Panza is the client"** — unsupported. The `files_extracted/` code is a
  separate "Forge" code-gen scaffold whose `OllamaClient.swift` targets Ollama
  (`:11434`), not ABB-MLX (`:8080`). Its persona/skills/"600 lines" details were
  misattributed to ABB-MLX (which is 870 lines).
- **"llama.cpp→MLX bridge"** — no such bridge. Ollama's MLX backend is a *separate*
  preview engine, not something llama.cpp bridges into.
- **Anthropic API** — the prior doc was *right* that this exists (v0.14.0); an
  intermediate correction that doubted it was itself wrong.
