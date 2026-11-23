<script setup lang="ts">
import type { HTMLAttributes } from "vue"
import { cn } from "~/lib/utils"

const props = defineProps<{ class?: HTMLAttributes["class"] }>()
</script>

<template>
  <div
    data-slot="card"
    :class="cn('flex flex-col gap-6 rounded-xl border border-border bg-background py-6 text-foreground shadow-sm', props.class)"
  >
    <slot />
  </div>
</template>
