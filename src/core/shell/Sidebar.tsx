import { NavLink } from 'react-router'
import { Icon } from '@/design-system'
import type { NavItem } from '@/core/plugin/types'

export function Sidebar({ items }: { items: NavItem[] }) {
  return (
    <nav className="ds-sidebar pa2" aria-label="Main">
      <ul className="list pl0 ma0">
        {items.map((item) => (
          <li key={item.to}>
            <NavLink to={item.to} className="ds-nav-link">
              <Icon name={item.icon} />
              {item.label}
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  )
}
