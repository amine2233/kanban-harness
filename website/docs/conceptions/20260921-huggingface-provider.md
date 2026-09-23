---
slug: /conceptions/huggingface-provider
title: Hugging Face provider
---

:::note Design note
A step-by-step plan for adding Hugging Face Inference Providers as a free provider kind. Source: `docs/conceptions/20260921-huggingface-provider.md`.
:::

# Hugging Face as a free AI provider

Add a `huggingface` provider kind so a ticket can be drafted with an open model through
Hugging Face **Inference Providers** — every account gets free monthly credits, no card.

## Where the work is

| Side             | What changes                                                  | Size      |
| ---------------- | ------------------------------------------------------------- | --------- |
| Server (Swift)   | the kind, its factory, CLI help, one test                     | ~25 lines |
| Web (TypeScript) | label, default URL, model placeholder — the select is derived | ~6 lines  |
| Docs             | one row + a paragraph                                         |           |

The server is the real work: a provider is a `kind` in the domain plus a factory in the
registry. The web never talks to a model; it only needs to know how to describe the kind.

## Why it is small

Hugging Face's router is **OpenAI-compatible**: `POST https://router.huggingface.co/v1/chat/completions`
with `Authorization: Bearer hf_…`. AnyLanguageModel already ships `OpenAILanguageModel`
with a `.chatCompletions` variant, and the `openai` kind already streams partial drafts,
extracts JSON and reports usage through it. So the whole backend is: a new case, and a
factory that builds `OpenAILanguageModel` with a different default base URL and a required
key.

(It already works today with `kind: openai` + `base_url: https://router.huggingface.co/v1`.
A dedicated kind buys the default URL, a "free" cost line, a proper label, and a place to
document tokens and model ids.)

## Steps

Follow them in order; each one compiles and has a green test before the next.

### 1. Domain — the kind (`Sources/DashboardDomain/AIConfig.swift`)

- Add `case huggingface` to `AIProviderKind` (put it before `claudeCode`; keep the raw value
  `huggingface`, it is what `config.yaml` will contain).
- `isFree`: include `.huggingface` — drafts are billed against free credits. Users who pay
  can still set `pricing`, which wins over `isFree` (see `AssistantService.priced`).
- `requiresAPIKey`: `true` — the router refuses anonymous calls.
- `CaseIterable` means the registry test in step 2 will fail until the factory exists — that
  is the point.

### 2. Registry — the factory (`Sources/DashboardAIProviders/Providers.swift`)

Model it on the `.anthropic` entry (key required) but build the OpenAI client:

```swift
registry.register(.huggingface) { config in
    AnyLanguageModelProvider(config: config) {
        guard let key = config.apiKey else { throw AIProviderError.notConfigured("\(config.name) has no API key") }
        return OpenAILanguageModel(
            baseURL: Self.url(config.baseURL, default: "https://router.huggingface.co/v1"),
            apiKey: key, model: config.model, apiVariant: .chatCompletions)
    }
}
```

Run `swift test --filter ProvidersTests`: `standardRegistryCoversEveryKind` must be green
again, and add `.huggingface` to the kinds in `keyedVendorsWithoutAKeyAreNotConfigured`.

### 3. Test the wire shape (`Tests/DashboardAIProvidersTests/ProvidersTests.swift`)

`withStub(_:contentType:_:)` starts a local Vapor server that records the request and
answers with a fixed body. Write `huggingFaceUsesChatCompletionsWithTheToken`:

- answer: OpenAI SSE — two `data: {"object":"chat.completion.chunk", "choices":[{"delta":{"content":"…"}}]}`
  chunks whose contents concatenate to a ticket JSON, then `data: [DONE]`; content type
  `text/event-stream`.
- config: `kind: .huggingface`, `baseURL: base.absoluteString`, `apiKey: "hf_token"`.
- assert: the first snapshot has the partial title, the `.done` event parses with
  `TicketDraft.parse`, and the recorded request has `path == "/chat/completions"`,
  `headers["authorization"] == "Bearer hf_token"`, `body["model"]` = the model id.

If the Swift tests start failing in unrelated modules with nonsense (enum values printing
without a case name), the build is stale: `swift package clean`.

### 4. CLI (`Sources/DashboardCLI/Commands/AICommand.swift`)

The `--kind` help string lists the kinds; add `huggingface`. Nothing else — the option is
parsed with `AIProviderKind(rawValue:)`.

### 5. Web (`web/packages/state/src/api/aiConfigApi.ts`, `web/src/plugins/settings/AIProvidersCard.tsx`)

The kind select, the key field and the URL default are all derived from three tables:

- `AIProviderKind` union: add `'huggingface'`.
- `KIND_LABELS`: `huggingface: 'Hugging Face (Inference Providers, free credits)'`.
- `KEYED_KINDS`: add it (shows the API key field and the "no key" warning).
- `KIND_BASE_URL`: `'https://router.huggingface.co/v1'`.
- `MODEL_PLACEHOLDER` in `AIProvidersCard.tsx`: `'Qwen/Qwen2.5-7B-Instruct'`.

`pnpm typecheck` tells you if a table is missing the new key (they are `Record<AIProviderKind, …>`).
The existing `AIProvidersCard.test.tsx` keeps passing; no new web test is needed.

### 6. Docs (`website/docs/ai/providers.md`)

Add the row to the kinds table (`HF token (free)` / `free`) and a short paragraph: token
with the _Inference Providers_ permission from huggingface.co/settings/tokens, model ids are
Hub ids (`Qwen/Qwen2.5-7B-Instruct`, `meta-llama/Llama-3.1-8B-Instruct`), `:provider`
suffix pins a backend (`:groq`, `:cerebras`), and one `dashboard ai providers add hf …` line.

## Verify

1. `mise run check` — web checks + tests, Swift tests.
2. Real call: create a token, then
   `MVP_DASHBOARD_AI_PROVIDERS_HF_API_KEY=hf_… mise run cli -- ai ticket "reset password by email" --provider hf --stream`
   after `dashboard ai providers add hf --kind huggingface --model Qwen/Qwen2.5-7B-Instruct`.
3. Web: New card → ✨ Draft with AI → pick the provider; the activity panel should read
   `hf · Qwen/… · free`.

## Things you will meet

- **`AI_BAD_OUTPUT`** — small open models sometimes ignore the JSON schema. Try a larger
  model (`Qwen/Qwen2.5-72B-Instruct`) before touching the prompt.
- **HTTP 402** — free credits exhausted for the month; surfaces as `AI_PROVIDER`.
- **Model not found** — the Hub id must be one that Inference Providers serves; the router
  lists them at https://huggingface.co/models?inference_provider=all.
- Token usage: the router returns `usage` on the last chunk, so the panel shows tokens; the
  cost line stays `free` unless `pricing` is set.

## Not in scope

- Browser sign-in instead of pasting a token, and where tokens are stored: see
  [Provider sign-in](20260921-provider-sign-in.md). The pasted `hf_…` token goes through the same
  `api_key` / env var path as every other kind.

- Listing available models in the UI (would need a call to the router's `/models`).
- Hugging Face **Endpoints** (dedicated, paid) — they are OpenAI-compatible too; use
  `kind: openai` with the endpoint's URL.
- Local `transformers`/`llama.cpp` models — that is the `ollama` kind, or ALM's `LlamaLanguageModel`
  behind a new kind if wanted later.
