-- =====================================================================
-- 0708 — WhatsApp do responsável no onboarding (create_tenant)
-- Coleta o WhatsApp na criação do estabelecimento e grava em dois lugares:
--   • tenants.whatsapp  → botão flutuante wa.me da página pública (valor p/ o
--                          cliente) e contato p/ suporte/retenção do dono
--   • profiles.telefone → contato do próprio dono
-- Normaliza para SÓ DÍGITOS. Opcional no banco (a obrigatoriedade é no app),
-- mantendo create_tenant idempotente e SECURITY DEFINER.
-- Precisa dropar a assinatura antiga (3 args) para não gerar overload ambíguo.
-- =====================================================================

drop function if exists create_tenant(text, text, text);

create or replace function create_tenant(
  p_nome     text,
  p_slug     text,
  p_vertical text default 'outro',
  p_whatsapp text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_tenant uuid;
  v_fone   text := nullif(regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g'), '');
begin
  if v_uid is null then
    raise exception 'unauthorized' using errcode = 'P0001';
  end if;

  -- já é dono de algum tenant? devolve o primeiro (idempotente).
  select tenant_id into v_tenant
  from memberships where user_id = v_uid and role = 'owner'
  order by created_at limit 1;
  if v_tenant is not null then
    return v_tenant;
  end if;

  if p_nome is null or length(trim(p_nome)) = 0 then
    raise exception 'invalid_name' using errcode = 'P0001';
  end if;
  if p_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'invalid_slug' using errcode = 'P0001';
  end if;
  if exists (select 1 from tenants where slug = p_slug) then
    raise exception 'slug_taken' using errcode = 'P0001';
  end if;

  insert into tenants (nome, slug, vertical, whatsapp)
  values (trim(p_nome), p_slug, nullif(p_vertical, ''), v_fone)
  returning id into v_tenant;
  -- o trigger trg_init_trial já cria o tenant_billing com 7 dias.

  insert into profiles (id, telefone) values (v_uid, v_fone)
    on conflict (id) do update
      set telefone = coalesce(profiles.telefone, excluded.telefone);

  insert into memberships (user_id, tenant_id, role)
  values (v_uid, v_tenant, 'owner');

  return v_tenant;
end;
$$;

revoke all on function create_tenant(text, text, text, text) from public;
grant execute on function create_tenant(text, text, text, text) to authenticated;
