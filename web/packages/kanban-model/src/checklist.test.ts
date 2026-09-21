import { expect, test } from 'vitest'
import { checklistProgress } from './checklist'

test('checklistProgress counts markdown task items', () => {
  expect(checklistProgress('Why\n- [ ] a\n- [x] b\n* [X] c')).toEqual({ done: 2, total: 3 })
  expect(checklistProgress('no list')).toBeNull()
  expect(checklistProgress(null)).toBeNull()
})
