/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5079 - Create apply_master_set_scope_diff Internal Helper Function
Versão......: 2.1
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02F-STAGING-01 →
               -STAGING-REVISION-01 → -STAGING-FINAL-REVISION-02 →
               -IMPLEMENTATION-01)

Descrição...:
Rotina interna COMPARTILHADA pelas duas RPCs que escrevem em
`collection_master_set_scope` — `set_collection_completion_policy_to_
master_set()` (5080, quando `p_card_variant_ids` é fornecido) e
`replace_master_set_scope()` (5082). Implementa a semântica KEEP/ADD/
REMOVE fechada em MODELING-REVISION-01 (item 1) e reafirmada em
MODELING-FINAL-FIX-02 (item 2): NUNCA `DELETE` total + `INSERT` total
— isso destruiria `adopted_at`/`adopted_by_user_id` de Variants que
permanecem no Scope.

CORREÇÃO v2.0 (STAGING-REVISION-01, item 1 — BLOCKER): a v1.0 criava
`CREATE TEMP TABLE _requested ON COMMIT DROP` / `_current ON COMMIT
DROP` dentro do corpo da função. `ON COMMIT DROP` só derruba a tabela
no COMMIT — dentro de uma mesma transação que nunca comita (ex.: a
bateria de validação `5812`, que chama esta função repetidas vezes),
a SEGUNDA chamada falha com "relation already exists". A v2.0 elimina
TEMP TABLEs por completo: KEEP/ADD/REMOVE é calculado inteiramente via
CTEs reconstruídas em cada statement (`WITH requested AS (...)`),
sem nenhum estado de sessão/transação persistido pela função — seguro
para qualquer número de chamadas na mesma transação.

CORREÇÃO v2.0 (STAGING-REVISION-01, item 2 — payload contract): a v1.0
validava só "existe e pertence ao Card Set certo", e usava `SELECT
DISTINCT` para montar o conjunto requisitado — o que tinha o efeito
colateral de NORMALIZAR silenciosamente duplicatas em vez de rejeitá-
las. A v2.0 valida o contrato do payload em camadas, cada uma
produzindo uma mensagem de erro com contagem exata, ANTES de qualquer
escrita:
  1. `p_requested_variant_ids` não-nulo e `jsonb_typeof(...) = 'array'`.
  2. Array não-vazio (Master Set Scope nunca pode ser vazio).
  3. Array não excede o guard operacional (`c_max_variant_ids`).
  4. Todo elemento é uma JSON string (`jsonb_typeof(elem) = 'string'`)
     — number/boolean/object/array aninhado são rejeitados.
  5. Nenhum valor duplicado — `[A,A,B]` é REJEITADO (FAIL, zero
     writes), nunca silenciosamente tratado como `[A,B]`. Checado
     ANTES do cast para UUID, comparando `count(*)` vs.
     `count(DISTINCT elem)` sobre o texto bruto.
  6. Todo elemento casa com o formato UUID (regex), validado ANTES de
     qualquer `::uuid` cast — um cast malformado levantaria um erro de
     runtime não-descritivo (`invalid input syntax for type uuid`) em
     vez de uma mensagem de domínio com contagem.
  7. Todo UUID bem-formado existe em `card_variant` E pertence ao
     mesmo Card Set referenciado pela Collection (mesma condição de
     elegibilidade de `5073`, verificada aqui de forma set-based antes
     de qualquer `DELETE`/`INSERT` — o trigger `BEFORE INSERT`
     continua como camada estrutural independente; esta validação é a
     conveniência de UX que aborta cedo com contagem exata).
Qualquer camada falhando aborta a função inteira via `RAISE EXCEPTION`
antes do primeiro `DELETE`/`INSERT` — atômico por construção de uma
função `plpgsql` única, nenhuma escrita parcial possível.

CORREÇÃO v2.1 (STAGING-FINAL-REVISION-02, item 1 — BLOCKER residual):
a v2.0 detectava duplicatas comparando `count(*)` vs. `count(DISTINCT
elem)` sobre o TEXTO BRUTO do payload — o que NÃO detecta duas
representações textuais do MESMO UUID (ex.: mesmo valor em lowercase e
UPPERCASE): como texto são valores diferentes, mas como UUID são
idênticos. A v2.1 move a checagem de duplicatas para DEPOIS da
validação de formato (regex), e passa a comparar por IDENTIDADE UUID —
`count(*)` vs. `count(DISTINCT elem::uuid)` — nunca mais por igualdade
textual exata. Ordem de validação final (substitui a ordem 1-7
descrita acima nos passos 5/6):
  1. shape do payload (array);
  2. array não-vazio;
  3. guard operacional de tamanho;
  4. todo elemento é string;
  5. todo elemento casa com o formato UUID (regex) — cast passa a ser
     seguro a partir daqui;
  6. duplicatas detectadas por IDENTIDADE UUID (`elem::uuid`), não por
     igualdade textual — corrige o BLOCKER acima; continua uma
     REJEIÇÃO explícita (FAIL, zero writes), nunca uma normalização
     silenciosa via DISTINCT;
  7. existência + pertencimento ao Card Set;
  8. só então qualquer escrita.
Nenhuma outra semântica de 5079 foi alterada — mesma eliminação de
TEMP TABLE (correção v2.0 item 1), mesmo guard operacional provisório
(`c_max_variant_ids`, sujeito a `5813`).

Ordem física DELETE-antes-de-INSERT (correção de documentação,
STAGING-REVISION-01 item 13): a sequência de statements abaixo não é
uma exigência semântica de KEEP/ADD/REMOVE — é apenas a ordem de
implementação escolhida, permitida porque os dois constraint triggers
de `5076`/`5077` são `DEFERRABLE INITIALLY DEFERRED` (o `DELETE` de
REMOVE nunca dispara a checagem de "Scope vazio" de imediato, mesmo
que ele resulte, momentaneamente, em zero linhas antes do `INSERT` de
ADD rodar). O contrato real é: VALIDATE ALL -> calcular KEEP/ADD/
REMOVE -> aplicar o delta atomicamente -> KEEP permanece intocado.

GUARD OPERACIONAL DE PAYLOAD — CONFIRMADO POR EVIDÊNCIA REAL
(COLLECTIONS-PHYSICAL-INCREMENT-02F-CANONICAL-PROMOTION-01, após
COLLECTIONS-PHYSICAL-INCREMENT-02F-PERFORMANCE-01). `c_max_variant_ids
= 10000` é um valor de proteção operacional contra payload abusivo
(tamanho de requisição/tempo de transação) — NUNCA uma decisão de
domínio ou limite arquitetural. Não foi derivado do maior Card Set
físico observado hoje (630 Card Variants na execução real, referência
operacional, nunca arquitetural). `5813` v2.0, executado com um pool
combinado de 10.000 Card Variants (630 reais + 9.370 sintéticas —
materialmente próximo ao teto do guard), mediu `replace_master_set_
scope()` em ~219ms (payload de 9.050 itens, maioria KEEP) e ~151ms
(payload de 1.900 itens, maioria ADD/REMOVE), sem spill de sort/hash
em nenhum plano capturado — evidência que CONFIRMA o valor atual sem
necessidade de redução. Permanece sujeito a revisão futura por nova
evidência operacional (nunca ajuste silencioso desta constante sem uma
rodada de performance dedicada).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE OR REPLACE FUNCTION public.apply_master_set_scope_diff(
    p_collection_id         UUID,
    p_requested_variant_ids JSONB
)
RETURNS TABLE (
    added_count   INTEGER,
    removed_count INTEGER,
    kept_count    INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    -- Guard operacional de payload, NÃO arquitetural — ver descrição
    -- acima. Confirmado por evidência real do plano de performance 5813.
    c_max_variant_ids CONSTANT INTEGER := 10000;

    v_raw_count        INTEGER;
    v_distinct_count   INTEGER;
    v_nonstring_count  INTEGER;
    v_malformed_count  INTEGER;
    v_valid_count      INTEGER;
    v_card_set_id      UUID;
    v_added_count      INTEGER;
    v_removed_count    INTEGER;
    v_kept_count       INTEGER;
BEGIN
    -- 1. Shape do payload: não-nulo e JSON array.
    IF p_requested_variant_ids IS NULL OR jsonb_typeof(p_requested_variant_ids) <> 'array' THEN
        RAISE EXCEPTION 'p_requested_variant_ids must be a non-null JSON array'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT count(*) INTO v_raw_count
    FROM jsonb_array_elements(p_requested_variant_ids);

    -- 2. Array não-vazio.
    IF v_raw_count = 0 THEN
        RAISE EXCEPTION 'p_requested_variant_ids must not be empty — master set scope can never be empty'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 3. Guard operacional de tamanho.
    IF v_raw_count > c_max_variant_ids THEN
        RAISE EXCEPTION 'p_requested_variant_ids exceeds the operational payload guard (% > %) — see 5813 before revising this limit', v_raw_count, c_max_variant_ids
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 4. Todo elemento deve ser uma JSON string — number/boolean/
    -- object/array aninhado são rejeitados explicitamente.
    SELECT count(*) INTO v_nonstring_count
    FROM jsonb_array_elements(p_requested_variant_ids) AS elem
    WHERE jsonb_typeof(elem) <> 'string';

    IF v_nonstring_count > 0 THEN
        RAISE EXCEPTION 'p_requested_variant_ids contains % non-string element(s) — every entry must be a UUID string', v_nonstring_count
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 5. Formato UUID validado por regex ANTES de qualquer cast, para
    -- nunca deixar um erro de cast bruto vazar como exceção não-
    -- descritiva sem contagem. Movido para ANTES da checagem de
    -- duplicata (correção STAGING-FINAL-REVISION-02 item 1 — BLOCKER
    -- residual): a checagem de duplicata abaixo agora faz `::uuid`
    -- cast, e esse cast só é seguro depois que todo elemento já foi
    -- confirmado como UUID bem-formado aqui.
    SELECT count(*) INTO v_malformed_count
    FROM jsonb_array_elements_text(p_requested_variant_ids) AS elem
    WHERE elem !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';

    IF v_malformed_count > 0 THEN
        RAISE EXCEPTION 'p_requested_variant_ids contains % malformed UUID value(s)', v_malformed_count
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 6. Duplicatas REJEITADAS explicitamente — nunca normalizadas via
    -- DISTINCT antes desta checagem (correção do BLOCKER v1.0).
    -- CORREÇÃO STAGING-FINAL-REVISION-02 item 1 (BLOCKER residual): a
    -- v2.0 comparava `count(DISTINCT elem)` sobre o TEXTO BRUTO, o que
    -- não detectava duas representações textuais do MESMO UUID (ex.:
    -- lowercase vs. UPPERCASE) — como texto são valores diferentes,
    -- mas como UUID são idênticos. A v2.1 compara por IDENTIDADE UUID
    -- (`elem::uuid`, cast já seguro por rodar depois do passo 5 acima),
    -- rejeitando corretamente duplicatas canônicas, não só duplicatas
    -- textuais exatas.
    SELECT count(*), count(DISTINCT elem::uuid) INTO v_raw_count, v_distinct_count
    FROM jsonb_array_elements_text(p_requested_variant_ids) AS elem;

    IF v_raw_count <> v_distinct_count THEN
        RAISE EXCEPTION 'p_requested_variant_ids contains % duplicate card_variant_id value(s) by UUID identity — duplicates are rejected, not normalized', v_raw_count - v_distinct_count
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- Card Set referenciado pela Collection (fronteira já validada
    -- pelo chamador via SELECT ... FOR UPDATE antes desta chamada).
    SELECT ccsr.card_set_id INTO v_card_set_id
    FROM public.collection_reference cr
    JOIN public.collection_card_set_reference ccsr
        ON ccsr.collection_reference_id = cr.id
    WHERE cr.collection_id = p_collection_id;

    IF v_card_set_id IS NULL THEN
        RAISE EXCEPTION 'collection % has no CARD_SET reference — cannot resolve master set eligibility', p_collection_id
            USING ERRCODE = 'check_violation';
    END IF;

    -- 7. Existência + pertencimento ao Card Set — validação INTEGRAL
    -- antes de qualquer escrita.
    SELECT count(*) INTO v_valid_count
    FROM jsonb_array_elements_text(p_requested_variant_ids) AS elem
    JOIN public.card_variant cv ON cv.id = elem::uuid
    JOIN public.card card ON card.id = cv.card_id AND card.card_set_id = v_card_set_id;

    IF v_valid_count <> v_distinct_count THEN
        RAISE EXCEPTION 'p_requested_variant_ids contains card_variant_id(s) that do not exist or do not belong to the referenced card set (% of % invalid) — zero changes applied', v_distinct_count - v_valid_count, v_distinct_count
            USING ERRCODE = 'check_violation';
    END IF;

    -- KEEP/ADD/REMOVE, set-based, SEM TEMP TABLE (correção do BLOCKER
    -- v1.0) — CTEs reconstruídas em cada statement; a função pode ser
    -- chamada mais de uma vez na mesma transação sem quebrar.
    WITH requested AS (
        SELECT DISTINCT elem::uuid AS card_variant_id
        FROM jsonb_array_elements_text(p_requested_variant_ids) AS elem
    )
    SELECT count(*) INTO v_kept_count
    FROM public.collection_master_set_scope s
    JOIN requested req ON req.card_variant_id = s.card_variant_id
    WHERE s.collection_id = p_collection_id;

    WITH requested AS (
        SELECT DISTINCT elem::uuid AS card_variant_id
        FROM jsonb_array_elements_text(p_requested_variant_ids) AS elem
    )
    DELETE FROM public.collection_master_set_scope s
    WHERE s.collection_id = p_collection_id
      AND s.card_variant_id NOT IN (SELECT card_variant_id FROM requested);
    GET DIAGNOSTICS v_removed_count = ROW_COUNT;

    WITH requested AS (
        SELECT DISTINCT elem::uuid AS card_variant_id
        FROM jsonb_array_elements_text(p_requested_variant_ids) AS elem
    )
    INSERT INTO public.collection_master_set_scope (collection_id, card_variant_id, adopted_by_user_id)
    SELECT p_collection_id, req.card_variant_id, (select auth.uid())
    FROM requested req
    WHERE req.card_variant_id NOT IN (
        SELECT card_variant_id FROM public.collection_master_set_scope
        WHERE collection_id = p_collection_id
    );
    GET DIAGNOSTICS v_added_count = ROW_COUNT;

    RETURN QUERY SELECT v_added_count, v_removed_count, v_kept_count;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_master_set_scope_diff(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.apply_master_set_scope_diff(uuid, jsonb) FROM anon;
REVOKE ALL ON FUNCTION public.apply_master_set_scope_diff(uuid, jsonb) FROM authenticated;
