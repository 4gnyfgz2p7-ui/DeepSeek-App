// 解析 Markdown，并对 LLM 流式输出做容错
//
// 移植自 deepseek-ai/chat-demo 的 src/services/markdown/parse.ts（MIT）。
// 两处扩展是关键：
//   - micromark-extension-llm-math：公式在流式输出里尚未闭合时也能解析，
//     不会先显示一串 $ 与 LaTeX 源码再突然变成公式
//   - 关闭 codeIndented：否则带前导空格的列表会被误判成缩进代码块
// 移除的部分：citation 角标替换依赖输入文本里的 [citation:N] 标记，
// 而 Messages API 把引用放在 citations_delta 里，等接引用渲染时再补。

import { fromMarkdown } from 'mdast-util-from-markdown'
import { gfmFromMarkdown } from 'mdast-util-gfm'
import { mathFromMarkdown } from 'mdast-util-math'
import { gfm } from 'micromark-extension-gfm'
import { math } from 'micromark-extension-llm-math'

export interface Source {
  index: number
  title?: string | null
  url: string
  siteName?: string | null
}

const text = (value: string) => ({ type: 'text', value })

/**
 * 解析正文，并把渲染器不单独处理的节点提前换掉：
 * - 传入 sources 时，[citation:N] 换成角标节点，找不到来源的直接去掉
 * - disableLink 时链接只保留文字
 * - 删除线保留原样的 ~ 定界符，脚注、引用式链接与定义显示原文
 */
export function toMdAst(input, { sources, disableLink } = { sources: undefined, disableLink: false }) {
  const ast = fromMarkdown(input, {
    extensions: [
      { ...gfm(), disable: { null: ['codeIndented'] } },
      math({ singleDollarTextMath: true }),
    ],
    mdastExtensions: [gfmFromMarkdown(), mathFromMarkdown()],
  })

  if (sources && sources.length > 0) {
    // 角标渲染待接：Messages API 的引用走 citations_delta，正文里没有 [citation:N] 标记
  }

  const raw = (node) => input.slice(node.position?.start.offset, node.position?.end.offset)

  const simplify = (node) => {
    if ('children' in node && Array.isArray(node.children)) {
      node.children = node.children.flatMap(simplify)
    }
    switch (node.type) {
      case 'link':
        return disableLink ? node.children : [node]
      case 'delete': {
        const delimiter = raw(node).match(/^~+/)?.[0] ?? ''
        return [text(delimiter), ...node.children, text(delimiter)]
      }
      case 'footnoteReference':
      case 'imageReference':
      case 'linkReference':
        return [text(raw(node))]
      case 'footnoteDefinition':
      case 'definition':
        return [{ type: 'paragraph', children: [text(raw(node))] }]
      default:
        return [node]
    }
  }

  simplify(ast)
  return ast
}
