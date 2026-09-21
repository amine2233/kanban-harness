import type {
  AICost,
  Card,
  CardPatch,
  CardPriority,
  CardStatus,
  Column,
  DraftPatch,
  NewSubtask,
} from '@mvp/kanban-model'

/** A proposed sub-task in the create form; unticked rows are not created. */
export interface SubtaskRow {
  key: number
  title: string
  description: string | null
  points: number | null
  include: boolean
}

/** Everything the card dialog edits, as plain data. Strings mirror the inputs. */
export interface CardForm {
  title: string
  description: string
  priority: CardPriority
  status: CardStatus
  columnId: string
  boardId: string
  dueDate: string
  points: string
  aiCost: AICost | undefined
  subtasks: SubtaskRow[]
  generateSubtasks: boolean // Whether to generate subtasks when using AI
}

export type CardFormAction =
  | {
      type: 'set'
      field: 'title' | 'description' | 'columnId' | 'boardId' | 'dueDate' | 'points'
      value: string
    }
  | { type: 'setPriority'; value: CardPriority }
  | { type: 'setStatus'; value: CardStatus }
  | { type: 'setGenerateSubtasks'; value: boolean }
  | { type: 'applyDraft'; patch: DraftPatch }
  | { type: 'subtask.add' }
  | { type: 'subtask.title'; key: number; value: string }
  | { type: 'subtask.description'; key: number; value: string }
  | { type: 'subtask.include'; key: number; value: boolean }
  | { type: 'subtask.remove'; key: number }

export function initialCardForm(
  card: Card | undefined,
  scope: { boardId: string },
  columns: Column[],
  columnId?: string,
): CardForm {
  return {
    title: card?.title ?? '',
    description: card?.description ?? '',
    priority: card?.priority ?? 'medium',
    status: card?.status ?? 'todo',
    columnId: card?.column_id ?? columnId ?? columns[0]?.id ?? '',
    boardId: scope.boardId,
    dueDate: card?.due_date?.slice(0, 10) ?? '',
    points: card?.points === null || card === undefined ? '' : String(card.points),
    aiCost: undefined,
    subtasks: [],
    generateSubtasks: true, // Default: generate subtasks with AI
  }
}

export function cardFormReducer(form: CardForm, action: CardFormAction): CardForm {
  switch (action.type) {
    case 'set':
      return { ...form, [action.field]: action.value }
    case 'setPriority':
      return { ...form, priority: action.value }
    case 'setStatus':
      return { ...form, status: action.value }
    case 'setGenerateSubtasks':
      return { ...form, generateSubtasks: action.value }
    case 'applyDraft': {
      const { patch } = action
      return {
        ...form,
        ...(patch.title !== undefined ? { title: patch.title } : {}),
        ...(patch.description !== undefined ? { description: patch.description } : {}),
        ...(patch.priority !== undefined ? { priority: patch.priority } : {}),
        ...(patch.points !== undefined ? { points: String(patch.points) } : {}),
        ...(patch.aiCost !== undefined ? { aiCost: patch.aiCost } : {}),
        ...(patch.subtasks !== undefined && form.generateSubtasks
          ? { subtasks: patch.subtasks.map((s, key) => ({ key, ...s, include: true })) }
          : {}),
      }
    }
    case 'subtask.add':
      return {
        ...form,
        subtasks: [
          ...form.subtasks,
          {
            key: (form.subtasks.at(-1)?.key ?? -1) + 1,
            title: '',
            description: null,
            points: null,
            include: true,
          },
        ],
      }
    case 'subtask.title':
      return {
        ...form,
        subtasks: form.subtasks.map((s) =>
          s.key === action.key ? { ...s, title: action.value } : s,
        ),
      }
    case 'subtask.description':
      return {
        ...form,
        subtasks: form.subtasks.map((s) =>
          s.key === action.key ? { ...s, description: action.value } : s,
        ),
      }
    case 'subtask.include':
      return {
        ...form,
        subtasks: form.subtasks.map((s) =>
          s.key === action.key ? { ...s, include: action.value } : s,
        ),
      }
    case 'subtask.remove':
      return { ...form, subtasks: form.subtasks.filter((s) => s.key !== action.key) }
  }
}

/** Ticked sub-tasks with a title, as the API wants them. */
export function includedSubtasks(form: CardForm): NewSubtask[] {
  return form.subtasks
    .filter((s) => s.include && s.title.trim())
    .map((s) => ({ title: s.title.trim(), description: s.description, points: s.points }))
}

/** Body of the create request, or null when the form is not submittable. */
export function toCreateRequest(form: CardForm) {
  const title = form.title.trim()
  if (!title) return null
  return {
    columnId: form.columnId,
    title,
    priority: form.priority,
    description: form.description.trim() || null,
    aiCost: form.aiCost,
    subtasks: includedSubtasks(form),
  }
}

/** PATCH for an existing card; a board change wins over a column change. */
export function toPatch(form: CardForm, card: Card, scope: { boardId: string }): CardPatch | null {
  const title = form.title.trim()
  if (!title) return null
  const patch: CardPatch = {
    title,
    description: form.description.trim() || null,
    priority: form.priority,
    status: form.status,
    due_date: form.dueDate ? new Date(`${form.dueDate}T00:00:00Z`).toISOString() : null,
    points: form.points === '' ? null : Number(form.points),
  }
  if (form.boardId !== scope.boardId) patch.board_id = form.boardId
  else if (form.columnId !== card.column_id) patch.column_id = form.columnId
  return patch
}
