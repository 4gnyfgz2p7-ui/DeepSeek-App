// 打包渲染器到 App 资源目录
//
// 产物直接提交进仓库（Sources/Resources/web），CI 里不需要 Node —— 少一个环境依赖，
// 也避免云端构建时再装一次依赖树。

import { build } from 'esbuild'
import { cp, mkdir, rm, readFile, writeFile, readdir, copyFile } from 'node:fs/promises'
import path from 'node:path'

const outDir = path.resolve('../Sources/Resources/web')

await rm(outDir, { recursive: true, force: true })
await mkdir(outDir, { recursive: true })

await build({
  entryPoints: ['src/index.ts'],
  bundle: true,
  minify: true,
  format: 'iife',
  target: ['safari17'],
  outfile: path.join(outDir, 'renderer.js'),
  legalComments: 'none',
  logLevel: 'info',
})

await cp('node_modules/katex/dist/katex.min.css', path.join(outDir, 'katex.min.css'))

// 只保留 woff2：WKWebView 全部支持，ttf/woff 是给老浏览器的回退，三份一起带会多占约 700KB
await mkdir(path.join(outDir, 'fonts'), { recursive: true })
const fontFiles = await readdir('node_modules/katex/dist/fonts')
for (const file of fontFiles.filter((name) => name.endsWith('.woff2'))) {
  await copyFile(
    path.join('node_modules/katex/dist/fonts', file),
    path.join(outDir, 'fonts', file)
  )
}

await cp('src/style.css', path.join(outDir, 'style.css'))

const html = await readFile('src/index.html', 'utf8')
await writeFile(path.join(outDir, 'index.html'), html)

// 保留上游许可证：KaTeX / Prism / Mermaid / chat-demo 均为 MIT
await writeFile(
  path.join(outDir, 'NOTICE.txt'),
  [
    'renderer.js bundles the following MIT-licensed projects:',
    '- katex (https://github.com/KaTeX/KaTeX)',
    '- prismjs (https://github.com/PrismJS/prism)',
    '- mermaid (https://github.com/mermaid-js/mermaid)',
    '- micromark / mdast utilities (https://github.com/micromark, https://github.com/syntax-tree)',
    '- parsing and rendering structure adapted from deepseek-ai/chat-demo (MIT)',
    '',
  ].join('\n')
)

console.log('renderer built →', outDir)
