/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2258 - CATALOG-VARIANT-DEFAULT-BACKFILL-01 (variante padrão por carta)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (2026-10-11, execute_sql no LIVE qjfutqujxrbzgrtkpgkg, após
              dry-run abortado de propósito: 20.240 elegíveis, 20.227 defaults, 13 empates)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-11
Mandato.....: Fabrício, 2026-10-11 — "Siga com DEFAULT-BACKFILL-01"; cartas só com versão
              reverse: "Default = única versão"; empates reais: "Deixar sem default".
Origem......: database/proposals/2026-10-11-default-backfill/README.md

O que faz
  Marca is_default = true em exatamente uma Card Variant de cada carta ativa que ainda não tem
  variante padrão. Não toca as cartas que já têm default (926, seeds 860/860a/860b).

Regra (extensão da regra editorial de 860/860a/860b, docs/05c: "STANDARD padrão quando existir;
HOLO só na ausência de STANDARD; REVERSE_HOLO nunca padrão"), ordem lexicográfica:
  R1  acabamento: STANDARD < HOLO < outros acabamentos não-reverse (RAINBOW, GOLD, COSMOS,
      CRACKED_ICE, ...) < família reverse (*REVERSE*). A reverse só é escolhida quando é a única
      opção da carta (decisão de Fabrício).
  R2  Edition Context: sem contexto < contexto simples < contexto composto (mais componentes '__',
      ex.: ARTWORK_SET_LOGO < ARTWORK_SET_LOGO__ROLE_STAFF; EVENT_WORLDS_2010 < ..._PLACEMENT_*).
  R3  Printing: sem perfil ou UNLIMITED < qualquer outro perfil (1ª edição, shadowless, erros).
  Empate na posição 1 (mais de uma variante igualmente "base") = carta fica SEM default e entra
  na lista de decisão editorial (13 cartas medidas em 2026-10-11).

Garantias (fail closed, tudo ou nada)
  G1  lock SHARE ROW EXCLUSIVE em card_variant durante a operação (nada entra no meio);
  G2  só cartas ativas sem nenhum default; atualiza só linhas is_default = false;
  P1  atualizadas = elegíveis − empates; cartas ativas com > 1 default = 0 (índice parcial único);
  P2  cartas ativas sem default depois = exatamente os empates.
  Rastro: 1 linha em catalog_admin_action_log por Card Set afetado (CARD_SET_UPDATED,
  metadata.operation = DEFAULT-BACKFILL-2258, contagens por acabamento).

Como validar
  select count(*) from public.card c where c.is_active and not exists
    (select 1 from public.card_variant v where v.card_id = c.id and v.is_default);  -- esperado 13
===============================================================================
*/

DO $mig$
DECLARE
  v_actor uuid := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';
  v_eligible int; v_tied int; v_upd int; v_left int; v_dup int;
BEGIN
  LOCK TABLE public.card_variant IN SHARE ROW EXCLUSIVE MODE;

  CREATE TEMP TABLE t2258 ON COMMIT DROP AS
  WITH nd AS (
    SELECT c.id FROM public.card c
     WHERE c.is_active
       AND NOT EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = c.id AND v.is_default)),
  r AS (
    SELECT v.id AS variant_id, v.card_id, t.code AS vt,
           CASE WHEN t.code = 'STANDARD' THEN 1 WHEN t.code = 'HOLO' THEN 2
                WHEN t.code LIKE '%REVERSE%' THEN 4 ELSE 3 END AS r1,
           CASE WHEN ec.code IS NULL THEN 0
                ELSE 1 + (length(ec.code) - length(replace(ec.code, '__', ''))) / 2 END AS r2,
           CASE WHEN pp.code IS NULL OR pp.code = 'UNLIMITED' THEN 0 ELSE 1 END AS r3
      FROM public.card_variant v
      JOIN nd ON nd.id = v.card_id
      JOIN public.card_variant_type t ON t.id = v.variant_type_id
      LEFT JOIN public.card_edition_context_profile ec ON ec.id = v.edition_context_profile_id
      LEFT JOIN public.card_printing_profile pp ON pp.id = v.printing_profile_id),
  k AS (SELECT r.*, dense_rank() OVER (PARTITION BY card_id ORDER BY r1, r2, r3) AS rk FROM r),
  top AS (SELECT card_id, count(*) AS n FROM k WHERE rk = 1 GROUP BY card_id)
  SELECT k.variant_id, k.card_id, k.vt, k.r1, top.n AS tied_candidates
    FROM k JOIN top ON top.card_id = k.card_id
   WHERE k.rk = 1;

  SELECT count(DISTINCT card_id) INTO v_eligible FROM t2258;
  SELECT count(DISTINCT card_id) INTO v_tied FROM t2258 WHERE tied_candidates > 1;

  UPDATE public.card_variant v SET is_default = true
    FROM t2258 t
   WHERE t.variant_id = v.id AND t.tied_candidates = 1 AND v.is_default = false;
  GET DIAGNOSTICS v_upd = ROW_COUNT;
  IF v_upd <> v_eligible - v_tied THEN
    RAISE EXCEPTION '2258_P1_UPDATED: % (esperado % - %)', v_upd, v_eligible, v_tied;
  END IF;

  SELECT count(*) INTO v_dup FROM (SELECT card_id FROM public.card_variant WHERE is_default
                                    GROUP BY card_id HAVING count(*) > 1) d;
  IF v_dup <> 0 THEN RAISE EXCEPTION '2258_P1_DUPLICATE_DEFAULT: %', v_dup; END IF;

  SELECT count(*) INTO v_left FROM public.card c
   WHERE c.is_active AND NOT EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = c.id AND v.is_default);
  IF v_left <> v_tied THEN RAISE EXCEPTION '2258_P2_LEFT: % (esperado %)', v_left, v_tied; END IF;

  INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
  SELECT v_actor, 'CARD_SET_UPDATED', 'CARD_SET', c.card_set_id,
         jsonb_build_object('operation', 'DEFAULT-BACKFILL-2258', 'change', 'card_variant_default_assigned',
           'defaults', count(*) FILTER (WHERE t.tied_candidates = 1),
           'standard', count(*) FILTER (WHERE t.tied_candidates = 1 AND t.r1 = 1),
           'holo', count(*) FILTER (WHERE t.tied_candidates = 1 AND t.r1 = 2),
           'other_finish', count(*) FILTER (WHERE t.tied_candidates = 1 AND t.r1 = 3),
           'reverse_only', count(*) FILTER (WHERE t.tied_candidates = 1 AND t.r1 = 4),
           'tied_left_without_default', count(DISTINCT t.card_id) FILTER (WHERE t.tied_candidates > 1),
           'rule', 'R1 acabamento > R2 edition context > R3 printing; empate fica sem default')
    FROM t2258 t JOIN public.card c ON c.id = t.card_id
   GROUP BY c.card_set_id;

  RAISE NOTICE '2258_OK eligible=% updated=% tied=%', v_eligible, v_upd, v_tied;
END;
$mig$;
