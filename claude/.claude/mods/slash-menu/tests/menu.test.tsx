import { expect, test } from 'claude-code/testing'

const BAND = {
  plugin: 'slash-menu',
  component: 'AbovePrompt',
  requestId: 'band',
  props: { hasSurvey: false, isWorking: false, maxRows: 20, bodyColumns: 150, scroll: { offset: 0, bodyRows: 19 }, view: {} },
} as const

const names = (prefix: string, n: number) => Array.from({ length: n }, (_, i) => `${prefix}-${String(i).padStart(2, '0')}`)
const entries = [
  ...names('chat', 20).map((name, i) => ({ name, description: `about ${name}`, source: 'builtin', group: 'chat', rank: i < 3 ? 1 : 2 })),
  ...names('model', 8).map(name => ({ name, description: `about ${name}`, source: 'builtin', group: 'model', rank: 1 })),
  ...names('code', 6).map(name => ({ name, description: `about ${name}`, source: 'builtin', group: 'code', rank: 2 })),
  { name: 'old-thing', description: '(removed) gone', source: 'builtin', group: 'legacy', rank: 3 },
]

function seed(on: any, menu: object) {
  on('state.get', (_: unknown, e: { key: string }) => {
    if (e.key === 'catalog') return { value: { value: { shape: 'catalog-3', value: { entries, isJudging: false, usage: { 'model-07': 3 } } }, version: 1 } }
    return { value: { value: { shape: 'menu-2', value: { isOpen: true, query: '', selected: null, isFilled: false, expanded: [], ...menu } }, version: 1 } }
  })
}

test('the menu fits the band and pins Frequent and the details', async ($, on) => {
  seed(on, {})
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect(await ui.find({ type: 'Text', text: /^Frequent$/ })).toBeDefined()
    expect(await ui.find({ key: 'b:model-07' })).toBeDefined()
    // The details show the first command.
    expect(await ui.find({ type: 'Text', text: /about model-07/ })).toBeDefined()
    // Legacy waits in the footer.
    expect(await ui.find({ key: 'legacy' })).toBeDefined()
    expect(await ui.find({ key: 'b:old-thing' })).toBeUndefined()
    await ui.unmount()
  }
})

test('an opened box shows its commands in columns', async ($, on) => {
  seed(on, { expanded: ['chat'] })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ key: 'b:chat-19' })).toBeDefined()
  expect(await ui.find({ key: 'less:chat' })).toBeDefined()
  await ui.unmount()
})

test('the open legacy box lists what is kept for old habits', async ($, on) => {
  seed(on, { expanded: ['legacy'] })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ key: 'b:old-thing' })).toBeDefined()
  await ui.unmount()
})
