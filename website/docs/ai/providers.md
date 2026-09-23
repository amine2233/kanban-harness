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
| `huggingface` | Hugging Face Inference Providers router (OpenAI-compatible)              | token or sign-in   | free¹         |
| `openrouter`  | OpenRouter (OpenAI-compatible, hundreds of models, `:free` ones cost 0)  | key or sign-in     | from pricing  |

¹ Hugging Face gives every account free monthly inference credits; a draft is reported as
free unless you set `pricing`. Model ids are Hub ids (`Qwen/Qwen2.5-7B-Instruct`,
`meta-llama/Llama-3.1-8B-Instruct`…); append `:provider` (`:groq`, `:cerebras`) to pin a
backend. OpenRouter model ids look like `meta-llama/llama-3.3-70b-instruct:free`.

## Signing in instead of pasting a key

`openrouter` and `huggingface` can authenticate through the browser (OAuth 2 with PKCE):
Settings → AI providers → **Sign in** on the provider, or `dashboard ai providers login <id>`.
The vendor sends the browser back to the dashboard server's own `/api/auth/callback`; the
credential is stored in `credentials.json` (mode `0600`, next to `config.yaml`), never in the
config file, and the provider reads `key set`. **Sign out** (or `logout`) forgets it
locally; it revokes nothing at the vendor, so the key or token keeps working until you
revoke it on the vendor's site.

- **OpenRouter** needs nothing else: the exchange returns a plain API key that never expires.
- **Hugging Face** needs an OAuth app: create one at huggingface.co/settings/applications
  with redirect URI `http://127.0.0.1:5175/api/auth/callback` (your server's address) and
  scopes `openid profile inference-api`, then put its client id (and secret, if issued) in
  the provider's _OAuth app_ fields. Access tokens expire; the server renews them with the
  refresh token before a draft.

Each vendor is its own Swift module (`DashboardProviderOpenRouter`,
`DashboardProviderHuggingFace`) built on the shared `DashboardOAuth` flow — adding another
vendor with a sign-in is a new module that registers a provider factory and a
`ProviderSignIn`.

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
dashboard ai providers add router --kind openrouter --model meta-llama/llama-3.3-70b-instruct:free
dashboard ai providers login router                # opens the browser, stores the key
dashboard ai providers add hf    --kind huggingface --model Qwen/Qwen2.5-7B-Instruct \
    --oauth-client-id <client id>             # or --api-key hf_… / the env var
dashboard ai providers add claude --kind anthropic  --model claude-sonnet-5 \
    --input-price 3 --output-price 15         # key: MVP_DASHBOARD_AI_PROVIDERS_CLAUDE_API_KEY
dashboard ai providers default cc
```

Fields: `id` (a-z, 0-9, `_`), `kind`, `name`, `model`, optional `base_url`, `api_key`,
`max_tokens`, `pricing`, `oauth` (`client_id`, `client_secret`). Settings land in `config.yaml`,
secrets in `credentials.json` — see [Configuration](../server/configuration).

## Which one to use

- **Claude Code** — best drafts, exact cost, no key; ~6 s per ticket, a few cents.
- **Apple Intelligence** — free, private, ~4–7 s; terser drafts, points on its own scale.
  Good default for a personal board.
- **Ollama** — free and private with any local model; quality depends on the model.
- **API vendors** — when you already have keys; set pricing to see costs.

Provider settings apply live: the next draft uses the new configuration.

## Switching a kind off

A provider kind can be taken out of the build entirely — not hidden, not disabled at call time,
but never registered:

```bash
MVP_DASHBOARD_PROVIDERS_DISABLED=huggingface,claude_code dashboard daemon start
```

Configuring one afterwards fails with _provider kind … is disabled for this home_. Set it when
starting the daemon: it does the work and inherits the environment of whatever started it, so
putting the variable on a later command changes nothing. An unknown name is ignored rather than
failing the process.

## How a provider streams

Every provider implements one contract — `stream(request) → text / snapshot / usage / done`
— and the assistant turns it into stages, partial drafts and a validated result. Details in
[Streaming and cost](streaming-and-cost).
