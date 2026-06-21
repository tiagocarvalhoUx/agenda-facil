-- =====================================================================
-- Seed de desenvolvimento (rodado por `supabase db reset`).
-- Cria um tenant demo com serviços, profissionais e expediente, para
-- testar o fluxo público em /studio-bem-estar sem precisar de login.
-- NÃO usar em produção.
-- =====================================================================

do $$
declare
  v_tenant uuid;
  v_prof_ana uuid;
  v_prof_rui uuid;
begin
  insert into tenants (nome, slug, plano, status, accent_color, vertical, timezone)
  values ('Studio Bem-Estar', 'studio-bem-estar', 'pro', 'ativo', '#C84B6B', 'salao', 'America/Sao_Paulo')
  returning id into v_tenant;

  insert into professionals (tenant_id, nome) values (v_tenant, 'Ana Costa') returning id into v_prof_ana;
  insert into professionals (tenant_id, nome) values (v_tenant, 'Rui Almeida') returning id into v_prof_rui;

  insert into services (tenant_id, nome, duracao_min, preco) values
    (v_tenant, 'Corte de cabelo', 45, 70.00),
    (v_tenant, 'Manicure', 60, 50.00),
    (v_tenant, 'Massagem relaxante', 90, 160.00);

  -- Expediente seg–sex (1..5), 09:00–18:00 para ambos os profissionais.
  insert into working_hours (tenant_id, professional_id, weekday, hora_inicio, hora_fim)
  select v_tenant, p.id, d.weekday, time '09:00', time '18:00'
  from (values (v_prof_ana), (v_prof_rui)) p(id)
  cross join generate_series(1, 5) as d(weekday);
end $$;
