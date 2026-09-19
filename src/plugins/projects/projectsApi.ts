import { baseApi } from '@/app/api'

export type StorageKind = 'json' | 'sqlite'

export interface Project {
  id: string
  name: string
  path: string
  storage: StorageKind
  created_at: string
}

export interface CreateProjectRequest {
  name: string
  path: string
  storage: StorageKind
}

export const projectsApi = baseApi.injectEndpoints({
  endpoints: (build) => ({
    // eslint-disable-next-line @typescript-eslint/no-invalid-void-type -- RTK's no-argument query convention
    listProjects: build.query<Project[], void>({
      query: () => 'projects',
      providesTags: (result = []) => [
        { type: 'Project', id: 'LIST' },
        ...result.map((p) => ({ type: 'Project' as const, id: p.id })),
      ],
    }),
    getProject: build.query<Project, string>({
      query: (id) => `projects/${id}`,
      providesTags: (_result, _error, id) => [{ type: 'Project', id }],
    }),
    createProject: build.mutation<Project, CreateProjectRequest>({
      query: (body) => ({ url: 'projects', method: 'POST', body }),
      invalidatesTags: [{ type: 'Project', id: 'LIST' }],
    }),
     
    updateProject: build.mutation<Project, { id: string; storage: StorageKind }>({
      query: ({ id, storage }) => ({ url: `projects/${id}`, method: 'PATCH', body: { storage } }),
      invalidatesTags: (_result, _error, { id }) => [
        { type: 'Project', id: 'LIST' },
        { type: 'Project', id },
      ],
    }),
    // eslint-disable-next-line @typescript-eslint/no-invalid-void-type -- 204 has no body
    deleteProject: build.mutation<void, string>({
      query: (id) => ({ url: `projects/${id}`, method: 'DELETE' }),
      invalidatesTags: (_result, _error, id) => [
        { type: 'Project', id: 'LIST' },
        { type: 'Project', id },
      ],
    }),
  }),
})

export const {
  useListProjectsQuery,
  useGetProjectQuery,
  useCreateProjectMutation,
  useUpdateProjectMutation,
  useDeleteProjectMutation,
} = projectsApi
