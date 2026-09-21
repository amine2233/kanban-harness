import { render, screen } from '@testing-library/react'
import { expect, test } from 'vitest'
import { App } from './App'

test('wires every registered plugin into the sidebar and redirects to the first one', async () => {
  render(<App />)
  const links = await screen.findAllByRole('link')
  expect(links.map((l) => l.textContent)).toEqual(['Overview', 'Settings'])
  expect(await screen.findByRole('heading', { level: 1 })).toHaveTextContent('Overview')
})
