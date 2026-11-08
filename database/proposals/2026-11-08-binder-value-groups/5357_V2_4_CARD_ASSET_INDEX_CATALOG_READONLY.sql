/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5357-V2.4 - DIAGNÓSTICO DE CATÁLOGO dos índices de card_asset
              (divergência potencial de uq_card_asset_card_type_external_url)
Versão......: 0.1 (B2 — V2.1 G3 CORRECTION & INDEX DIAGNOSIS-01)
Status......: PROPOSTO — NÃO EXECUTADO. Exige autorização específica.
Data........: 2026-11-08

Por que: no V2.1 executado, a busca de imagem da 5357 usou
uq_card_asset_card_type_external_url com "Index Cond: (card_id = c.id)" e sem
condição sobre external_url. A definição versionada (Query 180,
database/schema/180_create_card_asset_table.sql) declara esse índice PARCIAL:
  CREATE UNIQUE INDEX IF NOT EXISTS uq_card_asset_card_type_external_url
      ON public.card_asset (card_id, asset_type_id, external_url)
      WHERE external_url IS NOT NULL;
O PostgreSQL só usa índice parcial quando a consulta implica o predicado; a
consulta da 5357 não menciona external_url. Hipótese [I]: no banco o índice
não é parcial (ou difere de outra forma) — por exemplo, porque já existia com
outra definição quando a 180 rodou com IF NOT EXISTS. Este bloco só compara
definições; não decide nada.

Garantias da própria verificação
  - Transação READ ONLY; statement_timeout 5 s; lock_timeout 2 s;
    idle_in_transaction_session_timeout 30 s; ROLLBACK.
  - Lê só pg_class, pg_namespace, pg_index e pg_get_indexdef/pg_get_expr.
    Nenhuma linha de card_asset (nem de cartas, exemplares, coleções ou
    usuários) é lida.
  - Saída: uma linha por índice de public.card_asset com nome, definição
    vigente, colunas-chave, predicado, válido/pronto/único, e a comparação
    com a definição versionada da 180 para os índices que ela declara.

Leitura do resultado (INFO; nada aqui autoriza correção)
  - igual_ao_versionado = false em qualquer linha → divergência entre banco e
    repositório, a registrar e tratar em rodada própria (sem DDL nesta fase).
  - Para a 5357 importa só que exista índice válido com card_id na primeira
    posição (busca de imagem por card_id): coluna "serve_busca_por_card_id".
================================================================
*/

-- V2.4 [INFO] índices vigentes de public.card_asset × definição versionada (catálogo)
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
with versionado(nome, chaves, predicado, unico) as (values
  ('uq_card_asset_one_primary_per_card_type', 'card_id, asset_type_id',              '(is_primary = true)',         true),
  ('uq_card_asset_card_type_storage_path',    'card_id, asset_type_id, storage_path', '(storage_path IS NOT NULL)',  true),
  ('uq_card_asset_card_type_external_url',    'card_id, asset_type_id, external_url', '(external_url IS NOT NULL)',  true),
  ('ix_card_asset_card_id',                   'card_id',                              null,                          false)
), vigente as (
  select ic.relname                                                     as nome,
         pg_get_indexdef(i.indexrelid)                                  as definicao,
         (select string_agg(pg_get_indexdef(i.indexrelid, k, true), ', ' order by k)
            from generate_series(1, i.indnkeyatts) k)                   as chaves,
         pg_get_expr(i.indpred, i.indrelid)                             as predicado,
         i.indisunique as unico, i.indisvalid as valido, i.indisready as pronto,
         pg_get_indexdef(i.indexrelid, 1, true) = 'card_id'            as serve_busca_por_card_id
  from pg_index i
  join pg_class t      on t.oid = i.indrelid
  join pg_namespace n  on n.oid = t.relnamespace and n.nspname = 'public'
  join pg_class ic     on ic.oid = i.indexrelid
  where t.relname = 'card_asset'
)
select coalesce(v.nome, e.nome)                                          as indice,
       v.nome is not null                                                as existe_no_banco,
       e.nome is not null                                                as declarado_na_180,
       v.definicao, v.chaves, v.predicado, v.unico, v.valido, v.pronto, v.serve_busca_por_card_id,
       case when e.nome is null or v.nome is null then null
            else (v.chaves = e.chaves
                  and v.predicado is not distinct from e.predicado
                  and v.unico = e.unico) end                             as igual_ao_versionado
from vigente v
full join versionado e on e.nome = v.nome
order by 1;
rollback;
