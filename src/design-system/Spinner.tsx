import { cx } from './cx'

export function Spinner({
  inverted = false,
  label = 'Loading',
}: {
  inverted?: boolean
  label?: string
}) {
  const dot = cx('hk-spinner__dot', inverted && 'hk-spinner__dot--inverted')
  return (
    <span className="hk-spinner" role="status" aria-label={label}>
      <span className={cx(dot, 'hk-spinner__dot--one')} />
      <span className={cx(dot, 'hk-spinner__dot--two')} />
      <span className={cx(dot, 'hk-spinner__dot--three')} />
    </span>
  )
}
