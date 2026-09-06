/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5814 - Validate Fatia E (REFERENCE_POSITION Completion)
Versão......: 1.3 (VALIDATION-FINAL-FIX-02)
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em COLLECTIONS-POKEDEX-FATIA-E-STAGING-01,
               revisado em COLLECTIONS-POKEDEX-FATIA-E-STAGING-REVISION-01
               após auditoria direta de 5100/5101 — PASS, não alterados;
               revisado em COLLECTIONS-POKEDEX-FATIA-E-VALIDATION-
               FINAL-FIX-01 após auditoria direta de v1.1 —
               5100/5101/5815/README PASS, não alterados; revisado
               novamente em COLLECTIONS-POKEDEX-FATIA-E-VALIDATION-
               FINAL-FIX-02 após auditoria direta de v1.2 —
               5100/5101/5815/README PASS, não alterados nesta rodada)

CORREÇÃO v1.3 (VALIDATION-FINAL-FIX-02) — auditoria direta de v1.2
encontrou 1 problema final no test harness (não na lógica de 5100/5101):
No Caso N, já sob `SET ROLE authenticated`, o script fazia
`SELECT count(DISTINCT c.id) FROM public.card c WHERE c.card_set_id =
...` para computar o baseline esperado do STANDARD_SET. Isso é inválido:
`public.card` pertence ao Catálogo Editorial, fechado por RLS — RLS
habilitada, nenhuma `CREATE POLICY` permissiva para `authenticated` em
nenhuma tabela do Catálogo (`card`/`card_variant`/`card_set`/
`expansion`/`game`/`pokemon_species`/`pokemon_generation`/`pokedex`/
`pokedex_position`, confirmado por auditoria direta desta rodada) —
`authenticated` sempre recebe 0 linhas dessas tabelas, silenciosamente,
sem erro. Um baseline calculado dessa forma poderia divergir do total
real (que `collection_completion_summary()`, SECURITY DEFINER, calcula
corretamente), produzindo um FAIL falso de regressão. Corrigido:
`regression_standard_total` agora é materializado no PASSO 3, em
contexto privilegiado (antes do primeiro `SET ROLE authenticated`),
junto com `regression_card_set_id`/`regression_variant_1`/
`regression_variant_2`; o Caso N apenas LÊ esse valor de `test_ctx`, sem
nunca recalculá-lo sob `authenticated`. Revisado o restante do arquivo
(grep de todo `FROM public.<tabela do Catálogo>` cruzado com a posição
de cada `SET ROLE authenticated`): nenhum outro ponto do arquivo calcula
expectativa de teste por leitura direta de tabela do Catálogo Editorial
sob `authenticated` — todas as demais ocorrências ficam no PASSO 2/
PASSO 3 (contexto privilegiado, antes da primeira impersonação) ou são
checagens de resíduo do PASSO -1/PASSO 11 (fora de transação/pós-
ROLLBACK, sem impersonação ativa).

CORREÇÃO v1.2 (VALIDATION-FINAL-FIX-01) — auditoria direta de v1.1
encontrou 2 pontos finais, ambos corrigidos:
1. CASO I — COMPARAÇÃO INCOMPLETA + MUTAÇÃO NÃO PROVADA. A v1.1
   comparava só `satisfied_positions`/`total_positions` contra o
   baseline em cada estado — nunca os 5 campos do contrato
   (`total_positions`/`satisfied_positions`/`missing_positions`/
   `progress_percentage`/`is_complete`) — e nunca provava fisicamente
   que a troca de Primary Representative de fato ocorreu (poderia estar
   comparando contra uma chamada que silenciosamente não fez nada).
   Corrigido: os 5 campos são comparados contra o baseline em cada um
   dos 3 estados (criar/trocar/remover), e cada estado tem uma prova
   física direta contra
   `collection_pokedex_position_primary_representative` (Casos
   I.A/I.B/I.C) — a linha aponta para v_alloc_dup1 após criar, para
   v_alloc_dup2 após trocar (mesma PK, confirmando UPSERT), e deixa de
   existir após remover.
2. AUTH CONTEXT — NULL NÃO DETERMINÍSTICO. `auth.uid()` tem fallback
   para `request.jwt.claims.sub` (o claim completo em JSON) além de
   `request.jwt.claim.sub` (o atalho de claim único); limpar somente o
   segundo não garante `auth.uid() IS NULL` se uma impersonação anterior
   tiver deixado `request.jwt.claims` com um `sub` residual. Corrigido:
   toda troca/reset de identidade nesta bateria (entrada do Caso M1B e
   os 5 pontos de `RESET ROLE` entre impersonações) agora limpa os dois
   settings, sempre nesta ordem: `request.jwt.claim.sub` primeiro,
   `request.jwt.claims` (para `'{}'`) em seguida.

CORREÇÃO v1.1 (STAGING-REVISION-01) — auditoria direta encontrou 5
pontos na v1.0, todos corrigidos nesta revisão, nenhum deles em 5100/
5101 (que permanecem intocados, PASS):
1. TEMP PRIVILEGES — v1.0 nunca concedia privilégio explícito a
   `authenticated` sobre `test_ctx`/`test_results`/sua sequence/
   `pg_temp.log_result()`. Objetos TEMP não herdam GRANT de PUBLIC por
   padrão (diferente de funções) — qualquer leitura/escrita sob
   `SET ROLE authenticated` falharia por permissão negada. Corrigido
   com GRANTs explícitos logo antes do primeiro `SET ROLE authenticated`
   (novo Passo 4B), nunca estendidos a `anon`.
2. SECURITY M1 — v1.0 tentava invocar as duas funções sob `role = anon`
   esperando 0 linhas; como `anon` nunca teve `EXECUTE` (REVOKE
   explícito em 5100/5101), a chamada geraria erro de permissão, não
   0 linhas — o teste estava fisicamente incorreto. Corrigido: M1A
   prova a ACL de verdade (via `has_function_privilege`/`aclexplode`,
   nunca um PASS constante), M1B prova separadamente que `auth.uid()
   IS NULL` sob `role = authenticated` (que TEM `EXECUTE`) retorna 0
   linhas pelo filtro interno da CTE `target`, nunca por falta de
   permissão.
3. FIXTURE DETERMINÍSTICO — v1.0 usava `row_number() OVER ()` sobre o
   retorno de `add_physical_cards()` em lote para decidir qual
   Physical Card era `pos1`/`pos2`/etc.; o contrato da RPC não garante
   nenhuma correspondência ordinal entre o array de entrada e a ordem
   das linhas devolvidas. Corrigido: cada Physical Card semanticamente
   identificada agora nasce de uma chamada unitária (array de 1 item),
   capturando o único `id` devolvido diretamente — sem ambiguidade
   possível. Bulk preservado APENAS para o par de duplicatas do Caso F
   (`pc_g1b_dup1`/`pc_g1b_dup2`), onde a identidade individual de cada
   linha é deliberadamente irrelevante, e mesmo ali com
   `row_number() OVER (ORDER BY id)` — determinístico, nunca "sem
   ORDER BY".
4. PRIMARY REPRESENTATIVE — v1.0 só testava criar+remover sobre uma
   única Assignment. Corrigido: o Caso I foi movido para depois do
   Caso F (reaproveitando as duas Assignments reais de `pos2`/
   `col_full` criadas por `pc_g1b_dup1`/`pc_g1b_dup2`) e agora também
   prova TROCAR o Primary Representative entre as duas Assignments da
   MESMA Position, confirmando completion idêntica nos três estados.
5. FUTURE-PROOF FIXTURES — `variant_unresolved` e
   `regression_card_set_id` agora são resolvidos com filtro explícito
   `game.code = 'POKEMON'` (via `card -> card_set -> expansion ->
   game`), em vez de depender implicitamente do catálogo hoje conter
   só Cards Pokémon. Comentário de `species_g1c` corrigido: a Species
   da Position 3 não precisa ser "sem resolução" — o requisito real é
   a Physical Card usada no USER_OVERRIDE não possuir resolução
   compatível, independentemente de qual Species pos3 tem.

Descrição...:
Bateria funcional de validação de 5100/5101 (ramo REFERENCE_POSITION de
collection_completion_summary() + collection_pokedex_scope_positions()).
Mesmo mecanismo já estabelecido em 5808/5810/5812 (Collections) e 6830
(Fatia D): BEGIN...ROLLBACK, pg_temp.log_result()/test_results,
impersonação real via set_config('role'/'request.jwt.claim.sub', ...),
SELECT final consolidado, ROLLBACK incondicional, prova pós-ROLLBACK em
chamada separada. Nenhum COMMIT nesta bateria. Toda troca de role/claim
acontece em statements de TOPO DE TRANSAÇÃO (nunca dentro de um bloco
DO $$ ... $$), mesmo padrão já usado em 5812 — PL/pgSQL não garante
`SET ROLE`/`RESET ROLE` nem `SELECT` sem `INTO`/`PERFORM` como
statements internos de função; os blocos DO desta bateria contêm
apenas lógica de teste (`SELECT ... INTO`, `PERFORM pg_temp.log_result`).

FIXTURE CENTRAL — POKÉDEX DE TESTE DEDICADO: em vez de depender da forma
imprevisível do catálogo Pokémon real (1025 Positions da Pokédex
NATIONAL, cobertura desigual de card_primary_species resolvida por
Generation), esta bateria cria um Pokédex de teste isolado
(`VAL_TEST_FATIA_E_POKEDEX`, código único, `pokedex.code` livre
verificado no Passo -1) com exatamente 5 Positions, reaproveitando
Pokémon Species e Pokémon Generation REAIS já existentes no catálogo
(nenhuma criação de Species/Generation — só de Pokédex/Position, que são
catálogo livre por desenho, Query 6030). Isso torna "Scope completo"
(caso E) e "Assignment fora do Scope" (caso J) genuinamente
alcançáveis dentro de uma única transação, sem depender de nenhuma
Generation real inteira estar 100% coberta por card_primary_species —
condição que a Fatia E não controla e que hoje não se sabe se é
verdadeira para nenhuma Generation real.

Positions do Pokédex de teste (todas resolvidas dinamicamente no Passo
3, nunca hard-coded):
- pos1 -> species_g1a (Generation 1 real escolhida) — SPECIES_MATCH.
- pos2 -> species_g1b (mesma Generation) — SPECIES_MATCH, alvo de 2
  Physical Cards distintas da MESMA Variant (fixture DUPLICATES, Caso F;
  reaproveitada pelo Caso I para o teste de troca de Primary
  Representative).
- pos3 -> species_g1c (mesma Generation — Species escolhida sem nenhum
  requisito especial: USER_OVERRIDE não depende de pos3 ter ou não
  Species resolvida, e sim de a Physical Card usada não possuir
  resolução compatível) — alvo de USER_OVERRIDE via uma Card
  deliberadamente SEM card_primary_species (Caso H).
- pos4 -> species_g1d (mesma Generation) — SPECIES_MATCH, usada para
  fechar o caso COMPLETE (Caso E).
- pos5 -> species_g2a (Generation 2 real, DIFERENTE da Generation 1) —
  SPECIES_MATCH, usada exclusivamente para o caso "Assignment fora do
  Scope" (Caso J: Collections desta bateria com Scope GENERATION_FILTERED
  = [Generation 1] recebem uma Assignment em pos5 — o trigger de
  pokedex-match (Query 6118) permite, porque pos5 pertence ao MESMO
  Pokédex de teste; mas pos5 nunca aparece em reference_position_scope
  quando o filtro é só Generation 1).

Collections construídas (todas via RPCs reais, nunca INSERT direto em
`collection`/`collection_reference`/`collection_pokedex_reference` —
mesma disciplina fail-loud de exercitar a superfície pública real):
- col_full: FULL_REFERENCE -> total=5 (Caso A; também hospeda os Casos
  F e I).
- col_gen1: GENERATION_FILTERED=[gen1] -> total=4 (Caso B, 1 Generation).
- col_gen_both: GENERATION_FILTERED=[gen1,gen2] -> total=5, igual a
  col_full (Caso B, múltiplas Generations).
- col_zero: FULL_REFERENCE, zero Allocations -> numerator=0, progress=0
  (Caso C).
- col_partial: GENERATION_FILTERED=[gen1], só pos1+pos2 satisfeitas
  (2/4) (Caso D).
- col_complete: GENERATION_FILTERED=[gen1], pos1+pos2+pos3(override)+
  pos4 satisfeitas (4/4) (Caso E, G, H).
- col_outscope: GENERATION_FILTERED=[gen1], pos1 satisfeita (in-scope) +
  Assignment em pos5 (fora do Scope) (Caso J).
- col_scope_mut: GENERATION_FILTERED=[gen1], pos1 satisfeita -> Scope
  mutado para GENERATION_FILTERED=[gen2] -> pos1 sai do read
  model/summary sem a Assignment ser removida -> Scope mutado de volta
  para [gen1] -> pos1 reaparece contada (Caso K).
- col_standard / col_master: fixtures mínimas REAIS de STANDARD_SET/
  MASTER_SET (Card Set do catálogo real, restrito ao Game POKEMON),
  para regressão pós-5100 (Casos N/O) — nenhuma delas toca o Pokédex
  de teste.

Segurança/não-enumeração (Caso M): M1A prova a ACL real (authenticated
tem EXECUTE; anon e PUBLIC não têm, nas duas funções — nunca invocando
a função como anon, o que geraria erro de permissão em vez de um
resultado vazio); M1B prova `auth.uid() IS NULL` sob `authenticated`
(que TEM EXECUTE); M2/M3 provam Owner B contra Collection de Owner A e
Collection inexistente; M4/M5/M6 provam OPEN_CURATION/STANDARD_SET/
MASTER_SET. Todos devem produzir 0 linhas (para
collection_pokedex_scope_positions) ou 0 linhas no ramo correspondente
(para collection_completion_summary), nunca erro nem vazamento.

Cobertura desta bateria (mandato item 7, casos A-O):
A. FULL_REFERENCE — denominator correto; read model retorna todas as
   Positions.
B. GENERATION_FILTERED — 1 Generation; múltiplas Generations;
   denominator correto.
C. zero Assignment — numerator 0; progress 0.
D. parcial.
E. completa.
F. duas ou mais Physical Cards na mesma Position — numerator continua 1
   para a Position.
G. SPECIES_MATCH conta.
H. USER_OVERRIDE conta igualmente.
I. Primary Representative: criar / TROCAR entre duas Assignments da
   mesma Position / remover; completion não muda em nenhum dos três
   estados.
J. Assignment fora do Scope: existe fisicamente; não conta; não aparece
   em collection_pokedex_scope_positions().
K. Scope mutation: Assignment preservado; summary recalculada; Position
   entra/sai do read model conforme novo Scope.
L. p_only_missing false/true.
M. segurança/não-enumeração: ACL real (M1A); auth.uid() NULL sob
   authenticated (M1B); outro owner (M2); collection inexistente (M3);
   OPEN_CURATION/STANDARD_SET/MASTER_SET (M4-M6); todos sem vazamento.
N. regressão STANDARD_SET.
O. regressão MASTER_SET.

Comparação antes/depois exigida pelo mandato (não apenas ausência de
erro): cada caso de completion compara o valor NUMÉRICO esperado
(total_positions/satisfied_positions/progress_percentage/is_complete)
contra o retornado pela função, nunca só "não lançou exceção".

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

-- ================================================================
-- PASSO -1 (fora de transação) — baseline de resíduo
-- ================================================================
SELECT count(*) AS collections_com_prefixo_antes
FROM public.collection
WHERE name LIKE 'VAL-TEST-FATIA-E-%';

SELECT count(*) AS pokedex_teste_antes
FROM public.pokedex
WHERE code = 'VAL_TEST_FATIA_E_POKEDEX';

SELECT count(*) AS assignments_com_prefixo_antes
FROM public.collection_pokedex_position_assignment a
JOIN public.collection_allocation ca ON ca.id = a.collection_allocation_id
JOIN public.collection c ON c.id = ca.collection_id
WHERE c.name LIKE 'VAL-TEST-FATIA-E-%';

-- ================================================================
-- PASSO 0 — BEGIN + infraestrutura de log
-- ================================================================
BEGIN;

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

-- ================================================================
-- PASSO 1 — POSTCHECKS ESTRUTURAIS (5100/5101 existem com a forma certa)
-- ================================================================

-- POSTCHECK-1 — collection_completion_summary contém os quatro novos
-- identificadores do ramo REFERENCE_POSITION.
DO $$
DECLARE
    v_src TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p WHERE p.proname = 'collection_completion_summary';

    PERFORM pg_temp.log_result('POSTCHECK-1 - collection_completion_summary contem reference_position_target',
        v_src LIKE '%reference_position_target%', NULL);
    PERFORM pg_temp.log_result('POSTCHECK-1b - contem reference_position_scope',
        v_src LIKE '%reference_position_scope%', NULL);
    PERFORM pg_temp.log_result('POSTCHECK-1c - contem reference_position_denom',
        v_src LIKE '%reference_position_denom%', NULL);
    PERFORM pg_temp.log_result('POSTCHECK-1d - contem reference_position_numer',
        v_src LIKE '%reference_position_numer%', NULL);
    PERFORM pg_temp.log_result('POSTCHECK-1e - ramos STANDARD_SET/MASTER_SET preservados (target CARD_SET intacto)',
        v_src LIKE '%ccsr.card_set_id%' AND v_src LIKE '%standard_denom%' AND v_src LIKE '%master_denom%', NULL);
END $$;

-- POSTCHECK-2 — collection_pokedex_scope_positions existe com a
-- assinatura/contrato congelados.
DO $$
DECLARE
    v_oid OID;
    v_src TEXT;
BEGIN
    v_oid := to_regprocedure('public.collection_pokedex_scope_positions(uuid, boolean)');
    PERFORM pg_temp.log_result('POSTCHECK-2 - collection_pokedex_scope_positions(uuid, boolean) existe',
        v_oid IS NOT NULL, NULL);

    SELECT pg_get_functiondef(v_oid) INTO v_src;
    PERFORM pg_temp.log_result('POSTCHECK-2b - RETURNS TABLE contem os 5 campos do contrato congelado',
        v_src LIKE '%pokedex_position_id%'
        AND v_src LIKE '%position_number%'
        AND v_src LIKE '%species_id%'
        AND v_src LIKE '%species_name%'
        AND v_src LIKE '%is_satisfied%', NULL);
    PERFORM pg_temp.log_result('POSTCHECK-2c - NAO contem Primary Representative/assignment_count/Physical Card/UX',
        v_src NOT ILIKE '%primary_representative%'
        AND v_src NOT ILIKE '%assignment_count%'
        AND v_src NOT ILIKE '%physical_card%', NULL);
END $$;

-- POSTCHECK-3 — segurança: LANGUAGE SQL, STABLE, SECURITY DEFINER,
-- search_path=''.
DO $$
DECLARE
    r RECORD;
BEGIN
    SELECT p.provolatile, p.prosecdef, l.lanname, p.proconfig INTO r
    FROM pg_proc p
    JOIN pg_language l ON l.oid = p.prolang
    WHERE p.oid = to_regprocedure('public.collection_pokedex_scope_positions(uuid, boolean)');

    PERFORM pg_temp.log_result('POSTCHECK-3 - LANGUAGE SQL', r.lanname = 'sql', r.lanname);
    PERFORM pg_temp.log_result('POSTCHECK-3b - STABLE', r.provolatile = 's', r.provolatile::text);
    PERFORM pg_temp.log_result('POSTCHECK-3c - SECURITY DEFINER', r.prosecdef IS TRUE, NULL);
    PERFORM pg_temp.log_result('POSTCHECK-3d - search_path vazio no proconfig',
        EXISTS (SELECT 1 FROM unnest(r.proconfig) cfg WHERE split_part(cfg, '=', 1) = 'search_path' AND split_part(cfg, '=', 2) IN ('', '""')),
        array_to_string(r.proconfig, ','));
END $$;

-- POSTCHECK-4 — ACL estrutural (mesma prova de M1A, antecipada aqui
-- para o bloco de postchecks): authenticated com EXECUTE; anon sem.
DO $$
BEGIN
    PERFORM pg_temp.log_result('POSTCHECK-4 - authenticated tem EXECUTE em collection_pokedex_scope_positions',
        has_function_privilege('authenticated', 'public.collection_pokedex_scope_positions(uuid, boolean)', 'EXECUTE'), NULL);
    PERFORM pg_temp.log_result('POSTCHECK-4b - anon NAO tem EXECUTE',
        NOT has_function_privilege('anon', 'public.collection_pokedex_scope_positions(uuid, boolean)', 'EXECUTE'), NULL);
END $$;

-- ================================================================
-- PASSO 2 — PRÉ-CONDIÇÕES (fail-loud)
-- ================================================================
DO $$
DECLARE
    v_owner_count       INT;
    v_game_id           UUID;
    v_language_count    INT;
    v_generation_count  INT;
    v_unresolved_count  INT;
BEGIN
    SELECT count(DISTINCT i.owner_user_id) INTO v_owner_count
    FROM public.inventory i
    WHERE i.owner_user_id NOT IN (SELECT au.id FROM public.admin_user au);
    IF v_owner_count < 2 THEN
        RAISE EXCEPTION 'fixtures insuficientes: >= 2 Owners NAO-ADMIN distintos com Inventory necessarios (encontrados: %)', v_owner_count;
    END IF;

    SELECT g.id INTO v_game_id FROM public.game g WHERE g.code = 'POKEMON';
    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'fixtures insuficientes: Game POKEMON nao encontrado';
    END IF;

    SELECT count(*) INTO v_language_count FROM public.language;
    IF v_language_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhuma Language encontrada';
    END IF;

    -- >= 2 Generations distintas com >= 4 Species resolvidas
    -- (card_primary_species + >= 1 Card Variant) na primeira, e >= 1 na
    -- segunda — necessário para montar pos1/pos2/pos4 (gen1) e pos5
    -- (gen2) com SPECIES_MATCH automático real.
    SELECT count(*) INTO v_generation_count
    FROM (
        SELECT sp.generation_id
        FROM public.pokemon_species sp
        JOIN public.card_primary_species cps ON cps.pokemon_species_id = sp.id
        JOIN public.card_variant cv ON cv.card_id = cps.card_id
        GROUP BY sp.generation_id
        HAVING count(DISTINCT sp.id) >= 4
    ) g;
    IF v_generation_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhuma Generation com >= 4 Species resolvidas (card_primary_species + Card Variant) encontrada';
    END IF;

    SELECT count(DISTINCT sp.generation_id) INTO v_generation_count
    FROM public.pokemon_species sp
    JOIN public.card_primary_species cps ON cps.pokemon_species_id = sp.id
    JOIN public.card_variant cv ON cv.card_id = cps.card_id;
    IF v_generation_count < 2 THEN
        RAISE EXCEPTION 'fixtures insuficientes: sao necessarias >= 2 Generations distintas com pelo menos 1 Species resolvida cada';
    END IF;

    -- Card SEM card_primary_species resolvida, restrita ao Game POKEMON
    -- (FUTURE-PROOF: nunca depender implicitamente de o catálogo hoje
    -- só ter Pokémon) — para o Caso USER_OVERRIDE.
    SELECT count(*) INTO v_unresolved_count
    FROM public.card c
    JOIN public.card_variant cv ON cv.card_id = c.id
    JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    JOIN public.game gm ON gm.id = ex.game_id
    LEFT JOIN public.card_primary_species cps ON cps.card_id = c.id
    WHERE cps.card_id IS NULL
      AND gm.code = 'POKEMON';
    IF v_unresolved_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhuma Card POKEMON sem card_primary_species resolvida encontrada (necessaria para USER_OVERRIDE)';
    END IF;

    -- Card Set real do Game POKEMON com >= 2 Card Variants distintas
    -- (STANDARD_SET/MASTER_SET) para as regressões N/O.
    IF NOT EXISTS (
        SELECT 1 FROM public.card c
        JOIN public.card_variant cv ON cv.card_id = c.id
        JOIN public.card_set cs ON cs.id = c.card_set_id
        JOIN public.expansion ex ON ex.id = cs.expansion_id
        JOIN public.game gm ON gm.id = ex.game_id
        WHERE gm.code = 'POKEMON'
        GROUP BY c.card_set_id
        HAVING count(DISTINCT cv.id) >= 2
    ) THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhum Card Set real do Game POKEMON com >= 2 Card Variants encontrado (necessario para regressao MASTER_SET)';
    END IF;
END $$;

-- ================================================================
-- PASSO 3 — resolver contexto em test_ctx (key/value)
-- ================================================================
CREATE TEMP TABLE test_ctx (key TEXT PRIMARY KEY, value TEXT);

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

INSERT INTO test_ctx (key, value)
SELECT 'game_id', id::text FROM public.game WHERE code = 'POKEMON';

-- gen1: Generation com >= 4 Species resolvidas (card_primary_species +
-- Card Variant). gen2: qualquer outra Generation distinta com >= 1
-- Species resolvida.
DO $$
DECLARE
    v_gen1 UUID;
    v_gen2 UUID;
BEGIN
    SELECT sp.generation_id INTO v_gen1
    FROM public.pokemon_species sp
    JOIN public.card_primary_species cps ON cps.pokemon_species_id = sp.id
    JOIN public.card_variant cv ON cv.card_id = cps.card_id
    GROUP BY sp.generation_id
    HAVING count(DISTINCT sp.id) >= 4
    ORDER BY sp.generation_id
    LIMIT 1;

    SELECT sp.generation_id INTO v_gen2
    FROM public.pokemon_species sp
    JOIN public.card_primary_species cps ON cps.pokemon_species_id = sp.id
    JOIN public.card_variant cv ON cv.card_id = cps.card_id
    WHERE sp.generation_id <> v_gen1
    ORDER BY sp.generation_id
    LIMIT 1;

    INSERT INTO test_ctx (key, value) VALUES ('gen1_id', v_gen1::text), ('gen2_id', v_gen2::text);
END $$;

-- species_g1a/g1b/g1d: 3 Species distintas de gen1, cada uma com >= 1
-- Card Variant resolvida (card_primary_species). species_g1c: uma 4ª
-- Species de gen1, sem exigência de resolução — só usada como Species
-- da Position 3 (ver nota da CORREÇÃO v1.1, item 5, no cabeçalho).
CREATE TEMP TABLE test_gen1_species (species_id UUID, variant_id UUID, rn INT);

INSERT INTO test_gen1_species (species_id, variant_id, rn)
SELECT species_id, variant_id, row_number() OVER (ORDER BY species_id)
FROM (
    SELECT DISTINCT ON (sp.id) sp.id AS species_id, cv.id AS variant_id
    FROM public.pokemon_species sp
    JOIN public.card_primary_species cps ON cps.pokemon_species_id = sp.id
    JOIN public.card_variant cv ON cv.card_id = cps.card_id
    WHERE sp.generation_id = (SELECT value::uuid FROM test_ctx WHERE key = 'gen1_id')
    ORDER BY sp.id, cv.id
    LIMIT 3
) sub;

INSERT INTO test_ctx (key, value) SELECT 'species_g1a', species_id::text FROM test_gen1_species WHERE rn = 1;
INSERT INTO test_ctx (key, value) SELECT 'variant_g1a', variant_id::text FROM test_gen1_species WHERE rn = 1;
INSERT INTO test_ctx (key, value) SELECT 'species_g1b', species_id::text FROM test_gen1_species WHERE rn = 2;
INSERT INTO test_ctx (key, value) SELECT 'variant_g1b', variant_id::text FROM test_gen1_species WHERE rn = 2;
INSERT INTO test_ctx (key, value) SELECT 'species_g1d', species_id::text FROM test_gen1_species WHERE rn = 3;
INSERT INTO test_ctx (key, value) SELECT 'variant_g1d', variant_id::text FROM test_gen1_species WHERE rn = 3;

INSERT INTO test_ctx (key, value)
SELECT 'species_g1c', sp.id::text
FROM public.pokemon_species sp
WHERE sp.generation_id = (SELECT value::uuid FROM test_ctx WHERE key = 'gen1_id')
  AND sp.id NOT IN (SELECT species_id FROM test_gen1_species)
LIMIT 1;

-- species_g2a: 1 Species de gen2, com >= 1 Card Variant resolvida.
DO $$
DECLARE
    v_species UUID;
    v_variant UUID;
BEGIN
    SELECT sp.id, cv.id INTO v_species, v_variant
    FROM public.pokemon_species sp
    JOIN public.card_primary_species cps ON cps.pokemon_species_id = sp.id
    JOIN public.card_variant cv ON cv.card_id = cps.card_id
    WHERE sp.generation_id = (SELECT value::uuid FROM test_ctx WHERE key = 'gen2_id')
    ORDER BY sp.id, cv.id
    LIMIT 1;

    INSERT INTO test_ctx (key, value) VALUES ('species_g2a', v_species::text), ('variant_g2a', v_variant::text);
END $$;

-- variant_unresolved: Card Variant cuja Card NAO tem card_primary_species,
-- restrita ao Game POKEMON (CORREÇÃO v1.1, item 5) — fixture USER_OVERRIDE,
-- Caso H.
INSERT INTO test_ctx (key, value)
SELECT 'variant_unresolved', cv.id::text
FROM public.card c
JOIN public.card_variant cv ON cv.card_id = c.id
JOIN public.card_set cs ON cs.id = c.card_set_id
JOIN public.expansion ex ON ex.id = cs.expansion_id
JOIN public.game gm ON gm.id = ex.game_id
LEFT JOIN public.card_primary_species cps ON cps.card_id = c.id
WHERE cps.card_id IS NULL
  AND gm.code = 'POKEMON'
LIMIT 1;

-- Card Set real do Game POKEMON para regressão STANDARD_SET/MASTER_SET
-- (N/O), restrito explicitamente (CORREÇÃO v1.1, item 5): Set com >= 2
-- Card Variants distintas. CORREÇÃO v1.3 (VALIDATION-FINAL-FIX-02, item
-- único): o total esperado de Cards do Set (usado como baseline do
-- Caso N) é materializado AQUI, em contexto privilegiado, nunca sob
-- "SET ROLE authenticated" — public.card pertence ao Catálogo
-- Editorial, fechado por RLS (RLS habilitada, nenhuma policy
-- permissiva para authenticated em nenhuma das tabelas do Catálogo:
-- card/card_variant/card_set/expansion/game/pokemon_species/
-- pokemon_generation/pokedex/pokedex_position — SELECT direto sob
-- authenticated sempre retorna 0 linhas, nunca um erro, o que tornaria
-- qualquer comparação feita sob esse role um falso-FAIL/falso-PASS
-- silencioso). Guardado em test_ctx como 'regression_standard_total'
-- para ser lido, já sob authenticated, no Caso N — nunca recalculado
-- ali.
DO $$
DECLARE
    v_card_set UUID;
    v_v1 UUID;
    v_v2 UUID;
    v_standard_total BIGINT;
BEGIN
    SELECT c.card_set_id INTO v_card_set
    FROM public.card c
    JOIN public.card_variant cv ON cv.card_id = c.id
    JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    JOIN public.game gm ON gm.id = ex.game_id
    WHERE gm.code = 'POKEMON'
    GROUP BY c.card_set_id
    HAVING count(DISTINCT cv.id) >= 2
    ORDER BY c.card_set_id
    LIMIT 1;

    SELECT cv.id INTO v_v1
    FROM public.card c JOIN public.card_variant cv ON cv.card_id = c.id
    WHERE c.card_set_id = v_card_set ORDER BY cv.id LIMIT 1;

    SELECT cv.id INTO v_v2
    FROM public.card c JOIN public.card_variant cv ON cv.card_id = c.id
    WHERE c.card_set_id = v_card_set AND cv.id <> v_v1 ORDER BY cv.id LIMIT 1;

    -- Baseline privilegiado do Caso N — mesmo critério de denominator
    -- que reference_position_denom/standard_denom aplicam para
    -- STANDARD_SET (count DISTINCT de Card do Set), calculado aqui
    -- porque authenticated nao consegue ler public.card diretamente.
    SELECT count(DISTINCT c.id) INTO v_standard_total
    FROM public.card c
    WHERE c.card_set_id = v_card_set;

    INSERT INTO test_ctx (key, value) VALUES
        ('regression_card_set_id', v_card_set::text),
        ('regression_variant_1', v_v1::text),
        ('regression_variant_2', v_v2::text),
        ('regression_standard_total', v_standard_total::text);
END $$;

-- ================================================================
-- PASSO 4 — fixtures privilegiadas: Storage, Pokédex de teste + 5
-- Positions (contexto privilegiado, antes do SET ROLE).
-- ================================================================
WITH ins AS (
    INSERT INTO public.storage_container (inventory_id, name)
    VALUES ((SELECT value::uuid FROM test_ctx WHERE key = 'inventory_a'), 'VAL-TEST-FATIA-E-STORAGE-A')
    RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'storage_a', id::text FROM ins;

WITH ins AS (
    INSERT INTO public.storage_container (inventory_id, name)
    VALUES ((SELECT value::uuid FROM test_ctx WHERE key = 'inventory_b'), 'VAL-TEST-FATIA-E-STORAGE-B')
    RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'storage_b', id::text FROM ins;

-- Pokédex de teste dedicado (Query 6030 é catálogo livre — nenhuma
-- restrição de singleton; code livre confirmado no Passo -1).
WITH ins AS (
    INSERT INTO public.pokedex (code, canonical_name)
    VALUES ('VAL_TEST_FATIA_E_POKEDEX', 'VAL-TEST-FATIA-E Pokedex de Validacao')
    RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pokedex_test_id', id::text FROM ins;

-- 5 Positions do Pokédex de teste, reaproveitando Species reais.
WITH ins AS (
    INSERT INTO public.pokedex_position (pokedex_id, species_id, position_number)
    VALUES ((SELECT value::uuid FROM test_ctx WHERE key = 'pokedex_test_id'),
            (SELECT value::uuid FROM test_ctx WHERE key = 'species_g1a'), 1)
    RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pos1', id::text FROM ins;

WITH ins AS (
    INSERT INTO public.pokedex_position (pokedex_id, species_id, position_number)
    VALUES ((SELECT value::uuid FROM test_ctx WHERE key = 'pokedex_test_id'),
            (SELECT value::uuid FROM test_ctx WHERE key = 'species_g1b'), 2)
    RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pos2', id::text FROM ins;

WITH ins AS (
    INSERT INTO public.pokedex_position (pokedex_id, species_id, position_number)
    VALUES ((SELECT value::uuid FROM test_ctx WHERE key = 'pokedex_test_id'),
            (SELECT value::uuid FROM test_ctx WHERE key = 'species_g1c'), 3)
    RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pos3', id::text FROM ins;

WITH ins AS (
    INSERT INTO public.pokedex_position (pokedex_id, species_id, position_number)
    VALUES ((SELECT value::uuid FROM test_ctx WHERE key = 'pokedex_test_id'),
            (SELECT value::uuid FROM test_ctx WHERE key = 'species_g1d'), 4)
    RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pos4', id::text FROM ins;

WITH ins AS (
    INSERT INTO public.pokedex_position (pokedex_id, species_id, position_number)
    VALUES ((SELECT value::uuid FROM test_ctx WHERE key = 'pokedex_test_id'),
            (SELECT value::uuid FROM test_ctx WHERE key = 'species_g2a'), 5)
    RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pos5', id::text FROM ins;

-- ================================================================
-- PASSO 4B — GRANTs em objetos TEMP (CORREÇÃO v1.1, item 1). Objetos
-- TEMP não herdam privilégio de PUBLIC por padrão (ao contrário de
-- funções) — sem isto, qualquer leitura/escrita em test_ctx/
-- test_results e qualquer chamada a pg_temp.log_result() feita sob
-- "SET ROLE authenticated" (Passo 5 em diante) falharia por permissão
-- negada. NUNCA estendido a anon — não existe, nesta revisão, nenhuma
-- chamada de teste que dependa de anon conseguir escrever/ler estes
-- objetos (M1A prova a ACL de anon por introspecção, nunca por
-- invocação).
-- ================================================================
GRANT SELECT, INSERT ON test_ctx TO authenticated;
GRANT SELECT, INSERT ON test_results TO authenticated;
GRANT USAGE ON SEQUENCE test_results_id_seq TO authenticated;
GRANT EXECUTE ON FUNCTION pg_temp.log_result(TEXT, BOOLEAN, TEXT) TO authenticated;

-- ================================================================
-- PASSO 5 — Owner A cria as Collections Pokédex via RPC real
-- (impersonação authenticated a partir daqui).
-- ================================================================
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', (SELECT value FROM test_ctx WHERE key = 'owner_a'), true);

-- col_full — FULL_REFERENCE, total esperado = 5.
WITH ins AS (
    SELECT id FROM public.create_reference_based_pokedex_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id'),
        'VAL-TEST-FATIA-E-COL-FULL', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pokedex_test_id'),
        'FULL_REFERENCE', NULL
    )
)
INSERT INTO test_ctx (key, value) SELECT 'col_full', id::text FROM ins;

-- col_gen1 — GENERATION_FILTERED=[gen1], total esperado = 4.
WITH ins AS (
    SELECT id FROM public.create_reference_based_pokedex_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id'),
        'VAL-TEST-FATIA-E-COL-GEN1', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pokedex_test_id'),
        'GENERATION_FILTERED', ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'gen1_id')]
    )
)
INSERT INTO test_ctx (key, value) SELECT 'col_gen1', id::text FROM ins;

-- col_gen_both — GENERATION_FILTERED=[gen1,gen2], total esperado = 5.
WITH ins AS (
    SELECT id FROM public.create_reference_based_pokedex_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id'),
        'VAL-TEST-FATIA-E-COL-GENBOTH', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pokedex_test_id'),
        'GENERATION_FILTERED', ARRAY[
            (SELECT value::uuid FROM test_ctx WHERE key = 'gen1_id'),
            (SELECT value::uuid FROM test_ctx WHERE key = 'gen2_id')
        ]
    )
)
INSERT INTO test_ctx (key, value) SELECT 'col_gen_both', id::text FROM ins;

-- col_zero — FULL_REFERENCE, zero Allocations.
WITH ins AS (
    SELECT id FROM public.create_reference_based_pokedex_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id'),
        'VAL-TEST-FATIA-E-COL-ZERO', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pokedex_test_id'),
        'FULL_REFERENCE', NULL
    )
)
INSERT INTO test_ctx (key, value) SELECT 'col_zero', id::text FROM ins;

-- col_partial — GENERATION_FILTERED=[gen1], só pos1+pos2 serão satisfeitas.
WITH ins AS (
    SELECT id FROM public.create_reference_based_pokedex_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id'),
        'VAL-TEST-FATIA-E-COL-PARTIAL', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pokedex_test_id'),
        'GENERATION_FILTERED', ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'gen1_id')]
    )
)
INSERT INTO test_ctx (key, value) SELECT 'col_partial', id::text FROM ins;

-- col_complete — GENERATION_FILTERED=[gen1], as 4 Positions serão satisfeitas.
WITH ins AS (
    SELECT id FROM public.create_reference_based_pokedex_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id'),
        'VAL-TEST-FATIA-E-COL-COMPLETE', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pokedex_test_id'),
        'GENERATION_FILTERED', ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'gen1_id')]
    )
)
INSERT INTO test_ctx (key, value) SELECT 'col_complete', id::text FROM ins;

-- col_outscope — GENERATION_FILTERED=[gen1]; receberá Assignment em
-- pos5 (fora do Scope, mesma Pokédex).
WITH ins AS (
    SELECT id FROM public.create_reference_based_pokedex_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id'),
        'VAL-TEST-FATIA-E-COL-OUTSCOPE', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pokedex_test_id'),
        'GENERATION_FILTERED', ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'gen1_id')]
    )
)
INSERT INTO test_ctx (key, value) SELECT 'col_outscope', id::text FROM ins;

-- col_scope_mut — GENERATION_FILTERED=[gen1]; usada para o Caso K
-- (mutação de Scope).
WITH ins AS (
    SELECT id FROM public.create_reference_based_pokedex_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id'),
        'VAL-TEST-FATIA-E-COL-SCOPEMUT', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pokedex_test_id'),
        'GENERATION_FILTERED', ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'gen1_id')]
    )
)
INSERT INTO test_ctx (key, value) SELECT 'col_scope_mut', id::text FROM ins;

-- col_open — OPEN_CURATION (Caso M, não-enumeração de policy incompatível).
WITH ins AS (
    SELECT id FROM public.create_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id'),
        'VAL-TEST-FATIA-E-COL-OPEN', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a')
    )
)
INSERT INTO test_ctx (key, value) SELECT 'col_open', id::text FROM ins;

-- col_standard — STANDARD_SET real (Caso N, regressão).
WITH ins AS (
    SELECT id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id'),
        'VAL-TEST-FATIA-E-COL-STANDARD', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'regression_card_set_id')
    )
)
INSERT INTO test_ctx (key, value) SELECT 'col_standard', id::text FROM ins;

-- col_master — MASTER_SET real (Caso O, regressão): nasce STANDARD_SET,
-- depois transiciona.
WITH ins AS (
    SELECT id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id'),
        'VAL-TEST-FATIA-E-COL-MASTER', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'regression_card_set_id')
    )
)
INSERT INTO test_ctx (key, value) SELECT 'col_master', id::text FROM ins;

SELECT public.set_collection_completion_policy_to_master_set(
    (SELECT value::uuid FROM test_ctx WHERE key = 'col_master'),
    jsonb_build_array(
        (SELECT value FROM test_ctx WHERE key = 'regression_variant_1'),
        (SELECT value FROM test_ctx WHERE key = 'regression_variant_2')
    )
);

-- ================================================================
-- PASSO 6 — add_physical_cards() para cada Physical Card necessária,
-- ainda como Owner A (CORREÇÃO v1.1, item 3: uma chamada UNITÁRIA por
-- Physical Card semanticamente identificada — o contrato de
-- add_physical_cards() não garante correspondência ordinal entre o
-- array de entrada e a ordem das linhas devolvidas, então nenhum
-- row_number() sobre um lote pode decidir "qual" Physical Card vira
-- pos1/pos2/etc.). A única exceção aceita é o par de duplicatas do
-- Caso F, onde a identidade individual de cada Physical Card é
-- deliberadamente irrelevante — ver mais abaixo.
-- ================================================================

-- col_gen1 / col_gen_both: 1 Allocation cada, só para não ficarem
-- indistinguíveis de col_zero.
WITH ins AS (
    SELECT id FROM public.add_physical_cards(jsonb_build_array(jsonb_build_object(
        'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_g1a'),
        'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
    )))
)
INSERT INTO test_ctx (key, value) SELECT 'pc_gen1_pos1', id::text FROM ins;

WITH ins AS (
    SELECT id FROM public.add_physical_cards(jsonb_build_array(jsonb_build_object(
        'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_g1a'),
        'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
    )))
)
INSERT INTO test_ctx (key, value) SELECT 'pc_genboth_pos1', id::text FROM ins;

-- col_partial: pos1 + pos2.
WITH ins AS (
    SELECT id FROM public.add_physical_cards(jsonb_build_array(jsonb_build_object(
        'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_g1a'),
        'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
    )))
)
INSERT INTO test_ctx (key, value) SELECT 'pc_partial_pos1', id::text FROM ins;

WITH ins AS (
    SELECT id FROM public.add_physical_cards(jsonb_build_array(jsonb_build_object(
        'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_g1b'),
        'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
    )))
)
INSERT INTO test_ctx (key, value) SELECT 'pc_partial_pos2', id::text FROM ins;

-- col_complete: pos1 + pos2 + pos4 (SPECIES_MATCH) + 1 para pos3 via
-- override (variant_unresolved).
WITH ins AS (
    SELECT id FROM public.add_physical_cards(jsonb_build_array(jsonb_build_object(
        'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_g1a'),
        'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
    )))
)
INSERT INTO test_ctx (key, value) SELECT 'pc_complete_pos1', id::text FROM ins;

WITH ins AS (
    SELECT id FROM public.add_physical_cards(jsonb_build_array(jsonb_build_object(
        'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_g1b'),
        'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
    )))
)
INSERT INTO test_ctx (key, value) SELECT 'pc_complete_pos2', id::text FROM ins;

WITH ins AS (
    SELECT id FROM public.add_physical_cards(jsonb_build_array(jsonb_build_object(
        'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_g1d'),
        'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
    )))
)
INSERT INTO test_ctx (key, value) SELECT 'pc_complete_pos4', id::text FROM ins;

WITH ins AS (
    SELECT id FROM public.add_physical_cards(jsonb_build_array(jsonb_build_object(
        'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_unresolved'),
        'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
    )))
)
INSERT INTO test_ctx (key, value) SELECT 'pc_complete_pos3_override', id::text FROM ins;

-- col_outscope: pos1 (in-scope) + pos5 (fora do Scope).
WITH ins AS (
    SELECT id FROM public.add_physical_cards(jsonb_build_array(jsonb_build_object(
        'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_g1a'),
        'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
    )))
)
INSERT INTO test_ctx (key, value) SELECT 'pc_outscope_pos1', id::text FROM ins;

WITH ins AS (
    SELECT id FROM public.add_physical_cards(jsonb_build_array(jsonb_build_object(
        'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_g2a'),
        'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
    )))
)
INSERT INTO test_ctx (key, value) SELECT 'pc_outscope_pos5', id::text FROM ins;

-- col_scope_mut: pos1.
WITH ins AS (
    SELECT id FROM public.add_physical_cards(jsonb_build_array(jsonb_build_object(
        'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_g1a'),
        'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
    )))
)
INSERT INTO test_ctx (key, value) SELECT 'pc_scopemut_pos1', id::text FROM ins;

-- col_standard / col_master: 1 Physical Card real cada, da Variant de
-- regressão.
WITH ins AS (
    SELECT id FROM public.add_physical_cards(jsonb_build_array(jsonb_build_object(
        'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'regression_variant_1'),
        'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
    )))
)
INSERT INTO test_ctx (key, value) SELECT 'pc_standard_1', id::text FROM ins;

WITH ins AS (
    SELECT id FROM public.add_physical_cards(jsonb_build_array(jsonb_build_object(
        'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'regression_variant_1'),
        'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
    )))
)
INSERT INTO test_ctx (key, value) SELECT 'pc_master_1', id::text FROM ins;

-- pc_g1b_dup1/pc_g1b_dup2 (Caso F, DUPLICATES; reaproveitadas pelo
-- Caso I): 2 Physical Cards da MESMA Variant (variant_g1b). Identidade
-- individual deliberadamente irrelevante — qualquer uma das duas pode
-- ser "dup1" ou "dup2", o teste só precisa de duas linhas fisicamente
-- distintas apontando para a mesma Position via SPECIES_MATCH
-- automático. Único ponto desta bateria onde uma chamada bulk
-- permanece aceitável (CORREÇÃO v1.1, item 3) — e mesmo aqui com
-- row_number() SOBRE UM ORDER BY explícito (nunca "sem ORDER BY").
WITH ins AS (
    SELECT id, row_number() OVER (ORDER BY id) AS rn FROM public.add_physical_cards(
        jsonb_build_array(
            jsonb_build_object('card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_g1b'), 'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')),
            jsonb_build_object('card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_g1b'), 'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id'))
        )
    )
)
INSERT INTO test_ctx (key, value)
SELECT CASE rn WHEN 1 THEN 'pc_g1b_dup1' ELSE 'pc_g1b_dup2' END, id::text
FROM ins;

-- ================================================================
-- PASSO 7 — Allocations (aciona trigger 6119 -> SPECIES_MATCH
-- automático para toda Physical Card cuja Variant tenha Species
-- resolvida igual à Species de alguma Position do Pokédex de teste).
-- ================================================================
SELECT public.allocate_physical_cards_to_collection(
    (SELECT value::uuid FROM test_ctx WHERE key = 'col_gen1'),
    ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'pc_gen1_pos1')]
);

SELECT public.allocate_physical_cards_to_collection(
    (SELECT value::uuid FROM test_ctx WHERE key = 'col_gen_both'),
    ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'pc_genboth_pos1')]
);

SELECT public.allocate_physical_cards_to_collection(
    (SELECT value::uuid FROM test_ctx WHERE key = 'col_partial'),
    ARRAY[
        (SELECT value::uuid FROM test_ctx WHERE key = 'pc_partial_pos1'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pc_partial_pos2')
    ]
);

SELECT public.allocate_physical_cards_to_collection(
    (SELECT value::uuid FROM test_ctx WHERE key = 'col_complete'),
    ARRAY[
        (SELECT value::uuid FROM test_ctx WHERE key = 'pc_complete_pos1'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pc_complete_pos2'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pc_complete_pos4'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pc_complete_pos3_override')
    ]
);

SELECT public.allocate_physical_cards_to_collection(
    (SELECT value::uuid FROM test_ctx WHERE key = 'col_outscope'),
    ARRAY[
        (SELECT value::uuid FROM test_ctx WHERE key = 'pc_outscope_pos1'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pc_outscope_pos5')
    ]
);

SELECT public.allocate_physical_cards_to_collection(
    (SELECT value::uuid FROM test_ctx WHERE key = 'col_scope_mut'),
    ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'pc_scopemut_pos1')]
);

SELECT public.allocate_physical_cards_to_collection(
    (SELECT value::uuid FROM test_ctx WHERE key = 'col_standard'),
    ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'pc_standard_1')]
);

SELECT public.allocate_physical_cards_to_collection(
    (SELECT value::uuid FROM test_ctx WHERE key = 'col_master'),
    ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'pc_master_1')]
);

-- USER_OVERRIDE explícito (Caso H): pc_complete_pos3_override não tem
-- Species resolvida -> trigger 6119 nunca cria Assignment automática
-- para ela -> chamada manual obrigatória com p_confirm_override=true,
-- alvo = pos3.
SELECT public.set_pokedex_position_assignment(
    (SELECT value::uuid FROM test_ctx WHERE key = 'pc_complete_pos3_override'),
    (SELECT value::uuid FROM test_ctx WHERE key = 'pos3'),
    TRUE
);

-- ================================================================
-- PASSO 8 — CASOS A-O
-- ================================================================

-- CASO A — FULL_REFERENCE: denominator = 5; read model retorna as 5 Positions.
DO $$
DECLARE
    r RECORD;
    v_count INT;
BEGIN
    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_full'));
    PERFORM pg_temp.log_result('A - FULL_REFERENCE total_positions = 5', r.total_positions = 5, format('got=%s', r.total_positions));
    PERFORM pg_temp.log_result('A - FULL_REFERENCE completion_policy = REFERENCE_POSITION', r.completion_policy = 'REFERENCE_POSITION', r.completion_policy);

    SELECT count(*) INTO v_count FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_full'));
    PERFORM pg_temp.log_result('A - read model retorna as 5 Positions', v_count = 5, format('got=%s', v_count));
END $$;

-- CASO B — GENERATION_FILTERED 1 Generation (total=4) e múltiplas
-- Generations (total=5, igual a FULL_REFERENCE).
DO $$
DECLARE
    r RECORD;
BEGIN
    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_gen1'));
    PERFORM pg_temp.log_result('B - GENERATION_FILTERED 1 Generation total_positions = 4', r.total_positions = 4, format('got=%s', r.total_positions));

    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_gen_both'));
    PERFORM pg_temp.log_result('B - GENERATION_FILTERED 2 Generations total_positions = 5 (igual a FULL_REFERENCE)', r.total_positions = 5, format('got=%s', r.total_positions));
END $$;

-- CASO C — zero Assignment: numerator=0, progress=0.00, is_complete=false.
DO $$
DECLARE
    r RECORD;
BEGIN
    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_zero'));
    PERFORM pg_temp.log_result('C - zero Assignment: satisfied=0', r.satisfied_positions = 0, format('got=%s', r.satisfied_positions));
    PERFORM pg_temp.log_result('C - zero Assignment: progress=0.00', r.progress_percentage = 0.00, format('got=%s', r.progress_percentage));
    PERFORM pg_temp.log_result('C - zero Assignment: is_complete=false', r.is_complete IS FALSE, NULL);
    PERFORM pg_temp.log_result('C - zero Assignment: missing=total', r.missing_positions = r.total_positions, NULL);
END $$;

-- CASO D — parcial (col_partial: 2/4).
DO $$
DECLARE
    r RECORD;
BEGIN
    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_partial'));
    PERFORM pg_temp.log_result('D - parcial: total=4', r.total_positions = 4, NULL);
    PERFORM pg_temp.log_result('D - parcial: satisfied=2', r.satisfied_positions = 2, format('got=%s', r.satisfied_positions));
    PERFORM pg_temp.log_result('D - parcial: missing=2', r.missing_positions = 2, NULL);
    PERFORM pg_temp.log_result('D - parcial: is_complete=false', r.is_complete IS FALSE, NULL);
    PERFORM pg_temp.log_result('D - parcial: progress=50.00', r.progress_percentage = 50.00, format('got=%s', r.progress_percentage));
END $$;

-- CASO E — completa (col_complete: 4/4). CASO G/H embutidos (mistura
-- SPECIES_MATCH em pos1/pos2/pos4 e USER_OVERRIDE em pos3, todas contam).
DO $$
DECLARE
    r RECORD;
    v_basis_pos3 TEXT;
BEGIN
    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_complete'));
    PERFORM pg_temp.log_result('E - completa: total=4', r.total_positions = 4, NULL);
    PERFORM pg_temp.log_result('E/G/H - completa: satisfied=4 (SPECIES_MATCH+USER_OVERRIDE somados)', r.satisfied_positions = 4, format('got=%s', r.satisfied_positions));
    PERFORM pg_temp.log_result('E - completa: missing=0', r.missing_positions = 0, NULL);
    PERFORM pg_temp.log_result('E - completa: is_complete=true', r.is_complete IS TRUE, NULL);
    PERFORM pg_temp.log_result('E - completa: progress=100.00', r.progress_percentage = 100.00, format('got=%s', r.progress_percentage));

    SELECT a.assignment_basis INTO v_basis_pos3
    FROM public.collection_pokedex_position_assignment a
    JOIN public.collection_allocation ca ON ca.id = a.collection_allocation_id
    WHERE ca.collection_id = (SELECT value::uuid FROM test_ctx WHERE key = 'col_complete')
      AND a.pokedex_position_id = (SELECT value::uuid FROM test_ctx WHERE key = 'pos3');
    PERFORM pg_temp.log_result('H - pos3 e USER_OVERRIDE de fato', v_basis_pos3 = 'USER_OVERRIDE', v_basis_pos3);
END $$;

-- CASO F — duplicatas: pc_g1b_dup1/pc_g1b_dup2 (mesma Variant, SPECIES_MATCH
-- automático para a mesma pos2) alocadas a col_full — numerator não infla.
SELECT public.allocate_physical_cards_to_collection(
    (SELECT value::uuid FROM test_ctx WHERE key = 'col_full'),
    ARRAY[
        (SELECT value::uuid FROM test_ctx WHERE key = 'pc_g1b_dup1'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pc_g1b_dup2')
    ]
);

DO $$
DECLARE
    r RECORD;
    v_assignment_count INT;
BEGIN
    SELECT count(*) INTO v_assignment_count
    FROM public.collection_pokedex_position_assignment a
    JOIN public.collection_allocation ca ON ca.id = a.collection_allocation_id
    WHERE ca.collection_id = (SELECT value::uuid FROM test_ctx WHERE key = 'col_full')
      AND a.pokedex_position_id = (SELECT value::uuid FROM test_ctx WHERE key = 'pos2');
    PERFORM pg_temp.log_result('F - 2 Assignments fisicas para pos2 (2 Physical Cards distintas)', v_assignment_count = 2, format('got=%s', v_assignment_count));

    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_full'));
    PERFORM pg_temp.log_result('F - numerator NAO infla: satisfied=1 (só pos2 satisfeita em col_full)', r.satisfied_positions = 1, format('got=%s', r.satisfied_positions));
END $$;

-- CASO I — Primary Representative: criar / TROCAR entre as duas
-- Assignments da MESMA Position (pos2/col_full, que o Caso F acima já
-- deixou com 2 Assignments válidas via pc_g1b_dup1/pc_g1b_dup2) /
-- remover. CORREÇÃO v1.2 (VALIDATION-FINAL-FIX-01, item 1): compara os
-- 5 campos do summary (não só total/satisfied) em cada um dos 3
-- estados contra o baseline, E prova fisicamente que a mutação de fato
-- ocorreu — lendo diretamente collection_pokedex_position_primary_
-- representative (colunas collection_id/pokedex_position_id/
-- collection_allocation_id, Query 6120) — para que "completion não
-- mudou" não seja confundido com "a chamada não fez nada".
DO $$
DECLARE
    r0 RECORD;
    r1 RECORD;
    r2 RECORD;
    r3 RECORD;
    v_alloc_dup1 UUID;
    v_alloc_dup2 UUID;
    v_primary_alloc UUID;
    v_primary_exists BOOLEAN;
BEGIN
    SELECT * INTO r0 FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_full'));

    SELECT id INTO v_alloc_dup1 FROM public.collection_allocation
    WHERE physical_card_id = (SELECT value::uuid FROM test_ctx WHERE key = 'pc_g1b_dup1');
    SELECT id INTO v_alloc_dup2 FROM public.collection_allocation
    WHERE physical_card_id = (SELECT value::uuid FROM test_ctx WHERE key = 'pc_g1b_dup2');

    -- Estado 1 — Criar Primary apontando para a Assignment de dup1.
    PERFORM public.set_pokedex_position_primary_representative(v_alloc_dup1);
    SELECT * INTO r1 FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_full'));
    PERFORM pg_temp.log_result('I - criar Primary Representative (dup1): total_positions inalterado',
        r1.total_positions = r0.total_positions, format('esperado=%s got=%s', r0.total_positions, r1.total_positions));
    PERFORM pg_temp.log_result('I - criar Primary Representative (dup1): satisfied_positions inalterado',
        r1.satisfied_positions = r0.satisfied_positions, format('esperado=%s got=%s', r0.satisfied_positions, r1.satisfied_positions));
    PERFORM pg_temp.log_result('I - criar Primary Representative (dup1): missing_positions inalterado',
        r1.missing_positions = r0.missing_positions, format('esperado=%s got=%s', r0.missing_positions, r1.missing_positions));
    PERFORM pg_temp.log_result('I - criar Primary Representative (dup1): progress_percentage inalterado',
        r1.progress_percentage = r0.progress_percentage, format('esperado=%s got=%s', r0.progress_percentage, r1.progress_percentage));
    PERFORM pg_temp.log_result('I - criar Primary Representative (dup1): is_complete inalterado',
        r1.is_complete = r0.is_complete, format('esperado=%s got=%s', r0.is_complete, r1.is_complete));

    -- Prova física A: a linha de collection_pokedex_position_primary_
    -- representative para (col_full, pos2) aponta EXATAMENTE para
    -- v_alloc_dup1 — nunca um PASS assumido pela ausência de erro.
    SELECT collection_allocation_id INTO v_primary_alloc
    FROM public.collection_pokedex_position_primary_representative
    WHERE collection_id = (SELECT value::uuid FROM test_ctx WHERE key = 'col_full')
      AND pokedex_position_id = (SELECT value::uuid FROM test_ctx WHERE key = 'pos2');
    PERFORM pg_temp.log_result('I.A - apos set(dup1): linha aponta fisicamente para v_alloc_dup1',
        v_primary_alloc = v_alloc_dup1, format('esperado=%s got=%s', v_alloc_dup1, v_primary_alloc));

    -- Estado 2 — Trocar Primary para a Assignment de dup2 — MESMA
    -- Position (pos2), Allocation diferente (UPSERT sobre a PK
    -- collection_id+pokedex_position_id, Query 6125/6126).
    PERFORM public.set_pokedex_position_primary_representative(v_alloc_dup2);
    SELECT * INTO r2 FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_full'));
    PERFORM pg_temp.log_result('I - trocar Primary Representative (dup1 -> dup2): total_positions inalterado',
        r2.total_positions = r0.total_positions, format('esperado=%s got=%s', r0.total_positions, r2.total_positions));
    PERFORM pg_temp.log_result('I - trocar Primary Representative (dup1 -> dup2): satisfied_positions inalterado',
        r2.satisfied_positions = r0.satisfied_positions, format('esperado=%s got=%s', r0.satisfied_positions, r2.satisfied_positions));
    PERFORM pg_temp.log_result('I - trocar Primary Representative (dup1 -> dup2): missing_positions inalterado',
        r2.missing_positions = r0.missing_positions, format('esperado=%s got=%s', r0.missing_positions, r2.missing_positions));
    PERFORM pg_temp.log_result('I - trocar Primary Representative (dup1 -> dup2): progress_percentage inalterado',
        r2.progress_percentage = r0.progress_percentage, format('esperado=%s got=%s', r0.progress_percentage, r2.progress_percentage));
    PERFORM pg_temp.log_result('I - trocar Primary Representative (dup1 -> dup2): is_complete inalterado',
        r2.is_complete = r0.is_complete, format('esperado=%s got=%s', r0.is_complete, r2.is_complete));

    -- Prova física B: a MESMA linha (mesma PK collection_id+pokedex_
    -- position_id, confirmando UPSERT em vez de segunda linha) agora
    -- aponta para v_alloc_dup2 — prova que a troca de fato ocorreu.
    SELECT collection_allocation_id INTO v_primary_alloc
    FROM public.collection_pokedex_position_primary_representative
    WHERE collection_id = (SELECT value::uuid FROM test_ctx WHERE key = 'col_full')
      AND pokedex_position_id = (SELECT value::uuid FROM test_ctx WHERE key = 'pos2');
    PERFORM pg_temp.log_result('I.B - apos set(dup2): linha aponta fisicamente para v_alloc_dup2 (trocou de fato)',
        v_primary_alloc = v_alloc_dup2, format('esperado=%s got=%s', v_alloc_dup2, v_primary_alloc));

    -- Estado 3 — Remover Primary.
    PERFORM public.clear_pokedex_position_primary_representative(
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_full'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pos2')
    );
    SELECT * INTO r3 FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_full'));
    PERFORM pg_temp.log_result('I - remover Primary Representative: total_positions inalterado',
        r3.total_positions = r0.total_positions, format('esperado=%s got=%s', r0.total_positions, r3.total_positions));
    PERFORM pg_temp.log_result('I - remover Primary Representative: satisfied_positions inalterado',
        r3.satisfied_positions = r0.satisfied_positions, format('esperado=%s got=%s', r0.satisfied_positions, r3.satisfied_positions));
    PERFORM pg_temp.log_result('I - remover Primary Representative: missing_positions inalterado',
        r3.missing_positions = r0.missing_positions, format('esperado=%s got=%s', r0.missing_positions, r3.missing_positions));
    PERFORM pg_temp.log_result('I - remover Primary Representative: progress_percentage inalterado',
        r3.progress_percentage = r0.progress_percentage, format('esperado=%s got=%s', r0.progress_percentage, r3.progress_percentage));
    PERFORM pg_temp.log_result('I - remover Primary Representative: is_complete inalterado',
        r3.is_complete = r0.is_complete, format('esperado=%s got=%s', r0.is_complete, r3.is_complete));

    -- Prova física C: nao existe mais nenhuma linha de Primary para
    -- (col_full, pos2).
    SELECT EXISTS (
        SELECT 1 FROM public.collection_pokedex_position_primary_representative
        WHERE collection_id = (SELECT value::uuid FROM test_ctx WHERE key = 'col_full')
          AND pokedex_position_id = (SELECT value::uuid FROM test_ctx WHERE key = 'pos2')
    ) INTO v_primary_exists;
    PERFORM pg_temp.log_result('I.C - apos clear: nenhuma linha de Primary Representative existe para col_full/pos2',
        NOT v_primary_exists, NULL);
END $$;

-- CASO J — Assignment fora do Scope: existe fisicamente; não conta; não
-- aparece no read model.
DO $$
DECLARE
    r RECORD;
    v_exists BOOLEAN;
    v_in_read_model BOOLEAN;
BEGIN
    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_outscope'));
    PERFORM pg_temp.log_result('J - col_outscope total=4 (pos5 nunca conta no denominator)', r.total_positions = 4, format('got=%s', r.total_positions));
    PERFORM pg_temp.log_result('J - col_outscope satisfied=1 (só pos1, pos5 nao conta)', r.satisfied_positions = 1, format('got=%s', r.satisfied_positions));

    SELECT EXISTS (
        SELECT 1 FROM public.collection_pokedex_position_assignment a
        JOIN public.collection_allocation ca ON ca.id = a.collection_allocation_id
        WHERE ca.collection_id = (SELECT value::uuid FROM test_ctx WHERE key = 'col_outscope')
          AND a.pokedex_position_id = (SELECT value::uuid FROM test_ctx WHERE key = 'pos5')
    ) INTO v_exists;
    PERFORM pg_temp.log_result('J - Assignment em pos5 existe fisicamente (preservada)', v_exists, NULL);

    SELECT EXISTS (
        SELECT 1 FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_outscope'))
        WHERE pokedex_position_id = (SELECT value::uuid FROM test_ctx WHERE key = 'pos5')
    ) INTO v_in_read_model;
    PERFORM pg_temp.log_result('J - pos5 NAO aparece em collection_pokedex_scope_positions()', NOT v_in_read_model, NULL);
END $$;

-- CASO K — Scope mutation: Assignment preservado; Position entra/sai do
-- read model/summary conforme o Scope corrente.
DO $$
DECLARE
    r RECORD;
    v_in_read_model BOOLEAN;
BEGIN
    -- Estado inicial: Scope=[gen1], pos1 satisfeita e no read model.
    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_scope_mut'));
    PERFORM pg_temp.log_result('K - estado inicial Scope=[gen1]: satisfied=1', r.satisfied_positions = 1, format('got=%s', r.satisfied_positions));

    -- Muta Scope para [gen2] — pos1 (gen1) sai do Scope corrente.
    PERFORM public.set_collection_pokedex_scope(
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_scope_mut'),
        'GENERATION_FILTERED',
        ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'gen2_id')]
    );

    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_scope_mut'));
    PERFORM pg_temp.log_result('K - Scope mutado para [gen2]: total=1 (só pos5)', r.total_positions = 1, format('got=%s', r.total_positions));
    PERFORM pg_temp.log_result('K - Scope mutado para [gen2]: satisfied=0 (pos1 saiu, pos5 sem Assignment nesta Collection)', r.satisfied_positions = 0, format('got=%s', r.satisfied_positions));

    SELECT EXISTS (
        SELECT 1 FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_scope_mut'))
        WHERE pokedex_position_id = (SELECT value::uuid FROM test_ctx WHERE key = 'pos1')
    ) INTO v_in_read_model;
    PERFORM pg_temp.log_result('K - pos1 some do read model apos mutacao para gen2', NOT v_in_read_model, NULL);

    SELECT EXISTS (
        SELECT 1 FROM public.collection_pokedex_position_assignment a
        JOIN public.collection_allocation ca ON ca.id = a.collection_allocation_id
        WHERE ca.collection_id = (SELECT value::uuid FROM test_ctx WHERE key = 'col_scope_mut')
          AND a.pokedex_position_id = (SELECT value::uuid FROM test_ctx WHERE key = 'pos1')
    ) INTO v_in_read_model;
    PERFORM pg_temp.log_result('K - Assignment de pos1 preservada fisicamente apos mutacao', v_in_read_model, NULL);

    -- Muta Scope de volta para [gen1] — pos1 reaparece contada.
    PERFORM public.set_collection_pokedex_scope(
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_scope_mut'),
        'GENERATION_FILTERED',
        ARRAY[(SELECT value::uuid FROM test_ctx WHERE key = 'gen1_id')]
    );

    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_scope_mut'));
    PERFORM pg_temp.log_result('K - Scope de volta para [gen1]: satisfied=1 (pos1 reaparece contada, sem nova Assignment)', r.satisfied_positions = 1, format('got=%s', r.satisfied_positions));
END $$;

-- CASO L — p_only_missing false/true (col_partial: 4 total, 2
-- satisfeitas -> p_only_missing=true retorna exatamente pos3+pos4).
DO $$
DECLARE
    v_count_all INT;
    v_count_missing INT;
    v_missing_are_correct BOOLEAN;
BEGIN
    SELECT count(*) INTO v_count_all
    FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_partial'), FALSE);
    PERFORM pg_temp.log_result('L - p_only_missing=false retorna as 4 Positions', v_count_all = 4, format('got=%s', v_count_all));

    SELECT count(*) INTO v_count_missing
    FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_partial'), TRUE);
    PERFORM pg_temp.log_result('L - p_only_missing=true retorna exatamente 2 Positions', v_count_missing = 2, format('got=%s', v_count_missing));

    SELECT bool_and(pokedex_position_id IN (
        (SELECT value::uuid FROM test_ctx WHERE key = 'pos3'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'pos4')
    )) INTO v_missing_are_correct
    FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_partial'), TRUE);
    PERFORM pg_temp.log_result('L - as 2 Positions faltantes sao exatamente pos3/pos4', v_missing_are_correct, NULL);
END $$;

-- Fechamento da sessão Owner A antes das checagens de segurança.
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{}', true);

-- CASO M1A — ACL real (nunca PASS constante, CORREÇÃO v1.1 item 2):
-- authenticated tem EXECUTE; anon NAO tem, nas duas funções; nenhuma
-- linha do ACL concede EXECUTE a PUBLIC (grantee vazio, verificado via
-- aclexplode) em nenhuma delas. Rodado sem impersonação —
-- has_function_privilege/aclexplode não dependem do role de sessão
-- corrente, e NUNCA invocam a função como anon (o que geraria erro de
-- permissão, não 0 linhas).
DO $$
BEGIN
    PERFORM pg_temp.log_result('M1A - authenticated tem EXECUTE em collection_pokedex_scope_positions',
        has_function_privilege('authenticated', 'public.collection_pokedex_scope_positions(uuid, boolean)', 'EXECUTE'), NULL);
    PERFORM pg_temp.log_result('M1A - anon NAO tem EXECUTE em collection_pokedex_scope_positions',
        NOT has_function_privilege('anon', 'public.collection_pokedex_scope_positions(uuid, boolean)', 'EXECUTE'), NULL);
    PERFORM pg_temp.log_result('M1A - authenticated tem EXECUTE em collection_completion_summary',
        has_function_privilege('authenticated', 'public.collection_completion_summary(uuid)', 'EXECUTE'), NULL);
    PERFORM pg_temp.log_result('M1A - anon NAO tem EXECUTE em collection_completion_summary',
        NOT has_function_privilege('anon', 'public.collection_completion_summary(uuid)', 'EXECUTE'), NULL);
    PERFORM pg_temp.log_result('M1A - nenhum GRANT a PUBLIC em collection_pokedex_scope_positions (ACL real, via aclexplode)',
        NOT EXISTS (
            SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a
            WHERE p.oid = to_regprocedure('public.collection_pokedex_scope_positions(uuid, boolean)')
              AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'
        ), NULL);
    PERFORM pg_temp.log_result('M1A - nenhum GRANT a PUBLIC em collection_completion_summary (ACL real, via aclexplode)',
        NOT EXISTS (
            SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a
            WHERE p.oid = to_regprocedure('public.collection_completion_summary(uuid)')
              AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'
        ), NULL);
END $$;

-- CASO M1B — auth.uid() NULL sob role authenticated (não anônimo,
-- apenas sem claim, CORREÇÃO v1.1 item 2): authenticated JÁ TEM
-- EXECUTE (M1A confirmou), então a chamada nunca deve gerar erro de
-- permissão — o que se testa aqui é o filtro interno
-- "(select auth.uid()) IS NOT NULL" da CTE target, nunca a ACL.
-- CORREÇÃO v1.2 (VALIDATION-FINAL-FIX-01, item 2): auth.uid() tem
-- fallback para request.jwt.claims.sub (o claim completo em JSON) além
-- de request.jwt.claim.sub (o atalho de claim único) — limpar apenas o
-- primeiro não garante auth.uid() NULL se o segundo ainda carregar um
-- sub de uma impersonação anterior. Limpeza dupla, sempre nesta ordem,
-- para tornar o NULL determinístico.
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{}', true);

DO $$
DECLARE
    v_count INT;
    r RECORD;
BEGIN
    SELECT count(*) INTO v_count FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_full'));
    PERFORM pg_temp.log_result('M1B - auth.uid() NULL: collection_pokedex_scope_positions retorna 0 linhas', v_count = 0, format('got=%s', v_count));

    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_full'));
    PERFORM pg_temp.log_result('M1B - auth.uid() NULL: collection_completion_summary retorna 0 linhas', r IS NULL, NULL);
END $$;

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{}', true);

-- CASO M2/M3 — Owner B contra Collection de Owner A; Collection
-- inexistente.
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', (SELECT value FROM test_ctx WHERE key = 'owner_b'), true);

DO $$
DECLARE
    v_count INT;
    r RECORD;
BEGIN
    SELECT count(*) INTO v_count FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_full'));
    PERFORM pg_temp.log_result('M2 - Owner B contra Collection de Owner A: 0 linhas no read model', v_count = 0, format('got=%s', v_count));

    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_full'));
    PERFORM pg_temp.log_result('M2 - Owner B contra Collection de Owner A: 0 linhas no summary', r IS NULL, NULL);

    SELECT count(*) INTO v_count FROM public.collection_pokedex_scope_positions(gen_random_uuid());
    PERFORM pg_temp.log_result('M3 - Collection inexistente: 0 linhas no read model', v_count = 0, format('got=%s', v_count));
END $$;

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{}', true);

-- CASO M4/M5/M6 — OPEN_CURATION / STANDARD_SET / MASTER_SET não vazam
-- pelo ramo REFERENCE_POSITION nem pelo novo read model — Owner A.
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', (SELECT value FROM test_ctx WHERE key = 'owner_a'), true);

DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT count(*) INTO v_count FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_open'));
    PERFORM pg_temp.log_result('M4 - OPEN_CURATION: collection_pokedex_scope_positions retorna 0 linhas', v_count = 0, format('got=%s', v_count));

    SELECT count(*) INTO v_count FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_standard'));
    PERFORM pg_temp.log_result('M5 - STANDARD_SET: collection_pokedex_scope_positions retorna 0 linhas', v_count = 0, format('got=%s', v_count));

    SELECT count(*) INTO v_count FROM public.collection_pokedex_scope_positions((SELECT value::uuid FROM test_ctx WHERE key = 'col_master'));
    PERFORM pg_temp.log_result('M6 - MASTER_SET: collection_pokedex_scope_positions retorna 0 linhas', v_count = 0, format('got=%s', v_count));
END $$;

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{}', true);

-- CASOS N/O — regressão STANDARD_SET/MASTER_SET pós-5100 (Owner A).
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', (SELECT value FROM test_ctx WHERE key = 'owner_a'), true);

DO $$
DECLARE
    r RECORD;
    v_standard_total BIGINT;
BEGIN
    -- CORREÇÃO v1.3 (VALIDATION-FINAL-FIX-02): NUNCA ler public.card
    -- diretamente aqui — já estamos sob "SET ROLE authenticated"
    -- (linha acima), e public.card é Catálogo Editorial fechado por
    -- RLS para esse role (SELECT direto sempre retorna 0 linhas, sem
    -- erro). O baseline correto já foi materializado em contexto
    -- privilegiado no PASSO 3 (test_ctx.regression_standard_total) —
    -- só lido aqui, nunca recalculado.
    SELECT value::bigint INTO v_standard_total
    FROM test_ctx WHERE key = 'regression_standard_total';

    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_standard'));
    PERFORM pg_temp.log_result('N - regressao STANDARD_SET: completion_policy inalterado', r.completion_policy = 'STANDARD_SET', r.completion_policy);
    PERFORM pg_temp.log_result('N - regressao STANDARD_SET: total_positions = count(Cards do Set)', r.total_positions = v_standard_total, format('esperado=%s got=%s', v_standard_total, r.total_positions));
    PERFORM pg_temp.log_result('N - regressao STANDARD_SET: satisfied=1 (1 Physical Card alocada)', r.satisfied_positions = 1, format('got=%s', r.satisfied_positions));

    SELECT * INTO r FROM public.collection_completion_summary((SELECT value::uuid FROM test_ctx WHERE key = 'col_master'));
    PERFORM pg_temp.log_result('O - regressao MASTER_SET: completion_policy = MASTER_SET', r.completion_policy = 'MASTER_SET', r.completion_policy);
    PERFORM pg_temp.log_result('O - regressao MASTER_SET: total_positions = 2 (Scope adotado)', r.total_positions = 2, format('got=%s', r.total_positions));
    PERFORM pg_temp.log_result('O - regressao MASTER_SET: satisfied=1 (1 Variant do Scope com Physical Card exata)', r.satisfied_positions = 1, format('got=%s', r.satisfied_positions));
END $$;

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{}', true);

-- ================================================================
-- PASSO 9 — SELECT final consolidado
-- ================================================================
SELECT
    case_label,
    passed,
    detail
FROM test_results
ORDER BY id;

SELECT
    count(*) FILTER (WHERE passed) AS total_passed,
    count(*) FILTER (WHERE NOT passed) AS total_failed,
    count(*) AS total_cases
FROM test_results;

-- ================================================================
-- PASSO 10 — ROLLBACK incondicional (zero resíduo)
-- ================================================================
ROLLBACK;

-- ================================================================
-- PASSO 11 (fora de transação) — prova de zero resíduo pós-ROLLBACK
-- ================================================================
SELECT count(*) AS collections_com_prefixo_depois
FROM public.collection
WHERE name LIKE 'VAL-TEST-FATIA-E-%';

SELECT count(*) AS pokedex_teste_depois
FROM public.pokedex
WHERE code = 'VAL_TEST_FATIA_E_POKEDEX';

SELECT count(*) AS assignments_com_prefixo_depois
FROM public.collection_pokedex_position_assignment a
JOIN public.collection_allocation ca ON ca.id = a.collection_allocation_id
JOIN public.collection c ON c.id = ca.collection_id
WHERE c.name LIKE 'VAL-TEST-FATIA-E-%';
