import type { AICost, CardPriority } from './kanbanApi'

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

export interface Usage {
  input_tokens: number | null
  output_tokens: number | null
  cost_usd: number | null
  /** Computed from the provider's pricing rather than reported by the vendor. */
  estimated: boolean
}

export interface DraftTicketResponse {
  draft: TicketDraft
  provider: string
  model: string
  usage: Usage
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
  /** Set once the draft is final: what to stamp on the card when it is created. */
  aiCost?: AICost
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

export function costOf(result: DraftTicketResponse): AICost {
  return {
    provider: result.provider,
    model: result.model,
    input_tokens: result.usage.input_tokens,
    output_tokens: result.usage.output_tokens,
    cost_usd: result.usage.cost_usd,
    estimated: result.usage.estimated,
  }
}

/** `$0.0282`, `≈ $0.0282` when estimated, `free` for zero, `—` when unknown. */
export function formatCost(costUSD: number | null, estimated = false): string {
  if (costUSD === null) return '—'
  if (costUSD === 0) return 'free'
  return `${estimated ? '≈ ' : ''}$${costUSD.toFixed(4)}`
}

export function formatTokens(usage: { input_tokens: number | null; output_tokens: number | null }) {
  const parts = [
    usage.input_tokens !== null && `${String(usage.input_tokens)} in`,
    usage.output_tokens !== null && `${String(usage.output_tokens)} out`,
  ].filter(Boolean)
  return parts.join(' / ')
}
