-- STATUS: PROPOSTA -- ainda NAO aplicada em producao. Testada em BEGIN/ROLLBACK nesta rodada
-- (P16.5.2/P16.5.3, "executor de bootstrap + port/adapter", escopo autorizado por Fabricio em
-- 2026-08-26). Aguarda autorizacao explicita para aplicacao real.
--
-- Renumerada nesta rodada: esta RPC de persistencia em lote passa a ser 3958 (era 3957) porque
-- depende da coluna confirmed_sync_run_id introduzida pela migration 3957 (autoria relacional
-- de confirmacao) -- STD-001 exige ordem numerica ascendente de aplicacao, entao a migration
-- que cria o pre-requisito precisa ter o numero menor. Nenhuma excecao de ordem e mantida.
--
-- Contexto -- por que esta RPC existe (nao e um upsert PostgREST simples):
-- Introspeccao real (information_schema.role_table_grants) confirmou que service_role tem
-- apenas INSERT/SELECT em pricing_card_mapping e pricing_source_card_identity -- NAO tem
-- UPDATE. Um upsert PostgREST batch (.upsert(...).onConflict(...)) faz INSERT ... ON CONFLICT
-- DO UPDATE, que exige privilegio de UPDATE na tabela -- falharia toda vez que uma carta ja
-- tivesse uma linha (ex.: retomada apos falha parcial, o cenario "persistencia idempotente"
-- exigido no pedido). SECURITY DEFINER resolve isso executando com os privilegios do dono da
-- funcao (mesmo padrao ja usado por resolve_pricing_products_batch, migration 3928, e pelas
-- RPCs administrativas admin_resolve_pricing_mapping/admin_confirm_pricing_set_mapping) --
-- nenhum GRANT novo em tabela e necessario.
--
-- Semantica de upsert -- reimplementa em SQL, linha a linha dentro do lote, exatamente a regra
-- ja validada e testada de decideMappingUpsert() (P16.2, _shared/pricing-justtcg-matching/
-- mapping-upsert.ts) para NUNCA duplicar a decisao em dois lugares divergentes:
--   sem linha existente                              -> INSERT (action=INSERTED)
--   existente CONFIRMED/REJECTED, novo status igual   -> NOOP_SAME_STATUS (nunca reescreve)
--   existente CONFIRMED/REJECTED, novo status pior     -> NOOP_KEEP_PROTECTED_STATUS (nunca
--                                                          rebaixa um estado ja protegido)
--   existente PENDING/NOT_FOUND, mesmo novo status     -> NOOP_SAME_STATUS
--   existente PENDING/NOT_FOUND, novo status diferente -> UPDATE (action=UPGRADED; cobre tanto
--                                                          a promocao a CONFIRMED quanto a
--                                                          alternancia PENDING<->NOT_FOUND)
--
-- pricing_source_card_identity PRIMARY/CONFIRMED e escrita SOMENTE quando o status final da
-- linha (apos a decisao acima) e CONFIRMED -- nunca para PENDING/NOT_FOUND ("mappings seguros"
-- no vocabulario do pedido de Fabricio == classification SAFE do nucleo P16.2 == match_status
-- CONFIRMED aqui). ON CONFLICT (pricing_card_mapping_id, external_card_id) DO NOTHING -- uma
-- reexecucao com o mesmo staging determinista produz a mesma identidade, entao a segunda
-- tentativa e um no-op idempotente por construcao, nunca um erro nem uma reescrita.
--
-- Autoria (revisada nesta rodada, substitui o UUID sentinela da versao anterior) -- a funcao
-- agora aceita DOIS parametros de autoria, mutuamente exclusivos, espelhando exatamente o CHECK
-- ck_pricing_card_mapping_confirmation_consistency reescrito pela migration 3957:
--   p_confirmed_by         -- UUID de admin_user real, papel humano (ex.: fluxo administrativo
--                             futuro, nunca o bootstrap automatico).
--   p_confirmed_sync_run_id -- UUID de pricing_sync_run real, papel automatizado (o executor de
--                             bootstrap/CARD_SYNC sempre usa este, nunca o outro).
-- Exatamente um dos dois deve ser informado -- validado explicitamente no topo da funcao via
-- num_nonnulls(), com RAISE EXCEPTION antes de tocar qualquer linha, para falhar cedo com uma
-- mensagem clara em vez de deixar o CHECK da tabela abortar no meio do loop. Nenhum ator
-- ficticio e criado ou referenciado -- p_confirmed_sync_run_id aponta sempre para um
-- pricing_sync_run que realmente existe (o proprio run que esta chamando esta RPC).
--
-- REJECTED nunca e produzido por esta funcao (classification so mapeia para CONFIRMED/PENDING/
-- NOT_FOUND) -- o ramo REJECTED do CHECK de 3957 (exclusivamente humano) e defesa em
-- profundidade para um caminho que este codigo nao usa, nao uma lacuna.

CREATE OR REPLACE FUNCTION public.persist_pricing_bootstrap_card_batch(
  p_pricing_source_id uuid,
  p_confirmed_by uuid,
  p_confirmed_sync_run_id uuid,
  p_rows jsonb
)
RETURNS TABLE(
  card_id uuid,
  action text,
  final_match_status text,
  identity_created boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_item jsonb;
  v_card_id uuid;
  v_classification text;
  v_external_card_id text;
  v_external_card_name text;
  v_match_method text;
  v_match_evidence jsonb;
  v_new_status text;
  v_existing record;
  v_action text;
  v_final_status text;
  v_mapping_id uuid;
  v_identity_rowcount integer;
BEGIN
  IF num_nonnulls(p_confirmed_by, p_confirmed_sync_run_id) <> 1 THEN
    RAISE EXCEPTION 'autoria invalida: exatamente um entre p_confirmed_by (humano) e p_confirmed_sync_run_id (automatizado) deve ser informado -- CHECK ck_pricing_card_mapping_confirmation_consistency (migration 3957) exige num_nonnulls(confirmed_by, confirmed_sync_run_id) = 1 sempre que match_status=CONFIRMED';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  LOOP
    v_card_id := (v_item ->> 'card_id')::uuid;
    v_classification := v_item ->> 'classification';
    v_external_card_id := v_item ->> 'external_card_id';
    v_external_card_name := v_item ->> 'external_card_name';
    v_match_method := v_item ->> 'match_method';
    v_match_evidence := coalesce(v_item -> 'match_evidence', '{}'::jsonb);
    v_identity_rowcount := 0;

    v_new_status := CASE v_classification
      WHEN 'SAFE' THEN 'CONFIRMED'
      WHEN 'AMBIGUOUS' THEN 'PENDING'
      WHEN 'ABSENT' THEN 'NOT_FOUND'
      ELSE NULL
    END;
    IF v_new_status IS NULL THEN
      RAISE EXCEPTION 'classification invalida em p_rows: % (esperado SAFE|AMBIGUOUS|ABSENT)', v_classification;
    END IF;

    SELECT pcm.id, pcm.match_status INTO v_existing
    FROM public.pricing_card_mapping pcm
    WHERE pcm.card_id = v_card_id AND pcm.pricing_source_id = p_pricing_source_id
    FOR UPDATE;

    IF NOT FOUND THEN
      INSERT INTO public.pricing_card_mapping (
        card_id, pricing_source_id, external_card_id, external_card_name,
        match_status, match_method, match_evidence,
        confirmed_at, confirmed_by, confirmed_sync_run_id, last_checked_at
      ) VALUES (
        v_card_id, p_pricing_source_id, v_external_card_id, v_external_card_name,
        v_new_status, v_match_method, v_match_evidence,
        CASE WHEN v_new_status = 'CONFIRMED' THEN now() ELSE NULL END,
        CASE WHEN v_new_status = 'CONFIRMED' THEN p_confirmed_by ELSE NULL END,
        CASE WHEN v_new_status = 'CONFIRMED' THEN p_confirmed_sync_run_id ELSE NULL END,
        CASE WHEN v_new_status = 'NOT_FOUND' THEN now() ELSE NULL END
      )
      RETURNING id INTO v_mapping_id;
      v_action := 'INSERTED';
      v_final_status := v_new_status;

    ELSIF v_existing.match_status IN ('CONFIRMED', 'REJECTED') THEN
      v_mapping_id := v_existing.id;
      v_final_status := v_existing.match_status;
      v_action := CASE WHEN v_existing.match_status = v_new_status
                        THEN 'NOOP_SAME_STATUS'
                        ELSE 'NOOP_KEEP_PROTECTED_STATUS' END;

    ELSIF v_existing.match_status = v_new_status THEN
      v_mapping_id := v_existing.id;
      v_action := 'NOOP_SAME_STATUS';
      v_final_status := v_new_status;

    ELSE
      UPDATE public.pricing_card_mapping
      SET external_card_id = v_external_card_id,
          external_card_name = v_external_card_name,
          match_status = v_new_status,
          match_method = v_match_method,
          match_evidence = v_match_evidence,
          confirmed_at = CASE WHEN v_new_status = 'CONFIRMED' THEN now() ELSE NULL END,
          confirmed_by = CASE WHEN v_new_status = 'CONFIRMED' THEN p_confirmed_by ELSE NULL END,
          confirmed_sync_run_id = CASE WHEN v_new_status = 'CONFIRMED' THEN p_confirmed_sync_run_id ELSE NULL END,
          last_checked_at = CASE WHEN v_new_status = 'NOT_FOUND' THEN now() ELSE last_checked_at END,
          updated_at = now()
      WHERE id = v_existing.id
      RETURNING id INTO v_mapping_id;
      v_action := 'UPGRADED';
      v_final_status := v_new_status;
    END IF;

    IF v_final_status = 'CONFIRMED' AND v_external_card_id IS NOT NULL THEN
      INSERT INTO public.pricing_source_card_identity (
        pricing_card_mapping_id, pricing_source_id, external_card_id, external_card_name,
        match_status, identity_role, match_method, match_evidence,
        confirmed_at, confirmed_by, confirmed_sync_run_id, last_checked_at
      ) VALUES (
        v_mapping_id, p_pricing_source_id, v_external_card_id, v_external_card_name,
        'CONFIRMED', 'PRIMARY', v_match_method, v_match_evidence,
        now(), p_confirmed_by, p_confirmed_sync_run_id, now()
      )
      ON CONFLICT (pricing_card_mapping_id, external_card_id) DO NOTHING;
      GET DIAGNOSTICS v_identity_rowcount = ROW_COUNT;
    END IF;

    RETURN QUERY SELECT v_card_id, v_action, v_final_status, (v_identity_rowcount > 0);
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION public.persist_pricing_bootstrap_card_batch(uuid, uuid, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.persist_pricing_bootstrap_card_batch(uuid, uuid, uuid, jsonb) TO service_role;
