import { useAppDispatch, useAppSelector } from '@/app/hooks'
import { cx, Icon } from '@/design-system'
import { selectTheme, setTheme, THEMES, type Theme } from './settingsSlice'

const LABELS: Record<Theme, string> = { system: 'System', light: 'Light', dark: 'Dark' }
const ICONS: Record<Theme, 'monitor' | 'sun' | 'moon'> = {
  system: 'monitor',
  light: 'sun',
  dark: 'moon',
}

/** Segmented System / Light / Dark switch. */
export function ThemePicker({ compact = false }: { compact?: boolean }) {
  const dispatch = useAppDispatch()
  const theme = useAppSelector(selectTheme)
  return (
    <div
      className={cx('ds-segmented', compact && 'ds-segmented--compact')}
      role="radiogroup"
      aria-label="Theme"
    >
      {THEMES.map((option) => (
        <button
          key={option}
          type="button"
          role="radio"
          aria-checked={theme === option}
          aria-label={LABELS[option]}
          title={LABELS[option]}
          className="ds-segmented__option"
          onClick={() => {
            dispatch(setTheme(option))
          }}
        >
          <Icon name={ICONS[option]} size={14} />
          {!compact && <span>{LABELS[option]}</span>}
        </button>
      ))}
    </div>
  )
}
