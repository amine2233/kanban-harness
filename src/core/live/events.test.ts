import { describe, expect, test } from 'vitest'
import { eventsUrl, parseChangeEvent, tagsFor } from './events'

describe('parseChangeEvent', () => {
  test('accepts known kinds and normalises the project id', () => {
    expect(parseChangeEvent('{"kind":"hello"}')).toEqual({ kind: 'hello' })
    expect(parseChangeEvent('{"kind":"workspace_changed","project_id":"ABC-DEF"}')).toEqual({
      kind: 'workspace_changed',
      project_id: 'abc-def',
    })
  })

  test('rejects unknown kinds, missing ids and garbage', () => {
    expect(parseChangeEvent('{"kind":"nope"}')).toBeNull()
    expect(parseChangeEvent('{"kind":"workspace_changed"}')).toBeNull()
    expect(parseChangeEvent('not json')).toBeNull()
  })
})

test('tagsFor maps events to the caches they invalidate', () => {
  expect(tagsFor({ kind: 'hello' })).toEqual([])
  expect(tagsFor({ kind: 'projects_changed' })).toEqual(['Project'])
  expect(tagsFor({ kind: 'settings_changed' })).toEqual(['Settings'])
  expect(tagsFor({ kind: 'workspace_changed', project_id: 'p' })).toEqual([
    'Board',
    'Column',
    'Card',
  ])
})

test('eventsUrl swaps the scheme to ws(s)', () => {
  expect(eventsUrl('http://localhost:5173/api')).toBe('ws://localhost:5173/api/events')
  expect(eventsUrl('https://kanban.example.com/api')).toBe('wss://kanban.example.com/api/events')
})
