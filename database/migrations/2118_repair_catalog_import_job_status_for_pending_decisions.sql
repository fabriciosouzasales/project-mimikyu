/*
================================================================
Projeto.....: Project Mimikyu
Migration...: 2118 - Repair catalog_import_job Status for Pending Decisions
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Confirmação de execução (2026-08-07): UPDATE 2, os 2 jobs esperados —
0a067e94-b665-4d74-b47f-2635d12e22a9 (9 linhas decisão pendente) e
3ea4752c-cf6d-4fb9-8228-224f96c11030 (1 linha) — voltaram para STAGED,
validado pela query de confirmação abaixo (mesmas contagens).

Descrição...:
Correção retroativa do bug encontrado pela validação `2818` (fechamento
do Ciclo 2 de ADR-024): a versão v1.0 de admin_confirm_catalog_import()
(Query 2082) calculava o status final do job ignorando linhas com
decision_status = 'PENDING' (nunca decididas por nenhum administrador),
permitindo que um job chegasse a COMPLETED com decisões humanas
pendentes — violação direta da regra já documentada em ADR-024.

Esta migration não reprocessa nenhuma linha nem toca em
catalog_import_row — apenas devolve o status do job (coluna
catalog_import_job.status) para STAGED nos casos em que isso já deveria
ter acontecido, para que a tela de Revisão volte a mostrar essas linhas
como pendentes de decisão. A partir da execução da Query 2082 v1.1
(CREATE OR REPLACE, mesma assinatura), o bug deixa de poder se
reproduzir para novos jobs — esta migration cobre apenas o estado já
gravado em produção antes da correção.

Escopo confirmado nesta investigação (validação 2818, item 4):
- 0a067e94-b665-4d74-b47f-2635d12e22a9 — 9 linhas decision_status =
  'PENDING' (estava COMPLETED).
- 3ea4752c-cf6d-4fb9-8228-224f96c11030 — 1 linha decision_status =
  'PENDING' (estava COMPLETED).
A condição do WHERE abaixo é genérica (não hardcoded pelos 2 UUIDs)
para também cobrir qualquer outra ocorrência do mesmo padrão que não
tenha sido capturada pela amostra manual da validação 2818.

Não afeta o job bae2f19b-223f-42da-9acd-4283da8fc7b3 (270 linhas
decision_status = 'REJECTED', persistence_status = 'PENDING') — esse
é o comportamento correto por desenho (linha REJECTED nunca é
persistida, então nunca sai de PENDING; não bloqueia a conclusão do
job) e a condição abaixo filtra especificamente por decision_status =
'PENDING', não por persistence_status.

Pré-requisitos:
- Query 2060/2061 - Create Catalog Import Job Table + Triggers.
- Query 2070/2071 - Create Catalog Import Row Table + Triggers.
- Query 2082 v1.1 - admin_confirm_catalog_import() (correção do bug,
  deve ser executada antes ou junto desta migration — caso contrário
  uma nova chamada de confirmação no job recém-reaberto reproduziria
  o mesmo bug).
================================================================
*/

UPDATE public.catalog_import_job j
SET status = 'STAGED'
WHERE j.status IN ('COMPLETED', 'COMPLETED_WITH_ERRORS')
  AND EXISTS (
      SELECT 1
      FROM public.catalog_import_row r
      WHERE r.job_id = j.id
        AND r.decision_status = 'PENDING'
  );

/*
Resultado esperado:
UPDATE 2 (os 2 jobs listados acima — nenhum outro deve ser afetado,
salvo achado adicional não capturado pela amostra manual da 2818).

Como validar (query de confirmação):
SELECT
    j.id AS job_id,
    j.status,
    COUNT(*) FILTER (WHERE r.decision_status = 'PENDING') AS linhas_decisao_pendente
FROM public.catalog_import_job j
JOIN public.catalog_import_row r ON r.job_id = j.id
WHERE j.id IN (
    '0a067e94-b665-4d74-b47f-2635d12e22a9',
    '3ea4752c-cf6d-4fb9-8228-224f96c11030'
)
GROUP BY j.id, j.status;
-- Esperado: os 2 jobs com status = 'STAGED' e linhas_decisao_pendente > 0.
*/
