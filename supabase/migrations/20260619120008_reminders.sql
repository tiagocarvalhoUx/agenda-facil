-- =====================================================================
-- 0008 — Enfileiramento de lembretes (§6)
-- Trigger enfileira lembretes 24h e 2h antes do início, para qualquer
-- agendamento (público ou painel) cujo cliente tenha e-mail. Idempotente
-- (unique appointment_id+canal+agendado_para). Só janelas ainda futuras.
-- O disparo em si é feito pela Edge Function agendada (idempotente também).
-- =====================================================================

create or replace function fn_enqueue_reminders()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_email text;
begin
  select email into v_email from customers where id = new.customer_id;
  if v_email is null then
    return new; -- sem canal de envio, nada a enfileirar (MVP = e-mail)
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

  return new;
end;
$$;

create trigger trg_enqueue_reminders
  after insert on appointments
  for each row execute function fn_enqueue_reminders();

-- Quando um agendamento é cancelado, cancela lembretes pendentes.
create or replace function fn_cancel_reminders()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'cancelado' and old.status <> 'cancelado' then
    update reminders set status = 'cancelado'
      where appointment_id = new.id and status = 'pendente';
  end if;
  return new;
end;
$$;

create trigger trg_cancel_reminders
  after update of status on appointments
  for each row execute function fn_cancel_reminders();
