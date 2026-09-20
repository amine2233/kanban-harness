import { baseApi } from '@/app/api'
import type { CardPriority } from './kanbanApi'

export interface TicketDraft {
  title: string
  description: string | null
  acceptance_criteria: string[]
  priority: CardPriority
  points: number | null
}

export interface DraftTicketResponse {
  draft: TicketDraft
  provider: string
  model: string
  usage: { input_tokens: number | null; output_tokens: number | null; cost_usd: number | null }
}

/** The description that lands on the card: text plus criteria as a checklist. */
export function draftDescription(draft: TicketDraft): string {
  const parts: string[] = []
  if (draft.description) parts.push(draft.description)
  if (draft.acceptance_criteria.length > 0) {
    parts.push(
      '**Acceptance criteria**\n' + draft.acceptance_criteria.map((c) => `- [ ] ${c}`).join('\n'),
    )
  }
  return parts.join('\n\n')
}

export const assistantApi = baseApi.injectEndpoints({
  endpoints: (build) => ({
    draftTicket: build.mutation<
      DraftTicketResponse,
      { projectId: string; boardId: string; idea: string; provider?: string }
    >({
      query: ({ projectId, boardId, idea, provider }) => ({
        url: `projects/${projectId}/ai/tickets/draft`,
        method: 'POST',
        body: { idea, board_id: boardId, ...(provider ? { provider } : {}) },
      }),
    }),
  }),
})

export const { useDraftTicketMutation } = assistantApi
