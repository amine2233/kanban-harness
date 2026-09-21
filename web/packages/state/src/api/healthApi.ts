import { baseApi } from '../api/baseApi'

export interface Health {
  status: string
}

export const healthApi = baseApi.injectEndpoints({
  endpoints: (build) => ({
    // eslint-disable-next-line @typescript-eslint/no-invalid-void-type -- RTK's no-argument query convention
    health: build.query<Health, void>({ query: () => 'health' }),
  }),
})

export const { useHealthQuery } = healthApi
