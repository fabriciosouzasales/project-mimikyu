/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2265 - Acento no nome de exibição do acabamento CRACKED_ICE_HOLO
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (2026-10-11, apply_migration no LIVE, autorizado por Fabrício).
              Postcheck: name = 'Holográfica Cracked Ice'; id 9c19476b…, code, description e
              display_order (43) inalterados; 1 linha CARD_VARIANT_TYPE_UPDATED no log (ator admin).
Data........: 2026-10-11
Mandato.....: Fabrício, 2026-10-11 — corrigir "Holografica Cracked Ice" → "Holográfica Cracked Ice",
              sem alterar IDs nem identidades técnicas.

O que faz
  Chama a RPC administrativa existente admin_update_card_variant_type (Query 2155), como admin,
  trocando só o name. code (CRACKED_ICE_HOLO), id, description e display_order são preservados;
  a RPC grava CARD_VARIANT_TYPE_UPDATED no log administrativo. Guard: só age se o nome atual for
  exatamente o errado (reexecução não faz nada).

Como validar
  select code, name from public.card_variant_type where code = 'CRACKED_ICE_HOLO';
  -- esperado: CRACKED_ICE_HOLO | Holográfica Cracked Ice
===============================================================================
*/
DO $m$
DECLARE
  v_t public.card_variant_type%ROWTYPE;
BEGIN
  SELECT * INTO v_t FROM public.card_variant_type WHERE code = 'CRACKED_ICE_HOLO';
  IF NOT FOUND THEN RAISE EXCEPTION '2265: CRACKED_ICE_HOLO não encontrado'; END IF;
  IF v_t.name = 'Holográfica Cracked Ice' THEN RETURN; END IF;
  IF v_t.name <> 'Holografica Cracked Ice' THEN
    RAISE EXCEPTION '2265: nome inesperado (%), nada alterado', v_t.name;
  END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', 'fe316458-49dd-44e1-aac0-f4b7604ef8f2', 'role', 'authenticated')::text, true);
  PERFORM public.admin_update_card_variant_type(v_t.id, 'Holográfica Cracked Ice', v_t.description, v_t.display_order);
END
$m$;
