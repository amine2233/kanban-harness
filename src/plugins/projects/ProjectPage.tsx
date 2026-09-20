import { useNavigate, useParams } from 'react-router'
import { errorMessage } from '@/app/api'
import { Banner, Button, PageHeader, Select, Spinner } from '@/design-system'
import { KanbanBoard } from './KanbanBoard'
import {
  useDeleteProjectMutation,
  useGetProjectQuery,
  useUpdateProjectMutation,
  type StorageKind,
} from './projectsApi'

export function ProjectPage() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const { data: project, isLoading, error } = useGetProjectQuery(id)
  const [deleteProject, { isLoading: deleting }] = useDeleteProjectMutation()
  const [updateProject, { isLoading: switching }] = useUpdateProjectMutation()

  if (isLoading) return <Spinner />
  if (error || !project) {
    return (
      <Banner tone="danger" title="Project not found">
        {errorMessage(error)}
      </Banner>
    )
  }

  const unregister = async () => {
    if (!window.confirm(`Unregister "${project.name}"? Files on disk are kept.`)) return
    await deleteProject(project.id).unwrap()
    await navigate('/')
  }

  return (
    <div className="ds-page--fill">
      <PageHeader
        title={project.name}
        description={project.path}
        actions={
          <>
            <Select
              name="storage"
              aria-label="Storage"
              value={project.storage}
              disabled={switching}
              className="mr2"
              onChange={(e) => {
                void updateProject({ id: project.id, storage: e.target.value as StorageKind })
              }}
            >
              <option value="json">JSON</option>
              <option value="sqlite">SQLite</option>
            </Select>
            <Button
              variant="danger"
              size="sm"
              disabled={deleting}
              onClick={() => {
                void unregister()
              }}
            >
              Unregister
            </Button>
          </>
        }
      />
      <KanbanBoard projectId={project.id} />
    </div>
  )
}
