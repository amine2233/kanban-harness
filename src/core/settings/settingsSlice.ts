import { createSlice, type PayloadAction } from '@reduxjs/toolkit'

export interface SettingsState {
  /** Origin of the API server (e.g. `http://127.0.0.1:5175`); empty = same origin as the page. */
  serverUrl: string
}

export const SETTINGS_STORAGE_KEY = 'mvp-dashboard.settings'

const defaults: SettingsState = { serverUrl: '' }

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
    return { ...defaults, serverUrl: serverUrl ?? '' }
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
    resetSettings: () => defaults,
  },
  selectors: {
    selectServerUrl: (state) => state.serverUrl,
  },
})

export const { setServerUrl, resetSettings } = settingsSlice.actions
export const { selectServerUrl } = settingsSlice.selectors

/** `/api` on the configured server, or on the page's own origin. */
export function apiBaseUrl(serverUrl: string): string {
  return `${serverUrl || window.location.origin}/api`
}
