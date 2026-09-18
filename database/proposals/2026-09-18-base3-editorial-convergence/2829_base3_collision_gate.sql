/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2829 - BASE3 Collision Gate (harness READ-ONLY)
Versão......: 1.1
Status......: EXECUTADO — 2829 PRE 11/11 PASS · 2829 POST 11/11 PASS (2026-09-18).
              Harness READ-ONLY: evidência histórica, não schema permanente.
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-18
Mandato.....: BASE3 — IMPLEMENTATION STAGING-01

-------------------------------------------------------------------------------
POR QUE ESTE ARQUIVO EXISTE — E POR QUE NÃO ESTÁ DENTRO DO RUNNER
-------------------------------------------------------------------------------
O mandato exige reprovar o COLLISION GATE "antes da primeira escrita e no final":

    177 identidades projetadas · 177 distintas · 0 já materializadas

A projeção de identidade depende de DUAS funções do schema `internal`:

    internal.compute_variant_residual_signature(raw_data, game_id, asset_source_id)
    internal.lookup_variant_type_for_row(game_id, asset_source_id, card_set_id, ...)

`internal.*` NÃO é exposto ao PostgREST — o runner do navegador não pode
chamá-las. As duas alternativas seriam:

  (a) reimplementar o resolver em JavaScript -> PROIBIDO pelo mandato
                                                ("não duplicar lógica interna");
  (b) criar uma RPC pública nova             -> PROIBIDO pelo mandato
                                                ("não criar RPC permanente nova").

Logo o gate de colisão é, por construção, um harness SQL — executado no SQL
Editor do Supabase por Fabrício, READ-ONLY, DUAS vezes:

    2829 PRE  : ANTES da migration 2202 e do runner — isto é, antes da PRIMEIRA
                ESCRITA LIVE da rodada. O gate precisa medir o estado intocado.
    2829 POST : DEPOIS do runner e ANTES de aprovar/confirmar na UI.

Ordem canônica da rodada:

    2829 PRE  ->  2202  ->  runner  ->  2829 POST  ->  UI

O runner cobre o que ele PODE observar sem duplicar nada (job/rows/mappings,
`card_variant` das 62 Cards = 0, unicidade de tupla por Card) — ver a seção
COLLISION GATE de `base3-authenticated-runner.js`. Este arquivo é a prova
completa, e é o que satisfaz literalmente o item do mandato.

-------------------------------------------------------------------------------
Descrição resumida:
Projeta a identidade `(card_id, variant_type_id, printing_profile_id)` das 177
rows do job BASE3 e devolve uma tabela de checagens PASS/FAIL. NÃO escreve nada.

Descrição:
Para as 172 rows já resolvidas, a identidade vem do resolver REAL. Para as 5
rows da convergência editorial, a identidade vem de uma tabela de OVERLAY com as
decisões ratificadas em BASE3 — FINAL EDITORIAL RECONCILIATION-01. O overlay é
aplicado por ASSINATURA de `raw_data` (imutável), nunca por `validation_status`.

IDENTIDADE POR CODE, NÃO POR UUID — decisão de projeto, não detalhe.
A chave de comparação usa `code` de Variant Type e de Printing Profile, não os
UUIDs. Razão: no `2829 PRE` os três VTs e o Profile AINDA NÃO EXISTEM; uma
chave por UUID devolveria NULL para eles e produziria colisões FALSAS (foi o
defeito real da v1.0 deste arquivo, corrigido aqui). `code` é único por Game
(`UNIQUE (game_id, code)` em ambas as tabelas), logo é proxy exato do UUID.

O mesmo arquivo serve aos dois momentos:
  - ANTES: o resolver devolve NULL para as 5; o overlay supre pelo code.
  - DEPOIS: o resolver devolve valor para as 5; o check `C7` exige que o code
    real seja IDÊNTICO ao do overlay. Divergência = FAIL.

NÃO USA RAISE EXCEPTION. O gate é uma tabela — mesma disciplina adotada em
02E-STAGING-EXECUTION-SAFETY-FIX-01. Ler a coluna `status`.

Regras de Negócio:
- 100% READ-ONLY. Zero INSERT/UPDATE/DELETE/DDL. Nenhuma transação necessária.
- Identidade projetada = `(card_id, variant_type, printing_profile)`, exatamente
  as colunas dos dois índices únicos parciais disjuntos de `public.card_variant`:
      uq_card_variant_card_type_no_printing (card_id, variant_type_id)
          WHERE printing_profile_id IS NULL
      uq_card_variant_card_type_printing    (card_id, variant_type_id, printing_profile_id)
          WHERE printing_profile_id IS NOT NULL
- Profile NULL é significativo: NULL e não-NULL caem em índices DIFERENTES. A
  chave usa o sentinela `<NO_PROFILE>` para não colapsar NULLs.

Pré-requisitos:
- Nenhum. Roda em qualquer um dos dois estados.

Resultado esperado:
- 11 checagens `PASS` + linha `GATE` `PASS`.
- Execução de referência (LIVE, 2026-09-18, estado PRÉ-migration): 11/11 PASS.

Como validar:
    Executar o bloco SELECT abaixo inteiro. Qualquer linha `FAIL` => STOP, e
    rodar o detalhamento opcional do rodapé.
===============================================================================
*/

WITH ctx AS (
    SELECT e.game_id                                                        AS game_id,
           (SELECT s.id FROM public.asset_source s WHERE s.code = 'TCGDEX') AS asset_source_id,
           cs.id                                                            AS card_set_id
      FROM public.card_set cs
      JOIN public.expansion e                       ON e.id = cs.expansion_id
      JOIN public.catalog_variant_import_job j      ON j.card_set_id = cs.id
     WHERE j.id = 'd5b7a148-0459-40fd-a32f-13fdcb845026'
),

/* ---------------------------------------------------------------------------
 * OVERLAY — as 5 decisões editoriais, por assinatura imutável de `raw_data`.
 * `profile_code` NULL = identidade sem Printing Profile (índice parcial NULL).
 * ------------------------------------------------------------------------- */
overlay (sig_text, vt_code, profile_code) AS (
    VALUES
      ('holo|starlight|stamp:pre-release',        'PRERELEASE_HOLO',        NULL::text),
      ('holo|cosmos|stamp:pre-release',           'PRERELEASE_COSMOS_HOLO', NULL),
      ('holo|galaxy|subtype:evolution-box-error', 'HOLO',                   'EVOLUTION_BOX_ERROR'),
      ('holo|cosmos|subtype:1999-copyright',      'COSMOS_HOLO',            NULL),
      ('normal|-|stamp:wotc',                     'W_PROMO_STAMPED',        NULL)
),

/* As 177 rows, com assinatura textual derivada SOMENTE de `raw_data`.
 * A assinatura inclui `foil` — sem ele, as duas rows de Prerelease do
 * Aerodactyl (starlight e cosmos) colidiriam na própria assinatura. */
rr AS (
    SELECT r.id,
           r.card_id,
           c.collector_number AS num,
           c.name             AS card_name,
           r.raw_data,
           r.validation_status,
           r.decision_status,
           r.persistence_status,
           lower(COALESCE(r.raw_data->>'type', '?'))
             || '|' || lower(COALESCE(r.raw_data->>'foil', '-'))
             || '|' || CASE
                         WHEN jsonb_typeof(r.raw_data->'stamp') = 'array'
                              AND jsonb_array_length(r.raw_data->'stamp') > 0
                           THEN 'stamp:' || lower((
                                  SELECT string_agg(x, '+' ORDER BY ord)
                                    FROM jsonb_array_elements_text(r.raw_data->'stamp')
                                         WITH ORDINALITY AS t(x, ord)))
                         ELSE 'subtype:' || lower(COALESCE(r.raw_data->>'subtype', ''))
                       END AS sig_text
      FROM public.catalog_variant_import_row r
      JOIN public.card c ON c.id = r.card_id
     WHERE r.job_id = 'd5b7a148-0459-40fd-a32f-13fdcb845026'
),

/* Resolver REAL aplicado às 177, já traduzido para `code`. */
named AS (
    SELECT rr.*,
           rvt.code AS real_vt_code,
           rpp.code AS real_profile_code
      FROM rr
      CROSS JOIN ctx
      CROSS JOIN LATERAL internal.compute_variant_residual_signature(
               rr.raw_data, ctx.game_id, ctx.asset_source_id) s
      LEFT JOIN public.card_printing_profile rpp
             ON rpp.id = s.printing_profile_id
      LEFT JOIN public.card_variant_type rvt
             ON rvt.id = internal.lookup_variant_type_for_row(
                    ctx.game_id, ctx.asset_source_id, ctx.card_set_id,
                    s.residual_type, s.residual_foil, s.residual_subtype, s.residual_stamp)
),

/* Identidade EFETIVA: o overlay tem precedência para as 5 da convergência. */
eff AS (
    SELECT n.*,
           (o.sig_text IS NOT NULL) AS is_convergence,
           o.vt_code                AS ov_vt,
           o.profile_code           AS ov_prof,
           CASE WHEN o.sig_text IS NOT NULL THEN o.vt_code      ELSE n.real_vt_code      END AS eff_vt_code,
           CASE WHEN o.sig_text IS NOT NULL THEN o.profile_code ELSE n.real_profile_code END AS eff_profile_code
      FROM named n
      LEFT JOIN overlay o ON o.sig_text = n.sig_text
),

ident AS (
    SELECT eff.*,
           card_id::text
             || '|' || COALESCE(eff_vt_code, '<NO_VT>')
             || '|' || COALESCE(eff_profile_code, '<NO_PROFILE>') AS identity_key
      FROM eff
),

checks AS (
    /* C1  — cardinalidade do job */
    SELECT 1 AS n, 'C1_ROWS_TOTAL' AS check_name, '177'::text AS expected,
           (SELECT COUNT(*)::text FROM ident) AS got
    UNION ALL
    /* C2  — as 5 assinaturas da convergência, uma row cada */
    SELECT 2, 'C2_CONVERGENCE_SIGNATURES', '5 rows em 5 assinatura(s)',
           (SELECT COUNT(*)::text || ' rows em ' || COUNT(DISTINCT sig_text)::text || ' assinatura(s)'
              FROM ident WHERE is_convergence)
    UNION ALL
    /* C3  — nenhuma row sem Variant Type efetivo */
    SELECT 3, 'C3_NO_UNRESOLVED_VT', '0',
           (SELECT COUNT(*)::text FROM ident WHERE eff_vt_code IS NULL)
    UNION ALL
    /* C4  — GATE CENTRAL: 177 identidades distintas */
    SELECT 4, 'C4_IDENTITIES_DISTINCT', (SELECT COUNT(*)::text FROM ident),
           (SELECT COUNT(DISTINCT identity_key)::text FROM ident)
    UNION ALL
    /* C5  — nenhum grupo de colisão */
    SELECT 5, 'C5_COLLISION_GROUPS', '0',
           (SELECT COUNT(*)::text FROM (
                SELECT identity_key FROM ident GROUP BY identity_key HAVING COUNT(*) > 1) x)
    UNION ALL
    /* C6  — zero card_variant já materializado nas 62 Cards do Set */
    SELECT 6, 'C6_ALREADY_MATERIALIZED', '0',
           (SELECT COUNT(*)::text FROM public.card_variant v
             WHERE v.card_id IN (SELECT DISTINCT card_id FROM ident))
    UNION ALL
    /* C7  — overlay x resolver: se já resolveu, tem de bater (pós-execução) */
    SELECT 7, 'C7_OVERLAY_MATCHES_RESOLVER', '0 divergencia(s)',
           (SELECT COUNT(*)::text || ' divergencia(s)' FROM ident
             WHERE is_convergence
               AND ( (real_vt_code      IS NOT NULL AND real_vt_code      IS DISTINCT FROM ov_vt)
                  OR (real_profile_code IS NOT NULL AND real_profile_code IS DISTINCT FROM ov_prof) ))
    UNION ALL
    /* C8  — workflow intocado: nada decidido nem persistido */
    SELECT 8, 'C8_WORKFLOW_UNTOUCHED', '177 PENDING/PENDING',
           (SELECT COUNT(*)::text || ' PENDING/PENDING' FROM ident
             WHERE decision_status = 'PENDING' AND persistence_status = 'PENDING')
    UNION ALL
    /* C9  — cobertura de Card */
    SELECT 9, 'C9_CARD_COVERAGE', '62',
           (SELECT COUNT(DISTINCT card_id)::text FROM ident)
    UNION ALL
    /* C10 — card_variant projetado após a confirmação */
    SELECT 10, 'C10_PROJECTED_CARD_VARIANT',
           ((SELECT COUNT(*) FROM public.card_variant) + 177)::text,
           ((SELECT COUNT(*) FROM public.card_variant)
            + (SELECT COUNT(DISTINCT identity_key) FROM ident))::text
    UNION ALL
    /* C11 — as 172 fora da convergência continuam resolvidas pelo resolver */
    SELECT 11, 'C11_NON_CONVERGENCE_RESOLVED', '172',
           (SELECT COUNT(*)::text FROM ident WHERE NOT is_convergence AND real_vt_code IS NOT NULL)
),

graded AS (
    SELECT n, check_name, expected, got,
           CASE WHEN got = expected THEN 'PASS' ELSE 'FAIL' END AS status
      FROM checks
)

SELECT n, check_name, expected, got, status FROM graded
UNION ALL
SELECT 99, 'GATE', 'todas PASS',
       (SELECT COUNT(*) FILTER (WHERE status = 'PASS')::text || '/' || COUNT(*)::text FROM graded),
       (SELECT CASE WHEN COUNT(*) FILTER (WHERE status = 'FAIL') = 0 THEN 'PASS' ELSE 'FAIL' END FROM graded)
ORDER BY 1;

/*
===============================================================================
DETALHAMENTO OPCIONAL — executar somente se alguma checagem acima der FAIL.
Lista a projeção das 3 Cards da convergência, com resolver real.
===============================================================================

WITH ctx AS (
    SELECT e.game_id,
           (SELECT s.id FROM public.asset_source s WHERE s.code = 'TCGDEX') AS asset_source_id,
           cs.id AS card_set_id
      FROM public.card_set cs
      JOIN public.expansion e ON e.id = cs.expansion_id
     WHERE cs.code = 'BASE3'
)
SELECT c.collector_number,
       c.name,
       r.raw_data,
       r.validation_status,
       s.printing_state,
       COALESCE(pp.code, '(NULL)')   AS profile,
       COALESCE(vt.code, '(NENHUM)') AS variant_type
  FROM public.catalog_variant_import_row r
  JOIN public.card c ON c.id = r.card_id
  CROSS JOIN ctx
  CROSS JOIN LATERAL internal.compute_variant_residual_signature(r.raw_data, ctx.game_id, ctx.asset_source_id) s
  LEFT JOIN public.card_printing_profile pp ON pp.id = s.printing_profile_id
  LEFT JOIN public.card_variant_type vt
         ON vt.id = internal.lookup_variant_type_for_row(
              ctx.game_id, ctx.asset_source_id, ctx.card_set_id,
              s.residual_type, s.residual_foil, s.residual_subtype, s.residual_stamp)
 WHERE r.job_id = 'd5b7a148-0459-40fd-a32f-13fdcb845026'
   AND c.collector_number IN ('01', '15', '50')
 ORDER BY c.collector_number, r.raw_data::text;
===============================================================================
*/
