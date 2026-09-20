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

/** A card renders at the top level unless its parent is on the board (then it nests under it). */
export function isTopLevel(card: Card, cards: Card[]): boolean {
  return !card.parent_id || !cards.some((c) => c.id === card.parent_id)
}

export function neighbourColumns(
  columns: Column[],
  columnId: string,
): { previous?: Column | undefined; next?: Column | undefined } {
  const index = columns.findIndex((c) => c.id === columnId)
  if (index === -1) return {}
  return { previous: columns[index - 1], next: columns[index + 1] }
}
