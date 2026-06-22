-- =====================================================================
-- 0017 — Reforço da assinatura NO BANCO (paywall à prova de bypass)
-- Até aqui o bloqueio do trial vencido vivia só no frontend (router guard).
-- Quem tivesse o token do usuário ainda conseguiria ESCREVER via API REST.
-- Aqui a trava passa a valer na RLS: sem assinatura ativa (e trial expirado),
-- o painel não consegue mais INSERIR/ATUALIZAR/REMOVER os dados do negócio.
--
-- Decisões de escopo:
--   • Só ESCRITA é travada. Leitura continua (ver os próprios dados não é a
--     barreira de monetização; e não quebra a tela de paywall/exportações).
--   • Usamos policies RESTRICTIVE: elas são combinadas com AND às policies
--     permissivas já existentes, então NADA do RLS atual é alterado.
--   • O fluxo público (cliente final) usa RPCs SECURITY DEFINER que ignoram
--     RLS — logo NÃO é afetado aqui. Se quiser parar também o agendamento
--     público no trial vencido, isso é uma decisão de produto à parte (checar
--     tenant_has_access dentro das RPCs públicas).
--   • Tabelas de identidade/config (tenants, memberships, profiles) ficam de
--     fora de propósito, para não trancar o usuário fora da própria conta.
-- =====================================================================

-- ----- Helper: o tenant tem acesso liberado? (espelha auth.ts accessBlocked) -----
-- SECURITY DEFINER (owner = postgres, BYPASSRLS) para ler tenant_billing sem
-- esbarrar na RLS daquela tabela. STABLE + search_path fixo (anti-hijack),
-- mesmo contrato dos helpers de identidade (0003).
create or replace function tenant_has_access(p_tenant uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Sem registro de billing → não bloqueia (coalesce true), idêntico ao
  -- frontend: `if (!billing) return false /* accessBlocked */`.
  select coalesce(
    (
      select
        b.status = 'ativo'
        or (b.status = 'trial' and b.trial_ends_at is not null and b.trial_ends_at > now())
      from tenant_billing b
      where b.tenant_id = p_tenant
    ),
    true
  );
$$;

revoke all on function tenant_has_access(uuid) from public;
grant execute on function tenant_has_access(uuid) to authenticated;

-- ----- Policies RESTRICTIVE de billing nas tabelas operacionais -----
-- Combinadas com AND às permissivas existentes: a escrita só passa se o
-- recorte de tenant/role JÁ permitia E o tenant tem acesso (assinatura/trial).
-- Idempotente (drop if exists) para a migration ser re-aplicável com segurança.
do $$
declare t text;
begin
  foreach t in array array[
    'professionals','services','working_hours','customers',
    'appointments','professional_services','time_blocks','waitlist'
  ] loop
    execute format('drop policy if exists %1$I_billing_insert on %1$I;', t);
    execute format('drop policy if exists %1$I_billing_update on %1$I;', t);
    execute format('drop policy if exists %1$I_billing_delete on %1$I;', t);

    execute format($f$
      create policy %1$I_billing_insert on %1$I
        as restrictive for insert to authenticated
        with check (tenant_has_access(tenant_id));
    $f$, t);
    execute format($f$
      create policy %1$I_billing_update on %1$I
        as restrictive for update to authenticated
        using (tenant_has_access(tenant_id))
        with check (tenant_has_access(tenant_id));
    $f$, t);
    execute format($f$
      create policy %1$I_billing_delete on %1$I
        as restrictive for delete to authenticated
        using (tenant_has_access(tenant_id));
    $f$, t);
  end loop;
end $$;
