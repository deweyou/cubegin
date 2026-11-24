<script setup lang="ts">
import type { Snapshot } from 'cubegin'
import type { AsyncEngine } from 'cubegin/worker'
import type { SiteLanguage } from '#shared/utils/site-seo'
import { Button } from '~/components/ui/button'
import { Input } from '~/components/ui/input'
import { Label } from '~/components/ui/label'

const props = defineProps<{ engine: AsyncEngine, language: SiteLanguage }>()
const t = (zh: string, en: string) => props.language === 'en' ? en : zh
const algorithm = ref("R U R' U'")
const snapshot = shallowRef<Snapshot>()
const busy = ref(false)
const error = ref('')

async function apply(operation?: 'scramble' | 'solve') {
  if (busy.value) return
  busy.value = true
  error.value = ''
  try {
    let formula = algorithm.value
    if (operation === 'scramble') formula = (await props.engine.scramble(42)).algorithm
    if (operation === 'solve') {
      const current = await props.engine.evaluate(formula)
      formula = [formula, await props.engine.solve(current.facelets)].filter(Boolean).join(' ')
    }
    snapshot.value = await props.engine.evaluate(formula)
    algorithm.value = formula
  } catch (failure) {
    error.value = failure instanceof Error ? failure.message : String(failure)
  } finally {
    busy.value = false
  }
}

function open(expanded: boolean) {
  if (expanded && !snapshot.value) void apply()
}
</script>

<template>
  <PlaygroundDisclosure id="legacy" class="basic-api" :label="t('三阶基础 API', 'Basic 3×3×3 API')" @update:open="open">
    <form class="grid gap-2" @submit.prevent="apply()">
      <Label for="basic-algorithm">{{ t('基础 API 公式', 'Algorithm') }}</Label>
      <Input id="basic-algorithm" v-model="algorithm" class="bg-background font-mono" spellcheck="false" :disabled="busy" />
      <div class="flex flex-wrap gap-2">
        <Button size="sm" type="submit" :disabled="busy">{{ t('应用公式', 'Apply') }}</Button>
        <Button size="sm" variant="secondary" type="button" :disabled="busy" @click="apply('scramble')">{{ t('打乱 · 种子 42', 'Scramble · seed 42') }}</Button>
        <Button size="sm" variant="secondary" type="button" :disabled="busy || !snapshot" @click="apply('solve')">{{ t('求解', 'Solve') }}</Button>
      </div>
    </form>
    <p id="status" role="status">{{ snapshot ? (snapshot.solved ? t('已还原', 'Solved') : t('未还原', 'Scrambled')) : t('正在加载…', 'Loading…') }}</p>
    <p v-if="error" id="error" role="alert">{{ error }}</p>
    <div id="diagram" v-html="snapshot?.svg ?? ''" />
    <p id="state" class="break-all font-mono">{{ snapshot?.facelets }}</p>
  </PlaygroundDisclosure>
</template>

<style scoped>
.basic-api { margin-top: .75rem; padding: .75rem; border: 1px solid var(--border); border-radius: .6rem; }
.basic-api form, #status { margin-top: .75rem; }
#diagram { width: min(100%, 22rem); }
#diagram :deep(svg) { width: 100%; height: auto; }
#error { color: var(--destructive); }
</style>
