import type { CardPriority } from './kanbanApi'

export interface TicketDraft {
  title: string
  description: string | null
  acceptance_criteria: string[]
  priority: CardPriority
  points: number | null
}

/** What the model has produced so far; every field may still be missing. */
export interface PartialTicketDraft {
  title?: string | null
  description?: string | null
  acceptance_criteria?: string[]
  priority?: CardPriority | null
  points?: number | null
}

export interface DraftTicketResponse {
  draft: TicketDraft
  provider: string
  model: string
  usage: { input_tokens: number | null; output_tokens: number | null; cost_usd: number | null }
}

/** The description that lands on the card: text plus criteria as a checklist. */
export function draftDescription(draft: PartialTicketDraft): string {
  const parts: string[] = []
  if (draft.description) parts.push(draft.description)
  const criteria = draft.acceptance_criteria ?? []
  if (criteria.length > 0) {
    parts.push('**Acceptance criteria**\n' + criteria.map((c) => `- [ ] ${c}`).join('\n'))
  }
  return parts.join('\n\n')
}

/** The card-form fields a draft (or partial draft) can fill; absent = leave as is. */
export interface DraftPatch {
  title?: string
  description?: string
  priority?: CardPriority
  points?: number
}

export function draftPatch(draft: PartialTicketDraft): DraftPatch {
  const description = draftDescription(draft)
  return {
    ...(draft.title ? { title: draft.title } : {}),
    ...(description ? { description } : {}),
    ...(draft.priority ? { priority: draft.priority } : {}),
    ...(draft.points !== null && draft.points !== undefined ? { points: draft.points } : {}),
  }
}
