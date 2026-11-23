// Mermaid 渲染：逻辑照搬 deepseek-ai/chat-demo 的 mermaid.ts（MIT），
// 只把动态 import 改成静态导入，并把渲染结果落到独立缓存模块。

import mermaid from 'mermaid'
import { cachedMermaid, storeMermaid } from './mermaid-cache'

let renderQueue: Promise<unknown> = Promise.resolve()
let nextId = 0

/** 转义图片标签，对同一图中的全部标签生效 */
const sanitize = (code: string) => code.replace(/<((?:img|image)\s+)/gi, '&lt;$1')

export { cachedMermaid }

/** 串行执行初始化与绘制，避免不同图表互相覆盖 Mermaid 的全局配置 */
export function renderMermaid(code: string, dark: boolean): Promise<string | null> {
  const hit = cachedMermaid(code)
  if (hit) return Promise.resolve(hit)

  const result = renderQueue.then(async () => {
    if (!code.trim()) return null

    mermaid.initialize({
      theme: dark ? 'dark' : 'default',
      securityLevel: 'strict',
      startOnLoad: false,
      suppressErrorRendering: true,
    })

    const { svg } = await mermaid.render(`ds-mermaid-${nextId++}`, sanitize(code))
    storeMermaid(code, svg)
    return svg
  })

  // 某张图失败不阻塞后续图表
  renderQueue = result.then(
    () => {},
    () => {}
  )
  return result as Promise<string | null>
}
