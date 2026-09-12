/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6842 - Validacao do sourcing ME* de Card Primary Species
Versão......: 2.1
Status......: CONFIRMADO EXECUTADO / VALIDADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Executado...: 2026-09-12, read-only, em duas rodadas.
               Secoes 1 e 2 (manifesto pos-6129 + GATE A) apos a 6129:
                   751 linhas / 751 Cards / 751 external_id, 0 duplicadas.
               Secoes 3, 4 e 5 (manifesto pos-6130 + GATE B + GATE C) apos a 6130:
                   752 linhas / 752 Cards / 752 external_id, 0 duplicadas;
                   ME1=152 ME2=110 ME2.5=243 ME3=91 ME4=97 MEP=59;
                   751 AUTOMATIC_DEXID + 1 EDITORIAL_RECONCILIATION;
                   B1-B10 = 10/10 PASS · C1-C7 = 7/7 PASS.
               NAO promovida — permanece em proposals/ como prova da rodada,
               mesmo padrao de 6800/6810/6820/6821/6841.
Mandato.....: PRIMARY-SPECIES-ME-SOURCING-01 — BACKFILL-GATE-A-REVISION-01
               (autoria) / 6842-MANIFEST-FANOUT-CORRECTION-01 (v2.1, dedup dos
               manifestos pelo par logico) / BACKFILL-GATE-B-01 e
               FINAL-VALIDATION-01 (execucao)
Valida......: Query 6129 (backfill automatico de 751 Cards)
               Query 6130 (resolucao editorial de me01-086)

v2.0 (BACKFILL-GATE-A-REVISION-01) sobre a v1.0:
- o manifesto foi SEPARADO em duas secoes. A v1.0 alegava um manifesto de 752
  linhas lendo card_primary_species logo apos a 6129 — o que era falso: apos a
  6129 existem 751 linhas, nao 752. me01-086 so passa a existir depois da 6130.
- GATE A agora prova exatamente o estado pos-6129 (751) e GATE B o estado
  pos-6130 (752). Nenhum gate antecipa o resultado do outro.

READ-ONLY. Nenhuma escrita, nenhuma fixture, nenhum objeto criado (nem
temporario). Pode ser executada quantas vezes for preciso.

Esta Query permanece em database/proposals/ como evidencia de validacao —
NAO e promovida para database/schema/, mesmo padrao da 6841.

-------------------------------------------------------------------------------
ORDEM DE USO
-------------------------------------------------------------------------------
    apos a 6129  ->  Secao 1  (manifesto 751)  +  Secao 2  (GATE A)
    apos a 6130  ->  Secao 3  (manifesto 752)  +  Secao 4  (GATE B)
    ao final     ->  Secao 5  (nao-regressao)

Cada gate devolve uma coluna `resultado` com PASS ou FAIL. Qualquer FAIL = STOP.
===============================================================================
*/


-- =============================================================================
-- SECAO 1 — MANIFESTO POS-6129 (751 linhas, todas AUTOMATIC_DEXID)
-- =============================================================================
-- Seis colunas exigidas pelo mandato + basis. Aqui card_id e FATO DO BANCO,
-- nao transcricao. Exportar e anexar ao README como registro da rodada.
-- NAO esperar 752 nesta secao: me01-086 ainda nao existe.
SELECT
    cps.card_id,
    cs.code                                      AS card_set,
    cer.external_card_id,
    (cps.source_evidence -> 'tcgdex_dex_ids')    AS dexid_observado,
    sp.national_dex_number                       AS dexid_aplicado,
    sp.canonical_name                            AS pokemon_species,
    'AUTO_APPROVED'::text                        AS classificacao,
    cps.resolution_basis,
    c.name                                       AS card_name,
    cps.resolved_at
FROM public.card_primary_species cps
JOIN public.card c                    ON c.id  = cps.card_id
JOIN public.card_set cs               ON cs.id = c.card_set_id
JOIN public.pokemon_species sp        ON sp.id = cps.pokemon_species_id
-- DEDUPLICACAO POR PAR LOGICO (card_id, external_card_id) — v2.1.
-- Uma Card MEP tem DUAS card_external_reference ativas (en e pt-BR) com o
-- MESMO external_card_id; sem o GROUP BY abaixo o manifesto duplicava essas
-- 59 Cards (751 Cards -> 810 linhas). O agrupamento e pelo PAR, nao por
-- card_id: se um dia a mesma Card tiver DOIS external_card_id DIFERENTES,
-- ela volta a aparecer em duas linhas e a anomalia fica VISIVEL — que e o
-- comportamento desejado. Nada de DISTINCT ON, nada de idioma fixo.
JOIN (
    SELECT r.card_id, r.external_card_id
    FROM public.card_external_reference r
    JOIN public.asset_source asrc ON asrc.id = r.asset_source_id
    WHERE r.is_active
      AND asrc.code = 'TCGDEX'
    GROUP BY r.card_id, r.external_card_id
) cer ON cer.card_id = cps.card_id
WHERE cs.code IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')
  AND cps.resolution_basis = 'AUTOMATIC_DEXID'
ORDER BY cs.code, cer.external_card_id;


-- =============================================================================
-- SECAO 2 — GATE A: estado esperado APOS 6129 e ANTES de 6130
-- =============================================================================
WITH me_pokemon AS (
    SELECT c.id AS card_id, cs.code AS set_code
    FROM public.card c
    JOIN public.card_category cc ON cc.id = c.category_id
    JOIN public.card_set cs      ON cs.id = c.card_set_id
    WHERE cc.code = 'POKEMON' AND c.is_active
      AND cs.code IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')
),
alvo AS (
    SELECT c.id AS card_id
    FROM public.card c
    JOIN public.card_external_reference r ON r.card_id = c.id AND r.is_active
    WHERE r.external_card_id = 'me01-086'
)
SELECT 'A1 · 751 novas AUTOMATIC_DEXID nos Sets ME*' AS teste,
       CASE WHEN (SELECT count(*) FROM me_pokemon mp
                    JOIN public.card_primary_species cps ON cps.card_id = mp.card_id
                   WHERE cps.resolution_basis = 'AUTOMATIC_DEXID') = 751
            THEN 'PASS' ELSE 'FAIL' END AS resultado
UNION ALL
SELECT 'A2 · nenhuma EDITORIAL_RECONCILIATION nos Sets ME* ainda',
       CASE WHEN (SELECT count(*) FROM me_pokemon mp
                    JOIN public.card_primary_species cps ON cps.card_id = mp.card_id
                   WHERE cps.resolution_basis = 'EDITORIAL_RECONCILIATION') = 0
            THEN 'PASS' ELSE 'FAIL: a 6130 ja rodou? use o GATE B' END
UNION ALL
SELECT 'A3 · total global = 17408',
       CASE WHEN (SELECT count(*) FROM public.card_primary_species) = 17408
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'A4 · me01-086 continua SEM card_primary_species',
       CASE WHEN (SELECT count(*) FROM public.card_primary_species cps
                    JOIN alvo a ON a.card_id = cps.card_id) = 0
            THEN 'PASS' ELSE 'FAIL: foi resolvida indevidamente' END
UNION ALL
SELECT 'A5 · residual ME* = 1 (apenas me01-086)',
       CASE WHEN (SELECT count(*) FROM me_pokemon mp
                    LEFT JOIN public.card_primary_species cps ON cps.card_id = mp.card_id
                   WHERE cps.card_id IS NULL) = 1
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'A6 · residual global = 128',
       CASE WHEN (SELECT count(*) FROM public.card c
                    JOIN public.card_category cc ON cc.id = c.category_id
                    LEFT JOIN public.card_primary_species cps ON cps.card_id = c.id
                   WHERE cc.code = 'POKEMON' AND cps.card_id IS NULL) = 128
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'A7 · zero alteracao fora das 751 (nenhum UPDATE em linha preexistente)',
       CASE WHEN (SELECT count(*) FROM public.card_primary_species cps
                    JOIN public.card c      ON c.id  = cps.card_id
                    JOIN public.card_set cs ON cs.id = c.card_set_id
                   WHERE cs.code NOT IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')
                     AND cps.updated_at > cps.created_at) = 0
            THEN 'PASS' ELSE 'FAIL: houve UPDATE fora do escopo' END
UNION ALL
SELECT 'A8 · 16.657 resolucoes anteriores intactas fora dos Sets ME*',
       CASE WHEN (SELECT count(*) FROM public.card_primary_species cps
                    JOIN public.card c      ON c.id  = cps.card_id
                    JOIN public.card_set cs ON cs.id = c.card_set_id
                   WHERE cs.code NOT IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')) = 16657
            THEN 'PASS' ELSE 'FAIL' END;

/*
A9 — VERIFICACAO DOCUMENTAL, nao de banco:
     a evidencia congelada da Query 6129 deve continuar registrando

         {"e":"me01-086","d":351}

     Isto ja foi enforcado em tempo de execucao pelo guard G3b da propria
     6129 (que aborta a transacao se o par deixar de ser 351). Para reverificar
     a qualquer momento, sem banco:

         grep -n '"e":"me01-086"' 6129_backfill_card_primary_species_me_sets.sql

     Esperado: uma unica ocorrencia, com "d":351.
*/

-- Cardinalidade por Set apos a 6129 (ME1 = 151; demais = 100% das pendentes).
SELECT cs.code AS card_set,
       count(*) FILTER (WHERE cps.card_id IS NOT NULL) AS resolvidas,
       count(*) FILTER (WHERE cps.card_id IS NULL)     AS pendentes,
       CASE cs.code
           WHEN 'ME1'   THEN 151 WHEN 'ME2'  THEN 110 WHEN 'ME2.5' THEN 243
           WHEN 'ME3'   THEN 91  WHEN 'ME4'  THEN 97  WHEN 'MEP'   THEN 59
       END AS esperado,
       CASE WHEN count(*) FILTER (WHERE cps.card_id IS NOT NULL) =
                 CASE cs.code
                     WHEN 'ME1' THEN 151 WHEN 'ME2' THEN 110 WHEN 'ME2.5' THEN 243
                     WHEN 'ME3' THEN 91  WHEN 'ME4' THEN 97  WHEN 'MEP'   THEN 59
                 END
            THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM public.card c
JOIN public.card_category cc ON cc.id = c.category_id
JOIN public.card_set cs      ON cs.id = c.card_set_id
LEFT JOIN public.card_primary_species cps ON cps.card_id = c.id
WHERE cc.code = 'POKEMON' AND c.is_active
  AND cs.code IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')
GROUP BY cs.code
ORDER BY cs.code;


-- =============================================================================
-- SECAO 3 — MANIFESTO POS-6130 (752 linhas: 751 automaticas + 1 editorial)
-- =============================================================================
-- Só rodar DEPOIS da 6130. Este e o registro final da rodada.
SELECT
    cps.card_id,
    cs.code                                      AS card_set,
    cer.external_card_id,
    COALESCE(
        (cps.source_evidence -> 'tcgdex_dex_ids'),                    -- automatica
        jsonb_build_array((cps.source_evidence ->> 'observed_dex_id')::int) -- editorial
    )                                            AS dexid_observado,
    sp.national_dex_number                       AS dexid_aplicado,
    sp.canonical_name                            AS pokemon_species,
    CASE cps.resolution_basis
        WHEN 'AUTOMATIC_DEXID'          THEN 'AUTO_APPROVED'
        WHEN 'EDITORIAL_RECONCILIATION' THEN 'SOURCE_DATA_ERROR_RESOLVIDO'
    END                                          AS classificacao,
    cps.resolution_basis,
    c.name                                       AS card_name,
    cps.resolved_at
FROM public.card_primary_species cps
JOIN public.card c                    ON c.id  = cps.card_id
JOIN public.card_set cs               ON cs.id = c.card_set_id
JOIN public.pokemon_species sp        ON sp.id = cps.pokemon_species_id
-- DEDUPLICACAO POR PAR LOGICO (card_id, external_card_id) — v2.1.
-- Mesma regra da Secao 1, palavra por palavra. Ver justificativa la.
JOIN (
    SELECT r.card_id, r.external_card_id
    FROM public.card_external_reference r
    JOIN public.asset_source asrc ON asrc.id = r.asset_source_id
    WHERE r.is_active
      AND asrc.code = 'TCGDEX'
    GROUP BY r.card_id, r.external_card_id
) cer ON cer.card_id = cps.card_id
WHERE cs.code IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')
ORDER BY cs.code, cer.external_card_id;


-- =============================================================================
-- SECAO 4 — GATE B: estado esperado APOS 6130
-- =============================================================================
WITH me_pokemon AS (
    SELECT c.id AS card_id
    FROM public.card c
    JOIN public.card_category cc ON cc.id = c.category_id
    JOIN public.card_set cs      ON cs.id = c.card_set_id
    WHERE cc.code = 'POKEMON' AND c.is_active
      AND cs.code IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')
),
h AS (
    SELECT cps.*, sp.canonical_name, sp.national_dex_number
    FROM public.card_primary_species cps
    JOIN public.card_external_reference r ON r.card_id = cps.card_id AND r.is_active
    JOIN public.pokemon_species sp        ON sp.id = cps.pokemon_species_id
    WHERE r.external_card_id = 'me01-086'
)
SELECT 'B1 · 751 AUTOMATIC_DEXID nos Sets ME*' AS teste,
       CASE WHEN (SELECT count(*) FROM me_pokemon mp
                    JOIN public.card_primary_species cps ON cps.card_id = mp.card_id
                   WHERE cps.resolution_basis = 'AUTOMATIC_DEXID') = 751
            THEN 'PASS' ELSE 'FAIL' END AS resultado
UNION ALL
SELECT 'B2 · exatamente 1 EDITORIAL_RECONCILIATION nos Sets ME*',
       CASE WHEN (SELECT count(*) FROM me_pokemon mp
                    JOIN public.card_primary_species cps ON cps.card_id = mp.card_id
                   WHERE cps.resolution_basis = 'EDITORIAL_RECONCILIATION') = 1
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'B3 · a editorial e me01-086 -> Absol / 359',
       CASE WHEN (SELECT count(*) FROM h
                   WHERE resolution_basis = 'EDITORIAL_RECONCILIATION'
                     AND canonical_name = 'Absol'
                     AND national_dex_number = 359) = 1
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'B4 · decisao tem responsavel nomeado',
       CASE WHEN (SELECT count(*) FROM h WHERE resolved_by_user_id IS NOT NULL) = 1
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'B5 · contrato de source_evidence completo',
       CASE WHEN (SELECT count(*) FROM h
                   WHERE source_evidence ->> 'reason'   = 'SOURCE_DATA_ERROR'
                     AND source_evidence ->> 'provider' = 'TCGDEX'
                     AND source_evidence ->> 'external_card_id' = 'me01-086'
                     AND source_evidence ->> 'observed_name'    = 'Mega Absol ex'
                     AND (source_evidence ->> 'observed_dex_id')::int = 351
                     AND source_evidence ->> 'resolved_species'  = 'Absol'
                     AND (source_evidence ->> 'resolved_national_dex')::int = 359) = 1
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'B6 · 351 observado e 359 decidido permanecem distintos e registrados',
       CASE WHEN (SELECT count(*) FROM h
                   WHERE (source_evidence ->> 'observed_dex_id')::int
                      <> (source_evidence ->> 'resolved_national_dex')::int) = 1
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'B7 · evidencia editorial NAO se passa por automatica',
       CASE WHEN (SELECT count(*) FROM h
                   WHERE source_evidence ? 'tcgdex_dex_ids'
                      OR source_evidence ? 'resolved_dex_id') = 0
            THEN 'PASS' ELSE 'FAIL: evidencia automatica falsificada' END
UNION ALL
SELECT 'B8 · total global = 17409',
       CASE WHEN (SELECT count(*) FROM public.card_primary_species) = 17409
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'B9 · Sets ME* 100% resolvidos (752/752)',
       CASE WHEN (SELECT count(*) FROM me_pokemon mp
                    LEFT JOIN public.card_primary_species cps ON cps.card_id = mp.card_id
                   WHERE cps.card_id IS NULL) = 0
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'B10 · residual global = 127 (8 SVP + 119 ambiguidades)',
       CASE WHEN (SELECT count(*) FROM public.card c
                    JOIN public.card_category cc ON cc.id = c.category_id
                    LEFT JOIN public.card_primary_species cps ON cps.card_id = c.id
                   WHERE cc.code = 'POKEMON' AND cps.card_id IS NULL) = 127
            THEN 'PASS' ELSE 'FAIL' END;


-- =============================================================================
-- SECAO 5 — NAO-REGRESSAO: nada fora do universo autorizado foi tocado
-- =============================================================================
SELECT 'C1 · nenhuma resolucao preexistente sofreu UPDATE' AS teste,
       CASE WHEN (SELECT count(*) FROM public.card_primary_species cps
                    JOIN public.card c      ON c.id  = cps.card_id
                    JOIN public.card_set cs ON cs.id = c.card_set_id
                   WHERE cs.code NOT IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')
                     AND cps.updated_at > cps.created_at) = 0
            THEN 'PASS' ELSE 'FAIL' END AS resultado
UNION ALL
SELECT 'C2 · 16.657 resolucoes anteriores intactas fora dos Sets ME*',
       CASE WHEN (SELECT count(*) FROM public.card_primary_species cps
                    JOIN public.card c      ON c.id  = cps.card_id
                    JOIN public.card_set cs ON cs.id = c.card_set_id
                   WHERE cs.code NOT IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')) = 16657
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'C3 · toda linha ME* aponta para Species ativa',
       CASE WHEN (SELECT count(*) FROM public.card_primary_species cps
                    JOIN public.card c      ON c.id  = cps.card_id
                    JOIN public.card_set cs ON cs.id = c.card_set_id
                    JOIN public.pokemon_species sp ON sp.id = cps.pokemon_species_id
                   WHERE cs.code IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')
                     AND NOT sp.is_active) = 0
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'C4 · nenhuma Card nao-POKEMON recebeu Primary Species',
       CASE WHEN (SELECT count(*) FROM public.card_primary_species cps
                    JOIN public.card c           ON c.id  = cps.card_id
                    JOIN public.card_category cc ON cc.id = c.category_id
                   WHERE cc.code <> 'POKEMON') = 0
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'C5 · as 8 SVP continuam intocadas',
       CASE WHEN (SELECT count(*) FROM public.card c
                    JOIN public.card_category cc ON cc.id = c.category_id
                    JOIN public.card_set cs      ON cs.id = c.card_set_id
                    LEFT JOIN public.card_primary_species cps ON cps.card_id = c.id
                   WHERE cc.code = 'POKEMON' AND cs.code = 'SVP'
                     AND cps.card_id IS NULL) = 8
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'C6 · nenhuma Card nova foi criada nos Sets ME*',
       CASE WHEN (SELECT count(*) FROM public.card c
                    JOIN public.card_category cc ON cc.id = c.category_id
                    JOIN public.card_set cs      ON cs.id = c.card_set_id
                   WHERE cc.code = 'POKEMON' AND c.is_active
                     AND cs.code IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')) = 752
            THEN 'PASS' ELSE 'FAIL: o universo ME* mudou de tamanho' END
UNION ALL
SELECT 'C7 · corroboracao por nome nas ME* resolvidas = 100%',
       CASE WHEN (SELECT count(*) FROM public.card_primary_species cps
                    JOIN public.card c             ON c.id  = cps.card_id
                    JOIN public.card_set cs        ON cs.id = c.card_set_id
                    JOIN public.pokemon_species sp ON sp.id = cps.pokemon_species_id
                   WHERE cs.code IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')
                     AND lower(regexp_replace(c.name,'[^a-zA-Z]','','g'))
                         NOT LIKE '%' || lower(regexp_replace(sp.canonical_name,'[^a-zA-Z]','','g')) || '%') = 0
            THEN 'PASS' ELSE 'FAIL: ha Card cujo nome nao corrobora a Species' END;
