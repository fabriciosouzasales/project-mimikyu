/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2186 - Extend admin_list_catalog_action_log() for Mapping Entities
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-REVISION-02 (§1, §2, §5, §6)
Fase........: PHASE B do rollout — o reader precisa estar pronto ANTES do
              primeiro evento de Impressão existir.
Sucede......: Query 2127 v1.0 (canônica) + a migration não rastreada descrita
              em docs/log.md [2026-08-16] (ver DIVERGÊNCIA abaixo).

Descrição resumida:
Acrescenta branches de entity_label ao reader do Log de Atualizações, para
que Mapeamentos (Impressão e Tipo de Variação) deixem de exibir UUID cru.

-------------------------------------------------------------------------------
DIVERGÊNCIA REPOSITÓRIO × docs/log.md — LEIA ANTES DE EXECUTAR
-------------------------------------------------------------------------------
docs/log.md, entrada [2026-08-16], afirma:

    "Migration 2050_humanize_variant_governance_action_log (CONFIRMADO
     EXECUTADO): admin_list_catalog_action_log() ganhou 3 branches novas
     de entity_label — CARD_VARIANT_TYPE, CATALOG_VARIANT_IMPORT_JOB,
     CARD_VARIANT_TYPE_EXTERNAL_MAPPING"

Mas no repositório:

  - database/schema/2127...sql (v1.0, única definição da função) NÃO tem
    essas três branches — só as 7 originais;
  - NÃO existe nenhum arquivo chamado 2050_humanize_variant_governance_
    action_log; o número 2050 pertence a
    2050_create_admin_delete_card_set_function.sql;
  - nenhum outro arquivo em database/ faz CREATE OR REPLACE desta função.

Ou seja: OU o LIVE tem as três branches e a migration nunca foi promovida
ao repositório, OU o LIVE não as tem e o log.md está errado. Não é
possível decidir sem consultar o banco, o que esta rodada não faz.

É exatamente a classe de erro da Query 2159 v1.0: partir de um arquivo
canônico desatualizado e, sem perceber, REMOVER comportamento que existe
em produção.

Como isto é tratado aqui:

  1. O corpo abaixo é um SUPERCONJUNTO: contém as 7 branches originais
     MAIS as 3 da Governança de Variantes MAIS as novas. Sob qualquer uma
     das duas realidades, nada é removido.
  2. O GUARD extrai por regex TODOS os literais `WHEN '...'` da definição
     REAL da função e aborta se algum deles não estiver na lista conhecida
     desta Query. Se outra frente tiver acrescentado uma branch que este
     arquivo desconhece, a execução para antes de sobrescrever.

Premissa envelhece; guard não.

-------------------------------------------------------------------------------
LABEL DE CARD_VARIANT_TYPE_EXTERNAL_MAPPING — MUDANÇA DELIBERADA
-------------------------------------------------------------------------------
Se a realidade for a primeira, o LIVE hoje monta o label como
"Mapeamento externo — {nome da variação}" (segundo o log.md), isto é:
descreve o ALVO do mapeamento.

Esta Query passa a usar a ASSINATURA EXTERNA (type · foil · subtype ·
stamp), conforme §2 do mandato. Não é regressão: é troca consciente do
critério. Razão: a entidade logada é o MAPEAMENTO, e a identidade de um
mapeamento é a assinatura externa que ele resolve — não o Variant Type
para onde ele aponta. Dois mapeamentos diferentes podem apontar para o
mesmo Variant Type; com o label antigo, ficariam indistinguíveis na
tabela.

Está marcado aqui como decisão, não como detalhe.

-------------------------------------------------------------------------------
DISCIPLINA DE RESOLUÇÃO — IDÊNTICA À DA 2127
-------------------------------------------------------------------------------
Para cada entity_type:

    metadata específica  ->  tabela viva (LEFT JOIN condicional por PK)
                         ->  entity_id::text

Nenhuma branch inventa dado. Nenhuma branch reconstrói assinatura por
heurística: ela usa os campos que a própria escrita já gravou.

-------------------------------------------------------------------------------
PRESERVADO INTEGRALMENTE
-------------------------------------------------------------------------------
Assinatura pública (TEXT, TEXT, TEXT, UUID, INT, INT) · SECURITY DEFINER ·
SET search_path = '' · is_admin() com RAISE EXCEPTION · v_limit em [1,100] ·
v_offset >= 0 · p_search OR contra entity_label/actor_label/action ·
filtros AND · count(*) OVER() como total_count · actor_label via
user_profile · category via internal.catalog_admin_action_category() ·
ORDER BY created_at DESC · REVOKE/GRANT.

A Query 2126 NÃO é tocada (§4 do mandato). A action nova permanece em
'OUTRAS' pelo ELSE deliberado.

-------------------------------------------------------------------------------
ESCOPO ALÉM DO LITERAL — CARD_PRIMARY_SPECIES
-------------------------------------------------------------------------------
O mandato pede Impressão (§1) e Tipo de Variação (§2). Auditando o mesmo
reader, CARD_PRIMARY_SPECIES (Query 2159/6114) também cai no ELSE e
exibe UUID.

Incluí a branch dele porque o próprio argumento do §2 se aplica sem
alteração: não faz sentido tornar um mapeamento legível e deixar o
vizinho exibindo UUID. Custo: um LEFT JOIN condicional por PK em card.

Se você preferir manter o escopo literal, remova a branch
'CARD_PRIMARY_SPECIES' e o LEFT JOIN pspc — nada mais depende deles.

Pré-requisitos:
- Query 2127 - Create admin_list_catalog_action_log() Function.
- Query 2126 - internal.catalog_admin_action_category() (não alterada).
- Query 2185 - Widen Catalog Admin Action Log for Printing Mapping.
- Query 2172 - Card Printing External Mapping (tabela viva do fallback).
===============================================================================
*/

BEGIN;

-- =========================================================================
-- GUARD — nenhuma branch existente pode ser perdida. Fail-closed.
-- =========================================================================
DO $guard$
DECLARE
    v_def TEXT;
    v_unknown TEXT;
    v_secdef BOOLEAN;
    v_config TEXT[];
BEGIN
    SELECT pg_get_functiondef(p.oid), p.prosecdef, p.proconfig
      INTO v_def, v_secdef, v_config
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'admin_list_catalog_action_log';

    IF v_def IS NULL THEN
        RAISE EXCEPTION 'READER_NOT_FOUND: public.admin_list_catalog_action_log() não existe. A Query 2127 foi aplicada? STOP.';
    END IF;

    IF NOT v_secdef OR NOT (v_config @> ARRAY['search_path=""']) THEN
        RAISE EXCEPTION 'READER_SECURITY_DRIFT: a função viva não é SECURITY DEFINER com search_path vazio. Estado inesperado — reauditar antes de sobrescrever. STOP.';
    END IF;

    -- Extrai TODOS os literais de branch da definição REAL e confronta
    -- com a lista conhecida desta Query. Qualquer branch desconhecida
    -- seria silenciosamente destruída pelo CREATE OR REPLACE abaixo.
    SELECT string_agg(DISTINCT t, ', ' ORDER BY t) INTO v_unknown
      FROM (
            SELECT (regexp_matches(v_def, 'WHEN\s+''([A-Z_]+)''', 'g'))[1] AS t
      ) AS found
     WHERE t NOT IN (
            'GAME', 'EXPANSION', 'CARD_SET', 'CARD', 'CATALOG_IMPORT_JOB',
            'RARITY', 'RARITY_EXTERNAL_MAPPING',
            'CARD_VARIANT_TYPE', 'CATALOG_VARIANT_IMPORT_JOB',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING',
            'CARD_PRIMARY_SPECIES',
            'CARD_PRINTING_EXTERNAL_MAPPING'
     );

    IF v_unknown IS NOT NULL THEN
        RAISE EXCEPTION 'READER_UNKNOWN_BRANCH: a função viva resolve entity_type(s) que esta Query desconhece: %. Sobrescrevê-la removeria essa resolução. STOP — incorporar a(s) branch(es) a este arquivo antes de executar.', v_unknown;
    END IF;
END;
$guard$;

CREATE OR REPLACE FUNCTION public.admin_list_catalog_action_log(
    p_search TEXT DEFAULT NULL,
    p_entity_type TEXT DEFAULT NULL,
    p_action TEXT DEFAULT NULL,
    p_actor_id UUID DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    created_at TIMESTAMPTZ,
    actor_id UUID,
    actor_label TEXT,
    entity_type TEXT,
    entity_id UUID,
    entity_label TEXT,
    action TEXT,
    category TEXT,
    metadata JSONB,
    total_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_limit INT;
    v_offset INT;
    v_search TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_LIST_CATALOG_ACTION_LOG_FORBIDDEN: acesso restrito a administradores.';
    END IF;

    v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
    v_offset := GREATEST(COALESCE(p_offset, 0), 0);
    v_search := NULLIF(BTRIM(p_search), '');

    RETURN QUERY
    WITH resolved AS (
        SELECT
            l.id,
            l.created_at,
            l.actor_id,
            COALESCE(up.display_name, up.username) AS actor_label,
            l.entity_type,
            l.entity_id,
            CASE l.entity_type
                -- ===== 7 branches originais (Query 2127) — intactas =====
                WHEN 'GAME' THEN COALESCE(l.metadata->>'name', g.name, l.entity_id::text)
                WHEN 'EXPANSION' THEN COALESCE(l.metadata->>'name', e.name, l.entity_id::text)
                WHEN 'CARD_SET' THEN COALESCE(l.metadata->>'name', l.metadata->>'card_set_name', cs.name, l.entity_id::text)
                WHEN 'CARD' THEN COALESCE(l.metadata->>'name', c.name, l.entity_id::text)
                WHEN 'CATALOG_IMPORT_JOB' THEN COALESCE(l.metadata->>'card_set_name', job_cs.name, l.entity_id::text)
                WHEN 'RARITY' THEN COALESCE(l.metadata->>'name', rar.name, l.entity_id::text)
                WHEN 'RARITY_EXTERNAL_MAPPING' THEN COALESCE(l.metadata->>'external_value', rem.external_value, l.entity_id::text)

                -- ===== Governança de Variantes (ADR-028) =====
                -- Reconciliadas aqui; ver DIVERGÊNCIA no cabeçalho.
                WHEN 'CARD_VARIANT_TYPE'
                    THEN COALESCE(l.metadata->>'name', cvt.name, l.entity_id::text)

                WHEN 'CATALOG_VARIANT_IMPORT_JOB'
                    THEN COALESCE(l.metadata->>'card_set_name', vjob_cs.name, l.entity_id::text)

                -- Assinatura externa que o mapeamento resolve.
                -- metadata -> tabela viva -> UUID.
                WHEN 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING'
                    THEN COALESCE(
                        NULLIF(concat_ws(' · ',
                            l.metadata->>'external_type',
                            l.metadata->>'external_foil',
                            l.metadata->>'external_subtype',
                            CASE WHEN jsonb_typeof(l.metadata->'external_stamp') = 'array'
                                 THEN NULLIF(array_to_string(
                                        ARRAY(SELECT jsonb_array_elements_text(l.metadata->'external_stamp')),
                                        ' + '), '')
                                 ELSE NULL END
                        ), ''),
                        NULLIF(concat_ws(' · ',
                            vtem.external_type,
                            vtem.external_foil,
                            vtem.external_subtype,
                            NULLIF(array_to_string(vtem.external_stamp, ' + '), '')
                        ), ''),
                        l.entity_id::text
                    )

                -- ===== Pokédex (fora do escopo literal — ver cabeçalho) =====
                WHEN 'CARD_PRIMARY_SPECIES'
                    THEN COALESCE(l.metadata->>'name', pspc.name, l.entity_id::text)

                -- ===== Impressão (esta frente) =====
                -- A entidade e UM token externo: raw_field + token.
                -- Exemplo: "subtype · SHADOWLESS-RED-CHEEK".
                WHEN 'CARD_PRINTING_EXTERNAL_MAPPING'
                    THEN COALESCE(
                        NULLIF(concat_ws(' · ',
                            l.metadata->>'raw_field',
                            l.metadata->>'normalized_token'
                        ), ''),
                        NULLIF(concat_ws(' · ',
                            pem.raw_field,
                            pem.normalized_token
                        ), ''),
                        l.entity_id::text
                    )

                ELSE l.entity_id::text
            END AS entity_label,
            l.action,
            internal.catalog_admin_action_category(l.action) AS category,
            l.metadata
        FROM public.catalog_admin_action_log l
        LEFT JOIN public.user_profile up ON up.id = l.actor_id
        LEFT JOIN public.game g ON l.entity_type = 'GAME' AND g.id = l.entity_id
        LEFT JOIN public.expansion e ON l.entity_type = 'EXPANSION' AND e.id = l.entity_id
        LEFT JOIN public.card_set cs ON l.entity_type = 'CARD_SET' AND cs.id = l.entity_id
        LEFT JOIN public.card c ON l.entity_type = 'CARD' AND c.id = l.entity_id
        LEFT JOIN public.catalog_import_job job ON l.entity_type = 'CATALOG_IMPORT_JOB' AND job.id = l.entity_id
        LEFT JOIN public.card_set job_cs ON job_cs.id = job.card_set_id
        LEFT JOIN public.rarity rar ON l.entity_type = 'RARITY' AND rar.id = l.entity_id
        LEFT JOIN public.rarity_external_mapping rem ON l.entity_type = 'RARITY_EXTERNAL_MAPPING' AND rem.id = l.entity_id
        -- Novos, todos condicionais por entity_type e por PK.
        LEFT JOIN public.card_variant_type cvt
               ON l.entity_type = 'CARD_VARIANT_TYPE' AND cvt.id = l.entity_id
        LEFT JOIN public.catalog_variant_import_job vjob
               ON l.entity_type = 'CATALOG_VARIANT_IMPORT_JOB' AND vjob.id = l.entity_id
        LEFT JOIN public.card_set vjob_cs ON vjob_cs.id = vjob.card_set_id
        LEFT JOIN public.card_variant_type_external_mapping vtem
               ON l.entity_type = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING' AND vtem.id = l.entity_id
        LEFT JOIN public.card pspc
               ON l.entity_type = 'CARD_PRIMARY_SPECIES' AND pspc.id = l.entity_id
        LEFT JOIN public.card_printing_external_mapping pem
               ON l.entity_type = 'CARD_PRINTING_EXTERNAL_MAPPING' AND pem.id = l.entity_id
    )
    SELECT
        r.id, r.created_at, r.actor_id, r.actor_label,
        r.entity_type, r.entity_id, r.entity_label, r.action, r.category, r.metadata,
        count(*) OVER() AS total_count
    FROM resolved r
    WHERE (p_entity_type IS NULL OR r.entity_type = p_entity_type)
      AND (p_action IS NULL OR r.action = p_action)
      AND (p_actor_id IS NULL OR r.actor_id = p_actor_id)
      AND (
          v_search IS NULL
          OR r.entity_label ILIKE '%' || v_search || '%'
          OR r.actor_label ILIKE '%' || v_search || '%'
          OR r.action ILIKE '%' || v_search || '%'
      )
    ORDER BY r.created_at DESC
    LIMIT v_limit
    OFFSET v_offset;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_list_catalog_action_log(TEXT, TEXT, TEXT, UUID, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_catalog_action_log(TEXT, TEXT, TEXT, UUID, INT, INT) TO authenticated;

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   CREATE OR REPLACE FUNCTION + REVOKE + GRANT.
--   12 branches de entity_label (7 originais + 5 novas/reconciliadas).
--   Assinatura, segurança, paginação, filtros e total_count inalterados.
--
-- PERFORMANCE (§6 do mandato):
--   Os 5 JOINs novos seguem o mesmo padrão dos 9 existentes: LEFT JOIN
--   condicionado por entity_type e casado por PK (t.id = l.entity_id).
--   Set-based, um nested loop por branch, nenhuma correlação por linha
--   contra tabela. Nenhum N+1.
--
--   A única expressão por linha e a expansao de metadata->'external_stamp'
--   na branch de CARD_VARIANT_TYPE_EXTERNAL_MAPPING. Ela vive DENTRO do
--   CASE, que faz curto-circuito: so e avaliada para linhas daquele
--   entity_type (68 linhas historicas conhecidas). Nao toca tabela.
--
--   Cardinalidades das tabelas novas: card_printing_external_mapping ~5,
--   card_variant_type_external_mapping ~69, card_variant_type ~79,
--   catalog_variant_import_job dezenas, card (PK lookup pontual).
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Secao S26 (BLOCO I,
--   casos L01 a L07).
-- ============================================================================
