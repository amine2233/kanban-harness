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

/** Children keyed by parent id, in card-number order; only parents present on the board count. */
export function groupChildren(cards: Card[]): Map<string, Card[]> {
  const ids = new Set(cards.map((c) => c.id))
  const grouped = new Map<string, Card[]>()
  for (const card of cards) {
    if (card.parent_id && ids.has(card.parent_id)) {
      const list = grouped.get(card.parent_id) ?? []
      list.push(card)
      grouped.set(card.parent_id, list)
    }
  }
  for (const list of grouped.values()) list.sort((a, b) => a.card_number - b.card_number)
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

/** Flat UI palette; deliberately no orange. */
export const CARD_COLORS = [
  '#1abc9c',
  '#2ecc71',
  '#3498db',
  '#9b59b6',
  '#34495e',
  '#f1c40f',
  '#e74c3c',
  '#16a085',
  '#2980b9',
  '#8e44ad',
  '#7f8c8d',
] as const

/** A stable flat colour per card family: a sub-task wears its parent's colour. */
export function cardColor(card: Card, parent?: Card): string {
  const key = (parent ?? card).id
  let hash = 0
  for (const char of key) hash = (hash * 31 + char.charCodeAt(0)) >>> 0
  return CARD_COLORS[hash % CARD_COLORS.length] ?? CARD_COLORS[0]
}
