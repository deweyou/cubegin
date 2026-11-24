import MarkdownIt from 'markdown-it'
import privacyPolicy from '../../../../docs/privacy-policy.md?raw'

const [chinese, english, ...extra] = privacyPolicy.split('<!-- English -->')
if (!chinese?.trim() || !english?.trim() || extra.length > 0) {
  throw new Error('privacy-policy.md must contain Chinese and English sections.')
}

const markdown = new MarkdownIt({ html: false })

function renderPolicy(source: string) {
  const body = source.trim()
  const titleLine = body.match(/^# ([^\r\n]+)\r?\n/)
  if (!titleLine?.[1]) {
    throw new Error('Each privacy policy language must start with a level-one heading.')
  }

  const environment = {}
  const tokens = markdown.parse(body.slice(titleLine[0].length), environment)
  let sectionNumber = 0

  for (const token of tokens) {
    if (token.type === 'heading_open' && token.tag === 'h2') {
      sectionNumber += 1
      token.attrSet('id', 'section-' + sectionNumber)
    }
  }

  return {
    title: titleLine[1],
    html: markdown.renderer.render(tokens, markdown.options, environment),
  }
}

export const policies = {
  'zh-Hans': renderPolicy(chinese),
  en: renderPolicy(english),
}

export type PolicyLanguage = keyof typeof policies
