/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2277 - ME5.5 (Celebração de 30 Anos): três cartas Mew "RGB"
              (R, G, B) que a TCGdex passou a listar depois da importação
Versão......: 0.1
Status......: EXECUTADO (2026-11-08). Dry-run PASS (cartas=3/0 variantes=3/0
              total=161, resíduo zero); gravado com autorização de Fabrício
              ("Autorizo gravar assim"): ME5.5 161 | 161 com uma padrão;
              action log 3 CARD_CREATED + 3 CARD_VARIANT_CREATED. O arquivo
              mantém v_dry_run = true por segurança (reexecução é idempotente).
Data........: 2026-11-08

Contexto
  A importação do ME5.5 (2026-10-10) trouxe 158 cartas (001–158), tudo o que a
  TCGdex publicava. Hoje a TCGdex (`30th`, pt e en) lista 161: as 158 mais
  `30th-R`, `30th-G` e `30th-B` — "Mew", raridade "RGB Rare", holográfica,
  sem número (identificador = letra). A Scrydex confirma as mesmas três
  (`me55-R`, `me55-G`, `me55-B`). A raridade já existe no catálogo
  (`RGB_RARE`, "Rara RGB", com mapeamento "RGB Rare"/"Rara RGB"), sem cartas.

  O fluxo normal de importação de cartas NÃO consegue trazê-las: o plano de
  ordem do Set recusa identificador só com letras (`collector-order.ts`,
  UnsupportedCollectorNumberError "B") e o job inteiro falha — vale também
  para qualquer nova importação de cartas do ME5.5 enquanto não houver uma
  exceção nomeada (como HGSS/EXU). Por isso o cadastro é direto, como na 2275.

Mecanismo (mesmo da 2275)
  public.admin_create_card(...)          — valida Set, raridade, categoria,
                                           número e ordem únicos; grava
                                           CARD_CREATED no action log.
  public.admin_create_card_variant(...)  — a primeira variante da carta vira a
                                           padrão; grava CARD_VARIANT_CREATED.
  Nenhum INSERT direto em tabela.

Cartas (decisões para confirmar)
  Nº  Nome  Raridade  Categoria  Total  Ordem  Variante padrão
  R   Mew   Rara RGB  Pokémon    128    159    Holográfica · Celebração de 30 Anos
  G   Mew   Rara RGB  Pokémon    128    160    Holográfica · Celebração de 30 Anos
  B   Mew   Rara RGB  Pokémon    128    161    Holográfica · Celebração de 30 Anos
  - Número = a letra, exatamente como a TCGdex/Scrydex (passa em
    ck_card_collector_number_format).
  - Ordem R, G, B depois da 158 (ordem do nome da raridade e da Scrydex; a
    TCGdex lista B, G, R por ordem alfabética).
  - Total 128 e variante Holográfica + contexto CAMPAIGN_30TH_ANNIVERSARY,
    iguais às 158 cartas existentes do ME5.5.

Modos
  v_dry_run = true  (padrão): faz tudo, confere e desfaz (exceção sentinela
                     LI000 'DRY_RUN_OK'). Nada persiste.
  v_dry_run = false: grava. Só com autorização explícita.

Idempotência
  Carta cujo número já existe no Set é PULADA; variante já existente é PULADA.

Resultado esperado (primeira execução)
  3 cartas, 3 variantes; ME5.5 com 161 cartas, todas com exatamente uma padrão.

Como validar (depois de gravar)
  SELECT count(*) cards, count(*) FILTER (WHERE nd = 1) com_uma_padrao
    FROM (SELECT c.id, count(v.id) FILTER (WHERE v.is_default) nd
            FROM public.card c LEFT JOIN public.card_variant v ON v.card_id = c.id
           WHERE c.card_set_id = '3aa3fcf6-5826-4a13-b6a2-8f652a2b485a'
           GROUP BY c.id) s;
  -- esperado: 161 | 161

Imagens (fora deste arquivo)
  en: Scrydex `images.scrydex.com/pokemon/me55-{R,G,B}/large` (654 × 914).
  pt: sem fonte hoje (a TCGdex lista as três, mas os arquivos não existem).
*/

DO $$
DECLARE
  v_dry_run    boolean := true;   -- trocar para false só com autorização
  c_set        constant uuid := '3aa3fcf6-5826-4a13-b6a2-8f652a2b485a';  -- ME5.5
  c_admin      constant uuid := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';
  c_rgb        constant uuid := '585bb3f7-101e-4336-87e2-14526356507b';  -- rarity RGB_RARE
  c_pokemon    constant uuid := 'ee4beed4-7d4d-4420-8168-04a7085535e8';  -- category POKEMON
  c_holo       constant uuid := 'f2bddc37-b71d-4eda-bf33-2d188123bd16';  -- variant type HOLO
  c_30th       constant uuid := 'f4c4152e-34d8-4ccf-8f03-1bf86e1bf676';  -- CAMPAIGN_30TH_ANNIVERSARY

  r            record;
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

  FOR r IN
    SELECT * FROM (VALUES ('R', 159), ('G', 160), ('B', 161)) AS t(num, ord)
    ORDER BY ord
  LOOP
    SELECT id INTO v_card FROM public.card
     WHERE card_set_id = c_set AND collector_number = r.num;

    IF v_card IS NULL THEN
      v_card := public.admin_create_card(c_set, r.num, 128, r.ord, c_rgb, c_pokemon, 'Mew');
      v_cards_new := v_cards_new + 1;
    ELSE
      v_cards_skip := v_cards_skip + 1;
    END IF;

    IF EXISTS (SELECT 1 FROM public.card_variant cv
                WHERE cv.card_id = v_card
                  AND cv.variant_type_id = c_holo
                  AND cv.printing_profile_id IS NULL
                  AND cv.edition_context_profile_id IS NOT DISTINCT FROM c_30th) THEN
      v_vars_skip := v_vars_skip + 1;
    ELSE
      PERFORM public.admin_create_card_variant(v_card, c_holo, NULL, c_30th);
      v_vars_new := v_vars_new + 1;
    END IF;
  END LOOP;

  -- Conferência dentro da mesma transação.
  SELECT count(*) INTO v_total FROM public.card WHERE card_set_id = c_set;
  SELECT count(*) INTO v_bad
    FROM (SELECT c.id, count(cv.id) FILTER (WHERE cv.is_default) nd
            FROM public.card c LEFT JOIN public.card_variant cv ON cv.card_id = c.id
           WHERE c.card_set_id = c_set
           GROUP BY c.id) s
   WHERE nd <> 1;

  RAISE NOTICE 'cartas criadas=% puladas=% | variantes criadas=% puladas=% | ME5.5 total=% | sem exatamente 1 padrão=%',
    v_cards_new, v_cards_skip, v_vars_new, v_vars_skip, v_total, v_bad;

  IF v_total <> 161 OR v_bad <> 0 THEN
    RAISE EXCEPTION 'POSTCHECK_FAIL: total=% (esperado 161), sem padrão única=% (esperado 0)', v_total, v_bad;
  END IF;

  IF v_dry_run THEN
    RAISE EXCEPTION USING ERRCODE = 'LI000',
      MESSAGE = format('DRY_RUN_OK cartas=%s/%s variantes=%s/%s total=%s',
                       v_cards_new, v_cards_skip, v_vars_new, v_vars_skip, v_total);
  END IF;
END
$$;
