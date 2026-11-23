// 内嵌渲染器的页面逻辑与原生桥
//
// 状态留在 JS 侧：Swift 只发增量（appendText / setThinking），
// 避免每来一个 token 就把整段历史通过桥传一遍。
// 重绘按 80ms 合并一次，既保证「看着是实时出字」，又不会让 KaTeX 每帧重排。

import { renderMarkdown, escapeHtml } from './render'
import { renderMermaid } from './markdown/mermaid'

type Role = 'user' | 'assistant'

interface Msg {
  id: string
  role: Role
  text: string
  thinking?: string
  seconds?: number | null
  streaming?: boolean
}

const state: { messages: Msg[]; dark: boolean; stick: boolean } = {
  messages: [],
  dark: true,
  stick: true,
}

const ui = { expanded: new Set<string>() }

const root = document.getElementById('root') as HTMLElement

const messagesById = new Map<string, Msg>()

function find(id: string): Msg | undefined {
  return messagesById.get(id)
}

function actionsHtml(m: Msg): string {
  return [
    '<div class="actions">',
    `<button data-action="copy-message" data-id="${m.id}" aria-label="复制">`,
    '<svg viewBox="0 0 24 24" width="15" height="15"><path d="M9 3h9a2 2 0 0 1 2 2v9" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><rect x="4" y="7" width="11" height="13" rx="2" fill="none" stroke="currentColor" stroke-width="1.7"/></svg>',
    '</button>',
    '<button data-action="regenerate" aria-label="重新生成">',
    '<svg viewBox="0 0 24 24" width="15" height="15"><path d="M20 12a8 8 0 1 1-2.3-5.6M20 4v5h-5" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    '</button>',
    '</div>',
  ].join('')
}

function thinkingHtml(m: Msg): string {
  if (!m.thinking) return ''
  const expanded = m.streaming || ui.expanded.has(m.id)
  const header = m.streaming
    ? '正在思考'
    : `已思考（用时 ${Math.max(1, Math.round(m.seconds ?? 1))} 秒）`
  const chevron = expanded ? '⌄' : '›'
  return [
    `<div class="thinking${expanded ? ' open' : ''}">`,
    `<button class="thinking-head" data-action="toggle-thinking" data-id="${m.id}">`,
    `<span>${header}</span><span class="chev">${chevron}</span>`,
    '</button>',
    expanded ? `<div class="thinking-body">${escapeHtml(m.thinking)}</div>` : '',
    '</div>',
  ].join('')
}

function messageHtml(m: Msg): string {
  if (m.role === 'user') {
    return `<div class="msg user"><div class="bubble">${escapeHtml(m.text)}</div></div>`
  }

  const body = m.text
    ? `<div class="md">${renderMarkdown(m.text, { streaming: m.streaming })}</div>`
    : m.streaming
      ? '<div class="typing"><i></i><i></i><i></i></div>'
      : ''

  return [
    `<div class="msg assistant" data-id="${m.id}">`,
    thinkingHtml(m),
    body,
    m.streaming ? '' : actionsHtml(m),
    '</div>',
  ].join('')
}

function render() {
  messagesById.clear()
  for (const message of state.messages) messagesById.set(message.id, message)

  root.innerHTML = state.messages.map(messageHtml).join('')
  void hydrateMermaid()
  if (state.stick) scrollToBottom()
}

let scheduled = false
function schedule() {
  if (scheduled) return
  scheduled = true
  window.setTimeout(() => {
    scheduled = false
    render()
  }, 80)
}

async function hydrateMermaid() {
  const nodes = Array.from(document.querySelectorAll('.mermaid-block')) as HTMLElement[]
  for (const node of nodes) {
    const code = node.dataset.mermaid ?? ''
    if (!code) continue
    if (node.querySelector('svg')) continue
    try {
      const svg = await renderMermaid(code, state.dark)
      if (svg) node.innerHTML = svg
    } catch {
      node.innerHTML = '<div class="mermaid-error">图表渲染失败</div>'
    }
  }
}

function scrollToBottom() {
  window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'auto' })
}

function isNearBottom(): boolean {
  const distance = document.documentElement.scrollHeight - window.scrollY - window.innerHeight
  return distance < 120
}

window.addEventListener(
  'scroll',
  () => {
    state.stick = isNearBottom()
  },
  { passive: true }
)

function post(payload: Record<string, unknown>) {
  const handler = (window as any).webkit?.messageHandlers?.ds
  if (handler) handler.postMessage(payload)
}

document.addEventListener('click', (event) => {
  const target = (event.target as HTMLElement | null)?.closest('[data-action]') as HTMLElement | null
  if (!target) return

  switch (target.dataset.action) {
    case 'copy-code': {
      const pre = target.closest('.code-block')?.querySelector('pre')
      post({ type: 'copy', text: pre?.textContent ?? '' })
      break
    }
    case 'copy-message': {
      const id = target.dataset.id ?? ''
      post({ type: 'copy', text: find(id)?.text ?? '' })
      break
    }
    case 'regenerate':
      post({ type: 'regenerate' })
      break
    case 'toggle-thinking': {
      const id = target.dataset.id ?? ''
      if (ui.expanded.has(id)) ui.expanded.delete(id)
      else ui.expanded.add(id)
      render()
      break
    }
    default:
      break
  }
})

const DS = {
  reset(history: Msg[] = []) {
    state.messages = history
    ui.expanded.clear()
    render()
    scrollToBottom()
  },

  addMessage(message: Msg) {
    state.messages.push(message)
    render()
  },

  setText(id: string, text: string) {
    const message = find(id)
    if (!message) return
    message.text = text
    schedule()
  },

  appendText(id: string, chunk: string) {
    const message = find(id)
    if (!message) return
    message.text += chunk
    schedule()
  },

  setThinking(id: string, text: string) {
    const message = find(id)
    if (!message) return
    message.thinking = text
    schedule()
  },

  markDone(id: string, seconds: number) {
    const message = find(id)
    if (!message) return
    message.streaming = false
    message.seconds = seconds
    render()
  },

  removeMessage(id: string) {
    const index = state.messages.findIndex((message) => message.id === id)
    if (index < 0) return
    state.messages.splice(index, 1)
    render()
  },

  scrollToBottom,

  setTheme(dark: boolean) {
    state.dark = dark
    document.documentElement.dataset.theme = dark ? 'dark' : 'light'
    render()
  },

  clear() {
    state.messages = []
    ui.expanded.clear()
    render()
  },
}

;(window as any).DS = DS
render()
