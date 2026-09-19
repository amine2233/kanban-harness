import type { ReactNode } from 'react'

export interface PageHeaderProps {
  title: string
  description?: string
  actions?: ReactNode
}

export function PageHeader({ title, description, actions }: PageHeaderProps) {
  return (
    <header className="flex items-center justify-between mb4">
      <div>
        <h1 className="f1 b near-black ma0">{title}</h1>
        {description && <p className="f4 gray mt1 mb0">{description}</p>}
      </div>
      {actions && <div className="flex items-center">{actions}</div>}
    </header>
  )
}
