import { baseApi } from '@/app/api'
import type { StorageKind } from '@/plugins/projects/projectsApi'

/** Server-side settings (settings.json on the server), applied live. */
export interface ServerSettings {
  default_storage: StorageKind
  cors_origins: string[]
}

export const settingsApi = baseApi.enhanceEndpoints({ addTagTypes: ['Settings'] }).injectEndpoints({
  endpoints: (build) => ({
    // eslint-disable-next-line @typescript-eslint/no-invalid-void-type -- RTK's no-argument query convention
    getServerSettings: build.query<ServerSettings, void>({
      query: () => 'settings',
      providesTags: ['Settings'],
    }),
    updateServerSettings: build.mutation<ServerSettings, Partial<ServerSettings>>({
      query: (body) => ({ url: 'settings', method: 'PATCH', body }),
      invalidatesTags: ['Settings'],
    }),
  }),
})

export const { useGetServerSettingsQuery, useUpdateServerSettingsMutation } = settingsApi
