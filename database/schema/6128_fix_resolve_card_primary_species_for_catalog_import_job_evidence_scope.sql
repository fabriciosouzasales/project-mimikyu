/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6128 - Fix resolve_card_primary_species_for_catalog_import_job()
               — escopo da CTE `evidence` por p_job_id
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12 (aplicada no LIVE em APPLY-01; proveniencia
               reconciliada em RECOVERY-01; validada em VALIDATION-FIX-01
               com 6841 = 17 PASS / 0 FAIL / 0 NOT PROVEN; promovida para
               database/schema/ em PROMOTION-CLOSEOUT-01)

ESTE ARQUIVO E A FONTE CANONICA.
A copia em database/proposals/2026-09-12-primary-species-6116-timeout-fix/
permanece como evidencia historica da rodada de staging. Os cabecalhos das
duas divergem de proposito (cada uma declara o proprio papel); o que precisa
ser byte-identico entre proposal, schema e o objeto LIVE e o CORPO SQL
EXECUTAVEL, nao o arquivo inteiro.

Corpo aplicado no LIVE: md5 7f2e7de82acf9a50df23a5861475b601 / 4539 bytes.

Incidente (comprovado em PRIMARY-SPECIES-INCREMENTAL-HOOK-AUDIT-01):
Tres jobs TCGDEX chegaram a COMPLETED com Primary Species = 0:

    SMP  = 3904745c-480b-4884-ba1a-c04ac0c1e8fc
    SM10 = 1150a2eb-2e46-43e5-8e13-e592105778bc
    BW10 = fb3b25e3-14be-4260-9d89-020412234c2a

Causa provada, nao inferida. O proprio caller (web/scripts/bootstrap-cards/
run-bootstrap-cards.mjs) registrou o erro no CSV da rodada, campo `motivo`:

    IMPORTED,primary_species falhou (nao bloqueante):
             canceling statement due to statement timeout

Evidencia em out/cards-apply-2026-09-11T00-18-39-713Z.csv (SM10, BW10) e
out/cards-apply-2026-09-11T18-50-15-317Z.csv (SMP). Exatamente 3 ocorrencias
em todos os CSVs da serie — nenhum caso oculto. Jobs contemporaneos da mesma
rodada e mesma sessao (SM1, SM4, SM9, SM11, BW9) sairam com `job COMPLETED`
e resolveram normalmente.

O caller comportou-se conforme o desenho: chamou em RPC separada apos o
COMMIT da confirmacao, checou `{ data, error }`, registrou e NAO bloqueou a
importacao. O defeito e desta funcao.

MECANISMO:
`authenticated` tem statement_timeout = 8s (pg_roles.rolconfig); 6116 executa
como `authenticated`. A CTE `evidence` filtra

    r.resulting_card_id IN (SELECT card_id FROM job_rows)

SEM repetir `r.job_id = p_job_id`, e public.catalog_import_row nao tem indice
em resulting_card_id. O planner entao varre a tabela inteira a cada chamada,
independentemente do tamanho do job. Medido em 2026-09-12, cache quente, base
ociosa, para o job do SM10:

    Seq Scan on catalog_import_row (rows=20053) ............ 6571 ms
    Nested Loop Semi Join → Rows Removed by Join Filter: 3.891.225
    Execution Time ........................................ 7663 ms   (96% de 8s)

Sob a carga da importacao em massa de 2026-09-11, isso ultrapassou os 8s.
Hoje esta a ~340 ms da borda: nao e um evento raro, e uma falha prestes a
reincidir.

CORRECAO — UMA CLAUSULA:

    + AND r.job_id = p_job_id

Por que nao altera semantica:
- `job_rows` ja restringe as Cards ao proprio job; a clausula apenas impede
  que linhas de OUTROS jobs, apontando para as mesmas Cards, entrem na
  agregacao de dexId;
- medido em PRIMARY-SPECIES-GLOBAL-RECONCILIATION — AUDIT-01: 1.718 Cards
  aparecem em mais de um job (max. 3), e ZERO delas tem dexId divergente
  entre jobs, em 16.777 Cards com evidencia. O conjunto resultante e
  identico hoje;
- e MAIS correto, nao menos: elimina o acoplamento cross-job que a AUDIT-01
  ja havia registrado como risco latente. O modo de falha daquele acoplamento
  seria AMBIGUOUS (fail-closed), nunca uma escrita errada — mas o resultado
  de um lote passa a depender apenas do proprio lote.

Resultado real medido apos a aplicacao (VALIDATION-FIX-01, job do SM10):
    Execution Time ....... 262 ms   (era 7663 ms — ganho ~29x)
    Seq Scan global ...... ELIMINADO
    Ambos os acessos a catalog_import_row usam ix_catalog_import_row_job
    Margem vs statement_timeout de 8s: 3,3% consumido (era 96%)

O QUE ESTA MIGRATION DELIBERADAMENTE NAO FAZ:
- nao altera o contrato de retorno (status + 7 contadores + details);
- nao altera SECURITY DEFINER, STABLE/VOLATILE, LANGUAGE ou search_path;
- nao altera o guard public.is_admin();
- nao altera o guard de source (SOURCE_NOT_TCGDEX) nem NO_ELIGIBLE_CARDS;
- nao altera c_max_batch_size (10000) nem qualquer RAISE existente;
- nao altera o comportamento nao bloqueante para os callers;
- NAO reemite GRANT/REVOKE: CREATE OR REPLACE preserva a ACL quando a
  assinatura e identica — e ela e, `(p_job_id UUID)`. Nao tocar e mais
  seguro que reescrever;
- NAO reemite COMMENT ON FUNCTION: idem, e preservado. O texto do comentario
  continua valido (nada do contrato descrito nele mudou);
- NAO reemite o `DROP FUNCTION IF EXISTS ...(UUID, UUID[])` que a 6116 v1.2
  carregava: aquilo era defesa de transicao contra a assinatura v1.1, ja
  consumida na execucao original. Repetir seria ruido, nao correcao;
- nao cria indice;
- nao toca em run-bootstrap-cards.mjs nem em nenhum outro caller;
- nao toca em schema de tabelas.

DIVIDA DE PROVENIENCIA (registrada, NAO resolvida — ver README do staging):
o corpo LIVE anterior a esta migration media md5 9d6cd767dfcd627e76a38c21d820dbcf
/ 3005 bytes e NAO era byte-identico ao corpo do arquivo canonico da 6116,
apesar de o cabecalho daquele arquivo afirmar o contrario. O corpo historico
exato nao esta mais disponivel; NENHUMA equivalencia byte-level retroativa e
alegada. Divida documental/de proveniencia — nao classificada como defeito
funcional atual. Verificar outras funcoes promovidas exige mandato proprio.

Validacao: 6841_validate_primary_species_6116_evidence_scope.sql
(permanece em database/proposals/ como prova; nao e promovida).

Pré-requisitos:
- Query 6116 v1.2 aplicada (CONFIRMADO EXECUTADO / LIVE).
===============================================================================
*/

BEGIN;

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
          -- Query 6128: escopo explícito ao próprio job. Sem esta cláusula o
          -- planner varre catalog_import_row inteira (sem índice em
          -- resulting_card_id), estourando o statement_timeout de 8s do papel
          -- `authenticated` — causa real do incidente SMP/SM10/BW10.
          AND r.job_id = p_job_id
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

COMMIT;
