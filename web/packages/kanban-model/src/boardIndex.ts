import { checklistProgress } from './checklist'
import { cardColor } from './board'
import type { Card, Column } from './types'

export interface CardProgress {
  done: number
  total: number
}

/**
 * Everything the board derives from its cards, computed once per render:
 * lookups by id, the hierarchy, column names, colours and progress figures.
 */
export interface BoardIndex {
  byId: (id: string) => Card | undefined
  columnName: (columnId: string) => string
  parentOf: (card: Card) => Card | undefined
  childrenOf: (card: Card) => Card[]
  /** Sub-tasks done / total; `total` 0 when the card has none. */
  progress: (card: Card) => CardProgress
  checklist: (card: Card) => CardProgress | null
  color: (card: Card) => string
}

export function buildBoardIndex(cards: Card[], columns: Column[]): BoardIndex {
  const byId = new Map(cards.map((card) => [card.id, card]))
  const columnNames = new Map(columns.map((column) => [column.id, column.name]))
  const children = new Map<string, Card[]>()
  for (const card of cards) {
    if (card.parent_id && byId.has(card.parent_id)) {
      const list = children.get(card.parent_id) ?? []
      list.push(card)
      children.set(card.parent_id, list)
    }
  }
  for (const list of children.values()) list.sort((a, b) => a.card_number - b.card_number)
  const checklists = new Map(cards.map((card) => [card.id, checklistProgress(card.description)]))
  const parentOf = (card: Card) => (card.parent_id ? byId.get(card.parent_id) : undefined)

  return {
    byId: (id) => byId.get(id),
    columnName: (columnId) => columnNames.get(columnId) ?? '?',
    parentOf,
    childrenOf: (card) => children.get(card.id) ?? [],
    progress: (card) => {
      const list = children.get(card.id) ?? []
      return { done: list.filter((c) => c.status === 'done').length, total: list.length }
    },
    checklist: (card) => checklists.get(card.id) ?? null,
    color: (card) => cardColor(card, parentOf(card)),
  }
}
