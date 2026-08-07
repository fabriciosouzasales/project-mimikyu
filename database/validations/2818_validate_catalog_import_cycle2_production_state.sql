/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2818 - Validate Catalog Import Cycle 2 Production State
Versão......: 1.0
Status......: PROPOSTA — AGUARDANDO EXECUÇÃO POR FABRÍCIO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Fechamento formal do Ciclo 2 de ADR-024 (fluxo vertical completo de
ingestão de Cards via TCGdex — Edge Function `import-catalog-cards`,
telas `/catalogo/importar-cartas`/`/catalogo/importar-imagens`).

Diferente da validação do Ciclo 1 (Query 2814, dados sintéticos
`ZZTEST` dentro de uma transação com `ROLLBACK`, porque na época
nenhum processador existia ainda), o Ciclo 2 já está em uso ativo em
produção há dias, com múltiplos Card Sets reais importados (SV1-SV5,
SV3.5, SVE, SVP, ME5, entre outros). Não há dado sintético a limpar
nem transação a desfazer — esta é uma validação somente leitura
(nenhum `INSERT`/`UPDATE`/`DELETE`) que audita a integridade do que já
foi persistido de verdade, em vez de exercitar um cenário novo.

Cobre 8 pontos:
1. Assinatura real de `admin_start_asset_import_run()` em produção —
   resolve uma divergência encontrada durante esta auditoria: o
   cabeçalho do arquivo canônico (`database/schema/2092_...sql`, v1.3)
   ainda diz "PROPOSTA — AGUARDANDO EXECUÇÃO", mas a Revision History
   de `05-modelo-de-dados.md` (revisões 1.31/1.33/1.36) registra as
   versões v1.0/v1.1/v1.2 como confirmadas executadas, e o frontend em
   produção (seletor de idioma EN/PT-BR na tela Importar Imagens) só
   funciona se a assinatura de 4 parâmetros (`p_language_code`) já
   estiver instalada. Resultado 1 confirma qual das duas está certa.
2. Distribuição de `catalog_import_job` por status, só `source = 'TCGDEX'`.
3. Nenhum job preso em `CONFIRMING` (a semântica transacional de
   `admin_confirm_catalog_import()` deveria impedir isso por
   construção — ver ADR-024, "Concorrência: lock na linha do job").
4. Nenhuma linha `PENDING` (decisão ou persistência) dentro de um job
   já em estado terminal (`COMPLETED`/`COMPLETED_WITH_ERRORS`).
5. Auditoria: todo job TCGDEX que já foi confirmado ao menos uma vez
   tem pelo menos uma linha `CATALOG_IMPORT_JOB`/`CATALOG_IMPORT_CONFIRMED`
   correspondente em `catalog_admin_action_log`.
6. `card_set_external_reference` ativa para TCGDEX existe para todo
   Card Set com um job TCGDEX em estado terminal de sucesso — confirma
   que o `upsert` feito pelo processador (`import-catalog-cards`,
   passo 11 do fluxo) está funcionando.
7. Contagem cruzada: total de Cards ativas hoje vs. total de linhas
   `persistence_status = 'INSERTED'` em todo o staging — não precisam
   bater exatamente (Cards também nascem por cadastro manual, Query
   2115), mas o staging não pode superar o total real.
8. GRANTs de `service_role` (Migration 2090) ainda em vigor nas seis
   tabelas que o processador lê/escreve — pré-requisito para a Edge
   Function funcionar, nunca revogado por nenhuma emenda posterior.
================================================================
*/

-- 1. Assinatura real de admin_start_asset_import_run() em produção
SELECT
    p.proname,
    pg_get_function_identity_arguments(p.oid) AS assinatura_atual,
    (pg_get_function_identity_arguments(p.oid) LIKE '%p_language_code%') AS tem_parametro_idioma_v1_3
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'admin_start_asset_import_run';

-- 2. Distribuição de catalog_import_job (só TCGDEX) por status
SELECT status, count(*) AS total_jobs
FROM public.catalog_import_job
WHERE source = 'TCGDEX'
GROUP BY status
ORDER BY status;

-- 3. Jobs presos em CONFIRMING (esperado: 0 linhas)
SELECT id, card_set_id, status, updated_at
FROM public.catalog_import_job
WHERE source = 'TCGDEX' AND status = 'CONFIRMING';

-- 4. Linhas PENDING dentro de jobs já em estado terminal (esperado: 0 linhas)
SELECT j.id AS job_id, j.status AS job_status,
       count(*) FILTER (WHERE r.decision_status = 'PENDING') AS linhas_decisao_pendente,
       count(*) FILTER (WHERE r.persistence_status = 'PENDING') AS linhas_persistencia_pendente
FROM public.catalog_import_job j
JOIN public.catalog_import_row r ON r.job_id = j.id
WHERE j.source = 'TCGDEX' AND j.status IN ('COMPLETED', 'COMPLETED_WITH_ERRORS')
GROUP BY j.id, j.status
HAVING count(*) FILTER (WHERE r.decision_status = 'PENDING') > 0
    OR count(*) FILTER (WHERE r.persistence_status = 'PENDING') > 0;

-- 5. Jobs TCGDEX confirmados sem nenhuma linha de auditoria correspondente
--    (esperado: 0 linhas — todo CONFIRMED deveria ter gravado ao menos
--    uma vez em catalog_admin_action_log, mesmo que parcialmente)
SELECT j.id AS job_id, j.card_set_id, j.status
FROM public.catalog_import_job j
WHERE j.source = 'TCGDEX'
  AND j.status IN ('COMPLETED', 'COMPLETED_WITH_ERRORS')
  AND NOT EXISTS (
        SELECT 1 FROM public.catalog_admin_action_log l
        WHERE l.entity_type = 'CATALOG_IMPORT_JOB'
          AND l.entity_id = j.id
      );

-- 6. Card Sets com job TCGDEX terminal de sucesso, mas sem
--    card_set_external_reference ativa (esperado: 0 linhas)
SELECT DISTINCT j.card_set_id, cs.code
FROM public.catalog_import_job j
JOIN public.card_set cs ON cs.id = j.card_set_id
WHERE j.source = 'TCGDEX'
  AND j.status IN ('COMPLETED', 'COMPLETED_WITH_ERRORS')
  AND NOT EXISTS (
        SELECT 1 FROM public.card_set_external_reference cser
        JOIN public.asset_source src ON src.id = cser.asset_source_id
        WHERE cser.card_set_id = j.card_set_id
          AND src.code = 'TCGDEX'
          AND cser.is_active = true
      );

-- 7. Contagem cruzada: Cards ativas vs. linhas INSERTED no staging
SELECT
    (SELECT count(*) FROM public.card WHERE is_active = true) AS cards_ativas_hoje,
    (SELECT count(*) FROM public.catalog_import_row WHERE persistence_status = 'INSERTED') AS linhas_inseridas_via_staging;

-- 8. GRANTs de service_role (Migration 2090) ainda em vigor
SELECT table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'service_role'
  AND table_schema = 'public'
  AND table_name IN ('catalog_import_job', 'catalog_import_row', 'card_set', 'card', 'rarity', 'card_category')
ORDER BY table_name, privilege_type;

-- ================================================================
-- Resultado esperado (resumo):
-- 1. tem_parametro_idioma_v1_3 = true (se false, o cabeçalho do
--    arquivo canônico 2092 está certo e a v1.3 nunca foi executada —
--    nesse caso, avisar antes de qualquer outra conclusão, porque o
--    seletor de idioma da tela Importar Imagens não poderia estar
--    funcionando em produção).
-- 2. Ao menos um job em COMPLETED (ou COMPLETED_WITH_ERRORS) por
--    Card Set já importado — números exatos não são o ponto, só a
--    presença de estados terminais reais, não só STAGED/FAILED.
-- 3. Nenhuma linha (0 jobs presos em CONFIRMING).
-- 4. Nenhuma linha (nenhum job terminal com decisão/persistência
--    ainda pendente).
-- 5. Nenhuma linha (toda confirmação real gravou auditoria).
-- 6. Nenhuma linha (toda importação bem-sucedida deixou a referência
--    externa ativa, viabilizando a continuação automática de imagens).
-- 7. linhas_inseridas_via_staging <= cards_ativas_hoje (staging nunca
--    pode superar o total real; a diferença é esperada — nem toda
--    Card ativa veio da TCGdex, algumas vieram de cadastro manual).
-- 8. SELECT para as seis tabelas, service_role presente (INSERT em
--    catalog_import_job/catalog_import_row, SELECT nas quatro
--    tabelas de apoio) — ausência de qualquer linha esperada aqui
--    indicaria uma regressão de GRANT (mesmo padrão de bug recorrente
--    já visto várias vezes neste projeto).
--
-- Como validar: rodar cada bloco numerado e conferir contra o
-- resultado esperado correspondente. Reportar de volta especialmente
-- o resultado da Query 1 (resolve a divergência do cabeçalho de
-- 2092) e de qualquer bloco que devolver linhas nas Queries 3/4/5/6
-- (todas deveriam vir vazias).
-- ================================================================
