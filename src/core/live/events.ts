import type { TagDescription } from '@reduxjs/toolkit/query'

/** Wire shape of `GET /api/events` frames (see DashboardAPI.ChangeEventDTO). */
export interface ChangeEvent {
  kind: 'hello' | 'projects_changed' | 'workspace_changed' | 'settings_changed'
  project_id?: string | null
}

export type ApiTag = TagDescription<'Project' | 'Board' | 'Column' | 'Card' | 'Settings'>

export function parseChangeEvent(raw: string): ChangeEvent | null {
  try {
    const value = JSON.parse(raw) as Partial<ChangeEvent>
    switch (value.kind) {
      case 'hello':
      case 'projects_changed':
      case 'settings_changed':
        return { kind: value.kind }
      case 'workspace_changed':
        return typeof value.project_id === 'string'
          ? { kind: 'workspace_changed', project_id: value.project_id.toLowerCase() }
          : null
      default:
        return null
    }
  } catch {
    return null
  }
}

/** Which RTK Query caches an event makes stale. */
export function tagsFor(event: ChangeEvent): ApiTag[] {
  switch (event.kind) {
    case 'projects_changed':
      return ['Project']
    case 'settings_changed':
      return ['Settings']
    case 'workspace_changed':
      return ['Board', 'Column', 'Card']
    case 'hello':
      return []
  }
}

/** `ws(s)://…/api/events` for the configured API base (`http(s)://…/api`). */
export function eventsUrl(apiBase: string): string {
  return `${apiBase.replace(/^http/, 'ws')}/events`
}
