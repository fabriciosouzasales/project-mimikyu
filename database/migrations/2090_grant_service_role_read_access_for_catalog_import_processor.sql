/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2090 - Grant Service Role Read Access for Catalog Import Processor
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (2026-08-01 — teste real: job SVE processado
com sucesso após a correção, 24/24 linhas VALID, ver docs/05-modelo-de-dados.md)
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01

Descrição...:
Corrige um gap real de GRANT, descoberto na primeira execução real da
Edge Function import-catalog-cards (Ciclo 2, ADR-024): catalog_import_job,
card_set, card, rarity, card_category e asset_source têm RLS habilitado
e GRANT SELECT para authenticated, mas nenhuma delas jamais recebeu
GRANT SELECT para service_role — a Edge Function autentica como
service_role e faz SELECT direto nessas seis tabelas (localizar o job,
resolver o Game da Coleção via card_set/expansion, comparar contra
Cards já existentes, mapear raridade/categoria, localizar a fonte
TCGDEX). RLS bypass de service_role não substitui o GRANT de nível de
tabela — mesmo gap já visto quatro vezes neste projeto (migrations
250/253/254/272), desta vez auditado nas seis tabelas juntas contra o
código real da Edge Function, em vez de corrigido uma por vez a cada
novo erro isolado.

Sintoma real observado: a chamada da Edge Function retornou HTTP 500,
mas o job permaneceu em RECEIVED (nunca chegou a PROCESSING) — porque o
erro ocorreu dentro de findJob(), antes de qualquer transição de status
ser gravada. Sem esta migration, o mesmo padrão se repetiria a cada
SELECT subsequente (card_set, expansion, card, rarity, card_category,
asset_source), um de cada vez.

Regras de Negócio:
- Nenhuma política de RLS é alterada — só GRANT de nível de tabela,
  mesma técnica das migrations 250/253/254/272.
- expansion (migration 254) e card_set_external_reference (migration
  250) já tinham GRANT SELECT para service_role — não fazem parte desta
  migration.

Pré-requisitos:
- Query 2060 - Create Catalog Import Job Table.
- Query 120 - Create Card Set Table.
- Query 140 - Create Card Table.
- Query 130 - Create Rarity Table.
- Query 132 - Create Card Category Table.
- Query 200 - Create Asset Source Table.
================================================================
*/

GRANT SELECT ON public.catalog_import_job TO service_role;
GRANT SELECT ON public.card_set TO service_role;
GRANT SELECT ON public.card TO service_role;
GRANT SELECT ON public.rarity TO service_role;
GRANT SELECT ON public.card_category TO service_role;
GRANT SELECT ON public.asset_source TO service_role;
