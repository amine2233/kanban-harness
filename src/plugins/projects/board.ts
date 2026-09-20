import type { Card, Column } from './kanbanApi'

export function groupCardsByColumn(columns: Column[], cards: Card[]): Map<string, Card[]> {
  const grouped = new Map<string, Card[]>(columns.map((c) => [c.id, []]))
  for (const card of cards) {
    grouped.get(card.column_id)?.push(card)
  }
  for (const list of grouped.values()) {
    list.sort((a, b) => a.position - b.position || a.card_number - b.card_number)
  }
  return grouped
}

export function neighbourColumns(
  columns: Column[],
  columnId: string,
): { previous?: Column | undefined; next?: Column | undefined } {
  const index = columns.findIndex((c) => c.id === columnId)
  if (index === -1) return {}
  return { previous: columns[index - 1], next: columns[index + 1] }
}
