import { describe, expect, test } from 'vitest'
import { groupCardsByColumn, neighbourColumns } from './board'
import type { Card, Column } from './kanbanApi'

const column = (id: string, position: number): Column => ({
  id,
  board_id: 'b',
  name: id,
  position,
  wip_limit: null,
  default_status: null,
})

const card = (id: string, column_id: string, position: number, card_number = 1): Card => ({
  id,
  column_id,
  board_id: 'b',
  prefix: 'task',
  card_number,
  title: id,
  description: null,
  priority: 'medium',
  status: 'todo',
  position,
  due_date: null,
  points: null,
  ai_cost: null,
  parent_id: null,
  children: { total: 0, done: 0 },
})

const columns = [column('todo', 0), column('doing', 1), column('done', 2)]

describe('groupCardsByColumn', () => {
  test('buckets cards by column sorted by position then number', () => {
    const grouped = groupCardsByColumn(columns, [
      card('c', 'todo', 1, 3),
      card('a', 'todo', 0, 1),
      card('b', 'todo', 0, 2),
      card('d', 'doing', 0),
    ])
    expect(grouped.get('todo')?.map((c) => c.id)).toEqual(['a', 'b', 'c'])
    expect(grouped.get('doing')?.map((c) => c.id)).toEqual(['d'])
    expect(grouped.get('done')).toEqual([])
  })

  test('drops cards whose column is unknown', () => {
    const grouped = groupCardsByColumn(columns, [card('x', 'ghost', 0)])
    expect([...grouped.values()].flat()).toEqual([])
  })
})

describe('neighbourColumns', () => {
  test('returns previous and next around a middle column', () => {
    const { previous, next } = neighbourColumns(columns, 'doing')
    expect(previous?.id).toBe('todo')
    expect(next?.id).toBe('done')
  })

  test('omits missing neighbours at the edges and for unknown ids', () => {
    expect(neighbourColumns(columns, 'todo').previous).toBeUndefined()
    expect(neighbourColumns(columns, 'done').next).toBeUndefined()
    expect(neighbourColumns(columns, 'nope')).toEqual({})
  })
})
