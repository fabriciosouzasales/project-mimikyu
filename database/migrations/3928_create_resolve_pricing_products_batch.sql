-- STATUS: CONFIRMADO EXECUTADO -- aplicada em producao via Supabase MCP em 2026-08-21
-- (correcao R1/R5, Incremento de Atualizacao Diaria JustTCG). Validada em BEGIN/ROLLBACK
-- (18 cenarios A-R) antes da aplicacao real; revalidada em introspeccao somente leitura
-- apos a aplicacao (grants, volatilidade, security mode, search_path, plano de execucao
-- via EXPLAIN). Registrada no relatorio final desta rodada de implementacao R1/R5.
--
-- Contexto: defeito R1 (runs a31742a4 e seguintes, 2026-08-21, SV2-SV7/SV9/SWSH1-5/SWSH7)
-- -- o caminho antigo (findExistingProducts/insertProducts em
-- supabase/functions/_shared/pricing-justtcg-refresh/{port,supabase-adapter,core}.ts)
-- resolvia produto por pricing_source_card_identity_id. Quando a identity CONFIRMED atual
-- de um mapping divergia da identity sob a qual o produto ja fora gravado (ex.: apos um
-- reparo de identidade), o produto existente pela chave economica real
-- (pricing_card_mapping_id, external_product_id -- uq_pricing_product_mapping_external)
-- nao era reconhecido: o run tentava um INSERT duplicado, recebia 23505 e derrubava a onda
-- inteira (status=FAILED, observacao de preco perdida).
--
-- Esta migration cria a RPC resolve_pricing_products_batch(p_rows jsonb) -- unico ponto de
-- resolucao de produto do refresh diario a partir de agora (Alternativa C revisada,
-- aprovada por Fabrício): resolve SEMPRE pela chave economica real
-- (pricing_card_mapping_id, external_product_id), nunca por identity_id. Transacional,
-- maximo 200 pares por chamada. Fluxo interno em DUAS instrucoes SQL separadas (nunca uma
-- unica CTE) -- cada uma recebe um snapshot novo sob READ COMMITTED, o que garante que a
-- segunda instrucao (SELECT/JOIN de resolucao) sempre enxerga uma linha inserida por uma
-- transacao concorrente que venceu uma corrida de conflito durante o INSERT da primeira:
--   1. INSERT ... ON CONFLICT ON CONSTRAINT uq_pricing_product_mapping_external DO NOTHING
--      RETURNING -- registra exatamente quais pares eram genuinamente NEW.
--   2. SELECT/JOIN contra pricing_product pelos mesmos pares -- resolve TODOS os pares
--      pedidos (NEW + ja existentes), classificando cada um como NEW ou REUSE.
-- Retorna exatamente uma linha por par economico recebido (invariante de cardinalidade
-- validada dentro da propria funcao -- aborta a transacao em caso de par nao resolvido,
-- mais de uma linha para o mesmo par, ou classificacao fora de NEW/REUSE).
--
-- REUSE NUNCA faz UPDATE nem reparenting -- devolve o produto ja armazenado tal como esta
-- (pricing_source_card_identity_id e source_printing_label originais, nunca sobrescritos).
-- Divergencia entre a identity/printing_label candidata e a armazenada e apenas
-- SINALIZADA nos campos de retorno (pricing_source_card_identity_id armazenado,
-- candidate_printing_label x stored_printing_label) -- a decisao de emitir um aviso
-- operacional (IDENTITY_MISMATCH_ON_REUSE / PRINTING_LABEL_MISMATCH_ON_REUSE, nunca
-- hardFailure) cabe a core.ts, nunca a esta funcao.
--
-- Validacao minima de payload embutida na funcao (nunca delegada ao chamador): p_rows deve
-- ser array JSON, maximo 200 elementos, cada elemento objeto com mapping_id/identity_id
-- (UUID valido) e external_product_id/source_printing_label (texto nao vazio); par
-- (mapping_id, external_product_id) duplicado no mesmo payload aborta com
-- RESOLVE_PRODUCTS_BATCH_DUPLICATE_PAIR_IN_PAYLOAD. Nenhuma mensagem de erro expoe SQLSTATE
-- ou texto cru do driver -- mesma disciplina ja usada em admin_create_card/
-- batch_update_pricing_card_mapping_status (RAISE EXCEPTION 'CODIGO_PROPRIO: mensagem em
-- pt-BR, %', valor).
--
-- Colunas temporarias (_rppb_input/_rppb_new_pairs/_rppb_result) usam
-- DROP TABLE IF EXISTS pg_temp._nome seguido de CREATE TEMP TABLE ... ON COMMIT DROP --
-- garante estado limpo tanto na primeira quanto em chamadas repetidas na mesma sessao/
-- transacao, sem depender de nenhuma suposicao implicita sobre colisao de nome.
--
-- LANGUAGE plpgsql, VOLATILE, SECURITY INVOKER, search_path fixo ('public', 'pg_temp').
-- Acesso restrito a service_role -- REVOKE ALL FROM PUBLIC, sem grant a anon/authenticated.
-- Chave economica (pricing_card_mapping_id, external_product_id) permanece exatamente a
-- mesma ja usada por uq_pricing_product_mapping_external desde a era P4 -- nenhuma mudanca
-- de schema fisico nesta migration, apenas a nova funcao de resolucao em lote.

CREATE OR REPLACE FUNCTION public.resolve_pricing_products_batch(p_rows jsonb)
RETURNS TABLE(
  product_id uuid,
  pricing_card_mapping_id uuid,
  external_product_id text,
  pricing_source_card_identity_id uuid,
  classification text,
  candidate_printing_label text,
  stored_printing_label text
)
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_row_count integer;
  v_elem jsonb;
  v_idx integer;
  v_mapping_id uuid;
  v_identity_id uuid;
  v_external_product_id text;
  v_source_printing_label text;
  v_raw_text text;
BEGIN
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'RESOLVE_PRODUCTS_BATCH_INVALID_PAYLOAD_NOT_ARRAY: p_rows deve ser um array JSON.';
  END IF;
  v_row_count := jsonb_array_length(p_rows);
  IF v_row_count = 0 THEN RETURN; END IF;
  IF v_row_count > 200 THEN
    RAISE EXCEPTION 'RESOLVE_PRODUCTS_BATCH_PAYLOAD_TOO_LARGE: máximo 200 linhas por chamada, recebido %.', v_row_count;
  END IF;

  DROP TABLE IF EXISTS pg_temp._rppb_input;
  CREATE TEMP TABLE _rppb_input (
    row_index integer PRIMARY KEY, mapping_id uuid NOT NULL, identity_id uuid NOT NULL,
    external_product_id text NOT NULL, source_printing_label text NOT NULL
  ) ON COMMIT DROP;
  DROP TABLE IF EXISTS pg_temp._rppb_new_pairs;
  CREATE TEMP TABLE _rppb_new_pairs (mapping_id uuid NOT NULL, external_product_id text NOT NULL) ON COMMIT DROP;
  DROP TABLE IF EXISTS pg_temp._rppb_result;
  CREATE TEMP TABLE _rppb_result (
    product_id uuid NOT NULL, pricing_card_mapping_id uuid NOT NULL, external_product_id text NOT NULL,
    pricing_source_card_identity_id uuid, classification text NOT NULL,
    candidate_printing_label text NOT NULL, stored_printing_label text NOT NULL
  ) ON COMMIT DROP;

  v_idx := 0;
  FOR v_elem IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    IF jsonb_typeof(v_elem) <> 'object' THEN
      RAISE EXCEPTION 'RESOLVE_PRODUCTS_BATCH_ROW_NOT_OBJECT: linha % não é um objeto JSON.', v_idx;
    END IF;
    v_raw_text := v_elem->>'mapping_id';
    IF v_raw_text IS NULL OR btrim(v_raw_text) = '' THEN
      RAISE EXCEPTION 'RESOLVE_PRODUCTS_BATCH_MAPPING_ID_REQUIRED: linha % sem mapping_id.', v_idx;
    END IF;
    BEGIN
      v_mapping_id := v_raw_text::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'RESOLVE_PRODUCTS_BATCH_MAPPING_ID_INVALID_UUID: linha % com mapping_id inválido.', v_idx;
    END;
    v_raw_text := v_elem->>'identity_id';
    IF v_raw_text IS NULL OR btrim(v_raw_text) = '' THEN
      RAISE EXCEPTION 'RESOLVE_PRODUCTS_BATCH_IDENTITY_ID_REQUIRED: linha % sem identity_id.', v_idx;
    END IF;
    BEGIN
      v_identity_id := v_raw_text::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'RESOLVE_PRODUCTS_BATCH_IDENTITY_ID_INVALID_UUID: linha % com identity_id inválido.', v_idx;
    END;
    v_external_product_id := v_elem->>'external_product_id';
    IF v_external_product_id IS NULL OR btrim(v_external_product_id) = '' THEN
      RAISE EXCEPTION 'RESOLVE_PRODUCTS_BATCH_EXTERNAL_PRODUCT_ID_REQUIRED: linha % sem external_product_id.', v_idx;
    END IF;
    v_source_printing_label := v_elem->>'source_printing_label';
    IF v_source_printing_label IS NULL OR btrim(v_source_printing_label) = '' THEN
      RAISE EXCEPTION 'RESOLVE_PRODUCTS_BATCH_SOURCE_PRINTING_LABEL_REQUIRED: linha % sem source_printing_label.', v_idx;
    END IF;
    IF EXISTS (SELECT 1 FROM _rppb_input i WHERE i.mapping_id = v_mapping_id AND i.external_product_id = v_external_product_id) THEN
      RAISE EXCEPTION 'RESOLVE_PRODUCTS_BATCH_DUPLICATE_PAIR_IN_PAYLOAD: par (mapping_id=%, external_product_id=%) repetido no mesmo payload.', v_mapping_id, v_external_product_id;
    END IF;
    INSERT INTO _rppb_input (row_index, mapping_id, identity_id, external_product_id, source_printing_label)
    VALUES (v_idx, v_mapping_id, v_identity_id, v_external_product_id, v_source_printing_label);
    v_idx := v_idx + 1;
  END LOOP;

  WITH ins AS (
    INSERT INTO public.pricing_product AS ppins (
      pricing_card_mapping_id, pricing_source_card_identity_id, external_product_id,
      source_printing_label, language_status, language_id
    )
    SELECT i.mapping_id, i.identity_id, i.external_product_id, i.source_printing_label, 'UNDETERMINED', NULL
    FROM _rppb_input i
    ON CONFLICT ON CONSTRAINT uq_pricing_product_mapping_external DO NOTHING
    RETURNING ppins.pricing_card_mapping_id, ppins.external_product_id
  )
  INSERT INTO _rppb_new_pairs (mapping_id, external_product_id)
  SELECT ins.pricing_card_mapping_id, ins.external_product_id FROM ins;

  INSERT INTO _rppb_result (
    product_id, pricing_card_mapping_id, external_product_id,
    pricing_source_card_identity_id, classification, candidate_printing_label, stored_printing_label
  )
  SELECT pp.id, pp.pricing_card_mapping_id, pp.external_product_id, pp.pricing_source_card_identity_id,
    CASE WHEN np.mapping_id IS NOT NULL THEN 'NEW' ELSE 'REUSE' END, i.source_printing_label, pp.source_printing_label
  FROM _rppb_input i
  JOIN public.pricing_product pp ON pp.pricing_card_mapping_id = i.mapping_id AND pp.external_product_id = i.external_product_id
  LEFT JOIN _rppb_new_pairs np ON np.mapping_id = i.mapping_id AND np.external_product_id = i.external_product_id;

  IF (SELECT count(*) FROM _rppb_result) <> v_row_count THEN
    RAISE EXCEPTION 'RESOLVE_PRODUCTS_BATCH_CARDINALITY_MISMATCH: esperado % linha(s), resolvido %.', v_row_count, (SELECT count(*) FROM _rppb_result);
  END IF;
  IF EXISTS (SELECT 1 FROM _rppb_result r GROUP BY r.pricing_card_mapping_id, r.external_product_id HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'RESOLVE_PRODUCTS_BATCH_CARDINALITY_MISMATCH: par duplicado no resultado.';
  END IF;
  IF EXISTS (SELECT 1 FROM _rppb_result r WHERE r.classification NOT IN ('NEW', 'REUSE')) THEN
    RAISE EXCEPTION 'RESOLVE_PRODUCTS_BATCH_INVALID_CLASSIFICATION: classificação fora de NEW/REUSE.';
  END IF;
  RETURN QUERY SELECT * FROM _rppb_result;
END;
$function$;

COMMENT ON FUNCTION public.resolve_pricing_products_batch(jsonb) IS
  'R1/R5 (correção 2026-08-21, Incremento P15) — resolve em lote (máx. 200 pares/chamada) '
  'produtos pricing_product pela chave econômica REAL (pricing_card_mapping_id, '
  'external_product_id — uq_pricing_product_mapping_external), classificando cada par como '
  'NEW ou REUSE. Duas instruções SQL internas (INSERT...ON CONFLICT DO NOTHING RETURNING '
  'via CTE gravável, depois um SELECT/JOIN separado com snapshot novo) — nunca uma CTE '
  'única, para garantir que REUSE por corrida de concorrência veja o commit da transação '
  'vencedora. Nunca UPDATE/reparenting: REUSE sempre devolve product_id/identity/'
  'printing_label armazenados, tal como estão; divergências são só sinalizadas nos campos '
  'de retorno para o chamador decidir warnings (nunca mutação aqui). Invariante 1:1 (N '
  'pares válidos -> N linhas), aborta em caso de retorno parcial. SECURITY INVOKER, '
  'VOLATILE, search_path fixo, EXECUTE restrito a service_role. Substitui a resolução por '
  'identity_id que causava R1 (ver ADR-032/05f-pricing.md).';

REVOKE ALL ON FUNCTION public.resolve_pricing_products_batch(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_pricing_products_batch(jsonb) TO service_role;
