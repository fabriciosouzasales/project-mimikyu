/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6116 - Create resolve_card_primary_species_for_catalog_import_job() Function
Versão......: 1.2
Status......: PROPOSTA — NÃO EXECUTADO (staging desta rodada de auditoria;
               NÃO promovido para database/schema/, NÃO chamado por nenhum
               código real ainda)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em
               COLLECTIONS-POKEDEX-FATIA-C-INCREMENTAL-INTEGRATION-AUDIT-01;
               revisado em ...-REVISION-01; revisado em
               ...-FINAL-CHECK-01)

Correção v1.2 (FINAL-CHECK-01) — BLOCKER real encontrado e fechado antes
da implementação: v1.1 NUNCA verificava catalog_import_job.source. Ela
lia catalog_import_row.raw_data->'dexId' para QUALQUER job que
tivesse Cards POKEMON com resulting_card_id, inclusive um job com
source = 'PDF'. catalog_import_job.source é restrito a exatamente
'PDF' ou 'TCGDEX' (CHECK ck_catalog_import_job_source, Query 2060) — a
semântica de dexId em raw_data é inteiramente específica do payload da
API TCGdex (Query 6115/6112, cabeçalho: "raw_data->'dexId', bruto, como
observado na TCGdex"); um job PDF nunca tem esse payload por origem, e
mesmo que raw_data de um job PDF viesse a conter uma chave 'dexId' por
coincidência de schema (não é o caso hoje, mas não é uma garantia
estrutural), interpretá-la como evidência de Species seria uma
inferência sem base — o `raw_data` de um job PDF vem de um pipeline de
extração de checklist completamente diferente (fora do escopo TCGdex).

O motivo pelo qual isso importava na prática, não só em teoria:
`revalidate-catalog-import-rows` (Fluxo B, REVISION-01) é **genérico**
— `listRevalidatableJobs()` não filtra por source, processa qualquer
job elegível (`FAILED` rows revalidáveis), PDF ou TCGDEX. O Fluxo A
(`confirmarImportacao()`) vive na rota `/catalogo/importar-cartas/
tcgdex/`, então hoje só é exercitado por jobs TCGDEX na prática — mas
6116 não pode depender da disciplina do caminho de código que a chama
para se manter correta; o guard precisa estar na própria função,
único ponto de verdade desta orquestração.

Correção: 6116 agora CARREGA o catalog_import_job completo (não só
verifica existência) e, se `source <> 'TCGDEX'`, retorna
IMEDIATAMENTE com `status = 'SOURCE_NOT_TCGDEX'` — sem tocar em
raw_data->'dexId', sem chamar resolve_card_primary_species_bulk()
(Query 6115), sem nenhuma escrita em card_primary_species. Estado
explícito, nunca um resultado zerado indistinguível de "job TCGDEX sem
Cards elegíveis" (ver nova coluna `status` abaixo).

CONTRATO DE RETORNO AMPLIADO (v1.2 adiciona `status`, discutido e
fechado nesta correção — v1.0/v1.1 só tinham os contadores + details,
sem um sinal de estado no nível do job):
- 'SOURCE_NOT_TCGDEX': job existe, mas source <> 'TCGDEX' — nenhum
  processamento ocorreu. considered_count = 0, todos os demais
  contadores = 0, details = '[]'.
- 'NO_ELIGIBLE_CARDS': job é TCGDEX, mas nenhuma Card POKEMON com
  resulting_card_id foi encontrada (ex.: Card Set 100% TRAINER/ENERGY,
  ou nenhuma linha confirmada ainda). Mesma forma de retorno zerada,
  status diferente de SOURCE_NOT_TCGDEX para o chamador poder
  distinguir as duas causas se precisar.
- 'PROCESSED': job é TCGDEX e havia pelo menos uma Card POKEMON
  elegível — resolve_card_primary_species_bulk() foi chamada; os
  contadores/details refletem o retorno dela, repassado integralmente.
`p_job_id` inexistente continua sendo RAISE EXCEPTION (erro de
chamador, categoria diferente de "job válido com source errada", que é
uma condição normal de operação, não um bug de quem chama).

Descrição...:
Ponto de integração único e centralizado entre o pipeline de confirmação
de importação de Cards (admin_confirm_catalog_import(), Query 2082) e a
resolução automática de Card Primary Species (resolve_card_primary_
species_bulk(), Query 6115) — fecha o item "integração incremental" da
Fatia C sem duplicar lógica de agregação de evidência em mais de um
lugar e sem introduzir um terceiro caminho de escrita direta em
card_primary_species (ver "Relação com os invariantes da Fatia C"
abaixo).

PREMISSA CONFIRMADA (AUDIT-01, mantida): o fluxo real de importação é
    TCGdex → import-catalog-cards (Edge Function, staging)
    → catalog_import_row (staging efêmero)
    → decisão humana (admin_decide_catalog_import_row(), Query 2081)
    → admin_confirm_catalog_import() (Query 2082)
    → catalog_import_row.resulting_card_id (Card canônica persistida)
Não existe hoje nenhum ponto, dentro do próprio import-catalog-cards,
em que uma Card já tenha um id definitivo em public.card — a Card só
passa a existir de fato numa chamada a admin_confirm_catalog_import(),
que tem hoje EXATAMENTE DOIS callers reais (REVISION-01):

  A. confirmarImportacao() (Server Action, web/app/catalogo/importar-
     cartas/tcgdex/actions.ts:267-330) — rota específica de TCGdex;
     na prática só processa jobs source='TCGDEX', mas 6116 não confia
     nisso (ver correção v1.2 acima).
  B. confirmCatalogImport() (supabase/functions/revalidate-catalog-
     import-rows/services/database.ts:233-245) — GENÉRICO, não filtra
     por source; é exatamente por causa deste caller que o guard de
     source em 6116 é necessário, não decorativo.

admin_decide_catalog_import_row() (Query 2081) e as duas funções de
revalidação (svc_apply_catalog_import_revalidation/internal_persist_
catalog_import_revalidation, Queries 2105/2106) NUNCA tocam
resulting_card_id — resulting_card_id é escrito exclusivamente por
admin_confirm_catalog_import() (Query 2082).

CONTRATO (v1.1 REVISION-01 removeu p_row_ids; v1.2 FINAL-CHECK-01
adiciona o guard de source e a coluna `status`):
- p_job_id (obrigatório): escopa a leitura a um catalog_import_job
  específico — nunca varre o catálogo inteiro.

ALGORITMO (v1.2):
0. Carrega o catalog_import_job de p_job_id (não só verifica
   existência). source <> 'TCGDEX' → retorna imediatamente com
   status = 'SOURCE_NOT_TCGDEX', sem tocar em catalog_import_row,
   sem chamar 6115, sem escrita.
1. (source = 'TCGDEX' a partir daqui) Lê catalog_import_row do job
   inteiro com resulting_card_id IS NOT NULL — nunca matched_card_id.
2. Filtra somente Cards cuja card_category.code = 'POKEMON'.
3. Extrai evidência exclusivamente de raw_data->'dexId' (nenhuma
   inferência por nome de Card ou de Species) — seguro de fazer aqui
   porque o guard do passo 0 já garantiu que este raw_data é payload
   TCGdex.
4. Agrega, por Card (resulting_card_id), o conjunto DISTINCT de dexIds
   observados entre as linhas do job.
5. Delega inteiramente a decisão a resolve_card_primary_species_bulk()
   (Query 6115) — nunca reimplementada aqui.
6. Guard de tamanho: job com mais de c_max_batch_size Cards POKEMON
   elegíveis é rejeitado com RAISE EXCEPTION ANTES de chamar 6115.
7. Nunca gates por catalog_import_job.status (STAGED/CONFIRMING/
   COMPLETED/COMPLETED_WITH_ERRORS) — deliberado, ver README "jobs
   parcialmente confirmados". Isso é ortogonal ao guard de `source`
   do passo 0 — um é sobre O QUE o job é (canal de origem, imutável),
   o outro é sobre EM QUE PONTO do ciclo de vida ele está (mutável,
   não relevante para esta função).

RELAÇÃO COM OS INVARIANTES DA FATIA C: o invariante "só duas funções
SECURITY DEFINER podem escrever em card_primary_species — Queries
6114/6115" permanece verdadeiro — esta função NUNCA executa INSERT/
UPDATE/DELETE em card_primary_species diretamente; delega 100% a
resolve_card_primary_species_bulk() (Query 6115). O guard de source
reforça isso: para um job PDF, nem sequer a delegação a 6115 ocorre.

ERRO NÃO-BLOQUEANTE ("REQUISITO CRÍTICO", REVISION-01): chamada em RPC
SEPARADA, depois que admin_confirm_catalog_import() já commitou — em
NENHUM dos dois callers uma falha aqui reverte a confirmação. O guard
de source NUNCA levanta exceção (é um estado normal e esperado quando
o Fluxo B genérico processa um job PDF) — só o guard de tamanho
(>10000) e parâmetros claramente inválidos (p_job_id ausente/
inexistente) levantam RAISE EXCEPTION.

IDEMPOTÊNCIA: leitura pura + delegação a uma função já comprovadamente
idempotente (6115); chamar repetidamente para o mesmo job, inclusive um
job PDF (sempre retornando SOURCE_NOT_TCGDEX, sempre sem escrita), é
sempre seguro.

Pré-requisitos:
- Query 6112/6113/6114/6115 - Fatia C completa (Card Primary Species).
- Query 2060 - Create Catalog Import Job Table (source, CHECK PDF/TCGDEX).
- Query 2070/2081/2082 - Catalog Import Row/Decide/Confirm.
- Query 1060 - Create is_admin() Function.
===============================================================================
*/

BEGIN;

-- v1.1 tinha assinatura (UUID, UUID[]) antes de p_row_ids ser removido; v1.2
-- mantém (UUID) mas o DROP abaixo cobre defensivamente as duas formas
-- anteriores — nenhuma delas foi promovida/executada em lugar nenhum.
DROP FUNCTION IF EXISTS public.resolve_card_primary_species_for_catalog_import_job(UUID, UUID[]);

CREATE OR REPLACE FUNCTION public.resolve_card_primary_species_for_catalog_import_job(
    p_job_id UUID
)
RETURNS TABLE (
    status TEXT,
    considered_count INTEGER,
    resolved_count INTEGER,
    unchanged_count INTEGER,
    unresolved_count INTEGER,
    ambiguous_count INTEGER,
    conflict_count INTEGER,
    failed_count INTEGER,
    details JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    -- Mesmo guard operacional de resolve_card_primary_species_bulk() (Query
    -- 6115) — rejeitado aqui, ANTES de montar o payload, para uma mensagem
    -- de erro específica deste ponto de integração.
    c_max_batch_size CONSTANT INTEGER := 10000;

    v_job public.catalog_import_job%ROWTYPE;
    v_payload JSONB;
    v_payload_count INTEGER;
    v_bulk_result RECORD;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'RESOLVE_CARD_PRIMARY_SPECIES_FOR_CATALOG_IMPORT_JOB_FORBIDDEN: apenas administradores podem disparar esta resolução.';
    END IF;

    IF p_job_id IS NULL THEN
        RAISE EXCEPTION 'RESOLVE_CARD_PRIMARY_SPECIES_FOR_CATALOG_IMPORT_JOB_MISSING_JOB: p_job_id é obrigatório.';
    END IF;

    SELECT * INTO v_job FROM public.catalog_import_job WHERE id = p_job_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'RESOLVE_CARD_PRIMARY_SPECIES_FOR_CATALOG_IMPORT_JOB_NOT_FOUND: nenhum job encontrado para o id informado (%).', p_job_id;
    END IF;

    -- GUARD (v1.2, FINAL-CHECK-01): a semântica de raw_data->'dexId' é
    -- inteiramente específica de jobs TCGDEX. revalidate-catalog-import-rows
    -- (Fluxo B) é genérico e não restringe jobs a TCGDEX — este guard é a
    -- única barreira real contra interpretar payload de origem PDF como
    -- evidência de Species. Nunca RAISE aqui: é um estado normal, não um erro
    -- de chamador (ver cabeçalho, "ERRO NÃO-BLOQUEANTE").
    IF v_job.source <> 'TCGDEX' THEN
        RETURN QUERY SELECT 'SOURCE_NOT_TCGDEX'::TEXT, 0, 0, 0, 0, 0, 0, 0, '[]'::jsonb;
        RETURN;
    END IF;

    -- Deliberadamente SEM checagem de catalog_import_job.status aqui — ver
    -- cabeçalho, "jobs parcialmente confirmados". Ortogonal ao guard de
    -- source acima (ciclo de vida vs. canal de origem).

    WITH job_rows AS (
        SELECT DISTINCT r.resulting_card_id AS card_id
        FROM public.catalog_import_row r
        JOIN public.card c ON c.id = r.resulting_card_id
        JOIN public.card_category cc ON cc.id = c.category_id
        WHERE r.job_id = p_job_id
          AND r.resulting_card_id IS NOT NULL
          AND cc.code = 'POKEMON'
    ),
    evidence AS (
        SELECT
            r.resulting_card_id AS card_id,
            array_agg(DISTINCT (elem)::int) AS distinct_dex_ids
        FROM public.catalog_import_row r
        CROSS JOIN LATERAL jsonb_array_elements_text(r.raw_data->'dexId') AS elem
        WHERE r.raw_data ? 'dexId'
          AND r.resulting_card_id IN (SELECT card_id FROM job_rows)
        GROUP BY r.resulting_card_id
    )
    SELECT
        jsonb_agg(
            jsonb_build_object(
                'card_id', jr.card_id,
                'tcgdex_dex_ids', COALESCE(to_jsonb(ev.distinct_dex_ids), '[]'::jsonb)
            )
            ORDER BY jr.card_id
        ),
        count(*)
    INTO v_payload, v_payload_count
    FROM job_rows jr
    LEFT JOIN evidence ev ON ev.card_id = jr.card_id;

    IF v_payload_count IS NULL OR v_payload_count = 0 THEN
        -- Job TCGDEX, mas nenhuma Card POKEMON com resulting_card_id
        -- elegível (ex.: Card Set 100% TRAINER/ENERGY, ou nenhuma linha
        -- confirmada ainda) — status distinto de SOURCE_NOT_TCGDEX para o
        -- chamador poder diferenciar as duas causas se precisar.
        RETURN QUERY SELECT 'NO_ELIGIBLE_CARDS'::TEXT, 0, 0, 0, 0, 0, 0, 0, '[]'::jsonb;
        RETURN;
    END IF;

    IF v_payload_count > c_max_batch_size THEN
        RAISE EXCEPTION 'RESOLVE_CARD_PRIMARY_SPECIES_FOR_CATALOG_IMPORT_JOB_PAYLOAD_TOO_LARGE: % Cards POKEMON elegíveis excedem o guard (%) neste job.', v_payload_count, c_max_batch_size
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- Delegação total da decisão/escrita — nunca reimplementada aqui.
    SELECT * INTO v_bulk_result FROM public.resolve_card_primary_species_bulk(v_payload);

    RETURN QUERY SELECT
        'PROCESSED'::TEXT,
        v_payload_count,
        v_bulk_result.resolved_count,
        v_bulk_result.unchanged_count,
        v_bulk_result.unresolved_count,
        v_bulk_result.ambiguous_count,
        v_bulk_result.conflict_count,
        v_bulk_result.failed_count,
        v_bulk_result.details;
END;
$$;

COMMENT ON FUNCTION public.resolve_card_primary_species_for_catalog_import_job(UUID) IS
    'Ponto de integração único pós-confirmação (chamado pelos dois callers reais de admin_confirm_catalog_import(): confirmarImportacao() e confirmCatalogImport()/revalidate-catalog-import-rows). GUARD: só processa catalog_import_job.source = TCGDEX — retorna status=SOURCE_NOT_TCGDEX sem escrita para qualquer outra source (ex.: PDF). Lê catalog_import_row.resulting_card_id (nunca matched_card_id), filtra POKEMON, agrega dexId determinístico e delega a resolve_card_primary_species_bulk() (Query 6115). Nunca escreve diretamente em card_primary_species. is_admin()-gated.';

REVOKE ALL ON FUNCTION public.resolve_card_primary_species_for_catalog_import_job(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_card_primary_species_for_catalog_import_job(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_card_primary_species_for_catalog_import_job(UUID) TO authenticated;

COMMIT;
