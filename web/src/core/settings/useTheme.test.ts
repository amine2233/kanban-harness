import { expect, test, vi } from 'vitest'
import { applyTheme } from './useTheme'

test('the effective theme is stamped on <html>; system follows the OS preference', () => {
  applyTheme('dark')
  expect(document.documentElement.dataset.theme).toBe('dark')
  expect(document.documentElement.style.colorScheme).toBe('dark')
  vi.stubGlobal('matchMedia', () => ({
    matches: true,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  }))
  applyTheme('system')
  expect(document.documentElement.dataset.theme).toBe('dark')
  vi.stubGlobal('matchMedia', () => ({
    matches: false,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  }))
  applyTheme('system')
  expect(document.documentElement.dataset.theme).toBe('light')
  vi.unstubAllGlobals()
})
