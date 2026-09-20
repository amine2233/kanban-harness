import { createSlice, type PayloadAction } from '@reduxjs/toolkit'

export type Theme = 'system' | 'light' | 'dark'
export const THEMES: Theme[] = ['system', 'light', 'dark']

export interface SettingsState {
  /** Origin of the API server (e.g. `http://127.0.0.1:5175`); empty = same origin as the page. */
  serverUrl: string
  /** `system` follows the OS; light and dark force a look. */
  theme: Theme
}

export const SETTINGS_STORAGE_KEY = 'mvp-dashboard.settings'

const defaults: SettingsState = { serverUrl: '', theme: 'system' }

/** Accepts an empty string (same origin) or an absolute http(s) URL; returns the normalised origin. */
export function normaliseServerUrl(input: string): string | null {
  const trimmed = input.trim()
  if (trimmed === '') return ''
  try {
    const url = new URL(trimmed)
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return null
    return url.origin + url.pathname.replace(/\/+$/, '')
  } catch {
    return null
  }
}

export function loadSettings(): SettingsState {
  try {
    const raw = localStorage.getItem(SETTINGS_STORAGE_KEY)
    if (!raw) return defaults
    const parsed = JSON.parse(raw) as Partial<SettingsState>
    const serverUrl =
      typeof parsed.serverUrl === 'string' ? normaliseServerUrl(parsed.serverUrl) : null
    const theme = THEMES.find((t) => t === parsed.theme) ?? 'system'
    return { ...defaults, serverUrl: serverUrl ?? '', theme }
  } catch {
    return defaults
  }
}

export function saveSettings(settings: SettingsState): void {
  try {
    localStorage.setItem(SETTINGS_STORAGE_KEY, JSON.stringify(settings))
  } catch {
    // storage unavailable (private mode, quota): settings live for the session only
  }
}

export const settingsSlice = createSlice({
  name: 'settings',
  initialState: loadSettings,
  reducers: {
    setServerUrl(state, action: PayloadAction<string>) {
      state.serverUrl = action.payload
    },
    setTheme(state, action: PayloadAction<Theme>) {
      state.theme = action.payload
    },
    resetSettings: (state) => ({ ...defaults, theme: state.theme }),
  },
  selectors: {
    selectServerUrl: (state) => state.serverUrl,
    selectTheme: (state) => state.theme,
  },
})

export const { setServerUrl, setTheme, resetSettings } = settingsSlice.actions
export const { selectServerUrl, selectTheme } = settingsSlice.selectors

/** `/api` on the configured server, or on the page's own origin. */
export function apiBaseUrl(serverUrl: string): string {
  return `${serverUrl || window.location.origin}/api`
}
