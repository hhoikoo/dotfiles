import { atom, read, update } from 'claude-code'
import type { EngineInterface as Engine, Register } from 'claude-code'

import type { Catalog, Entry, Menu } from '../types'

// ── groups ────────────────────────────────────────────────────────────────

const GROUPS = [
  { id: 'chat', label: 'Chat & session', hint: 'the conversation and the session: clear, compact, context, resume, rewind, branch, export, exit, restart, moving to cloud/desktop/phone, directories, handoff' },
  { id: 'model', label: 'Model & settings', hint: 'model, effort, fast/plan/voice modes, permissions, sandbox, the settings menu, theme, status line, keybindings, terminal/IDE' },
  { id: 'code', label: 'Code & agents', hint: 'reviewing, verifying, running and initialising code, PRs, subagents, background tasks, loops, schedules, workflows, research' },
  { id: 'docs', label: 'Docs & design', hint: 'documents, office files, slides, design, artifacts, charts' },
  { id: 'extend', label: 'Skills & extensions', hint: "plugins, MCP, hooks, skills, memory/CLAUDE.md, config files, the API, and the user's own personal skills (teaching, setup, handoff)" },
  { id: 'help', label: 'Help & account', hint: 'help, status, usage, feedback, login, plan, promos, and anything that fits nowhere else' },
  { id: 'legacy', label: 'Legacy & compat', hint: 'removed, renamed, deprecated or alias commands kept only for old habits' },
] as const

const GROUP_IDS: readonly string[] = GROUPS.map(g => g.id)

// Where built-ins go until Opus has judged them (the first open after an
// update, for a few seconds).
const STATIC: Record<string, string> = {}
function put(group: string, names: string) {
  for (const name of names.split(' ')) STATIC[name] = group
}
put('chat', 'clear compact context resume rewind branch fork rename export copy recap btw goal autocompact focus exit restart background cd add-dir teleport desktop mobile remote-control send-to-project remote-env web-setup')
put('model', 'model effort fast plan advisor voice output-style permissions sandbox auto-mode-setup fewer-permission-prompts config theme color statusline keybindings tui scroll-speed ide chrome privacy-settings')
put('code', 'code-review security-review simplify verify run run-skill-generator init autofix-pr diff tasks list-agents subtask loop schedule batch workflows workflow-authoring deep-research')
put('docs', 'docs docx pdf pptx xlsx slides design design-sync design-login artifacts artifact-capabilities artifact-diagramming dataviz google-workspace')
put('extend', 'plugin reload-plugins mcp hooks skills reload-skills skill-creator skill-doctor plugin-authoring claude-api update-config memory import import-memory')
put('help', 'help doctor status usage usage-credits insights release-notes feedback debug login logout upgrade rate-limit-options powerup passes stickers radio install-github-app install-slack-app team-onboarding')

// Kept for compatibility: what replaced each.
const LEGACY: Record<string, string> = {
  agents: 'removed: ask Claude, or use /list-agents',
  'extra-usage': 'renamed to /usage-credits',
  ultrareview: 'alias of /code-review ultra',
  bug: 'old name of /feedback',
  'terminal-setup': 'only needed on terminals without Shift+Enter',
}
const LEGACY_TEXT = /^\s*\((removed|deprecated|legacy)\)|\b(renamed to|deprecated|alias (of|for))\b/i

const FREQUENT = 6

// ── state ─────────────────────────────────────────────────────────────────

const catalogA = atom(
  { plugin: 'slash-menu', key: 'catalog' } as const,
  { entries: [], isJudging: false, usage: {} },
  { shape: 'catalog-3' },
)
const menuA = atom(
  { plugin: 'slash-menu', key: 'menu' } as const,
  { isOpen: false, query: '', selected: null, isFilled: false, expanded: [] },
  { shape: 'menu-2' },
)

type Judged = { group: string; rank: number }
type Cache = { version: string; judged: Record<string, Judged> }
const CACHE_KEY = 'judged-2'

// Facts command.describe hands us as the engine lists commands; refilled on
// every listing, so a reload losing them costs nothing.
const described = new Map<string, { isHidden: boolean; hint?: string }>()
let refreshing: Promise<void> | null = null

function isMenuText(text: string): boolean {
  return /^\/[^\s]*$/.test(text)
}

function labelOf(id: string): string {
  return GROUPS.find(g => g.id === id)?.label ?? 'Other'
}

// ── catalog ───────────────────────────────────────────────────────────────

async function refresh($: Engine) {
  if (refreshing) return refreshing
  refreshing = build($).finally(() => {
    refreshing = null
  })
  return refreshing
}

type Raw = { name: string; description: string; source: string; hint?: string; isLegacy: boolean }

async function build($: Engine) {
  const [list, version] = await Promise.all([$.command.list(), $.session.version()])
  const stored = (await $.store.get(CACHE_KEY)) as Cache | undefined
  // A new Claude Code version can add, rename or retire commands: judge afresh.
  const cache: Cache = stored && stored.version === version.version ? stored : { version: version.version, judged: {} }
  const usage = ((await $.store.get('usage')) ?? {}) as Record<string, number>

  const raws: Raw[] = []
  for (const c of list) {
    if (c.name.startsWith('__')) continue
    const facts = described.get(c.name)
    const isLegacy = c.name in LEGACY || LEGACY_TEXT.test(c.description)
    // Hidden by the engine itself (internal, plan-specific) unless it is a
    // retired command people may still type.
    if (facts?.isHidden && !isLegacy) continue
    raws.push({
      name: c.name,
      description: LEGACY[c.name] ? `${c.description} (${LEGACY[c.name]})` : c.description,
      source: c.source,
      hint: facts?.hint,
      isLegacy,
    })
  }

  const toEntries = (): Entry[] =>
    raws.map(r => {
      const j = r.isLegacy ? { group: 'legacy', rank: 3 } : cache.judged[r.name]
      return {
        name: r.name,
        description: r.description,
        hint: r.hint,
        source: r.source,
        group: j?.group ?? STATIC[r.name] ?? 'help',
        rank: j?.rank ?? 2,
      }
    })

  const unjudged = raws.filter(r => !r.isLegacy && !cache.judged[r.name])
  await setCatalog($, { entries: toEntries(), isJudging: unjudged.length > 0, usage })
  if (unjudged.length === 0) return

  // Everything at once after an update, so importance is weighed across the
  // whole set; only the newcomers when a skill is added.
  const known = Object.entries(cache.judged)
    .filter(([, j]) => j.rank === 1)
    .map(([name]) => name)
  const verdicts = await judge($, unjudged, known)
  for (const r of unjudged) cache.judged[r.name] = verdicts[r.name] ?? { group: STATIC[r.name] ?? 'help', rank: 2 }
  await $.store.set(CACHE_KEY, cache)
  await setCatalog($, { entries: toEntries(), isJudging: false, usage })
}

async function setCatalog($: Engine, next: Catalog) {
  await update($, catalogA, old => (JSON.stringify(old) === JSON.stringify(next) ? old : next))
}

async function judge($: Engine, items: Raw[], coreAlready: string[]): Promise<Record<string, Judged>> {
  const groups = GROUPS.filter(g => g.id !== 'legacy')
    .map(g => `- ${g.id}: ${g.hint}`)
    .join('\n')
  const lines = items.map(i => `- ${i.name} [${i.source === 'builtin' ? 'built-in' : i.source === 'user' ? "user's own skill" : i.source}]: ${i.description.slice(0, 240)}`).join('\n')
  const prompt =
    `These are slash commands and skills in Claude Code, shown in a menu grouped into boxes. ` +
    `For each, pick its group and judge how important it is to a developer using Claude Code day to day.\n\n` +
    `Groups:\n${groups}\n\n` +
    `Importance:\n` +
    `1 = core: people reach for it often or it is essential to know (e.g. clear, compact, model, resume). Keep it rare: at most about 20 across all commands, 2 to 5 per group.\n` +
    `2 = useful sometimes: worth a click to find.\n` +
    `3 = niche, one-off setup, promotional, or almost never needed (e.g. stickers, passes, install-slack-app).\n` +
    `A user's own skill is usually 1 or 2: they made it for a reason.\n` +
    (coreAlready.length ? `Already judged core: ${coreAlready.join(', ')}.\n` : '') +
    `\nCommands:\n${lines}\n\n` +
    `Answer with one JSON object only, mapping each command name to [groupId, importance], e.g. {"clear":["conversation",1]}. No prose.`
  try {
    const r = await $.model.complete({ model: 'opus', prompt, maxTokens: 8000, effort: 'medium', timeoutMs: 180000 })
    if (!r.isAnswered) {
      $.ui.log(`slash-menu: judging skipped (${r.reason})`)
      return {}
    }
    const parsed = JSON.parse(r.text.slice(r.text.indexOf('{'), r.text.lastIndexOf('}') + 1)) as Record<string, unknown>
    const out: Record<string, Judged> = {}
    for (const i of items) {
      const v = parsed[i.name]
      if (!Array.isArray(v)) continue
      const group = typeof v[0] === 'string' && GROUP_IDS.includes(v[0]) ? v[0] : 'help'
      const rank = v[1] === 1 || v[1] === 2 || v[1] === 3 ? v[1] : 2
      out[i.name] = { group, rank }
    }
    return out
  } catch (err) {
    $.ui.log(`slash-menu: judging failed: ${String(err)}`)
    return {}
  }
}

// ── filtering and layout ──────────────────────────────────────────────────

type Item = Entry & { isWeak: boolean }
// Every command that belongs in the box, best first, and how many it shows
// while nobody has asked for more.
type Group = { id: string; label: string; all: Item[]; preferred: number }

function groups(entries: Entry[], usage: Record<string, number>, query: string): Group[] {
  const q = query.toLowerCase()
  const out: Group[] = []

  if (q === '') {
    // What the person runs most, kept out of the boxes below.
    const frequent = entries
      .filter(e => e.group !== 'legacy' && (usage[e.name] ?? 0) > 0)
      .sort((a, b) => (usage[b.name] ?? 0) - (usage[a.name] ?? 0) || a.name.localeCompare(b.name))
      .slice(0, FREQUENT)
      .map(e => ({ ...e, isWeak: false }))
    out.push({ id: 'frequent', label: 'Frequent', all: frequent, preferred: frequent.length })
    const taken = new Set(frequent.map(e => e.name))
    entries = entries.filter(e => !taken.has(e.name))
  }

  for (const g of GROUPS) {
    const all = entries
      .filter(e => e.group === g.id)
      .map(e => {
        const name = e.name.toLowerCase()
        const match = q === '' ? 1 : name.startsWith(q) ? 0 : name.includes(q) ? 1 : q.length >= 3 && e.description.toLowerCase().includes(q) ? 2 : -1
        return { e, match }
      })
      .filter(x => x.match >= 0)
      .sort((a, b) => a.match - b.match || a.e.rank - b.e.rank || a.e.name.localeCompare(b.e.name))
      .map(x => ({ ...x.e, isWeak: x.match === 2 }))
    if (all.length === 0) continue
    // Searching shows every match; otherwise a box shows its core commands,
    // and never shows empty: its two most important stand in.
    const core = all.filter(x => x.rank === 1).length
    const preferred = q !== '' ? all.length : core >= 2 || g.id === 'legacy' ? core : Math.min(2, all.filter(x => x.rank < 3).length)
    out.push({ id: g.id, label: g.label, all, preferred })
  }
  return out
}

// ── layout ────────────────────────────────────────────────────────────────
// Everything is sized to fit the band, so it never scrolls: the Frequent
// strip and the details stay in view. Render and the arrow keys share it.

type Shown = { g: Group; items: Item[]; more: number; isWide: boolean; perColumn: number; subColumns: number }
type LayoutRow = { boxes: Shown[]; height: number; top: number }
type Spot = { name: string; x: number; y: number }
type Layout = { strip: Group | undefined; rows: LayoutRow[]; boxW: number; spots: Spot[]; first: string | undefined; legacy: Group | undefined }

const STRIP_ROWS = 3
const FOOTER_ROWS = 1
const SUB_W = 24

function shownRows(s: Shown): number {
  // Border two, the title (which carries "+N" or "fewer"), the commands.
  return 3 + (s.isWide ? s.perColumn : s.items.length)
}

function layout(c: Catalog, m: Menu, leftW: number, maxRows: number): Layout {
  const gs = groups(c.entries, c.usage, m.query)
  const strip = gs[0]?.id === 'frequent' ? gs[0] : undefined
  const openId = m.expanded[0]
  // Legacy is a link in the footer until opened or searched.
  const boxesAll = gs.filter(g => g.id !== 'frequent' && (g.id !== 'legacy' || openId === 'legacy' || m.query !== ''))
  const n = leftW >= 96 ? 3 : leftW >= 64 ? 2 : 1
  const boxW = Math.floor((leftW - (n - 1)) / n)
  const room = Math.max(6, maxRows - FOOTER_ROWS - (strip ? STRIP_ROWS : 0))

  // One box at a time opens up: it spans the left side, its commands in
  // columns.
  const subColumns = Math.max(1, Math.floor((leftW - 4) / SUB_W))

  const build = (cap: number, wideCap: number): LayoutRow[] => {
    const rows: LayoutRow[] = []
    let pair: Shown[] = []
    const flush = () => {
      if (pair.length) rows.push({ boxes: pair, height: Math.max(...pair.map(shownRows)), top: 0 })
      pair = []
    }
    for (const g of boxesAll) {
      if (g.id === openId) {
        flush()
        const perColumn = Math.max(1, Math.min(wideCap, Math.ceil(g.all.length / subColumns)))
        const items = g.all.slice(0, perColumn * subColumns)
        const wide: Shown = { g, items, more: g.all.length - items.length, isWide: true, perColumn, subColumns }
        rows.push({ boxes: [wide], height: shownRows(wide), top: 0 })
        continue
      }
      const items = g.all.slice(0, Math.min(g.preferred, cap))
      pair.push({ g, items, more: g.all.length - items.length, isWide: false, perColumn: items.length, subColumns: 1 })
      if (pair.length === n) flush()
    }
    flush()
    let top = 0
    for (const r of rows) {
      r.top = top
      top += r.height
    }
    return rows
  }

  const total = (rows: LayoutRow[]) => rows.reduce((sum, r) => sum + r.height, 0)
  // The biggest lists that still fit: shrink the open box first, then every box.
  let cap = 99
  let wideCap = 99
  let rows = build(cap, wideCap)
  while (total(rows) > room) {
    const open = rows.flatMap(r => r.boxes).find(b => b.isWide)
    const tallest = Math.max(0, ...rows.flatMap(r => r.boxes.filter(b => !b.isWide).map(b => b.items.length)))
    // The box the person opened keeps its room longest.
    if (tallest > 1) cap = tallest - 1
    else if (open && open.perColumn > 1) wideCap = open.perColumn - 1
    else break
    rows = build(cap, wideCap)
  }

  // Where each command is drawn, in reading order: the strip, then each row's
  // boxes left to right, a box top to bottom (an open box column by column).
  const spots: Spot[] = []
  if (strip) {
    let x = 2 + 'Frequent'.length + 3
    for (const it of strip.all) {
      spots.push({ name: it.name, x, y: 1 })
      x += it.name.length + ` ${c.usage[it.name] ?? 0}×`.length + 3
    }
  }
  const y0 = strip ? STRIP_ROWS : 0
  for (const r of rows) {
    r.boxes.forEach((s, ci) => {
      s.items.forEach((it, i) => {
        if (s.isWide) {
          const col = Math.floor(i / s.perColumn)
          spots.push({ name: it.name, x: 2 + col * Math.floor((leftW - 4) / s.subColumns), y: y0 + r.top + 2 + (i % s.perColumn) })
        } else {
          spots.push({ name: it.name, x: ci * (boxW + 1) + 2, y: y0 + r.top + 2 + i })
        }
      })
    })
  }
  // The highlighted command when none is picked: the first in group order.
  const first = strip?.all[0]?.name ?? boxesAll.flatMap(g => g.all)[0]?.name
  const legacy = boxesAll.some(g => g.id === 'legacy') ? undefined : gs.find(g => g.id === 'legacy')
  return { strip, rows, boxW, spots, first, legacy }
}

// The band's size as last drawn: moves are made on that layout.
let lastLeftW = 100
let lastMaxRows = 30

type Dir = 'up' | 'down' | 'left' | 'right'

function step(c: Catalog, m: Menu, dir: Dir): string | undefined {
  const { spots, first } = layout(c, m, lastLeftW, lastMaxRows)
  if (spots.length === 0) return undefined
  const here = spots.find(s => s.name === m.selected) ?? spots.find(s => s.name === first) ?? spots[0]
  if (!here) return undefined
  if (dir === 'up' || dir === 'down') {
    const at = spots.indexOf(here)
    return spots[(at + (dir === 'down' ? 1 : -1) + spots.length) % spots.length]?.name
  }
  // ← and →: the nearest command on that side, same line first; past the
  // edge, round to the far side.
  const sign = dir === 'right' ? 1 : -1
  const near = (pool: Spot[]) =>
    pool.sort((a, b) => Math.abs(a.y - here.y) - Math.abs(b.y - here.y) || Math.abs(a.x - here.x) - Math.abs(b.x - here.x))[0]
  const side = spots.filter(s => (s.x - here.x) * sign > 0)
  const sameRowBand = side.filter(s => Math.abs(s.y - here.y) <= 1)
  const target = near(sameRowBand.length ? sameRowBand : side)
  if (target) return target.name
  const farX = sign > 0 ? Math.min(...spots.map(s => s.x)) : Math.max(...spots.map(s => s.x))
  return near(spots.filter(s => s.x === farX && s !== here))?.name
}

function firstShown(c: Catalog, query: string): Entry | undefined {
  const gs = groups(c.entries, c.usage, query)
  return gs.flatMap(g => g.all)[0]
}

// ── menu actions ──────────────────────────────────────────────────────────

async function syncFromText($: Engine, text: string) {
  if (isMenuText(text)) {
    const query = text.slice(1)
    await update($, menuA, m => (m.isOpen && m.query === query && !m.isFilled ? m : { ...m, isOpen: true, query, selected: null, isFilled: false }))
    void refresh($)
  } else {
    await update($, menuA, m => (m.isOpen ? { ...m, isOpen: false, isFilled: false, selected: null } : m))
  }
}

// The picked command goes in the box with the caret right after its slash:
// from there ← and → are both moves the prompt reports, so they reach us.
async function pick($: Engine, name: string) {
  await update($, menuA, m => ({ ...m, selected: name, isFilled: true }))
}

async function pickAndFill($: Engine, name: string) {
  await pick($, name)
  await $.prompt.fill({ text: `/${name}`, cursor: 1 })
}

async function moveBy($: Engine, dir: Dir) {
  const m = await read($, menuA)
  if (!m.isOpen) return
  const name = step(await read($, catalogA), m, dir)
  if (name) await pickAndFill($, name)
}

async function countRun($: Engine, command: string) {
  const usage = ((await $.store.get('usage')) ?? {}) as Record<string, number>
  usage[command] = (usage[command] ?? 0) + 1
  await $.store.set('usage', usage)
  await update($, catalogA, c => ({ ...c, usage }))
}

// ── hooks ─────────────────────────────────────────────────────────────────

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const r = await next(e)
    if (e.isInteractive) void refresh($)
    return r
  })

  // Count what the person runs, for the Frequent box.
  on('command.run', async ($, e, next) => {
    // Counted on the side, so a failed write never holds the command up.
    if (e.origin.kind === 'composer') void countRun($, e.command).catch(() => {})
    return next(e)
  })

  // Take every command out of the engine's own list; each still runs when
  // typed in full. The grouped menu above the prompt lists them instead.
  on('command.describe', async ($, e, next) => {
    const r = await next(e)
    described.set(e.command, { isHidden: r.isHidden, hint: r.argumentHint })
    return { ...r, isHidden: true }
  })

  on('prompt.edit', async ($, e, next) => {
    const m = await read($, menuA)
    const arrow = e.key && !e.key.ctrl && (e.key.key === 'left' || e.key.key === 'right') ? e.key.key : undefined

    // ← and → (bare or with ⌥) step between the boxes while the menu is up.
    if (m.isOpen && arrow && isMenuText(e.text)) {
      const name = step(await read($, catalogA), m, arrow)
      if (name) {
        await pick($, name)
        return { text: `/${name}`, cursor: 1 }
      }
    }

    // After a move the box holds the picked command; typing keeps editing the
    // search the person typed, not the picked name.
    if (m.isOpen && m.isFilled && m.selected && e.text === `/${m.selected}`) {
      const isMove = e.inputText === '' && e.start === e.end
      if (/[\s/]/.test(e.inputText)) {
        // Arguments follow the command, wherever the caret was.
        const text = `/${m.selected}${e.inputText}`
        await syncFromText($, text)
        return { text, cursor: text.length }
      }
      if (!isMove) {
        const query = e.inputText !== '' ? m.query + e.inputText : m.query.slice(0, -1)
        const text = e.inputText === '' && m.query === '' ? '' : `/${query}`
        await syncFromText($, text)
        return { text, cursor: text.length }
      }
    }
    const r = await next(e)
    await syncFromText($, r.text)
    return r
  })

  on('prompt.change', async ($, e, next) => {
    const r = await next(e)
    // Our own fill already set the menu.
    if (!(e.origin.kind === 'plugin' && e.origin.name === 'slash-menu')) await syncFromText($, e.text)
    return r
  })

  // The engine's own list is empty, so it would say "No commands match".
  // Offer the best match as its one row instead: Tab takes it. A picked
  // command is typed in full, and the engine shows its own row for it.
  on('prompt.autocomplete', { token: /^\// }, async ($, e, next) => {
    const r = await next(e)
    if (e.start !== 0 || !isMenuText(e.text)) return r
    const c = await read($, catalogA)
    const typed = e.text.slice(1)
    if (c.entries.some(x => x.name === typed)) return r
    const best = firstShown(c, typed)
    if (!best) return r
    return { suggestions: [{ text: `/${best.name}`, label: `/${best.name}`, description: best.description }, ...r.suggestions] }
  })

  // The keys, under the prompt while the menu is up.
  on('ui.render', { component: 'PromptHint' }, async ($, e, next) => {
    const m = await read($, menuA)
    if (!m.isOpen) return next(e)
    return next({ ...e, props: { ...e.props, tail: '  ⌥↑ ⌥↓ ← → move · ⏎ run · tab complete · hover for details' } })
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const m = await read($, menuA)
    if (!m.isOpen || e.props.hasSurvey) return next(e)

    const { Box, Button, Text } = $.ui.resolve(e)
    const catalog = await read($, catalogA)
    const cols = e.props.bodyColumns
    // Boxes take the left two thirds, the details the right third.
    const leftW = Math.floor((cols * 2) / 3)
    const panelW = cols - leftW - 1
    lastLeftW = leftW
    lastMaxRows = e.props.maxRows
    const lay = layout(catalog, m, leftW, e.props.maxRows)
    const shownNames = new Set(lay.spots.map(s => s.name))
    const byName = new Map(catalog.entries.map(x => [x.name, x]))
    const current = byName.get(m.selected && shownNames.has(m.selected) ? m.selected : (lay.first ?? ''))
    const gridH = lay.rows.reduce((sum, r) => sum + r.height, 0)
    const panelH = Math.max(6, Math.min(14, gridH))

    const details = (x: Entry) => (
      <>
        <Text bold>
          /{x.name}
          {x.hint ? <Text dimColor> {x.hint}</Text> : null}
        </Text>
        <Text wrap="wrap">{x.description}</Text>
        <Text> </Text>
        <Text dimColor>
          {labelOf(x.group)} · {x.source === 'builtin' ? 'built-in' : x.source === 'user' ? 'your skill' : x.source}
        </Text>
      </>
    )

    // The picked command's details; each other command's are stacked over
    // them, shown only while the pointer is on its name.
    const panel = (
      <Box flexDirection="column" width={panelW} height={panelH} borderStyle="round" borderColor="inactive" paddingX={1} overflow="hidden">
        {current ? details(current) : <Text dimColor>No commands match “{m.query}”.</Text>}
        {[...shownNames]
          .filter(name => name !== current?.name)
          .map(name => {
            const x = byName.get(name)
            return x ? (
              <Box
                key={`d:${x.name}`}
                position="absolute"
                top={0}
                left={0}
                width={panelW - 4}
                height={panelH - 2}
                flexDirection="column"
                display="none"
                backgroundColor="black"
                hover={{ scope: `c:${x.name}`, display: 'flex' }}
              >
                {details(x)}
              </Box>
            ) : null
          })}
      </Box>
    )

    const name = (x: Item) =>
      x.name === current?.name ? (
        <Text inverse>{x.name}</Text>
      ) : x.source === 'user' ? (
        <Text color="suggestion">{x.name}</Text>
      ) : x.isWeak || x.group === 'legacy' ? (
        <Text dimColor>{x.name}</Text>
      ) : (
        x.name
      )

    const entry = (x: Item, width?: number) => (
      <Box key={`i:${x.name}`} width={width} flexShrink={0} hover={{ scope: `c:${x.name}`, backgroundColor: '#333333' }}>
        <Button key={`b:${x.name}`} plain onPress={() => pickAndFill($, x.name)}>
          {name(x)}
        </Button>
      </Box>
    )

    const toggle = (s: Shown) =>
      s.isWide ? (
        <Button key={`less:${s.g.id}`} plain dimColor onPress={() => update($, menuA, v => ({ ...v, expanded: [] }))}>
          {s.more > 0 ? `▾ fewer (${s.more} more when searched)` : '▾ fewer'}
        </Button>
      ) : s.more > 0 ? (
        <Button key={`more:${s.g.id}`} plain dimColor onPress={() => update($, menuA, v => ({ ...v, expanded: [s.g.id] }))}>
          {`+${s.more} ▸`}
        </Button>
      ) : null

    const box = (s: Shown, height: number) => {
      const subW = Math.floor((leftW - 4) / s.subColumns)
      return (
        <Box
          key={`g:${s.g.id}`}
          flexDirection="column"
          width={s.isWide ? leftW : lay.boxW}
          height={height}
          borderStyle="round"
          borderColor={s.items.some(x => x.name === current?.name) ? 'claude' : 'inactive'}
          paddingX={1}
        >
          <Box flexDirection="row" justifyContent="space-between">
            <Text bold color={s.g.id === 'legacy' ? 'inactive' : 'claude'} wrap="truncate-end">
              {s.g.label}
            </Text>
            {toggle(s)}
          </Box>
          {s.isWide ? (
            <Box flexDirection="row">
              {Array.from({ length: s.subColumns }, (_, k) => (
                <Box key={`sub:${s.g.id}:${k}`} flexDirection="column" width={subW}>
                  {s.items.slice(k * s.perColumn, (k + 1) * s.perColumn).map(x => entry(x, subW - 1))}
                </Box>
              ))}
            </Box>
          ) : (
            s.items.map(x => entry(x))
          )}
        </Box>
      )
    }

    // Frequent: one row across the whole width.
    const strip = lay.strip ? (
      <Box
        flexDirection="row"
        width={cols}
        height={STRIP_ROWS}
        borderStyle="round"
        borderColor={lay.strip.all.some(x => x.name === current?.name) ? 'claude' : 'inactive'}
        paddingX={1}
        columnGap={3}
        overflow="hidden"
      >
        <Text bold color="claude">
          Frequent
        </Text>
        {lay.strip.all.length === 0 ? <Text dimColor>fills as you run commands</Text> : null}
        {lay.strip.all.map(x => (
          <Box key={`i:${x.name}`} flexShrink={0} hover={{ scope: `c:${x.name}`, backgroundColor: '#333333' }}>
            <Button key={`b:${x.name}`} plain onPress={() => pickAndFill($, x.name)}>
              {name(x)}
              <Text dimColor> {catalog.usage[x.name]}×</Text>
            </Button>
          </Box>
        ))}
      </Box>
    ) : null

    return (
      <Box flexDirection="column" width={cols}>
        {strip}
        <Box flexDirection="row" columnGap={1}>
          <Box flexDirection="column" width={leftW}>
            {lay.rows.map((row, ri) => (
              <Box key={`row:${ri}`} flexDirection="row" columnGap={1}>
                {row.boxes.map(s => box(s, row.height))}
              </Box>
            ))}
          </Box>
          {panel}
        </Box>
        <Box flexDirection="row" columnGap={2} height={FOOTER_ROWS}>
          <Button key="up" plain dimColor action="app:diffFileListUp" onPress={() => moveBy($, 'up')}>
            ⌥↑ up
          </Button>
          <Button key="down" plain dimColor action="app:diffFileListDown" onPress={() => moveBy($, 'down')}>
            ⌥↓ down
          </Button>
          {lay.legacy ? (
            <Button key="legacy" plain dimColor onPress={() => update($, menuA, v => ({ ...v, expanded: ['legacy'] }))}>
              ▸ legacy & compat ({lay.legacy.all.length})
            </Button>
          ) : null}
          {catalog.isJudging ? <Text dimColor>Opus is sorting the commands…</Text> : null}
        </Box>
      </Box>
    )
  })
}
