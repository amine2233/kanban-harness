export { createStore, type AppDispatch, type AppStore } from './store'
export { rootReducer, type RootState } from './reducer'
export { useAppDispatch, useAppSelector } from './hooks'

export { baseApi, errorMessage, type ApiErrorBody } from './api/baseApi'
export * from './api/kanbanApi'
export * from './api/projectsApi'
export * from './api/settingsApi'
export * from './api/aiConfigApi'
export * from './api/healthApi'

export {
  settingsSlice,
  setServerUrl,
  setTheme,
  resetSettings,
  selectServerUrl,
  selectTheme,
  normaliseServerUrl,
  apiBaseUrl,
  loadSettings,
  saveSettings,
  SETTINGS_STORAGE_KEY,
  THEMES,
  type SettingsState,
  type Theme,
} from './settings/settingsSlice'
export { shellSlice, toggleSidebar, selectSidebarCollapsed } from './shell/shellSlice'
export {
  liveSlice,
  startLive,
  stopLive,
  selectLiveStatus,
  selectLiveEventCount,
  type LiveStatus,
} from './live/liveSlice'
export { parseChangeEvent, tagsFor, eventsUrl, type ChangeEvent } from './live/events'
export {
  assistantSlice,
  streamDraft,
  resetDraft,
  frameReceived,
  selectAssistant,
  phaseDurations,
  STEPS,
  type AssistantState,
  type AssistantError,
  type AssistantFrame,
  type Stage,
  type Step,
} from './assistant/assistantSlice'
