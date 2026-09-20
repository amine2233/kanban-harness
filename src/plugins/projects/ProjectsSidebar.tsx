import { useState } from 'react'
import { NavLink } from 'react-router'
import { errorMessage } from '@/app/api'
import { Icon, Spinner } from '@/design-system'
import { AddProjectForm } from './AddProjectForm'
import { useListProjectsQuery } from './projectsApi'

export function ProjectsSidebar() {
  const { data: projects = [], isLoading, error } = useListProjectsQuery()
  const [adding, setAdding] = useState(false)

  return (
    <section className="ds-sidebar-section" aria-label="Projects">
      <div className="ds-sidebar-section__header flex items-center justify-between ph2 mb1">
        <span className="f6 b gray ttu tracked">Projects</span>
        <button
          type="button"
          className="ds-icon-button gray"
          aria-label="Add project"
          aria-expanded={adding}
          onClick={() => {
            setAdding((open) => !open)
          }}
        >
          <Icon name="plus" />
        </button>
      </div>
      {adding && (
        <AddProjectForm
          onDone={() => {
            setAdding(false)
          }}
        />
      )}
      {isLoading && (
        <div className="ph2 pv1">
          <Spinner />
        </div>
      )}
      {error && <p className="ph2 f6 red ma0">{errorMessage(error)}</p>}
      {!isLoading && !error && projects.length === 0 && (
        <p className="ph2 f6 gray ma0">No projects yet</p>
      )}
      <ul className="ds-sidebar-section__list list pl0 ma0">
        {projects.map((project) => (
          <li key={project.id}>
            <NavLink to={`/projects/${project.id}`} className="ds-nav-link">
              <Icon name="folder" />
              {project.name}
            </NavLink>
          </li>
        ))}
      </ul>
    </section>
  )
}
