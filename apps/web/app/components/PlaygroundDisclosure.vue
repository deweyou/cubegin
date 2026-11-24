<script setup lang="ts">
import { ChevronDown } from '@lucide/vue'
import { Button } from '~/components/ui/button'
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '~/components/ui/collapsible'

defineProps<{ label: string, disabled?: boolean }>()
const open = defineModel<boolean>('open', { default: false })
</script>

<template>
  <Collapsible v-model:open="open" :disabled="disabled" :unmount-on-hide="false">
    <CollapsibleTrigger as-child>
      <Button type="button" variant="ghost" class="group h-auto w-full justify-between py-2.5 text-muted-foreground">
        {{ label }}
        <ChevronDown aria-hidden="true" class="size-4 group-data-[state=open]:rotate-180" />
      </Button>
    </CollapsibleTrigger>
    <CollapsibleContent>
      <slot />
    </CollapsibleContent>
  </Collapsible>
</template>
