import { afterEach, describe, expect, test, vi } from 'vitest'
import {
  apiBaseUrl,
  loadSettings,
  normaliseServerUrl,
  saveSettings,
  SETTINGS_STORAGE_KEY,
} from './settingsSlice'
import { applyTheme } from './useTheme'

afterEach(() => {
  localStorage.clear()
})

describe('normaliseServerUrl', () => {
  test('accepts empty, http and https and strips trailing slashes', () => {
    expect(normaliseServerUrl('  ')).toBe('')
    expect(normaliseServerUrl('http://127.0.0.1:5175/')).toBe('http://127.0.0.1:5175')
    expect(normaliseServerUrl('https://kanban.example.com/base/')).toBe(
      'https://kanban.example.com/base',
    )
  })

  test('rejects other schemes and garbage', () => {
    expect(normaliseServerUrl('ftp://x')).toBeNull()
    expect(normaliseServerUrl('not a url')).toBeNull()
    expect(normaliseServerUrl('javascript:alert(1)')).toBeNull()
  })
})

describe('persistence', () => {
  test('loads defaults when nothing or garbage is stored', () => {
    expect(loadSettings()).toEqual({ serverUrl: '', theme: 'system' })
    localStorage.setItem(SETTINGS_STORAGE_KEY, '{bad json')
    expect(loadSettings()).toEqual({ serverUrl: '', theme: 'system' })
    localStorage.setItem(
      SETTINGS_STORAGE_KEY,
      JSON.stringify({ serverUrl: 'ftp://nope', theme: 'neon' }),
    )
    expect(loadSettings()).toEqual({ serverUrl: '', theme: 'system' })
  })

  test('round-trips a saved server url and theme', () => {
    saveSettings({ serverUrl: 'http://localhost:9999', theme: 'dark' })
    expect(loadSettings()).toEqual({ serverUrl: 'http://localhost:9999', theme: 'dark' })
  })

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
})

test('apiBaseUrl falls back to the page origin', () => {
  expect(apiBaseUrl('')).toBe(`${window.location.origin}/api`)
  expect(apiBaseUrl('http://10.0.0.2:5175')).toBe('http://10.0.0.2:5175/api')
})
