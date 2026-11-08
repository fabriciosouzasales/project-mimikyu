/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5357-V1.9 - UNICIDADE DE collection_allocation.physical_card_id
              (somente catálogo; pré-requisito do V1.7)
Versão......: 0.1 (B2 — V1 CLOSEOUT & V2 READINESS-01)
Status......: PROPOSTO — NÃO EXECUTADO. Exige autorização específica.
              Arquivo separado para não alterar o V1 v0.3 já executado.
Data........: 2026-11-08

Por que: o V1.7 junta collection_allocation a cada bolso ocupado; a junção só
não multiplica bolsos se physical_card_id for único. A definição versionada
(5040) declara "physical_card_id UUID NOT NULL UNIQUE"; este bloco confirma a
definição VIGENTE no banco.

Garantias da própria verificação
  - Transação READ ONLY; statement_timeout 5 s; lock_timeout 2 s;
    idle_in_transaction_session_timeout 30 s; ROLLBACK.
  - Lê só pg_class, pg_namespace, pg_attribute, pg_index e pg_constraint.
    Nenhuma linha de collection_allocation é lida.
  - Saída: booleanos e a definição do índice (texto de catálogo, sem dados).

GATE (todos TRUE):
  tabela_existe, coluna_existe, coluna_not_null, existe_unico_valido_total —
  há ao menos um índice UNIQUE sobre EXATAMENTE (physical_card_id), válido
  (indisvalid), pronto (indisready), não parcial (indpred nulo) e sem
  expressão (indexprs nulo); restricao_unique_validada — e ele sustenta uma
  constraint UNIQUE/PK validada (convalidated).
  indices_info é informativo (conferência manual na auditoria).
STOP: qualquer FALSE/NULL, timeout ou SQLSTATE.
================================================================
*/

-- V1.9 [GATE] unicidade vigente de collection_allocation.physical_card_id (catálogo)
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
with t as (
  select c.oid as relid
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'collection_allocation' and c.relkind = 'r'
), col as (
  select a.attnum, a.attnotnull
  from pg_attribute a join t on a.attrelid = t.relid
  where a.attname = 'physical_card_id' and not a.attisdropped
), idx as (
  select i.indexrelid, i.indisvalid, i.indisready, i.indpred is null as total, i.indexprs is null as sem_expressao,
         exists (select 1 from pg_constraint k
                  where k.conindid = i.indexrelid and k.contype in ('u', 'p') and k.convalidated) as sustenta_constraint
  from pg_index i join t on i.indrelid = t.relid
  where i.indisunique
    and i.indnkeyatts = 1
    and i.indkey[0] = (select attnum from col)
)
select exists (select 1 from t)                                                        as tabela_existe,
       exists (select 1 from col)                                                      as coluna_existe,
       coalesce((select attnotnull from col), false)                                   as coluna_not_null,
       exists (select 1 from idx where indisvalid and indisready and total and sem_expressao) as existe_unico_valido_total,
       exists (select 1 from idx where indisvalid and indisready and total and sem_expressao and sustenta_constraint) as restricao_unique_validada,
       (select string_agg(pg_get_indexdef(indexrelid), ' | ' order by 1) from idx)     as indices_info;
rollback;
