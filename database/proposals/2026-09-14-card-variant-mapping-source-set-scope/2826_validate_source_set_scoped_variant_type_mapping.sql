/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2826 - Validate Source-Set Scoped Variant Type Mapping
Versão......: 4.0
Status......: CONFIRMADO EXECUTADO — run #2 em 2026-09-14:
              35 PASS / 0 FAIL / 35 registros · P_VECTORS 10/10 · zero residuo.
              (run #1 = 32/3: P_VECTORS/AE/AF, todos defeitos DESTE harness e
              nenhum das migrations 2191-2197 — corrigidos em
              GATE-B-HARNESS-CORRECTION-01, ver marcadores no corpo.)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-14
Mandato.....: CARD-VARIANTS — EDITORIAL-CONVERGENCE-16 /
              SOURCE-SET-SCOPED-FOUNDATION /
              GATE-A-REV-03 — FINAL-PROOF-CLOSURE

-------------------------------------------------------------------------------
>>> O QUE ESTE HARNESS AFIRMA — E O QUE NÃO AFIRMA <<<
-------------------------------------------------------------------------------
Medido em 2026-09-14, dentro do canal execute_sql do Management API:

    current_user = postgres (NAO superuser)   auth.uid()          = NULL
    request.jwt.claims = NULL                 public.is_admin()   = FALSE

`public.is_admin()` e `EXISTS (SELECT 1 FROM admin_user WHERE id = auth.uid())`.
Logo TODA RPC publica protegida por esse guard e INALCANCAVEL por este canal.
Isso e ausencia de sessao de aplicacao autenticada no CANAL — nao defeito do
desenho da aplicacao.

Portanto este harness:

  * NAO afirma, em nenhum caso, ter executado positivamente uma RPC publica
    protegida por is_admin();
  * prova o COMPORTAMENTO em runtime pelas funcoes internal.* (SECURITY
    DEFINER, alcancaveis como postgres);
  * prova a FRONTEIRA PUBLICA estaticamente, por catalogo (casos AB e AD);
  * deixa a prova E2E POSITIVA da fronteira para 1 smoke test com sessao
    admin REAL da aplicacao, registrado na Secao 11 do README da proposal.

Nada de JWT fabricado, request.jwt.claims alterado, admin temporario ou
service_role. A limitacao e do canal; nao vira arquitetura nova.

-------------------------------------------------------------------------------
ARQUITETURA — HERDADA DA QUERY 2825 v3.6, QUE JÁ PASSOU 29/0 NO LIVE
-------------------------------------------------------------------------------
NÃO existe BEGIN/COMMIT/ROLLBACK de topo. Provado em 2026-09-13 contra o LIVE:
o canal `execute_sql` do Supabase Management API já entrega o payload dentro de
uma transação aberta, um ROLLBACK interno encerra a transação EXTERNA, e objetos
TEMP não sobrevivem entre chamadas.

Portanto CADA cenário mutável vive em SUBTRANSAÇÃO PL/pgSQL com sentinela:

    BEGIN
        <writes reais>
        <PROVAS de que os writes aconteceram>   -- nunca depois da sentinela
        RAISE EXCEPTION 'HARNESS_<CASO>_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_<CASO>_ROLLBACK' THEN <reverteu> ELSE <falhou> END IF;
    END;
    <PROVAS de que nada sobreviveu>

Variáveis PL/pgSQL NÃO são transacionais e sobrevivem ao rollback do sub-bloco;
TEMP TABLES são. Por isso nenhum veredito é gravado em `_r` de dentro de um
sub-bloco.

EXECUTAR O ARQUIVO INTEIRO EM UMA ÚNICA CHAMADA execute_sql.

-------------------------------------------------------------------------------
COBERTURA — 35 casos (34 + o runner dos 10 vetores compartilhados)
-------------------------------------------------------------------------------
SEÇÃO 1 — estrutura
  A  coluna/CHECK                      C  FK scoped válida
  B  MATCH SIMPLE aceita global        D  FK scoped inexistente rejeitada
SEÇÃO 2 — unicidade
  E  UNIQUE GLOBAL                     G  coexistência global + scoped
  F  UNIQUE SCOPED                     H  dois scoped de Sets diferentes
SEÇÃO 3 — precedência
  I  precedência scoped                L  isolamento entre Fontes
  J  fallback global                   M  ausência de escopo -> só global
  K  nenhum -> NEEDS_REVIEW
SEÇÃO 4 — paridade
  P_VECTORS  10 vetores do arquivo único: variant_type + matched_scope +
             validation_status, TODOS os escopos de cada vetor
SEÇÃO 5 — corpus real
  N   mismatch REAL -> SCOPE_MISMATCH   R  propagation VALID -> VALID
  N0  escopo vem da referência canônica S  propagation NEEDS_REVIEW -> VALID
  O   contrato de preview = zero escrita T  rows fora do alvo: bidirecional
  P   classe B -> decision E worker      U  jobs não afetados: bidirecional
  Q   classe C -> decision E worker      V  counters dos afetados corretos
  Q2  provenance -> decision E worker    W  action log correto (sem widen)
                                         X  atomicidade em 4 superfícies
SEÇÃO 6 — regressão
  Y  retrocompatibilidade dos 70 globais  Z  zero resíduo
SEÇÃO 7 — fronteira e compatibilidade
  AA  2197 aplicada (hash do prosrc)      AD  wrappers finos
  AB  fronteira pública (estática)        AE  proteção de drift do 2196
  AC  GLOBAL legado em runtime            AF  mensagens do worker (runtime)

P1..P10 — vetores de precedência, lidos do arquivo ÚNICO
          test-vectors/variant-type-mapping-scope-vectors.json.

>>> OS EXPECTED VALUES DOS VETORES NÃO SÃO DECLARADOS AQUI. <<<
A Seção 4 abaixo implementa o RUNNER SQL. O dataset e os expected values vivem
só no JSON, e o runner Deno da Edge consome o MESMO arquivo. Duplicar o
expected em dois lugares reintroduziria exatamente a divergência Edge x SQL que
esta frente existe para eliminar.

-------------------------------------------------------------------------------
FIXTURES — NENHUMA GLOBAL
-------------------------------------------------------------------------------
A Seção 0 só LÊ. Todo Variant Type, mapping e alteração de referência nasce e
morre dentro do seu próprio caso, revertido por sentinela.

Combo sintético usado nos testes de precedência:
    NORMAL | HARNESSFOIL2826 | NULL | {}
Escolhido porque tem ZERO mappings no catálogo real (provado na Seção 0), então
nenhum caso pode colidir com dado de produção.

Escopos reais usados: 'base1' e 'base3' (TCGDEX) — existem e estão ativos em
card_set_external_reference, confirmado em 2026-09-14.

-------------------------------------------------------------------------------
GABARITO DE PRODUÇÃO — informativo, não é FAIL
-------------------------------------------------------------------------------
Medido em 2026-09-14, read-only:
  TCGDEX/base3 · HOLO|GALAXY|NULL|{}  -> universo 30, todos classe A
  (30 VALID · 30 decision=PENDING · 30 persistence=PENDING ·
   30 resulting_variant_id NULL · 15 com FIRST_EDITION)
  BASE3: 177 total / 80 VALID / 97 NEEDS_REVIEW
  card_variant de BASE3: 0 · physical_card global: 0
Divergência é INFO. Número de corpus não é contrato de função.

Pré-requisitos: Queries 2191, 2192, 2193, 2194, 2195, 2196 **e 2197** aplicadas.
                (o caso AA exige a 2197 pelo hash do prosrc; sem ela, reprova)
===============================================================================
*/

-- =============================================================================
-- SEÇÃO 0 — INFRAESTRUTURA, PRÉ-REQUISITOS E BASELINE (somente leitura)
-- =============================================================================

CREATE TEMP TABLE _r2826 (
    caso     TEXT PRIMARY KEY,
    veredito TEXT NOT NULL,
    detalhe  TEXT
);

CREATE TEMP TABLE _ctx2826 (k TEXT PRIMARY KEY, v TEXT);

CREATE OR REPLACE FUNCTION pg_temp._chk(p_caso TEXT, p_ok BOOLEAN, p_detalhe TEXT)
RETURNS VOID LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO _r2826(caso, veredito, detalhe)
    VALUES (p_caso, CASE WHEN p_ok THEN 'PASS' ELSE 'FAIL' END, p_detalhe)
    ON CONFLICT (caso) DO UPDATE
       SET veredito = EXCLUDED.veredito, detalhe = EXCLUDED.detalhe;
END;
$f$;

-- =============================================================================
-- IDENTIDADE DE COMBO — EXPRESSÃO ÚNICA (GATE-A-REV-03 §3)
--
-- A identidade de um mapping tem QUATRO dimensões:
--   normalized_type · normalized_foil · normalized_subtype · normalized_stamp
--
-- A v2.0 comparava só type+foil em dois pontos do runner de vetores (prova do
-- mapping GLOBAL real e derivação de matched_scope). Duas dimensões a menos
-- significam duas chances de casar o mapping ERRADO e o vetor "passar".
--
-- Centralizado aqui de propósito: com duas cópias da expressão, uma delas
-- envelhece. Os COALESCE espelham exatamente os índices parciais da Query
-- 2191 (foil/subtype -> '', stamp -> '{}').
--
-- p_scope_global = TRUE  -> external_set_id IS NULL   (escopo GLOBAL)
-- p_scope_global = FALSE -> external_set_id = p_scope (escopo SOURCE_SET)
-- p_vt NULL              -> não filtra por Variant Type
-- =============================================================================
CREATE OR REPLACE FUNCTION pg_temp._map_count(
    p_game UUID, p_src UUID,
    p_scope TEXT, p_scope_global BOOLEAN,
    p_type TEXT, p_foil TEXT, p_sub TEXT, p_stamp TEXT[],
    p_vt UUID DEFAULT NULL
)
RETURNS INTEGER LANGUAGE sql STABLE AS $mapc$
    SELECT count(*)::INTEGER
      FROM public.card_variant_type_external_mapping m
     WHERE m.game_id         = p_game
       AND m.asset_source_id = p_src
       AND (CASE WHEN p_scope_global THEN m.external_set_id IS NULL
                 ELSE m.external_set_id = p_scope END)
       AND m.normalized_type = p_type
       AND COALESCE(m.normalized_foil, '')            = COALESCE(p_foil, '')
       AND COALESCE(m.normalized_subtype, '')         = COALESCE(p_sub, '')
       AND COALESCE(m.normalized_stamp, '{}'::TEXT[]) = COALESCE(p_stamp, '{}'::TEXT[])
       AND (p_vt IS NULL OR m.variant_type_id = p_vt)
$mapc$;

CREATE OR REPLACE FUNCTION pg_temp._snap2826()
RETURNS TABLE(k TEXT, v TEXT)
LANGUAGE sql AS $snap$
    SELECT 'mappings_total',
           (SELECT count(*)::TEXT FROM public.card_variant_type_external_mapping)
    UNION ALL SELECT 'mappings_global',
           (SELECT count(*)::TEXT FROM public.card_variant_type_external_mapping
             WHERE external_set_id IS NULL)
    UNION ALL SELECT 'mappings_scoped',
           (SELECT count(*)::TEXT FROM public.card_variant_type_external_mapping
             WHERE external_set_id IS NOT NULL)
    UNION ALL SELECT 'variant_types',
           (SELECT count(*)::TEXT FROM public.card_variant_type)
    UNION ALL SELECT 'card_variants',
           (SELECT count(*)::TEXT FROM public.card_variant)
    UNION ALL SELECT 'action_log',
           (SELECT count(*)::TEXT FROM public.catalog_admin_action_log)
    UNION ALL SELECT 'refs_ativas',
           (SELECT count(*)::TEXT FROM public.card_set_external_reference WHERE is_active)
    -- Digest de ROW INTEIRA do catálogo de mapping: pega vazamento em
    -- QUALQUER coluna, inclusive as que vierem no futuro.
    UNION ALL SELECT 'mapping_rows_digest',
           (SELECT COALESCE(md5(string_agg(
                       m.id::TEXT || ':' || to_jsonb(m)::TEXT, '|' ORDER BY m.id)), 'VAZIO')
              FROM public.card_variant_type_external_mapping m)
    -- Digest de ROW INTEIRA das linhas de staging dos jobs STAGED.
    UNION ALL SELECT 'staged_rows_digest',
           (SELECT COALESCE(md5(string_agg(
                       r.id::TEXT || ':' || to_jsonb(r)::TEXT, '|' ORDER BY r.id)), 'VAZIO')
              FROM public.catalog_variant_import_row r
              JOIN public.catalog_variant_import_job j ON j.id = r.job_id
             WHERE j.status = 'STAGED')
    UNION ALL SELECT 'jobs_rows_digest',
           (SELECT COALESCE(md5(string_agg(
                       j.id::TEXT || ':' || to_jsonb(j)::TEXT, '|' ORDER BY j.id)), 'VAZIO')
              FROM public.catalog_variant_import_job j)
    UNION ALL SELECT 'residuo_vt_harness',
           (SELECT count(*)::TEXT FROM public.card_variant_type WHERE code LIKE 'HARNESS%')
    UNION ALL SELECT 'residuo_map_harness',
           (SELECT count(*)::TEXT FROM public.card_variant_type_external_mapping
             WHERE normalized_foil = 'HARNESSFOIL2826')
$snap$;

CREATE TEMP TABLE _base2826 AS SELECT k, v FROM pg_temp._snap2826();

DO $s0$
DECLARE
    v_admin UUID; v_game UUID; v_src UUID; v_src2 UUID;
    v_cs_base1 UUID; v_cs_base3 UUID; v_vt_holo UUID; v_vt_galaxy UUID;
    v_res TEXT; v_n INTEGER;
BEGIN
    SELECT string_agg(k || '=' || v, ', ') INTO v_res
      FROM _base2826 WHERE k LIKE 'residuo_%' AND v <> '0';
    IF v_res IS NOT NULL THEN
        RAISE EXCEPTION 'S0 ABORT: ja existe residuo de harness na base (%). Limpe antes — o caso Z nao distingue residuo antigo de novo.', v_res;
    END IF;

    -- Estrutura da foundation precisa existir. Sem isto, tudo o mais é teatro.
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public'
                      AND table_name='card_variant_type_external_mapping'
                      AND column_name='external_set_id') THEN
        RAISE EXCEPTION 'S0 ABORT: coluna external_set_id nao existe. Query 2191 nao aplicada. NAO registrar como PASS.';
    END IF;

    FOREACH v_res IN ARRAY ARRAY['resolve_variant_mapping_scope',
                                 'variant_type_mapping_impact',
                                 'variant_type_mapping_decision',
                                 'apply_variant_type_mapping',
                                 'lookup_variant_type_for_row'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                        WHERE n.nspname='internal' AND p.proname = v_res) THEN
            RAISE EXCEPTION 'S0 ABORT: internal.%() nao existe. Queries 2192/2193/2196 nao aplicadas.', v_res;
        END IF;
    END LOOP;

    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public'
                      AND p.proname IN ('admin_preview_catalog_variant_import_mapping',
                                        'admin_resolve_catalog_variant_import_mapping_for_set')
                    HAVING count(*) = 2) THEN
        RAISE EXCEPTION 'S0 ABORT: RPCs publicas de preview/scoped ausentes. Queries 2194/2195 nao aplicadas.';
    END IF;

    SELECT id INTO v_admin FROM public.admin_user ORDER BY id LIMIT 1;
    IF v_admin IS NULL THEN
        RAISE EXCEPTION 'S0 ABORT: nenhum administrador em public.admin_user. O contrato NAO PODE ser provado nesta base — FAIL HIGH.';
    END IF;

    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code='TCGDEX';
    IF v_game IS NULL OR v_src IS NULL THEN
        RAISE EXCEPTION 'S0 ABORT: Game POKEMON e/ou asset_source TCGDEX nao encontrados.';
    END IF;

    -- Segunda Fonte, para o caso L (isolamento entre Fontes).
    SELECT id INTO v_src2 FROM public.asset_source WHERE code <> 'TCGDEX' ORDER BY code LIMIT 1;

    SELECT cs.id INTO v_cs_base1 FROM public.card_set cs WHERE cs.code='BASE1';
    SELECT cs.id INTO v_cs_base3 FROM public.card_set cs WHERE cs.code='BASE3';
    IF v_cs_base1 IS NULL OR v_cs_base3 IS NULL THEN
        RAISE EXCEPTION 'S0 ABORT: Card Sets BASE1/BASE3 nao encontrados.';
    END IF;

    -- Os dois escopos precisam existir e estar ATIVOS.
    SELECT count(*) INTO v_n FROM public.card_set_external_reference r
     WHERE r.asset_source_id = v_src AND r.is_active
       AND r.external_set_id IN ('base1','base3');
    IF v_n <> 2 THEN
        RAISE EXCEPTION 'S0 ABORT: esperadas 2 referencias TCGDEX ativas (base1, base3), encontradas %.', v_n;
    END IF;

    SELECT id INTO v_vt_holo   FROM public.card_variant_type WHERE game_id=v_game AND code='HOLO';
    SELECT id INTO v_vt_galaxy FROM public.card_variant_type WHERE game_id=v_game AND code='GALAXY_HOLO';
    IF v_vt_holo IS NULL OR v_vt_galaxy IS NULL THEN
        RAISE EXCEPTION 'S0 ABORT: Variant Types HOLO e/ou GALAXY_HOLO nao encontrados.';
    END IF;

    -- O combo sintético precisa estar LIVRE, senão os casos de precedência
    -- colidiriam com dado real.
    SELECT count(*) INTO v_n FROM public.card_variant_type_external_mapping
     WHERE normalized_foil = 'HARNESSFOIL2826';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'S0 ABORT: combo sintetico HARNESSFOIL2826 ja existe no catalogo (% linhas).', v_n;
    END IF;

    INSERT INTO _ctx2826 VALUES
        ('admin', v_admin::TEXT), ('game', v_game::TEXT), ('src', v_src::TEXT),
        ('src2', COALESCE(v_src2::TEXT, '')),
        ('cs_base1', v_cs_base1::TEXT), ('cs_base3', v_cs_base3::TEXT),
        ('vt_holo', v_vt_holo::TEXT), ('vt_galaxy', v_vt_galaxy::TEXT);
END;
$s0$;

-- =============================================================================
-- SEÇÃO 1 — ESTRUTURA: COLUNA, CHECK, FK (casos A, B, C, D)
-- =============================================================================

DO $a$
DECLARE v_fails TEXT := ''; v_def TEXT;
BEGIN
    -- A.1 coluna existe, TEXT, nullable
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='card_variant_type_external_mapping'
                      AND column_name='external_set_id' AND data_type='text'
                      AND is_nullable='YES') THEN
        v_fails := v_fails || 'A1(coluna ausente, nao-TEXT ou NOT NULL) ';
    END IF;

    -- A.2 CHECK de não-vazio
    SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint
     WHERE conrelid='public.card_variant_type_external_mapping'::regclass
       AND conname='ck_card_variant_type_external_mapping_external_set_id_not_blank';
    IF v_def IS NULL THEN
        v_fails := v_fails || 'A2(CHECK de nao-vazio ausente) ';
    END IF;

    -- A.3 FK composta com MATCH SIMPLE e ON DELETE RESTRICT.
    -- MATCH SIMPLE é o default e NÃO aparece no texto de
    -- pg_get_constraintdef — o que se prova é a AUSÊNCIA de
    -- "MATCH FULL", que é o que quebraria os globais (caso B).
    SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint
     WHERE conrelid='public.card_variant_type_external_mapping'::regclass
       AND conname='fk_card_variant_type_external_mapping_source_set';
    IF v_def IS NULL THEN
        v_fails := v_fails || 'A3(FK composta ausente) ';
    ELSE
        IF v_def NOT LIKE '%card_set_external_reference(asset_source_id, external_set_id)%' THEN
            v_fails := v_fails || 'A3(FK nao aponta para a UNIQUE canonica) ';
        END IF;
        IF v_def LIKE '%MATCH FULL%' THEN
            v_fails := v_fails || 'A3(MATCH FULL — quebraria TODOS os mappings globais) ';
        END IF;
        IF v_def NOT LIKE '%ON DELETE RESTRICT%' THEN
            v_fails := v_fails || 'A3(FK sem ON DELETE RESTRICT) ';
        END IF;
    END IF;

    PERFORM pg_temp._chk('A', v_fails = '',
        COALESCE(NULLIF(v_fails,''), 'coluna TEXT nullable + CHECK de nao-vazio + FK composta para a UNIQUE canonica, sem MATCH FULL, ON DELETE RESTRICT'));
END;
$a$;

-- B — MATCH SIMPLE aceita linha GLOBAL (external_set_id NULL) sem
--     exigir correspondencia em card_set_external_reference.
--     ESTE É O CASO QUE TRAVA A REGRESSÃO MATCH FULL.
DO $b$
DECLARE
    v_game UUID; v_src UUID; v_vt UUID; v_id UUID;
    v_ok BOOLEAN := FALSE; v_rolled BOOLEAN := FALSE; v_fails TEXT := '';
BEGIN
    SELECT v::UUID INTO v_game FROM _ctx2826 WHERE k='game';
    SELECT v::UUID INTO v_src  FROM _ctx2826 WHERE k='src';
    SELECT v::UUID INTO v_vt   FROM _ctx2826 WHERE k='vt_holo';

    BEGIN
        INSERT INTO public.card_variant_type_external_mapping
            (game_id, asset_source_id, external_set_id,
             external_type, external_foil, normalized_type, normalized_foil, variant_type_id)
        VALUES (v_game, v_src, NULL,
                'NORMAL', 'HARNESSFOIL2826', 'NORMAL', 'HARNESSFOIL2826', v_vt)
        RETURNING id INTO v_id;

        v_ok := (v_id IS NOT NULL);
        RAISE EXCEPTION 'HARNESS_B_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_B_ROLLBACK' THEN v_rolled := TRUE;
        ELSE v_fails := v_fails || 'B(INSERT global REJEITADO: ' || SQLERRM || ') '; END IF;
    END;

    IF NOT v_ok    THEN v_fails := v_fails || 'B(linha global nao foi aceita) '; END IF;
    IF NOT v_rolled THEN v_fails := v_fails || 'B(sentinela nao disparou) '; END IF;

    PERFORM pg_temp._chk('B', v_fails = '',
        COALESCE(NULLIF(v_fails,''), 'MATCH SIMPLE: mapping GLOBAL (external_set_id NULL) aceito sem referencia externa correspondente, e revertido'));
END;
$b$;

-- C — FK scoped VÁLIDA é aceita.  |  D — FK scoped INEXISTENTE é rejeitada.
DO $cd$
DECLARE
    v_game UUID; v_src UUID; v_vt UUID; v_id UUID;
    v_c_ok BOOLEAN := FALSE; v_d_raised BOOLEAN := FALSE;
    v_rolled BOOLEAN := FALSE; v_msg TEXT; v_fails TEXT := '';
BEGIN
    SELECT v::UUID INTO v_game FROM _ctx2826 WHERE k='game';
    SELECT v::UUID INTO v_src  FROM _ctx2826 WHERE k='src';
    SELECT v::UUID INTO v_vt   FROM _ctx2826 WHERE k='vt_holo';

    BEGIN
        -- C: escopo real e ativo
        INSERT INTO public.card_variant_type_external_mapping
            (game_id, asset_source_id, external_set_id,
             external_type, external_foil, normalized_type, normalized_foil, variant_type_id)
        VALUES (v_game, v_src, 'base3',
                'NORMAL', 'HARNESSFOIL2826', 'NORMAL', 'HARNESSFOIL2826', v_vt)
        RETURNING id INTO v_id;
        v_c_ok := (v_id IS NOT NULL);

        -- D: escopo inexistente na referência canônica
        BEGIN
            INSERT INTO public.card_variant_type_external_mapping
                (game_id, asset_source_id, external_set_id,
                 external_type, external_foil, normalized_type, normalized_foil, variant_type_id)
            VALUES (v_game, v_src, 'harness-set-inexistente-2826',
                    'NORMAL', 'HARNESSFOIL2826', 'NORMAL', 'HARNESSFOIL2826', v_vt);
        EXCEPTION WHEN foreign_key_violation THEN
            v_d_raised := TRUE; v_msg := SQLERRM;
        END;

        RAISE EXCEPTION 'HARNESS_CD_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_CD_ROLLBACK' THEN v_rolled := TRUE;
        ELSE v_fails := v_fails || 'CD(excecao inesperada: ' || SQLERRM || ') '; END IF;
    END;

    IF NOT v_rolled THEN v_fails := v_fails || 'CD(sentinela nao disparou) '; END IF;

    PERFORM pg_temp._chk('C', v_c_ok AND v_fails = '',
        CASE WHEN v_c_ok THEN 'mapping SCOPED com external_set_id=base3 aceito pela FK composta'
             ELSE 'scoped valido REJEITADO' END);
    PERFORM pg_temp._chk('D', v_d_raised,
        CASE WHEN v_d_raised THEN 'escopo inexistente rejeitado por foreign_key_violation: ' || COALESCE(v_msg,'')
             ELSE 'FALHA: escopo inexistente foi ACEITO — a FK nao esta protegendo nada' END);
END;
$cd$;

-- =============================================================================
-- SEÇÃO 2 — UNICIDADE (casos E, F, G, H)
-- =============================================================================

DO $efgh$
DECLARE
    v_game UUID; v_src UUID; v_vt UUID; v_vt2 UUID;
    v_e BOOLEAN := FALSE; v_f BOOLEAN := FALSE;
    v_g BOOLEAN := FALSE; v_h BOOLEAN := FALSE;
    v_rolled BOOLEAN := FALSE; v_fails TEXT := '';
BEGIN
    SELECT v::UUID INTO v_game FROM _ctx2826 WHERE k='game';
    SELECT v::UUID INTO v_src  FROM _ctx2826 WHERE k='src';
    SELECT v::UUID INTO v_vt   FROM _ctx2826 WHERE k='vt_holo';
    SELECT v::UUID INTO v_vt2  FROM _ctx2826 WHERE k='vt_galaxy';

    BEGIN
        -- G: global + scoped do MESMO combo coexistem
        INSERT INTO public.card_variant_type_external_mapping
            (game_id, asset_source_id, external_set_id,
             external_type, external_foil, normalized_type, normalized_foil, variant_type_id)
        VALUES (v_game, v_src, NULL,
                'NORMAL','HARNESSFOIL2826','NORMAL','HARNESSFOIL2826', v_vt);

        INSERT INTO public.card_variant_type_external_mapping
            (game_id, asset_source_id, external_set_id,
             external_type, external_foil, normalized_type, normalized_foil, variant_type_id)
        VALUES (v_game, v_src, 'base3',
                'NORMAL','HARNESSFOIL2826','NORMAL','HARNESSFOIL2826', v_vt2);
        v_g := TRUE;

        -- H: dois scoped de Sets DIFERENTES coexistem
        INSERT INTO public.card_variant_type_external_mapping
            (game_id, asset_source_id, external_set_id,
             external_type, external_foil, normalized_type, normalized_foil, variant_type_id)
        VALUES (v_game, v_src, 'base1',
                'NORMAL','HARNESSFOIL2826','NORMAL','HARNESSFOIL2826', v_vt);
        v_h := TRUE;

        -- E: segundo GLOBAL do mesmo combo precisa falhar
        BEGIN
            INSERT INTO public.card_variant_type_external_mapping
                (game_id, asset_source_id, external_set_id,
                 external_type, external_foil, normalized_type, normalized_foil, variant_type_id)
            VALUES (v_game, v_src, NULL,
                    'NORMAL','HARNESSFOIL2826','NORMAL','HARNESSFOIL2826', v_vt2);
        EXCEPTION WHEN unique_violation THEN v_e := TRUE;
        END;

        -- F: segundo SCOPED do mesmo (set, combo) precisa falhar
        BEGIN
            INSERT INTO public.card_variant_type_external_mapping
                (game_id, asset_source_id, external_set_id,
                 external_type, external_foil, normalized_type, normalized_foil, variant_type_id)
            VALUES (v_game, v_src, 'base3',
                    'NORMAL','HARNESSFOIL2826','NORMAL','HARNESSFOIL2826', v_vt);
        EXCEPTION WHEN unique_violation THEN v_f := TRUE;
        END;

        RAISE EXCEPTION 'HARNESS_EFGH_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_EFGH_ROLLBACK' THEN v_rolled := TRUE;
        ELSE v_fails := v_fails || 'EFGH(excecao inesperada: ' || SQLERRM || ') '; END IF;
    END;

    IF NOT v_rolled THEN v_fails := v_fails || 'EFGH(sentinela nao disparou) '; END IF;

    PERFORM pg_temp._chk('E', v_e AND v_fails='',
        CASE WHEN v_e THEN 'segundo mapping GLOBAL do mesmo combo rejeitado por unique_violation'
             ELSE 'FALHA: dois globais do mesmo combo coexistiram' END);
    PERFORM pg_temp._chk('F', v_f AND v_fails='',
        CASE WHEN v_f THEN 'segundo mapping SCOPED do mesmo (source-set, combo) rejeitado por unique_violation'
             ELSE 'FALHA: dois scoped do mesmo set/combo coexistiram' END);
    PERFORM pg_temp._chk('G', v_g AND v_fails='',
        CASE WHEN v_g THEN 'global e scoped do MESMO combo coexistem (indices parciais disjuntos)'
             ELSE 'FALHA: coexistencia global+scoped rejeitada' END);
    PERFORM pg_temp._chk('H', v_h AND v_fails='',
        CASE WHEN v_h THEN 'dois scoped de source-sets diferentes (base1, base3) coexistem'
             ELSE 'FALHA: scoped de Sets diferentes colidiram' END);
END;
$efgh$;

-- =============================================================================
-- SEÇÃO 3 — PRECEDÊNCIA (casos I, J, K, L, M)
-- =============================================================================

DO $ijklm$
DECLARE
    v_game UUID; v_src UUID; v_src2 UUID; v_vt UUID; v_vt2 UUID;
    v_cs1 UUID; v_cs3 UUID; v_ref UUID;
    v_got UUID; v_rolled BOOLEAN := FALSE; v_fails TEXT := '';
    v_i BOOLEAN := FALSE; v_j BOOLEAN := FALSE; v_k BOOLEAN := FALSE;
    v_l BOOLEAN := FALSE; v_m BOOLEAN := FALSE; v_l_skip BOOLEAN := FALSE;
BEGIN
    SELECT v::UUID INTO v_game FROM _ctx2826 WHERE k='game';
    SELECT v::UUID INTO v_src  FROM _ctx2826 WHERE k='src';
    SELECT NULLIF(v,'')::UUID INTO v_src2 FROM _ctx2826 WHERE k='src2';
    SELECT v::UUID INTO v_vt   FROM _ctx2826 WHERE k='vt_holo';
    SELECT v::UUID INTO v_vt2  FROM _ctx2826 WHERE k='vt_galaxy';
    SELECT v::UUID INTO v_cs1  FROM _ctx2826 WHERE k='cs_base1';
    SELECT v::UUID INTO v_cs3  FROM _ctx2826 WHERE k='cs_base3';

    -- K precisa ser avaliado ANTES de qualquer mapping existir.
    v_got := internal.lookup_variant_type_for_row(
                 v_game, v_src, v_cs3, 'NORMAL', 'HARNESSFOIL2826', NULL, NULL);
    v_k := (v_got IS NULL);

    BEGIN
        -- global -> vt_holo ; scoped base3 -> vt_galaxy
        INSERT INTO public.card_variant_type_external_mapping
            (game_id, asset_source_id, external_set_id,
             external_type, external_foil, normalized_type, normalized_foil, variant_type_id)
        VALUES (v_game, v_src, NULL,
                'NORMAL','HARNESSFOIL2826','NORMAL','HARNESSFOIL2826', v_vt);

        INSERT INTO public.card_variant_type_external_mapping
            (game_id, asset_source_id, external_set_id,
             external_type, external_foil, normalized_type, normalized_foil, variant_type_id)
        VALUES (v_game, v_src, 'base3',
                'NORMAL','HARNESSFOIL2826','NORMAL','HARNESSFOIL2826', v_vt2);

        -- I — escopo base3: scoped VENCE
        v_got := internal.lookup_variant_type_for_row(
                     v_game, v_src, v_cs3, 'NORMAL', 'HARNESSFOIL2826', NULL, NULL);
        v_i := (v_got = v_vt2);

        -- J — escopo base1 (sem scoped proprio): fallback GLOBAL
        v_got := internal.lookup_variant_type_for_row(
                     v_game, v_src, v_cs1, 'NORMAL', 'HARNESSFOIL2826', NULL, NULL);
        v_j := (v_got = v_vt);

        -- L — Fonte diferente nao cruza
        IF v_src2 IS NULL THEN
            v_l_skip := TRUE;
        ELSE
            v_got := internal.lookup_variant_type_for_row(
                         v_game, v_src2, v_cs3, 'NORMAL', 'HARNESSFOIL2826', NULL, NULL);
            v_l := (v_got IS NULL);
        END IF;

        -- M — referencia canonica INATIVA: escopo deixa de existir,
        --     lookup cai no GLOBAL. Prova que is_active participa e
        --     que o escopo nao e lido do job.
        UPDATE public.card_set_external_reference
           SET is_active = FALSE
         WHERE asset_source_id = v_src AND external_set_id = 'base3'
        RETURNING id INTO v_ref;

        v_got := internal.lookup_variant_type_for_row(
                     v_game, v_src, v_cs3, 'NORMAL', 'HARNESSFOIL2826', NULL, NULL);
        v_m := (v_got = v_vt);

        RAISE EXCEPTION 'HARNESS_IJKLM_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_IJKLM_ROLLBACK' THEN v_rolled := TRUE;
        ELSE v_fails := v_fails || 'IJKLM(excecao inesperada: ' || SQLERRM || ') '; END IF;
    END;

    IF NOT v_rolled THEN v_fails := v_fails || 'IJKLM(sentinela nao disparou) '; END IF;

    -- A referencia base3 precisa ter voltado a ATIVA.
    IF NOT EXISTS (SELECT 1 FROM public.card_set_external_reference
                    WHERE asset_source_id=v_src AND external_set_id='base3' AND is_active) THEN
        v_fails := v_fails || 'IJKLM(referencia base3 NAO voltou a ativa apos o rollback) ';
    END IF;

    PERFORM pg_temp._chk('I', v_i AND v_fails='',
        CASE WHEN v_i THEN 'precedencia: com scoped e global presentes, o SCOPED venceu'
             ELSE 'FALHA: scoped nao venceu' END);
    PERFORM pg_temp._chk('J', v_j AND v_fails='',
        CASE WHEN v_j THEN 'fallback: Set sem scoped proprio resolveu pelo GLOBAL'
             ELSE 'FALHA: fallback global nao ocorreu' END);
    PERFORM pg_temp._chk('K', v_k,
        CASE WHEN v_k THEN 'sem nenhum mapping, lookup devolveu NULL (linha permaneceria NEEDS_REVIEW)'
             ELSE 'FALHA: lookup devolveu Variant Type sem mapping algum' END);
    PERFORM pg_temp._chk('L',
        CASE WHEN v_l_skip THEN FALSE ELSE v_l AND v_fails='' END,
        CASE WHEN v_l_skip THEN 'FALHA HIGH: nenhuma segunda asset_source na base — o isolamento entre Fontes NAO pode ser provado. Nao mascarar como PASS.'
             WHEN v_l THEN 'isolamento: mesma external_set_id em Fonte diferente NAO casou'
             ELSE 'FALHA: lookup cruzou Fontes' END);
    PERFORM pg_temp._chk('M', v_m AND v_fails='',
        CASE WHEN v_m THEN 'referencia canonica INATIVA: escopo deixou de valer e o lookup caiu no GLOBAL'
             ELSE 'FALHA: is_active nao participa da resolucao de escopo' END);
END;
$ijklm$;

-- =============================================================================
-- SEÇÃO 4 — RUNNER DOS VETORES COMPARTILHADOS P1..P10
--
-- >>> CANAL DE CARGA — FECHADO EM GATE-A-REV-01 §8 <<<
--
-- A v1.0 declarava P_VECTORS como FAIL deliberado, porque não havia canal para
-- levar o JSON até dentro do SQL. FAIL permanente é ruído: um gate que sempre
-- reprova deixa de distinguir "quebrou" de "ainda não". O canal agora existe.
--
-- CONTRATO DE MONTAGEM DO PAYLOAD — obrigatório, mecânico, uma linha:
--
--   1. Ler test-vectors/variant-type-mapping-scope-vectors.json INTEIRO.
--   2. Substituir o literal `{"vectors":[]}` do bloco PAYLOAD abaixo pelo
--      conteúdo integral do arquivo, entre os delimitadores $vecjson$.
--   3. Não editar mais nada. Não reformatar. Não remover campos.
--
-- O delimitador $vecjson$ é dollar-quoting: o JSON entra literal, sem escaping.
-- NENHUM expected value é declarado aqui — eles vivem só no arquivo. O runner
-- Deno da Edge consome o MESMO arquivo, com as MESMAS bindings (bloco
-- `bindings` do JSON). É isso que torna a paridade Edge × SQL verificável em
-- vez de afirmada.
--
-- Se o payload continuar sendo o default vazio, esta seção ABORTA a execução
-- inteira — o harness não roda sem os seus vetores. Isso é diferente de um
-- caso reprovado: é pré-requisito ausente, da mesma natureza dos ABORTs da
-- Seção 0.
--
-- >>> BINDINGS — por que existem <<<
-- Os vetores P1..P7 descrevem combos abstratos (HOLO|GALAXY, NORMAL|GALAXY).
-- Esses combos COLIDEM com mappings reais de produção: existe um global
-- TCGDEX HOLO|GALAXY -> GALAXY_HOLO (medido em 2026-09-14). Executar os
-- vetores sintéticos literalmente devolveria o mapping de produção e o vetor
-- "provaria" algo que não é seu. Por isso o bloco `bindings` do JSON define,
-- para os DOIS runners, como cada símbolo vira objeto físico — em especial a
-- substituição do foil sintético por HARNESSFOIL2826, combo provado livre na
-- Seção 0. A estrutura RELACIONAL do vetor (mesmo combo no mapping e no
-- lookup, escopos distintos, Fontes distintas) é preservada integralmente.
-- P8/P9/P10 são vetores de corpus REAL e não sofrem substituição.
-- =============================================================================

CREATE TEMP TABLE _vec2826 (payload JSONB);

-- >>> PAYLOAD — substituir o literal abaixo pelo JSON integral <<<
INSERT INTO _vec2826(payload) VALUES ($vecjson${
  "$schema_note": "Vetores COMPARTILHADOS de precedência do mapping de Card Variant Type. Arquivo ÚNICO, consumido por DOIS runners: (1) o harness SQL 2826, Seção 4; (2) o teste offline Deno da Edge import-card-variants. Os expected values existem SÓ aqui — nenhum runner pode declarar o seu. Se os dois runners divergirem em qualquer vetor, a paridade Edge x SQL está quebrada e o GATE-B falha.",
  "version": "1.0",
  "status": "PROPOSTA — NAO EXECUTADO",
  "mandato": "CARD-VARIANTS — EDITORIAL-CONVERGENCE-16 / SOURCE-SET-SCOPED-FOUNDATION / GATE-A-REV-03",

  "contract": {
    "precedence": ["scoped", "global", "none"],
    "tie_breakers_forbidden": ["created_at", "updated_at", "display_order", "is_active", "id"],
    "cascade_levels": 1,
    "scope_authority": "card_set_external_reference (is_active = true)",
    "scope_authority_forbidden": "catalog_variant_import_job.external_set_id",
    "no_match_outcome": "NEEDS_REVIEW"
  },

  "bindings": {
    "$note": "ACRESCENTADO EM GATE-A-REV-01. Como cada simbolo abstrato dos vetores vira objeto fisico. Os DOIS runners (harness SQL 2826 Secao 4 e teste offline Deno) aplicam EXATAMENTE estas regras. Sem este bloco, cada runner inventaria a sua propria ligacao e a paridade seria afirmada, nao verificada.",

    "$why_foil_substitution": "Os combos dos vetores P1-P7 (HOLO|GALAXY, NORMAL|GALAXY) COLIDEM com dado real: existe um mapping GLOBAL TCGDEX HOLO|GALAXY -> GALAXY_HOLO no catalogo de producao (medido em 2026-09-14, mapping a30ab1d7-461d-490a-adac-6bd4f69e24d7). Executar os vetores sinteticos literalmente devolveria o mapping de producao, e o vetor 'passaria' provando outra coisa. Por isso o foil dos vetores SINTETICOS e substituido por HARNESSFOIL2826, combo provado livre (zero mappings) na Secao 0 do harness. A estrutura RELACIONAL do vetor — mesmo combo no mapping e no lookup, escopos distintos, Fontes distintas — e preservada integralmente. O `type` NAO e substituido: HOLO e NORMAL continuam distinguindo P1/P2/P3 de P4/P5.",

    "synthetic_vectors": ["P1", "P2", "P3", "P4", "P5", "P6", "P7"],
    "real_corpus_vectors": ["P8", "P9", "P10"],

    "combo": {
      "synthetic": { "foil": "HARNESSFOIL2826", "type": "literal do vetor", "subtype": "literal do vetor", "stamp": "NULL" },
      "real_corpus": "sem substituicao — combo literal do vetor"
    },

    "variant_type": {
      "VT_*": "simbolo de fixture. O runner CRIA um card_variant_type com code = o proprio simbolo, dentro da sentinela, e o destroi no rollback. code respeita ^[A-Z][A-Z0-9_]*$ (CHECK ck_card_variant_type_code_format) e recebe display_order = max(display_order do Game) + n.",
      "outros": "code REAL, ja existente em card_variant_type do Game POKEMON (ex.: HOLO, GALAXY_HOLO). Nunca criado, apenas resolvido."
    },

    "source": {
      "default": "TCGDEX",
      "SRC_A": "TCGDEX",
      "SRC_B": "POKEMON_TCG_API",
      "$note": "POKEMON_TCG_API existe em asset_source e tem ZERO card_set_external_reference (medido), entao a referencia de fixture de P7 nasce sem conflito com dado real."
    },

    "scope": {
      "set-alpha": { "card_set": "ME5.5", "criacao": "INSERT de card_set_external_reference na sentinela" },
      "set-beta":  { "card_set": "RC",    "criacao": "INSERT de card_set_external_reference na sentinela" },
      "null":      { "card_set": "SP",    "criacao": "nenhuma — o Set fica SEM referencia ativa, que e o cenario de P6" },
      "base3":     { "card_set": "BASE3", "criacao": "referencia REAL ja existente e ativa" },
      "sv03.5 | sv05 | sv06": { "criacao": "referencias REAIS ja existentes e ativas" },
      "$why_insert_only": "trg_020_govern_card_set_external_reference torna external_set_id IMUTAVEL em UPDATE (levanta CARD_SET_EXTERNAL_REFERENCE_EXTERNAL_SET_ID_IMMUTABLE). Logo escopo de fixture SO pode nascer por INSERT, e so em Card Set que ainda nao tenha referencia para aquela Fonte — por causa do UNIQUE (card_set_id, asset_source_id). ME5.5, RC e SP foram escolhidos por serem exatamente os 3 Card Sets sem referencia TCGDEX (medido em 2026-09-14). Se isso mudar, o runner FALHA declarando rebase de bindings, em vez de adaptar em silencio."
    },

    "isolation": "Cada vetor roda limpo: o runner apaga, ao fim de cada vetor, todos os mappings de fixture (foil HARNESSFOIL2826, variant_type VT_*, escopos set-alpha/set-beta, e o override base3 dos vetores reais). O vetor seguinte nao herda estado do anterior."
  },

  "notes": [
    "combo = (normalized_type, normalized_foil, normalized_subtype, normalized_stamp) RESIDUAL, nunca bruto.",
    "`mappings` descreve o estado do catálogo de mapping no momento do lookup.",
    "`expected.variant_type` null significa: nenhum mapping casa -> a linha permanece NEEDS_REVIEW.",
    "Os vetores P8/P9/P10 referenciam o corpus REAL (BASE3 e os três modernos) e servem de ponte entre o teste sintético e o gabarito de produção."
  ],

  "vectors": [
    {
      "id": "P1",
      "title": "sem scoped, global existe -> global",
      "job_scope": "set-alpha",
      "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null },
      "mappings": [
        { "scope": null, "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "VT_GLOBAL" }
      ],
      "expected": { "variant_type": "VT_GLOBAL", "matched_scope": "GLOBAL" }
    },
    {
      "id": "P2",
      "title": "scoped e global existem -> scoped VENCE",
      "job_scope": "set-alpha",
      "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null },
      "mappings": [
        { "scope": null, "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "VT_GLOBAL" },
        { "scope": "set-alpha", "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "VT_SCOPED" }
      ],
      "expected": { "variant_type": "VT_SCOPED", "matched_scope": "SOURCE_SET" }
    },
    {
      "id": "P3",
      "title": "scoped existe para OUTRO Set -> global (isolamento entre Sets)",
      "job_scope": "set-alpha",
      "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null },
      "mappings": [
        { "scope": null, "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "VT_GLOBAL" },
        { "scope": "set-beta", "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "VT_SCOPED_BETA" }
      ],
      "expected": { "variant_type": "VT_GLOBAL", "matched_scope": "GLOBAL" }
    },
    {
      "id": "P4",
      "title": "scoped existe e global NAO -> scoped",
      "job_scope": "set-alpha",
      "combo": { "type": "NORMAL", "foil": "GALAXY", "subtype": null, "stamp": null },
      "mappings": [
        { "scope": "set-alpha", "combo": { "type": "NORMAL", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "VT_SCOPED" }
      ],
      "expected": { "variant_type": "VT_SCOPED", "matched_scope": "SOURCE_SET" }
    },
    {
      "id": "P5",
      "title": "nenhum mapping -> NEEDS_REVIEW",
      "job_scope": "set-alpha",
      "combo": { "type": "NORMAL", "foil": "GALAXY", "subtype": null, "stamp": null },
      "mappings": [],
      "expected": { "variant_type": null, "matched_scope": null, "validation_status": "NEEDS_REVIEW" }
    },
    {
      "id": "P6",
      "title": "Card Set SEM referencia externa ativa -> somente GLOBAL e considerado",
      "job_scope": null,
      "job_scope_note": "card_set_external_reference ausente ou is_active = false. O escopo NAO e inventado, nem lido do job.",
      "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null },
      "mappings": [
        { "scope": null, "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "VT_GLOBAL" },
        { "scope": "set-alpha", "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "VT_SCOPED" }
      ],
      "expected": { "variant_type": "VT_GLOBAL", "matched_scope": "GLOBAL" }
    },
    {
      "id": "P7",
      "title": "mesma external_set_id em Fonte DIFERENTE -> nao cruza source",
      "job_scope": "set-alpha",
      "job_source": "SRC_A",
      "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null },
      "mappings": [
        { "scope": "set-alpha", "source": "SRC_B", "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "VT_SCOPED_OTHER_SOURCE" }
      ],
      "expected": { "variant_type": null, "matched_scope": null, "validation_status": "NEEDS_REVIEW" }
    },
    {
      "id": "P8",
      "title": "CASO REAL — TCGDEX / base3 / HOLO|GALAXY -> HOLO",
      "job_scope": "base3",
      "job_source": "TCGDEX",
      "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null },
      "mappings": [
        { "scope": null, "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "GALAXY_HOLO" },
        { "scope": "base3", "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "HOLO" }
      ],
      "expected": { "variant_type": "HOLO", "matched_scope": "SOURCE_SET" },
      "corpus_note": "30 rows LIVE em BASE3 (15 sem FIRST_EDITION + 15 com). NAO criar este override no GATE-A."
    },
    {
      "id": "P9",
      "title": "CASO REAL — modernos preservados no GLOBAL",
      "job_scope": ["sv03.5", "sv05", "sv06"],
      "job_source": "TCGDEX",
      "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null },
      "mappings": [
        { "scope": null, "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "GALAXY_HOLO" },
        { "scope": "base3", "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "HOLO" }
      ],
      "expected": { "variant_type": "GALAXY_HOLO", "matched_scope": "GLOBAL" },
      "corpus_note": "SV3.5 #094 Gengar, SV5 #121 Miraidon, SV6 #022 Sinistcha — 3 card_variant canonicos. O override de base3 NAO pode toca-los."
    },
    {
      "id": "P10",
      "title": "CASO REAL — TCGDEX / base3 / NORMAL|GALAXY sem override -> NEEDS_REVIEW",
      "job_scope": "base3",
      "job_source": "TCGDEX",
      "combo": { "type": "NORMAL", "foil": "GALAXY", "subtype": null, "stamp": null },
      "mappings": [
        { "scope": null, "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "GALAXY_HOLO" },
        { "scope": "base3", "combo": { "type": "HOLO", "foil": "GALAXY", "subtype": null, "stamp": null }, "variant_type": "HOLO" }
      ],
      "expected": { "variant_type": null, "matched_scope": null, "validation_status": "NEEDS_REVIEW" },
      "corpus_note": "As 92 rows NORMAL|GALAXY de BASE3 seguem NEEDS_REVIEW. Decisao editorial separada e ainda em aberto (EDITORIAL-CONVERGENCE-11 a 13). Este vetor prova que a foundation NAO as toca por efeito colateral."
    }
  ]
}$vecjson$::JSONB);

DO $vguard$
DECLARE v_n INTEGER;
BEGIN
    SELECT jsonb_array_length(COALESCE(payload->'vectors', '[]'::JSONB))
      INTO v_n FROM _vec2826;

    IF COALESCE(v_n, 0) = 0 THEN
        RAISE EXCEPTION 'S4 ABORT: payload de vetores vazio. Substitua o literal do bloco PAYLOAD pelo conteudo de test-vectors/variant-type-mapping-scope-vectors.json antes de executar. NAO registrar P_VECTORS como PASS nem como FAIL — o harness nao roda sem os vetores.';
    END IF;

    IF (SELECT payload ? 'bindings' FROM _vec2826) IS NOT TRUE THEN
        RAISE EXCEPTION 'S4 ABORT: payload sem bloco `bindings`. O runner SQL e o runner Deno precisam do mesmo contrato de binding; sem ele a paridade nao e verificavel.';
    END IF;
END;
$vguard$;

DO $p$
DECLARE
    v_b JSONB;                        -- payload->'bindings'
    v_game UUID; v_src_a UUID; v_src_b UUID;
    v_cs_alpha UUID; v_cs_beta UUID; v_cs_noref UUID;
    v_code_a TEXT; v_code_b TEXT; v_code_def TEXT;
    v_set_alpha TEXT; v_set_beta TEXT; v_set_noref TEXT;
    v_synth_foil TEXT; v_synth_ids TEXT[];
    v_roster TEXT; v_ord INTEGER;
    v_out JSONB := '[]'::JSONB;
    v_rolled BOOLEAN := FALSE; v_erro TEXT := '';
    v_falhas TEXT := ''; v_ok INTEGER := 0; v_tot INTEGER := 0;
    e JSONB;
    v_src_def UUID;
BEGIN
    SELECT v::UUID INTO v_game FROM _ctx2826 WHERE k='game';

    SELECT payload->'bindings' INTO v_b FROM _vec2826;

    -- =====================================================================
    -- BINDINGS LIDOS DO PAYLOAD — GATE-A-REV-02 §4
    --
    -- A v1.0 hardcodava POKEMON_TCG_API, HARNESSFOIL2826, a lista P1..P7 e
    -- os Card Sets de fixture. O runner Deno lia esses mesmos valores de
    -- payload.bindings. Chamar isso de "binding compartilhado" quando só um
    -- dos runners consome o arquivo é afirmar uma paridade que não existe.
    -- Agora os DOIS leem do mesmo lugar; divergir passa a ser impossível
    -- sem editar o arquivo, que é o ponto.
    -- =====================================================================
    v_code_def  := v_b->'source'->>'default';
    v_code_a    := v_b->'source'->>'SRC_A';
    v_code_b    := v_b->'source'->>'SRC_B';
    v_synth_foil:= v_b->'combo'->'synthetic'->>'foil';
    v_set_alpha := v_b->'scope'->'set-alpha'->>'card_set';
    v_set_beta  := v_b->'scope'->'set-beta'->>'card_set';
    v_set_noref := v_b->'scope'->'null'->>'card_set';

    SELECT array_agg(x::TEXT) INTO v_synth_ids
      FROM jsonb_array_elements_text(v_b->'synthetic_vectors') x;

    IF v_code_a IS NULL OR v_code_b IS NULL OR v_synth_foil IS NULL
       OR v_set_alpha IS NULL OR v_set_beta IS NULL OR v_set_noref IS NULL
       OR v_synth_ids IS NULL THEN
        PERFORM pg_temp._chk('P_VECTORS', FALSE,
            'bloco bindings incompleto no arquivo de vetores: faltam source.SRC_A/SRC_B, '
            'combo.synthetic.foil, scope.set-alpha/set-beta/null.card_set ou synthetic_vectors. '
            'Sem eles os dois runners nao podem ligar os simbolos do MESMO jeito.');
        RETURN;
    END IF;

    -- ROSTER EXATO (§3): 10 vetores, ids exatos, nada a mais nem a menos.
    SELECT string_agg(vv->>'id', ',' ORDER BY ord) INTO v_roster
      FROM _vec2826, LATERAL jsonb_array_elements(payload->'vectors')
                             WITH ORDINALITY AS t(vv, ord);

    IF v_roster IS DISTINCT FROM 'P1,P2,P3,P4,P5,P6,P7,P8,P9,P10' THEN
        PERFORM pg_temp._chk('P_VECTORS', FALSE,
            format('roster de vetores divergente. Esperado P1..P10 nessa ordem; lido: %s',
                   COALESCE(v_roster,'<vazio>')));
        RETURN;
    END IF;

    -- >>> FONTES VÊM DO JSON — GATE-A-REV-03 §1 <<<
    -- A v2.0 lia bindings.source.SRC_A mas resolvia v_src_a de _ctx2826
    -- (portanto TCGDEX, sempre). O binding ficava decorativo: trocar SRC_A
    -- no arquivo não mudava nada no runner SQL, enquanto mudava no Deno —
    -- ou seja, a "fonte única" podia divergir em silêncio. Agora as DUAS
    -- Fontes e o default saem do arquivo, e Fonte inexistente é FAIL.
    --
    -- A Seção 0 segue usando TCGDEX para os casos PRÓPRIOS do harness; o
    -- contrato compartilhado é só este runner.
    SELECT id INTO v_src_a   FROM public.asset_source WHERE code = v_code_a;
    SELECT id INTO v_src_b   FROM public.asset_source WHERE code = v_code_b;
    SELECT id INTO v_src_def FROM public.asset_source WHERE code = v_code_def;

    SELECT id INTO v_cs_alpha FROM public.card_set WHERE code = v_set_alpha;
    SELECT id INTO v_cs_beta  FROM public.card_set WHERE code = v_set_beta;
    SELECT id INTO v_cs_noref FROM public.card_set WHERE code = v_set_noref;

    IF v_src_a IS NULL OR v_src_b IS NULL OR v_src_def IS NULL THEN
        PERFORM pg_temp._chk('P_VECTORS', FALSE,
            format('binding de Fonte invalido: SRC_A=%s -> %s, SRC_B=%s -> %s, default=%s -> %s. Fonte declarada no arquivo nao existe em asset_source.',
                   v_code_a,   COALESCE(v_src_a::TEXT,  '<INEXISTENTE>'),
                   v_code_b,   COALESCE(v_src_b::TEXT,  '<INEXISTENTE>'),
                   v_code_def, COALESCE(v_src_def::TEXT,'<INEXISTENTE>')));
        RETURN;
    END IF;

    IF v_cs_alpha IS NULL OR v_cs_beta IS NULL OR v_cs_noref IS NULL THEN
        PERFORM pg_temp._chk('P_VECTORS', FALSE,
            format('binding impossivel: Card Sets %s/%s/%s ausentes no catalogo. Rebasear o bloco bindings.',
                   v_set_alpha, v_set_beta, v_set_noref));
        RETURN;
    END IF;

    -- Pré-condição do binding: os Sets de fixture não podem ter referência
    -- da Fonte A, senão `external_set_id` seria imutável e o INSERT falharia.
    IF EXISTS (SELECT 1 FROM public.card_set_external_reference r
                WHERE r.asset_source_id = v_src_a
                  AND r.card_set_id IN (v_cs_alpha, v_cs_beta, v_cs_noref)) THEN
        PERFORM pg_temp._chk('P_VECTORS', FALSE,
            format('binding invalido: %s/%s/%s passaram a ter referencia %s. '
                   'trg_020_govern_card_set_external_reference torna external_set_id IMUTAVEL, '
                   'entao a fixture so pode nascer por INSERT em Set sem referencia. Rebasear bindings.',
                   v_set_alpha, v_set_beta, v_set_noref, v_code_a));
        RETURN;
    END IF;

    SELECT COALESCE(max(display_order), 0) INTO v_ord
      FROM public.card_variant_type WHERE game_id = v_game;

    BEGIN
        DECLARE
            v_vec JSONB; v_map JSONB; v_id TEXT; v_scope TEXT;
            v_cs UUID; v_src UUID; v_vt UUID; v_map_src UUID;
            v_type TEXT; v_foil TEXT; v_sub TEXT; v_stamp TEXT[];
            v_map_foil TEXT; v_map_sub TEXT; v_map_stamp TEXT[];
            v_exp_code TEXT; v_exp_scope TEXT; v_exp_vs TEXT;
            v_got UUID; v_got_code TEXT; v_matched TEXT; v_vs TEXT;
            v_sint BOOLEAN; v_ins INTEGER; v_realmap INTEGER;
            v_has_scoped BOOLEAN; v_ok_vec BOOLEAN; v_det TEXT;
            v_scopes TEXT[]; v_one TEXT;
        BEGIN
            -- Referências de escopo sintético (INSERT, nunca UPDATE).
            INSERT INTO public.card_set_external_reference
                (card_set_id, asset_source_id, external_set_id, metadata, is_active)
            VALUES (v_cs_alpha, v_src_a, 'set-alpha', '{}'::JSONB, TRUE),
                   (v_cs_beta,  v_src_a, 'set-beta',  '{}'::JSONB, TRUE),
                   (v_cs_alpha, v_src_b, 'set-alpha', '{}'::JSONB, TRUE);

            -- Variant Types de fixture: um por símbolo VT_* citado no arquivo.
            FOR v_id IN
                SELECT DISTINCT m->>'variant_type'
                  FROM _vec2826,
                       LATERAL jsonb_array_elements(payload->'vectors') vv,
                       LATERAL jsonb_array_elements(COALESCE(vv->'mappings','[]'::JSONB)) m
                 WHERE m->>'variant_type' LIKE 'VT\_%'
                 ORDER BY 1
            LOOP
                v_ord := v_ord + 1;
                INSERT INTO public.card_variant_type (game_id, code, name, display_order)
                VALUES (v_game, v_id, 'Harness 2826 ' || v_id, v_ord);
            END LOOP;

            FOR v_vec IN SELECT vv FROM _vec2826,
                                LATERAL jsonb_array_elements(payload->'vectors') vv
            LOOP
                v_id   := v_vec->>'id';
                v_sint := (v_id = ANY (v_synth_ids));
                v_tot  := v_tot + 1;

                -- Aceita símbolo (SRC_A/SRC_B) OU código concreto igual ao
                -- que o binding declara. Default vem do arquivo.
                v_src := CASE COALESCE(v_vec->>'job_source', v_code_def)
                             WHEN 'SRC_A'    THEN v_src_a
                             WHEN 'SRC_B'    THEN v_src_b
                             WHEN v_code_a   THEN v_src_a
                             WHEN v_code_b   THEN v_src_b
                             WHEN v_code_def THEN v_src_def
                             ELSE NULL END;

                IF v_src IS NULL THEN
                    RAISE EXCEPTION
                      'HARNESS_VECTOR_SOURCE_UNBOUND: vetor % declara job_source=% que nao casa com SRC_A/SRC_B/default do bloco bindings.',
                      v_id, COALESCE(v_vec->>'job_source','<null>');
                END IF;

                -- -----------------------------------------------------
                -- MAPPINGS — §5: sem ON CONFLICT DO NOTHING
                --
                -- Fixture que deveria nascer e colide é FALHA, não
                -- silêncio: o INSERT sobe a exceção e o vetor reprova.
                -- Para os vetores de corpus REAL, o mapping GLOBAL já
                -- existe em producao — nesses casos NAO se insere:
                -- prova-se que ele existe e aponta para o variant_type
                -- declarado. Depender de DO NOTHING ali seria aceitar
                -- falso-verde caso o mapping real tivesse sumido.
                -- -----------------------------------------------------
                FOR v_map IN SELECT m FROM jsonb_array_elements(
                                   COALESCE(v_vec->'mappings','[]'::JSONB)) m
                LOOP
                    SELECT t.id INTO v_vt FROM public.card_variant_type t
                     WHERE t.game_id = v_game AND t.code = v_map->>'variant_type';

                    -- combo do mapping, nas QUATRO dimensões (§3)
                    v_map_foil := CASE WHEN v_sint THEN v_synth_foil
                                       ELSE v_map->'combo'->>'foil' END;
                    v_map_sub  := v_map->'combo'->>'subtype';
                    v_map_stamp := CASE
                        WHEN jsonb_typeof(v_map->'combo'->'stamp') = 'array'
                        THEN ARRAY(SELECT jsonb_array_elements_text(v_map->'combo'->'stamp'))
                        ELSE NULL END;

                    v_map_src := CASE COALESCE(v_map->>'source', v_code_def)
                                     WHEN 'SRC_A'    THEN v_src_a
                                     WHEN 'SRC_B'    THEN v_src_b
                                     WHEN v_code_a   THEN v_src_a
                                     WHEN v_code_b   THEN v_src_b
                                     WHEN v_code_def THEN v_src_def
                                     ELSE NULL END;

                    IF v_map_src IS NULL THEN
                        RAISE EXCEPTION
                          'HARNESS_VECTOR_SOURCE_UNBOUND: vetor % declara mapping.source=% fora do bloco bindings.',
                          v_id, COALESCE(v_map->>'source','<null>');
                    END IF;

                    IF NOT v_sint AND v_map->>'scope' IS NULL THEN
                        -- corpus real + escopo GLOBAL -> tem de JA existir.
                        -- Identidade COMPLETA: type+foil+subtype+stamp.
                        v_realmap := pg_temp._map_count(
                            v_game, v_map_src, NULL, TRUE,
                            v_map->'combo'->>'type', v_map_foil, v_map_sub, v_map_stamp, v_vt);

                        IF v_realmap <> 1 THEN
                            RAISE EXCEPTION
                              'HARNESS_VECTOR_REALMAP_MISSING: vetor % espera EXATAMENTE 1 mapping GLOBAL real %|%|%|% -> %, encontrados %.',
                              v_id, v_map->'combo'->>'type', COALESCE(v_map_foil,'<null>'),
                              COALESCE(v_map_sub,'<null>'), COALESCE(v_map_stamp::TEXT,'<null>'),
                              v_map->>'variant_type', v_realmap;
                        END IF;
                    ELSE
                        -- >>> GATE-B-HARNESS-CORRECTION-01 §1 <<<
                        -- external_type e NOT NULL sem default (Query 2140).
                        -- A fixture omitia external_type/external_foil e abortava
                        -- com 23502 antes de qualquer lookup. Informados agora de
                        -- forma COERENTE com o contrato da tabela, nao apenas para
                        -- satisfazer o NOT NULL: external_* recebe o valor BRUTO do
                        -- vetor e normalized_* segue identico ao que ja estava.
                        -- external_foil recebe o foil EFETIVO da fixture (ou seja,
                        -- ja com a substituicao sintetica HARNESSFOIL2826 aplicada),
                        -- porque e esse o foil que o mapping realmente carrega.
                        INSERT INTO public.card_variant_type_external_mapping
                            (game_id, asset_source_id, external_set_id, variant_type_id,
                             external_type, external_foil,
                             normalized_type, normalized_foil, normalized_subtype, normalized_stamp)
                        VALUES (
                            v_game, v_map_src, v_map->>'scope', v_vt,
                            v_map->'combo'->>'type', v_map_foil,
                            v_map->'combo'->>'type', v_map_foil, v_map_sub, v_map_stamp);

                        GET DIAGNOSTICS v_ins = ROW_COUNT;
                        IF v_ins <> 1 THEN
                            RAISE EXCEPTION
                              'HARNESS_VECTOR_FIXTURE_NOT_INSERTED: vetor % nao criou o mapping declarado.', v_id;
                        END IF;
                    END IF;
                END LOOP;

                v_type := v_vec->'combo'->>'type';
                v_foil := CASE WHEN v_sint THEN v_synth_foil ELSE v_vec->'combo'->>'foil' END;
                v_sub  := v_vec->'combo'->>'subtype';
                -- stamp do vetor carregado de verdade (§3): hoje NULL em
                -- P1..P10, mas a dimensão existe e passa a ser transportada.
                v_stamp := CASE
                    WHEN jsonb_typeof(v_vec->'combo'->'stamp') = 'array'
                    THEN ARRAY(SELECT jsonb_array_elements_text(v_vec->'combo'->'stamp'))
                    ELSE NULL END;

                v_exp_code  := v_vec->'expected'->>'variant_type';
                v_exp_scope := v_vec->'expected'->>'matched_scope';
                v_exp_vs    := v_vec->'expected'->>'validation_status';

                -- -----------------------------------------------------
                -- §3: job_scope ARRAY testa TODOS os elementos.
                -- P9 cita sv03.5, sv05 e sv06 — um acerto em sv03.5 não
                -- prova P9; os três precisam resolver GLOBAL/GALAXY_HOLO.
                -- -----------------------------------------------------
                IF jsonb_typeof(v_vec->'job_scope') = 'array' THEN
                    SELECT array_agg(x::TEXT) INTO v_scopes
                      FROM jsonb_array_elements_text(v_vec->'job_scope') x;
                ELSE
                    v_scopes := ARRAY[ v_vec->>'job_scope' ];
                END IF;

                v_ok_vec := TRUE;
                v_det    := '';

                FOREACH v_one IN ARRAY v_scopes
                LOOP
                    v_scope := v_one;
                    v_cs := CASE
                              WHEN v_scope IS NULL       THEN v_cs_noref
                              WHEN v_scope = 'set-alpha' THEN v_cs_alpha
                              WHEN v_scope = 'set-beta'  THEN v_cs_beta
                              ELSE (SELECT r.card_set_id
                                      FROM public.card_set_external_reference r
                                     WHERE r.asset_source_id = v_src
                                       AND r.external_set_id = v_scope
                                       AND r.is_active)
                            END;
                    IF v_cs IS NULL THEN v_cs := v_cs_noref; END IF;

                    v_got := internal.lookup_variant_type_for_row(
                                 v_game, v_src, v_cs, v_type, v_foil, v_sub, v_stamp);

                    SELECT t.code INTO v_got_code
                      FROM public.card_variant_type t WHERE t.id = v_got;

                    -- matched_scope derivado pela MESMA precedência do lookup,
                    -- com a identidade COMPLETA de 4 dimensões (§3) e pela
                    -- mesma expressão centralizada.
                    v_has_scoped := (v_scope IS NOT NULL)
                        AND pg_temp._map_count(v_game, v_src, v_scope, FALSE,
                                               v_type, v_foil, v_sub, v_stamp) > 0;

                    v_matched := CASE WHEN v_got IS NULL THEN NULL
                                      WHEN v_has_scoped  THEN 'SOURCE_SET'
                                      ELSE 'GLOBAL' END;

                    v_vs := CASE WHEN v_got IS NULL THEN 'NEEDS_REVIEW' ELSE 'VALID' END;

                    IF v_got_code IS DISTINCT FROM v_exp_code
                       OR v_matched IS DISTINCT FROM v_exp_scope
                       OR (v_exp_vs IS NOT NULL AND v_vs IS DISTINCT FROM v_exp_vs) THEN
                        v_ok_vec := FALSE;
                        v_det := v_det || format('[escopo=%s vt esperado=%s obtido=%s; matched esperado=%s obtido=%s; status esperado=%s obtido=%s] ',
                                    COALESCE(v_scope,'<sem escopo>'),
                                    COALESCE(v_exp_code,'<nenhum>'), COALESCE(v_got_code,'<nenhum>'),
                                    COALESCE(v_exp_scope,'<nenhum>'), COALESCE(v_matched,'<nenhum>'),
                                    COALESCE(v_exp_vs,'<nao declarado>'), v_vs);
                    END IF;
                END LOOP;

                v_out := v_out || jsonb_build_object(
                    'id', v_id,
                    'ok', v_ok_vec,
                    'det', format('%s (%s escopo(s) testado(s)): %s',
                                  v_id, cardinality(v_scopes),
                                  CASE WHEN v_ok_vec THEN 'todos conferem' ELSE v_det END));

                -- Isolamento entre vetores: o próximo não herda fixture.
                DELETE FROM public.card_variant_type_external_mapping
                 WHERE normalized_foil = v_synth_foil
                    OR variant_type_id IN (SELECT id FROM public.card_variant_type
                                            WHERE game_id=v_game AND code LIKE 'VT\_%')
                    OR external_set_id IN ('set-alpha','set-beta')
                    OR (external_set_id IS NOT NULL AND normalized_foil = 'GALAXY');
            END LOOP;

            RAISE EXCEPTION 'HARNESS_VECTORS_ROLLBACK';
        END;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_VECTORS_ROLLBACK' THEN v_rolled := TRUE;
        ELSE v_erro := SQLERRM; END IF;
    END;

    IF NOT v_rolled THEN
        PERFORM pg_temp._chk('P_VECTORS', FALSE,
            'runner de vetores abortou fora da sentinela: ' ||
            COALESCE(NULLIF(v_erro,''), 'sentinela nao disparou'));
        RETURN;
    END IF;

    FOR e IN SELECT value FROM jsonb_array_elements(v_out) LOOP
        IF (e->>'ok')::BOOLEAN THEN v_ok := v_ok + 1;
        ELSE v_falhas := v_falhas || (e->>'det') || ' ;; ';
        END IF;
    END LOOP;

    PERFORM pg_temp._chk('P_VECTORS',
        (v_tot = 10 AND v_ok = 10),
        format('%s/%s vetores conferem com o arquivo unico (variant_type + matched_scope + validation_status, todos os escopos de cada vetor).%s',
               v_ok, v_tot,
               CASE WHEN v_falhas = '' THEN '' ELSE ' DIVERGENCIAS: ' || v_falhas END));
END;
$p$;

-- =============================================================================
-- SEÇÃO 5 — CORPUS REAL: PREVIEW, GUARDS E PROPAGATION
--        (casos N, N0, O, P, Q, Q2, R, S, T, U, V, W, X)
--
-- Usa o alvo real TCGDEX/base3 · HOLO|GALAXY|NULL|{} — 30 rows, todas classe A.
-- TODA escrita vive em sentinela.
--
-- >>> REESCRITA EM GATE-A-REV-01 <<<
-- A v1.0 provava os guards só pelo lado POSITIVO (B=0, C=0 no corpus feliz),
-- o que não prova bloqueio nenhum: um guard que nunca viu uma condição de
-- bloqueio não está provado, está apenas não-contrariado. Agora cada guard tem
-- fixture que o faz DISPARAR de verdade:
--
--   N   job.external_set_id divergente     -> SCOPE_MISMATCH
--   P   row com persistence UNCHANGED      -> ROWS_NOT_ELIGIBLE
--   Q   card_variant + resulting_variant_id-> CANONICAL_VARIANT_MATERIALIZED
--   Q2  card_variant SEM provenance        -> PROVENANCE_INSUFFICIENT
--
-- E T/U deixaram de usar `updated_at > now() - interval '1 minute'`, que não é
-- prova de preservação: mede relógio, não conteúdo, e passaria em qualquer
-- base cuja escrita não mexesse em updated_at. Agora são snapshots de ROW
-- INTEIRA (to_jsonb) tirados ANTES, em TEMP tables criadas FORA da sentinela.
-- =============================================================================

-- Snapshots de row inteira — criados no topo, fora de qualquer sentinela, para
-- que sobrevivam ao rollback das subtransações e possam ser confrontados depois.
CREATE TEMP TABLE _snap_rows2826 AS
SELECT r.id, to_jsonb(r) AS row_json
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
 WHERE j.card_set_id = (SELECT v::UUID FROM _ctx2826 WHERE k='cs_base3');

-- card_set_id capturado EXPLICITAMENTE no snapshot (GATE-A-REV-03 §4):
-- a classificação "pertencia ao universo baseline" tem de sair do SNAPSHOT,
-- nunca de um JOIN com o estado atual.
CREATE TEMP TABLE _snap_jobs2826 AS
SELECT j.id, j.card_set_id AS card_set_id_orig, to_jsonb(j) AS row_json
  FROM public.catalog_variant_import_job j;

CREATE TEMP TABLE _alvo2826 AS
SELECT r.id, r.card_id
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
  CROSS JOIN LATERAL internal.compute_variant_residual_signature(
      r.raw_data,
      (SELECT v::UUID FROM _ctx2826 WHERE k='game'),
      (SELECT v::UUID FROM _ctx2826 WHERE k='src')) sg
 WHERE j.card_set_id = (SELECT v::UUID FROM _ctx2826 WHERE k='cs_base3')
   AND j.status = 'STAGED'
   AND sg.residual_type = 'HOLO' AND sg.residual_foil = 'GALAXY'
   AND sg.residual_subtype IS NULL
   AND COALESCE(sg.residual_stamp,'{}'::TEXT[]) = '{}'::TEXT[];

DO $corpus$
DECLARE
    v_game UUID; v_src UUID; v_cs3 UUID; v_vt_holo UUID; v_vt_galaxy UUID;
    v_origin UUID; v_prev RECORD; v_dec RECORD;
    v_snap_before TEXT; v_snap_after TEXT;
    v_out JSONB := '[]'::JSONB;
    v_rolled BOOLEAN := FALSE; v_erro TEXT := '';
    v_casos TEXT[] := ARRAY['N','N0','O','P','Q','Q2','R','S','T','U','V','W','X'];
    e JSONB;
BEGIN
    SELECT v::UUID INTO v_game      FROM _ctx2826 WHERE k='game';
    SELECT v::UUID INTO v_src       FROM _ctx2826 WHERE k='src';
    SELECT v::UUID INTO v_cs3       FROM _ctx2826 WHERE k='cs_base3';
    SELECT v::UUID INTO v_vt_holo   FROM _ctx2826 WHERE k='vt_holo';
    SELECT v::UUID INTO v_vt_galaxy FROM _ctx2826 WHERE k='vt_galaxy';

    -- Placeholders: qualquer caso não sobrescrito reprova.
    PERFORM pg_temp._chk(t.c, FALSE, 'caso nao registrado pela Secao 5 — cobertura incompleta')
      FROM unnest(v_casos) AS t(c);

    -- Linha de origem: uma das 30 VALID de BASE3 com HOLO|GALAXY.
    SELECT r.id INTO v_origin
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
      JOIN public.card_set cs ON cs.id = j.card_set_id
      CROSS JOIN LATERAL internal.compute_variant_residual_signature(r.raw_data, v_game, v_src) sg
     WHERE cs.id = v_cs3 AND j.status='STAGED'
       AND sg.residual_type='HOLO' AND sg.residual_foil='GALAXY'
       AND sg.residual_subtype IS NULL
       AND COALESCE(sg.residual_stamp,'{}'::TEXT[]) = '{}'::TEXT[]
     ORDER BY r.id LIMIT 1;

    IF v_origin IS NULL THEN
        PERFORM pg_temp._chk(t.c, FALSE,
            'nenhuma linha BASE3 HOLO|GALAXY encontrada — o corpus real mudou e a Secao 5 nao pode ser provada nesta base')
          FROM unnest(v_casos) AS t(c);
        RETURN;
    END IF;

    -- ---------------------------------------------------------
    -- O — O CONTRATO QUE ALIMENTA O PREVIEW NÃO ESCREVE NADA
    --
    -- >>> REESTRUTURADO EM GATE-A-REV-01-CONTINUATION §2 <<<
    --
    -- A v1.0 chamava public.admin_preview_catalog_variant_import_mapping()
    -- diretamente. Medido em 2026-09-14: no canal execute_sql do
    -- Management API, current_user=postgres (NÃO superuser),
    -- auth.uid()=NULL, request.jwt.claims=NULL e portanto
    -- public.is_admin()=FALSE. A RPC levantaria
    -- ..._FORBIDDEN e abortaria a Seção 5 inteira.
    --
    -- Este harness NÃO afirma executar positivamente RPC pública
    -- protegida por is_admin(). O canal não tem sessão de aplicação
    -- autenticada — limitação do CANAL, não do desenho.
    --
    -- O que se prova aqui é o COMPORTAMENTO: exercita-se
    -- internal.variant_type_mapping_decision(), que é EXATAMENTE o
    -- contrato do qual o preview extrai todos os seus campos (2194
    -- linhas 97-116: uma única chamada + projeção). Os campos
    -- conferidos abaixo são os mesmos que o preview devolveria.
    --
    -- A FRONTEIRA (guard is_admin, ACL, SECURITY DEFINER, delegação)
    -- é provada estaticamente na Seção 7, caso AB.
    -- A prova E2E positiva com sessão admin real é gate futuro,
    -- registrado no README — não pertence ao execute_sql.
    -- ---------------------------------------------------------
    SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k)) INTO v_snap_before
      FROM pg_temp._snap2826();

    SELECT * INTO v_prev
      FROM internal.variant_type_mapping_decision(v_origin, v_vt_holo, 'SOURCE_SET');

    SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k)) INTO v_snap_after
      FROM pg_temp._snap2826();

    PERFORM pg_temp._chk('O',
        v_snap_before = v_snap_after
        -- o contrato precisa ter devolvido o quadro COMPLETO que o
        -- preview projeta; campo ausente = preview quebrado
        AND v_prev.external_set_id IS NOT NULL
        AND v_prev.rows_total IS NOT NULL
        AND v_prev.rows_class_a IS NOT NULL
        AND v_prev.rows_class_b IS NOT NULL
        AND v_prev.canonical_class_c IS NOT NULL
        AND v_prev.rows_valid_reclassified IS NOT NULL
        AND v_prev.jobs_affected IS NOT NULL
        AND v_prev.current_effective_scope IS NOT NULL
        AND v_prev.supersedes_interpretation IS NOT NULL,
        CASE WHEN v_snap_before = v_snap_after
             THEN format('contrato de preview executado (ok=%s, escopo=%s, universo=%s, A=%s, B=%s, C=%s, reclass=%s, jobs=%s, vigente=%s, supersede=%s) e o snapshot completo NAO mudou — leitura pura confirmada',
                         v_prev.ok, v_prev.external_set_id, v_prev.rows_total,
                         v_prev.rows_class_a, v_prev.rows_class_b, v_prev.canonical_class_c,
                         v_prev.rows_valid_reclassified, v_prev.jobs_affected,
                         v_prev.current_effective_scope, v_prev.supersedes_interpretation)
             ELSE 'FALHA: o contrato de leitura alterou estado' END);

    -- ---------------------------------------------------------
    -- N0 — o escopo do preview vem da referência canônica
    --      (condição NECESSÁRIA, não suficiente — ver caso N)
    -- ---------------------------------------------------------
    PERFORM pg_temp._chk('N0',
        v_prev.external_set_id = (SELECT r.external_set_id
                                    FROM public.card_set_external_reference r
                                   WHERE r.card_set_id = v_cs3
                                     AND r.asset_source_id = v_src AND r.is_active),
        format('escopo derivado=%s; referencia canonica ativa=%s (o campo do job NAO e autoridade)',
               COALESCE(v_prev.external_set_id,'<null>'),
               (SELECT r.external_set_id FROM public.card_set_external_reference r
                 WHERE r.card_set_id = v_cs3 AND r.asset_source_id = v_src AND r.is_active)));

    -- ---------------------------------------------------------
    -- N — MISMATCH REAL (GATE-A-REV-01 §2)
    --
    -- N0 sozinho só prova que o preview LÊ a referência canônica.
    -- Não prova o que acontece quando o job CONTRADIZ essa
    -- referência — que é o caso perigoso, e o único em que a
    -- palavra "mismatch" significa alguma coisa.
    --
    -- Fixture: dentro da sentinela, job.external_set_id passa de
    -- 'base3' para 'base1'. 'base1' é um valor VÁLIDO (referência
    -- TCGDEX ativa, medida em 2026-09-14) porém DIVERGENTE deste
    -- Card Set — exatamente o formato de corrupção que o guard
    -- existe para pegar. Não há FK nem CHECK em
    -- catalog_variant_import_job.external_set_id (medido), então o
    -- UPDATE é legítimo e o cenário é alcançável.
    --
    -- Espera-se: block_reason = SCOPE_MISMATCH, would_apply = FALSE,
    -- o worker recusa ANTES de escrever, e o job volta ao valor
    -- original quando a sentinela reverte.
    -- ---------------------------------------------------------
    -- >>> ORDEM DE SNAPSHOT — CORRIGIDA EM GATE-A-REV-02 §1 <<<
    --
    -- A v1.0 do caso tirava o snapshot ANTES da fixture e o comparava
    -- DEPOIS. Como a fixture altera o próprio job, `jobs_rows_digest`
    -- mudava pela FIXTURE — e o caso reprovaria SEMPRE, acusando o
    -- worker de uma escrita que foi minha. Falso-vermelho garantido.
    --
    -- A ordem correta separa duas perguntas diferentes:
    --   * o WORKER escreveu alguma coisa?  -> snapshot PÓS-FIXTURE
    --     comparado ao snapshot PÓS-WORKER;
    --   * a FIXTURE foi revertida?         -> to_jsonb do job inteiro,
    --     capturado antes da sentinela, comparado depois do rollback.
    --
    -- O job NÃO é excluído do snapshot global. O que muda é o PONTO de
    -- referência: excluir o job mascararia uma escrita real do worker
    -- naquele mesmo job.
    DECLARE
        v_n_out   JSONB := '[]'::JSONB;
        v_n_roll  BOOLEAN := FALSE;
        v_n_err   TEXT := '';
        v_job_id  UUID;
        v_job_json_antes JSONB;
    BEGIN
        SELECT r.job_id INTO v_job_id
          FROM public.catalog_variant_import_row r WHERE r.id = v_origin;

        -- Estado ORIGINAL do job, row inteira, fora da sentinela.
        SELECT to_jsonb(j) INTO v_job_json_antes
          FROM public.catalog_variant_import_job j WHERE j.id = v_job_id;

        BEGIN
            DECLARE
                v_d RECORD; v_worker_err TEXT := '';
                v_canon TEXT;
                v_snap_pos_fixture TEXT; v_snap_pos_worker TEXT;
                v_job_ext_fixture  TEXT;
            BEGIN
                -- A. FIXTURE — mismatch declarado
                UPDATE public.catalog_variant_import_job
                   SET external_set_id = 'base1'
                 WHERE id = v_job_id;

                -- a fixture precisa ter MESMO acontecido (anti falso-verde)
                SELECT j.external_set_id INTO v_job_ext_fixture
                  FROM public.catalog_variant_import_job j WHERE j.id = v_job_id;

                -- B. a referência canônica NÃO se moveu: ela é a autoridade,
                --    e o UPDATE tocou só o dado de operação.
                SELECT s.external_set_id INTO v_canon
                  FROM internal.resolve_variant_mapping_scope(v_cs3, v_src) s;

                -- C. SNAPSHOT PÓS-FIXTURE / PRÉ-WORKER
                SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k)) INTO v_snap_pos_fixture
                  FROM pg_temp._snap2826();

                -- D. decision
                SELECT * INTO v_d
                  FROM internal.variant_type_mapping_decision(v_origin, v_vt_holo, 'SOURCE_SET');

                -- E. worker
                BEGIN
                    PERFORM internal.apply_variant_type_mapping(
                                (SELECT v::UUID FROM _ctx2826 WHERE k='admin'),
                                v_origin, v_vt_holo, 'SOURCE_SET');
                EXCEPTION WHEN OTHERS THEN
                    v_worker_err := SQLERRM;
                END;

                -- G. SNAPSHOT PÓS-WORKER
                SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k)) INTO v_snap_pos_worker
                  FROM pg_temp._snap2826();

                v_n_out := v_n_out || jsonb_build_object('caso','N',
                    'ok', (v_job_ext_fixture = 'base1'            -- fixture efetiva
                           AND v_canon = 'base3'                  -- B
                           AND v_d.block_reason = 'SCOPE_MISMATCH'-- F
                           AND v_d.ok IS FALSE
                           AND v_worker_err LIKE 'VARIANT_IMPORT_SCOPE_MISMATCH%'
                           AND v_snap_pos_worker = v_snap_pos_fixture), -- G
                    'det', format('fixture job.external_set_id=%s vs referencia canonica ATIVA=%s | decision=%s ok=%s | worker=%s | efeito do WORKER sobre o estado: %s',
                                  COALESCE(v_job_ext_fixture,'<null>'),
                                  COALESCE(v_canon,'<null>'),
                                  COALESCE(v_d.block_reason,'<null>'), v_d.ok,
                                  COALESCE(NULLIF(left(v_worker_err,60),''),'<NAO LEVANTOU — FALHA>'),
                                  CASE WHEN v_snap_pos_worker = v_snap_pos_fixture
                                       THEN 'NENHUM (snapshot pos-worker = pos-fixture)'
                                       ELSE 'HOUVE ESCRITA — FALHA' END));

                RAISE EXCEPTION 'HARNESS_N_ROLLBACK';   -- H
            END;
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM = 'HARNESS_N_ROLLBACK' THEN v_n_roll := TRUE;
            ELSE v_n_err := SQLERRM; END IF;
        END;

        -- I. ROLLBACK INTEGRAL DA FIXTURE — row inteira, não só a coluna
        IF v_n_roll AND jsonb_array_length(v_n_out) = 1 THEN
            PERFORM pg_temp._chk('N',
                ((v_n_out->0->>'ok')::BOOLEAN
                 AND (SELECT to_jsonb(j) FROM public.catalog_variant_import_job j
                       WHERE j.id = v_job_id) = v_job_json_antes),
                (v_n_out->0->>'det') || format(' | rollback da fixture: job %s',
                    CASE WHEN (SELECT to_jsonb(j) FROM public.catalog_variant_import_job j
                                WHERE j.id = v_job_id) = v_job_json_antes
                         THEN 'IDENTICO a to_jsonb original (row inteira)'
                         ELSE 'DIVERGE do original — FALHA' END));
        ELSE
            PERFORM pg_temp._chk('N', FALSE,
                'fixture de mismatch nao completou: ' ||
                COALESCE(NULLIF(v_n_err,''), 'sentinela nao disparou'));
        END IF;
    END;

    -- ---------------------------------------------------------
    -- P / Q / Q2 — GUARDS FAIL-CLOSED, PROVA NEGATIVA REAL
    --              (GATE-A-REV-01 §3 e §4)
    --
    -- A v1.0 só media B=0 e C=0 no corpus feliz. Isso prova que o
    -- corpus está limpo, não que o guard bloqueia. Aqui cada guard
    -- ganha uma fixture que o faz disparar:
    --
    --   P   uma row alvo vira persistence_status='UNCHANGED'
    --       -> sai da classe A -> ROWS_NOT_ELIGIBLE
    --
    --   Q   cria card_variant + amarra resulting_variant_id numa
    --       row alvo -> identidade canônica materializada
    --       -> CANONICAL_VARIANT_MATERIALIZED
    --       (só nomeável porque REV-01 inverteu a precedência
    --        C-antes-de-B; com a ordem antiga sairia
    --        ROWS_NOT_ELIGIBLE e a classe C seria indemonstrável)
    --
    --   Q2  cria card_variant do variant_type VIGENTE em card de
    --       BASE3 SEM amarrar provenance -> detecção exata dá zero
    --       e o guard conservador assume -> PROVENANCE_INSUFFICIENT
    --
    -- Pré-condição medida em 2026-09-14: BASE3 tem 0 card_variant,
    -- logo nenhuma fixture colide com uq_card_variant_card_type_no_printing.
    -- E o mapping vigente de HOLO|GALAXY é GALAXY_HOLO, distinto do
    -- alvo HOLO — por isso supersedes_interpretation é TRUE e os
    -- guards ficam ARMADOS. O harness ASSERTA isso em vez de supor.
    -- ---------------------------------------------------------
    -- >>> DECISION **E** EXECUTE — CORRIGIDO EM GATE-A-REV-02 §2 <<<
    --
    -- A v1.0 dos três casos só chamava
    -- internal.variant_type_mapping_decision(). Isso prova o DECISION,
    -- não o WORKER — e o worker é quem escreve. Um worker que ignorasse
    -- o block_reason passaria os três casos intocado.
    --
    -- Cada fixture agora vive na SUA PRÓPRIA sentinela e roda o ciclo
    -- completo: fixture -> decision -> snapshot pós-fixture -> worker ->
    -- SQLERRM esperado -> zero escrita -> rollback integral.
    --
    -- Mensagens do worker (Query 2193, medidas no arquivo):
    --   ROWS_NOT_ELIGIBLE / CANONICAL_VARIANT_MATERIALIZED /
    --   PROVENANCE_INSUFFICIENT  ->
    --   'VARIANT_TYPE_MAPPING_RECONCILIATION_REQUIRED: <reason> — ...'
    -- O reason entra no texto, então o LIKE distingue os três.
    -- ---------------------------------------------------------
    DECLARE
        v_pq_out  JSONB := '[]'::JSONB;
        v_caso    TEXT;
        v_snap_base2 TEXT;
    BEGIN
        SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k)) INTO v_snap_base2
          FROM pg_temp._snap2826();

        FOREACH v_caso IN ARRAY ARRAY['P','Q','Q2']
        LOOP
            DECLARE
                v_roll BOOLEAN := FALSE; v_err TEXT := '';
                v_res  JSONB := NULL;
            BEGIN
                BEGIN
                    DECLARE
                        v_d0 RECORD; v_d RECORD;
                        v_row UUID; v_card UUID; v_cv UUID; v_ord INTEGER;
                        v_snap_fix TEXT; v_snap_pos TEXT;
                        v_werr TEXT := '';
                        v_reason_esp TEXT;
                        v_maps_antes INTEGER; v_maps_depois INTEGER;
                        v_log_antes  INTEGER; v_log_depois  INTEGER;
                        v_fixture_ok BOOLEAN := FALSE;
                    BEGIN
                        -- premissa comum: o guard precisa estar ARMADO
                        SELECT * INTO v_d0
                          FROM internal.variant_type_mapping_decision(v_origin, v_vt_holo, 'SOURCE_SET');

                        SELECT count(*) INTO v_maps_antes
                          FROM public.card_variant_type_external_mapping;
                        SELECT count(*) INTO v_log_antes
                          FROM public.catalog_admin_action_log;

                        -- 1. FIXTURE
                        IF v_caso = 'P' THEN
                            v_reason_esp := 'ROWS_NOT_ELIGIBLE';
                            SELECT id INTO v_row FROM _alvo2826 ORDER BY id LIMIT 1;
                            UPDATE public.catalog_variant_import_row
                               SET persistence_status = 'UNCHANGED'
                             WHERE id = v_row;
                            SELECT (persistence_status = 'UNCHANGED') INTO v_fixture_ok
                              FROM public.catalog_variant_import_row WHERE id = v_row;

                        ELSE
                            v_reason_esp := CASE v_caso
                                              WHEN 'Q'  THEN 'CANONICAL_VARIANT_MATERIALIZED'
                                              ELSE 'PROVENANCE_INSUFFICIENT' END;

                            SELECT id, card_id INTO v_row, v_card
                              FROM _alvo2826 ORDER BY id LIMIT 1;

                            SELECT COALESCE(max(variant_order), 0) + 1 INTO v_ord
                              FROM public.card_variant WHERE card_id = v_card;

                            INSERT INTO public.card_variant
                                (card_id, variant_type_id, variant_order, is_default, printing_profile_id)
                            VALUES (v_card, v_vt_galaxy, v_ord, FALSE, NULL)
                            RETURNING id INTO v_cv;

                            IF v_caso = 'Q' THEN
                                -- provenance EXATA: row alvo aponta para o card_variant
                                UPDATE public.catalog_variant_import_row
                                   SET resulting_variant_id = v_cv
                                 WHERE id = v_row;
                                SELECT (resulting_variant_id = v_cv) INTO v_fixture_ok
                                  FROM public.catalog_variant_import_row WHERE id = v_row;
                            ELSE
                                -- Q2: card_variant SEM vínculo — ponto cego
                                v_fixture_ok := (v_cv IS NOT NULL);
                            END IF;
                        END IF;

                        -- 2. DECISION
                        SELECT * INTO v_d
                          FROM internal.variant_type_mapping_decision(v_origin, v_vt_holo, 'SOURCE_SET');

                        -- 3. SNAPSHOT PÓS-FIXTURE
                        SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k)) INTO v_snap_fix
                          FROM pg_temp._snap2826();

                        -- 4/5. WORKER + SQLERRM
                        BEGIN
                            PERFORM internal.apply_variant_type_mapping(
                                        (SELECT v::UUID FROM _ctx2826 WHERE k='admin'),
                                        v_origin, v_vt_holo, 'SOURCE_SET');
                        EXCEPTION WHEN OTHERS THEN
                            v_werr := SQLERRM;
                        END;

                        SELECT count(*) INTO v_maps_depois
                          FROM public.card_variant_type_external_mapping;
                        SELECT count(*) INTO v_log_depois
                          FROM public.catalog_admin_action_log;

                        -- 11. SNAPSHOT PÓS-TENTATIVA
                        SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k)) INTO v_snap_pos
                          FROM pg_temp._snap2826();

                        v_res := jsonb_build_object(
                            'ok', (v_fixture_ok                                  -- fixture efetiva
                                   AND v_d0.supersedes_interpretation IS TRUE    -- guard armado
                                   AND v_d.ok IS FALSE                           -- 2
                                   AND v_d.block_reason = v_reason_esp
                                   AND v_werr LIKE 'VARIANT_TYPE_MAPPING_RECONCILIATION_REQUIRED: '
                                                   || v_reason_esp || '%'        -- 6
                                   AND v_maps_depois = v_maps_antes              -- 7
                                   AND v_log_depois  = v_log_antes               -- 10
                                   AND v_snap_pos = v_snap_fix),                 -- 8/9/11
                            'det', format('fixture=%s | supersedes=%s | decision.ok=%s block=%s (esperado %s) | worker=%s | mappings %s->%s | action log %s->%s | snapshot pos-tentativa %s',
                                   CASE WHEN v_fixture_ok THEN 'efetiva' ELSE 'NAO APLICADA — FALHA' END,
                                   v_d0.supersedes_interpretation,
                                   v_d.ok, COALESCE(v_d.block_reason,'<null>'), v_reason_esp,
                                   COALESCE(NULLIF(left(v_werr,70),''),'<NAO LEVANTOU — FALHA>'),
                                   v_maps_antes, v_maps_depois,
                                   v_log_antes, v_log_depois,
                                   CASE WHEN v_snap_pos = v_snap_fix
                                        THEN 'IDENTICO ao pos-fixture (zero propagation, zero counter)'
                                        ELSE 'ALTERADO — FALHA' END));

                        RAISE EXCEPTION 'HARNESS_PQ_ROLLBACK';   -- 12
                    END;
                EXCEPTION WHEN OTHERS THEN
                    IF SQLERRM = 'HARNESS_PQ_ROLLBACK' THEN v_roll := TRUE;
                    ELSE v_err := SQLERRM; END IF;
                END;

                -- 13. ROLLBACK INTEGRAL — snapshot volta à baseline do bloco
                IF v_roll AND v_res IS NOT NULL THEN
                    v_pq_out := v_pq_out || jsonb_build_object(
                        'caso', v_caso,
                        'ok', ((v_res->>'ok')::BOOLEAN
                               AND v_snap_base2 = (SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k))
                                                     FROM pg_temp._snap2826())),
                        'det', (v_res->>'det') || format(' | rollback integral: %s',
                                CASE WHEN v_snap_base2 = (SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k))
                                                            FROM pg_temp._snap2826())
                                     THEN 'snapshot de volta a baseline do bloco'
                                     ELSE 'SOBROU ESTADO — FALHA' END));
                ELSE
                    v_pq_out := v_pq_out || jsonb_build_object('caso', v_caso, 'ok', FALSE,
                        'det', 'fixture negativa nao completou: ' ||
                               COALESCE(NULLIF(v_err,''), 'sentinela nao disparou'));
                END IF;
            END;
        END LOOP;

        FOR e IN SELECT value FROM jsonb_array_elements(v_pq_out) LOOP
            PERFORM pg_temp._chk(e->>'caso', (e->>'ok')::BOOLEAN, e->>'det');
        END LOOP;
    END;

    -- ---------------------------------------------------------
    -- BLOCO MUTÁVEL — execute scoped real, revertido por sentinela
    -- ---------------------------------------------------------
    BEGIN
        DECLARE
            v_res RECORD; v_n INTEGER; v_log INTEGER; v_meta JSONB;
            v_alvo UUID[]; v_fora INTEGER; v_jobs_tocados INTEGER;
        BEGIN
            SELECT ARRAY(
                SELECT r.id FROM public.catalog_variant_import_row r
                  JOIN public.catalog_variant_import_job j ON j.id=r.job_id
                  CROSS JOIN LATERAL internal.compute_variant_residual_signature(r.raw_data, v_game, v_src) sg
                 WHERE j.card_set_id = v_cs3 AND j.status='STAGED'
                   AND sg.residual_type='HOLO' AND sg.residual_foil='GALAXY'
                   AND sg.residual_subtype IS NULL
                   AND COALESCE(sg.residual_stamp,'{}'::TEXT[]) = '{}'::TEXT[]
                 ORDER BY r.id) INTO v_alvo;

            SELECT * INTO v_res
              FROM internal.apply_variant_type_mapping(
                       (SELECT v::UUID FROM _ctx2826 WHERE k='admin'),
                       v_origin, v_vt_holo, 'SOURCE_SET');

            -- R — VALID -> VALID com variant_type diferente
            SELECT count(*) INTO v_n FROM public.catalog_variant_import_row r
             WHERE r.id = ANY(v_alvo) AND r.validation_status='VALID'
               AND (r.normalized_data->>'variant_type_id')::UUID = v_vt_holo;
            v_out := v_out || jsonb_build_object('caso','R',
                'ok', (v_n = cardinality(v_alvo) AND v_n > 0),
                'det', format('%s de %s linhas alvo reclassificadas VALID->VALID para HOLO', v_n, cardinality(v_alvo)));

            -- S — nenhuma das alvo ficou NEEDS_REVIEW
            SELECT count(*) INTO v_n FROM public.catalog_variant_import_row r
             WHERE r.id = ANY(v_alvo) AND r.validation_status <> 'VALID';
            v_out := v_out || jsonb_build_object('caso','S','ok',(v_n = 0),
                'det', format('%s linha(s) alvo fora de VALID apos propagation (esperado 0)', v_n));

            -- T — linha FORA do alvo preservada por ROW INTEIRA
            --
            -- >>> REESCRITO EM GATE-A-REV-01 §5 <<<
            -- A v1.0 usava `updated_at > now() - interval '1 minute'`.
            -- Isso mede RELÓGIO, não conteúdo: passaria em qualquer base
            -- cuja escrita indevida não tocasse updated_at, e reprovaria
            -- por qualquer atividade concorrente alheia ao teste. Agora
            -- confronta to_jsonb da row INTEIRA contra o snapshot tirado
            -- antes, fora da sentinela.
            -- >>> BIDIRECIONAL — CORRIGIDO EM GATE-A-REV-02 §6 <<<
            -- INNER JOIN contra o snapshot só enxerga row ALTERADA. Row
            -- APAGADA some do join; row NOVA nunca entra nele. Os dois
            -- casos passariam despercebidos. FULL JOIN pega os três:
            -- desaparecida (r.id IS NULL), nova (s.id IS NULL) e alterada.
            SELECT count(*) INTO v_fora
              FROM (
                SELECT s.id AS sid, s.row_json, r.id AS rid, to_jsonb(r) AS now_json
                  FROM _snap_rows2826 s
                  FULL JOIN (
                        SELECT r2.*
                          FROM public.catalog_variant_import_row r2
                          JOIN public.catalog_variant_import_job j2 ON j2.id = r2.job_id
                         WHERE j2.card_set_id = v_cs3
                  ) r ON r.id = s.id
                 WHERE COALESCE(s.id, r.id) <> ALL (v_alvo)
              ) d
             WHERE d.sid IS NULL                       -- row NOVA
                OR d.rid IS NULL                       -- row APAGADA
                OR d.now_json IS DISTINCT FROM d.row_json;  -- row ALTERADA
            v_out := v_out || jsonb_build_object('caso','T','ok',(v_fora = 0),
                'det', format('%s divergencia(s) entre snapshot e estado atual das rows de BASE3 fora do alvo — conta APAGADA, NOVA e ALTERADA (esperado 0; universo confrontado=%s)',
                              v_fora, (SELECT count(*) FROM _snap_rows2826 s2
                                        WHERE s2.id <> ALL (v_alvo))));

            -- U — jobs NAO afetados intocados, bidirecional de verdade
            --
            -- >>> CORRIGIDO EM GATE-A-REV-03 §4 <<<
            -- A v2.0 montava o lado-baseline com um JOIN entre o snapshot e a
            -- tabela ATUAL para decidir quem era "fora do Card Set alvo".
            -- Quem tivesse sido APAGADO sumia do JOIN, e quem tivesse sido
            -- MOVIDO para v_cs3 saía do universo — os dois casos escapavam
            -- justamente da prova que o caso existe para fazer.
            --
            -- Agora o lado-baseline vem do snapshot puro (card_set_id_orig,
            -- capturado no momento da foto) e o lado-atual da tabela. O FULL
            -- JOIN pega: apagado, novo, alterado, movido PARA o alvo e movido
            -- PARA FORA do alvo.
            SELECT count(*) INTO v_jobs_tocados
              FROM (
                SELECT s.id AS sid, s.row_json, j.id AS jid, to_jsonb(j) AS now_json
                  FROM (SELECT s2.id, s2.row_json
                          FROM _snap_jobs2826 s2
                         WHERE s2.card_set_id_orig <> v_cs3) s        -- baseline puro
                  FULL JOIN (SELECT j3.* FROM public.catalog_variant_import_job j3
                              WHERE j3.card_set_id <> v_cs3) j        -- estado atual
                    ON j.id = s.id
              ) d
             WHERE d.sid IS NULL                        -- NOVO, ou movido PARA fora do alvo
                OR d.jid IS NULL                        -- APAGADO, ou movido PARA o alvo
                OR d.now_json IS DISTINCT FROM d.row_json;  -- ALTERADO
            v_out := v_out || jsonb_build_object('caso','U','ok',(v_jobs_tocados = 0),
                'det', format('%s divergencia(s) entre baseline (card_set_id do SNAPSHOT) e estado atual dos jobs fora do Card Set alvo — conta APAGADO, NOVO, ALTERADO e MOVIDO nos dois sentidos (esperado 0; universo baseline=%s)',
                              v_jobs_tocados, (SELECT count(*) FROM _snap_jobs2826 s2
                                                WHERE s2.card_set_id_orig <> v_cs3)));

            -- V — counters do job afetado corretos
            SELECT count(*) INTO v_n
              FROM public.catalog_variant_import_job j
              CROSS JOIN LATERAL (
                  SELECT count(*) AS t,
                         count(*) FILTER (WHERE r.validation_status='VALID') AS vv
                    FROM public.catalog_variant_import_row r WHERE r.job_id=j.id) c
             WHERE j.card_set_id = v_cs3
               AND (j.total_rows IS DISTINCT FROM c.t OR j.valid_rows IS DISTINCT FROM c.vv);
            v_out := v_out || jsonb_build_object('caso','V','ok',(v_n = 0),
                'det', format('%s job(s) afetado(s) com counters divergentes da contagem real (esperado 0)', v_n));

            -- W — action log: MESMA action, sem widen, metadata com escopo
            --
            -- >>> CORRIGIDO EM GATE-A-REV-01 §1 <<<
            -- A v1.0 escrevia `SELECT count(*), max(metadata) INTO ...`.
            -- PostgreSQL NÃO tem max(jsonb) — confirmado por catálogo em
            -- 2026-09-14: max(jsonb)=0 e min(jsonb)=0 ocorrências em
            -- pg_proc. O harness abortaria com "function max(jsonb) does
            -- not exist" ANTES de provar qualquer coisa, e o caso W nunca
            -- teria rodado. Mesma classe do incidente min(uuid) da Query
            -- 2189: agregado inexistente escondido dentro de um SELECT que
            -- "parece certo".
            --
            -- Correção: contagem e leitura do metadata em DOIS statements,
            -- sem agregado sobre jsonb. O LIMIT 1 é seguro porque a própria
            -- assertion exige v_log = 1.
            SELECT count(*) INTO v_log
              FROM public.catalog_admin_action_log
             WHERE action='CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED'
               AND entity_id = v_res.mapping_id;

            SELECT metadata INTO v_meta
              FROM public.catalog_admin_action_log
             WHERE action='CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED'
               AND entity_id = v_res.mapping_id
             ORDER BY created_at, id
             LIMIT 1;
            v_out := v_out || jsonb_build_object('caso','W',
                'ok', (v_log = 1
                       AND v_meta->>'scope_kind' = 'SOURCE_SET'
                       AND v_meta->>'external_set_id' = 'base3'
                       AND v_meta ? 'origin_row_id'
                       AND v_meta ? 'fallback_global_mapping_id'
                       AND v_meta ? 'rows_reclassified'
                       AND v_meta ? 'jobs_affected'),
                'det', format('%s evento(s) com action reutilizada; metadata=%s', v_log, COALESCE(v_meta::TEXT,'<null>')));

            RAISE EXCEPTION 'HARNESS_CORPUS_ROLLBACK';
        END;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_CORPUS_ROLLBACK' THEN v_rolled := TRUE;
        ELSE v_erro := SQLERRM; END IF;
    END;

    IF v_rolled THEN
        FOR e IN SELECT value FROM jsonb_array_elements(v_out) LOOP
            PERFORM pg_temp._chk(e->>'caso', (e->>'ok')::BOOLEAN, e->>'det');
        END LOOP;
    ELSE
        PERFORM pg_temp._chk(t.c, FALSE,
            COALESCE(NULLIF(v_erro,''), 'sentinela do bloco de corpus nao disparou'))
          FROM unnest(v_casos) AS t(c)
         WHERE t.c NOT IN ('N','N0','O','P','Q','Q2');
    END IF;

    -- ---------------------------------------------------------
    -- X — ATOMICIDADE
    --
    -- >>> REFORÇADO EM GATE-A-REV-01 §13 <<<
    -- A v1.0 provava apenas "não sobrou mapping scoped de base3".
    -- Isso é um subconjunto pequeno do que a sentinela precisa
    -- reverter: o bloco mutável escreveu MAPPING + STAGING (30
    -- rows reclassificadas) + COUNTERS do job + ACTION LOG. Provar
    -- só o mapping deixaria três superfícies inteiras sem
    -- verificação de reversão.
    --
    -- Agora confronta as QUATRO superfícies contra a baseline
    -- tirada na Seção 0, por digest de ROW INTEIRA onde existe —
    -- o que também pega vazamento em coluna que ainda nem foi
    -- criada.
    -- ---------------------------------------------------------
    DECLARE
        v_x_map  BOOLEAN; v_x_stg BOOLEAN; v_x_job BOOLEAN;
        v_x_log  BOOLEAN; v_x_sco BOOLEAN;
    BEGIN
        v_x_sco := NOT EXISTS (SELECT 1 FROM public.card_variant_type_external_mapping
                                WHERE external_set_id = 'base3');

        v_x_map := (SELECT v FROM _base2826 WHERE k='mapping_rows_digest')
                 = (SELECT v FROM pg_temp._snap2826() WHERE k='mapping_rows_digest');

        v_x_stg := (SELECT v FROM _base2826 WHERE k='staged_rows_digest')
                 = (SELECT v FROM pg_temp._snap2826() WHERE k='staged_rows_digest');

        v_x_job := (SELECT v FROM _base2826 WHERE k='jobs_rows_digest')
                 = (SELECT v FROM pg_temp._snap2826() WHERE k='jobs_rows_digest');

        v_x_log := (SELECT v FROM _base2826 WHERE k='action_log')
                 = (SELECT v FROM pg_temp._snap2826() WHERE k='action_log');

        PERFORM pg_temp._chk('X',
            v_rolled AND v_x_sco AND v_x_map AND v_x_stg AND v_x_job AND v_x_log,
            format('sentinela=%s | mapping scoped base3 ausente=%s | digest mappings=%s | digest staging=%s | digest jobs=%s | action log=%s',
                   CASE WHEN v_rolled THEN 'disparou' ELSE 'NAO DISPAROU' END,
                   CASE WHEN v_x_sco THEN 'OK' ELSE 'FALHA' END,
                   CASE WHEN v_x_map THEN 'OK' ELSE 'FALHA' END,
                   CASE WHEN v_x_stg THEN 'OK' ELSE 'FALHA' END,
                   CASE WHEN v_x_job THEN 'OK' ELSE 'FALHA' END,
                   CASE WHEN v_x_log THEN 'OK' ELSE 'FALHA' END));
    END;
END;
$corpus$;

-- =============================================================================
-- SEÇÃO 6 — RETROCOMPATIBILIDADE E ISOLAMENTO (casos Y, Z)
-- =============================================================================

DO $yz$
DECLARE v_div TEXT; v_globais INTEGER; v_scoped INTEGER;
BEGIN
    -- Y — os mappings pré-existentes continuam TODOS globais e íntegros.
    SELECT count(*) FILTER (WHERE external_set_id IS NULL),
           count(*) FILTER (WHERE external_set_id IS NOT NULL)
      INTO v_globais, v_scoped
      FROM public.card_variant_type_external_mapping;

    PERFORM pg_temp._chk('Y',
        v_globais::TEXT = (SELECT v FROM _base2826 WHERE k='mappings_global')
        AND v_scoped = 0
        AND (SELECT v FROM _base2826 WHERE k='mapping_rows_digest') =
            (SELECT v FROM pg_temp._snap2826() WHERE k='mapping_rows_digest'),
        format('%s mapping(s) global(is) integros por digest de row inteira; %s scoped remanescente(s) (esperado 0)',
               v_globais, v_scoped));

    -- Z — isolamento total contra a baseline.
    SELECT string_agg(format('%s: baseline=%s agora=%s', COALESCE(b.k, s.k), b.v, s.v), ' | ')
      INTO v_div
      FROM _base2826 b
      FULL JOIN pg_temp._snap2826() s ON s.k = b.k
     WHERE b.v IS DISTINCT FROM s.v;

    PERFORM pg_temp._chk('Z', v_div IS NULL,
        COALESCE(v_div,
        'isolamento confirmado: mappings, variant types, card_variant, staging, jobs, action log, referencias ativas e digests identicos a baseline'));
END;
$yz$;

-- =============================================================================
-- SEÇÃO 7 — FRONTEIRA PÚBLICA E COMPATIBILIDADE (casos AA, AB, AC, AD)
--
-- >>> ACRESCENTADA EM GATE-A-REV-01-CONTINUATION <<<
--
-- Princípio aprovado (opção 3): o canal execute_sql NÃO tem sessão de
-- aplicação autenticada — auth.uid()=NULL, is_admin()=FALSE (medido).
-- Portanto a prova se separa:
--
--   A. FRONTEIRA PÚBLICA  -> estática/estrutural, por catálogo  (AB, AD)
--   B. COMPORTAMENTO      -> runtime pelas internal.*           (AC + Seções 3/5)
--   C. E2E POSITIVO       -> sessão admin REAL da aplicação, gate futuro
--                            registrado no README. NÃO pertence aqui.
--
-- Este harness NÃO afirma, em nenhum ponto, ter executado positivamente uma
-- RPC pública protegida por is_admin().
-- =============================================================================

DO $s7$
DECLARE
    v_falhas TEXT := '';
    v_n      INTEGER;
    r        RECORD;
    v_oid    OID;
    v_src    TEXT;
    v_msg    TEXT;   -- separado de v_src de proposito: reaproveitar a mesma
                     -- variavel para prosrc E para o loop de mensagens
                     -- sobrescreveria o corpo no meio da checagem
BEGIN
    -- -------------------------------------------------------------------
    -- AA — o CONSUMIDOR 2 aplicado é exatamente a Query 2197
    --
    -- Prova por igualdade de hash do prosrc, não por leitura visual. O valor
    -- esperado foi produzido mecanicamente (prosrc LIVE + 4 substituições) e
    -- registrado no cabeçalho da 2197.
    -- -------------------------------------------------------------------
    SELECT md5(p.prosrc) INTO v_src
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public'
       AND p.proname='admin_resolve_catalog_variant_import_printing_mapping';

    PERFORM pg_temp._chk('AA',
        v_src = 'b98f96a287f7c4d270c4239433bb6f2c',
        format('md5(prosrc) do consumidor 2 = %s (esperado b98f96a287f7c4d270c4239433bb6f2c). '
               || 'Baseline pre-2197 era 2063b34d552766ff8cb220c9c6099f40; se o md5 bater na baseline, '
               || 'a Query 2197 NAO foi aplicada; se nao bater em nenhum dos dois, houve drift e o diff precisa ser rebaseado.',
               COALESCE(v_src,'<funcao ausente>')));

    -- -------------------------------------------------------------------
    -- AB — PROVA ESTÁTICA FORTE DA FRONTEIRA PÚBLICA
    --
    -- Para cada RPC pública relevante: existência única (sem overload),
    -- assinatura de identidade exata, SECURITY DEFINER, search_path vazio,
    -- guard is_admin(), captura de auth.uid(), delegação ao contrato interno
    -- esperado, e ACL (authenticated sim; anon e PUBLIC não).
    --
    -- search_path é testado POR VALOR (proconfig guarda `search_path=""`,
    -- com aspas), não por literal — erro já cometido e corrigido nesta frente.
    -- -------------------------------------------------------------------
    -- >>> POR RESPONSABILIDADE — GATE-A-REV-02 §7 <<<
    --
    -- A v1.0 exigia auth.uid() nas TRÊS. Medido em 2194: o preview é
    -- read-only e NÃO passa ator para lugar nenhum — o corpo só chama
    -- is_admin() e delega. Exigir auth.uid() ali reprovaria uma função
    -- correta, ou pior: forçaria alguém a inserir uma chamada inútil só
    -- para o harness ficar verde. Harness não deve ditar código morto.
    --
    -- Contrato por tipo:
    --   TODAS          -> is_admin(), SECURITY DEFINER, search_path vazio,
    --                     ACL, delegação fina
    --   DE ESCRITA     -> + auth.uid() capturado e delegado como ator
    --   PREVIEW        -> auth.uid() NÃO exigido (não é contrato dele)
    FOR r IN
        SELECT * FROM (VALUES
            ('admin_preview_catalog_variant_import_mapping',
             'p_row_id uuid, p_variant_type_id uuid, p_scope_kind text',
             'internal.variant_type_mapping_decision', FALSE),
            ('admin_resolve_catalog_variant_import_mapping',
             'p_row_id uuid, p_variant_type_id uuid',
             'internal.apply_variant_type_mapping', TRUE),
            ('admin_resolve_catalog_variant_import_mapping_for_set',
             'p_row_id uuid, p_variant_type_id uuid',
             'internal.apply_variant_type_mapping', TRUE)
        ) AS t(fname, args, deleg, escrita)
    LOOP
        SELECT count(*) INTO v_n
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname = r.fname;

        IF v_n <> 1 THEN
            v_falhas := v_falhas || format('%s: %s definicao(oes), esperado exatamente 1 (overload quebra o contrato do cliente) ;; ', r.fname, v_n);
            CONTINUE;
        END IF;

        SELECT p.oid, p.prosrc INTO v_oid, v_src
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname = r.fname;

        IF pg_get_function_identity_arguments(v_oid) <> r.args THEN
            v_falhas := v_falhas || format('%s: assinatura=%s, esperado=%s ;; ',
                                           r.fname, pg_get_function_identity_arguments(v_oid), r.args);
        END IF;

        IF NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid=v_oid) THEN
            v_falhas := v_falhas || format('%s: nao e SECURITY DEFINER ;; ', r.fname);
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM pg_proc p, LATERAL unnest(COALESCE(p.proconfig, ARRAY[]::TEXT[])) c
             WHERE p.oid=v_oid AND c LIKE 'search_path=%'
               AND btrim(replace(split_part(c,'=',2), '"', '')) = ''
        ) THEN
            v_falhas := v_falhas || format('%s: search_path nao esta vazio em proconfig ;; ', r.fname);
        END IF;

        IF position('public.is_admin()' IN v_src) = 0 THEN
            v_falhas := v_falhas || format('%s: corpo nao contem guard public.is_admin() ;; ', r.fname);
        END IF;

        -- auth.uid() só é contrato das RPCs DE ESCRITA, que precisam
        -- entregar o ator ao worker. Ver bloco acima.
        IF r.escrita AND position('auth.uid()' IN v_src) = 0 THEN
            v_falhas := v_falhas || format('%s: RPC de escrita nao captura auth.uid() para delegar como ator ;; ', r.fname);
        END IF;

        IF position(r.deleg IN v_src) = 0 THEN
            v_falhas := v_falhas || format('%s: corpo nao delega a %s ;; ', r.fname, r.deleg);
        END IF;

        IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE') THEN
            v_falhas := v_falhas || format('%s: authenticated SEM EXECUTE ;; ', r.fname);
        END IF;

        IF has_function_privilege('anon', v_oid, 'EXECUTE') THEN
            v_falhas := v_falhas || format('%s: anon COM EXECUTE ;; ', r.fname);
        END IF;

        IF EXISTS (
            SELECT 1 FROM pg_proc p, LATERAL aclexplode(p.proacl) a
             WHERE p.oid=v_oid AND a.grantee = 0 AND a.privilege_type='EXECUTE'
        ) THEN
            v_falhas := v_falhas || format('%s: PUBLIC COM EXECUTE ;; ', r.fname);
        END IF;
    END LOOP;

    -- Específicos da RPC GLOBAL legada: retorno histórico de 3 colunas,
    -- scope literal GLOBAL, e as mensagens de erro preservadas literalmente.
    SELECT p.oid, p.prosrc INTO v_oid, v_src
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='admin_resolve_catalog_variant_import_mapping';

    IF v_oid IS NOT NULL THEN
        IF pg_get_function_result(v_oid)
           <> 'TABLE(mapping_id uuid, rows_updated integer, jobs_affected integer)' THEN
            v_falhas := v_falhas || format('RPC legada: retorno=%s, esperado TABLE(mapping_id uuid, rows_updated integer, jobs_affected integer) ;; ',
                                           pg_get_function_result(v_oid));
        END IF;

        IF position('''GLOBAL''' IN v_src) = 0 THEN
            v_falhas := v_falhas || 'RPC legada: nao delega com escopo literal GLOBAL ;; ';
        END IF;

        -- >>> MENSAGENS POR RESPONSABILIDADE — GATE-A-REV-02 §8 <<<
        --
        -- Só FORBIDDEN e MISSING_IDS pertencem à FRONTEIRA e vivem
        -- mesmo no wrapper. NOT_NEEDS_REVIEW e DUPLICATE são erros do
        -- WORKER; o wrapper apenas os menciona num COMENTÁRIO do corpo
        -- (2195 linha 114). Como `prosrc` inclui comentários, procurar
        -- essas strings aqui daria PASS por causa do comentário — falso
        -- positivo puro, provando o texto e não o comportamento. Elas
        -- passam a ser provadas em RUNTIME no worker, caso AF.
        FOREACH v_msg IN ARRAY ARRAY[
            'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_FORBIDDEN',
            'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_MISSING_IDS']
        LOOP
            IF position(v_msg IN v_src) = 0 THEN
                v_falhas := v_falhas || format('RPC legada: mensagem de FRONTEIRA %s ausente ;; ', v_msg);
            END IF;
        END LOOP;
    END IF;

    -- A RPC scoped precisa delegar com SOURCE_SET e ser função DISTINTA
    -- (opt-in explícito, decisão 1 do contrato — não overload, não DEFAULT).
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public'
           AND p.proname='admin_resolve_catalog_variant_import_mapping_for_set'
           AND position('''SOURCE_SET''' IN p.prosrc) > 0
    ) THEN
        v_falhas := v_falhas || 'RPC scoped: nao delega com escopo literal SOURCE_SET ;; ';
    END IF;

    PERFORM pg_temp._chk('AB', v_falhas = '',
        CASE WHEN v_falhas = ''
             THEN 'fronteira publica integra nas 3 RPCs: definicao unica, assinatura de identidade exata, SECURITY DEFINER, search_path vazio por VALOR, guard public.is_admin(), delegacao ao contrato internal esperado, ACL authenticated=EXECUTE e anon/PUBLIC sem EXECUTE; auth.uid() exigido SO nas 2 RPCs de escrita (o preview e read-only e nao passa ator); RPC legada com retorno historico de 3 colunas, escopo GLOBAL e as 2 mensagens de FRONTEIRA preservadas (as do worker sao provadas em runtime no caso AF); RPC scoped delegando SOURCE_SET como funcao distinta'
             ELSE v_falhas END);

    -- -------------------------------------------------------------------
    -- AD — WRAPPERS FINOS: zero lógica de negócio duplicada
    --
    -- O risco real de ter wrapper público + worker interno é o wrapper
    -- ganhar regra própria com o tempo e divergir silenciosamente do
    -- contrato. Prova: nenhum dos wrappers pode tocar diretamente as
    -- tabelas de staging ou de mapping — se tocar, deixou de ser wrapper.
    -- -------------------------------------------------------------------
    v_falhas := '';
    FOR r IN
        SELECT p.proname AS fname, p.prosrc AS src
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public'
           AND p.proname IN ('admin_preview_catalog_variant_import_mapping',
                             'admin_resolve_catalog_variant_import_mapping',
                             'admin_resolve_catalog_variant_import_mapping_for_set')
    LOOP
        IF position('catalog_variant_import_row' IN r.src) > 0 THEN
            v_falhas := v_falhas || format('%s: referencia catalog_variant_import_row diretamente — deixou de ser wrapper fino ;; ', r.fname);
        END IF;
        IF position('card_variant_type_external_mapping' IN r.src) > 0 THEN
            v_falhas := v_falhas || format('%s: referencia card_variant_type_external_mapping diretamente — deixou de ser wrapper fino ;; ', r.fname);
        END IF;
        IF position('compute_variant_residual_signature' IN r.src) > 0 THEN
            v_falhas := v_falhas || format('%s: recalcula assinatura residual — duplicacao de regra ;; ', r.fname);
        END IF;
    END LOOP;

    PERFORM pg_temp._chk('AD', v_falhas = '',
        CASE WHEN v_falhas = ''
             THEN 'os 3 wrappers publicos nao tocam staging, mapping nem recalculam assinatura residual: toda a regra A/B/C vive no contrato internal, uma implementacao so'
             ELSE v_falhas END);
END;
$s7$;

-- -------------------------------------------------------------------------
-- AC — COMPATIBILIDADE SEMÂNTICA DO CAMINHO GLOBAL LEGADO (runtime)
--
-- Executa o MESMO cenário que a RPC legada delega — worker interno com
-- p_scope_kind='GLOBAL' e ator admin REAL já existente em admin_user —
-- dentro de sentinela revertida.
--
-- >>> ESCOPO DESTA PROVA, DECLARADO <<<
-- Prova a SEMÂNTICA delegada: mapping nasce GLOBAL (external_set_id NULL),
-- propagation, counters, action log e rollback integral.
-- NÃO prova autenticação pública — isso é AB (estático) + gate E2E futuro.
--
-- O mapping criado aqui é sintético e revertido; NÃO constitui decisão
-- editorial sobre nenhum combo real.
-- -------------------------------------------------------------------------
DO $ac$
DECLARE
    v_game UUID; v_src UUID; v_cs3 UUID; v_admin UUID;
    v_origin UUID; v_vt UUID;
    v_out JSONB := NULL; v_roll BOOLEAN := FALSE; v_erro TEXT := '';
    v_snap_antes TEXT;
BEGIN
    SELECT v::UUID INTO v_game  FROM _ctx2826 WHERE k='game';
    SELECT v::UUID INTO v_src   FROM _ctx2826 WHERE k='src';
    SELECT v::UUID INTO v_cs3   FROM _ctx2826 WHERE k='cs_base3';
    SELECT v::UUID INTO v_admin FROM _ctx2826 WHERE k='admin';
    SELECT v::UUID INTO v_vt    FROM _ctx2826 WHERE k='vt_galaxy';

    SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k)) INTO v_snap_antes
      FROM pg_temp._snap2826();

    -- >>> FIXTURE DETERMINÍSTICA — GATE-A-REV-02 §10 <<<
    --
    -- A v1.0 pegava "a primeira NEEDS_REVIEW de BASE3 por ORDER BY id".
    -- Isso faz o teste MUDAR DE SIGNIFICADO se a ordem ou o corpus
    -- mudarem: amanhã a primeira pode ser outra assinatura, com outra
    -- elegibilidade, e o caso passaria provando outra coisa.
    --
    -- Agora a assinatura é ESCOLHIDA e DECLARADA: BASE3 NORMAL|GALAXY.
    -- Medido em 2026-09-14: 92 rows, TODAS NEEDS_REVIEW / decision
    -- PENDING / persistence PENDING / resulting_variant_id NULL, com
    -- printing resolvido (46 RESOLVED_NO_PRINTING + 46 RESOLVED_WITH_PROFILE)
    -- e ZERO mapping GLOBAL para o combo — logo o caminho GLOBAL legado
    -- (que exige origem NEEDS_REVIEW e combo sem mapping) é exercitável
    -- sem ambiguidade.
    --
    -- A ausência do mapping é PROVADA antes de usar a fixture, e não
    -- assumida.
    DECLARE
        v_map_global INTEGER;
    BEGIN
        SELECT count(*) INTO v_map_global
          FROM public.card_variant_type_external_mapping m
         WHERE m.game_id = v_game AND m.asset_source_id = v_src
           AND m.normalized_type = 'NORMAL'
           AND COALESCE(m.normalized_foil,'') = 'GALAXY'
           AND COALESCE(m.normalized_subtype,'') = ''
           AND COALESCE(m.normalized_stamp,'{}'::TEXT[]) = '{}'::TEXT[];

        IF v_map_global <> 0 THEN
            PERFORM pg_temp._chk('AC', FALSE,
                format('pre-condicao quebrada: ja existe %s mapping(s) para BASE3 NORMAL|GALAXY. '
                       'A fixture do caminho GLOBAL legado exige combo SEM mapping vigente (guard DUPLICATE). '
                       'Se um override foi criado, rebasear a fixture do caso AC.', v_map_global));
            RETURN;
        END IF;

        SELECT r.id INTO v_origin
          FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          CROSS JOIN LATERAL internal.compute_variant_residual_signature(r.raw_data, v_game, v_src) sg
         WHERE j.card_set_id = v_cs3 AND j.status='STAGED'
           AND r.validation_status = 'NEEDS_REVIEW'
           AND r.decision_status = 'PENDING'
           AND r.persistence_status = 'PENDING'
           AND r.resulting_variant_id IS NULL
           AND sg.printing_state IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE')
           AND sg.residual_type = 'NORMAL'
           AND sg.residual_foil = 'GALAXY'
           AND sg.residual_subtype IS NULL
           AND COALESCE(sg.residual_stamp,'{}'::TEXT[]) = '{}'::TEXT[]
         ORDER BY r.id LIMIT 1;
    END;

    IF v_origin IS NULL THEN
        PERFORM pg_temp._chk('AC', FALSE,
            'nenhuma row BASE3 NORMAL|GALAXY elegivel (NEEDS_REVIEW/PENDING/PENDING/sem variant, printing resolvido) — corpus mudou, rebasear a fixture declarada do caso AC');
        RETURN;
    END IF;

    BEGIN
        DECLARE v_res RECORD; v_scoped INTEGER; v_log INTEGER; v_cnt INTEGER;
        BEGIN
            SELECT * INTO v_res
              FROM internal.apply_variant_type_mapping(v_admin, v_origin, v_vt, 'GLOBAL');

            SELECT count(*) INTO v_scoped
              FROM public.card_variant_type_external_mapping
             WHERE id = v_res.mapping_id AND external_set_id IS NULL;

            SELECT count(*) INTO v_log
              FROM public.catalog_admin_action_log
             WHERE action='CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED'
               AND entity_id = v_res.mapping_id;

            -- counters do job afetado batem com a contagem real
            SELECT count(*) INTO v_cnt
              FROM public.catalog_variant_import_job j
              CROSS JOIN LATERAL (
                  SELECT count(*) AS t,
                         count(*) FILTER (WHERE r.validation_status='VALID') AS vv
                    FROM public.catalog_variant_import_row r WHERE r.job_id=j.id) c
             WHERE j.card_set_id = v_cs3
               AND (j.total_rows IS DISTINCT FROM c.t OR j.valid_rows IS DISTINCT FROM c.vv);

            v_out := jsonb_build_object(
                'ok', (v_res.mapping_id IS NOT NULL
                       AND v_scoped = 1
                       AND v_res.scope_kind = 'GLOBAL'
                       AND v_res.external_set_id IS NULL
                       AND v_res.rows_reclassified > 0
                       AND v_res.jobs_affected >= 1
                       AND v_log = 1
                       AND v_cnt = 0),
                'det', format('mapping_id=%s scope=%s external_set_id=%s total=%s reclassificadas=%s pendentes=%s jobs=%s; mapping GLOBAL(external_set_id NULL)=%s; action log=%s evento(s); jobs com counters divergentes=%s',
                              v_res.mapping_id, v_res.scope_kind,
                              COALESCE(v_res.external_set_id,'NULL'),
                              v_res.rows_total, v_res.rows_reclassified,
                              v_res.rows_still_pending, v_res.jobs_affected,
                              v_scoped, v_log, v_cnt));

            RAISE EXCEPTION 'HARNESS_AC_ROLLBACK';
        END;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_AC_ROLLBACK' THEN v_roll := TRUE;
        ELSE v_erro := SQLERRM; END IF;
    END;

    IF v_roll AND v_out IS NOT NULL THEN
        PERFORM pg_temp._chk('AC',
            (v_out->>'ok')::BOOLEAN
            AND v_snap_antes = (SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k))
                                  FROM pg_temp._snap2826()),
            (v_out->>'det') || format(' | rollback integral: %s',
                CASE WHEN v_snap_antes = (SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k))
                                            FROM pg_temp._snap2826())
                     THEN 'snapshot completo identico ao de antes'
                     ELSE 'FALHA — sobrou estado' END));
    ELSE
        PERFORM pg_temp._chk('AC', FALSE,
            'cenario GLOBAL legado nao completou: ' ||
            COALESCE(NULLIF(v_erro,''), 'sentinela nao disparou'));
    END IF;
END;
$ac$;

-- -------------------------------------------------------------------------
-- AE — PROTEÇÃO DE DRIFT DO CONSUMIDOR 1 (Query 2196)
--
-- >>> GATE-A-REV-02 §9 <<<
-- O README afirmava proteção de rebase para "2196/2197". Na prática o caso
-- AA cobria SÓ o consumidor 2. Afirmação maior que a prova — corrigido aqui.
--
-- ASSIMETRIA DECLARADA, de propósito:
--   * CONSUMIDOR 2 (Query 2197) — hash NOS DOIS LADOS. O arquivo foi gerado
--     mecanicamente do prosrc LIVE, então o resultado é previsível byte a byte.
--   * CONSUMIDOR 1 (Query 2196) — hash no PRECHECK, propriedades no PÓS.
--     O corpo do 2196 foi escrito com comentários explicativos próprios, logo
--     o prosrc pós-aplicação NÃO é byte-idêntico ao diff mínimo. Fixar um hash
--     de saída ali seria inventar um número.
--
-- >>> ONDE MORA CADA METADE — CORRIGIDO EM GATE-A-REV-03 §5 <<<
-- O PRECHECK por hash vive DENTRO da Query 2196, na Seção 0 daquele arquivo,
-- antes do primeiro CREATE OR REPLACE. É lá que ele pode existir: este
-- harness só roda com a 2196 já aplicada (o caso AA exige a 2197, que vem
-- depois), então AE jamais poderia ser precheck de nada.
--
-- Consequência: AE é POSTCHECK PURO. Não aceita mais a baseline como estado
-- válido — se o consumidor 1 ainda estiver na baseline quando o harness roda,
-- a 2196 não foi aplicada e isso É uma falha.
--
-- Baseline (usada pelo precheck da 2196, registrada aqui só como referência):
--   md5 4ce5cc4ca573955c744ffe376eb03ca4 · 15.868 chars · 356 linhas
--   (o diff mínimo semântico daria 1b506eecc9760dc0ad9a94761deb3798 /
--    15.778 / 357 — REFERÊNCIA do diff, NÃO gate, porque o arquivo carrega
--    comentários a mais.)
-- -------------------------------------------------------------------------
DO $ae$
DECLARE
    v_src TEXT; v_md5 TEXT;
    v_baseline BOOLEAN; v_pos BOOLEAN;
    v_vm INTEGER; v_tab INTEGER; v_helper INTEGER; v_cs INTEGER;
BEGIN
    SELECT p.prosrc, md5(p.prosrc) INTO v_src, v_md5
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='internal'
       AND p.proname='create_card_printing_profile_with_backfill';

    IF v_src IS NULL THEN
        PERFORM pg_temp._chk('AE', FALSE,
            'internal.create_card_printing_profile_with_backfill nao existe — Query 2190/2196 ausente');
        RETURN;
    END IF;

    -- >>> GATE-B-HARNESS-CORRECTION-01 §3 <<<
    --
    -- A v4.0 exigia `v_tab = 0` — ZERO ocorrencias do nome da tabela no
    -- prosrc. Mas `prosrc` PRESERVA COMENTARIOS, e o corpo da 2196 carrega,
    -- de proposito, o comentario que explica o proprio diff:
    --     "Substitui o LEFT JOIN direto contra card_variant_type_external_mapping."
    -- Logo `v_tab` nunca poderia ser 0 e o gate era insatisfazivel por
    -- construcao — falso negativo da MESMA classe ja corrigida em
    -- GATE-A-REV-02 §8 (a 2195 citando NOT_NEEDS_REVIEW em comentario).
    -- Ausencia textual de um nome de tabela nao e prova de nada quando o
    -- texto inclui prosa.
    --
    -- Agora existe o que faltava na REV-02: EVIDENCIA POS-APLICACAO REAL.
    -- A 2196 foi aplicada no LIVE e o corpo resultante foi confrontado,
    -- token a token, com o arquivo staged (vm.=0, JOIN direto real ausente
    -- por position(), helper=1, card_set_id=4). Esse corpo tem hash estavel:
    --
    --     md5(prosrc) = ea56488f9805858ab2b1839de2a85515
    --     16.211 chars · 366 linhas
    --
    -- O VEREDITO passa a ser esse hash exato. Baseline pre-2196 deixa de ser
    -- estado aceitavel, e nao ha mais OR entre baseline e pos.
    -- As quatro contagens permanecem — como DIAGNOSTICO, para nomear o que
    -- divergiu quando o hash divergir, nunca como criterio de aprovacao.
    v_baseline := (v_md5 = '4ce5cc4ca573955c744ffe376eb03ca4');

    v_vm     := (length(v_src) - length(replace(v_src, 'vm.', ''))) / 3;
    v_tab    := (length(v_src) - length(replace(v_src, 'card_variant_type_external_mapping', ''))) / 34;
    v_helper := (length(v_src) - length(replace(v_src, 'lookup_variant_type_for_row', ''))) / 27;
    v_cs     := (length(v_src) - length(replace(v_src, 'card_set_id', ''))) / 11;

    -- Diagnostico secundario. NAO e o veredito.
    v_pos := (v_vm = 0 AND v_helper >= 1 AND v_cs >= 1);

    PERFORM pg_temp._chk('AE',
        (v_md5 = 'ea56488f9805858ab2b1839de2a85515'),
        format('consumidor 1: md5=%s | esperado pos-2196=ea56488f9805858ab2b1839de2a85515 -> %s | baseline pre-2196=%s | diagnostico: refs vm.=%s, refs tabela de mapping (inclui comentarios)=%s, chamadas ao helper=%s, mencoes a card_set_id=%s -> %s. %s',
               v_md5,
               CASE WHEN v_md5 = 'ea56488f9805858ab2b1839de2a85515' THEN 'HASH EXATO' ELSE 'DIVERGE' END,
               CASE WHEN v_baseline THEN 'SIM — 2196 NAO aplicada' ELSE 'nao' END,
               v_vm, v_tab, v_helper, v_cs,
               CASE WHEN v_pos THEN 'propriedades do diff presentes' ELSE 'propriedades do diff AUSENTES' END,
               CASE WHEN v_md5 = 'ea56488f9805858ab2b1839de2a85515'
                        THEN 'Consumidor 1 identico ao corpo aplicado e confrontado. Sem drift.'
                    WHEN v_baseline
                        THEN 'DRIFT: o consumidor 1 ainda esta na baseline pre-2196 — a Query 2196 NAO foi aplicada.'
                    ELSE 'DRIFT: o corpo do consumidor 1 nao e o que foi aplicado no GATE-B. REBASEAR e reconferir antes de prosseguir.' END));
END;
$ae$;

-- -------------------------------------------------------------------------
-- AF — MENSAGENS DO WORKER, PROVADAS EM RUNTIME
--
-- >>> GATE-A-REV-02 §8 <<<
-- NOT_NEEDS_REVIEW e DUPLICATE são erros do WORKER, não da fronteira. A v1.0
-- os procurava no prosrc do wrapper — onde aparecem apenas num COMENTÁRIO
-- (2195 linha 114). `prosrc` inclui comentários, então aquilo daria PASS
-- provando texto, não comportamento. Aqui os dois são exercitados de verdade.
-- -------------------------------------------------------------------------
DO $af$
DECLARE
    v_game UUID; v_src UUID; v_cs3 UUID; v_admin UUID; v_vt UUID;
    v_row_valid UUID; v_row_nr UUID;
    v_out JSONB := NULL; v_roll BOOLEAN := FALSE; v_erro TEXT := '';
    v_snap TEXT;
BEGIN
    SELECT v::UUID INTO v_game  FROM _ctx2826 WHERE k='game';
    SELECT v::UUID INTO v_src   FROM _ctx2826 WHERE k='src';
    SELECT v::UUID INTO v_cs3   FROM _ctx2826 WHERE k='cs_base3';
    SELECT v::UUID INTO v_admin FROM _ctx2826 WHERE k='admin';
    SELECT v::UUID INTO v_vt    FROM _ctx2826 WHERE k='vt_galaxy';

    SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k)) INTO v_snap
      FROM pg_temp._snap2826();

    -- origem VALID: viola a pré-condição histórica do caminho GLOBAL
    SELECT r.id INTO v_row_valid
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id=r.job_id
     WHERE j.card_set_id=v_cs3 AND j.status='STAGED'
       AND r.validation_status='VALID'
     ORDER BY r.id LIMIT 1;

    -- origem NEEDS_REVIEW de NORMAL|GALAXY (combo sem mapping — ver AC)
    SELECT r.id INTO v_row_nr
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id=r.job_id
      CROSS JOIN LATERAL internal.compute_variant_residual_signature(r.raw_data, v_game, v_src) sg
     WHERE j.card_set_id=v_cs3 AND j.status='STAGED'
       AND r.validation_status='NEEDS_REVIEW' AND r.decision_status='PENDING'
       AND sg.printing_state IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE')
       AND sg.residual_type='NORMAL' AND sg.residual_foil='GALAXY'
     ORDER BY r.id LIMIT 1;

    IF v_row_valid IS NULL OR v_row_nr IS NULL THEN
        PERFORM pg_temp._chk('AF', FALSE,
            format('fixtures ausentes: row VALID=%s, row NEEDS_REVIEW NORMAL|GALAXY=%s',
                   COALESCE(v_row_valid::TEXT,'<nenhuma>'), COALESCE(v_row_nr::TEXT,'<nenhuma>')));
        RETURN;
    END IF;

    BEGIN
        DECLARE
            v_e1 TEXT := ''; v_e2 TEXT := '';
            v_vs_antes TEXT; v_ins INTEGER;
        BEGIN
            -- ---------------------------------------------------------
            -- 1. ORIGIN_NOT_NEEDS_REVIEW — origem VALID
            -- ---------------------------------------------------------
            BEGIN
                PERFORM internal.apply_variant_type_mapping(v_admin, v_row_valid, v_vt, 'GLOBAL');
            EXCEPTION WHEN OTHERS THEN v_e1 := SQLERRM;
            END;

            -- ---------------------------------------------------------
            -- 2. DUPLICATE_GLOBAL — DETERMINÍSTICO
            --
            -- >>> CORRIGIDO EM GATE-A-REV-03 §6 <<<
            -- A v2.0 aplicava o worker DUAS vezes na MESMA origem. Medida a
            -- ordem real dos guards no contrato (Query 2192):
            --    ORIGIN_NOT_NEEDS_REVIEW (462) ... DUPLICATE (526)
            -- A primeira aplicação PROPAGA e reclassifica a própria origem
            -- para VALID — então a segunda chamada bateria em
            -- ORIGIN_NOT_NEEDS_REVIEW e NUNCA chegaria ao DUPLICATE. O caso
            -- passaria pelo motivo errado ou reprovaria sem explicar por quê.
            --
            -- Cenário correto: criar o mapping por INSERT DIRETO (fixture),
            -- sem passar pelo worker. Ninguém revalida as rows, então a
            -- origem CONTINUA NEEDS_REVIEW e satisfaz todos os guards
            -- anteriores; o único que pode disparar é o DUPLICATE.
            --
            -- O harness se adapta ao contrato real do worker. O worker NÃO é
            -- alterado para o harness passar.
            -- ---------------------------------------------------------
            SELECT r.validation_status INTO v_vs_antes
              FROM public.catalog_variant_import_row r WHERE r.id = v_row_nr;

            -- >>> GATE-B-HARNESS-CORRECTION-01 §2 <<<
            -- external_type e NOT NULL sem default: a fixture abortava com
            -- 23502 e o caso nunca chegava a exercitar o guard DUPLICATE.
            -- external_type/external_foil recebem o par bruto correspondente
            -- aos normalized_* ja declarados. Nada mais do caso AF muda:
            -- mesma ordem de guards, mesmo worker, origem segue NEEDS_REVIEW.
            INSERT INTO public.card_variant_type_external_mapping
                (game_id, asset_source_id, external_set_id, variant_type_id,
                 external_type, external_foil,
                 normalized_type, normalized_foil, normalized_subtype, normalized_stamp)
            VALUES (v_game, v_src, NULL, v_vt,
                    'NORMAL', 'GALAXY',
                    'NORMAL', 'GALAXY', NULL, NULL);

            GET DIAGNOSTICS v_ins = ROW_COUNT;
            IF v_ins <> 1 THEN
                RAISE EXCEPTION 'HARNESS_AF_FIXTURE_NOT_INSERTED: mapping GLOBAL de fixture nao foi criado.';
            END IF;

            BEGIN
                PERFORM internal.apply_variant_type_mapping(v_admin, v_row_nr, v_vt, 'GLOBAL');
            EXCEPTION WHEN OTHERS THEN v_e2 := SQLERRM;
            END;

            v_out := jsonb_build_object(
                'ok', (v_e1 LIKE 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_NOT_NEEDS_REVIEW%'
                       AND v_vs_antes = 'NEEDS_REVIEW'   -- guards anteriores satisfeitos
                       AND v_e2 LIKE 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_DUPLICATE%'),
                'det', format('origem VALID -> %s | origem NEEDS_REVIEW (%s) com mapping GLOBAL pre-existente por INSERT direto -> %s',
                              COALESCE(NULLIF(left(v_e1,60),''),'<NAO LEVANTOU — FALHA>'),
                              COALESCE(v_vs_antes,'<null>'),
                              COALESCE(NULLIF(left(v_e2,60),''),'<NAO LEVANTOU — FALHA>')));

            RAISE EXCEPTION 'HARNESS_AF_ROLLBACK';
        END;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_AF_ROLLBACK' THEN v_roll := TRUE;
        ELSE v_erro := SQLERRM; END IF;
    END;

    IF v_roll AND v_out IS NOT NULL THEN
        PERFORM pg_temp._chk('AF',
            (v_out->>'ok')::BOOLEAN
            AND v_snap = (SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k)) FROM pg_temp._snap2826()),
            (v_out->>'det') || format(' | rollback: %s',
                CASE WHEN v_snap = (SELECT md5(string_agg(k || '=' || v, '|' ORDER BY k))
                                      FROM pg_temp._snap2826())
                     THEN 'snapshot identico ao de antes' ELSE 'SOBROU ESTADO — FALHA' END));
    ELSE
        PERFORM pg_temp._chk('AF', FALSE,
            'cenario de mensagens do worker nao completou: ' ||
            COALESCE(NULLIF(v_erro,''), 'sentinela nao disparou'));
    END IF;
END;
$af$;

-- =============================================================================
-- GATE — CARDINALIDADE EXATA: 35 PASS / 0 FAIL / 35 REGISTROS
--
-- >>> REFORÇADO EM GATE-A-REV-01 §12 <<<
-- A v1.0 exigia apenas `v_fail = 0`. Isso passa silenciosamente quando um caso
-- NÃO RODA: sem registro, não há FAIL, e o gate aprova uma cobertura
-- incompleta. Agora o gate exige as três coisas ao mesmo tempo — nenhum FAIL,
-- o número EXATO de PASS, e o número EXATO de registros — de modo que caso
-- ausente, caso duplicado e caso extra são todos detectados.
--
-- Não há COMMIT nem ROLLBACK aqui. Se o gate reprovar, o RAISE aborta a
-- transação que o Management API abriu — camada final de segurança, não o
-- mecanismo do qual o PASS depende.
-- =============================================================================
DO $gate$
DECLARE
    c_esperado CONSTANT INTEGER := 35;
    v_pass INTEGER; v_fail INTEGER; v_tot INTEGER; v_falhas TEXT; v_ausentes TEXT;
    c_roster CONSTANT TEXT[] := ARRAY[
        'A','B','C','D',                          -- Secao 1
        'E','F','G','H',                          -- Secao 2
        'I','J','K','L','M',                      -- Secao 3
        'P_VECTORS',                              -- Secao 4
        'N','N0','O','P','Q','Q2','R','S','T','U','V','W','X',  -- Secao 5
        'Y','Z',                                  -- Secao 6
        'AA','AB','AC','AD','AE','AF'];           -- Secao 7
BEGIN
    SELECT count(*) FILTER (WHERE veredito='PASS'),
           count(*) FILTER (WHERE veredito='FAIL'),
           count(*)
      INTO v_pass, v_fail, v_tot FROM _r2826;

    SELECT string_agg(caso || ': ' || detalhe, E'\n') INTO v_falhas
      FROM _r2826 WHERE veredito='FAIL';

    SELECT string_agg(c, ', ') INTO v_ausentes
      FROM unnest(c_roster) AS t(c)
     WHERE NOT EXISTS (SELECT 1 FROM _r2826 r WHERE r.caso = t.c);

    IF v_fail > 0 OR v_pass <> c_esperado OR v_tot <> c_esperado OR v_ausentes IS NOT NULL THEN
        RAISE EXCEPTION 'GATE_2826_FAILED: % PASS / % FAIL / % registros (exigido %/0/%).% %',
            v_pass, v_fail, v_tot, c_esperado, c_esperado,
            CASE WHEN v_ausentes IS NULL THEN ''
                 ELSE E'\nCASOS AUSENTES (nao rodaram): ' || v_ausentes END,
            E'\n' || COALESCE(v_falhas, '');
    END IF;
END;
$gate$;

SELECT 'CASO'::TEXT AS tipo, caso AS chave, veredito AS valor, detalhe
  FROM _r2826
 ORDER BY chave;

-- ================================================================
-- CONFIRMADO EXECUTADO em 2026-09-14 — run #2: 35 PASS / 0 FAIL / 35 registros,
-- P_VECTORS 10/10, zero resíduo. Mantida em proposals/ como evidência de
-- validação (harnesses não são promovidos para database/schema/).
-- ================================================================
