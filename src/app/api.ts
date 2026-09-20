import {
  createApi,
  fetchBaseQuery,
  type BaseQueryFn,
  type FetchArgs,
  type FetchBaseQueryError,
} from '@reduxjs/toolkit/query/react'
import { apiBaseUrl, selectServerUrl } from '@/core/settings/settingsSlice'

/** Resolves the base URL per request so a settings change applies immediately. */
const dynamicBaseQuery: BaseQueryFn<string | FetchArgs, unknown, FetchBaseQueryError> = (
  args,
  api,
  extraOptions,
) => {
  const serverUrl = selectServerUrl(api.getState() as Parameters<typeof selectServerUrl>[0])
  return fetchBaseQuery({ baseUrl: apiBaseUrl(serverUrl) })(args, api, extraOptions)
}

/** Single RTK Query API; plugins add endpoints with `baseApi.injectEndpoints`. */
export const baseApi = createApi({
  reducerPath: 'api',
  baseQuery: dynamicBaseQuery,
  tagTypes: ['Project', 'Board', 'Column', 'Card', 'Settings'],
  endpoints: () => ({}),
})

export interface ApiErrorBody {
  code: string
  message: string
}

export function errorMessage(error: unknown): string {
  if (typeof error === 'object' && error !== null && 'data' in error) {
    const data = (error as { data?: Partial<ApiErrorBody> }).data
    if (data?.message) return data.message
  }
  return 'Request failed'
}
