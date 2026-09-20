/** Flips the `[ ]` / `[x]` of the task on 1-based `line`. */
export function toggleTask(source: string, line: number): string {
  const lines = source.split('\n')
  const current = lines[line - 1]
  if (current === undefined) return source
  lines[line - 1] = /^(\s*[-*+]\s+)\[[xX]\]/.test(current)
    ? current.replace(/^(\s*[-*+]\s+)\[[xX]\]/, '$1[ ]')
    : current.replace(/^(\s*[-*+]\s+)\[ \]/, '$1[x]')
  return lines.join('\n')
}

/** Counts `- [ ]` / `- [x]` items; null when the text has no checklist. */
export function checklistProgress(source: string | null): { done: number; total: number } | null {
  if (!source) return null
  const items = source.match(/^\s*[-*+]\s+\[( |[xX])\]/gm) ?? []
  if (items.length === 0) return null
  return { done: items.filter((item) => /\[[xX]\]/.test(item)).length, total: items.length }
}
