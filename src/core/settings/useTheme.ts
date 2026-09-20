import { useEffect } from 'react'
import { useAppSelector } from '@/app/hooks'
import { selectTheme, type Theme } from './settingsSlice'

const query = () =>
  typeof window.matchMedia === 'function' ? window.matchMedia('(prefers-color-scheme: dark)') : null

/** The look actually in effect: `system` resolves through the OS preference. */
export function effectiveTheme(theme: Theme): 'light' | 'dark' {
  if (theme !== 'system') return theme
  return query()?.matches ? 'dark' : 'light'
}

/** Stamps the effective theme on `<html>` so the stylesheet only ever branches on `data-theme`. */
export function applyTheme(theme: Theme): void {
  const effective = effectiveTheme(theme)
  document.documentElement.dataset.theme = effective
  document.documentElement.style.colorScheme = effective
}

export function useTheme(): Theme {
  const theme = useAppSelector(selectTheme)
  useEffect(() => {
    applyTheme(theme)
    if (theme !== 'system') return undefined
    const media = query()
    if (!media) return undefined
    const follow = () => {
      applyTheme('system')
    }
    media.addEventListener('change', follow)
    return () => {
      media.removeEventListener('change', follow)
    }
  }, [theme])
  return theme
}
