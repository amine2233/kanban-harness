import { useState, type SyntheticEvent } from 'react'
import { errorMessage } from '@/app/api'
import {
  Badge,
  Banner,
  Button,
  Card,
  ConfirmModal,
  Input,
  Menu,
  Modal,
  Row,
  Select,
  Spinner,
} from '@mvp/design-system'
import {
  KEYED_KINDS,
  KIND_BASE_URL,
  KIND_LABELS,
  useGetAIConfigQuery,
  useRemoveAIProviderMutation,
  useSetDefaultAIProviderMutation,
  useUpsertAIProviderMutation,
  type AIProvider,
  type AIProviderKind,
} from './aiConfigApi'

type Dialog =
  | { kind: 'add' }
  | { kind: 'edit'; provider: AIProvider }
  | { kind: 'remove'; provider: AIProvider }

/** Providers live in config.json / config.yaml on the server; keys are write-only. */
export function AIProvidersCard() {
  const { data, isLoading, error } = useGetAIConfigQuery()
  const [setDefault] = useSetDefaultAIProviderMutation()
  const [remove, removal] = useRemoveAIProviderMutation()
  const [dialog, setDialog] = useState<Dialog>()
  const close = () => {
    setDialog(undefined)
  }

  return (
    <Card
      title="AI providers"
      className="mw7 mt3"
      actions={
        <Button
          size="sm"
          onClick={() => {
            setDialog({ kind: 'add' })
          }}
        >
          Add provider
        </Button>
      }
    >
      <p className="f6 gray mt0 mb3">
        Stored in <code>config.json</code> (or <code>config.yaml</code>) on the server. API keys are
        written there and never sent back; set{' '}
        <code>MVP_DASHBOARD_AI_PROVIDERS_&lt;ID&gt;_API_KEY</code> in the server&apos;s environment
        to keep a key out of the file.
      </p>
      {isLoading && <Spinner />}
      {error && (
        <Banner tone="danger" title="Cannot load AI providers">
          {errorMessage(error)}
        </Banner>
      )}
      {data?.providers.length === 0 && <p className="f5 gray ma0">No provider configured yet.</p>}
      {data && data.providers.length > 0 && (
        <ul className="list pl0 ma0">
          {data.providers.map((provider) => (
            <li
              key={provider.id}
              className="ds-row ds-gap-md ds-align-center pv2 bb b--light-silver"
              aria-label={provider.name}
            >
              <span className="flex-auto" style={{ minWidth: 0 }}>
                <span className="b near-black">{provider.name}</span>
                {data.default_provider === provider.id && (
                  <Badge variant="new" className="ml2">
                    default
                  </Badge>
                )}
                <span className="db f6 gray truncate">
                  {KIND_LABELS[provider.kind]} · {provider.model}
                  {provider.base_url && ` · ${provider.base_url}`}
                  {provider.pricing &&
                    ` · $${String(provider.pricing.input_per_million)} / $${String(provider.pricing.output_per_million)} per M tokens`}
                </span>
              </span>
              <Badge
                variant={
                  provider.has_api_key || !KEYED_KINDS.has(provider.kind) ? 'outline' : 'alpha'
                }
              >
                {!KEYED_KINDS.has(provider.kind)
                  ? 'no key needed'
                  : provider.has_api_key
                    ? 'key set'
                    : 'no key'}
              </Badge>
              <Menu
                label={`${provider.name} actions`}
                items={[
                  {
                    label: 'Edit',
                    onSelect: () => {
                      setDialog({ kind: 'edit', provider })
                    },
                  },
                  {
                    label: 'Make default',
                    disabled: data.default_provider === provider.id,
                    onSelect: () => {
                      void setDefault(provider.id)
                    },
                  },
                  {
                    label: 'Remove',
                    danger: true,
                    separated: true,
                    onSelect: () => {
                      setDialog({ kind: 'remove', provider })
                    },
                  },
                ]}
              />
            </li>
          ))}
        </ul>
      )}
      {dialog?.kind === 'add' && <ProviderDialog onClose={close} />}
      {dialog?.kind === 'edit' && <ProviderDialog provider={dialog.provider} onClose={close} />}
      {dialog?.kind === 'remove' && (
        <ConfirmModal
          title={`Remove "${dialog.provider.name}"?`}
          message="The provider and its stored key are deleted from the config file."
          confirmLabel="Remove"
          busy={removal.isLoading}
          onConfirm={() => {
            void remove(dialog.provider.id).then((result) => {
              if (!('error' in result)) close()
            })
          }}
          onClose={close}
        />
      )}
    </Card>
  )
}

const KINDS = Object.keys(KIND_LABELS) as AIProviderKind[]

const MODEL_PLACEHOLDER: Record<AIProviderKind, string> = {
  apple: 'system',
  anthropic: 'claude-sonnet-5',
  openai: 'gpt-5',
  gemini: 'gemini-2.5-flash',
  ollama: 'llama3.2',
  claude_code: 'sonnet',
}

function ProviderDialog({
  provider,
  onClose,
}: {
  provider?: AIProvider | undefined
  onClose: () => void
}) {
  const [id, setId] = useState(provider?.id ?? '')
  const [kind, setKind] = useState<AIProviderKind>(provider?.kind ?? 'anthropic')
  const [name, setName] = useState(provider?.name ?? '')
  const [model, setModel] = useState(provider?.model ?? '')
  const [baseUrl, setBaseUrl] = useState(provider?.base_url ?? '')
  const [apiKey, setApiKey] = useState('')
  const [clearKey, setClearKey] = useState(false)
  const [maxTokens, setMaxTokens] = useState(
    provider?.max_tokens === null || !provider ? '' : String(provider.max_tokens),
  )
  const [inputPrice, setInputPrice] = useState(
    provider?.pricing ? String(provider.pricing.input_per_million) : '',
  )
  const [outputPrice, setOutputPrice] = useState(
    provider?.pricing ? String(provider.pricing.output_per_million) : '',
  )
  const [upsert, result] = useUpsertAIProviderMutation()
  const idValid = /^[a-z][a-z0-9_]{0,31}$/.test(id)
  const needsKey = KEYED_KINDS.has(kind)
  const defaultBaseUrl = KIND_BASE_URL[kind]

  const submit = async (event: SyntheticEvent) => {
    event.preventDefault()
    if (!idValid) return
    const body = {
      kind,
      name: name.trim() || id,
      model: model.trim(),
      base_url: defaultBaseUrl && baseUrl.trim() !== '' ? baseUrl.trim() : null,
      max_tokens: maxTokens === '' ? null : Number(maxTokens),
      pricing:
        inputPrice === '' && outputPrice === ''
          ? null
          : {
              input_per_million: Number(inputPrice || 0),
              output_per_million: Number(outputPrice || 0),
            },
      ...(clearKey ? { api_key: '' } : apiKey ? { api_key: apiKey } : {}),
    }
    const outcome = await upsert({ id, body })
    if (outcome.data) onClose()
  }

  return (
    <Modal title={provider ? `Edit ${provider.name}` : 'Add AI provider'} onClose={onClose}>
      <form
        onSubmit={(event) => {
          void submit(event)
        }}
      >
        <Row className="mb2">
          <Input
            name="provider-id"
            label="Id"
            placeholder="claude"
            value={id}
            disabled={provider !== undefined}
            required
            className="flex-auto"
            onChange={(e) => {
              setId(e.target.value.toLowerCase())
            }}
          />
          <Select
            name="provider-kind"
            label="Kind"
            value={kind}
            className="flex-auto"
            onChange={(e) => {
              setKind(e.target.value as AIProviderKind)
            }}
          >
            {KINDS.map((k) => (
              <option key={k} value={k}>
                {KIND_LABELS[k]}
              </option>
            ))}
          </Select>
        </Row>
        {!idValid && id !== '' && (
          <p className="f6 red mt0 mb2">Use a-z, 0-9 and _, starting with a letter.</p>
        )}
        <Row className="mb2">
          <Input
            name="provider-name"
            label="Name"
            placeholder={id || 'Display name'}
            value={name}
            className="flex-auto"
            onChange={(e) => {
              setName(e.target.value)
            }}
          />
          <Input
            name="provider-model"
            label="Model"
            placeholder={MODEL_PLACEHOLDER[kind]}
            value={model}
            required
            className="flex-auto"
            onChange={(e) => {
              setModel(e.target.value)
            }}
          />
        </Row>
        {defaultBaseUrl && (
          <Input
            name="provider-base-url"
            label="Base URL (optional)"
            placeholder={defaultBaseUrl}
            value={baseUrl}
            className="mb2"
            onChange={(e) => {
              setBaseUrl(e.target.value)
            }}
          />
        )}
        {needsKey && (
          <>
            <Input
              name="provider-api-key"
              label={
                provider?.has_api_key ? 'API key (leave empty to keep the stored key)' : 'API key'
              }
              type="password"
              autoComplete="off"
              value={apiKey}
              disabled={clearKey}
              className="mb1"
              onChange={(e) => {
                setApiKey(e.target.value)
              }}
            />
            {provider?.has_api_key && (
              <label className="f6 gray db mb2">
                <input
                  type="checkbox"
                  checked={clearKey}
                  onChange={(e) => {
                    setClearKey(e.target.checked)
                  }}
                />{' '}
                Clear the stored key
              </label>
            )}
          </>
        )}
        <Row className="mb2">
          <Input
            name="provider-max-tokens"
            label="Max tokens (optional)"
            type="number"
            min={1}
            value={maxTokens}
            className="flex-auto"
            onChange={(e) => {
              setMaxTokens(e.target.value)
            }}
          />
          <Input
            name="provider-input-price"
            label="Input $/M tokens"
            type="number"
            min={0}
            step="any"
            placeholder={
              kind === 'claude_code' ? 'reported by claude' : KEYED_KINDS.has(kind) ? '3' : 'free'
            }
            value={inputPrice}
            className="flex-auto"
            onChange={(e) => {
              setInputPrice(e.target.value)
            }}
          />
          <Input
            name="provider-output-price"
            label="Output $/M tokens"
            type="number"
            min={0}
            step="any"
            placeholder={
              kind === 'claude_code' ? 'reported by claude' : KEYED_KINDS.has(kind) ? '15' : 'free'
            }
            value={outputPrice}
            className="flex-auto"
            onChange={(e) => {
              setOutputPrice(e.target.value)
            }}
          />
        </Row>
        <p className="f6 gray mt0 mb2">
          Pricing is used to estimate a draft&apos;s cost when the vendor does not report one; local
          models are free without it.
        </p>
        {result.error && <p className="f6 red mt0 mb2">{errorMessage(result.error)}</p>}
        <Row className="justify-end">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" disabled={!idValid || result.isLoading}>
            {provider ? 'Save' : 'Add'}
          </Button>
        </Row>
      </form>
    </Modal>
  )
}
