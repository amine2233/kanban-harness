import { describe, expect, test } from 'vitest'
import type { Card, Column } from '@mvp/kanban-model'
import {
  cardFormReducer,
  includedSubtasks,
  initialCardForm,
  toCreateRequest,
  toPatch,
} from './cardForm'

const columns: Column[] = [
  { id: 'todo', board_id: 'b1', name: 'To do', position: 0, wip_limit: null, default_status: null },
  { id: 'done', board_id: 'b1', name: 'Done', position: 1, wip_limit: null, default_status: null },
]
const card: Card = {
  id: 'c1',
  column_id: 'todo',
  board_id: 'b1',
  prefix: 'task',
  card_number: 1,
  title: 'Existing',
  description: 'Why',
  priority: 'high',
  status: 'todo',
  position: 0,
  due_date: '2026-12-24T00:00:00Z',
  points: 3,
  ai_cost: null,
  parent_id: null,
  children: { total: 0, done: 0 },
}
const scope = { boardId: 'b1' }

describe('cardForm', () => {
  test('starts from the card, or from the column a new card lands in', () => {
    expect(initialCardForm(card, scope, columns)).toMatchObject({
      title: 'Existing',
      dueDate: '2026-12-24',
      points: '3',
      columnId: 'todo',
    })
    expect(initialCardForm(undefined, scope, columns, 'done').columnId).toBe('done')
    expect(initialCardForm(undefined, scope, columns).columnId).toBe('todo')
  })

  test('a draft patch fills only the fields it carries and ticks every sub-task', () => {
    let form = initialCardForm(undefined, scope, columns)
    form = cardFormReducer(form, { type: 'set', field: 'title', value: 'mine' })
    form = cardFormReducer(form, {
      type: 'applyDraft',
      patch: { description: 'd', subtasks: [{ title: 'One', description: null, points: 2 }] },
    })
    expect(form.title).toBe('mine')
    expect(form.description).toBe('d')
    expect(form.subtasks).toEqual([
      { key: 0, title: 'One', description: null, points: 2, include: true },
    ])
    form = cardFormReducer(form, { type: 'subtask.add' })
    form = cardFormReducer(form, { type: 'subtask.title', key: 1, value: ' Two ' })
    form = cardFormReducer(form, { type: 'subtask.include', key: 0, value: false })
    expect(includedSubtasks(form)).toEqual([{ title: 'Two', description: null, points: null }])
    form = cardFormReducer(form, { type: 'subtask.remove', key: 1 })
    expect(form.subtasks).toHaveLength(1)
  })

  test('requests: empty titles are rejected, board change beats column change', () => {
    const blank = initialCardForm(undefined, scope, columns)
    expect(toCreateRequest(blank)).toBeNull()
    const filled = cardFormReducer(blank, { type: 'set', field: 'title', value: ' New ' })
    expect(toCreateRequest(filled)).toMatchObject({
      title: 'New',
      description: null,
      columnId: 'todo',
    })

    let edit = initialCardForm(card, scope, columns)
    edit = cardFormReducer(edit, { type: 'set', field: 'columnId', value: 'done' })
    expect(toPatch(edit, card, scope)).toMatchObject({ column_id: 'done', points: 3 })
    edit = cardFormReducer(edit, { type: 'set', field: 'boardId', value: 'b2' })
    const moved = toPatch(edit, card, scope)
    expect(moved?.board_id).toBe('b2')
    expect(moved).not.toHaveProperty('column_id')
    expect(
      toPatch(cardFormReducer(edit, { type: 'set', field: 'title', value: ' ' }), card, scope),
    ).toBeNull()
  })
})
