-- =====================================================================
-- 0001 — Extensões
-- =====================================================================
-- pgcrypto: gen_random_uuid()
-- btree_gist: necessário para o EXCLUDE constraint anti-overbooking
--             (combina igualdade em professional_id com && em tstzrange).
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;
