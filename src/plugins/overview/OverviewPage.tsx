import { Link } from 'react-router'
import { errorMessage } from '@/app/api'
import { Banner, Icon, PageHeader, Spinner } from '@mvp/design-system'
import { AddProjectForm } from '@/plugins/projects/AddProjectForm'
import { useListBoardsQuery } from '@/plugins/projects/api/kanbanApi'
import { useListProjectsQuery, type Project } from '@/plugins/projects/api/projectsApi'

export function OverviewPage() {
  const { data: projects = [], isLoading, error } = useListProjectsQuery()

  return (
    <>
      <PageHeader
        title="Overview"
        description={
          projects.length === 0
            ? 'Register a folder to start a board.'
            : `${String(projects.length)} project${projects.length === 1 ? '' : 's'}`
        }
      />
      {isLoading && <Spinner />}
      {error && (
        <Banner tone="danger" title="Cannot load projects">
          {errorMessage(error)}
        </Banner>
      )}
      {!isLoading && !error && projects.length === 0 && (
        <div className="ds-empty">
          <span className="ds-empty__icon">
            <Icon name="folder" size={28} />
          </span>
          <h2 className="ds-empty__title">No projects yet</h2>
          <p className="ds-empty__text">
            A project is a folder on this machine holding one kanban workspace. Point the dashboard
            at a folder — it is created and seeded if it does not exist.
          </p>
          <div className="ds-empty__form">
            <AddProjectForm onDone={() => undefined} />
          </div>
        </div>
      )}
      <div className="ds-grid">
        {projects.map((project) => (
          <ProjectSummary key={project.id} project={project} />
        ))}
      </div>
    </>
  )
}

function ProjectSummary({ project }: { project: Project }) {
  const { data: boards = [] } = useListBoardsQuery(project.id)
  return (
    <Link to={`/projects/${project.id}`} className="ds-tile">
      <span className="ds-tile__icon">
        <Icon name="folder" size={18} />
      </span>
      <span className="ds-tile__body">
        <span className="ds-tile__title">{project.name}</span>
        <span className="ds-tile__path">{project.path}</span>
        <span className="ds-tile__meta">
          <span className="ds-chip">{project.storage.toUpperCase()}</span>
          <span>
            {String(boards.length)} board{boards.length === 1 ? '' : 's'}
          </span>
          {boards.length > 0 && (
            <span className="truncate">{boards.map((b) => b.name).join(' · ')}</span>
          )}
        </span>
      </span>
      <Icon name="arrowRight" size={16} className="ds-tile__arrow" />
    </Link>
  )
}
