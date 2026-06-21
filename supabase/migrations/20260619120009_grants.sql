-- =====================================================================
-- 0009 — GRANTs de privilégio de tabela (complementam a RLS)
-- No Supabase, privilégio de tabela e RLS são camadas distintas:
--   • `authenticated` recebe privilégios nas tabelas e a RLS filtra por
--     tenant/role (sem grant, tudo é negado já no privilégio).
--   • `anon` NÃO recebe nenhum privilégio de tabela — o fluxo público só
--     acessa via RPCs SECURITY DEFINER (reforça §5.3). Tabelas continuam
--     inacessíveis diretamente para o cliente final.
-- Tabelas sem policy para uma operação seguem negando por RLS (default deny).
-- =====================================================================

grant usage on schema public to anon, authenticated;

-- authenticated: privilégios nas tabelas de negócio (RLS aplica o recorte).
grant select, insert, update, delete on
  tenants, profiles, memberships, professionals, services,
  working_hours, customers, appointments, reminders, audit_log
to authenticated;

-- anon: nenhum privilégio de tabela. Apenas EXECUTE nas RPCs públicas
-- (concedido nas migrations 0006). booking_attempts/audit_log nunca são
-- acessíveis diretamente por authenticated além do que a policy permite.
