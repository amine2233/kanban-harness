import { formatCost, formatTokens } from '@mvp/kanban-model'
import type { AssistantState } from '@mvp/state'

/** Plain-text version of the panel, for issues and support. */
export function logText(assistant: AssistantState, providerLabel: string | null): string {
  const lines = [`provider: ${providerLabel ?? '?'}`, `status: ${assistant.status}`]
  for (const s of assistant.log) {
    lines.push(
      `${String(s.elapsed_ms).padStart(6)} ms  ${s.step}${s.detail ? `: ${s.detail}` : ''}`,
    )
  }
  if (assistant.usage) {
    lines.push(
      `tokens: ${formatTokens(assistant.usage)}; cost: ${formatCost(assistant.usage.cost_usd, assistant.usage.estimated)}`,
    )
  }
  if (assistant.error) lines.push(`error ${assistant.error.code}: ${assistant.error.message}`)
  return lines.join('\n')
}
