import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test, vi } from 'vitest'
import { Markdown } from './Markdown'
import { toggleTask } from './markdownTasks'

const source =
  'Why it matters\n\n**Acceptance criteria**\n- [ ] Email sent\n- [x] Link expires\n\n[docs](https://example.com)'

test('renders gfm with checklist items and safe links', async () => {
  render(<Markdown source={source} />)
  expect((await screen.findByText('Acceptance criteria')).tagName).toBe('STRONG')
  const boxes = screen.getAllByRole('checkbox')
  expect(boxes.map((b) => (b as HTMLInputElement).checked)).toEqual([false, true])
  expect(boxes[0]).toBeDisabled()
  expect(screen.getByRole('link', { name: 'docs' })).toHaveAttribute('target', '_blank')
  render(<Markdown source={'<script>alert(1)</script> plain'} />)
  await screen.findByText(/plain/)
  expect(document.querySelector('script')).toBeNull()
})

test('clicking a task hands back the toggled source', async () => {
  const onChange = vi.fn()
  render(<Markdown source={source} onChange={onChange} />)
  await userEvent.click(await screen.findByRole('checkbox', { name: 'Email sent' }))
  expect(onChange).toHaveBeenCalledWith(source.replace('- [ ] Email sent', '- [x] Email sent'))
  await userEvent.click(screen.getByRole('checkbox', { name: 'Link expires' }))
  expect(onChange).toHaveBeenLastCalledWith(
    source.replace('- [x] Link expires', '- [ ] Link expires'),
  )
})

test('toggleTask flips one line and leaves the rest alone', () => {
  expect(toggleTask('- [ ] a\n- [x] b', 2)).toBe('- [ ] a\n- [ ] b')
  expect(toggleTask('- [ ] a', 5)).toBe('- [ ] a')
})
