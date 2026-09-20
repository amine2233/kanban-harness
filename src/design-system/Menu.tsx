import { useEffect, useId, useRef, useState } from 'react'
import { Button } from './Button'
import { cx } from './cx'

export interface MenuItem {
  label: string
  onSelect: () => void
  danger?: boolean
  disabled?: boolean
  /** Draw a divider above this item. */
  separated?: boolean
}

export interface MenuProps {
  /** Accessible name of the "⋯" trigger, e.g. "Board actions". */
  label: string
  items: MenuItem[]
  align?: 'left' | 'right'
  size?: 'sm' | 'md'
}

/** "⋯" trigger opening a purple3 dropdown; closes on select, Escape or outside click. */
export function Menu({ label, items, align = 'right', size = 'sm' }: MenuProps) {
  const [open, setOpen] = useState(false)
  const root = useRef<HTMLDivElement>(null)
  const menuId = useId()

  useEffect(() => {
    if (!open) return
    const onPointer = (event: MouseEvent) => {
      if (!root.current?.contains(event.target as Node)) setOpen(false)
    }
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false)
    }
    document.addEventListener('mousedown', onPointer)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onPointer)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  return (
    <div ref={root} className="relative dib">
      <Button
        variant="tertiary"
        size={size}
        aria-label={label}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={menuId}
        onClick={() => {
          setOpen((o) => !o)
        }}
      >
        ⋯
      </Button>
      {open && (
        <ul
          id={menuId}
          role="menu"
          aria-label={label}
          className={cx(align === 'right' ? 'hk-dropdown--right' : 'hk-dropdown', 'ma0 z-5')}
        >
          {items.map((item) => (
            <li key={item.label} className={cx(item.separated && 'bt b--light-silver mt1 pt1')}>
              <button
                type="button"
                role="menuitem"
                className={item.danger ? 'hk-dropdown-item--danger' : 'hk-dropdown-item'}
                disabled={item.disabled}
                onClick={() => {
                  setOpen(false)
                  item.onSelect()
                }}
              >
                {item.label}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
