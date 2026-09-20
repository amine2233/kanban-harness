---
title: Providers
---

# AI providers

A provider is a configured model the assistant can draft with. Several can coexist; one is
the default and any draft can pick another.

| Kind          | Backed by                                                                | Needs              | Cost reported |
| ------------- | ------------------------------------------------------------------------ | ------------------ | ------------- |
| `claude_code` | Claude Code CLI in headless mode (`claude -p`), streaming partial output | `claude` logged in | yes, exact    |
| `apple`       | Apple's on-device model (`SystemLanguageModel`)                          | macOS 26           | free          |
| `anthropic`   | Anthropic Messages API                                                   | API key            | from pricing  |
| `openai`      | Any OpenAI-compatible `/v1` endpoint — OpenAI, Mistral, Groq, LM Studio… | API key (or none)  | from pricing  |
| `gemini`      | Google Gemini                                                            | API key            | from pricing  |
| `ollama`      | Local Ollama (`http://127.0.0.1:11434` by default)                       | Ollama running     | free          |

Everything but `claude_code` goes through
[AnyLanguageModel](https://github.com/mattt/AnyLanguageModel); adding a vendor is one line
in `AIProviderRegistry.standard`. `claude_code` is our own: it runs your Claude Code
installation, so your Claude subscription pays, no API key is involved, and the cost it
reports is the real one.

## Adding one

Settings → **AI providers** → _Add provider_, or:

```bash
dashboard ai providers add cc    --kind claude_code --model sonnet --name "Claude Code"
dashboard ai providers add apple --kind apple       --model system --name "Apple Intelligence"
dashboard ai providers add local --kind ollama      --model llama3.2
dashboard ai providers add claude --kind anthropic  --model claude-sonnet-5 \
    --input-price 3 --output-price 15         # key: MVP_DASHBOARD_AI_PROVIDERS_CLAUDE_API_KEY
dashboard ai providers default cc
```

Fields: `id` (a-z, 0-9, `_`), `kind`, `name`, `model`, optional `base_url`, `api_key`,
`max_tokens`, `pricing`. All of it lands in `config.yaml` — see
[Configuration](../server/configuration).

## Which one to use

- **Claude Code** — best drafts, exact cost, no key; ~6 s per ticket, a few cents.
- **Apple Intelligence** — free, private, ~4–7 s; terser drafts, points on its own scale.
  Good default for a personal board.
- **Ollama** — free and private with any local model; quality depends on the model.
- **API vendors** — when you already have keys; set pricing to see costs.

Provider settings apply live: the next draft uses the new configuration.

## How a provider streams

Every provider implements one contract — `stream(request) → text / snapshot / usage / done`
— and the assistant turns it into stages, partial drafts and a validated result. Details in
[Streaming and cost](streaming-and-cost).
