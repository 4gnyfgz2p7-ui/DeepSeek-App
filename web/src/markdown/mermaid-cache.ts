// Mermaid 渲染结果缓存（独立模块，不引入 mermaid 本身）
// 这样纯字符串渲染路径（render.ts）不依赖任何 DOM，可以在 Node 里直接验证。

const cache = new Map<string, string>()

export function cachedMermaid(code: string): string | undefined {
  return cache.get(code)
}

export function storeMermaid(code: string, svg: string): void {
  cache.set(code, svg)
}
