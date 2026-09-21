import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test, vi } from 'vitest'
import { Menu } from './Menu'

test('opens on the trigger, runs the item and closes', async () => {
  const rename = vi.fn()
  const remove = vi.fn()
  render(
    <>
      <p>outside</p>
      <Menu
        label="Board actions"
        items={[
          { label: 'Rename', onSelect: rename },
          { label: 'Delete', onSelect: remove, danger: true, separated: true },
          { label: 'Disabled', onSelect: vi.fn(), disabled: true },
        ]}
      />
    </>,
  )
  expect(screen.queryByRole('menu')).not.toBeInTheDocument()
  await userEvent.click(screen.getByRole('button', { name: 'Board actions' }))
  expect(screen.getByRole('menu', { name: 'Board actions' })).toBeInTheDocument()
  expect(screen.getByRole('menuitem', { name: 'Delete' })).toHaveClass('hk-dropdown-item--danger')
  expect(screen.getByRole('menuitem', { name: 'Disabled' })).toBeDisabled()

  await userEvent.click(screen.getByRole('menuitem', { name: 'Rename' }))
  expect(rename).toHaveBeenCalled()
  expect(screen.queryByRole('menu')).not.toBeInTheDocument()

  await userEvent.click(screen.getByRole('button', { name: 'Board actions' }))
  await userEvent.keyboard('{Escape}')
  expect(screen.queryByRole('menu')).not.toBeInTheDocument()

  await userEvent.click(screen.getByRole('button', { name: 'Board actions' }))
  await userEvent.click(screen.getByText('outside'))
  expect(screen.queryByRole('menu')).not.toBeInTheDocument()
  expect(remove).not.toHaveBeenCalled()
})
