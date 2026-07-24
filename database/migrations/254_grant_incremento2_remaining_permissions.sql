-- Project Mimikyu
-- Query 254 - Grant Incremento 2 Remaining Permissions
-- Status: CONFIRMADA EXECUTADA (SQL Editor do Supabase Dashboard, uma
-- instrução por vez, cada uma confirmada por "Success"; reconfirmada pela
-- execução real e completa do Incremento 2 para a ME1 — 188/188 imagens,
-- 0 falhas)
-- Ver docs/06-pipeline-importacao.md, seção "Sprint B3.19", para o contexto
-- completo da descoberta.
--
-- Causa raiz real: mesmo gap já identificado nas Queries 250
-- (card_set_external_reference) e 253 (card_external_reference) — RLS
-- habilitado não substitui o GRANT de nível de tabela do PostgreSQL. Desta
-- vez, o gap apareceu em sequência, uma tabela por vez, conforme o teste
-- controlado do Incremento 2 avançava etapa por etapa:
--   1. `language`      — LANGUAGE_QUERY_FAILED / permission denied
--   2. `card_asset_type` — CARD_ASSET_TYPE_QUERY_FAILED / permission denied
--   3. `card_asset`      — CARD_ASSET_INSERT_FAILED / permission denied
--      (SELECT, INSERT e UPDATE — a tabela recebe leitura para a busca de
--      idempotência de `upsertCardAsset`, além de escrita)
--   4. `expansion`       — CARD_ASSET_INSERT_FAILED / permission denied
--      (descoberta indireta: o INSERT em `card_asset` aciona uma dependência
--      — provavelmente uma FK/trigger de validação — que consulta `expansion`)
--
-- Cada erro foi resolvido individualmente, seguindo a mesma regra do
-- projeto: nunca adivinhar a causa, sempre confirmar pelo erro real do
-- PostgreSQL (retornado nos logs da Edge Function) antes de corrigir.
--
-- Pendência reafirmada, agora com seis casos reais confirmados do mesmo
-- padrão (Queries 250/253/254): Fabrício propôs novamente consolidar uma
-- auditoria completa de GRANTs em um único script futuro (`grants.sql`),
-- ainda deliberadamente adiada — ver "Em Aberto" em
-- docs/06-pipeline-importacao.md.

begin;

grant select
    on table public.language
    to service_role;

grant select
    on table public.card_asset_type
    to service_role;

grant select, insert, update
    on table public.card_asset
    to service_role;

grant select
    on table public.expansion
    to service_role;

commit;
