// 代码高亮：语言与别名映射照搬 deepseek-ai/chat-demo 的 highlight.ts（MIT）。
// 原实现对每种语言做动态 import 以减小首屏体积；内嵌到 App 里没有首屏概念，
// 因此改为静态导入，打包成单文件，逻辑保持一致。

import Prism from './prism-setup'

import 'prismjs/components/prism-markup-templating'
import 'prismjs/components/prism-json'
import 'prismjs/components/prism-jsx'
import 'prismjs/components/prism-typescript'
import 'prismjs/components/prism-tsx'
import 'prismjs/components/prism-bash'
import 'prismjs/components/prism-python'
import 'prismjs/components/prism-swift'
import 'prismjs/components/prism-go'
import 'prismjs/components/prism-rust'
import 'prismjs/components/prism-java'
import 'prismjs/components/prism-c'
import 'prismjs/components/prism-cpp'
import 'prismjs/components/prism-csharp'
import 'prismjs/components/prism-sql'
import 'prismjs/components/prism-yaml'
import 'prismjs/components/prism-toml'
import 'prismjs/components/prism-markdown'
import 'prismjs/components/prism-diff'
import 'prismjs/components/prism-docker'
import 'prismjs/components/prism-kotlin'
import 'prismjs/components/prism-ruby'
import 'prismjs/components/prism-php'

const aliases: Record<string, string> = {
  html: 'markup',
  xml: 'markup',
  vue: 'markup',
  js: 'javascript',
  ts: 'typescript',
  shell: 'bash',
  sh: 'bash',
  zsh: 'bash',
  'c++': 'cpp',
  cc: 'cpp',
  cplusplus: 'cpp',
  cs: 'csharp',
  'c#': 'csharp',
  dockerfile: 'docker',
  golang: 'go',
  hs: 'haskell',
  kt: 'kotlin',
  tex: 'latex',
  mk: 'makefile',
  md: 'markdown',
  objc: 'objectivec',
  py: 'python',
  rb: 'ruby',
  rs: 'rust',
  yml: 'yaml',
}

/** 代码块语言名 → Prism 语言名；不支持时返回 null，按纯文本显示 */
export function prismLanguageName(infostring: string): string | null {
  const key = infostring.trim().toLowerCase()
  if (!key) return null
  const lang = Object.prototype.hasOwnProperty.call(aliases, key) ? aliases[key] : key
  return Object.prototype.hasOwnProperty.call(Prism.languages, lang) ? lang : null
}

export function highlightCode(code: string, lang: string): string | null {
  const grammar = Prism.languages[lang]
  if (!grammar) return null
  try {
    return Prism.highlight(code, grammar, lang)
  } catch {
    return null
  }
}
