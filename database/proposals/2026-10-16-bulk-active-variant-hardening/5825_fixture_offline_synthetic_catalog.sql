/*
================================================================
Query 5825 — F-SYN: catálogo sintético para a validação OFFLINE de 5152
================================================================
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO. Uso EXCLUSIVO no ambiente
              PostgreSQL 17 isolado montado pelo manifesto
              COLLECTION-BULK-OFFLINE-MANIFEST-01 (151 arquivos).
              NUNCA executar no LIVE nem em banco com catálogo real.
Frente......: COLLECTION-BULK-OFFLINE-FIXTURE-01
Pré-req.....: manifesto 001–151 aplicado, incluindo as seeds 800
              (game), 830 (rarity), 831 (card_category), 850
              (card_variant_type), 890 (language) e a migration 2268
              (card_variant.is_active). expansion, card_set, card e
              card_variant precisam estar VAZIAS.
Executor....: postgres (dono das tabelas; RLS habilitada sem FORCE).
Ordem.......: depois do manifesto (151) e ANTES dos 2 usuários
              sintéticos, da calibração 5822/5823, de 5152 e de 5824.

================================================================
CONTEÚDO (somente dados sintéticos; nada vem do LIVE)
================================================================
  expansion ....... 1   ZZSYN_BULK        (Game POKEMON)
  card_set ........ 2   ZZSYN-A, ZZSYN-B  (REGULAR, 500/500 cada)
  card ............ 1000 (500 por set; collector_number SYN0001..SYN0500)
  card_variant .... 1005
      1000 STANDARD, is_default = TRUE,  is_active = TRUE (1 por card)
         5 HOLO,     is_default = FALSE, is_active = TRUE
           (cards ZZSYN-A SYN0001..SYN0005, variant_order = 2)

  rarity / category / variant type: SEMPRE os registros das seeds
  canônicas do Game POKEMON (rarity COMMON, category POKEMON, variant
  types STANDARD e HOLO). Nenhuma linha é criada nessas tabelas.

================================================================
DETERMINISMO
================================================================
Todo id é derivado de md5('mmkyu-fsyn:<entidade>:<chave natural>')
convertido para uuid. A mesma instalação produz sempre os mesmos ids
e, portanto, a mesma ordenação por id — que é o critério de seleção
de 5822, 5823 e 5824. Nenhum valor depende de random() ou de relógio
(created_at/updated_at usam o DEFAULT da tabela e não participam de
nenhum seletor).

================================================================
IDEMPOTÊNCIA E ATOMICIDADE
================================================================
Fail-closed: o bloco PRE aborta se o catálogo de cartas não estiver
vazio. Uma segunda execução, portanto, falha sem escrever nada — não
há duplicação nem "merge" silencioso. Tudo roda em uma transação
única; o bloco POST verifica o resultado e, se qualquer invariante
falhar, levanta exceção e a transação inteira é revertida.
================================================================
*/

BEGIN;

-- ================================================================
-- PRE — pré-condições (fail-closed)
-- ================================================================
DO $pre$
DECLARE
    v_game UUID;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';
    IF v_game IS NULL THEN
        RAISE EXCEPTION 'F-SYN PRE: Game POKEMON ausente (seed 800 não aplicada)';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.rarity WHERE game_id = v_game AND code = 'COMMON') THEN
        RAISE EXCEPTION 'F-SYN PRE: rarity COMMON do Game POKEMON ausente (seed 830)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.card_category WHERE game_id = v_game AND code = 'POKEMON') THEN
        RAISE EXCEPTION 'F-SYN PRE: card_category POKEMON do Game POKEMON ausente (seed 831)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.card_variant_type WHERE game_id = v_game AND code = 'STANDARD') THEN
        RAISE EXCEPTION 'F-SYN PRE: card_variant_type STANDARD do Game POKEMON ausente (seed 850)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.card_variant_type WHERE game_id = v_game AND code = 'HOLO') THEN
        RAISE EXCEPTION 'F-SYN PRE: card_variant_type HOLO do Game POKEMON ausente (seed 850)';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.language) THEN
        RAISE EXCEPTION 'F-SYN PRE: nenhuma language (seed 890)';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute
                    WHERE attrelid = 'public.card_variant'::regclass
                      AND attname = 'is_active' AND NOT attisdropped) THEN
        RAISE EXCEPTION 'F-SYN PRE: card_variant.is_active ausente (2268 não aplicada)';
    END IF;

    IF EXISTS (SELECT 1 FROM public.expansion)
       OR EXISTS (SELECT 1 FROM public.card_set)
       OR EXISTS (SELECT 1 FROM public.card)
       OR EXISTS (SELECT 1 FROM public.card_variant) THEN
        RAISE EXCEPTION 'F-SYN PRE: catálogo de cartas não está vazio — a fixture só roda em instalação nova';
    END IF;
END
$pre$;

-- ================================================================
-- 1. Expansion (1)
-- ================================================================
INSERT INTO public.expansion (id, game_id, code, name, release_order)
SELECT md5('mmkyu-fsyn:expansion:ZZSYN_BULK')::uuid,
       g.id,
       'ZZSYN_BULK',
       'F-SYN Bulk Offline Expansion',
       1
  FROM public.game g
 WHERE g.code = 'POKEMON';

-- ================================================================
-- 2. Card Sets (2) — mesmo Game, mesma Expansion
-- ================================================================
INSERT INTO public.card_set (id, expansion_id, code, name, set_type,
                             release_order, base_set_size, total_set_size)
SELECT md5('mmkyu-fsyn:card_set:' || s.code)::uuid,
       md5('mmkyu-fsyn:expansion:ZZSYN_BULK')::uuid,
       s.code,
       s.name,
       'REGULAR',
       s.ord,
       500,
       500
  FROM (VALUES ('ZZSYN-A', 'F-SYN Set A', 1),
               ('ZZSYN-B', 'F-SYN Set B', 2)) AS s(code, name, ord);

-- ================================================================
-- 3. Cards (1000 = 2 × 500)
-- ================================================================
INSERT INTO public.card (id, card_set_id, rarity_id, category_id,
                         collector_number, collector_total, collector_order, name)
SELECT md5('mmkyu-fsyn:card:' || s.code || ':' || n)::uuid,
       md5('mmkyu-fsyn:card_set:' || s.code)::uuid,
       (SELECT r.id FROM public.rarity r
          JOIN public.game g ON g.id = r.game_id
         WHERE g.code = 'POKEMON' AND r.code = 'COMMON'),
       (SELECT c.id FROM public.card_category c
          JOIN public.game g ON g.id = c.game_id
         WHERE g.code = 'POKEMON' AND c.code = 'POKEMON'),
       'SYN' || lpad(n::text, 4, '0'),
       500,
       n,
       'F-SYN ' || s.code || ' #' || lpad(n::text, 4, '0')
  FROM (VALUES ('ZZSYN-A'), ('ZZSYN-B')) AS s(code)
 CROSS JOIN generate_series(1, 500) AS n;

-- ================================================================
-- 4a. Variante padrão: exatamente 1 STANDARD por card (1000)
-- ================================================================
INSERT INTO public.card_variant (id, card_id, variant_type_id,
                                 variant_order, is_default, is_active)
SELECT md5('mmkyu-fsyn:card_variant:' || s.code || ':' || n || ':STANDARD')::uuid,
       md5('mmkyu-fsyn:card:' || s.code || ':' || n)::uuid,
       (SELECT t.id FROM public.card_variant_type t
          JOIN public.game g ON g.id = t.game_id
         WHERE g.code = 'POKEMON' AND t.code = 'STANDARD'),
       1,
       TRUE,
       TRUE
  FROM (VALUES ('ZZSYN-A'), ('ZZSYN-B')) AS s(code)
 CROSS JOIN generate_series(1, 500) AS n;

-- ================================================================
-- 4b. Variantes adicionais NÃO padrão e ativas: HOLO em 5 cards
--     distintos do set ZZSYN-A (5824 exige >= 3)
-- ================================================================
INSERT INTO public.card_variant (id, card_id, variant_type_id,
                                 variant_order, is_default, is_active)
SELECT md5('mmkyu-fsyn:card_variant:ZZSYN-A:' || n || ':HOLO')::uuid,
       md5('mmkyu-fsyn:card:ZZSYN-A:' || n)::uuid,
       (SELECT t.id FROM public.card_variant_type t
          JOIN public.game g ON g.id = t.game_id
         WHERE g.code = 'POKEMON' AND t.code = 'HOLO'),
       2,
       FALSE,
       TRUE
  FROM generate_series(1, 5) AS n;

-- ================================================================
-- POST — invariantes da fixture e dos seletores dos harnesses
-- (qualquer falha reverte a transação inteira)
-- ================================================================
DO $post$
DECLARE
    v_game UUID;
    v_bad  TEXT := '';
    v_n    BIGINT;
    v_cv1  UUID; v_set1 UUID; v_cv2 UUID; v_cvo UUID;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';

    -- Quantidades
    IF (SELECT count(*) FROM public.expansion) <> 1 THEN v_bad := v_bad || 'expansion<>1; '; END IF;
    IF (SELECT count(*) FROM public.card_set)  <> 2 THEN v_bad := v_bad || 'card_set<>2; '; END IF;
    IF (SELECT count(*) FROM public.card)      <> 1000 THEN v_bad := v_bad || 'card<>1000; '; END IF;
    IF (SELECT count(*) FROM public.card WHERE card_set_id = md5('mmkyu-fsyn:card_set:ZZSYN-A')::uuid) <> 500
       OR (SELECT count(*) FROM public.card WHERE card_set_id = md5('mmkyu-fsyn:card_set:ZZSYN-B')::uuid) <> 500 THEN
        v_bad := v_bad || 'distribuicao por set<>500/500; ';
    END IF;
    IF (SELECT count(*) FROM public.card_variant) <> 1005 THEN v_bad := v_bad || 'card_variant<>1005; '; END IF;

    -- Exatamente 1 variante padrão (ativa) por card
    SELECT count(*) INTO v_n FROM (
        SELECT c.id
          FROM public.card c
          LEFT JOIN public.card_variant cv ON cv.card_id = c.id AND cv.is_default
         GROUP BY c.id
        HAVING count(cv.id) <> 1) x;
    IF v_n <> 0 THEN v_bad := v_bad || format('cards sem exatamente 1 default=%s; ', v_n); END IF;

    -- Todas as variantes ativas; >= 3 não padrão em cards distintos
    IF EXISTS (SELECT 1 FROM public.card_variant WHERE NOT is_active) THEN v_bad := v_bad || 'variante inativa; '; END IF;
    IF (SELECT count(DISTINCT card_id) FROM public.card_variant WHERE is_active AND NOT is_default) < 3 THEN
        v_bad := v_bad || 'menos de 3 nao-padrao ativas em cards distintos; ';
    END IF;

    -- Raridade, categoria e tipo pertencem ao Game POKEMON
    IF EXISTS (SELECT 1 FROM public.card c
                 JOIN public.rarity r        ON r.id = c.rarity_id
                 JOIN public.card_category k ON k.id = c.category_id
                WHERE r.game_id <> v_game OR k.game_id <> v_game) THEN
        v_bad := v_bad || 'rarity/category fora do Game; ';
    END IF;
    IF EXISTS (SELECT 1 FROM public.card_variant cv
                 JOIN public.card_variant_type t ON t.id = cv.variant_type_id
                WHERE t.game_id <> v_game) THEN
        v_bad := v_bad || 'variant_type fora do Game; ';
    END IF;

    -- Seletores 5822/5823 (mesmas consultas dos harnesses)
    SELECT cv.id, ca.card_set_id INTO v_cv1, v_set1
      FROM public.card_variant cv
      JOIN public.card ca      ON ca.id = cv.card_id
      JOIN public.card_set cs  ON cs.id = ca.card_set_id
      JOIN public.expansion ex ON ex.id = cs.expansion_id
     ORDER BY cv.id LIMIT 1;
    SELECT cv.id INTO v_cv2
      FROM public.card_variant cv
      JOIN public.card ca ON ca.id = cv.card_id
     WHERE ca.card_set_id = v_set1 AND cv.id <> v_cv1
     ORDER BY cv.id LIMIT 1;
    SELECT cv.id INTO v_cvo
      FROM public.card_variant cv
      JOIN public.card ca      ON ca.id = cv.card_id
      JOIN public.card_set cs  ON cs.id = ca.card_set_id
      JOIN public.expansion ex ON ex.id = cs.expansion_id
     WHERE ex.game_id = v_game AND ca.card_set_id <> v_set1
     ORDER BY cv.id LIMIT 1;
    IF v_cv1 IS NULL OR v_cv2 IS NULL OR v_cvo IS NULL THEN
        v_bad := v_bad || 'seletor cv1/cv2/cv_other incompleto; ';
    END IF;

    -- Seletor 5823 D01/D02: 1000 primeiras por id, todas ativas
    IF (SELECT count(*) FROM (SELECT is_active FROM public.card_variant ORDER BY id LIMIT 1000) s
         WHERE s.is_active) <> 1000 THEN
        v_bad := v_bad || '5823 D: 1000 primeiras por id nao sao todas ativas; ';
    END IF;

    -- Seletor 5824 F01: 3 ativas e não padrão, em cards distintos
    IF (SELECT count(*) FROM (
            SELECT DISTINCT ON (cv.card_id) cv.id
              FROM public.card_variant cv
             WHERE cv.is_active AND NOT cv.is_default
             ORDER BY cv.card_id, cv.id
             LIMIT 3) x) <> 3 THEN
        v_bad := v_bad || '5824 F01: menos de 3 variantes; ';
    END IF;

    IF v_bad <> '' THEN
        RAISE EXCEPTION 'F-SYN POST reprovado: %', v_bad;
    END IF;

    RAISE NOTICE 'F-SYN POST: OK — expansion=1 card_set=2 card=1000 card_variant=1005 (1000 STANDARD padrao + 5 HOLO nao padrao), todas ativas';
END
$post$;

COMMIT;
