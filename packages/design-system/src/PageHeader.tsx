import type { ReactNode } from 'react'

export interface PageHeaderProps {
  title: string
  description?: string
  actions?: ReactNode
}

export function PageHeader({ title, description, actions }: PageHeaderProps) {
  return (
    <header className="ds-page-header">
      <div style={{ minWidth: 0 }}>
        <h1 className="ds-page-title truncate">{title}</h1>
        {description && <p className="ds-page-description truncate">{description}</p>}
      </div>
      {actions && <div className="flex items-center flex-none">{actions}</div>}
    </header>
  )
}
