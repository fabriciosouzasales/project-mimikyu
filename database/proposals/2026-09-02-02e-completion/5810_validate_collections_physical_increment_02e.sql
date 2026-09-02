/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5810 - Validation Queries: Collections Physical Increment 02E (PROPOSTA)
Versão......: 4.1 (GRANT USAGE ON SEQUENCE test_results_id_seq —
               achado real de execução, ver v4.1 no changelog abaixo)
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (v2.0: COLLECTIONS-PHYSICAL-INCREMENT-02E-
               STAGING-REVISION-01, item 1 — BLOCKER: v1.0 era roteiro
               comentado, não execution-ready. v2.1: COLLECTIONS-
               PHYSICAL-INCREMENT-02E-STAGING-REVISION-02 — 5070/5071
               corrigidas de SECURITY INVOKER para SECURITY DEFINER
               (achado real: card/card_variant são admin-only sob RLS,
               ver cabeçalho de 5070 v2.0); bloco de segurança
               reescrito para provar comportamento real de Owner,
               outro usuário, anon, e o bypass de ownership, além de
               confirmar que o Catálogo Editorial continua fechado a
               SELECT direto mesmo com as funções SECURITY DEFINER.
               v2.2: COLLECTIONS-PHYSICAL-INCREMENT-02E-STAGING-FINAL-
               AUDIT-01, item 4 — owner_a/owner_b resolvidos em test_ctx
               agora excluem explicitamente public.admin_user, e cada
               um tem uma prova real de is_admin() = false logo após a
               impersonação (PRECOND-ADMIN-A/PRECOND-ADMIN-B), fail-
               loud se o fixture selecionado for admin.
               v3.0: COLLECTIONS-PHYSICAL-INCREMENT-02E-STAGING-FINAL-
               FIX-01 — (1) todo SELECT estrutural/de segurança que
               ficava fora de test_results (chk_collection_completion_
               policy, NOT NULL, PUBLIC/anon/authenticated EXECUTE,
               SECURITY DEFINER, STABLE, search_path, overload) virou
               asserção real via pg_temp.log_result(); (2) removidos os
               blocos SEC-C/SEC-D/SEC-E/SEC-F/SEC-G que só inseriam
               TRUE constante com "ver Caso X acima" — os rótulos do
               mandato agora estão embutidos diretamente nas chamadas
               reais dos Casos G/H/U/V/W; (3) adicionado um GATE FINAL
               (DO block com RAISE EXCEPTION se existir qualquer
               test_results.passed = false) entre o SELECT consolidado
               e o ROLLBACK — nenhum FAIL pode terminar em ROLLBACK
               silencioso interpretável como sucesso; (4) comentário
               novo esclarecendo que este script, rodando inteiramente
               dentro de BEGIN...ROLLBACK sem nunca dar COMMIT, não
               prova nem exercita os constraint triggers DEFERRABLE
               INITIALLY DEFERRED do 02D — essa invariante já foi
               validada em sua própria rodada, 02E não a revalida)
               v4.0: COLLECTIONS-PHYSICAL-INCREMENT-02E-STAGING-
               EXECUTION-SAFETY-FIX-01 — o comportamento do cliente/
               ferramenta de execução diante de um RAISE EXCEPTION no
               MEIO do batch (se ele continua enviando os statements
               restantes, incluindo o ROLLBACK) nunca foi confirmado
               (ver rodada STAGING-SOURCE-HANDOFF-01, resposta B: "não
               confirmado"). Removido o GATE FINAL (DO block com RAISE
               EXCEPTION) que antecedia o ROLLBACK — o script agora
               SEMPRE alcança ROLLBACK em execução normal, com ou sem
               FAIL registrado em test_results. A decisão de prosseguir
               com a implementação (aplicar 5067-5071, medir 5811,
               promover schema) passa a ser um gate de PROCESSO,
               fiscalizado pelo executor da rodada a partir do SELECT
               de total/passaram/falharam: falharam=0 -> prosseguir;
               falharam>0 -> IMPLEMENTATION STOP, reportar rótulos
               falhos, não executar 5811, não promover schema. As
               pré-condições fail-loud (fixtures insuficientes/
               inválidos) permanecem inalteradas — representam
               impossibilidade de executar a bateria, não resultado
               funcional FAIL.
               v4.1: COLLECTIONS-PHYSICAL-INCREMENT-02E-IMPLEMENTATION-
               01, Fase 3 — achado real de execução (primeira vez que
               este arquivo rodou contra Postgres de verdade): 5067-
               5071 aplicadas com sucesso (Fase 1), postcheck físico
               sem divergência (Fase 2), mas a primeira execução de
               5810 abortou com "permission denied for sequence
               test_results_id_seq" dentro de PRECOND-ADMIN-A. Causa:
               test_results.id é SERIAL, e pg_temp.log_result() é
               SECURITY INVOKER (roda com o privilégio de quem chama —
               authenticated/anon durante a bateria), então INSERT
               precisa de USAGE na sequence subjacente, não só
               INSERT/SELECT na tabela. Nenhuma das rodadas de staging/
               auditoria anteriores pegou isso porque nenhuma
               executou de fato. Corrigido: GRANT USAGE ON SEQUENCE
               test_results_id_seq TO authenticated, anon, adicionado
               logo após os GRANTs de test_results já existentes no
               Passo 3, para ambas as roles. Zero resíduo confirmado
               após o erro (transação da chamada com erro nunca
               chegou a COMMIT, nada persistiu). Nenhuma outra linha
               do arquivo alterada.

Descrição...:
Bateria de validação funcional REAL (não roteiro) para completion_
policy (5067), create_collection()/create_reference_based_card_set_
collection() estendidas (5068/5069) e os dois read models
collection_completion_summary()/collection_completion_positions()
(5070/5071). Requer que 5067-5071 já estejam aplicadas ao banco real
antes da execução — arquivo pensado para colar em UMA chamada
execute_sql, mesma sessão do início ao fim, dentro de uma transação
revertida (BEGIN...ROLLBACK), mesmo padrão de 5807/5808/5811.

Distinção estrutural exigida (COLLECTIONS-PHYSICAL-INCREMENT-02E-
STAGING-REVISION-01, item 2). 5067 já terá sido aplicada ANTES deste
arquivo rodar — não é possível testar literalmente "o backfill
acontecendo" depois que a migration já terminou. Por isso:

- STRUCTURAL POSTCHECK (blocos 1-4, [SQL ESTÁTICO], sem fixture): prova
  que o ESTADO FÍSICO pós-migration é o esperado — NOT NULL, CHECK
  existente, domínio de valores, zero linha física hoje fora das duas
  combinações permitidas. Casos A/B (nomeados "backfill" na lista
  original) são na verdade este postcheck — não uma prova de que o
  backfill *aconteceu corretamente no passado*, que não é mais
  observável.
- BEHAVIOR TEST (Casos C/D): prova comportamental real, via INSERT
  direto reversível (como role privilegiada — authenticated não tem
  INSERT em public.collection, então este teste roda ANTES da troca
  de role, mesmo raciocínio já usado nos "[ESTRUTURAL] bypass da RPC"
  de 5806/5808) dos 4 combos: OPEN_CURATION+NONE (PASS),
  REFERENCE_BASED+STANDARD_SET com Reference válida (PASS),
  OPEN_CURATION+STANDARD_SET (FAIL esperado), REFERENCE_BASED+NONE
  (FAIL esperado).

Mecanismo de log (mesmo espírito do padrão final de 5808 — pg_temp.
log_result() + tabela de resultados, impersonação real via set_config,
Casos A-Z realmente executados, SELECT final consolidado, ROLLBACK,
prova pós-ROLLBACK em chamada separada):

    CREATE TEMP TABLE test_results (case_label TEXT, passed BOOLEAN, detail TEXT);
    CREATE FUNCTION pg_temp.log_result(...) ...

Casos "deveria FALHAR" usam DO $$ ... EXCEPTION WHEN ... $$ (savepoint
implícito do bloco) para capturar o erro esperado sem abortar a
transação inteira — casos "deveria PASSAR" não têm tratamento de
exceção: se falharem, o script inteiro aborta (fail-loud, mesmo
princípio já usado em todas as pré-condições deste domínio).

Pré-condições (Passo 0): >= 2 Owners distintos com Inventory (Owner A
e Owner B, necessários para os Casos U/V/W/X — cross-user real, não
simulável com 1 único Owner); >= 1 Game; >= 1 Language; >= 1 Card com
>= 2 Card Variants (fixture de K/L); um Card Set pequeno com cobertura
de Card Variant 100% (fixture de completude real, Caso O — escolha de
fixture, não requisito arquitetural de STANDARD_SET, ver 5811 para a
mesma ressalva aplicada ao benchmark de performance).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

-- ================================================================
-- PASSO -1 (fora de transação) — baseline de resíduo
-- ================================================================
SELECT count(*) AS physical_card_count_antes
FROM public.physical_card
WHERE inventory_id IN (SELECT id FROM public.inventory);

SELECT count(*) AS collections_com_prefixo_antes
FROM public.collection
WHERE name LIKE 'VAL-TEST-02E-%';

SELECT count(*) AS card_sets_com_prefixo_antes
FROM public.card_set
WHERE code LIKE 'ZZVAL%';

-- ================================================================
-- PASSO 0 — BEGIN
-- ================================================================
BEGIN;

-- Criação real da infraestrutura de log — movida para ANTES de
-- qualquer postcheck (mandato STAGING-FINAL-FIX-01, item 1: nenhuma
-- checagem estrutural/de segurança pode existir apenas como SELECT
-- intermediário fora de test_results — o SELECT final consolidado
-- precisa, sozinho, dizer se a bateria passou ou falhou)
CREATE TEMP TABLE test_results (
    id          SERIAL PRIMARY KEY,
    case_label  TEXT NOT NULL,
    passed      BOOLEAN NOT NULL,
    detail      TEXT
);

CREATE FUNCTION pg_temp.log_result(p_case TEXT, p_passed BOOLEAN, p_detail TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO test_results (case_label, passed, detail) VALUES (p_case, p_passed, p_detail);
END;
$$;

-- ----------------------------------------------------------------
-- STRUCTURAL POSTCHECK 1 — chk_collection_completion_policy existe
-- (agora uma asserção real via log_result, não um SELECT solto)
-- ----------------------------------------------------------------
DO $$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_constraintdef(oid) INTO v_def
    FROM pg_constraint
    WHERE conrelid = 'public.collection'::regclass
      AND conname = 'chk_collection_completion_policy';
    PERFORM pg_temp.log_result('POSTCHECK-1 - chk_collection_completion_policy existe',
        v_def IS NOT NULL, COALESCE(v_def, 'constraint nao encontrada'));
END $$;

-- ----------------------------------------------------------------
-- STRUCTURAL POSTCHECK 2 — completion_policy NOT NULL
-- (idem — asserção real)
-- ----------------------------------------------------------------
DO $$
DECLARE
    v_nullable TEXT;
BEGIN
    SELECT is_nullable INTO v_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'collection'
      AND column_name = 'completion_policy';
    PERFORM pg_temp.log_result('POSTCHECK-2 - completion_policy e NOT NULL',
        v_nullable = 'NO', format('is_nullable=%s', v_nullable));
END $$;

-- ----------------------------------------------------------------
-- STRUCTURAL POSTCHECK 3 (Caso A/B) — zero linha física hoje fora do
-- domínio de valores permitido / fora das 2 combinações permitidas
-- (o que hoje se pode observar sobre o resultado do backfill — o
-- evento em si não é mais observável).
-- ----------------------------------------------------------------
DO $$
DECLARE
    v_fora_dominio        INT;
    v_combinacao_invalida INT;
BEGIN
    SELECT count(*) INTO v_fora_dominio
    FROM public.collection WHERE completion_policy NOT IN ('NONE', 'STANDARD_SET');

    SELECT count(*) INTO v_combinacao_invalida
    FROM public.collection
    WHERE NOT (
        (mode = 'OPEN_CURATION'   AND completion_policy = 'NONE')
        OR
        (mode = 'REFERENCE_BASED' AND completion_policy = 'STANDARD_SET')
    );

    PERFORM pg_temp.log_result('A - postcheck: zero linha fora do dominio NONE/STANDARD_SET',
        v_fora_dominio = 0, format('encontradas=%s', v_fora_dominio));
    PERFORM pg_temp.log_result('B - postcheck: zero combinacao mode/completion_policy invalida',
        v_combinacao_invalida = 0, format('encontradas=%s', v_combinacao_invalida));
END $$;

-- ----------------------------------------------------------------
-- STRUCTURAL POSTCHECK 4 — validate_collection_structural_identity()
-- não menciona completion_policy (permanece mutável)
-- ----------------------------------------------------------------
DO $$
DECLARE
    v_menciona BOOLEAN;
BEGIN
    SELECT pg_get_functiondef(p.oid) LIKE '%completion_policy%' INTO v_menciona
    FROM pg_proc p WHERE p.proname = 'validate_collection_structural_identity';
    PERFORM pg_temp.log_result('postcheck: completion_policy permanece mutavel (fora do trigger estrutural)',
        NOT v_menciona, format('menciona=%s', v_menciona));
END $$;

-- NOTA (mandato STAGING-FINAL-FIX-01, item 4 — correção de redação,
-- nenhum caso deste arquivo depende disso). Este script inteiro roda
-- dentro de BEGIN...ROLLBACK e NUNCA executa COMMIT. Os constraint
-- triggers DEFERRABLE INITIALLY DEFERRED do 02D (Queries 5057-5059,
-- que garantem REFERENCE_BASED <-> exatamente 1 collection_reference
-- CARD_SET) só disparam no COMMIT — logo, nada neste arquivo prova,
-- reprova ou de qualquer forma exercita esse comportamento; um
-- ROLLBACK não é evidência sobre uma checagem que nunca chega a
-- rodar. Essa invariante já foi validada em sua própria rodada
-- (02D-IMPLEMENTATION-01, Query 5808, execução real com COMMIT). O
-- Caso D (abaixo) só confirma que uma Collection REFERENCE_BASED/
-- STANDARD_SET criada com uma Reference já válida (não uma correção
-- tardia de uma Reference ausente) é aceita pelo CHECK IMEDIATO
-- chk_collection_completion_policy — nunca o trigger deferred. 02E
-- não precisa e não tenta revalidar 02D integralmente.

-- ================================================================
-- PRÉ-CONDIÇÕES (fail-loud)
-- ================================================================
DO $$
DECLARE
    v_owner_count    INT;
    v_game_count     INT;
    v_language_count INT;
    v_multi_count    INT;
    v_complete_count INT;
BEGIN
    -- Owners NÃO-ADMIN apenas (mandato STAGING-FINAL-AUDIT-01, item 4):
    -- os testes de segurança devem provar o comportamento de um usuário
    -- comum, nunca de um admin (que teria caminho de leitura adicional
    -- via catalog_admin_select, mascarando um eventual bug de RLS).
    -- public.admin_user é a fonte de verdade de is_admin() (Query 1060)
    -- — consultada aqui diretamente pela role privilegiada, nunca via
    -- is_admin() (que só responde sobre auth.uid() da própria sessão,
    -- por design do ADR-021, e não serve para filtrar candidatos).
    SELECT count(DISTINCT i.owner_user_id) INTO v_owner_count
    FROM public.inventory i
    WHERE i.owner_user_id NOT IN (SELECT au.id FROM public.admin_user au);
    IF v_owner_count < 2 THEN
        RAISE EXCEPTION 'fixtures insuficientes: >= 2 Owners NAO-ADMIN distintos com Inventory necessarios para Casos U/V/W/X/SEC-* (encontrados: %)', v_owner_count;
    END IF;

    SELECT count(*) INTO v_game_count FROM public.game;
    IF v_game_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhum Game encontrado';
    END IF;

    SELECT count(*) INTO v_language_count FROM public.language;
    IF v_language_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhuma Language encontrada';
    END IF;

    SELECT count(*) INTO v_multi_count
    FROM public.card c
    WHERE (SELECT count(*) FROM public.card_variant cv WHERE cv.card_id = c.id) >= 2;
    IF v_multi_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhuma Card com >= 2 Card Variants (necessaria para Casos K/L)';
    END IF;

    SELECT count(*) INTO v_complete_count
    FROM (
        SELECT c.card_set_id
        FROM public.card c
        LEFT JOIN public.card_variant cv ON cv.card_id = c.id
        GROUP BY c.card_set_id
        HAVING count(DISTINCT c.id) = count(DISTINCT CASE WHEN cv.id IS NOT NULL THEN c.id END)
    ) elegiveis;
    IF v_complete_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhum Card Set com cobertura de Card Variant 100%% encontrado (necessario para Caso O — escolha de fixture, nao requisito de STANDARD_SET)';
    END IF;
END $$;

-- ================================================================
-- PASSO 1 — resolver contexto em test_ctx (key/value)
-- ================================================================
CREATE TEMP TABLE test_ctx (key TEXT PRIMARY KEY, value TEXT);

-- owner_a / owner_b: explicitamente NÃO-ADMIN (mandato STAGING-FINAL-
-- AUDIT-01, item 4) — excluídos via public.admin_user, nunca via
-- is_admin() (que não aceita parâmetro de usuário, por design).
INSERT INTO test_ctx (key, value)
SELECT 'owner_a', owner_user_id::text FROM public.inventory
WHERE owner_user_id NOT IN (SELECT id FROM public.admin_user)
ORDER BY owner_user_id LIMIT 1;

INSERT INTO test_ctx (key, value)
SELECT 'owner_b', owner_user_id::text FROM public.inventory
WHERE owner_user_id NOT IN (SELECT id FROM public.admin_user)
  AND owner_user_id <> (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a')
ORDER BY owner_user_id LIMIT 1;

INSERT INTO test_ctx (key, value)
SELECT 'inventory_a', id::text FROM public.inventory
WHERE owner_user_id = (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a');

INSERT INTO test_ctx (key, value)
SELECT 'inventory_b', id::text FROM public.inventory
WHERE owner_user_id = (SELECT value::uuid FROM test_ctx WHERE key = 'owner_b');

INSERT INTO test_ctx (key, value)
SELECT 'language_id', id::text FROM public.language LIMIT 1;

-- Card com >= 2 Variants (fixture de K/L) e seu Card Set/Game
DO $$
DECLARE
    v_card_multi UUID;
    v_card_set   UUID;
    v_game       UUID;
BEGIN
    SELECT c.id, c.card_set_id INTO v_card_multi, v_card_set
    FROM public.card c
    WHERE (SELECT count(*) FROM public.card_variant cv WHERE cv.card_id = c.id) >= 2
    LIMIT 1;

    SELECT ex.game_id INTO v_game
    FROM public.card_set cs JOIN public.expansion ex ON ex.id = cs.expansion_id
    WHERE cs.id = v_card_set;

    INSERT INTO test_ctx (key, value) VALUES
        ('card_multi', v_card_multi::text),
        ('test_card_set', v_card_set::text),
        ('game_id_test', v_game::text);
END $$;

INSERT INTO test_ctx (key, value)
SELECT 'variant_multi_1', id::text FROM public.card_variant
WHERE card_id = (SELECT value::uuid FROM test_ctx WHERE key = 'card_multi')
ORDER BY variant_order LIMIT 1;

INSERT INTO test_ctx (key, value)
SELECT 'variant_multi_2', id::text FROM public.card_variant
WHERE card_id = (SELECT value::uuid FROM test_ctx WHERE key = 'card_multi')
ORDER BY variant_order OFFSET 1 LIMIT 1;

-- 2 outras Cards distintas do mesmo Card Set, com >= 1 Variant cada
-- (fixture de M e do restante da progressão)
CREATE TEMP TABLE test_other_cards (card_id UUID, variant_id UUID, rn INT);

INSERT INTO test_other_cards (card_id, variant_id, rn)
SELECT card_id, variant_id, row_number() OVER ()
FROM (
    SELECT DISTINCT ON (c.id) c.id AS card_id, cv.id AS variant_id
    FROM public.card c
    JOIN public.card_variant cv ON cv.card_id = c.id
    WHERE c.card_set_id = (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
      AND c.id <> (SELECT value::uuid FROM test_ctx WHERE key = 'card_multi')
    ORDER BY c.id, cv.variant_order
    LIMIT 2
) sub;

INSERT INTO test_ctx (key, value)
SELECT 'total_positions_test_set', count(*)::text
FROM public.card WHERE card_set_id = (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set');

-- Card Set pequeno, 100% coberto por Card Variant (fixture de Caso O)
DO $$
DECLARE
    v_set  UUID;
    v_game UUID;
BEGIN
    SELECT c.card_set_id INTO v_set
    FROM public.card c
    LEFT JOIN public.card_variant cv ON cv.card_id = c.id
    GROUP BY c.card_set_id
    HAVING count(DISTINCT c.id) = count(DISTINCT CASE WHEN cv.id IS NOT NULL THEN c.id END)
    ORDER BY count(DISTINCT c.id) ASC
    LIMIT 1;

    SELECT ex.game_id INTO v_game
    FROM public.card_set cs JOIN public.expansion ex ON ex.id = cs.expansion_id
    WHERE cs.id = v_set;

    INSERT INTO test_ctx (key, value) VALUES
        ('complete_card_set', v_set::text),
        ('game_id_complete', v_game::text);
END $$;

CREATE TEMP TABLE test_complete_variants (card_id UUID, variant_id UUID, rn INT);

INSERT INTO test_complete_variants (card_id, variant_id, rn)
SELECT card_id, variant_id, row_number() OVER ()
FROM (
    SELECT DISTINCT ON (c.id) c.id AS card_id, cv.id AS variant_id
    FROM public.card c
    JOIN public.card_variant cv ON cv.card_id = c.id
    WHERE c.card_set_id = (SELECT value::uuid FROM test_ctx WHERE key = 'complete_card_set')
    ORDER BY c.id, cv.variant_order
) sub;

-- Card Set fantasma, sem nenhuma Card (fixture de Caso Y — denominator
-- zero). Reaproveita a expansion/Game do test_card_set; release_order
-- deliberadamente muito alto para não colidir com nenhum valor real.
DO $$
DECLARE
    v_expansion UUID;
    v_max_order INT;
    v_empty_set UUID;
BEGIN
    SELECT cs.expansion_id INTO v_expansion
    FROM public.card_set cs WHERE cs.id = (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set');

    SELECT COALESCE(max(release_order), 0) + 100000 INTO v_max_order
    FROM public.card_set WHERE expansion_id = v_expansion;

    INSERT INTO public.card_set (
        expansion_id, code, name, set_type, release_order, base_set_size, total_set_size
    )
    VALUES (
        v_expansion, 'ZZVAL-EMPTY', 'VAL-TEST-02E Card Set Vazio', 'SPECIAL', v_max_order, 1, 1
    )
    RETURNING id INTO v_empty_set;

    INSERT INTO test_ctx (key, value) VALUES ('empty_card_set', v_empty_set::text);
END $$;

-- ================================================================
-- PASSO 2 — fixtures privilegiadas (Storage Containers)
-- ================================================================
WITH ins AS (
    INSERT INTO public.storage_container (inventory_id, name)
    VALUES ((SELECT value::uuid FROM test_ctx WHERE key = 'inventory_a'), 'VAL-TEST-02E-STORAGE-A')
    RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'storage_a', id::text FROM ins;

WITH ins AS (
    INSERT INTO public.storage_container (inventory_id, name)
    VALUES ((SELECT value::uuid FROM test_ctx WHERE key = 'inventory_b'), 'VAL-TEST-02E-STORAGE-B')
    RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'storage_b', id::text FROM ins;

-- ================================================================
-- BEHAVIOR TEST (Casos C/D) — INSERT direto em public.collection,
-- como role privilegiada (authenticated não tem INSERT nesta tabela
-- — o objetivo aqui é testar o CHECK, não a RLS/grant, que já é
-- provada separadamente no bloco de Security abaixo)
-- ================================================================

-- C (PASS) — OPEN_CURATION + NONE
DO $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO public.collection (
        owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy
    )
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        'VAL-TEST-02E-BEHAVIOR-C-PASS', 'OPEN_CURATION', 'NONE'
    )
    RETURNING id INTO v_id;
    PERFORM pg_temp.log_result('C - CHECK aceita OPEN_CURATION/NONE (PASS)', v_id IS NOT NULL, NULL);
END $$;

-- C (FAIL esperado) — OPEN_CURATION + STANDARD_SET
DO $$
BEGIN
    INSERT INTO public.collection (
        owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy
    )
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        'VAL-TEST-02E-BEHAVIOR-C-FAIL', 'OPEN_CURATION', 'STANDARD_SET'
    );
    PERFORM pg_temp.log_result('C - CHECK rejeita OPEN_CURATION/STANDARD_SET (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.log_result('C - CHECK rejeita OPEN_CURATION/STANDARD_SET (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- D (PASS) — REFERENCE_BASED + STANDARD_SET, com Reference válida
DO $$
DECLARE
    v_id UUID;
    v_ref_id UUID;
BEGIN
    INSERT INTO public.collection (
        owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy
    )
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        'VAL-TEST-02E-BEHAVIOR-D-PASS', 'REFERENCE_BASED', 'STANDARD_SET'
    )
    RETURNING id INTO v_id;

    INSERT INTO public.collection_reference (collection_id, reference_kind)
    VALUES (v_id, 'CARD_SET') RETURNING id INTO v_ref_id;

    INSERT INTO public.collection_card_set_reference (collection_reference_id, card_set_id)
    VALUES (v_ref_id, (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set'));

    PERFORM pg_temp.log_result('D - CHECK aceita REFERENCE_BASED/STANDARD_SET com Reference valida (PASS)', v_id IS NOT NULL, NULL);
END $$;

-- D (FAIL esperado) — REFERENCE_BASED + NONE
DO $$
BEGIN
    INSERT INTO public.collection (
        owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy
    )
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        'VAL-TEST-02E-BEHAVIOR-D-FAIL', 'REFERENCE_BASED', 'NONE'
    );
    PERFORM pg_temp.log_result('D - CHECK rejeita REFERENCE_BASED/NONE (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.log_result('D - CHECK rejeita REFERENCE_BASED/NONE (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- ================================================================
-- PASSO 2b — Physical Cards de fixture (privilegiado), NÃO alocadas
-- ainda (alocação real acontece via RPC, como authenticated, no
-- Passo 5)
-- ================================================================

-- pc_j / pc_k / pc_l / pc_m — progressão J-N
WITH ins AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'variant_multi_1'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'language_id'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'inventory_a')
    ) RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pc_j', id::text FROM ins;

WITH ins AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'variant_multi_2'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'language_id'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'inventory_a')
    ) RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pc_k', id::text FROM ins;

WITH ins AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'variant_multi_1'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'language_id'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'inventory_a')
    ) RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pc_l', id::text FROM ins;

WITH ins AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (
        (SELECT variant_id FROM test_other_cards WHERE rn = 1),
        (SELECT value::uuid FROM test_ctx WHERE key = 'language_id'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'inventory_a')
    ) RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pc_m', id::text FROM ins;

-- pc_archive — fixture do Caso T
WITH ins AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (
        (SELECT variant_id FROM test_other_cards WHERE rn = 2),
        (SELECT value::uuid FROM test_ctx WHERE key = 'language_id'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'inventory_a')
    ) RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pc_archive', id::text FROM ins;

-- Physical Cards para completar 100% do complete_card_set (Caso O)
CREATE TEMP TABLE test_complete_pcs (id UUID);

WITH ins AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    SELECT tcv.variant_id,
           (SELECT value::uuid FROM test_ctx WHERE key = 'language_id'),
           (SELECT value::uuid FROM test_ctx WHERE key = 'inventory_a')
    FROM test_complete_variants tcv
    RETURNING id
)
INSERT INTO test_complete_pcs (id) SELECT id FROM ins;

-- ================================================================
-- PASSO 3 — GRANTs em pg_temp para o papel authenticated (ANTES da
-- troca de role — mesma correção já aprendida em 02C/02D/5811)
-- ================================================================
-- test_ctx recebe INSERT além de SELECT: os DO blocks do Passo 5
-- (E/F/col_complete/col_archive/col_empty) gravam de volta em test_ctx
-- os ids das Collections criadas via RPC, já como authenticated —
-- sem este GRANT, cada um desses INSERTs falharia com "permission
-- denied for table test_ctx"
GRANT SELECT, INSERT ON test_ctx TO authenticated;
GRANT SELECT ON test_other_cards TO authenticated;
GRANT SELECT ON test_complete_variants TO authenticated;
GRANT SELECT ON test_complete_pcs TO authenticated;
GRANT INSERT, SELECT ON test_results TO authenticated;
-- test_results.id é SERIAL — INSERT via role não-owner exige USAGE na
-- sequence subjacente (pg_temp.log_result() é SECURITY INVOKER, roda
-- com o privilégio de quem chama). Achado real (IMPLEMENTATION-01,
-- primeira execução real de 5810 contra o banco): sem este GRANT, todo
-- log_result() chamado como authenticated/anon falha com "permission
-- denied for sequence test_results_id_seq" — nunca detectado nas
-- rodadas de staging porque nenhuma delas executou de fato.
GRANT USAGE ON SEQUENCE test_results_id_seq TO authenticated;
GRANT EXECUTE ON FUNCTION pg_temp.log_result(TEXT, BOOLEAN, TEXT) TO authenticated;

-- Também concedido a anon: SOMENTE a infraestrutura de log/contexto
-- deste script (test_ctx/test_results/log_result), para que o Caso
-- SEC-H (mandato REVISION-02) consiga registrar o resultado do teste
-- enquanto impersona anon de verdade. Não é acesso a nenhuma tabela
-- de domínio real, nem amplia GRANT/RLS de card/card_variant/
-- collection — puramente andaime de teste, existe só dentro desta
-- transação revertida.
GRANT SELECT ON test_ctx TO anon;
GRANT INSERT, SELECT ON test_results TO anon;
-- mesma correção acima: SEC-H também chama log_result() impersonando
-- anon (tanto no ramo "erro esperado" quanto no ramo "BUG" da
-- EXCEPTION), e precisa da mesma USAGE na sequence.
GRANT USAGE ON SEQUENCE test_results_id_seq TO anon;
GRANT EXECUTE ON FUNCTION pg_temp.log_result(TEXT, BOOLEAN, TEXT) TO anon;

-- ================================================================
-- PASSO 4 — trocar para o contexto do Owner A autenticado
-- ================================================================
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', (SELECT value FROM test_ctx WHERE key = 'owner_a'), true);

-- PRECOND-ADMIN-A — prova real (mandato STAGING-FINAL-AUDIT-01, item
-- 4): Owner A, já impersonado, chama is_admin() de verdade e deve
-- receber FALSE. Roda ANTES de qualquer Caso funcional/de segurança —
-- se isto falhar, os fixtures NÃO são válidos para SEC-M/cross-owner
-- e o restante do script não deveria ser interpretado como prova de
-- comportamento não-admin.
DO $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT public.is_admin() INTO v_is_admin;
    PERFORM pg_temp.log_result('PRECOND-ADMIN-A - Owner A authenticated: is_admin() = false', v_is_admin IS FALSE, format('is_admin=%s', v_is_admin));
    IF v_is_admin IS NOT FALSE THEN
        RAISE EXCEPTION 'fixture invalido: Owner A resolvido em test_ctx e ADMIN (is_admin()=%) — refazer selecao de owner_a excluindo public.admin_user', v_is_admin;
    END IF;
END $$;

-- ================================================================
-- PASSO 5 — Casos funcionais reais, como Owner A
-- ================================================================

-- E — create_collection() grava NONE
DO $$
DECLARE
    v_id UUID;
    v_policy TEXT;
BEGIN
    SELECT id INTO v_id FROM public.create_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        'VAL-TEST-02E-COL-E', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a')
    );
    SELECT completion_policy INTO v_policy FROM public.collection WHERE id = v_id;
    PERFORM pg_temp.log_result('E - create_collection() grava completion_policy=NONE', v_policy = 'NONE', v_policy);
    INSERT INTO test_ctx (key, value) VALUES ('col_e', v_id::text);
END $$;

-- F — create_reference_based_card_set_collection() grava STANDARD_SET
DO $$
DECLARE
    v_id UUID;
    v_policy TEXT;
BEGIN
    SELECT id INTO v_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        'VAL-TEST-02E-COL-F', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
    );
    SELECT completion_policy INTO v_policy FROM public.collection WHERE id = v_id;
    PERFORM pg_temp.log_result('F - create_reference_based_card_set_collection() grava completion_policy=STANDARD_SET', v_policy = 'STANDARD_SET', v_policy);
    INSERT INTO test_ctx (key, value) VALUES ('col_f', v_id::text);
END $$;

-- col_complete e col_archive (mesma RPC, apontando para outros Sets)
DO $$
DECLARE
    v_id UUID;
BEGIN
    SELECT id INTO v_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_complete'),
        'VAL-TEST-02E-COL-COMPLETE', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'complete_card_set')
    );
    INSERT INTO test_ctx (key, value) VALUES ('col_complete', v_id::text);
END $$;

DO $$
DECLARE
    v_id UUID;
BEGIN
    SELECT id INTO v_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        'VAL-TEST-02E-COL-ARCHIVE', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
    );
    INSERT INTO test_ctx (key, value) VALUES ('col_archive', v_id::text);
END $$;

-- col_empty — REFERENCE_BASED apontando para o Card Set fantasma
-- (Caso Y, denominator zero)
DO $$
DECLARE
    v_id UUID;
BEGIN
    SELECT id INTO v_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        'VAL-TEST-02E-COL-EMPTY', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'empty_card_set')
    );
    INSERT INTO test_ctx (key, value) VALUES ('col_empty', v_id::text);
END $$;

-- G / SEC-G — OPEN_CURATION summary -> 0 rows (rótulo do mandato
-- REVISION-02 embutido diretamente aqui, sem alias artificial)
DO $$
DECLARE
    v_rows INT;
BEGIN
    SELECT count(*) INTO v_rows FROM public.collection_completion_summary(
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_e'));
    PERFORM pg_temp.log_result('G / SEC-G - OPEN_CURATION summary -> 0 rows', v_rows = 0, format('rows=%s', v_rows));
END $$;

-- H / SEC-G — OPEN_CURATION positions -> 0 rows
DO $$
DECLARE
    v_rows INT;
BEGIN
    SELECT count(*) INTO v_rows FROM public.collection_completion_positions(
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_e'));
    PERFORM pg_temp.log_result('H / SEC-G - OPEN_CURATION positions -> 0 rows', v_rows = 0, format('rows=%s', v_rows));
END $$;

-- I — Collection vazia STANDARD_SET -> total > 0, satisfied = 0,
-- missing = total, is_complete = false
DO $$
DECLARE
    v_total BIGINT; v_satisfied BIGINT; v_missing BIGINT; v_complete BOOLEAN;
BEGIN
    SELECT total_positions, satisfied_positions, missing_positions, is_complete
    INTO v_total, v_satisfied, v_missing, v_complete
    FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));

    PERFORM pg_temp.log_result('I - Collection vazia: total > 0', v_total > 0, format('total=%s', v_total));
    PERFORM pg_temp.log_result('I - Collection vazia: satisfied = 0', v_satisfied = 0, format('satisfied=%s', v_satisfied));
    PERFORM pg_temp.log_result('I - Collection vazia: missing = total', v_missing = v_total, format('missing=%s total=%s', v_missing, v_total));
    PERFORM pg_temp.log_result('I - Collection vazia: is_complete = false', v_complete = FALSE, format('is_complete=%s', v_complete));
END $$;

-- J — 1 Card / 1 Variant / 1 Physical Card -> +1 requirement
DO $$
DECLARE
    v_satisfied BIGINT;
BEGIN
    PERFORM public.allocate_physical_cards_to_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_f'),
        ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'pc_j')]
    );
    SELECT satisfied_positions INTO v_satisfied
    FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    PERFORM pg_temp.log_result('J - allocate 1a Variant -> satisfied = 1', v_satisfied = 1, format('satisfied=%s', v_satisfied));
END $$;

-- K — segunda Variant da MESMA Card não aumenta
DO $$
DECLARE
    v_satisfied BIGINT;
BEGIN
    PERFORM public.allocate_physical_cards_to_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_f'),
        ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'pc_k')]
    );
    SELECT satisfied_positions INTO v_satisfied
    FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    PERFORM pg_temp.log_result('K - allocate 2a Variant da mesma Card -> satisfied continua 1', v_satisfied = 1, format('satisfied=%s', v_satisfied));
END $$;

-- L — duplicata da MESMA Variant não aumenta
DO $$
DECLARE
    v_satisfied BIGINT;
BEGIN
    PERFORM public.allocate_physical_cards_to_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_f'),
        ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'pc_l')]
    );
    SELECT satisfied_positions INTO v_satisfied
    FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    PERFORM pg_temp.log_result('L - allocate duplicata da mesma Variant -> satisfied continua 1', v_satisfied = 1, format('satisfied=%s', v_satisfied));
END $$;

-- M — Card diferente aumenta
DO $$
DECLARE
    v_satisfied BIGINT;
BEGIN
    PERFORM public.allocate_physical_cards_to_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_f'),
        ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'pc_m')]
    );
    SELECT satisfied_positions INTO v_satisfied
    FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    PERFORM pg_temp.log_result('M - allocate Card diferente -> satisfied = 2', v_satisfied = 2, format('satisfied=%s', v_satisfied));
END $$;

-- N — deallocate reduz imediatamente
DO $$
DECLARE
    v_satisfied BIGINT;
BEGIN
    PERFORM public.deallocate_physical_cards_from_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_f'),
        ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'pc_m')]
    );
    SELECT satisfied_positions INTO v_satisfied
    FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    PERFORM pg_temp.log_result('N - deallocate reduz imediatamente -> satisfied volta a 1', v_satisfied = 1, format('satisfied=%s', v_satisfied));
END $$;

-- P — percentual correto (com o estado atual de col_f: 1 satisfeita)
DO $$
DECLARE
    v_total BIGINT; v_satisfied BIGINT; v_pct NUMERIC;
BEGIN
    SELECT total_positions, satisfied_positions, progress_percentage
    INTO v_total, v_satisfied, v_pct
    FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    PERFORM pg_temp.log_result('P - progress_percentage bate com round((satisfied/total)*100,2)',
        v_pct = round((v_satisfied::numeric / v_total::numeric) * 100, 2),
        format('total=%s satisfied=%s pct=%s', v_total, v_satisfied, v_pct));
END $$;

-- Q — only_missing = false -> todas as Cards do Card Set
DO $$
DECLARE
    v_rows BIGINT; v_total BIGINT;
BEGIN
    SELECT count(*) INTO v_rows FROM public.collection_completion_positions(
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_f'), FALSE);
    SELECT total_positions INTO v_total FROM public.collection_completion_summary(
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    PERFORM pg_temp.log_result('Q - only_missing=false retorna todas as posicoes', v_rows = v_total, format('rows=%s total=%s', v_rows, v_total));
END $$;

-- R — only_missing = true -> só faltantes
DO $$
DECLARE
    v_rows BIGINT; v_total BIGINT; v_satisfied BIGINT; v_any_satisfied BOOLEAN;
BEGIN
    SELECT count(*), bool_or(is_satisfied) INTO v_rows, v_any_satisfied
    FROM public.collection_completion_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'), TRUE);
    SELECT total_positions, satisfied_positions INTO v_total, v_satisfied
    FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    PERFORM pg_temp.log_result('R - only_missing=true retorna exatamente total-satisfied',
        v_rows = v_total - v_satisfied, format('rows=%s total=%s satisfied=%s', v_rows, v_total, v_satisfied));
    PERFORM pg_temp.log_result('R - only_missing=true nunca retorna linha satisfeita',
        v_any_satisfied IS NOT TRUE, format('any_satisfied=%s', v_any_satisfied));
END $$;

-- S — ordenação determinística (collector_order, collector_number, id)
DO $$
DECLARE
    v_bate BOOLEAN;
BEGIN
    WITH funcao AS (
        SELECT card_id, row_number() OVER () AS rn
        FROM public.collection_completion_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'), FALSE)
    ),
    esperado AS (
        SELECT c.id AS card_id, row_number() OVER (ORDER BY c.collector_order, c.collector_number, c.id) AS rn
        FROM public.card c
        WHERE c.card_set_id = (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
    )
    SELECT NOT EXISTS (
        SELECT 1 FROM funcao f JOIN esperado e ON e.rn = f.rn WHERE f.card_id <> e.card_id
    ) INTO v_bate;
    PERFORM pg_temp.log_result('S - ordenacao bate com collector_order/collector_number/id', v_bate, NULL);
END $$;

-- T — ARCHIVED continua consultável
DO $$
DECLARE
    v_before_total BIGINT; v_before_satisfied BIGINT;
    v_after_total  BIGINT; v_after_satisfied  BIGINT;
    v_after_rows   BIGINT;
BEGIN
    PERFORM public.allocate_physical_cards_to_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_archive'),
        ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'pc_archive')]
    );
    SELECT total_positions, satisfied_positions INTO v_before_total, v_before_satisfied
    FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_archive'));

    PERFORM public.archive_collection((SELECT value::uuid FROM test_ctx WHERE key = 'col_archive'));

    SELECT total_positions, satisfied_positions INTO v_after_total, v_after_satisfied
    FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_archive'));
    SELECT count(*) INTO v_after_rows
    FROM public.collection_completion_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_archive'));

    PERFORM pg_temp.log_result('T - ARCHIVED: summary preserva total/satisfied',
        v_before_total = v_after_total AND v_before_satisfied = v_after_satisfied,
        format('antes=%s/%s depois=%s/%s', v_before_satisfied, v_before_total, v_after_satisfied, v_after_total));
    PERFORM pg_temp.log_result('T - ARCHIVED: positions continua respondendo', v_after_rows = v_after_total, format('rows=%s total=%s', v_after_rows, v_after_total));
END $$;

-- O — summary completo -> is_complete true (col_complete, Card Set
-- 100% coberto, TODOS os Physical Cards alocados de uma vez)
DO $$
DECLARE
    v_ids UUID[];
    v_total BIGINT; v_satisfied BIGINT; v_missing BIGINT; v_pct NUMERIC; v_complete BOOLEAN;
BEGIN
    SELECT array_agg(id) INTO v_ids FROM test_complete_pcs;

    PERFORM public.allocate_physical_cards_to_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_complete'), v_ids
    );

    SELECT total_positions, satisfied_positions, missing_positions, progress_percentage, is_complete
    INTO v_total, v_satisfied, v_missing, v_pct, v_complete
    FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_complete'));

    PERFORM pg_temp.log_result('O - satisfied = total', v_satisfied = v_total, format('satisfied=%s total=%s', v_satisfied, v_total));
    PERFORM pg_temp.log_result('O - missing = 0', v_missing = 0, format('missing=%s', v_missing));
    PERFORM pg_temp.log_result('O - progress_percentage = 100.00', v_pct = 100.00, format('pct=%s', v_pct));
    PERFORM pg_temp.log_result('O - is_complete = true', v_complete = TRUE, format('is_complete=%s', v_complete));
END $$;

-- Y — denominator zero protegido (col_empty, Card Set fantasma)
DO $$
DECLARE
    v_total BIGINT; v_satisfied BIGINT; v_pct NUMERIC; v_complete BOOLEAN; v_rows INT;
BEGIN
    SELECT total_positions, satisfied_positions, progress_percentage, is_complete
    INTO v_total, v_satisfied, v_pct, v_complete
    FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_empty'));
    PERFORM pg_temp.log_result('Y - total_positions = 0', v_total = 0, format('total=%s', v_total));
    PERFORM pg_temp.log_result('Y - progress_percentage = 0.00 sem divisao por zero', v_pct = 0.00, format('pct=%s', v_pct));
    PERFORM pg_temp.log_result('Y - is_complete = false mesmo com total=0', v_complete = FALSE, format('is_complete=%s', v_complete));

    SELECT count(*) INTO v_rows FROM public.collection_completion_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_empty'));
    PERFORM pg_temp.log_result('Y - positions retorna 0 rows para Card Set vazio', v_rows = 0, format('rows=%s', v_rows));
END $$;

-- ================================================================
-- PASSO 5b — trocar para Owner B (mesmo role authenticated, novo
-- jwt.claim.sub) para os Casos U/V/W/X (não-enumeração) e para criar
-- col_b — Collection REAL do Owner B (STANDARD_SET), necessária para
-- o teste de bypass de ownership do Passo 5c (mandato REVISION-02,
-- item 10: "Adicionar caso específico tentando consultar Collection
-- real do Owner B como Owner A")
-- ================================================================
SELECT set_config('request.jwt.claim.sub', (SELECT value FROM test_ctx WHERE key = 'owner_b'), true);

-- PRECOND-ADMIN-B — mesma prova real de PRECOND-ADMIN-A, agora para
-- Owner B (mandato STAGING-FINAL-AUDIT-01, item 4)
DO $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT public.is_admin() INTO v_is_admin;
    PERFORM pg_temp.log_result('PRECOND-ADMIN-B - Owner B authenticated: is_admin() = false', v_is_admin IS FALSE, format('is_admin=%s', v_is_admin));
    IF v_is_admin IS NOT FALSE THEN
        RAISE EXCEPTION 'fixture invalido: Owner B resolvido em test_ctx e ADMIN (is_admin()=%) — refazer selecao de owner_b excluindo public.admin_user', v_is_admin;
    END IF;
END $$;

-- col_b — Collection real do Owner B, criada pela própria RPC como
-- Owner B (nunca por INSERT privilegiado) — usada só para provar que
-- Owner A NÃO consegue lê-la via summary/positions
DO $$
DECLARE
    v_id UUID;
BEGIN
    SELECT id INTO v_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        'VAL-TEST-02E-COL-B-OWNER-B', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_b'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
    );
    INSERT INTO test_ctx (key, value) VALUES ('col_b', v_id::text);
    PERFORM pg_temp.log_result('col_b criada com sucesso como Owner B (fixture do teste de bypass)', v_id IS NOT NULL, NULL);
END $$;

-- U / SEC-C — foreign summary -> 0 rows (rótulo do mandato REVISION-
-- 02 embutido diretamente aqui — mandato STAGING-FINAL-FIX-01, item 2:
-- nunca um pg_temp.log_result(..., TRUE, 'ver outro caso'), a asserção
-- de segurança É esta chamada real)
DO $$
DECLARE
    v_rows INT;
BEGIN
    SELECT count(*) INTO v_rows FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    PERFORM pg_temp.log_result('U / SEC-C - authenticated outro usuario: summary sobre Collection de outro Owner -> 0 rows', v_rows = 0, format('rows=%s', v_rows));
END $$;

-- V / SEC-E — nonexistent summary -> 0 rows
DO $$
DECLARE
    v_rows INT;
BEGIN
    SELECT count(*) INTO v_rows FROM public.collection_completion_summary(gen_random_uuid());
    PERFORM pg_temp.log_result('V / SEC-E - nonexistent: summary sobre Collection inexistente -> 0 rows', v_rows = 0, format('rows=%s', v_rows));
END $$;

-- W / SEC-D / SEC-F — foreign positions -> 0 rows (e nonexistent,
-- mesma forma)
DO $$
DECLARE
    v_rows_foreign INT;
    v_rows_nonexistent INT;
BEGIN
    SELECT count(*) INTO v_rows_foreign FROM public.collection_completion_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    SELECT count(*) INTO v_rows_nonexistent FROM public.collection_completion_positions(gen_random_uuid());
    PERFORM pg_temp.log_result('W / SEC-D - authenticated outro usuario: positions sobre Collection de outro Owner -> 0 rows', v_rows_foreign = 0, format('rows=%s', v_rows_foreign));
    PERFORM pg_temp.log_result('W / SEC-F - nonexistent: positions sobre Collection inexistente -> 0 rows, mesma forma que foreign', v_rows_nonexistent = v_rows_foreign, format('foreign=%s nonexistent=%s', v_rows_foreign, v_rows_nonexistent));
END $$;

-- ================================================================
-- PASSO 5c — bloco de SEGURANÇA (mandato COLLECTIONS-PHYSICAL-
-- INCREMENT-02E-STAGING-REVISION-02, itens 9/10, endurecido em
-- STAGING-FINAL-FIX-01 item 2) — de volta ao contexto de Owner A.
-- Os rótulos SEC-C/SEC-D/SEC-E/SEC-F/SEC-G do mandato já estão
-- embutidos nos Casos U/V/W/G/H acima (mesma chamada real, mesmo
-- pg_temp.log_result) — removidos os blocos que só reafirmavam
-- TRUE constante com "ver Caso X acima": isso criava uma linha em
-- test_results que passa mesmo se o Caso referenciado nunca tivesse
-- rodado ou tivesse sido removido, um falso-positivo estrutural para
-- um gate de segurança. Só SEC-A/SEC-B (sem Caso anterior 1:1) e o
-- restante do bloco original permanecem aqui.
-- ================================================================
SELECT set_config('request.jwt.claim.sub', (SELECT value FROM test_ctx WHERE key = 'owner_a'), true);

-- SEC-A — authenticated Owner: summary funciona
DO $$
DECLARE
    v_rows INT;
    v_policy TEXT;
BEGIN
    SELECT count(*) INTO v_rows FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    SELECT completion_policy INTO v_policy FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    PERFORM pg_temp.log_result('SEC-A - authenticated Owner: summary funciona (1 row, completion_policy=STANDARD_SET)',
        v_rows = 1 AND v_policy = 'STANDARD_SET', format('rows=%s policy=%s', v_rows, v_policy));
END $$;

-- SEC-B — authenticated Owner: positions funcionam
DO $$
DECLARE
    v_rows INT;
BEGIN
    SELECT count(*) INTO v_rows FROM public.collection_completion_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    PERFORM pg_temp.log_result('SEC-B - authenticated Owner: positions funcionam (rows > 0)', v_rows > 0, format('rows=%s', v_rows));
END $$;

-- SEC-BYPASS (mandato, item 10) — Owner A tentando consultar a
-- Collection REAL de Owner B (col_b), não uma inexistente. Esperado:
-- 0 rows, mesma forma externa de uma Collection inexistente.
DO $$
DECLARE
    v_rows_summary_colb    INT;
    v_rows_positions_colb  INT;
    v_rows_summary_random  INT;
    v_rows_positions_random INT;
    v_random_id UUID := gen_random_uuid();
BEGIN
    SELECT count(*) INTO v_rows_summary_colb
        FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_b'));
    SELECT count(*) INTO v_rows_positions_colb
        FROM public.collection_completion_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_b'));
    SELECT count(*) INTO v_rows_summary_random
        FROM public.collection_completion_summary(v_random_id);
    SELECT count(*) INTO v_rows_positions_random
        FROM public.collection_completion_positions(v_random_id);

    PERFORM pg_temp.log_result('SEC-BYPASS - Owner A sobre Collection REAL de Owner B (col_b), summary -> 0 rows',
        v_rows_summary_colb = 0, format('rows=%s', v_rows_summary_colb));
    PERFORM pg_temp.log_result('SEC-BYPASS - Owner A sobre Collection REAL de Owner B (col_b), positions -> 0 rows',
        v_rows_positions_colb = 0, format('rows=%s', v_rows_positions_colb));
    PERFORM pg_temp.log_result('SEC-BYPASS - col_b (existe, de outro Owner) e UUID aleatorio (nao existe) tem a MESMA forma externa (summary)',
        v_rows_summary_colb = v_rows_summary_random, format('colb=%s random=%s', v_rows_summary_colb, v_rows_summary_random));
    PERFORM pg_temp.log_result('SEC-BYPASS - col_b (existe, de outro Owner) e UUID aleatorio (nao existe) tem a MESMA forma externa (positions)',
        v_rows_positions_colb = v_rows_positions_random, format('colb=%s random=%s', v_rows_positions_colb, v_rows_positions_random));
END $$;

-- SEC-M — authenticated (Owner A, ainda no mesmo contexto) continua
-- SEM leitura direta funcional de card/card_variant via RLS
-- admin-only — a projeção SECURITY DEFINER não reabriu o Catálogo
-- Editorial a SELECT direto (mandato, item 13 "NÃO FAZER")
DO $$
DECLARE
    v_card_direct         BIGINT;
    v_card_variant_direct BIGINT;
BEGIN
    SELECT count(*) INTO v_card_direct FROM public.card
        WHERE card_set_id = (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set');
    SELECT count(*) INTO v_card_variant_direct FROM public.card_variant
        WHERE card_id = (SELECT value::uuid FROM test_ctx WHERE key = 'card_multi');

    PERFORM pg_temp.log_result('SEC-M - authenticated: SELECT direto em public.card continua bloqueado por RLS (0 rows)',
        v_card_direct = 0, format('rows=%s (existem %s Cards reais nesse Card Set)', v_card_direct,
            (SELECT value FROM test_ctx WHERE key = 'total_positions_test_set')));
    PERFORM pg_temp.log_result('SEC-M - authenticated: SELECT direto em public.card_variant continua bloqueado por RLS (0 rows)',
        v_card_variant_direct = 0, format('rows=%s (existem >= 2 Variants reais nessa Card)', v_card_variant_direct));
END $$;

-- SEC-H — anon: EXECUTE negado (behavioral real, não só privilégio
-- estático — tenta chamar de fato como anon e espera erro)
DO $$
BEGIN
    PERFORM set_config('role', 'anon', true);
    PERFORM set_config('request.jwt.claim.sub', '', true);

    PERFORM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    PERFORM pg_temp.log_result('SEC-H - anon: EXECUTE negado em collection_completion_summary (esperado erro)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.log_result('SEC-H - anon: EXECUTE negado em collection_completion_summary (esperado erro)', TRUE, SQLERRM);
END $$;

-- Nota: a exceção capturada no bloco anterior aciona um ROLLBACK TO
-- SAVEPOINT implícito do DO — que desfaz também o set_config('role',
-- 'anon', true) executado DENTRO daquele bloco (SET LOCAL/set_config
-- com is_local=true é transacional). Por isso o papel 'anon' precisa
-- ser reafirmado aqui, no início deste segundo bloco — senão este
-- teste rodaria (incorretamente) como authenticated/Owner A, que tem
-- EXECUTE legítimo, e nunca lançaria o erro esperado.
DO $$
BEGIN
    PERFORM set_config('role', 'anon', true);
    PERFORM set_config('request.jwt.claim.sub', '', true);

    PERFORM public.collection_completion_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    PERFORM pg_temp.log_result('SEC-H - anon: EXECUTE negado em collection_completion_positions (esperado erro)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.log_result('SEC-H - anon: EXECUTE negado em collection_completion_positions (esperado erro)', TRUE, SQLERRM);
END $$;

-- volta para authenticated/Owner A — script segue precisando gravar
-- em test_results/test_ctx (GRANT concedido só a authenticated)
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', (SELECT value FROM test_ctx WHERE key = 'owner_a'), true);

-- X — security: reafirmação positiva (Owner A enxerga, Owner B não)
DO $$
DECLARE
    v_rows_owner INT;
BEGIN
    SELECT count(*) INTO v_rows_owner FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_f'));
    PERFORM pg_temp.log_result('X - Owner A sobre a propria Collection -> 1 row (positivo, contraste com U)', v_rows_owner = 1, format('rows=%s', v_rows_owner));
END $$;

-- SEC-I/SEC-J/SEC-K/SEC-L — mandato STAGING-FINAL-FIX-01, item 1:
-- eram SELECTs soltos (resultado intermediário, nunca alimentavam
-- test_results). Convertidos em asserções reais via log_result, uma
-- por função por checagem — loop sobre as 2 funções, 5 checagens
-- cada (proacl PUBLIC/anon/authenticated + prosecdef + proconfig),
-- 10 linhas em test_results.
DO $$
DECLARE
    r RECORD;
    v_public_sem_execute BOOLEAN;
    v_anon_pode          BOOLEAN;
    v_authenticated_pode BOOLEAN;
BEGIN
    FOR r IN
        SELECT p.proname, p.proacl, p.prosecdef, p.provolatile, p.proconfig
        FROM pg_proc p
        WHERE p.proname IN ('collection_completion_summary', 'collection_completion_positions')
    LOOP
        v_public_sem_execute := NOT EXISTS (
            SELECT 1 FROM aclexplode(r.proacl) a
            WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'   -- grantee = 0 => PUBLIC
        );
        v_anon_pode := has_function_privilege('anon',
            format('public.%I(%s)', r.proname, CASE WHEN r.proname = 'collection_completion_positions' THEN 'uuid, boolean' ELSE 'uuid' END),
            'EXECUTE');
        v_authenticated_pode := has_function_privilege('authenticated',
            format('public.%I(%s)', r.proname, CASE WHEN r.proname = 'collection_completion_positions' THEN 'uuid, boolean' ELSE 'uuid' END),
            'EXECUTE');

        PERFORM pg_temp.log_result(format('SEC-I - %s: PUBLIC sem EXECUTE (proacl real)', r.proname),
            v_public_sem_execute, format('public_sem_execute=%s', v_public_sem_execute));
        PERFORM pg_temp.log_result(format('SEC-I - %s: anon sem EXECUTE (has_function_privilege)', r.proname),
            v_anon_pode IS NOT TRUE, format('anon_pode=%s', v_anon_pode));
        PERFORM pg_temp.log_result(format('SEC-J - %s: authenticated com EXECUTE', r.proname),
            v_authenticated_pode IS TRUE, format('authenticated_pode=%s', v_authenticated_pode));
        PERFORM pg_temp.log_result(format('SEC-K - %s: SECURITY DEFINER (prosecdef=true)', r.proname),
            r.prosecdef IS TRUE, format('prosecdef=%s', r.prosecdef));
        PERFORM pg_temp.log_result(format('SEC-K - %s: STABLE (provolatile=s)', r.proname),
            r.provolatile = 's', format('provolatile=%s', r.provolatile));
        PERFORM pg_temp.log_result(format('SEC-L - %s: proconfig contem search_path=', r.proname),
            EXISTS (SELECT 1 FROM unnest(r.proconfig) cfg WHERE cfg LIKE 'search_path=%'),
            format('proconfig=%s', r.proconfig));
    END LOOP;
END $$;

-- Overload inesperado — mandato item 1, último bullet: uma asserção
-- por função das 4 relevantes (create_collection,
-- create_reference_based_card_set_collection,
-- collection_completion_summary, collection_completion_positions)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT fname FROM unnest(ARRAY[
            'create_collection', 'create_reference_based_card_set_collection',
            'collection_completion_summary', 'collection_completion_positions'
        ]) AS fname
    LOOP
        PERFORM pg_temp.log_result(
            format('OVERLOAD - %s: exatamente 1 assinatura no catalogo', r.fname),
            (SELECT count(*) FROM pg_proc WHERE proname = r.fname) = 1,
            format('overloads=%s', (SELECT count(*) FROM pg_proc WHERE proname = r.fname))
        );
    END LOOP;
END $$;

-- Z — zero residue (checagem intra-transação; a prova definitiva é o
-- ROLLBACK do Passo 7 + Passo 8 pós-transação)
DO $$
DECLARE
    v_test_collections INT;
BEGIN
    SELECT count(*) INTO v_test_collections FROM public.collection WHERE name LIKE 'VAL-TEST-02E-%';
    PERFORM pg_temp.log_result('Z - fixtures de teste existem dentro da transacao (serao desfeitas no ROLLBACK)', v_test_collections > 0, format('collections=%s', v_test_collections));
END $$;

-- ================================================================
-- PASSO 6 — leitura final consolidada (ainda dentro da transação)
-- ================================================================
SELECT case_label, passed, detail FROM test_results ORDER BY id;

SELECT count(*) AS total_casos, count(*) FILTER (WHERE passed) AS passaram, count(*) FILTER (WHERE NOT passed) AS falharam
FROM test_results;

-- ================================================================
-- GOVERNANÇA DO RESULTADO (mandato STAGING-EXECUTION-SAFETY-FIX-01,
-- itens 1/2 — substitui integralmente o antigo "GATE FINAL" de
-- STAGING-FINAL-FIX-01, que fazia RAISE EXCEPTION aqui). Removido por
-- decisão explícita: o comportamento do cliente/ferramenta que
-- executa este script diante de um erro no MEIO do batch — se ele
-- continua enviando os statements restantes (incluindo o ROLLBACK
-- logo abaixo) ou aborta o envio do que falta — nunca foi confirmado
-- (ver resposta A/B da rodada STAGING-SOURCE-HANDOFF-01). Um RAISE
-- EXCEPTION aqui dependia dessa garantia não confirmada para que o
-- ROLLBACK do Passo 7 fosse de fato alcançado; essa dependência foi
-- removida.
--
-- Esta bateria SQL é reversível e SEMPRE executa ROLLBACK — em toda
-- execução normal (nenhum RAISE fora das pré-condições de fixture,
-- ver abaixo), o fluxo é: SELECT detalhado de test_results -> SELECT
-- de total/passaram/falharam -> ROLLBACK -> provas pós-ROLLBACK,
-- independentemente de existir qualquer test_results.passed = false.
--
-- A decisão de PROSSEGUIR ou não com a implementação passa a ser um
-- gate do PROCESSO, fiscalizado por quem está executando esta rodada
-- (o "executor"), lendo o SELECT de total/passaram/falharam acima —
-- nunca um RAISE EXCEPTION dentro da transação:
--   falharam = 0  -> pode prosseguir (aplicar 5067-5071, depois medir
--                    5811, depois promover schema/documentação).
--   falharam > 0  -> IMPLEMENTATION STOP: não executar 5811, não
--                    promover schema, reportar os rótulos falhos
--                    (coluna case_label das linhas com passed=false
--                    no SELECT detalhado acima) antes de qualquer
--                    novo passo.
--
-- As pré-condições fail-loud (RAISE EXCEPTION no bloco "PRÉ-CONDIÇÕES"
-- e nos blocos PRECOND-ADMIN-A/PRECOND-ADMIN-B, mais acima) NÃO foram
-- alteradas por este item — permanecem como estão, porque representam
-- IMPOSSIBILIDADE de executar a bateria (fixtures insuficientes ou
-- inválidos), não um resultado funcional FAIL de um Caso já executado.
-- ================================================================

-- ================================================================
-- PASSO 7 — desfazer tudo (alcançado sempre, em toda execução normal
-- da bateria — não depende de nenhuma condição sobre test_results)
-- ================================================================
ROLLBACK;

-- ================================================================
-- PASSO 8 (fora de transação) — prova de zero resíduo
-- ================================================================
SELECT count(*) AS physical_card_count_depois
FROM public.physical_card
WHERE inventory_id IN (SELECT id FROM public.inventory);
-- Esperado: igual ao Passo -1

SELECT count(*) AS collections_residuais FROM public.collection WHERE name LIKE 'VAL-TEST-02E-%';
-- Esperado: 0

SELECT count(*) AS card_sets_residuais FROM public.card_set WHERE code LIKE 'ZZVAL%';
-- Esperado: 0
