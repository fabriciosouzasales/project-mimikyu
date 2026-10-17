/*
Query 2275 — MEP: cartas publicadas só na Scrydex (089–110 e 120)
====================================================================
Status......: CONFIRMADO EXECUTADO (2026-10-17, autorizado por Fabrício: "As 7 suposições estão certas e
              autorizo a execução"; dry-run PASS antes; executado com v_dry_run = false)
Proposta....: database/proposals/2026-10-17-mep-scrydex-cards/ (ver README.md)
Card Set....: MEP "MEP Black Star Promos" 5c106d7c-c001-4f09-85c6-087c6ed0a925

Objetivo
  Cadastrar as 23 cartas do MEP que a TCGdex ainda não publica (089–110 e 120),
  com a variante principal de cada uma (que vira a padrão) e as variantes
  adicionais listadas pela Scrydex. "Pikachu at the Museum" (jumbo, sem número)
  fica fora por decisão de Fabrício. A versão jumbo do 100 também fica fora
  (formato jumbo é fora de escopo no catálogo).

Como grava
  Somente pelas funções administrativas já no LIVE, com a identidade do
  administrador na sessão (mesmo protocolo da 2252):
    public.admin_create_card(...)          — valida Set, raridade, categoria,
                                             número e ordem únicos; grava
                                             CARD_CREATED no action log.
    public.admin_create_card_variant(...)  — valida acabamento e contexto;
                                             a primeira variante da carta vira
                                             a padrão; grava CARD_VARIANT_CREATED.
  Nenhum INSERT direto em tabela.

Modos
  v_dry_run = true  (padrão): faz tudo, confere e desfaz (exceção sentinela
                     LI000 'DRY_RUN_OK'). Nada persiste.
  v_dry_run = false: grava. Só com autorização explícita.

Idempotência
  Carta cujo número já existe no Set é PULADA (não recria nem altera); variante
  cuja combinação (acabamento, contexto) já existe na carta é PULADA. Rodar duas
  vezes não duplica nada.

Resultado esperado (primeira execução)
  23 cartas criadas, 26 variantes criadas (23 padrão + segunda variante em
  092, 093 e 101), MEP com 111 cartas, todas com exatamente uma variante padrão.
  Dry-run no LIVE em 2026-10-17: DRY_RUN_OK cartas=23/0 variantes=26/0
  total=111; resíduo conferido em zero (MEP segue com 88, nenhum log novo).
  Execução real em 2026-10-17: MEP 111 | 111 com uma padrão; 26 variantes
  novas; action log com 23 CARD_CREATED e 26 CARD_VARIANT_CREATED.

Como validar (depois de gravar)
  SELECT count(*) cards,
         count(*) FILTER (WHERE nd = 1) com_uma_padrao
    FROM (SELECT c.id, count(v.id) FILTER (WHERE v.is_default) nd
            FROM public.card c LEFT JOIN public.card_variant v ON v.card_id = c.id
           WHERE c.card_set_id = '5c106d7c-c001-4f09-85c6-087c6ed0a925'
           GROUP BY c.id) s;
  -- esperado: 111 | 111
*/

DO $$
DECLARE
  v_dry_run    boolean := true;   -- trocar para false só com autorização
  c_set        constant uuid := '5c106d7c-c001-4f09-85c6-087c6ed0a925';
  c_admin      constant uuid := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';
  c_promo      constant uuid := 'd61e7929-de52-445c-957c-219a12508ae3';  -- rarity PROMO
  c_pokemon    constant uuid := 'ee4beed4-7d4d-4420-8168-04a7085535e8';  -- category POKEMON
  c_trainer    constant uuid := '7c43e8ed-51e7-448b-bb29-a1959707444d';  -- category TRAINER
  c_holo       constant uuid := 'f2bddc37-b71d-4eda-bf33-2d188123bd16';  -- variant type HOLO
  c_standard   constant uuid := 'a7058cbb-d858-4af4-92e4-623fa9efbb8c';  -- variant type STANDARD
  c_30th       constant uuid := 'f4c4152e-34d8-4ccf-8f03-1bf86e1bf676';  -- CAMPAIGN_30TH_ANNIVERSARY
  c_worlds     constant uuid := '07bd71d9-658f-4d52-b1fe-d58d645408a2';  -- EVENT_WORLDS_2025
  c_worlds_st  constant uuid := 'f11b4738-a051-4e46-93d0-ee3ab2bc9725';  -- EVENT_WORLDS_2025__ROLE_STAFF
  c_winner     constant uuid := '3ecdc0e2-26a0-4b16-b9eb-eb6367e4af01';  -- PLACEMENT_WINNER
  c_pcenter    constant uuid := 'be3721ac-cbcc-4908-bb4d-f9c5fd7cf463';  -- CHANNEL_POKEMON_CENTER

  r            record;
  v            record;
  v_card       uuid;
  v_cards_new  int := 0;
  v_cards_skip int := 0;
  v_vars_new   int := 0;
  v_vars_skip  int := 0;
  v_total      int;
  v_bad        int;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', c_admin, 'role', 'authenticated')::text, true);
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'PRECHECK: identidade da sessão não é administradora';
  END IF;

  -- Cartas: número, nome (pt quando já existe no catálogo), categoria.
  -- Variantes: em ordem; a primeira vira a padrão.
  FOR r IN
    SELECT * FROM (VALUES
      ('089', 'Mega Zeraora ex',     c_pokemon, ARRAY[c_holo], ARRAY[NULL::uuid]),
      ('090', 'Mega Darkrai ex',     c_pokemon, ARRAY[c_holo], ARRAY[NULL::uuid]),
      ('091', 'Mega Dragonite ex',   c_pokemon, ARRAY[c_holo], ARRAY[NULL::uuid]),
      ('092', 'Resort Paraíso',      c_trainer, ARRAY[c_holo, c_holo], ARRAY[c_worlds_st, c_worlds]),
      ('093', 'Pikachu',             c_pokemon, ARRAY[c_holo, c_holo], ARRAY[c_winner, c_worlds]),
      ('094', 'Exeggutor de Alola',  c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('095', 'Lucario',             c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('096', 'Moltres',             c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('097', 'Articuno',            c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('098', 'Zapdos',              c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('099', 'Greninja ex',         c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('100', 'Sylveon ex',          c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('101', 'Nidorina',            c_pokemon, ARRAY[c_holo, c_holo], ARRAY[c_30th, c_pcenter]),
      ('102', 'Victini',             c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('103', 'Zeraora',             c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('104', 'Mewtwo',              c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('105', 'Mew',                 c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('106', 'Ditto',               c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('107', 'Pikachu ex',          c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('108', 'Espeon ex',           c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('109', 'Pikachu ex',          c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('110', 'Umbreon ex',          c_pokemon, ARRAY[c_holo], ARRAY[c_30th]),
      ('120', 'Fanfarra de Celebração', c_trainer, ARRAY[c_standard], ARRAY[NULL::uuid])
    ) AS t(num, name, cat, vtypes, contexts)
    ORDER BY num
  LOOP
    SELECT id INTO v_card FROM public.card
     WHERE card_set_id = c_set AND collector_number = r.num;

    IF v_card IS NULL THEN
      v_card := public.admin_create_card(
        c_set, r.num, 88, r.num::int, c_promo, r.cat, r.name);
      v_cards_new := v_cards_new + 1;
    ELSE
      v_cards_skip := v_cards_skip + 1;
    END IF;

    FOR v IN SELECT u.vt, u.ctx, u.ord
               FROM unnest(r.vtypes, r.contexts) WITH ORDINALITY AS u(vt, ctx, ord)
              ORDER BY u.ord
    LOOP
      IF EXISTS (SELECT 1 FROM public.card_variant cv
                  WHERE cv.card_id = v_card
                    AND cv.variant_type_id = v.vt
                    AND cv.printing_profile_id IS NULL
                    AND cv.edition_context_profile_id IS NOT DISTINCT FROM v.ctx) THEN
        v_vars_skip := v_vars_skip + 1;
      ELSE
        PERFORM public.admin_create_card_variant(v_card, v.vt, NULL, v.ctx);
        v_vars_new := v_vars_new + 1;
      END IF;
    END LOOP;
  END LOOP;

  -- Conferência dentro da mesma transação.
  SELECT count(*) INTO v_total FROM public.card WHERE card_set_id = c_set;
  SELECT count(*) INTO v_bad
    FROM (SELECT c.id, count(cv.id) FILTER (WHERE cv.is_default) nd
            FROM public.card c LEFT JOIN public.card_variant cv ON cv.card_id = c.id
           WHERE c.card_set_id = c_set
           GROUP BY c.id) s
   WHERE nd <> 1;

  RAISE NOTICE 'cartas criadas=% puladas=% | variantes criadas=% puladas=% | MEP total=% | cartas sem exatamente 1 padrão=%',
    v_cards_new, v_cards_skip, v_vars_new, v_vars_skip, v_total, v_bad;

  IF v_total <> 111 OR v_bad <> 0 THEN
    RAISE EXCEPTION 'POSTCHECK_FAIL: total=% (esperado 111), sem padrão única=% (esperado 0)', v_total, v_bad;
  END IF;

  IF v_dry_run THEN
    RAISE EXCEPTION USING ERRCODE = 'LI000',
      MESSAGE = format('DRY_RUN_OK cartas=%s/%s variantes=%s/%s total=%s',
                       v_cards_new, v_cards_skip, v_vars_new, v_vars_skip, v_total);
  END IF;
END
$$;
