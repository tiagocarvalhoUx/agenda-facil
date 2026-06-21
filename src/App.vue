<script setup lang="ts">
import { onMounted } from 'vue'
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
</template>
