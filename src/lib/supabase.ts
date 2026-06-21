import { createClient } from '@supabase/supabase-js'

// SEGURANÇA (§5.2): o frontend usa EXCLUSIVAMENTE a anon key. Todo acesso
// passa por RLS. A service_role JAMAIS aparece aqui nem no bundle.
const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  throw new Error(
    'Configuração ausente: defina VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY no .env',
  )
}

// Sem o generic <Database> até gerarmos os tipos (npm run gen:types).
// Os shapes são aplicados nos call-sites via os tipos em @/types/database.types.
export const supabase = createClient(url, anonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true, // necessário p/ Magic Link
  },
})
