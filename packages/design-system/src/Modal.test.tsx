import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test, vi } from 'vitest'
import { ConfirmModal, Modal } from './Modal'

test('modal closes on Escape, close button and backdrop but not content clicks', async () => {
  const onClose = vi.fn()
  render(
    <Modal title="Edit" onClose={onClose}>
      <p>body</p>
    </Modal>,
  )
  expect(screen.getByRole('dialog', { name: 'Edit' })).toBeInTheDocument()
  await userEvent.click(screen.getByText('body'))
  expect(onClose).not.toHaveBeenCalled()
  await userEvent.keyboard('{Escape}')
  await userEvent.click(screen.getByRole('button', { name: 'Close' }))
  expect(onClose).toHaveBeenCalledTimes(2)
})

test('confirm modal calls onConfirm', async () => {
  const onConfirm = vi.fn()
  render(<ConfirmModal title="Delete?" message="Sure?" onConfirm={onConfirm} onClose={vi.fn()} />)
  await userEvent.click(screen.getByRole('button', { name: 'Delete' }))
  expect(onConfirm).toHaveBeenCalled()
})
