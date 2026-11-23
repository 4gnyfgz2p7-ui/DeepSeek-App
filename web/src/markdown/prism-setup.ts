// Prism 必须先于各语言包执行，语言包通过全局 Prism 注册自己
import Prism from 'prismjs'

;(globalThis as any).Prism = Prism

export default Prism
