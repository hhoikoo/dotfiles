export type Entry = {
  name: string
  description: string
  hint?: string
  source: string
  group: string
  // 1 core, always shown; 2 useful, behind "+N more"; 3 niche, search only.
  rank: number
}

export type Catalog = { entries: Entry[]; isJudging: boolean; usage: Record<string, number> }

export type Menu = {
  isOpen: boolean
  query: string
  selected: string | null
  isFilled: boolean
  expanded: string[]
}

declare module 'claude-code' {
  interface PluginState {
    'slash-menu': { catalog: Shaped<Catalog>; menu: Shaped<Menu> }
  }
}
