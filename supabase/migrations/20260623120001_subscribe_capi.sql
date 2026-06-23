-- =====================================================================
-- 0018 — Marca de envio do evento Subscribe (Meta CAPI)
-- O /subscribe já marca status='ativo' na CRIAÇÃO da assinatura (antes do
-- pagamento confirmar). Logo, a transição de status NÃO serve de gatilho para
-- o Subscribe. Usamos esta coluna como trava idempotente: o webhook dispara o
-- Subscribe (CAPI) UMA vez, no 1º pagamento confirmado, e marca aqui — à prova
-- de retries do Asaas. Escrita só pelo servidor (service_role); ninguém lê isto
-- via API (sem policy → negado para anon/authenticated).
-- =====================================================================

alter table tenant_billing add column if not exists subscribe_tracked_at timestamptz;
