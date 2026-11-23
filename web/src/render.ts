// mdast → HTML
//
// 渲染结构参照 chat-demo 的 components/markdown（MIT），改为纯字符串输出，
// 便于在内嵌 WebView 里整段替换，不需要虚拟 DOM。
// 公式与代码高亮都带缓存：流式输出期间同一段内容会被反复渲染，
// 不做缓存的话 KaTeX 会随长度线性变慢。

import katex from 'katex'
import { toMdAst } from './markdown/parse'
import { prismLanguageName, highlightCode } from './markdown/highlight'
import { cachedMermaid } from './markdown/mermaid-cache'

const ESCAPES: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
}

export const escapeHtml = (value: string): string =>
  value.replace(/[&<>"']/g, (char) => ESCAPES[char] ?? char)

const escapeAttr = escapeHtml

const mathCache = new Map<string, string>()

function renderMath(value: string, display: boolean): string {
  const key = (display ? 'D:' : 'I:') + value
  const hit = mathCache.get(key)
  if (hit) return hit

  let html: string
  try {
    html = katex.renderToString(value, {
      displayMode: display,
      throwOnError: false,
      strict: false,
      output: 'html',
      trust: false,
    })
  } catch {
    html = `<code>${escapeHtml(value)}</code>`
  }
  mathCache.set(key, html)
  return html
}

function renderCode(node: any): string {
  const raw: string = node.value ?? ''
  const lang: string = (node.lang ?? '').trim()

  if (lang === 'mermaid') {
    const cached = cachedMermaid(raw)
    const inner = cached ?? '<div class="mermaid-pending">图表渲染中…</div>'
    return `<div class="mermaid-block" data-mermaid="${escapeAttr(raw)}">${inner}</div>`
  }

  const prismLang = prismLanguageName(lang)
  const highlighted = prismLang ? highlightCode(raw, prismLang) : null
  const body = highlighted ?? escapeHtml(raw)

  return [
    '<div class="code-block">',
    '<div class="code-head">',
    `<span class="code-lang">${escapeHtml(lang || 'text')}</span>`,
    '<button class="code-copy" data-action="copy-code">复制</button>',
    '</div>',
    `<pre><code class="language-${escapeAttr(prismLang ?? 'text')}">${body}</code></pre>`,
    '</div>',
  ].join('')
}

function renderTable(node: any): string {
  const rows: any[] = node.children ?? []
  if (rows.length === 0) return ''
  const [head, ...rest] = rows

  const cell = (tag: 'th' | 'td', c: any) =>
    `<${tag}${c.align ? ` style="text-align:${c.align}"` : ''}>${inline(c.children)}</${tag}>`

  const thead = `<thead><tr>${(head.children ?? []).map((c: any) => cell('th', c)).join('')}</tr></thead>`
  const tbody = rest.length
    ? `<tbody>${rest
        .map((row: any) => `<tr>${(row.children ?? []).map((c: any) => cell('td', c)).join('')}</tr>`)
        .join('')}</tbody>`
    : ''

  return `<div class="table-wrap"><table>${thead}${tbody}</table></div>`
}

function inline(children: any[] | undefined): string {
  return (children ?? []).map(renderInline).join('')
}

function renderInline(node: any): string {
  switch (node.type) {
    case 'text':
      return escapeHtml(node.value ?? '')
    case 'emphasis':
      return `<em>${inline(node.children)}</em>`
    case 'strong':
      return `<strong>${inline(node.children)}</strong>`
    case 'delete':
      return `<del>${inline(node.children)}</del>`
    case 'inlineCode':
      return `<code class="inline">${escapeHtml(node.value ?? '')}</code>`
    case 'inlineMath':
      return renderMath(node.value ?? '', false)
    case 'break':
      return '<br>'
    case 'link':
      return `<a href="${escapeAttr(node.url ?? '')}" target="_blank" rel="noreferrer">${inline(node.children)}</a>`
    case 'image':
      return `<img src="${escapeAttr(node.url ?? '')}" alt="${escapeAttr(node.alt ?? '')}" loading="lazy">`
    default:
      if (node.children) return inline(node.children)
      return escapeHtml(node.value ?? '')
  }
}

function renderBlock(node: any): string {
  switch (node.type) {
    case 'paragraph':
      return `<p>${inline(node.children)}</p>`
    case 'heading': {
      const depth = Math.min(Math.max(node.depth ?? 1, 1), 6)
      return `<h${depth}>${inline(node.children)}</h${depth}>`
    }
    case 'math':
      return `<div class="math-block">${renderMath(node.value ?? '', true)}</div>`
    case 'code':
      return renderCode(node)
    case 'blockquote':
      return `<blockquote>${blocks(node.children)}</blockquote>`
    case 'list': {
      const tag = node.ordered ? 'ol' : 'ul'
      const start =
        node.ordered && node.start != null && node.start !== 1 ? ` start="${node.start}"` : ''
      return `<${tag}${start}>${blocks(node.children)}</${tag}>`
    }
    case 'listItem':
      return `<li>${renderListItem(node)}</li>`
    case 'thematicBreak':
      return '<hr>'
    case 'table':
      return renderTable(node)
    case 'html':
      return escapeHtml(node.value ?? '')
    default:
      return node.children ? blocks(node.children) : ''
  }
}

function renderListItem(node: any): string {
  const children: any[] = node.children ?? []
  if ((node.spread ?? false) === false && children.length === 1 && children[0].type === 'paragraph') {
    return inline(children[0].children)
  }
  return children
    .map((child) => (child.type === 'paragraph' ? `<p>${inline(child.children)}</p>` : renderBlock(child)))
    .join('')
}

function blocks(children: any[] | undefined): string {
  return (children ?? []).map(renderBlock).join('')
}

export function renderMarkdown(input: string, options: { streaming?: boolean } = {}): string {
  if (!input) return ''

  const source = options.streaming ? closeTrailingInlineMath(input) : input

  try {
    const ast = toMdAst(source, { sources: undefined, disableLink: false })
    return blocks(ast.children)
  } catch {
    // 解析失败时至少保证内容可见，而不是整段消失
    return `<p>${escapeHtml(input)}</p>`
  }
}

/**
 * 流式输出里行内公式常常还差一个收尾的 `$`，此时解析器会把它当普通文本，
 * 屏幕上就是一段 LaTeX 源码。这里仅在流式态下补一个临时闭合符：
 * 只在尾段确实像公式（含反斜杠、上下标、花括号或等号）时才补，
 * 避免把「$100 美元」这类普通文本误当公式。
 * 块级 $$ 不需要处理 —— llm-math 扩展本身支持未闭合的块级公式。
 */
function closeTrailingInlineMath(input: string): string {
  let dollars = 0
  for (let i = 0; i < input.length; i++) {
    if (input[i] === '\\') {
      i += 1
      continue
    }
    if (input[i] === '$') dollars += 1
  }

  if (dollars % 2 === 0) return input

  const tail = input.slice(input.lastIndexOf('$') + 1)
  if (tail.includes('\n') || tail.includes('$')) return input
  if (!/[\\^_{}=]/.test(tail)) return input

  return `${input}$`
}
