import { render, screen } from '@testing-library/react'
import { expect, test } from 'vitest'
import { Button } from './Button'

test('maps variant and size to purple3 classes', () => {
  render(
    <Button variant="danger" size="sm">
      Delete
    </Button>,
  )
  const button = screen.getByRole('button', { name: 'Delete' })
  expect(button).toHaveClass('hk-button-sm--danger')
  expect(button).toHaveAttribute('type', 'button')
})
