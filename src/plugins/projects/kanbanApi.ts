import { baseApi } from '@/app/api'

export interface Page<T> {
  items: T[]
  total: number
  page: number
  page_size: number
  total_pages: number
}

export interface Board {
  id: string
  name: string
  description: string | null
  card_prefix: string | null
  position: number
}

export interface Column {
  id: string
  board_id: string
  name: string
  position: number
  wip_limit: number | null
  default_status: CardStatus | null
}

export type CardPriority = 'low' | 'medium' | 'high' | 'critical'
export type CardStatus = 'todo' | 'in_progress' | 'blocked' | 'done'

export interface Card {
  id: string
  column_id: string
  board_id: string
  prefix: string
  card_number: number
  title: string
  description: string | null
  priority: CardPriority
  status: CardStatus
  position: number
  due_date: string | null
  points: number | null
}

interface BoardScope {
  projectId: string
  boardId: string
}

/** PATCH body for a card; `null` clears a field, `board_id` moves it to another board. */
export interface CardPatch {
  title?: string
  description?: string | null
  priority?: CardPriority
  status?: CardStatus
  column_id?: string
  board_id?: string
  due_date?: string | null
  points?: number | null
}

const PAGE_SIZE = 500

/** kanban-server's REST API, proxied per project by dashboard-server. */
export const kanban = (projectId: string) => `projects/${projectId}/kanban/v1`

export const kanbanApi = baseApi.injectEndpoints({
  endpoints: (build) => ({
    listBoards: build.query<Board[], string>({
      query: (projectId) => `${kanban(projectId)}/boards?page_size=${String(PAGE_SIZE)}`,
      transformResponse: (page: Page<Board>) => page.items,
      providesTags: (_result, _error, projectId) => [{ type: 'Board', id: projectId }],
    }),
    createBoard: build.mutation<
      Board,
      {
        projectId: string
        name: string
        card_prefix?: string | null
        with_default_columns?: boolean
      }
    >({
      query: ({ projectId, ...body }) => ({
        url: `${kanban(projectId)}/boards`,
        method: 'POST',
        body,
      }),
      invalidatesTags: (_result, _error, { projectId }) => [{ type: 'Board', id: projectId }],
    }),
    updateBoard: build.mutation<
      Board,
      BoardScope & {
        name?: string
        position?: number
        description?: string | null
        card_prefix?: string | null
      }
    >({
      query: ({ projectId, boardId, ...body }) => ({
        url: `${kanban(projectId)}/boards/${boardId}`,
        method: 'PATCH',
        body,
      }),
      invalidatesTags: (_result, _error, { projectId }) => [{ type: 'Board', id: projectId }],
    }),
    // eslint-disable-next-line @typescript-eslint/no-invalid-void-type -- 204 has no body
    deleteBoard: build.mutation<void, BoardScope>({
      query: ({ projectId, boardId }) => ({
        url: `${kanban(projectId)}/boards/${boardId}`,
        method: 'DELETE',
      }),
      invalidatesTags: (_result, _error, { projectId }) => [{ type: 'Board', id: projectId }],
    }),
    cloneBoard: build.mutation<Board, BoardScope & { name?: string }>({
      query: ({ projectId, boardId, name }) => ({
        url: `${kanban(projectId)}/boards/${boardId}/clone`,
        method: 'POST',
        body: name ? { name } : {},
      }),
      invalidatesTags: (_result, _error, { projectId }) => [{ type: 'Board', id: projectId }],
    }),
    listColumns: build.query<Column[], BoardScope>({
      query: ({ projectId, boardId }) =>
        `${kanban(projectId)}/boards/${boardId}/columns?page_size=${String(PAGE_SIZE)}`,
      transformResponse: (page: Page<Column>) =>
        [...page.items].sort((a, b) => a.position - b.position),
      providesTags: (_result, _error, { boardId }) => [{ type: 'Column', id: boardId }],
    }),
    createColumn: build.mutation<
      Column,
      BoardScope & { name: string; wip_limit?: number | null; default_status?: CardStatus | null }
    >({
      query: ({ projectId, boardId, ...body }) => ({
        url: `${kanban(projectId)}/boards/${boardId}/columns`,
        method: 'POST',
        body,
      }),
      invalidatesTags: (_result, _error, { boardId }) => [{ type: 'Column', id: boardId }],
    }),
    updateColumn: build.mutation<
      Column,
      BoardScope & {
        columnId: string
        name?: string
        position?: number
        wip_limit?: number | null
        default_status?: CardStatus | null
      }
    >({
      query: ({ projectId, boardId, columnId, ...body }) => ({
        url: `${kanban(projectId)}/boards/${boardId}/columns/${columnId}`,
        method: 'PATCH',
        body,
      }),
      invalidatesTags: (_result, _error, { boardId }) => [{ type: 'Column', id: boardId }],
    }),
    // eslint-disable-next-line @typescript-eslint/no-invalid-void-type -- 204 has no body
    deleteColumn: build.mutation<void, BoardScope & { columnId: string }>({
      query: ({ projectId, boardId, columnId }) => ({
        url: `${kanban(projectId)}/boards/${boardId}/columns/${columnId}`,
        method: 'DELETE',
      }),
      invalidatesTags: (_result, _error, { boardId }) => [
        { type: 'Column', id: boardId },
        { type: 'Card', id: boardId },
      ],
    }),
    listCards: build.query<Card[], BoardScope>({
      query: ({ projectId, boardId }) =>
        `${kanban(projectId)}/boards/${boardId}/cards?page_size=${String(PAGE_SIZE)}`,
      transformResponse: (page: Page<Card>) => page.items,
      providesTags: (_result, _error, { boardId }) => [{ type: 'Card', id: boardId }],
    }),
    createCard: build.mutation<
      Card,
      BoardScope & {
        columnId: string
        title: string
        priority: CardPriority
        description?: string | null
      }
    >({
      query: ({ projectId, columnId, title, priority, description }) => ({
        url: `${kanban(projectId)}/columns/${columnId}/cards`,
        method: 'POST',
        body: { title, priority, description: description ?? null },
      }),
      invalidatesTags: (_result, _error, { boardId }) => [{ type: 'Card', id: boardId }],
    }),
    moveCard: build.mutation<Card, BoardScope & { cardId: string; columnId: string }>({
      query: ({ projectId, boardId, cardId, columnId }) => ({
        url: `${kanban(projectId)}/boards/${boardId}/cards/${cardId}`,
        method: 'PATCH',
        body: { column_id: columnId },
      }),
      invalidatesTags: (_result, _error, { boardId }) => [{ type: 'Card', id: boardId }],
    }),
    updateCard: build.mutation<Card, BoardScope & { cardId: string; patch: CardPatch }>({
      query: ({ projectId, boardId, cardId, patch }) => ({
        url: `${kanban(projectId)}/boards/${boardId}/cards/${cardId}`,
        method: 'PATCH',
        body: patch,
      }),
      invalidatesTags: (_result, _error, { boardId, patch }) => [
        { type: 'Card', id: boardId },
        ...(patch.board_id ? [{ type: 'Card' as const, id: patch.board_id }] : []),
      ],
    }),
    // eslint-disable-next-line @typescript-eslint/no-invalid-void-type -- 204 has no body
    deleteCard: build.mutation<void, BoardScope & { cardId: string }>({
      query: ({ projectId, boardId, cardId }) => ({
        url: `${kanban(projectId)}/boards/${boardId}/cards/${cardId}`,
        method: 'DELETE',
      }),
      invalidatesTags: (_result, _error, { boardId }) => [{ type: 'Card', id: boardId }],
    }),
  }),
})

export const {
  useListBoardsQuery,
  useCreateBoardMutation,
  useUpdateBoardMutation,
  useDeleteBoardMutation,
  useCloneBoardMutation,
  useListColumnsQuery,
  useCreateColumnMutation,
  useUpdateColumnMutation,
  useDeleteColumnMutation,
  useListCardsQuery,
  useCreateCardMutation,
  useMoveCardMutation,
  useUpdateCardMutation,
  useDeleteCardMutation,
} = kanbanApi
