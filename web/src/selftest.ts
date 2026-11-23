// 纯渲染自检：不依赖浏览器，验证解析 → 公式 → 高亮 → 表格 → 图表占位这条链路
// 运行：npx esbuild src/selftest.ts --bundle --platform=node --format=esm --outfile=/tmp/selftest.mjs && node /tmp/selftest.mjs

import { renderMarkdown } from './render'

const sample = [
  '## 二次方程求根',
  '',
  '判别式为 $\\Delta = b^2 - 4ac$，当 $\\Delta \\geq 0$ 时：',
  '',
  '$$',
  'x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}',
  '$$',
  '',
  '| 情形 | 判别式 |',
  '| --- | --- |',
  '| 两个实根 | $\\Delta > 0$ |',
  '',
  '```swift',
  'func roots(_ a: Double) -> Double { a.squareRoot() }',
  '```',
  '',
  '```mermaid',
  'flowchart LR',
  '  A --> B',
  '```',
  '',
  '1. 先算判别式',
  '2. 再判断符号',
].join('\n')

const html = renderMarkdown(sample)

const streamingPartial = renderMarkdown('当 $\\Delta = b^2 - 4a', { streaming: true })
const streamingPlain = renderMarkdown('价格 $100 美元', { streaming: true })
const unclosedCode = renderMarkdown('```python\nprint(1)')

const checks = {
  heading: html.includes('<h2>'),
  inlineMath: (html.match(/class="katex"/g) ?? []).length,
  displayMath: (html.match(/katex-display/g) ?? []).length,
  codeTokens: (html.match(/class="token /g) ?? []).length,
  table: html.includes('<table>'),
  mermaidPlaceholder: html.includes('data-mermaid='),
  orderedList: html.includes('<ol>'),
  streamingInlineMath: (streamingPartial.match(/class="katex"/g) ?? []).length,
  currencyStaysText: (streamingPlain.match(/class="katex"/g) ?? []).length === 0,
  unclosedCodeBlock: unclosedCode.includes('<pre>'),
}

console.log(checks)
console.log('html length:', html.length)

const ok =
  checks.heading &&
  checks.inlineMath >= 2 &&
  checks.displayMath >= 1 &&
  checks.codeTokens > 0 &&
  checks.table &&
  checks.mermaidPlaceholder &&
  checks.orderedList &&
  checks.streamingInlineMath >= 1 &&
  checks.currencyStaysText &&
  checks.unclosedCodeBlock

if (!ok) {
  console.error('self-check failed')
  process.exit(1)
}
console.log('self-check passed')
