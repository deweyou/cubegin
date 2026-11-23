<script setup lang="ts">
import type { HTMLAttributes } from "vue"
import { cn } from "~/lib/utils"

const props = defineProps<{ class?: HTMLAttributes["class"] }>()
const modelValue = defineModel<string>({ required: true })
</script>

<template>
  <input
    v-model="modelValue"
    data-slot="input"
    :class="cn(
      'h-9 w-full min-w-0 rounded-md border border-input bg-transparent px-3 py-1 text-base shadow-xs outline-none transition-[color,box-shadow] placeholder:text-muted-foreground selection:bg-primary selection:text-primary-foreground md:text-sm',
      'focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 aria-invalid:border-destructive aria-invalid:ring-destructive/20 disabled:pointer-events-none disabled:opacity-50',
      props.class,
    )"
  >
</template>
