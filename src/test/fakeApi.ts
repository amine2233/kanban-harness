import { vi } from 'vitest'

type Handler = (body: unknown) => { status?: number; body?: unknown }
export type Routes = Record<string, Handler>

/** Stubs global fetch with handlers keyed by `METHOD /api/path` (query string ignored). */
export function stubApi(routes: Routes) {
  const calls: { key: string; body: unknown }[] = []
  const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const request = input instanceof Request ? input : new Request(input, init)
    const path = new URL(request.url).pathname
    const key = `${request.method} ${path}`
    const text = await request.text()
    const body = text ? (JSON.parse(text) as unknown) : undefined
    calls.push({ key, body })
    const handler = routes[key]
    if (!handler) {
      return new Response(JSON.stringify({ code: 'NOT_FOUND', message: `no route ${key}` }), {
        status: 404,
        headers: { 'content-type': 'application/json' },
      })
    }
    const result = handler(body)
    return new Response(result.body === undefined ? null : JSON.stringify(result.body), {
      status: result.status ?? 200,
      headers: { 'content-type': 'application/json' },
    })
  })
  vi.stubGlobal('fetch', fetchMock)
  return { calls }
}
