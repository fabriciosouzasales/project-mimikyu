/*
Query 2276 — MEP: alinhar todos os totais a 111 cartas
========================================================
Status......: CONFIRMADO EXECUTADO (2026-10-17; dry-run PASS antes: cartas_atualizadas=111 set=111/111)
Mandato.....: Fabrício, 2026-10-17: "precisamos ajustar a numeração total de cartas. Ainda temos a
              exibição de 60, 88 e 111 na mesma tela. Hoje temos 111 cartas. Ajuste em todos os campos
              possíveis."
Card Set....: MEP "MEP Black Star Promos" 5c106d7c-c001-4f09-85c6-087c6ed0a925

Origem de cada número na tela do Set
  60  → card_set.base_set_size e card_set.total_set_size ("Cartas totais", "111 de 60").
  88  → card.collector_total das 111 cartas (rótulo "#001/088").
  111 → contagem real de cartas.

O que faz (só pelas funções administrativas, com auditoria própria)
  1. public.admin_update_card_set: base_set_size = total_set_size = 111 (Set PROMO exige base = total);
     demais campos repetidos como estão.
  2. public.admin_update_card em cada carta com collector_total <> 111: collector_total = 111;
     nome, ordem, raridade e categoria repetidos como estão.
  Idempotente: rodar de novo não altera nada (cartas já em 111 são puladas).

Efeito colateral conhecido
  A TCGdex informa total 88 para o MEP; uma futura reimportação pela tela vai marcar as cartas como
  ATUALIZAÇÃO (88). Basta não aprovar essa diferença, ou rodar esta query de novo.

Modos: v_dry_run = true faz tudo, confere e desfaz (sentinela LI000); false grava.

Como validar
  SELECT cs.base_set_size, cs.total_set_size, count(c.*) cards,
         count(*) FILTER (WHERE c.collector_total = 111) com_111
    FROM public.card_set cs JOIN public.card c ON c.card_set_id = cs.id
   WHERE cs.id = '5c106d7c-c001-4f09-85c6-087c6ed0a925'
   GROUP BY 1, 2;
  -- esperado: 111 | 111 | 111 | 111
*/

DO $$
DECLARE
  v_dry_run boolean := false;  -- executado assim em 2026-10-17
  c_set     constant uuid := '5c106d7c-c001-4f09-85c6-087c6ed0a925';
  c_admin   constant uuid := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';
  c_total   constant int  := 111;
  s record; r record; v_n int := 0; v_cards int; v_ok int;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', c_admin, 'role', 'authenticated')::text, true);
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'PRECHECK: sessão não é administradora'; END IF;

  SELECT count(*) INTO v_cards FROM public.card WHERE card_set_id = c_set;
  IF v_cards <> c_total THEN RAISE EXCEPTION 'PRECHECK: MEP tem % cartas, esperado %', v_cards, c_total; END IF;

  SELECT * INTO s FROM public.card_set WHERE id = c_set;
  IF s.base_set_size <> c_total OR s.total_set_size <> c_total THEN
    PERFORM public.admin_update_card_set(s.id, s.code, s.name, s.set_type, s.release_order, s.release_date, c_total, c_total);
  END IF;

  FOR r IN SELECT id, name, collector_order, rarity_id, category_id FROM public.card
            WHERE card_set_id = c_set AND collector_total IS DISTINCT FROM c_total ORDER BY collector_order
  LOOP
    PERFORM public.admin_update_card(r.id, r.name, c_total, r.collector_order, r.rarity_id, r.category_id);
    v_n := v_n + 1;
  END LOOP;

  SELECT count(*) FILTER (WHERE collector_total = c_total) INTO v_ok FROM public.card WHERE card_set_id = c_set;
  SELECT * INTO s FROM public.card_set WHERE id = c_set;
  IF v_ok <> c_total OR s.base_set_size <> c_total OR s.total_set_size <> c_total THEN
    RAISE EXCEPTION 'POSTCHECK_FAIL: cartas com 111=%, base=%, total=%', v_ok, s.base_set_size, s.total_set_size;
  END IF;

  IF v_dry_run THEN
    RAISE EXCEPTION USING ERRCODE = 'LI000',
      MESSAGE = format('DRY_RUN_OK cartas_atualizadas=%s set=%s/%s', v_n, s.base_set_size, s.total_set_size);
  END IF;
END
$$;

/*
Execução (2026-10-17): validação 111 | 111 | 111 | 111; tela do Set mostra "111 cartas", "111 de 111" e #NNN/111.
*/
