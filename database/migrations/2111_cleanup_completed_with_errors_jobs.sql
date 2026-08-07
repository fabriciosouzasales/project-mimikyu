/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2111 - Cleanup COMPLETED_WITH_ERRORS Duplicate Jobs
Versão......: 1.0
Status......: MIGRATION — CONFIRMADO EXECUTADO (limpeza pontual de dado)
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Limpeza pontual de dado, não uma mudança de schema: 16 jobs de
importação em status COMPLETED_WITH_ERRORS cobrindo 8 Coleções
(BASE1, BASEP, GYM1, GYM2, SV1, SV4.5, SV5, SWSH1) — cada
duplicata era uma nova tentativa de "Analisar" na mesma Coleção
depois que a tentativa anterior já havia terminado em erro
(admin_start_catalog_import(), Query 2080, só bloqueia fingerprint
duplicado enquanto o job anterior está em estado NÃO-terminal —
uma vez COMPLETED_WITH_ERRORS, nada impedia uma nova tentativa
de gerar outro job para a mesma Coleção). Decisão de Fabrício,
tomada antes da tela /catalogo/raridades (task #336) nascer com um
botão único "Revalidar tudo" em vez de revalidação job a job —
manter 8 jobs duplicados por Coleção só adicionaria ruído a essa
tela sem nenhum valor de auditoria adicional (a Card, se
persistida, já está persistida; o job antigo não guarda nenhuma
informação que o mais recente não tenha).

Regras de Negócio:
- Critério de manutenção: só o job mais recente (maior created_at)
  por Card Set em COMPLETED_WITH_ERRORS é mantido; os demais são
  excluídos.
- catalog_import_row tem FK ON DELETE CASCADE para
  catalog_import_job (Query 2070/2071) — excluir o job também
  remove suas linhas de staging automaticamente, sem passo
  adicional.
- Nenhuma Card (public.card) é afetada — catalog_import_row nunca
  é a fonte de verdade de uma Card já persistida, só o rascunho de
  staging que a originou.
- catalog_admin_action_log não referencia catalog_import_job por
  FK (entity_id é polimórfico, Query 2010) — as linhas de auditoria
  dos jobs excluídos permanecem intactas, preservando o histórico
  de quem tentou importar o quê e quando.

Pré-requisitos:
- Query 2060/2061 - Create Catalog Import Job Table.
- Query 2070/2071 - Create Catalog Import Row Table (FK ON DELETE
  CASCADE para catalog_import_job).
================================================================
*/

DELETE FROM public.catalog_import_job j
WHERE j.status = 'COMPLETED_WITH_ERRORS'
  AND j.id NOT IN (
      SELECT DISTINCT ON (j2.source_card_set_id) j2.id
      FROM public.catalog_import_job j2
      WHERE j2.status = 'COMPLETED_WITH_ERRORS'
      ORDER BY j2.source_card_set_id, j2.created_at DESC
  );

-- ================================================================
-- Confirmado executado (2026-08-07): 8 jobs excluídos (16 → 8),
-- um por Coleção (BASE1, BASEP, GYM1, GYM2, SV1, SV4.5, SV5,
-- SWSH1), cada exclusão removendo em cascata suas
-- catalog_import_row. Nenhuma Card afetada; auditoria em
-- catalog_admin_action_log preservada. Ver docs/log.md,
-- [2026-08-07] fix | Limpeza de jobs COMPLETED_WITH_ERRORS
-- duplicados (Query 2111).
-- ================================================================
