import type { CardProgress } from './boardIndex'

/** Counts `- [ ]` / `- [x]` items; null when the text has no checklist. */
export function checklistProgress(source: string | null): CardProgress | null {
  if (!source) return null
  const items = source.match(/^\s*[-*+]\s+\[( |[xX])\]/gm) ?? []
  if (items.length === 0) return null
  return { done: items.filter((item) => /\[[xX]\]/.test(item)).length, total: items.length }
}
