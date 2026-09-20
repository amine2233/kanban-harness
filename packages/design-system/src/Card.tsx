import type { HTMLAttributes, ReactNode } from 'react'
import { cx } from './cx'

export interface CardProps extends Omit<HTMLAttributes<HTMLElement>, 'title'> {
  title?: ReactNode
  actions?: ReactNode
}

export function Card({ title, actions, className, children, ...rest }: CardProps) {
  return (
    <section className={cx('bg-white br2 shadow-outer-1', className)} {...rest}>
      {(title ?? actions) && (
        <header
          className="flex items-center justify-between ph3 pv2 bb b--light-silver"
          style={{ gap: 8 }}
        >
          <h2 className="f3 b dark-gray ma0 truncate flex-auto">{title}</h2>
          {actions && <div className="flex-none">{actions}</div>}
        </header>
      )}
      <div className="pa3">{children}</div>
    </section>
  )
}
