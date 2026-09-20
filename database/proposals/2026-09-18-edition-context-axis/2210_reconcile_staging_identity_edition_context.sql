-- ============================================================================
-- Query 2210 — Identidade de catalog_variant_import_row com Edition Context
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 2.0
--
-- v2.0 (GATE-A-FINAL-CORRECTION-01):
--   C1 os DROPs dos dois indices antigos estavam COMENTADOS. Migraram para a
--      Query 2216, executavel e auditavel.
--   C2 CONCURRENTLY REMOVIDO — indice normal sob FREEZE (ver 2209 v2.0).
--   C5 o guard nasce **PERMISSIVO**: VALID-requires-edition-context-key foi
--      MOVIDO para a Query 2214, que so entra DEPOIS do backfill (2212).
--      Criar o guard antes do backfill faria as rows VALID legadas falharem
--      em qualquer UPDATE. (A cifra "24.020" da v1.x estava STALE — o LIVE
--      media 24.372. Nenhum artefato compara com constante de staging.)
--        2210 (shape permissivo) -> 2212 (backfill) -> 2832 (prova) -> 2214.
-- BLOCKER 1 da CORRECTION-01
--
-- v1.1 (EDITION-CONTEXT-AXIS-GATE-A-01):
--   B1 regra normativa de REBUILD do indice (o Gate A a declarava BLOCKER se
--      ausente) — ver bloco CONTRATO DE ESTABILIDADE abaixo;
--   B2 guard de forma passa a validar FORMATO UUID, nao apenas jsonb_typeof.
--      O harness (caso S9) ja afirmava essa prova; o DDL v1.0 nao a tinha.
--   B3 CONCURRENTLY marcado como passo isolado — nao roda em transacao.
--
-- DEFEITO REAL, MEDIDO NO LIVE
--   uq_cvir_job_card_type_no_printing
--     (job_id, card_id, (normalized_data->>'variant_type_id'))
--     WHERE variant_type_id IS NOT NULL
--       AND jsonb_typeof(normalized_data->'printing_profile_id') = 'null'
--   uq_cvir_job_card_type_printing
--     (job_id, card_id, (normalized_data->>'variant_type_id'),
--                       (normalized_data->>'printing_profile_id'))
--     WHERE variant_type_id IS NOT NULL
--       AND jsonb_typeof(normalized_data->'printing_profile_id') = 'string'
--
--   Edition Context NÃO participa. Duas linhas do MESMO job, MESMA card,
--   MESMO finish, MESMO printing e Edition Contexts DIFERENTES colidiriam
--   incorretamente — seriam rejeitadas como duplicata sendo objetos distintos.
--   Exemplo real do corpus: a mesma Card com EVENT_WORLDS_2010+PLACEMENT_TOP_16
--   e com EVENT_WORLDS_2010+ROLE_STAFF (547 linhas em C colidem entre si).
--
-- CONTRATO TRI-STATE — agora em DOIS eixos
--   Herdado da 2184 para printing e ESTENDIDO a edition context. A distinção
--   só é possível por jsonb_typeof, porque `->>` colapsa 'null' e ausente:
--
--     chave AUSENTE          -> eixo NÃO RESOLVIDO  (NEEDS_REVIEW por construção)
--     chave = JSON null      -> RESOLVIDO SEM aquele eixo
--     chave = string UUID    -> RESOLVIDO COM aquele eixo
--
--   INVARIANTE VALID: uma linha VALID exige AS DUAS chaves presentes
--   (cada uma em JSON null ou UUID). Chave ausente ⇒ jamais VALID.
--
-- POR QUE NÃO `NULLS NOT DISTINCT` AQUI
--   Avaliado explicitamente e REJEITADO: a semântica tri-state vive DENTRO do
--   JSONB, não em colunas nuláveis. `normalized_data->>'x'` devolve SQL NULL
--   tanto para 'JSON null' quanto para 'chave ausente' — e esses dois estados
--   têm significado OPOSTO aqui. `NULLS NOT DISTINCT` os trataria como iguais,
--   apagando exatamente a distinção que o contrato precisa preservar.
--   A solução correta é uma expressão TOTAL que projeta os três estados em
--   valores textuais distintos e nunca nulos — abaixo.
-- ============================================================================

-- ============================================================================
-- CONTRATO DE ESTABILIDADE — NORMATIVO (GATE-A-01, item B1)
-- ----------------------------------------------------------------------------
-- internal.axis_identity_token() participa de um INDICE DE EXPRESSAO
-- (uq_cvir_row_identity). Postgres NAO revalida indices quando o corpo de uma
-- funcao IMMUTABLE muda: as entradas ja gravadas permanecem com o valor ANTIGO
-- e as novas passam a usar o valor NOVO. O resultado e um indice unico
-- SILENCIOSAMENTE CORROMPIDO — duplicatas entram sem erro nenhum.
--
-- REGRA, sem excecao:
--   1. Qualquer alteracao do COMPORTAMENTO desta funcao (o mapeamento de
--      estado para token, incluindo os literais 'A' / 'N' / 'U:') exige, na
--      MESMA migration:
--         REINDEX INDEX public.uq_cvir_row_identity;
--      ou DROP + CREATE do indice. SEM `CONCURRENTLY`, sob FREEZE — o
--      projeto nao usa DDL nao-transacional (Correcao 2).
--   2. NAO adicionar STRICT. A funcao e deliberadamente NAO-STRICT: com
--      p_data NULL ela retorna 'A' (total, nunca NULL). STRICT devolveria NULL
--      e quebraria a totalidade da expressao — mesma classe de corrupcao.
--   3. Alteracao apenas de COMMENT ou formatacao nao exige rebuild.
--
-- O harness 2830 (caso S2-BIS) verifica que o COMMENT abaixo contem esta
-- regra — a documentacao e parte do contrato, nao adorno.
-- ============================================================================

-- Projeção total e determinística dos três estados de um eixo.
-- IMMUTABLE: obrigatório para uso em índice.
-- Fronteira transacional EXPLÍCITA (TRANSACTION-BOUNDARY-CORRECTION-02).
-- Doze statements top-level: 2 funções, 1 índice de expressão, 1 trigger,
-- 3 REVOKE, 1 GRANT e COMMENTs. O índice `uq_cvir_row_identity` DEPENDE da
-- função `axis_identity_token` — função sem índice, ou índice sem o guard de
-- shape, são estados parciais aplicáveis. A ACL é parte do contrato, não
-- epílogo: a função criada sem os REVOKE ficaria executável por `anon`.
BEGIN;

CREATE OR REPLACE FUNCTION internal.axis_identity_token(p_data JSONB, p_key TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
    SELECT CASE jsonb_typeof(p_data -> p_key)
             WHEN 'string' THEN 'U:' || (p_data ->> p_key)  -- resolvido COM eixo
             WHEN 'null'   THEN 'N'                          -- resolvido SEM eixo
             ELSE               'A'                          -- ausente / não resolvido
           END;
$$;

COMMENT ON FUNCTION internal.axis_identity_token(JSONB, TEXT) IS
'Projeta o contrato TRI-STATE de um eixo de normalized_data em token textual total: U:<uuid> | N | A. Nunca retorna NULL — e por isso a identidade de staging nao depende de NULLS NOT DISTINCT nem de indices parciais por jsonb_typeof. CONTRATO DE ESTABILIDADE: participa do indice de expressao uq_cvir_row_identity. Qualquer mudanca de comportamento (mapeamento de estado para token) EXIGE REINDEX INDEX public.uq_cvir_row_identity na mesma migration (sem CONCURRENTLY, sob FREEZE — coerente com a decisao da Correcao 2), sob pena de corrupcao silenciosa do indice unico. NAO adicionar STRICT: a funcao e deliberadamente nao-strict para permanecer total.';

-- ----------------------------------------------------------------------------
-- IDENTIDADE ÚNICA DE STAGING — quatro componentes, UM índice
-- ----------------------------------------------------------------------------
-- Substitui os DOIS índices parciais atuais por um único índice total.
-- Vantagem direta sobre manter parciais: com dois eixos tri-state seriam
-- 3x3 = 9 combinações; nove predicados parciais são inauditáveis e qualquer
-- lacuna abre buraco silencioso.
-- Sem CONCURRENTLY: indice normal sob o FREEZE da etapa 0 (ver 2209 v2.0
-- para a comparacao A x B). Transacional, compativel com apply_migration.
CREATE UNIQUE INDEX uq_cvir_row_identity
    ON public.catalog_variant_import_row (
        job_id,
        card_id,
        (normalized_data ->> 'variant_type_id'),
        internal.axis_identity_token(normalized_data, 'printing_profile_id'),
        internal.axis_identity_token(normalized_data, 'edition_context_profile_id')
    )
    WHERE (normalized_data ->> 'variant_type_id') IS NOT NULL;

COMMENT ON INDEX public.uq_cvir_row_identity IS
'Identidade de staging em quatro componentes. Duas rows do mesmo job/card/finish/printing que diferem SOMENTE em edition_context_profile_id coexistem legitimamente. Substitui uq_cvir_job_card_type_no_printing e uq_cvir_job_card_type_printing.';

-- ============================================================================
-- OS DROPS NAO ESTAO AQUI — E DELIBERADO, E ERA UM BLOCKER NA v1.x.
--   uq_cvir_job_card_type_no_printing e uq_cvir_job_card_type_printing sao
--   removidos pela **Query 2216**, que antes de cada DROP prova que
--   uq_cvir_row_identity existe e e valida.
--   **2210 sem 2216 NAO entrega o eixo no staging**: enquanto os antigos
--   viverem, duas rows do mesmo job que diferem so em Edition Context
--   continuam colidindo.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- SHAPE GUARD + VALID-REQUIRES-KEY
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.guard_cvir_normalized_shape()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v_pp TEXT := jsonb_typeof(NEW.normalized_data -> 'printing_profile_id');
    v_ec TEXT := jsonb_typeof(NEW.normalized_data -> 'edition_context_profile_id');
BEGIN
    -- SHAPE: quando presente, cada eixo só pode ser 'null' ou 'string'.
    IF v_pp IS NOT NULL AND v_pp NOT IN ('null','string') THEN
        RAISE EXCEPTION 'CVIR_SHAPE_INVALID_PRINTING: printing_profile_id deve ser JSON null ou string UUID, recebido %.', v_pp;
    END IF;
    IF v_ec IS NOT NULL AND v_ec NOT IN ('null','string') THEN
        RAISE EXCEPTION 'CVIR_SHAPE_INVALID_EDITION_CONTEXT: edition_context_profile_id deve ser JSON null ou string UUID, recebido %.', v_ec;
    END IF;

    -- FORMATO UUID (GATE-A-01, B2): 'string' nao basta. Sem esta checagem,
    -- {"edition_context_profile_id":"banana"} passaria o guard e produziria o
    -- token 'U:banana' — uma identidade de staging valida apontando para nada.
    IF v_pp = 'string' AND (NEW.normalized_data ->> 'printing_profile_id')
         !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RAISE EXCEPTION 'CVIR_SHAPE_INVALID_PRINTING: printing_profile_id nao e UUID valido (%).',
              NEW.normalized_data ->> 'printing_profile_id';
    END IF;
    IF v_ec = 'string' AND (NEW.normalized_data ->> 'edition_context_profile_id')
         !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RAISE EXCEPTION 'CVIR_SHAPE_INVALID_EDITION_CONTEXT: edition_context_profile_id nao e UUID valido (%).',
              NEW.normalized_data ->> 'edition_context_profile_id';
    END IF;

    -- VALID-REQUIRES-KEY — ESTAGIO 1 (PERMISSIVO).
    -- Exige apenas o que o LIVE JA satisfaz hoje: variant_type_id e a chave
    -- printing_profile_id. A exigencia de edition_context_profile_id entra na
    -- Query 2214, DEPOIS do backfill 2212. Liga-la aqui quebraria todo UPDATE
    -- sobre as rows VALID legadas, que ainda nao tem a chave.
    IF NEW.validation_status = 'VALID' THEN
        IF (NEW.normalized_data ->> 'variant_type_id') IS NULL THEN
            RAISE EXCEPTION 'CVIR_VALID_REQUIRES_VARIANT_TYPE: row % marcada VALID sem variant_type_id.', NEW.id;
        END IF;
        IF v_pp IS NULL THEN
            RAISE EXCEPTION 'CVIR_VALID_REQUIRES_PRINTING_KEY: row % marcada VALID sem a chave printing_profile_id (ausente = nao resolvido).', NEW.id;
        END IF;
        -- edition_context_profile_id: NAO exigido nesta versao. Ver 2214.
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cvir_normalized_shape
    BEFORE INSERT OR UPDATE OF normalized_data, validation_status
    ON public.catalog_variant_import_row
    FOR EACH ROW EXECUTE FUNCTION internal.guard_cvir_normalized_shape();

REVOKE ALL ON FUNCTION internal.guard_cvir_normalized_shape() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION internal.axis_identity_token(JSONB, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION internal.axis_identity_token(JSONB, TEXT) TO authenticated;

COMMIT;

-- ============================================================================
-- SEQUENCIA OBRIGATORIA A PARTIR DAQUI  (ver DAG.md)
--   2210 (esta) .... shape PERMISSIVO + indice novo. Rows VALID legadas
--                    continuam gravaveis, sem a chave de Edition Context.
--   2212 ........... BACKFILL: grava JSON null nas rows que DEVEM receber e
--                    nao toca nas que NAO PODEM.
--   2832 ........... PROVA: zero chave ausente no universo exigido,
--                    idempotencia, counters e validation_status intactos.
--   2214 ........... SO ENTAO promove o guard para exigir a chave em VALID.
--   2216 ........... DROP dos dois indices antigos de staging.
-- Inverter qualquer par produz falha em massa ou janela desprotegida.
-- ============================================================================
