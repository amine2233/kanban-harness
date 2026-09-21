import { baseApi } from '../api/baseApi'

export type AIProviderKind =
  | 'apple'
  | 'anthropic'
  | 'openai'
  | 'gemini'
  | 'ollama'
  | 'huggingface'
  | 'openrouter'
  | 'claude_code'

/** USD per million tokens; prices a draft when the vendor reports no cost. */
export interface AIPricing {
  input_per_million: number
  output_per_million: number
}

export interface AIProvider {
  id: string
  kind: AIProviderKind
  name: string
  model: string
  base_url: string | null
  max_tokens: number | null
  pricing: AIPricing | null
  has_api_key: boolean
  /** Client id of the OAuth app registered at the vendor; the secret never leaves the server. */
  oauth_client_id: string | null
}

export interface OAuthClientSettings {
  client_id: string
  client_secret?: string
}

export interface AIConfig {
  providers: AIProvider[]
  default_provider: string | null
}

/** `api_key`: omit to keep the stored key, empty string to clear it. */
export interface UpsertAIProvider {
  kind: AIProviderKind
  name: string
  model: string
  base_url?: string | null
  api_key?: string
  max_tokens?: number | null
  pricing?: AIPricing | null
  oauth?: OAuthClientSettings | null
}

export const KIND_LABELS: Record<AIProviderKind, string> = {
  apple: 'Apple Intelligence (on-device, macOS 26)',
  anthropic: 'Anthropic (Claude)',
  openai: 'OpenAI-compatible (OpenAI, Mistral, Groq, LM Studio…)',
  gemini: 'Google Gemini',
  ollama: 'Ollama (local)',
  huggingface: 'Hugging Face (Inference Providers, free credits)',
  openrouter: 'OpenRouter (many vendors, :free models)',
  claude_code: 'Claude Code CLI (your Claude login)',
}

/** Kinds that authenticate with an API key; the others use a local runtime or login. */
export const KEYED_KINDS: ReadonlySet<AIProviderKind> = new Set([
  'anthropic',
  'openai',
  'gemini',
  'huggingface',
  'openrouter',
])

export const KIND_BASE_URL: Record<AIProviderKind, string | null> = {
  apple: null,
  anthropic: 'https://api.anthropic.com/v1',
  openai: 'https://api.openai.com/v1',
  gemini: 'https://generativelanguage.googleapis.com/v1beta',
  ollama: 'http://127.0.0.1:11434',
  huggingface: 'https://router.huggingface.co/v1',
  openrouter: 'https://openrouter.ai/api/v1',
  claude_code: null,
}

/** Kinds with a browser sign-in; OpenRouter needs nothing, Hugging Face needs an OAuth app (client id). */
export const SIGN_IN_KINDS: ReadonlySet<AIProviderKind> = new Set(['huggingface', 'openrouter'])
export const OAUTH_APP_KINDS: ReadonlySet<AIProviderKind> = new Set(['huggingface'])

export interface SignInResponse {
  url: string
}

export const aiConfigApi = baseApi.injectEndpoints({
  endpoints: (build) => ({
    // eslint-disable-next-line @typescript-eslint/no-invalid-void-type -- RTK's no-argument query convention
    getAIConfig: build.query<AIConfig, void>({
      query: () => 'settings/ai',
      providesTags: ['AIConfig'],
    }),
    upsertAIProvider: build.mutation<AIConfig, { id: string; body: UpsertAIProvider }>({
      query: ({ id, body }) => ({ url: `settings/ai/providers/${id}`, method: 'PUT', body }),
      invalidatesTags: ['AIConfig'],
    }),
    removeAIProvider: build.mutation<AIConfig, string>({
      query: (id) => ({ url: `settings/ai/providers/${id}`, method: 'DELETE' }),
      invalidatesTags: ['AIConfig'],
    }),
    beginSignIn: build.mutation<SignInResponse, string>({
      query: (id) => ({ url: `settings/ai/providers/${id}/sign-in`, method: 'POST' }),
    }),
    signOut: build.mutation<AIConfig, string>({
      query: (id) => ({ url: `settings/ai/providers/${id}/credential`, method: 'DELETE' }),
      invalidatesTags: ['AIConfig'],
    }),
    setDefaultAIProvider: build.mutation<AIConfig, string>({
      query: (provider_id) => ({
        url: 'settings/ai/default',
        method: 'PUT',
        body: { provider_id },
      }),
      invalidatesTags: ['AIConfig'],
    }),
  }),
})

export const {
  useGetAIConfigQuery,
  useUpsertAIProviderMutation,
  useRemoveAIProviderMutation,
  useSetDefaultAIProviderMutation,
  useBeginSignInMutation,
  useSignOutMutation,
} = aiConfigApi
