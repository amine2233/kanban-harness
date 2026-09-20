import type { SVGAttributes } from 'react'

const PATHS = {
  home: 'M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z',
  grid: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z',
  settings:
    'M12 15.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zm7.4-2.5.9.7-1.9 3.3-1.1-.4a7 7 0 0 1-1.8 1l-.2 1.2H9.7l-.2-1.2a7 7 0 0 1-1.8-1l-1.1.4-1.9-3.3.9-.7a7 7 0 0 1 0-2l-.9-.7 1.9-3.3 1.1.4a7 7 0 0 1 1.8-1l.2-1.2h3.6l.2 1.2a7 7 0 0 1 1.8 1l1.1-.4 1.9 3.3-.9.7a7 7 0 0 1 0 2z',
  bolt: 'M13 2 4 14h6l-1 8 9-12h-6z',
  menu: 'M4 6h16M4 12h16M4 18h16',
  plus: 'M12 5v14M5 12h14',
  folder: 'M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
  trash: 'M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3',
  arrowLeft: 'M19 12H5M11 18l-6-6 6-6',
  arrowRight: 'M5 12h14M13 6l6 6-6 6',
  dots: 'M5 12h.01M12 12h.01M19 12h.01',
} as const

export type IconName = keyof typeof PATHS

export interface IconProps extends SVGAttributes<SVGSVGElement> {
  name: IconName
  size?: number
}

export function Icon({ name, size = 16, ...rest }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      {...rest}
    >
      <path d={PATHS[name]} />
    </svg>
  )
}
