import { expect, test } from 'vitest'
import { buildBoardIndex } from './boardIndex'
import type { Card, Column } from './types'

const columns: Column[] = [
  { id: 'todo', board_id: 'b', name: 'To do', position: 0, wip_limit: null, default_status: null },
  { id: 'done', board_id: 'b', name: 'Done', position: 1, wip_limit: null, default_status: 'done' },
]
const card = (id: string, column_id: string, extra: Partial<Card> = {}): Card => ({
  id,
  column_id,
  board_id: 'b',
  prefix: 'task',
  card_number: Number(id.replace(/\D/g, '')),
  title: id,
  description: null,
  priority: 'medium',
  status: column_id === 'done' ? 'done' : 'todo',
  position: 0,
  due_date: null,
  points: null,
  ai_cost: null,
  parent_id: null,
  children: { total: 0, done: 0 },
  ...extra,
})

test('the index answers hierarchy, names, colours and progress from one pass', () => {
  const parent = card('c1', 'todo', { description: '- [x] a\n- [ ] b' })
  const one = card('c2', 'done', { parent_id: 'c1' })
  const two = card('c3', 'todo', { parent_id: 'c1' })
  const orphan = card('c4', 'todo', { parent_id: 'missing' })
  const index = buildBoardIndex([two, one, parent, orphan], columns)

  expect(index.byId('c2')).toBe(one)
  expect(index.columnName('done')).toBe('Done')
  expect(index.columnName('nope')).toBe('?')
  expect(index.parentOf(one)).toBe(parent)
  expect(index.parentOf(orphan)).toBeUndefined()
  expect(index.childrenOf(parent).map((c) => c.id)).toEqual(['c2', 'c3'])
  expect(index.progress(parent)).toEqual({ done: 1, total: 2 })
  expect(index.progress(one)).toEqual({ done: 0, total: 0 })
  expect(index.checklist(parent)).toEqual({ done: 1, total: 2 })
  expect(index.checklist(one)).toBeNull()
  expect(index.color(one)).toBe(index.color(parent))
})
