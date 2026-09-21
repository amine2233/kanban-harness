import type { DashboardPlugin } from '@/core/plugin/types'
import { ProjectPage } from './ProjectPage'
import { ProjectsSidebar } from './ProjectsSidebar'

export const projectsPlugin: DashboardPlugin = {
  id: 'projects',
  name: 'Projects',
  nav: [],
  routes: [{ path: '/projects/:id', element: <ProjectPage /> }],
  sidebar: ProjectsSidebar,
}
