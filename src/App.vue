<script setup lang="ts">
import { onMounted } from 'vue'
import { Analytics } from '@vercel/analytics/vue'
import { useAuthStore } from '@/stores/auth'
import ToastHost from '@/components/feedback/ToastHost.vue'

const auth = useAuthStore()
onMounted(() => {
  void auth.init()
})
</script>

<template>
  <RouterView />
  <ToastHost />
  <Analytics />
</template>
