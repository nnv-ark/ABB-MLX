# ABB-MLX

**v1.0.0 beta** — a native macOS menu-bar app that runs local LLMs on Apple
Silicon via [mlx-swift](https://github.com/ml-explore/mlx-swift) and serves
them through an OpenAI-compatible HTTP API.

ABB-MLX is built to drop into **Xcode 26's Coding Intelligence panel** as a
Localhost chat provider — no Python, no `mlx_lm.server`, no manual launch.

## Quick start

```bash
cd ABB-MLX
swift run ABBMLXApp
```

A CPU icon appears in the menu bar. Click it, pick a model that's already
in `~/.cache/huggingface/hub`, click **Start**.

## Wire to Xcode (one time)

1. Xcode → **Settings…** → **Coding Intelligence**
2. **Chat → Add a Chat Provider… → Localhost**
3. URL: `http://localhost:8080` (the menu bar app shows it; tap the URL chip to copy)
4. Name: `ABB-MLX`
5. Pick it in the chat panel.

The menu bar app has a **Connect to Xcode…** button that walks you through
this exact flow.

## What's in v1.0.0 beta

- Native MLX inference (mlx-swift + mlx-swift-examples / MLXLLM)
- Endpoints: `GET /health`, `GET /v1/models`, `POST /v1/chat/completions`
  (streaming SSE + sync), `POST /v1/embeddings`
- Persistent settings (`@AppStorage`) — port, model, auto-start
- Hides vision models from the picker (MLXVLM not in v1)
- Designed for Xcode as the primary client; works with any
  OpenAI-API-shaped client (Cursor, Continue, LM Studio importers, etc.)

## Not in this beta (roadmap)

- Tool / function calling
- Vision (VLM) chat
- Model download UI with progress
- LaunchAgent for "start at login"
- Packaged `.app` bundle + DMG

## License

Olafur Hjordisar Jonsson, 2026.
