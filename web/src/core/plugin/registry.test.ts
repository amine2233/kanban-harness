import { describe, expect, test } from 'vitest'
import { buildRegistry } from './registry'
import type { DashboardPlugin } from './types'

const plugin = (id: string, to: string): DashboardPlugin => ({
  id,
  name: id,
  nav: [{ label: id, to, icon: 'grid' }],
  routes: [{ path: to, element: null }],
})

describe('buildRegistry', () => {
  test('flattens nav and routes in plugin order', () => {
    const registry = buildRegistry([plugin('a', '/a'), plugin('b', '/b')])
    expect(registry.nav.map((n) => n.to)).toEqual(['/a', '/b'])
    expect(registry.routes.map((r) => r.path)).toEqual(['/a', '/b'])
  })

  test('collects sidebar sections only from plugins that define one', () => {
    const Section = () => null
    const registry = buildRegistry([plugin('a', '/a'), { ...plugin('b', '/b'), sidebar: Section }])
    expect(registry.sidebarSections).toEqual([Section])
  })

  test('rejects duplicate ids', () => {
    expect(() => buildRegistry([plugin('a', '/a'), plugin('a', '/b')])).toThrow(
      'Duplicate plugin id: a',
    )
  })
})
