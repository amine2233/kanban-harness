import { createApi, fetchBaseQuery } from '@reduxjs/toolkit/query/react'

/** Single RTK Query API; plugins add endpoints with `baseApi.injectEndpoints`. */
export const baseApi = createApi({
  reducerPath: 'api',
  baseQuery: fetchBaseQuery({ baseUrl: new URL('/api', window.location.origin).href }),
  tagTypes: ['Project', 'Board', 'Column', 'Card'],
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
