import { vi } from 'vitest'

type Handler = (body: unknown) => { status?: number; body?: unknown; sse?: [string, unknown][] }
export type Routes = Record<string, Handler>

/**
 * Stubs global fetch with handlers keyed by `METHOD /api/path` (query string ignored).
 * A handler returning `sse` answers with those `[event, data]` frames as an event stream.
 */
export function stubApi(routes: Routes) {
  const calls: { key: string; body: unknown; search: string }[] = []
  const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const request = input instanceof Request ? input : new Request(input, init)
    const url = new URL(request.url)
    const key = `${request.method} ${url.pathname}`
    const text = await request.text()
    const body = text ? (JSON.parse(text) as unknown) : undefined
    calls.push({ key, body, search: url.search })
    const handler = routes[key]
    if (!handler) {
      return new Response(JSON.stringify({ code: 'NOT_FOUND', message: `no route ${key}` }), {
        status: 404,
        headers: { 'content-type': 'application/json' },
      })
    }
    const result = handler(body)
    if (result.sse) {
      const text = result.sse
        .map(([event, data]) => `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`)
        .join('')
      return new Response(text, { status: 200, headers: { 'content-type': 'text/event-stream' } })
    }
    return new Response(result.body === undefined ? null : JSON.stringify(result.body), {
      status: result.status ?? 200,
      headers: { 'content-type': 'application/json' },
    })
  })
  vi.stubGlobal('fetch', fetchMock)
  return { calls }
}
