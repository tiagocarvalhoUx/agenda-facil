-- =====================================================================
-- 0702 — WhatsApp do estabelecimento (botão flutuante wa.me)
-- Guarda o número de WhatsApp do tenant e o expõe na capa pública para o
-- botão de "fale conosco" (click-to-chat). Só o número; nada de API/token.
-- Idempotente.
-- =====================================================================

alter table tenants add column if not exists whatsapp text;

-- Recria a capa pública incluindo o whatsapp (demais campos inalterados).
create or replace function get_public_establishment(p_tenant_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_tenant tenants%rowtype; v_result jsonb;
begin
  select * into v_tenant from tenants where slug = p_tenant_slug and status = 'ativo';
  if not found then
    return null;
  end if;

  select jsonb_build_object(
    'nome', v_tenant.nome,
    'slug', v_tenant.slug,
    'accent_color', v_tenant.accent_color,
    'vertical', v_tenant.vertical,
    'timezone', v_tenant.timezone,
    'whatsapp', v_tenant.whatsapp,
    'servicos', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome,
                       'duracao_min', s.duracao_min, 'preco', s.preco)
                       order by s.nome)
      from services s
      where s.tenant_id = v_tenant.id and s.ativo = true and s.deleted_at is null
    ), '[]'::jsonb),
    'profissionais', coalesce((
      select jsonb_agg(jsonb_build_object('id', pr.id, 'nome', pr.nome) order by pr.nome)
      from professionals pr
      where pr.tenant_id = v_tenant.id and pr.ativo = true and pr.deleted_at is null
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function get_public_establishment(text) from public;
grant execute on function get_public_establishment(text) to anon, authenticated;
