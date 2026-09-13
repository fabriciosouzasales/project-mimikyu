/*
===============================================================================
   ███  EXECUTADA / VALIDADA — PHASE E CLOSED  ███

   Executada em 2026-09-13 no LIVE, via apply_migration, em transação
   única com SET LOCAL mimikyu.phase_e_authorized = 'CONFIRMED'.

       GUARD 0 ................ PASS
       GUARDS 1..6 ............ PASS (as seis precondicoes)
       ADD CONSTRAINT ......... ck_..._valid_requires_printing_key NOT VALID
       VALIDATE CONSTRAINT .... PASS — convalidated = true
       COMMENT ON CONSTRAINT .. aplicado
       DROP INDEX ............. uq_cvir_job_card_type_bridge_legacy removido
       COMMIT ................. sucesso

   Migration history criada:
       version 20260913181725
       name    finalize_staging_identity_and_drop_compatibility_bridge

   Validada pelo harness: Query 2824 v2.6, BLOCO IV — Secao S24
   (4 assercoes PASS) e Secao S25 (5 assercoes PASS).

   ESTE FOI O PONTO DE NAO RETORNO, e ele ja foi atravessado. Uma linha
   VALID sem a chave printing_profile_id deixou de ser representavel
   neste banco. A compatibilidade transitoria da Query 2179 expirou no
   mesmo instante, por construcao: o ramo legado testa a EXISTENCIA do
   bridge, e o bridge nao existe mais.

   Os GUARDS permanecem no codigo. Uma reexecucao pararia no GUARD 1
   (bridge ausente) ou no GUARD 4 (constraint final ja existe) — os dois
   por desenho, para falhar alto em vez de fingir sucesso.
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2184 - Finalize Staging Identity and Drop Compatibility Bridge
Versão......: 2.0
Status......: MIGRATION — CONFIRMADO EXECUTADO / LIVE — PHASE E CLOSED
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Promovida...: 2026-09-13 — TECHNICAL-CLOSEOUT-PROMOTION-01
Origem......: database/proposals/2026-09-12-card-variants-printing-routing/
              2184_drop_staging_identity_bridge_index.sql
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§12)
               + STAGING-REVISION-01 (R1, R2-D, R5, R6)
Fase........: PHASE E do rollout — ULTIMA migration da frente

Alterações da versão 2.0 (STAGING-REVISION-01):
- ESCOPO AMPLIADO. A v1.0 só removia o bridge. Remover o bridge sem
  colocar nada no lugar deixaria as linhas "VALID + chave ausente"
  simplesmente SEM proteção nenhuma — o buraco que o bridge tapava
  ficaria aberto. A v2.0 fecha o estado estruturalmente ANTES de
  remover a proteção transitória.
- NOVA CONSTRAINT ck_catalog_variant_import_row_valid_requires_printing_key
  (invariante final de normalized_data, R5).
- GUARD 0 — autorização explícita de fase (R1).
- GUARDS 1..6 — as seis precondições do §6 do mandato, todas provadas
  ANTES de qualquer modificação. Qualquer uma falhando: STOP sem
  alteração parcial (tudo em uma transação).
- Renomeada de "Drop Staging Identity Bridge Index" para refletir o
  escopo real.

-------------------------------------------------------------------------------
O INVARIANTE FINAL (R5)
-------------------------------------------------------------------------------
    validation_status <> 'VALID'
        OR normalized_data ? 'printing_profile_id'

Lido em português: se uma linha está VALID, a chave printing_profile_id
EXISTE. NEEDS_REVIEW e os demais estados podem manter a chave ausente —
e devem, porque "ainda não sei" é uma informação legítima.

O tipo do valor já era garantido desde a Query 2177, por
ck_catalog_variant_import_row_printing_profile_shape: JSON null ou
string UUID válida. As duas constraints juntas dão o contrato completo:

    VALID  ->  chave presente  ->  valor é null OU UUID válido

Sobre `?` vs jsonb_typeof: para esta constraint os dois funcionam, mas
`normalized_data ? 'printing_profile_id'` é o operador de existência de
chave — diz exatamente o que se quer dizer, e é o que um leitor futuro
precisa entender sem consultar a tabela de jsonb_typeof.

Esta constraint NÃO pode existir durante A/B: ela invalidaria as 5.653
linhas legadas no ato. É por isso que ela mora aqui, e não na 2177.

-------------------------------------------------------------------------------
ADD NOT VALID + VALIDATE — POR QUE EM DOIS PASSOS
-------------------------------------------------------------------------------
ADD CONSTRAINT ... NOT VALID registra a regra sem varrer a tabela (e já
passa a valer para toda escrita nova). VALIDATE CONSTRAINT faz a
varredura com um lock mais fraco (SHARE UPDATE EXCLUSIVE) e é o passo
que PROVA que nenhuma linha existente viola.

Em ~6 mil linhas a diferença de custo é irrelevante. O que importa é
outra coisa: separar "declarar" de "provar" deixa o VALIDATE ser o
ponto explícito onde a prova acontece — que é literalmente o que o
mandato pede ("provar que a constraint pode ser criada/validada após o
backfill"). Os dois passos ocorrem na MESMA transação: ou a regra passa
a valer e está provada, ou nada aconteceu.

-------------------------------------------------------------------------------
POR QUE NAO MANTER O BRIDGE PARA SEMPRE
-------------------------------------------------------------------------------
Porque ele protege exatamente o estado que o contrato novo considera
INVALIDO: row com Variant Type resolvido e Printing NAO resolvido.
Depois do rollout, esse estado so deve existir transitoriamente, dentro
de uma transacao de resolucao — nunca commitado como VALID.

Manter o bridge seria manter viva uma identidade paralela, e com ela a
possibilidade de uma row escapar dos dois indices canonicos sem que nada
reclame.

-------------------------------------------------------------------------------
EFEITO COLATERAL DESEJADO — A COMPATIBILIDADE TRANSITÓRIA EXPIRA AQUI
-------------------------------------------------------------------------------
A Query 2179 v1.1 condiciona seu ramo de compatibilidade legada à
EXISTÊNCIA deste bridge. Ao removê-lo, o confirm volta, no mesmo
instante e sem nenhuma migration adicional, a rejeitar chave ausente
incondicionalmente.

Isso é de propósito: a compatibilidade transitória não pode virar
contrato permanente, e a forma de garantir isso é amarrá-la ao objeto
físico que define a janela — não à memória de quem operou o rollout.

Regras de Negócio:
- Nenhuma linha e lida, escrita ou movida.
- Os dois indices canonicos permanecem intactos.
- Fail-closed: qualquer precondicao falhando, nada e alterado.

Pré-requisitos:
- Query 2177 - criou o bridge e os dois índices canônicos.
- Query 2183 - reconciliou o legado (PHASE D).
- Edge Function nova em produção como writer vigente (PHASE C).

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Versão inicial (2026-09-12).** Removia apenas o bridge.
        Substituída antes da execução: remover a proteção transitória sem
        fechar o estado deixaria o buraco aberto. |
| 2.0 | **Constraint final + seis guards + escopo ampliado (2026-09-12).**
        Esta é a versão executada e confirmada no banco físico em
        2026-09-13, via apply_migration (version 20260913181725). |
|     | **PROMOÇÃO (2026-09-13, TECHNICAL-CLOSEOUT-PROMOTION-01).** Copiada
        de database/proposals/ para database/migrations/ nesta mesma versão
        2.0. O SQL executável permanece idêntico ao artefato executado no
        LIVE; só o cabeçalho registra o estado final (Status, Promovida,
        Origem). A proposal original é preservada como histórico. |
===============================================================================
*/

BEGIN;

-- =========================================================================
-- GUARD 0 — AUTORIZAÇÃO DE FASE (R1).
--
--     BEGIN;
--     SET LOCAL mimikyu.phase_e_authorized = 'CONFIRMED';
--     \i 2184_drop_staging_identity_bridge_index.sql
--
-- O QUE ESTE GUC É — E O QUE ELE NÃO É
--
-- É: uma CONFIRMAÇÃO OPERACIONAL EXPLÍCITA DO EXECUTOR, que impede que
-- este ponto de não retorno seja atravessado por acidente.
--
-- NÃO é: prova técnica de que a Edge nova é a writer vigente. O banco
-- não consegue verificar isso. Este SET LOCAL registra uma afirmação,
-- não a verifica.
--
-- A autorização REAL da PHASE E é a conjunção de:
--   (a) PASS do harness da fase anterior — Query 2824, BLOCO III (S23);
--   (b) checklist operacional do rollout (README, §4);
--   (c) os GUARDS 1..6 abaixo, que são a única prova TÉCNICA desta
--       Query — e essa sim o banco verifica;
--   (d) o operador executar explicitamente o SET LOCAL abaixo.
--
-- O GUC é (d). A prova de verdade é (c).
-- =========================================================================
DO $phase$
BEGIN
    IF COALESCE(current_setting('mimikyu.phase_e_authorized', true), '') <> 'CONFIRMED' THEN
        RAISE EXCEPTION 'PHASE_E_NOT_AUTHORIZED: esta Query é o ponto de não retorno do rollout de Impressão. Só execute com a Edge nova em produção e a PHASE D concluída, declarando na mesma transação: SET LOCAL mimikyu.phase_e_authorized = ''CONFIRMED''; STOP.';
    END IF;
END;
$phase$;

-- =========================================================================
-- GUARDS 1..6 — AS SEIS PRECONDIÇÕES (§6). Todas provadas ANTES de
-- qualquer modificação. Nada de alteração parcial.
-- =========================================================================
DO $guard$
DECLARE
    v_absent INTEGER;
    v_conflicts INTEGER;
BEGIN
    -- (1) O bridge ainda existe. Se não existir, ou a 2177 não rodou, ou
    --     esta Query já rodou — nos dois casos, parar e reauditar.
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_indexes
         WHERE schemaname = 'public'
           AND indexname = 'uq_cvir_job_card_type_bridge_legacy'
    ) THEN
        RAISE EXCEPTION 'PHASE_E_BRIDGE_NOT_FOUND: uq_cvir_job_card_type_bridge_legacy não existe. A Query 2177 foi aplicada? Ou esta Query já rodou? STOP.';
    END IF;

    -- (2) Os DOIS índices finais existem. Remover o bridge sem eles
    --     deixaria o staging inteiro sem identidade.
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_indexes
                    WHERE schemaname = 'public'
                      AND indexname = 'uq_cvir_job_card_type_no_printing')
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_indexes
                    WHERE schemaname = 'public'
                      AND indexname = 'uq_cvir_job_card_type_printing')
    THEN
        RAISE EXCEPTION 'PHASE_E_CANONICAL_INDEXES_MISSING: um dos dois índices canônicos de identidade de staging não existe. Remover o bridge agora deixaria linhas sem nenhuma proteção de unicidade. STOP.';
    END IF;

    -- (3) O CHECK de forma da Query 2177 está no lugar. Sem ele, a
    --     constraint nova garantiria presença mas não formato.
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
         WHERE conrelid = 'public.catalog_variant_import_row'::regclass
           AND conname = 'ck_catalog_variant_import_row_printing_profile_shape'
    ) THEN
        RAISE EXCEPTION 'PHASE_E_SHAPE_CHECK_MISSING: ck_catalog_variant_import_row_printing_profile_shape não existe. A Query 2177 foi aplicada? STOP.';
    END IF;

    -- (4) A constraint final ainda não existe (idempotência honesta:
    --     falha alto em vez de fingir sucesso).
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
         WHERE conrelid = 'public.catalog_variant_import_row'::regclass
           AND conname = 'ck_catalog_variant_import_row_valid_requires_printing_key'
    ) THEN
        RAISE EXCEPTION 'PHASE_E_ALREADY_FINALIZED: a constraint final já existe. Esta Query já rodou parcialmente? Reauditar o estado antes de prosseguir. STOP.';
    END IF;

    -- (5) VALID com chave ausente = 0. É a prova de que a PHASE D
    --     rodou E de que nenhum writer antigo voltou a escrever depois.
    --     É também a prova de que a constraint nova PODE ser validada.
    SELECT count(*) INTO v_absent
      FROM public.catalog_variant_import_row r
     WHERE r.validation_status = 'VALID'
       AND jsonb_typeof(r.normalized_data -> 'printing_profile_id') IS NULL;

    IF v_absent <> 0 THEN
        RAISE EXCEPTION 'PHASE_E_PREMATURE: % row(s) VALID ainda estão sem a chave printing_profile_id. O writer antigo ainda está ativo ou a Query 2183 não rodou. STOP — remover o bridge agora deixaria essas rows sem nenhuma proteção de unicidade, e a constraint final não validaria.', v_absent;
    END IF;

    -- (6) Nenhuma linha conflita nos índices finais. O bridge pode
    --     estar mascarando uma colisão que só apareceria depois de
    --     removido — e aí seria tarde.
    SELECT count(*) INTO v_conflicts
      FROM (
            SELECT 1
              FROM public.catalog_variant_import_row r
             WHERE (r.normalized_data ->> 'variant_type_id') IS NOT NULL
             GROUP BY r.job_id, r.card_id,
                      (r.normalized_data ->> 'variant_type_id'),
                      jsonb_typeof(r.normalized_data -> 'printing_profile_id'),
                      (r.normalized_data ->> 'printing_profile_id')
            HAVING count(*) > 1
      ) AS dup;

    IF v_conflicts <> 0 THEN
        RAISE EXCEPTION 'PHASE_E_IDENTITY_CONFLICT: % grupo(s) de linhas colidiriam nos índices canônicos de identidade. STOP — reconciliar o staging antes de remover o bridge.', v_conflicts;
    END IF;
END;
$guard$;

-- =========================================================================
-- INVARIANTE FINAL (R5) — declarar e, em seguida, PROVAR.
-- =========================================================================
ALTER TABLE public.catalog_variant_import_row
    ADD CONSTRAINT ck_catalog_variant_import_row_valid_requires_printing_key
    CHECK (
        validation_status <> 'VALID'
        OR normalized_data ? 'printing_profile_id'
    ) NOT VALID;

ALTER TABLE public.catalog_variant_import_row
    VALIDATE CONSTRAINT ck_catalog_variant_import_row_valid_requires_printing_key;

COMMENT ON CONSTRAINT ck_catalog_variant_import_row_valid_requires_printing_key
    ON public.catalog_variant_import_row IS
    'Invariante final do roteamento de Impressão (PHASE E): linha VALID tem obrigatoriamente a chave printing_profile_id. O TIPO do valor é garantido por ck_catalog_variant_import_row_printing_profile_shape. NEEDS_REVIEW pode manter a chave ausente — "ainda não sei" é estado legítimo.';

-- =========================================================================
-- REMOÇÃO DA PROTEÇÃO TRANSITÓRIA — só agora, com o estado já fechado.
-- =========================================================================
DROP INDEX public.uq_cvir_job_card_type_bridge_legacy;

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   ADD CONSTRAINT (NOT VALID) + VALIDATE CONSTRAINT + COMMENT + DROP INDEX.
--
--   Estado final:
--     - DOIS indices de identidade de staging:
--         uq_cvir_job_card_type_no_printing
--         uq_cvir_job_card_type_printing
--     - DUAS constraints de contrato de normalized_data:
--         ck_catalog_variant_import_row_printing_profile_shape   (tipo)
--         ck_catalog_variant_import_row_valid_requires_printing_key (presença)
--     - VALID + chave ausente: IMPOSSIVEL no banco.
--     - Query 2179: ramo de compatibilidade legada extinto automaticamente.
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Secoes S24 e S25 (BLOCO IV).
-- ============================================================================
