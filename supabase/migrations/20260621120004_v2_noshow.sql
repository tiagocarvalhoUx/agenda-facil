-- =====================================================================
-- 0013 (v2) — Reputação anti no-show + consistência de lembretes (§6.3)
-- 1) no_show_count do cliente mantido por trigger (fonte da verdade no banco,
--    não no cliente) ao alternar o status do agendamento.
-- 2) Ao remarcar (inicio_at muda), os lembretes pendentes antigos são
--    cancelados e novos são enfileirados para o novo horário.
-- =====================================================================

-- ----- 1) Reputação no-show -----
create or replace function fn_track_no_show()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'no_show' and old.status is distinct from 'no_show' then
    update customers set no_show_count = no_show_count + 1 where id = new.customer_id;
  elsif old.status = 'no_show' and new.status is distinct from 'no_show' then
    update customers set no_show_count = greatest(no_show_count - 1, 0) where id = new.customer_id;
  end if;
  return new;
end;
$$;

create trigger trg_track_no_show
  after update of status on appointments
  for each row execute function fn_track_no_show();

-- ----- 2) Reenfileiramento de lembretes ao remarcar -----
create or replace function fn_reenqueue_reminders()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_email text;
begin
  if new.inicio_at is distinct from old.inicio_at then
    -- descarta lembretes pendentes do horário antigo
    update reminders set status = 'cancelado'
      where appointment_id = new.id and status = 'pendente';

    select email into v_email from customers where id = new.customer_id;
    if v_email is null then
      return new;
    end if;

    if new.inicio_at - interval '24 hours' > now() then
      insert into reminders (tenant_id, appointment_id, canal, agendado_para)
        values (new.tenant_id, new.id, 'email', new.inicio_at - interval '24 hours')
        on conflict (appointment_id, canal, agendado_para) do nothing;
    end if;
    if new.inicio_at - interval '2 hours' > now() then
      insert into reminders (tenant_id, appointment_id, canal, agendado_para)
        values (new.tenant_id, new.id, 'email', new.inicio_at - interval '2 hours')
        on conflict (appointment_id, canal, agendado_para) do nothing;
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_reenqueue_reminders
  after update of inicio_at on appointments
  for each row execute function fn_reenqueue_reminders();
