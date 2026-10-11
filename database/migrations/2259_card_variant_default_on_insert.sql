/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2259 - Variante padrão automática para variantes novas (trigger)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (2026-10-11, apply_migration no LIVE qjfutqujxrbzgrtkpgkg). Testes
              (transação desfeita): empates 0/13 escolhidos; carta sem padrão + reverse nova → STANDARD;
              carta com padrão + variante nova → padrão mantido; empate + insert → sem padrão, sem erro;
              regra sobre as 21.166 cartas em ~0,8 s; EXECUTE negado a anon/authenticated.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-11
Mandato.....: Fabrício, 2026-10-11 — "Trigger no banco", reutilizando a regra do 2258 como fonte
              única; nunca substituir is_default existente; só vencedor único; processar só as
              cartas afetadas; nunca impedir a importação.
Depende.....: 160 (card_variant + índice único parcial de is_default), 2258 (regra)

O que faz
  1. internal.pick_card_variant_default(uuid[]) — FONTE ÚNICA da regra de 2258:
       R1 acabamento: STANDARD < HOLO < outros não-reverse < família reverse (reverse só quando
          é a única opção); R2 Edition Context: sem < simples < composto (componentes '__');
       R3 Printing: sem perfil/UNLIMITED < outros. Devolve (card_id, card_variant_id) só para
       cartas ativas SEM padrão e com vencedor ÚNICO. Empate não devolve nada.
  2. Trigger AFTER INSERT (por comando, tabela de transição) em card_variant: aplica a função
     às cartas das linhas inseridas. Cobre importação, seed e migration manual.

Garantias
  - Nunca troca padrão: só atualiza carta sem nenhum is_default (checado na própria UPDATE).
  - Concorrência: trava as cartas afetadas (FOR NO KEY UPDATE, ordem estável) antes de decidir;
    compatível com o FOR KEY SHARE das FKs. Se mesmo assim houver conflito no índice único,
    o bloco engole a violação: a carta fica sem padrão e a importação segue.
  - Custo proporcional: só as cartas do comando; cartas que já têm padrão saem no filtro.
  - EXECUTE revogado de PUBLIC/anon/authenticated nas duas funções.

Como validar
  select tgname from pg_trigger where tgrelid='public.card_variant'::regclass and tgname='trg_card_variant_assign_default';
===============================================================================
*/

CREATE OR REPLACE FUNCTION internal.pick_card_variant_default(p_card_ids uuid[])
RETURNS TABLE (card_id uuid, card_variant_id uuid)
LANGUAGE sql STABLE
SET search_path = ''
AS $f$
  WITH r AS (
    SELECT v.id, v.card_id,
           CASE WHEN t.code = 'STANDARD' THEN 1 WHEN t.code = 'HOLO' THEN 2
                WHEN t.code LIKE '%REVERSE%' THEN 4 ELSE 3 END AS r1,
           CASE WHEN ec.code IS NULL THEN 0
                ELSE 1 + (length(ec.code) - length(replace(ec.code, '__', ''))) / 2 END AS r2,
           CASE WHEN pp.code IS NULL OR pp.code = 'UNLIMITED' THEN 0 ELSE 1 END AS r3
      FROM public.card_variant v
      JOIN public.card c ON c.id = v.card_id AND c.is_active
      JOIN public.card_variant_type t ON t.id = v.variant_type_id
      LEFT JOIN public.card_edition_context_profile ec ON ec.id = v.edition_context_profile_id
      LEFT JOIN public.card_printing_profile pp ON pp.id = v.printing_profile_id
     WHERE v.card_id = ANY (p_card_ids)
       AND NOT EXISTS (SELECT 1 FROM public.card_variant d WHERE d.card_id = v.card_id AND d.is_default)
  ), k AS (
    SELECT r.*, dense_rank() OVER (PARTITION BY r.card_id ORDER BY r.r1, r.r2, r.r3) AS rk FROM r
  )
  SELECT k.card_id, min(k.id::text)::uuid
    FROM k WHERE k.rk = 1
   GROUP BY k.card_id
  HAVING count(*) = 1;
$f$;
REVOKE ALL ON FUNCTION internal.pick_card_variant_default(uuid[]) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION internal.assign_card_variant_default_on_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $f$
DECLARE
  v_cards uuid[];
BEGIN
  SELECT array_agg(DISTINCT n.card_id ORDER BY n.card_id) INTO v_cards
    FROM new_rows n
   WHERE NOT n.is_default
     AND NOT EXISTS (SELECT 1 FROM public.card_variant d WHERE d.card_id = n.card_id AND d.is_default);
  IF v_cards IS NULL THEN
    RETURN NULL;
  END IF;

  BEGIN
    PERFORM 1 FROM public.card c WHERE c.id = ANY (v_cards) ORDER BY c.id FOR NO KEY UPDATE;

    UPDATE public.card_variant cv
       SET is_default = true
      FROM internal.pick_card_variant_default(v_cards) w
     WHERE cv.id = w.card_variant_id
       AND NOT EXISTS (SELECT 1 FROM public.card_variant d WHERE d.card_id = w.card_id AND d.is_default);
  EXCEPTION WHEN unique_violation THEN
    -- outra transação definiu o padrão no meio do caminho: não bloquear a importação
    NULL;
  END;
  RETURN NULL;
END;
$f$;
REVOKE ALL ON FUNCTION internal.assign_card_variant_default_on_insert() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_card_variant_assign_default ON public.card_variant;
CREATE TRIGGER trg_card_variant_assign_default
  AFTER INSERT ON public.card_variant
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION internal.assign_card_variant_default_on_insert();
