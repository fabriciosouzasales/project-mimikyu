/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5809 - Performance Checks Collections Physical Increment 02D (PROPOSTA)
Versão......: 2.2 (v2.0 em COLLECTIONS-PHYSICAL-INCREMENT-02D-
               STAGING-REVISION-01 — v1.0 continha SQL não executável e
               uma metodologia de medição incorreta para os constraint
               triggers diferidos; v2.1 em -STAGING-FINAL-FIX-01 —
               Workload 3 media CS1 -> CS1, ver item 7 abaixo; v2.2 em
               -IMPLEMENTATION-01 — execução real revelou que a
               ferramenta de execução de SQL usada nesta rodada só
               retorna o resultado do último SELECT (statement que
               produz linhas) do script, não mensagens RAISE NOTICE nem
               a saída de EXPLAIN solto — os 4 Workloads mediam
               corretamente, mas os resultados (RAISE NOTICE) e o plano
               do Workload 4a (EXPLAIN solto) nunca chegavam a ser
               observados. Puramente instrumentação de captura de
               resultado, nenhuma mudança de metodologia de medição:
               RAISE NOTICE substituído por INSERT numa TEMP TABLE
               perf_results (mesmo padrão já usado em 5808 com
               test_results/log_result), e o EXPLAIN do Workload 4a
               capturado linha a linha via FOR ... IN EXECUTE dentro de
               um bloco DO, também logado em perf_results. Ver item 9
               abaixo)
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02D-
               MODELING-01/-REVISION-01/-FINAL-01/-STAGING-REVISION-01)

Descrição...:
Plano de performance do Incremento 02D. Só será executado de fato numa
futura rodada -IMPLEMENTATION-01, sobre um Supabase já com 5049-5066
aplicadas — mesmo padrão de staging de 5807 (02C): volume sintético,
ROLLBACK ao final, zero resíduo.

Mudanças estruturais desta reescrita (v2.0), todas de mecânica SQL ou
de metodologia de medição — NENHUMA decisão conceitual foi reaberta:

1. Removido \echo — é meta-comando do cliente psql, não SQL executável
   por apply_migration/execute_sql no Supabase.
2. create_storage_container() corrigido para a assinatura real de 1
   argumento (p_name text). Confirmado em database/schema/5022.
3. add_physical_cards() removido dos fixtures — mesmo motivo e mesma
   correção do 5808: Physical Cards inseridas diretamente em
   public.physical_card, sem depender do shape do payload jsonb.
4. Todo padrão `array_agg(x) ... LIMIT N` corrigido para
   `array_agg(x) FROM (SELECT ... LIMIT N) q` — mesma correção do 5808.
5. WORKLOAD 1 corrigido: a v1.0 chamava `SET CONSTRAINTS ... IMMEDIATE`
   dentro do loop sem nunca voltar para DEFERRED — a partir da segunda
   iteração, os constraints permaneciam IMMEDIATE, fazendo cada criação
   seguinte falhar no estado intermediário (INSERT de collection antes
   de collection_reference existir). Corrigido com alternância explícita
   DEFERRED (antes de cada trio de INSERTs) -> IMMEDIATE (força e mede o
   flush) -> DEFERRED de novo, a cada iteração.
6. WORKLOAD 2 redesenhado inteiramente: a v1.0 tratava "fim da chamada
   de RPC" como equivalente a "COMMIT", o que é falso dentro de uma
   única transação BEGIN...ROLLBACK — os constraint triggers diferidos
   das N chamadas ficam todos pendentes, não avaliados, até o ROLLBACK
   final (que nunca os executa). A v2.0 mede em duas fases explícitas e
   rotuladas: Fase A (custo de criação, sem flush) e Fase B (custo do
   flush forçado via SET CONSTRAINTS IMMEDIATE de todas as pendências
   de uma vez) — com nota explícita de que a Fase B mede um teto
   superior de stress (N x 3 checagens de uma vez), não o custo real de
   COMMIT isolado por chamada que só ocorreria em N transações
   separadas (fora do escopo de um script reversível único).
7. WORKLOAD 3 corrigido (-STAGING-FINAL-FIX-01): a v2.0 chamava
   set_collection_card_set_reference(rec.id, v_cs) usando o MESMO
   card_set_id já usado na criação (Workload 2) — uma troca CS1 -> CS1,
   não uma troca real, que nunca exercitava de fato o ramo de checagem
   de lock em 5055 (`NEW.card_set_id IS DISTINCT FROM OLD.card_set_id`
   era sempre falso). Corrigido resolvendo um segundo Card Set real
   (`card_set_2_id`) no mesmo Game, com abort explícito se o Game
   escolhido não tiver >= 2 Card Sets.
8. WORKLOAD 4a corrigido (-STAGING-FINAL-FIX-01): a v2.0 rodava uma
   consulta solta (`ca.card_set_id = ...` sem filtro por `pc.id`), sem
   nenhuma relação com o lote real que 4b aloca — não tinha o mesmo
   shape de 5063/5064 (que sempre filtram por um lote específico de
   `physical_card.id`). Corrigido (opção A) unificando os fixtures de
   4a/4b: agora ambos usam o mesmo lote real de até 100 Physical Cards,
   e 4a mede o shape exato (filtro por lote + card_set_id) sobre esse
   lote antes de 4b executar a RPC completa sobre ele.
9. (-IMPLEMENTATION-01) Captura de resultado corrigida: RAISE NOTICE
   (Workloads 1-3 e 4b) e o EXPLAIN solto (Workload 4a) nunca chegavam
   a ser observados pela ferramenta de execução real usada nesta
   rodada, que só retorna o último SELECT do script. Substituído por
   uma TEMP TABLE perf_results (workload, detail) — mesmo padrão já
   usado em 5808 (test_results/log_result) — com um SELECT final sobre
   ela logo antes do ROLLBACK. O EXPLAIN do Workload 4a passa a ser
   capturado linha a linha via `FOR v_line IN EXECUTE '...' LOOP`
   dentro de um bloco DO, concatenado e logado como mais uma linha de
   perf_results. Pura instrumentação de captura — nenhuma mudança na
   metodologia de medição em si (mesmos pontos de clock_timestamp(),
   mesmo EXPLAIN (ANALYZE, BUFFERS), mesmo volume/fixtures).

Workloads cobertos (os 4 pontos novos introduzidos pelo 02D que não
existiam em nenhum incremento anterior):

  1. Overhead dos CONSTRAINT TRIGGERs DEFERRABLE INITIALLY DEFERRED
     (5057/5058/5059) — custo de criação vs. custo de flush, separados.
  2. Custo da RPC de criação atômica
     (create_reference_based_card_set_collection, Query 5065) — Fase A
     (criação) e Fase B (flush) separadas, mesma lógica do Workload 1.
  3. Custo da RPC de troca de Card Set antes do lock
     (set_collection_card_set_reference, Query 5066) — triggers
     envolvidos (5055) são imediatos, não diferidos; sem necessidade de
     separar fases aqui.
  4. Custo do JOIN de elegibilidade de Reference introduzido em
     allocate_physical_cards_to_collection() (Query 5064) e no trigger
     estrutural equivalente (Query 5063) — via EXPLAIN (ANALYZE,
     BUFFERS), já que aqui o custo é de shape de query, não de timing
     de trigger diferido.

Fora de escopo aqui (já cobertos e aprovados em planos de performance
anteriores, sem mudança de shape nesta rodada): custo de
add_physical_cards(), custo de archive_collection()/
reactivate_collection(), RLS de physical_card/inventory.

Metodologia: todo o volume sintético é gerado e revertido dentro de
uma única transação (BEGIN...ROLLBACK) — nenhuma linha sobrevive,
mesma garantia ACID incondicional já usada em 5807. Catálogo
(Game/Card Set/Card/Card Variant/Language) é sempre reaproveitado do
catálogo real já carregado — nenhum dado de catálogo sintético.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

BEGIN;

-- ============================================================
-- FIXTURES
-- ============================================================

CREATE TEMP TABLE perf_results (
    seq      SERIAL PRIMARY KEY,
    workload TEXT NOT NULL,
    detail   TEXT
);

CREATE OR REPLACE FUNCTION pg_temp.log_perf(p_workload TEXT, p_detail TEXT)
RETURNS VOID LANGUAGE sql AS $$
    INSERT INTO perf_results (workload, detail) VALUES (p_workload, p_detail);
$$;

CREATE TEMP TABLE perf_ctx AS
SELECT inv.owner_user_id AS owner_id, inv.id AS inventory_id
FROM public.inventory inv
LIMIT 1;

DO $$
BEGIN
    IF (SELECT count(*) FROM perf_ctx) = 0 THEN
        RAISE EXCEPTION 'nenhum Inventory real encontrado — 5809 exige ao menos 1 Owner com Inventory já existente';
    END IF;
END;
$$;

-- Game elegível para o Workload 3 (troca real de Card Set): precisa
-- ter >= 2 Card Sets reais, senão não existe um "CS2" distinto para
-- medir a troca CS1 -> CS2. Restringe a escolha do maior Card Set
-- (abaixo) a Games que já satisfazem essa condição — corrige a v2.0,
-- que podia escolher o maior Card Set do catálogo inteiro e só depois
-- descobrir que o Game dele tinha um único Card Set.
CREATE TEMP TABLE perf_eligible_games AS
SELECT ex.game_id
FROM public.card_set cs
JOIN public.expansion ex ON ex.id = cs.expansion_id
GROUP BY ex.game_id
HAVING count(DISTINCT cs.id) >= 2;

DO $$
BEGIN
    IF (SELECT count(*) FROM perf_eligible_games) = 0 THEN
        RAISE EXCEPTION 'nenhum Game com >= 2 Card Sets reais encontrado — 5809 Workload 3 exige um Game com pelo menos 2 Card Sets para medir uma troca real (CS1 -> CS2)';
    END IF;
END;
$$;

-- Maior Card Set real disponível, restrito aos Games elegíveis acima
-- (maximiza o custo do JOIN de elegibilidade no Workload 4 — pior caso
-- realista, não hipotético — e já garante um CS2 no mesmo Game).
CREATE TEMP TABLE perf_cardset AS
SELECT cs.id AS card_set_id, ex.game_id AS game_id, count(ca.id) AS card_count
FROM public.card_set cs
JOIN public.expansion ex ON ex.id = cs.expansion_id
JOIN public.card ca ON ca.card_set_id = cs.id
WHERE ex.game_id IN (SELECT game_id FROM perf_eligible_games)
GROUP BY cs.id, ex.game_id
ORDER BY count(ca.id) DESC
LIMIT 1;

DO $$
BEGIN
    IF (SELECT count(*) FROM perf_cardset) = 0 THEN
        RAISE EXCEPTION 'nenhum Card Set com Cards encontrado dentro de um Game elegível (>= 2 Card Sets) — catálogo insuficiente para 5809';
    END IF;
END;
$$;

-- Segundo Card Set (CS2), mesmo Game de perf_cardset.card_set_id (CS1),
-- distinto dele — usado pelo Workload 3 para medir uma troca real.
ALTER TABLE perf_cardset ADD COLUMN card_set_2_id UUID;
UPDATE perf_cardset SET card_set_2_id = (
    SELECT cs.id FROM public.card_set cs
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    WHERE ex.game_id = (SELECT game_id FROM perf_cardset)
      AND cs.id <> (SELECT card_set_id FROM perf_cardset)
    ORDER BY cs.id LIMIT 1
);

DO $$
BEGIN
    IF (SELECT card_set_2_id FROM perf_cardset) IS NULL THEN
        RAISE EXCEPTION 'falha ao resolver um segundo Card Set no mesmo Game de card_set_id — inconsistente com o filtro de Games elegíveis (>= 2 Card Sets) aplicado acima';
    END IF;
END;
$$;

-- Storage Container de Owner A — assinatura real: create_storage_container(p_name text).
DO $$
DECLARE
    v_owner UUID := (SELECT owner_id FROM perf_ctx);
    v_storage_id UUID;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);
    SELECT id INTO v_storage_id FROM public.create_storage_container('PERF-02D-Storage');
    RESET ROLE;
    CREATE TEMP TABLE perf_storage AS SELECT v_storage_id AS storage_id;
END;
$$;

SELECT
    (SELECT card_count FROM perf_cardset) AS maior_card_set_encontrado,
    (SELECT game_id FROM perf_cardset)    AS game_id;

-- ============================================================
-- WORKLOAD 1 — Overhead dos constraint triggers diferidos
-- (5057/5058/5059) em criação sequencial de N Collections
-- REFERENCE_BASED via INSERT direto — custo de criação e custo de
-- flush medidos separadamente, com DEFERRED restaurado explicitamente
-- a cada iteração.
-- ============================================================
DO $$
DECLARE
    v_owner    UUID := (SELECT owner_id FROM perf_ctx);
    v_game     UUID := (SELECT game_id FROM perf_cardset);
    v_cs       UUID := (SELECT card_set_id FROM perf_cardset);
    v_storage  UUID := (SELECT storage_id FROM perf_storage);
    v_n        INT := 200;
    v_coll_id  UUID;
    v_ref_id   UUID;
    v_t0       TIMESTAMPTZ;
    v_t1       TIMESTAMPTZ;
    v_t2       TIMESTAMPTZ;
    v_create_total INTERVAL := interval '0';
    v_flush_total  INTERVAL := interval '0';
    i          INT;
BEGIN
    FOR i IN 1..v_n LOOP
        SET CONSTRAINTS trg_collection_reference_presence DEFERRED;
        SET CONSTRAINTS trg_collection_reference_consistency DEFERRED;
        SET CONSTRAINTS trg_collection_card_set_reference_consistency DEFERRED;

        v_t0 := clock_timestamp();

        INSERT INTO public.collection (owner_user_id, game_id, name, default_storage_container_id, mode)
        VALUES (v_owner, v_game, 'PERF-02D-Bulk-' || i, v_storage, 'REFERENCE_BASED')
        RETURNING id INTO v_coll_id;

        INSERT INTO public.collection_reference (collection_id, reference_kind)
        VALUES (v_coll_id, 'CARD_SET')
        RETURNING id INTO v_ref_id;

        INSERT INTO public.collection_card_set_reference (collection_reference_id, card_set_id)
        VALUES (v_ref_id, v_cs);

        v_t1 := clock_timestamp();

        SET CONSTRAINTS trg_collection_reference_presence IMMEDIATE;
        SET CONSTRAINTS trg_collection_reference_consistency IMMEDIATE;
        SET CONSTRAINTS trg_collection_card_set_reference_consistency IMMEDIATE;

        v_t2 := clock_timestamp();

        v_create_total := v_create_total + (v_t1 - v_t0);
        v_flush_total  := v_flush_total  + (v_t2 - v_t1);
    END LOOP;

    -- deixa DEFERRED de novo — não vazar estado para os workloads seguintes
    SET CONSTRAINTS trg_collection_reference_presence DEFERRED;
    SET CONSTRAINTS trg_collection_reference_consistency DEFERRED;
    SET CONSTRAINTS trg_collection_card_set_reference_consistency DEFERRED;

    PERFORM pg_temp.log_perf('WORKLOAD 1', format(
        '%s criações REFERENCE_BASED completas (3 INSERTs/criação): custo de criação = %s (média %s / criação); custo de flush diferido (SET CONSTRAINTS IMMEDIATE, por criação) = %s (média %s / criação)',
        v_n, v_create_total, v_create_total / v_n, v_flush_total, v_flush_total / v_n));
END;
$$;

-- ============================================================
-- WORKLOAD 2 — Custo da RPC de criação atômica
-- (create_reference_based_card_set_collection, 5065), N chamadas
-- reais via RPC. Fase A (criação, sem flush) e Fase B (flush forçado
-- de todas as N pendências de uma vez) medidas separadamente — ver
-- nota 6 do cabeçalho sobre por que "fim da função" != "COMMIT" dentro
-- desta transação única.
-- ============================================================
DO $$
DECLARE
    v_owner    UUID := (SELECT owner_id FROM perf_ctx);
    v_game     UUID := (SELECT game_id FROM perf_cardset);
    v_cs       UUID := (SELECT card_set_id FROM perf_cardset);
    v_storage  UUID := (SELECT storage_id FROM perf_storage);
    v_n        INT := 200;
    v_create_start TIMESTAMPTZ;
    v_create_end   TIMESTAMPTZ;
    v_flush_start  TIMESTAMPTZ;
    v_flush_end    TIMESTAMPTZ;
    i          INT;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);

    v_create_start := clock_timestamp();

    FOR i IN 1..v_n LOOP
        PERFORM public.create_reference_based_card_set_collection(
            v_game, 'PERF-02D-RPC-' || i, NULL, v_storage, v_cs
        );
    END LOOP;

    v_create_end := clock_timestamp();

    RESET ROLE;

    -- As N chamadas acima já retornaram, mas os 3 constraint triggers
    -- diferidos disparados por cada uma continuam pendentes nesta
    -- transação (nenhum COMMIT real aconteceu ainda). Forçar e medir o
    -- flush de todas de uma vez:
    v_flush_start := clock_timestamp();
    SET CONSTRAINTS trg_collection_reference_presence IMMEDIATE;
    SET CONSTRAINTS trg_collection_reference_consistency IMMEDIATE;
    SET CONSTRAINTS trg_collection_card_set_reference_consistency IMMEDIATE;
    v_flush_end := clock_timestamp();

    SET CONSTRAINTS trg_collection_reference_presence DEFERRED;
    SET CONSTRAINTS trg_collection_reference_consistency DEFERRED;
    SET CONSTRAINTS trg_collection_card_set_reference_consistency DEFERRED;

    PERFORM pg_temp.log_perf('WORKLOAD 2', format(
        '%s chamadas create_reference_based_card_set_collection(): Fase A (criação, sem flush) = %s (média %s / chamada); Fase B (flush de TODAS as %s pendências de uma vez) = %s (média %s / chamada) — NOTA: em produção cada chamada é sua própria transação e flusha 1 conjunto de checagens no seu próprio COMMIT; a Fase B aqui mede um teto superior de stress (N conjuntos de uma vez), não o custo isolado real de N COMMITs separados',
        v_n, (v_create_end - v_create_start), (v_create_end - v_create_start) / v_n,
        v_n, (v_flush_end - v_flush_start), (v_flush_end - v_flush_start) / v_n));
END;
$$;

-- ============================================================
-- WORKLOAD 3 — Custo da RPC de troca de Card Set antes do lock
-- (set_collection_card_set_reference, 5066), N chamadas sobre as
-- Collections criadas no Workload 2 (ainda sem Allocation, portanto
-- sem lock). Mede uma troca REAL: as Collections do Workload 2 nascem
-- com card_set_id = CS1 (perf_cardset.card_set_id); aqui trocamos para
-- CS2 (perf_cardset.card_set_2_id) — distinto, mesmo Game. Com CS1 ->
-- CS1 (bug da v2.0), NEW.card_set_id IS DISTINCT FROM OLD.card_set_id
-- era sempre falso, então o ramo de checagem de lock em 5055 nunca
-- era exercitado de fato. Trigger envolvido (5055) é imediato, não
-- diferido — sem necessidade de separar Fase A/B aqui.
-- ============================================================
DO $$
DECLARE
    v_owner    UUID := (SELECT owner_id FROM perf_ctx);
    v_cs2      UUID := (SELECT card_set_2_id FROM perf_cardset);
    v_start    TIMESTAMPTZ;
    v_end      TIMESTAMPTZ;
    v_count    INT := 0;
    rec        RECORD;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);

    v_start := clock_timestamp();

    FOR rec IN
        SELECT id FROM public.collection WHERE name LIKE 'PERF-02D-RPC-%'
    LOOP
        PERFORM public.set_collection_card_set_reference(rec.id, v_cs2);
        v_count := v_count + 1;
    END LOOP;

    v_end := clock_timestamp();
    RESET ROLE;

    PERFORM pg_temp.log_perf('WORKLOAD 3', format(
        '%s chamadas set_collection_card_set_reference() medindo troca REAL CS1 -> CS2 (Card Sets distintos, mesmo Game): %s (média %s / chamada)',
        v_count, (v_end - v_start), (v_end - v_start) / GREATEST(v_count, 1)));
END;
$$;

-- ============================================================
-- WORKLOAD 4 — Custo do JOIN de elegibilidade de Reference
-- (Query 5063, trigger estrutural; Query 5064, pré-checagem da RPC)
-- contra o maior Card Set real do catálogo — pior caso de largura de
-- JOIN, não hipotético.
-- ============================================================

-- Fixtures compartilhadas entre 4a e 4b: um lote real de até 100
-- Physical Cards elegíveis do maior Card Set do catálogo (CS1), e uma
-- Collection REFERENCE_BASED apontando para esse mesmo Card Set. As
-- duas sub-medições usam o MESMO lote — corrige a v2.0, em que 4a era
-- uma consulta solta (`ca.card_set_id = ...` sem nenhum filtro por
-- `pc.id`), sem relação real com o batch que 4b de fato aloca; agora
-- 4a mede exatamente o shape usado por 5063/5064 (filtro por lote de
-- physical_card.id + card_set_id) sobre o batch real de 4b. Physical
-- Cards inseridas diretamente (mesma correção do 5808 — não via
-- add_physical_cards(), cujo contrato real é jsonb).
DO $$
DECLARE
    v_owner       UUID := (SELECT owner_id FROM perf_ctx);
    v_inv         UUID := (SELECT inventory_id FROM perf_ctx);
    v_game        UUID := (SELECT game_id FROM perf_cardset);
    v_cs1         UUID := (SELECT card_set_id FROM perf_cardset);
    v_storage     UUID := (SELECT storage_id FROM perf_storage);
    v_lang        UUID;
    v_coll_id     UUID;
    v_variant_ids UUID[];
    v_pc_id       UUID;
    v_variant_id  UUID;
BEGIN
    SELECT id INTO v_lang FROM public.language LIMIT 1;
    IF v_lang IS NULL THEN
        RAISE EXCEPTION 'nenhum Language real encontrado — Workload 4 exige catálogo mínimo já carregado';
    END IF;

    SELECT array_agg(x.id) INTO v_variant_ids
    FROM (
        SELECT cv.id
        FROM public.card_variant cv
        JOIN public.card ca ON ca.id = cv.card_id
        WHERE ca.card_set_id = v_cs1
        LIMIT 100
    ) x;

    IF v_variant_ids IS NULL OR array_length(v_variant_ids, 1) < 1 THEN
        RAISE EXCEPTION 'maior Card Set do catálogo não tem Card Variants suficientes para o Workload 4';
    END IF;

    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);

    SELECT id INTO v_coll_id FROM public.create_reference_based_card_set_collection(
        v_game, 'PERF-02D-Alloc-4', NULL, v_storage, v_cs1
    );

    RESET ROLE;

    CREATE TEMP TABLE perf_workload4_pc (id UUID);

    FOREACH v_variant_id IN ARRAY v_variant_ids LOOP
        INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
        VALUES (v_variant_id, v_lang, v_inv)
        RETURNING id INTO v_pc_id;
        INSERT INTO perf_workload4_pc (id) VALUES (v_pc_id);
    END LOOP;

    CREATE TEMP TABLE perf_workload4_coll AS SELECT v_coll_id AS collection_id;
END;
$$;

-- 4a. Custo isolado da subconsulta de elegibilidade sobre o MESMO
--     lote real que 4b aloca abaixo — shape equivalente ao usado em
--     5063/5064 (filtro por lote de physical_card.id + card_set_id).
--     Usa IN (subquery contra TEMP TABLE) em vez de ANY(array): mesmo
--     shape de plano para o otimizador, sem precisar montar um literal
--     de array UUID gigante inline num EXPLAIN de nível superior.
DO $$
DECLARE
    v_line TEXT;
    v_plan TEXT := '';
BEGIN
    FOR v_line IN
        EXECUTE '
            EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
            SELECT count(*)
            FROM public.physical_card pc
            JOIN public.card_variant cv ON cv.id = pc.card_variant_id
            JOIN public.card ca ON ca.id = cv.card_id
            WHERE pc.id IN (SELECT id FROM perf_workload4_pc)
              AND ca.card_set_id = (SELECT card_set_id FROM perf_cardset)
        '
    LOOP
        v_plan := v_plan || v_line || E'\n';
    END LOOP;

    PERFORM pg_temp.log_perf('WORKLOAD 4a', v_plan);
END;
$$;

-- 4b. allocate_physical_cards_to_collection() de ponta a ponta, sobre
--     o mesmo lote e a mesma Collection REFERENCE_BASED criados acima
--     — mede o custo real end-to-end (Owner/Game check + elegibilidade
--     + already-allocated + INSERT + trigger estrutural 5063).
DO $$
DECLARE
    v_owner    UUID := (SELECT owner_id FROM perf_ctx);
    v_coll_id  UUID := (SELECT collection_id FROM perf_workload4_coll);
    v_pc_ids   UUID[];
    v_start    TIMESTAMPTZ;
    v_end      TIMESTAMPTZ;
BEGIN
    SELECT array_agg(id) INTO v_pc_ids FROM perf_workload4_pc;

    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner::text, true);

    v_start := clock_timestamp();
    PERFORM public.allocate_physical_cards_to_collection(v_coll_id, v_pc_ids);
    v_end := clock_timestamp();

    RESET ROLE;

    PERFORM pg_temp.log_perf('WORKLOAD 4b', format(
        'allocate_physical_cards_to_collection() com %s cartas elegíveis (mesmo lote medido isoladamente em 4a; Card Set com %s Cards no total): %s',
        array_length(v_pc_ids, 1), (SELECT card_count FROM perf_cardset), (v_end - v_start)));
END;
$$;

-- ============================================================
-- Verificação de resíduo (ainda dentro da transação — prova
-- primária) antes do ROLLBACK. Logada em perf_results (mesmo motivo
-- do item 9 do cabeçalho: só o último SELECT do script é observável).
-- ============================================================
DO $$
DECLARE
    v_coll_residue INT;
    v_ref_residue  INT;
BEGIN
    SELECT count(*) INTO v_coll_residue FROM public.collection WHERE name LIKE 'PERF-02D-%';
    SELECT count(*) INTO v_ref_residue
    FROM public.collection_reference cr
    JOIN public.collection col ON col.id = cr.collection_id
    WHERE col.name LIKE 'PERF-02D-%';

    PERFORM pg_temp.log_perf('RESIDUE-PRE-ROLLBACK', format(
        'collections_sinteticas=%s references_sinteticas=%s (esperado > 0 aqui — ainda dentro da transação, antes do ROLLBACK; prova de zero resíduo real é a checagem pós-ROLLBACK, em chamada separada)',
        v_coll_residue, v_ref_residue));
END;
$$;

SELECT workload, detail FROM perf_results ORDER BY seq;

ROLLBACK;

-- Prova adicional pós-ROLLBACK (executar em chamada separada, depois
-- deste script, mesma metodologia de 5807):
--
--   SELECT count(*) FROM public.collection WHERE name LIKE 'PERF-02D-%';
--   SELECT count(*) FROM public.storage_container WHERE name = 'PERF-02D-Storage';
--
-- Esperado: 0 em ambas.
