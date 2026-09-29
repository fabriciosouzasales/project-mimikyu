\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
BEGIN TRANSACTION READ ONLY;
SET LOCAL search_path = '';
SET LOCAL TimeZone = 'UTC';
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '2s';
SET LOCAL idle_in_transaction_session_timeout = '120s';
-- >>> G11B-BODY
WITH
k AS (SELECT '2026-09-19T01:27:48Z'::timestamptz     AS t0,
             '2026-09-19T02:04:25.084Z'::timestamptz AS t1,
             '2026-09-28T17:01:46Z'::timestamptz     AS s_anchor,
             interval '10 minutes'                   AS margin),
-- censo nominal LIVE 2026-09-19T01:27:53Z (registro original, verbatim)
census(code, n_t0) AS (VALUES
  ('STANDARD',9966),('REVERSE_HOLO',7277),('HOLO',5100),('SET_LOGO_STANDARDS',484),
  ('POKE_BALL_REVERSE',302),('ENERGY_REVERSE',268),('COSMOS_HOLO',245),('MASTER_BALL_REVERSE',211),
  ('SET_LOGO_REVERSE',185),('RAINBOW_HOLO',151),('GOLD_HOLO',130),('SATANDARD_REWARDS',51),
  ('STAFF_HOLO',40),('PROMO_STAMPED',33),('REWARDS_HOLO',30),('STANDARDS_SNOWFLAKE',27),
  ('DUSK_BALL_REVERSE',26),('LOVE_BALL_REVERSE',25),('FRIEND_BALL_REVERSE',23),('QUICK_BALL_REVERSE',22),
  ('COSMOS_REVERSE',20),('CRACKED_ICE_HOLO',20),('POKEMON_CENTER_HOLO',19),('COSMOS_REWARDS_HOLO',18),
  ('COSMOS_REWARDS_REVERSE',17),('SHOWFLAKE_HOLO',17),('COSMOS_PROFESSOR_REVERSE',16),('STANDARDS_TEACHER_PROGRAM',14),
  ('ROCKET_REVERSE',10),('GAMESTOP_HOLO',9),('STANDARD_GYM_CHALLENGE',9),('EBGAMES_HOLO',8),
  ('STANDARD_REGIONAL_CHAMPIONSHIPS',8),('TINSEL_REVERSE',8),('GALAXY_HOLO',6),('STANDARD_PIKACHU_WORLD_2000',6),
  ('W_PROMO_STAMPED',6),('SNOWFLAKE_COSMOS_HOLO',5),('STANDARD_FIRST_MOVIE',4),('STANDARD_FIRST_MOVIE_INVERTED',4),
  ('STANDARD_REGIONAL_CHAMPIONSHIPS_STAFF',4),('STANDARDS_LEAGUE',4),('GYM_CHALLENGE_HOLO',3),('SET_LOGO_COSMOS_HOLO',3),
  ('STANDARD_WORLDS_2024',3),('STANDARDS_HORIZONS',3),('TINSEL_HOLO',3),('EBGAMES_REVERSE',2),
  ('STANDARD_POKEMON_4EVER',2),('STANDARD_POKEMON_CENTER_NY',2),('STANDARDS_GAMESTOP',2),('STANDARDS_POKEMON_TOGETHER',2),
  ('COSMO_HOLO_EBGAMES',1),('HORIZONS_HOLO',1),('INTERNATIONAL_CHAMPIONSHIPS_EUROPE_HOLO',1),('INTERNATIONAL_CHAMPIONSHIPS_NORTH_AMERICA_REVERSE',1),
  ('INTL_CHAMPIONSHIPS_NORTH_AMERICA_REVERSE_STAFF',1),('LENTICULAR',1),('MASTER_BALL_HOLO',1),('METAL',1),
  ('METAL_GOLD',1),('NATIONAL_CHAMPIONSHIPS_REVERSE',1),('NATIONAL_CHAMPIONSHIPS_REVERSE_STAFF',1),('PLAYER_REWARD_REVERSE',1),
  ('POKEDAY_HOLO',1),('PRERELEASE_COSMOS_HOLO',1),('PRERELEASE_HOLO',1),('SET_LOGO_STAFF_HOLO',1),
  ('STANDARD_POKETOUR_1999',1),('STANDARD_ULTRA_BALL_LEAGUE',1),('STANDARDS_ASIA_2023_2024',1),('STANDARDS_POKEMON_CENTER',1),
  ('STANDARDS_WORLDS_2023',1),('STANDARDS_WORLDS_2023_STAFF',1),('STANDARDS_WORLDS_2023_TOP_16',1),('STANDARDS_WORLDS_2023_TOP_2',1),
  ('STANDARDS_WORLDS_2023_TOP_32',1),('STANDARDS_WORLDS_2023_TOP_4',1),('STANDARDS_WORLDS_2023_TOP_8',1),('STANDARDS_WORLDS_2024_STAFF',1),
  ('STANDARDS_WORLDS_2024_TOP_16',1),('STANDARDS_WORLDS_2024_TOP_2',1),('STANDARDS_WORLDS_2024_TOP_32',1),('STANDARDS_WORLDS_2024_TOP_4',1),
  ('STANDARDS_WORLDS_2024_TOP_8',1),('STANDARDS_WORLDS_2025',1),('STANDARDS_WORLDS_2025_STAFF',1),('STANDARDS_WORLDS_2025_TOP_16',1),
  ('STANDARDS_WORLDS_2025_TOP_2',1),('STANDARDS_WORLDS_2025_TOP_32',1),('STANDARDS_WORLDS_2025_TOP_4',1),('STANDARDS_WORLDS_2026_TOP_8',1),
  ('MASTER_BALL_LEAGUE_COSMOS_HOLO',0),('MASTER_BALL_PATTERN',0),('POKE_BALL_PATTERN',0),('POKEMON_CENTER_EXCLUSIVE',0),
  ('POKEMON_DAY_COSMOS_HOLO',0)),
-- lista FINISH verbatim do seletor original (02:04:20Z)
finish(code) AS (VALUES ('STANDARD'),('HOLO'),('COSMOS_HOLO'),('REVERSE_HOLO'),('ENERGY_REVERSE'),('POKE_BALL_REVERSE'),
  ('LOVE_BALL_REVERSE'),('FRIEND_BALL_REVERSE'),('QUICK_BALL_REVERSE'),('DUSK_BALL_REVERSE'),('ROCKET_REVERSE'),
  ('MASTER_BALL_REVERSE'),('GOLD_HOLO'),('TINSEL_HOLO'),('TINSEL_REVERSE'),('CRACKED_ICE_HOLO'),('GALAXY_HOLO'),
  ('RAINBOW_HOLO'),('METAL'),('METAL_GOLD'),('LENTICULAR'),('COSMOS_REVERSE'),('MASTER_BALL_PATTERN'),
  ('POKE_BALL_PATTERN'),('MASTER_BALL_HOLO'),('SNOWFLAKE_COSMOS_HOLO'),('STANDARDS_SNOWFLAKE'),('SHOWFLAKE_HOLO')),
-- detalhe SET_LOGO por regime, LIVE 2026-09-19T02:03:40Z (registro original, verbatim)
sl_t0(regime, items) AS (VALUES
  ('1-EX7_EX16', ARRAY['EX11:89','EX13:82','EX16:78','EX15:77','EX14:75','EX12:68','EX11:18','EX13:16','EX12:14','EX14:13','EX16:13','EX15:12']),
  ('2-DOCUMENTADO', ARRAY['SVP:38','DP1:4','DP1:2']),
  ('3-SEM_EVIDENCIA', ARRAY['SV8.5:13','SV10:9','SV9:7','SV7:6','SV5:4','SV8:4','SV6:3','DP2:2','SV10.5W:2','SV2:2','SV5:2','SV7:2','SWSH10:2',
     'COL1:1','HGSS4:1','HGSS4:1','SV10.5B:1','SV3:1','SV3.5:1','SV4:1','SV5:1','SV6:1','SV6.5:1','SV8.5:1','SWSH11:1','SWSH12:1','SWSH2:1','SWSH3:1','SWSH4:1'])),
-- mapa nominal dos 63 tipos READY (auditado contra Q11)
grp(code, grp) AS (VALUES
  ('SATANDARD_REWARDS','A'),('STAFF_HOLO','A'),('SET_LOGO_REVERSE','A'),('REWARDS_HOLO','A'),('POKEMON_CENTER_HOLO','A'),
  ('COSMOS_REWARDS_HOLO','A'),('COSMOS_REWARDS_REVERSE','A'),('COSMOS_PROFESSOR_REVERSE','A'),('STANDARDS_TEACHER_PROGRAM','A'),
  ('STANDARD_GYM_CHALLENGE','A'),('GAMESTOP_HOLO','A'),('STANDARD_REGIONAL_CHAMPIONSHIPS','A'),('EBGAMES_HOLO','A'),
  ('STANDARD_PIKACHU_WORLD_2000','A'),('W_PROMO_STAMPED','A'),('SET_LOGO_STANDARDS','A'),('STANDARD_FIRST_MOVIE','A'),
  ('STANDARD_FIRST_MOVIE_INVERTED','A'),('STANDARD_REGIONAL_CHAMPIONSHIPS_STAFF','A'),('STANDARDS_LEAGUE','A'),
  ('STANDARD_WORLDS_2024','A'),('STANDARDS_HORIZONS','A'),('GYM_CHALLENGE_HOLO','A'),
  ('STANDARDS_ASIA_2023_2024','B'),('STANDARDS_WORLDS_2023','B'),('STANDARDS_WORLDS_2023_STAFF','B'),('STANDARDS_WORLDS_2023_TOP_16','B'),
  ('STANDARDS_WORLDS_2023_TOP_2','B'),('STANDARDS_WORLDS_2023_TOP_32','B'),('STANDARDS_WORLDS_2023_TOP_4','B'),('STANDARDS_WORLDS_2023_TOP_8','B'),
  ('STANDARDS_WORLDS_2024_STAFF','B'),('STANDARDS_WORLDS_2024_TOP_16','B'),('STANDARDS_WORLDS_2024_TOP_2','B'),('STANDARDS_WORLDS_2024_TOP_32','B'),
  ('STANDARDS_WORLDS_2024_TOP_4','B'),('STANDARDS_WORLDS_2024_TOP_8','B'),('STANDARDS_WORLDS_2025','B'),('STANDARDS_WORLDS_2025_STAFF','B'),
  ('STANDARDS_WORLDS_2025_TOP_16','B'),('STANDARDS_WORLDS_2025_TOP_2','B'),('STANDARDS_WORLDS_2025_TOP_32','B'),('STANDARDS_WORLDS_2025_TOP_4','B'),
  ('STANDARDS_WORLDS_2026_TOP_8','B'),
  ('EBGAMES_REVERSE','C_DOUBLE'),('STANDARD_POKEMON_4EVER','C_DOUBLE'),('STANDARD_POKEMON_CENTER_NY','C_DOUBLE'),
  ('STANDARDS_GAMESTOP','C_DOUBLE'),('STANDARDS_POKEMON_TOGETHER','C_DOUBLE'),
  ('COSMO_HOLO_EBGAMES','C_UNITARY'),('HORIZONS_HOLO','C_UNITARY'),('INTERNATIONAL_CHAMPIONSHIPS_EUROPE_HOLO','C_UNITARY'),
  ('INTERNATIONAL_CHAMPIONSHIPS_NORTH_AMERICA_REVERSE','C_UNITARY'),('INTL_CHAMPIONSHIPS_NORTH_AMERICA_REVERSE_STAFF','C_UNITARY'),
  ('NATIONAL_CHAMPIONSHIPS_REVERSE','C_UNITARY'),('NATIONAL_CHAMPIONSHIPS_REVERSE_STAFF','C_UNITARY'),('PLAYER_REWARD_REVERSE','C_UNITARY'),
  ('POKEDAY_HOLO','C_UNITARY'),('PRERELEASE_COSMOS_HOLO','C_UNITARY'),('PRERELEASE_HOLO','C_UNITARY'),('STANDARD_POKETOUR_1999','C_UNITARY'),
  ('STANDARD_ULTRA_BALL_LEAGUE','C_UNITARY'),('STANDARDS_POKEMON_CENTER','C_UNITARY')),
-- universo com a particao do seletor ORIGINAL (semantica verbatim, objetos qualificados)
v AS (
    SELECT vt.id AS tid, vt.code AS tipo, cv.id AS vid, cv.card_id, cs.id AS set_id, cs.code AS set_code,
           cv.created_at AS cv_created, cv.updated_at AS cv_updated, c.updated_at AS c_updated,
           CASE WHEN vt.code = 'SET_LOGO_STANDARDS' THEN 'STANDARD'
                WHEN vt.code IN ('SET_LOGO_REVERSE','SET_LOGO_STAFF_HOLO') THEN 'HOLO'
                WHEN vt.code = 'SET_LOGO_COSMOS_HOLO' THEN 'COSMOS_HOLO'
                WHEN vt.code ~ 'COSMOS' THEN 'COSMOS_HOLO' WHEN vt.code ~ 'REVERSE' THEN 'REVERSE_HOLO'
                WHEN vt.code ~ 'HOLO' THEN 'HOLO' ELSE 'STANDARD' END AS base,
           CASE WHEN vt.code LIKE 'SET_LOGO%' AND cs.code ~ '^EX(7|8|9|10|11|12|13|14|15|16)$' THEN 'NAO_CONTAMINADO_FINISH'
                WHEN vt.code LIKE 'SET_LOGO%' AND cs.code IN ('DP1','SWSH9','SVP') THEN 'READY'
                WHEN vt.code LIKE 'SET_LOGO%' THEN 'HOLD'
                WHEN vt.code = 'PROMO_STAMPED' THEN 'HOLD'
                WHEN vt.code IN (SELECT finish.code FROM finish) THEN 'FINISH_PURO'
                ELSE 'READY' END AS particao
      FROM public.card_variant_type vt
      JOIN public.card_variant cv ON cv.variant_type_id = vt.id
      JOIN public.card c          ON c.id  = cv.card_id
      JOIN public.card_set cs     ON cs.id = c.card_set_id),
vw AS (
    SELECT v.*,
           CASE WHEN v.cv_created <= k.t0 THEN 'PRE_T0' WHEN v.cv_created <= k.t1 THEN 'W1' ELSE 'W2' END AS win_created,
           CASE WHEN v.cv_updated <= k.t0 THEN 'PRE_T0' WHEN v.cv_updated <= k.t1 THEN 'W1' ELSE 'W2' END AS win_updated,
           CASE WHEN v.c_updated  <= k.t0 THEN 'PRE_T0' WHEN v.c_updated  <= k.t1 THEN 'W1' ELSE 'W2' END AS win_card_updated,
           (v.cv_created > k.t0 - k.margin AND v.cv_created <= k.t0)
             OR (v.cv_updated > k.t0 - k.margin AND v.cv_updated <= k.t0) AS near_t0,
           v.cv_updated < v.cv_created AS anomaly_upd_before_cre,
           v.cv_created > k.s_anchor OR v.cv_updated > k.s_anchor AS anomaly_after_s
      FROM v CROSS JOIN k),
r AS (SELECT vw.*, g.grp FROM vw LEFT JOIN grp g ON g.code = vw.tipo WHERE vw.particao = 'READY'),
-- K1 cardinalidade por tipo (sem escopo de Game, como o censo original)
type_now AS (
    SELECT vt.code, pg_catalog.count(DISTINCT vt.id) AS n_type_rows, pg_catalog.count(cv.id) AS n_now
      FROM public.card_variant_type vt
      LEFT JOIN public.card_variant cv ON cv.variant_type_id = vt.id
     GROUP BY vt.code),
type_ev AS (
    SELECT vw.tipo AS code,
           pg_catalog.count(*) FILTER (WHERE vw.win_created = 'W1') AS created_w1,
           pg_catalog.count(*) FILTER (WHERE vw.win_created = 'W2') AS created_w2,
           pg_catalog.count(*) FILTER (WHERE vw.win_updated = 'W1') AS updated_w1,
           pg_catalog.count(*) FILTER (WHERE vw.win_updated = 'W2') AS updated_w2
      FROM vw GROUP BY vw.tipo),
k1 AS (
    SELECT COALESCE(c.code, t.code) AS code, c.n_t0, t.n_now, t.n_type_rows,
           (g.code IS NOT NULL) AS ready_type,
           COALESCE(e.created_w1, 0) AS created_w1, COALESCE(e.created_w2, 0) AS created_w2,
           COALESCE(e.updated_w1, 0) AS updated_w1, COALESCE(e.updated_w2, 0) AS updated_w2
      FROM census c
      FULL JOIN type_now t ON t.code = c.code
      LEFT JOIN grp g      ON g.code = COALESCE(c.code, t.code)
      LEFT JOIN type_ev e  ON e.code = COALESCE(c.code, t.code)),
-- K2 SET_LOGO por regime (mesma agregacao da consulta original de 02:03:35Z)
sl_now_raw AS (
    SELECT vt.code AS sl_tipo, cs.code AS set_code, pg_catalog.count(*) AS n
      FROM public.card_variant_type vt
      JOIN public.card_variant cv ON cv.variant_type_id = vt.id
      JOIN public.card c          ON c.id  = cv.card_id
      JOIN public.card_set cs     ON cs.id = c.card_set_id
     WHERE vt.code LIKE 'SET_LOGO%'
     GROUP BY vt.code, cs.code),
sl_now AS (
    SELECT CASE WHEN s.set_code ~ '^EX(7|8|9|10|11|12|13|14|15|16)$' THEN '1-EX7_EX16'
                WHEN s.set_code IN ('DP1','SWSH9','SVP') THEN '2-DOCUMENTADO'
                ELSE '3-SEM_EVIDENCIA' END AS regime,
           pg_catalog.array_agg(s.set_code || ':' || s.n ORDER BY s.set_code || ':' || s.n) AS items
      FROM sl_now_raw s GROUP BY 1),
k2 AS (
    SELECT COALESCE(a.regime, b.regime) AS regime,
           ARRAY(SELECT x FROM pg_catalog.unnest(a.items) AS x ORDER BY x) AS t0_items,
           b.items AS now_items,
           ARRAY(SELECT x FROM pg_catalog.unnest(a.items) AS x ORDER BY x) IS NOT DISTINCT FROM b.items AS equal
      FROM sl_t0 a FULL JOIN sl_now b ON b.regime = a.regime),
-- K5 tipos
k5 AS (
    SELECT vt.code, g.grp, vt.is_active, vt.updated_at,
           CASE WHEN vt.created_at <= k.t0 THEN 'PRE_T0' WHEN vt.created_at <= k.t1 THEN 'W1' ELSE 'W2' END AS win_created,
           CASE WHEN vt.updated_at <= k.t0 THEN 'PRE_T0' WHEN vt.updated_at <= k.t1 THEN 'W1' ELSE 'W2' END AS win_updated
      FROM public.card_variant_type vt CROSS JOIN k
      LEFT JOIN grp g ON g.code = vt.code),
-- K7 Sets que hospedam SET_LOGO (determinam a particao) + SVP/DP1/SWSH9
k7 AS (
    SELECT cs.code, cs.updated_at,
           CASE WHEN cs.created_at <= k.t0 THEN 'PRE_T0' WHEN cs.created_at <= k.t1 THEN 'W1' ELSE 'W2' END AS win_created,
           CASE WHEN cs.updated_at <= k.t0 THEN 'PRE_T0' WHEN cs.updated_at <= k.t1 THEN 'W1' ELSE 'W2' END AS win_updated
      FROM public.card_set cs CROSS JOIN k
     WHERE cs.code IN ('SVP','DP1','SWSH9')
        OR cs.id IN (SELECT vw.set_id FROM vw WHERE vw.tipo LIKE 'SET_LOGO%')),
-- K8 canal indireto de exclusao (FK ON DELETE SET NULL)
k8 AS (
    SELECT CASE WHEN x.updated_at <= k.t0 THEN 'PRE_T0' WHEN x.updated_at <= k.t1 THEN 'W1' ELSE 'W2' END AS win_updated,
           pg_catalog.count(*) AS n
      FROM public.catalog_variant_import_row x CROSS JOIN k
     WHERE x.persistence_status IN ('INSERTED', 'UNCHANGED')
       AND x.resulting_variant_id IS NULL
     GROUP BY 1),
card_trg AS (
    SELECT pg_catalog.count(*) AS n
      FROM pg_catalog.pg_trigger tg
     WHERE tg.tgrelid = pg_catalog.to_regclass('public.card')
       AND NOT tg.tgisinternal AND tg.tgenabled IN ('O', 'A')
       AND (tg.tgtype & 1) <> 0 AND (tg.tgtype & 2) <> 0 AND (tg.tgtype & 16) <> 0
       AND tg.tgfoid = pg_catalog.to_regprocedure('public.set_updated_at()')),
m AS (
    SELECT
      (SELECT pg_catalog.count(*) FROM r)                                   AS ready_n,
      (SELECT pg_catalog.count(DISTINCT r.tid) FROM r)                      AS ready_types,
      (SELECT pg_catalog.md5(pg_catalog.string_agg(r.vid::text, ',' ORDER BY r.vid)) FROM r) AS ready_md5,
      (SELECT pg_catalog.count(*) FROM r
        WHERE EXISTS (SELECT 1 FROM public.card_variant v2
                        JOIN public.card_variant_type t2 ON t2.id = v2.variant_type_id
                       WHERE v2.card_id = r.card_id AND t2.code = r.base))  AS ready_collision,
      (SELECT pg_catalog.count(*) FROM r WHERE r.grp IS NULL)               AS ready_outside_nominal_map,
      (SELECT pg_catalog.count(*) FROM grp WHERE grp.code NOT IN (SELECT r.tipo FROM r)) AS nominal_types_absent,
      (SELECT pg_catalog.jsonb_object_agg(z.particao, pg_catalog.jsonb_build_object('variants', z.n, 'types', z.t))
         FROM (SELECT vw.particao, pg_catalog.count(*) AS n, pg_catalog.count(DISTINCT vw.tipo) AS t
                 FROM vw GROUP BY vw.particao) z)                          AS partition_now,
      (SELECT pg_catalog.count(*) FROM vw)                                  AS universe_n,
      (SELECT pg_catalog.count(DISTINCT vw.tipo) FROM vw)                   AS universe_types,
      (SELECT pg_catalog.count(*) FROM public.game)                         AS n_games)
SELECT pg_catalog.jsonb_pretty(pg_catalog.jsonb_build_object(
  'probe', 'B5X-G1.1b',
  'constants', (SELECT pg_catalog.jsonb_build_object('t0', k.t0, 't1', k.t1, 's_anchor', k.s_anchor, 'margin', k.margin::text) FROM k),
  'K3_original_selector', pg_catalog.jsonb_build_object(
        'ready_n', m.ready_n, 'ready_types', m.ready_types, 'ready_md5', m.ready_md5,
        'ready_md5_equals_q11', m.ready_md5 = 'ee0e4c54336179431797e602a358bb0e',
        'ready_collision', m.ready_collision,
        'ready_outside_nominal_map', m.ready_outside_nominal_map, 'nominal_types_absent', m.nominal_types_absent,
        'partition_now', m.partition_now, 'universe_n', m.universe_n, 'universe_types', m.universe_types, 'n_games', m.n_games,
        't0_reference', pg_catalog.jsonb_build_object('READY', '365/63', 'HOLD', '107/5', 'NAO_CONTAMINADO_FINISH', '555/2',
                                                      'FINISH_PURO', '23866/26', 'TOTAL', '24893/92', 'ready_collision', 188)),
  'K1_type_cardinality', pg_catalog.jsonb_build_object(
        'census_codes', (SELECT pg_catalog.count(*) FROM census),
        'now_codes', (SELECT pg_catalog.count(*) FROM type_now),
        'duplicate_code_rows', (SELECT COALESCE(pg_catalog.jsonb_agg(t.code ORDER BY t.code), '[]'::pg_catalog.jsonb)
                                  FROM type_now t WHERE t.n_type_rows > 1),
        'mismatches', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                           'code', k1.code, 'n_t0', k1.n_t0, 'n_now', k1.n_now, 'ready_type', k1.ready_type,
                           'created_w1', k1.created_w1, 'created_w2', k1.created_w2,
                           'updated_w1', k1.updated_w1, 'updated_w2', k1.updated_w2) ORDER BY k1.code), '[]'::pg_catalog.jsonb)
                         FROM k1 WHERE k1.n_t0 IS DISTINCT FROM k1.n_now),
        'ready_mismatch_count', (SELECT pg_catalog.count(*) FROM k1 WHERE k1.ready_type AND k1.n_t0 IS DISTINCT FROM k1.n_now),
        'other_mismatch_count', (SELECT pg_catalog.count(*) FROM k1 WHERE NOT k1.ready_type AND k1.n_t0 IS DISTINCT FROM k1.n_now)),
  'K2_set_logo_by_set', (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                           'regime', k2.regime, 'equal', k2.equal, 't0', k2.t0_items, 'now', k2.now_items) ORDER BY k2.regime) FROM k2),
  'K4_ready_members', pg_catalog.jsonb_build_object(
        'by_group', (SELECT pg_catalog.jsonb_object_agg(z.g, z.o) FROM (
                        SELECT COALESCE(r.grp, 'UNMAPPED') AS g, pg_catalog.jsonb_build_object(
                          'n', pg_catalog.count(*),
                          'created_w1', pg_catalog.count(*) FILTER (WHERE r.win_created = 'W1'),
                          'created_w2', pg_catalog.count(*) FILTER (WHERE r.win_created = 'W2'),
                          'updated_w1', pg_catalog.count(*) FILTER (WHERE r.win_updated = 'W1'),
                          'updated_w2', pg_catalog.count(*) FILTER (WHERE r.win_updated = 'W2'),
                          'near_t0_margin', pg_catalog.count(*) FILTER (WHERE r.near_t0),
                          'anomaly_updated_before_created', pg_catalog.count(*) FILTER (WHERE r.anomaly_upd_before_cre),
                          'anomaly_after_s_anchor', pg_catalog.count(*) FILTER (WHERE r.anomaly_after_s),
                          'max_created', pg_catalog.max(r.cv_created), 'max_updated', pg_catalog.max(r.cv_updated)) AS o
                          FROM r GROUP BY 1) z),
        'events_total', (SELECT pg_catalog.count(*) FROM r WHERE r.win_created <> 'PRE_T0' OR r.win_updated <> 'PRE_T0'),
        'events', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                         'card_variant_id', z.vid, 'type', z.tipo, 'set', z.set_code, 'grp', z.grp,
                         'created_at', z.cv_created, 'updated_at', z.cv_updated,
                         'win_created', z.win_created, 'win_updated', z.win_updated) ORDER BY z.cv_updated DESC, z.vid), '[]'::pg_catalog.jsonb)
                     FROM (SELECT r.* FROM r WHERE r.win_created <> 'PRE_T0' OR r.win_updated <> 'PRE_T0'
                            ORDER BY r.cv_updated DESC, r.vid LIMIT 200) z)),
  'K5_types', pg_catalog.jsonb_build_object(
        'ready_types_created_after_t0', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('code', k5.code, 'win', k5.win_created) ORDER BY k5.code), '[]'::pg_catalog.jsonb)
                                           FROM k5 WHERE k5.grp IS NOT NULL AND k5.win_created <> 'PRE_T0'),
        'ready_types_updated_after_t0', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('code', k5.code, 'win', k5.win_updated, 'updated_at', k5.updated_at, 'is_active', k5.is_active) ORDER BY k5.code), '[]'::pg_catalog.jsonb)
                                           FROM k5 WHERE k5.grp IS NOT NULL AND k5.win_updated <> 'PRE_T0'),
        'any_type_created_after_t0', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('code', k5.code, 'win', k5.win_created) ORDER BY k5.code), '[]'::pg_catalog.jsonb)
                                        FROM k5 WHERE k5.win_created <> 'PRE_T0'),
        'other_types_updated_after_t0', (SELECT pg_catalog.count(*) FROM k5 WHERE k5.grp IS NULL AND k5.win_updated <> 'PRE_T0')),
  'K6_cards', pg_catalog.jsonb_build_object(
        'card_updated_at_trigger_ok', (SELECT card_trg.n = 1 FROM card_trg),
        'setlogo_ready_cards_updated', (SELECT pg_catalog.jsonb_build_object(
                'W1', pg_catalog.count(*) FILTER (WHERE r.win_card_updated = 'W1'),
                'W2', pg_catalog.count(*) FILTER (WHERE r.win_card_updated = 'W2'))
             FROM r WHERE r.tipo LIKE 'SET_LOGO%'),
        'setlogo_ready_card_events', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                'card_id', r.card_id, 'set', r.set_code, 'type', r.tipo, 'card_updated_at', r.c_updated, 'win', r.win_card_updated)
                ORDER BY r.c_updated DESC, r.card_id), '[]'::pg_catalog.jsonb)
             FROM r WHERE r.tipo LIKE 'SET_LOGO%' AND r.win_card_updated <> 'PRE_T0'),
        'other_ready_cards_updated_informative', (SELECT pg_catalog.jsonb_build_object(
                'W1', pg_catalog.count(*) FILTER (WHERE r.win_card_updated = 'W1'),
                'W2', pg_catalog.count(*) FILTER (WHERE r.win_card_updated = 'W2'))
             FROM r WHERE r.tipo NOT LIKE 'SET_LOGO%')),
  'K7_sets', (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                  'set', k7.code, 'win_created', k7.win_created, 'win_updated', k7.win_updated, 'updated_at', k7.updated_at)
                  ORDER BY k7.code), '[]'::pg_catalog.jsonb)
                FROM k7 WHERE k7.win_created <> 'PRE_T0' OR k7.win_updated <> 'PRE_T0' OR k7.code IN ('SVP', 'DP1', 'SWSH9')),
  'K8_lineage_nullified_persisted', (SELECT COALESCE(pg_catalog.jsonb_object_agg(k8.win_updated, k8.n), '{}'::pg_catalog.jsonb) FROM k8),
  'K9_global_churn_informative', (SELECT pg_catalog.jsonb_object_agg(z.particao, z.o) FROM (
        SELECT vw.particao, pg_catalog.jsonb_build_object(
               'created_w1', pg_catalog.count(*) FILTER (WHERE vw.win_created = 'W1'),
               'created_w2', pg_catalog.count(*) FILTER (WHERE vw.win_created = 'W2'),
               'updated_w1', pg_catalog.count(*) FILTER (WHERE vw.win_updated = 'W1'),
               'updated_w2', pg_catalog.count(*) FILTER (WHERE vw.win_updated = 'W2'),
               'anomaly_after_s_anchor', pg_catalog.count(*) FILTER (WHERE vw.anomaly_after_s)) AS o
          FROM vw GROUP BY vw.particao) z)
)) AS g11b
  FROM m
-- <<< G11B-BODY
;
ROLLBACK;
