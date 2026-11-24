<script setup lang="ts" generic="Value extends string | number | string[]">
import type { AcceptableValue } from 'reka-ui'
import { Label } from '~/components/ui/label'
import { Select, SelectContent, SelectTrigger, SelectValue } from '~/components/ui/select'

defineProps<{
  id: string
  label: string
  describedBy?: string
  disabled?: boolean
  summary?: string
  compact?: boolean
}>()

const selection = defineModel<Value>({ required: true })

function updateSelection(value: AcceptableValue | AcceptableValue[] | undefined) {
  if (value !== undefined) selection.value = value as Value
}
</script>

<template>
  <div :class="compact ? 'min-w-14' : 'grid min-w-0 gap-1.5'">
    <Label :id="id + '-label'" :for="id" :class="{ 'sr-only': compact }">{{ label }}</Label>
    <Select :model-value="selection" :multiple="Array.isArray(selection)" :disabled="disabled" @update:model-value="updateSelection">
      <SelectTrigger
        :id="id"
        :aria-labelledby="id + '-label'"
        :aria-describedby="describedBy"
        :size="compact ? 'sm' : 'default'"
        class="w-full bg-background"
      >
        <SelectValue v-if="summary !== undefined">{{ summary }}</SelectValue>
        <SelectValue v-else />
      </SelectTrigger>
      <SelectContent position="popper" :side-offset="5" class="max-h-[min(18rem,var(--reka-select-content-available-height,18rem))]">
        <slot />
      </SelectContent>
    </Select>
  </div>
</template>
