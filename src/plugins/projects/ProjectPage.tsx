import { useNavigate, useParams } from 'react-router'
import { errorMessage } from '@/app/api'
import { Badge, Banner, Button, PageHeader, Spinner } from '@/design-system'
import { KanbanBoard } from './KanbanBoard'
import { useDeleteProjectMutation, useGetProjectQuery } from './projectsApi'

export function ProjectPage() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const { data: project, isLoading, error } = useGetProjectQuery(id)
  const [deleteProject, { isLoading: deleting }] = useDeleteProjectMutation()

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
    <>
      <PageHeader
        title={project.name}
        description={project.path}
        actions={
          <>
            <Badge variant="outline" className="mr2">
              {project.storage}
            </Badge>
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
    </>
  )
}
