/*
================================================================
V1-16 · 5364 v1.1 — prova de concorrência com DUAS sessões
Status: PREPARADO, NÃO EXECUTADO (OFFLINE POSTGRES VALIDATION-01).
Onde: SOMENTE no PostgreSQL local descartável do runbook
      OFFLINE-VALIDATION-RUNBOOK.md (nunca no LIVE).
Pré-req: 5361–5364 aplicadas; harness 5887 completo PASS (66/66);
         dois terminais psql (A e B) no MESMO banco local, como postgres.
Objetivo: provar que uma remoção concorrente de um exemplar do lote
         reprova a edição inteira (tudo ou nada) em vez de virar
         sucesso parcial — e que a ordem inversa não perde a edição.
Tudo termina em ROLLBACK, exceto onde indicado; o passo 0 cria
exemplares sintéticos num catálogo sintético que o passo 9 remove.
================================================================
*/

-- ---------------------------------------------------------------
-- PASSO 0 (sessão A, sozinha) — fixtures: 3 exemplares NM do u1
-- ---------------------------------------------------------------
-- Usa o primeiro usuário de auth.users (o runbook cria dois sintéticos).
-- Anotar os três ids impressos como X, Y e Z.
BEGIN;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', (SELECT id FROM auth.users ORDER BY created_at, id LIMIT 1)::text,
                         'role', 'authenticated')::text, false);
WITH v AS (
  SELECT cv.id AS cv, (SELECT id FROM public.language ORDER BY id LIMIT 1) AS lang
    FROM public.card_variant cv WHERE cv.is_active ORDER BY cv.id LIMIT 1
), p AS (
  SELECT public.preview_bulk_operation(jsonb_build_object('operation_type','REGISTER_PHYSICAL_CARDS',
           'items', jsonb_build_array(jsonb_build_object('card_variant_id', v.cv::text, 'language_id', v.lang::text, 'quantity', 3)))) AS r, v.*
    FROM v
)
SELECT public.register_physical_cards_bulk(jsonb_build_object(
         'idempotency_key', gen_random_uuid()::text,
         'preview_fingerprint', p.r ->> 'preview_fingerprint',
         'items', jsonb_build_array(jsonb_build_object('card_variant_id', p.cv::text, 'language_id', p.lang::text, 'quantity', 3))))
       -> 'result_summary' -> 'physical_card_ids' AS ids
  FROM p;
COMMIT;   -- local descartável: necessário para duas sessões enxergarem os exemplares

-- ---------------------------------------------------------------
-- CENÁRIO 1 — remoção commitada ENQUANTO a edição espera a trava
-- ---------------------------------------------------------------
-- [A] BEGIN; (identidade do u1, igual ao passo 0, com is_local = true)
--     SELECT * FROM public.remove_my_physical_card('<X>'::uuid);    -- trava X e remove (não commitar ainda)
-- [B] BEGIN; (identidade do u1)
--     SELECT * FROM public.set_my_physical_cards_condition(ARRAY['<X>','<Y>']::uuid[], 'LP');
--     -- ESPERADO: B fica BLOQUEADO (espera a trava de X)
-- [A] COMMIT;
--     -- ESPERADO em B: ERRO 22023 'um ou mais physical_card_ids não pertencem ao inventory do chamador'
--     --   (X deixou de existir; a contagem sobre o conjunto travado = 1 ≠ 2)
-- [B] ROLLBACK;
-- [A] SELECT id, condition_code FROM public.physical_card WHERE id IN ('<X>','<Y>');
--     -- ESPERADO: X ausente; Y = 'NM' (nada parcial)
--
-- Contraprova da v1.0 (opcional, só para registro): com a contagem ANTES da trava,
-- B retornaria requested_count = 2, changed_count = 1 — sucesso parcial.

-- ---------------------------------------------------------------
-- CENÁRIO 2 — edição trava primeiro; remoção espera
-- ---------------------------------------------------------------
-- [B] BEGIN; (u1)
--     SELECT * FROM public.set_my_physical_cards_condition(ARRAY['<Y>','<Z>']::uuid[], 'HP');
--     -- ESPERADO: requested_count 2, changed_count 2 (Y e Z travados até o fim de B)
-- [A] BEGIN; (u1)
--     SELECT * FROM public.remove_my_physical_card('<Y>'::uuid);
--     -- ESPERADO: A BLOQUEADO até B terminar (ou erro de lock_timeout, se a função tiver um)
-- [B] COMMIT;
-- [A] (desbloqueia) → remove Y normalmente; ROLLBACK; (não remover de fato)
-- [A] SELECT id, condition_code FROM public.physical_card WHERE id IN ('<Y>','<Z>');
--     -- ESPERADO: Y = 'HP', Z = 'HP' (a edição de B não foi perdida)

-- ---------------------------------------------------------------
-- CENÁRIO 3 — duas edições concorrentes no mesmo exemplar
-- ---------------------------------------------------------------
-- [A] BEGIN; SELECT * FROM public.set_my_physical_cards_condition(ARRAY['<Z>']::uuid[], 'MP');   -- 1/1
-- [B] BEGIN; SELECT * FROM public.set_my_physical_cards_condition(ARRAY['<Z>']::uuid[], 'MP');   -- BLOQUEADO
-- [A] COMMIT;
--     -- ESPERADO em B: requested_count 1, changed_count 0 (idempotente após reler a linha)
-- [B] COMMIT;

-- ---------------------------------------------------------------
-- PASSO 9 — limpeza (sessão A, sozinha)
-- ---------------------------------------------------------------
-- DELETE FROM public.physical_card WHERE id IN ('<X>','<Y>','<Z>');   -- local descartável
-- e conferir: SELECT count(*) FROM public.physical_card;   -- igual ao baseline do runbook
