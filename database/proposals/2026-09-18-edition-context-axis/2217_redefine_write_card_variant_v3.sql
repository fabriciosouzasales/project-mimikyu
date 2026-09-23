-- ============================================================================
-- Query 2217 — internal.write_card_variant() v3.0 (SETE argumentos) — EXPAND
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 2.0
-- v2.0: EDITION-CONTEXT-AXIS-WRITER-EXPAND-CONTRACT-CORRECTION-01
-- v1.0: CORREÇÃO 7 da GATE-A-FINAL-CORRECTION-01
--
-- ----------------------------------------------------------------------------
-- v2.0 — POR QUE O DROP SAIU DAQUI
-- ----------------------------------------------------------------------------
--   A v1.0 fazia CREATE da de sete E DROP da de seis no mesmo arquivo, com um
--   guard que exigia a 2218 já aplicada. Isso forçava a ordem 2218 → 2217 e
--   criava uma janela real: depois da 2218 e antes da 2217, o confirm chamava
--   um writer de sete argumentos que AINDA NAO EXISTIA. RPC instalada e
--   inexecutável — mesmo sob FREEZE, é um estado que não queremos.
--
--   A troca passa a seguir EXPAND → SWITCH → CONTRACT:
--
--     2217 (EXPAND)   cria a de SETE · PRESERVA a de SEIS · não dropa nada
--     2218 (SWITCH)   confirm passa a chamar SOMENTE a de sete
--     2223 (CONTRACT) prova que ninguém usa a de seis · então dropa
--
--   Em nenhum momento existe caller apontando para assinatura ausente. Cada
--   etapa é individualmente reversível e o sistema é executável entre elas.
--
--   O DROP e a prova negativa de callers migraram INTEGRALMENTE para a
--   Query 2223. Nenhum wrapper de compatibilidade foi criado: a de seis
--   permanece exatamente como está (2143 v2.0), viva e inalterada, até a 2223.
--
-- BASE: database/schema/2143_create_internal_write_card_variant_function.sql
--       v2.0 (CANÔNICA / LIVE). Este arquivo é o ESTADO FINAL proposto —
--       corpo inteiro, não um patch — porque o projeto aplica Queries
--       individualmente e `CREATE OR REPLACE FUNCTION` substitui o corpo todo.
--
-- ----------------------------------------------------------------------------
-- ACHADO DE AUDITORIA QUE MUDA O DESENHO DE CONCORRÊNCIA
-- ----------------------------------------------------------------------------
--   O CONCURRENCY-DESIGN.md dizia que matching e lock aconteciam AQUI. Não
--   acontecem. A leitura do código canônico (2143 v2.0) mostra que esta
--   função é um INSERT puro: não faz SELECT de matching, não toma lock e não
--   aloca variant_order — o próprio cabeçalho da v2.0 diz que
--   `p_variant_order` "é sempre calculado pelo chamador (Query 2145)".
--
--   Portanto o lock na Card, o matching por identidade e o tratamento de
--   `unique_violation` pertencem à Query 2218 (admin_confirm_catalog_variant_
--   import), NÃO a esta. Esta função permanece deliberadamente burra.
--
-- ----------------------------------------------------------------------------
-- v3.0 — O QUE MUDA, E SÓ ISSO
-- ----------------------------------------------------------------------------
--   + p_edition_context_profile_id UUID  (SÉTIMO argumento, SEM DEFAULT)
--   + validação de existência do profile, quando informado
--   + a coluna entra no INSERT
--
--   NADA MAIS muda: mesmo schema `internal`, mesmo SECURITY DEFINER, mesmo
--   `search_path = ''`, mesmos REVOKEs, mesmos códigos de erro, mesma recusa
--   de UPDATE, mesmo tratamento de is_default (nunca no INSERT).
--
-- POR QUE SEM `DEFAULT NULL` — mesmo argumento que a v2.0 usou para Printing
--   Um DEFAULT manteria compilando a chamada de seis argumentos. Qualquer
--   writer futuro que esquecesse o contexto gravaria NULL SILENCIOSAMENTE — e
--   NULL aqui não é placeholder, é o valor semanticamente carregado "sem
--   contexto de edição". Sem o DEFAULT, o erro de omissão vira ERRO DE
--   COMPILAÇÃO. É a mesma decisão, pelo mesmo motivo, no mesmo lugar.
--
-- O OVERLOAD É DELIBERADO E TEMPORÁRIO
--   `CREATE OR REPLACE` com aridade diferente CRIA UM OVERLOAD — não
--   substitui. Na v1.0 isso era tratado como defeito a corrigir no mesmo
--   arquivo; na v2.0 é o mecanismo do EXPAND: as duas assinaturas coexistem
--   entre 2217 e 2223, e é justamente essa coexistência que elimina a janela
--   de RPC inexecutável.
--
--   O risco que o DROP existia para eliminar — o confirm antigo gravando
--   Variants sem o quarto componente — continua eliminado, mas por outro
--   meio: a 2218 (SWITCH) substitui o corpo do confirm, e a 2223 (CONTRACT)
--   só dropa depois de PROVAR que nenhum caller executável restou. A janela
--   de coexistência é curta, está sob FREEZE, e tem prova de saída.
--
-- ----------------------------------------------------------------------------
-- SAME-GAME: NÃO validado aqui, de propósito — AUTORIDADE É A QUERY 2224
-- ----------------------------------------------------------------------------
--   A autoridade do same-Game do terceiro eixo é
--   `internal.enforce_card_variant_edition_context_profile_game()` +
--   `trg_card_variant_edition_context_profile_game`, instalados pela
--   **Query 2224**, que espelha o que a `2170` já faz para Impressão.
--   Duplicar a regra aqui criaria duas fontes de verdade e uma delas ficaria
--   desatualizada — esta função valida EXISTÊNCIA e só.
--
--   ⚠️ CORREÇÃO DE PREMISSA (`BATCH9-2217-READINESS-CORRECTION-01`). Até a
--   v2.0, este cabeçalho afirmava que a autoridade era
--   `public.validate_card_variant_game_consistency`, *"que a Query 2220
--   estende para o terceiro eixo"*. **As duas metades eram falsas**, e a
--   auditoria provou mecanicamente:
--     · `validate_card_variant_game_consistency` (161:60-104) compara Card ×
--       **Variant Type**, nunca menciona `edition_context_profile_id`, e seu
--       trigger é `UPDATE OF card_id, variant_type_id` — não acorda para este
--       eixo;
--     · a `2220` redefine `variant_type_mapping_impact`/`_decision` — o read
--       contract do mapping de Variant Type — e não contém `CREATE TRIGGER`
--       nem toca naquela função.
--   Consequência: antes da `2224` **não existia** proteção server-side contra
--   `edition_context_profile_id` de outro Game. A `2224` fecha a lacuna e é
--   **pré-requisito desta Query** no DAG.
--
-- ORDEM NO ROLLOUT: 2224 (GUARD) → 2217 (EXPAND) → 2218 (SWITCH) →
--   2223 (CONTRACT). O número não é a ordem; o `DAG.md` é a autoridade.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---
-- GATE: a coluna precisa existir (Query 2208) antes de o writer gravá-la.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'card_variant'
           AND column_name = 'edition_context_profile_id'
    ) THEN
        RAISE EXCEPTION 'WRITER_V3_BLOCKED: card_variant.edition_context_profile_id nao existe. Rode a Query 2208 antes.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 2 ---
CREATE OR REPLACE FUNCTION internal.write_card_variant(
    p_mode TEXT,
    p_variant_id UUID,
    p_card_id UUID,
    p_variant_type_id UUID,
    p_variant_order INTEGER,
    p_printing_profile_id UUID,
    p_edition_context_profile_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_variant_id UUID;
BEGIN
    IF p_mode NOT IN ('CREATE', 'UPDATE') THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_INVALID_MODE: p_mode deve ser CREATE ou UPDATE (recebido: %).', p_mode;
    END IF;

    IF p_mode = 'UPDATE' THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_UPDATE_NOT_SUPPORTED: nenhum fluxo atual atualiza uma Card Variant existente — ela é tratada como UNCHANGED. Parâmetro reservado para uma necessidade futura ainda não desenhada.';
    END IF;

    -- p_mode = 'CREATE'
    IF p_variant_id IS NOT NULL THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_UNEXPECTED_ID: p_variant_id não deve ser informado em modo CREATE.';
    END IF;
    IF p_card_id IS NULL THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_MISSING_CARD: p_card_id é obrigatório em modo CREATE.';
    END IF;
    IF p_variant_type_id IS NULL THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_MISSING_TYPE: p_variant_type_id é obrigatório em modo CREATE.';
    END IF;
    IF p_variant_order IS NULL OR p_variant_order <= 0 THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_INVALID_ORDER: p_variant_order deve ser um inteiro positivo (recebido: %).', p_variant_order;
    END IF;

    -- Se um perfil de impressão foi informado, ele precisa existir. Same-Game
    -- NAO e checado aqui de proposito: o trigger da Query 2170 e a autoridade.
    IF p_printing_profile_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM public.card_printing_profile p WHERE p.id = p_printing_profile_id
       ) THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_PRINTING_PROFILE_NOT_FOUND: Perfil de Impressão % não encontrado.', p_printing_profile_id;
    END IF;

    -- v3.0 — MESMA disciplina para o terceiro eixo. Existência SIM; same-Game
    -- NAO: a autoridade e o trigger da Query 2224
    -- (internal.enforce_card_variant_edition_context_profile_game), espelho do
    -- que a 2170 faz para Impressao. NENHUMA criacao automatica. Jamais.
    IF p_edition_context_profile_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM public.card_edition_context_profile e WHERE e.id = p_edition_context_profile_id
       ) THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_EDITION_CONTEXT_NOT_FOUND: Perfil de Contexto de Edição % não encontrado.', p_edition_context_profile_id;
    END IF;

    INSERT INTO public.card_variant
        (card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id)
    VALUES
        (p_card_id, p_variant_type_id, p_variant_order, p_printing_profile_id, p_edition_context_profile_id)
    RETURNING id INTO v_variant_id;

    RETURN v_variant_id;
END;
$$;

REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID, UUID) FROM anon;
REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID, UUID) FROM authenticated;

-- ---------------------------------------------------------------- PASSO 3 ---
-- POSTCHECK DO EXPAND. As DUAS assinaturas devem existir, e ambas limpas.
-- O DROP da de seis NÃO acontece aqui — pertence à Query 2223 (CONTRACT).
--
-- HARDENING B1/B2/B3 (BATCH9-2217-READINESS-CORRECTION-01). A versão anterior
-- deste bloco provava menos do que o contrato exige, em três frentes:
--   B1  `v_cfg::TEXT LIKE '%search_path=%'` casava com `search_path=public` —
--       em SECURITY DEFINER isso é vetor de search-path hijacking. Trocado por
--       igualdade exata de array. Mesma classe de defeito já corrigida no
--       `5812` (02F) e já evitada na `2214`.
--   B2  `information_schema.role_routine_grants` não expressa PUBLIC como
--       grantee, é filtrada pelo usuário corrente, e NÃO enxerga o caso
--       decisivo — `proacl IS NULL`, que é ACL padrão = EXECUTE a PUBLIC.
--       Trocado por `proacl` + `aclexplode` por OID, fail-closed no nulo.
--       **Endurecido em `CORRECTION-02`:** o critério deixou de ser "não tem
--       PUBLIC/anon/authenticated" e passou a ser **OWNER-ONLY** —
--       `count(DISTINCT grantee) = 1` **e** esse grantee `= proowner`.
--       Barrar por lista de roles proibidas é sempre incompleto: um grant a
--       `service_role`, a um role de BI ou a qualquer role futura passava e
--       só gerava `WARNING`. Agora **qualquer** principal além do owner
--       levanta exceção, em cada assinatura, independentemente.
--   B3  os gates distinguiam as assinaturas só por `pronargs`. Uma overload
--       de 7 args com tipos errados passaria. Trocado por resolução via
--       `to_regprocedure` das DUAS assinaturas exatas.
DO $$
DECLARE
    c_sig6 CONSTANT TEXT := 'internal.write_card_variant(text,uuid,uuid,uuid,integer,uuid)';
    c_sig7 CONSTANT TEXT := 'internal.write_card_variant(text,uuid,uuid,uuid,integer,uuid,uuid)';
    v_oid6      OID;
    v_oid7      OID;
    v_n         INT;
    v_def       INT;
    v_sec       BOOLEAN;
    v_cfg       TEXT[];
    v_acl_nula  BOOLEAN;
    v_owner     OID;
    v_own_nome  TEXT;
    v_own_tem   BOOLEAN;
    v_n_grantee INT;
    v_quem6     TEXT;
    v_quem7     TEXT;
    v_extras    TEXT;
BEGIN
    -- B3 · E1 — a de SETE nasceu, com os TIPOS EXATOS.
    v_oid7 := to_regprocedure(c_sig7)::OID;
    IF v_oid7 IS NULL THEN
        RAISE EXCEPTION 'EXPAND_V3_MISSING: assinatura % nao existe. Tipos exatos sao parte do contrato — pronargs=7 nao basta.', c_sig7;
    END IF;

    -- B3 · E2 — a de SEIS foi PRESERVADA, com os TIPOS EXATOS. Se sumiu,
    -- alguem dropou fora de contrato e o confirm vivo (que ainda chama com
    -- seis) esta quebrado agora.
    v_oid6 := to_regprocedure(c_sig6)::OID;
    IF v_oid6 IS NULL THEN
        RAISE EXCEPTION 'EXPAND_V3_LEGACY_LOST: a assinatura % deveria estar PRESERVADA neste passo. O DROP pertence a Query 2223.', c_sig6;
    END IF;

    -- B3 · E3 — exatamente DUAS overloads do nome, nem mais. Qualquer terceira
    -- assinatura e ambiguidade de resolucao esperando acontecer.
    SELECT count(*),
           COALESCE(string_agg(p.oid::REGPROCEDURE::TEXT, ' | ')
                      FILTER (WHERE p.oid NOT IN (v_oid6, v_oid7)), '(nenhuma)')
      INTO v_n, v_extras
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

    IF v_n <> 2 THEN
        RAISE EXCEPTION 'EXPAND_V3_UNEXPECTED_SIGNATURES: esperadas exatamente 2 assinaturas durante o EXPAND, encontradas %. Fora do contrato: %.', v_n, v_extras;
    END IF;
    IF v_extras <> '(nenhuma)' THEN
        RAISE EXCEPTION 'EXPAND_V3_UNEXPECTED_SIGNATURES: assinatura(s) fora do contrato presentes: %.', v_extras;
    END IF;

    -- B1 · E4 — a de SETE: 0 DEFAULT, SECURITY DEFINER, search_path EXATO.
    SELECT p.pronargdefaults, p.prosecdef, p.proconfig
      INTO v_def, v_sec, v_cfg
      FROM pg_proc p WHERE p.oid = v_oid7;

    IF v_def <> 0 THEN
        RAISE EXCEPTION 'WRITER_V3_HAS_DEFAULT: nenhum argumento pode ter DEFAULT (obtido %).', v_def;
    END IF;
    IF v_sec IS NOT TRUE THEN
        RAISE EXCEPTION 'WRITER_V3_NOT_SECDEF: SECURITY DEFINER perdido na de 7 args.';
    END IF;
    IF v_cfg IS DISTINCT FROM ARRAY['search_path=""']::TEXT[] THEN
        RAISE EXCEPTION 'WRITER_V3_SEARCH_PATH: a de 7 args deve ter proconfig exatamente ARRAY[''search_path=""''], obtido %.', COALESCE(v_cfg::TEXT, '(NULO)');
    END IF;

    -- B1 · E5 — a de SEIS preservou contrato: 0 DEFAULT, SECDEF, search_path
    -- EXATO. Nada foi tocado nela; este gate prova que continua intacta.
    SELECT p.pronargdefaults, p.prosecdef, p.proconfig
      INTO v_def, v_sec, v_cfg
      FROM pg_proc p WHERE p.oid = v_oid6;

    IF v_def <> 0 THEN
        RAISE EXCEPTION 'EXPAND_V3_LEGACY_HAS_DEFAULT: a de 6 args ganhou DEFAULT (obtido %) — contrato da 2143 v2.0 violado.', v_def;
    END IF;
    IF v_sec IS NOT TRUE THEN
        RAISE EXCEPTION 'EXPAND_V3_LEGACY_NOT_SECDEF: a de 6 args perdeu SECURITY DEFINER.';
    END IF;
    IF v_cfg IS DISTINCT FROM ARRAY['search_path=""']::TEXT[] THEN
        RAISE EXCEPTION 'EXPAND_V3_LEGACY_SEARCH_PATH: a de 6 args deve ter proconfig exatamente ARRAY[''search_path=""''], obtido %.', COALESCE(v_cfg::TEXT, '(NULO)');
    END IF;

    -- B2 · E6 — ACL **OWNER-ONLY**, fail-closed, provada INDEPENDENTEMENTE
    -- para CADA assinatura. `internal.write_card_variant` nao e contrato RPC:
    -- e alcancavel so por outra funcao SECURITY DEFINER do mesmo owner
    -- (2143, "Regras de Negocio"). Logo o unico principal que pode ter EXECUTE
    -- e o proprio owner.
    --
    -- Nao se barra por lista de roles proibidas — toda lista e incompleta
    -- (service_role, um role de BI, qualquer role futura). A prova e por
    -- CARDINALIDADE + IDENTIDADE: exatamente UM grantee, e esse grantee E o
    -- proowner. Qualquer outro principal, nomeado ou nao, reprova.
    --
    -- ASSIMETRIA NAO E O GATE. Cada ACL e verificada por si; a igualdade entre
    -- as duas e CONSEQUENCIA de ambas serem owner-only, nunca o criterio —
    -- duas ACLs igualmente erradas passariam num teste de igualdade.

    -- E6.a — a de SETE.
    SELECT p.proacl IS NULL, p.proowner, pg_get_userbyid(p.proowner)
      INTO v_acl_nula, v_owner, v_own_nome
      FROM pg_proc p WHERE p.oid = v_oid7;

    IF v_acl_nula THEN
        RAISE EXCEPTION 'WRITER_V3_ACL_DEFAULT: proacl NULL na de 7 args — ACL padrao concede EXECUTE a PUBLIC. O REVOKE nao surtiu efeito.';
    END IF;

    SELECT count(DISTINCT a.grantee),
           COALESCE(bool_or(a.grantee = v_owner), false),
           COALESCE(string_agg(DISTINCT CASE WHEN a.grantee = 0
                                             THEN 'PUBLIC'
                                             ELSE pg_get_userbyid(a.grantee) END, ', '),
                    '(ninguem)')
      INTO v_n_grantee, v_own_tem, v_quem7
      FROM pg_proc p, aclexplode(p.proacl) a
     WHERE p.oid = v_oid7 AND a.privilege_type = 'EXECUTE';

    IF NOT v_own_tem THEN
        RAISE EXCEPTION 'WRITER_V3_OWNER_SEM_EXECUTE: o owner (%) nao tem EXECUTE na de 7 args. Mantem EXECUTE: %.', v_own_nome, v_quem7;
    END IF;
    IF v_n_grantee <> 1 THEN
        RAISE EXCEPTION 'WRITER_V3_ACL_NAO_OWNER_ONLY: a de 7 args deve ter EXATAMENTE 1 grantee com EXECUTE (o owner %), encontrados %. Mantem EXECUTE: %. Qualquer principal alem do owner — PUBLIC, anon, authenticated, service_role ou outro — e violacao de contrato.', v_own_nome, v_n_grantee, v_quem7;
    END IF;

    -- E6.b — a de SEIS, verificada por si mesma, com o MESMO criterio.
    SELECT p.proacl IS NULL, p.proowner, pg_get_userbyid(p.proowner)
      INTO v_acl_nula, v_owner, v_own_nome
      FROM pg_proc p WHERE p.oid = v_oid6;

    IF v_acl_nula THEN
        RAISE EXCEPTION 'EXPAND_V3_LEGACY_ACL_DEFAULT: proacl NULL na de 6 args — ACL padrao concede EXECUTE a PUBLIC.';
    END IF;

    SELECT count(DISTINCT a.grantee),
           COALESCE(bool_or(a.grantee = v_owner), false),
           COALESCE(string_agg(DISTINCT CASE WHEN a.grantee = 0
                                             THEN 'PUBLIC'
                                             ELSE pg_get_userbyid(a.grantee) END, ', '),
                    '(ninguem)')
      INTO v_n_grantee, v_own_tem, v_quem6
      FROM pg_proc p, aclexplode(p.proacl) a
     WHERE p.oid = v_oid6 AND a.privilege_type = 'EXECUTE';

    IF NOT v_own_tem THEN
        RAISE EXCEPTION 'EXPAND_V3_LEGACY_OWNER_SEM_EXECUTE: o owner (%) nao tem EXECUTE na de 6 args. Mantem EXECUTE: %.', v_own_nome, v_quem6;
    END IF;
    IF v_n_grantee <> 1 THEN
        RAISE EXCEPTION 'EXPAND_V3_LEGACY_ACL_NAO_OWNER_ONLY: a de 6 args deve ter EXATAMENTE 1 grantee com EXECUTE (o owner %), encontrados %. Mantem EXECUTE: %. O estado canonico registrado na 2143 e "so postgres (owner)".', v_own_nome, v_n_grantee, v_quem6;
    END IF;

    -- E7 — INFORMATIVO, nao condicao de seguranca. Chegando aqui, ambas ja
    -- foram provadas owner-only; se os owners diferirem entre as overloads
    -- isso e anomalia de propriedade, nao de privilegio. Reportado no NOTICE.
    RAISE NOTICE 'EXPAND OK — exatamente 2 assinaturas EXATAS (% preservada + % nova), 0 defaults nas duas, SECDEF, proconfig = search_path vazio, proacl nao-nulo. ACL OWNER-ONLY provada independentemente em cada uma: 6 args -> unico grantee com EXECUTE = % ; 7 args -> % . CONTRACT = Query 2223.',
                 c_sig6, c_sig7, v_quem6, v_quem7;
END $$;

-- ============================================================================
-- PAYLOAD BOUNDS: inalterados. Esta função grava UMA linha por chamada; o
--   limite de lote é do chamador (2218), não daqui.
-- MENSAGENS: todos os códigos de erro da v2.0 preservados literalmente. O
--   único código novo é INTERNAL_WRITE_CARD_VARIANT_EDITION_CONTEXT_NOT_FOUND,
--   espelhando o de Printing.
-- LOCKS: nenhum tomado aqui, nem antes nem agora. Ver 2218.
--
-- ESTADO APÓS ESTA QUERY (EXPAND):
--   internal.write_card_variant  ......... 2 assinaturas
--     (TEXT,UUID,UUID,UUID,INTEGER,UUID)         6 args — 2143 v2.0, INTACTA
--     (TEXT,UUID,UUID,UUID,INTEGER,UUID,UUID)    7 args — v3.0, NOVA
--   admin_confirm_catalog_variant_import ... ainda chama a de SEIS
--   → sistema executável. Nenhum caller aponta para assinatura ausente.
--
-- PRÓXIMOS PASSOS OBRIGATÓRIOS, NESTA ORDEM:
--   2218 (SWITCH)   → confirm passa a chamar SOMENTE a de sete
--   2223 (CONTRACT) → prova negativa de callers + DROP da de seis
--
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
-- ============================================================================
COMMIT;
