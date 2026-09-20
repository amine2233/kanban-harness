import { baseApi } from '@/app/api'

export type AIProviderKind = 'anthropic' | 'openai_compatible' | 'ollama'

export interface AIProvider {
  id: string
  kind: AIProviderKind
  name: string
  model: string
  base_url: string | null
  max_tokens: number | null
  has_api_key: boolean
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
}

export const KIND_LABELS: Record<AIProviderKind, string> = {
  anthropic: 'Anthropic (Claude)',
  openai_compatible: 'OpenAI-compatible (OpenAI, Mistral, Groq, LM Studio…)',
  ollama: 'Ollama (local)',
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
} = aiConfigApi
