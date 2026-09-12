/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6130 - Resolucao editorial de Card Primary Species para
               me01-086 (ME1 "Mega Absol ex") — defeito de dado na TCGdex
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO — EVIDENCIA HISTORICA DE STAGING
               (a copia canonica promovida vive em database/migrations/
                6130_editorial_resolve_card_primary_species_me01_086.sql;
                o corpo executavel e o mesmo, so os cabecalhos diferem)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Executado...: 2026-09-12, Caminho B (SQL Editor com request.jwt.claims).
               Responsavel: fe316458-49dd-44e1-aac0-f4b7604ef8f2.
               Guards P1/P2/P3/P3b/P4-P9 e asserts A1/A1b/A2-A10 passaram;
               COMMIT efetivado. Caminho A (Secao 3) nao foi utilizado.
Mandato.....: PRIMARY-SPECIES-ME-SOURCING-01 — BACKFILL-GATE-A-REVISION-01
               (autoria) / 6130-FINAL-HARDENING-01 (P3b, A1b, A9, A10) /
               6130-EDITORIAL-RESOLUTION-01 (execucao) /
               DOCUMENTATION-CLOSEOUT-01 (promocao)
Depende de..: Query 6129 executada (esta Card e a unica das 752 ME* que a
               6129 deliberadamente NAO resolve)

RESOLUCAO, NAO CORRECAO DE LINHA. Nao existe linha anterior em
card_primary_species para esta Card. A 6114 fara INSERT e registrara
CARD_PRIMARY_SPECIES_RESOLVED em catalog_admin_action_log — nao ha UPDATE,
nao ha sobrescrita, nao ha decisao anterior sendo revogada. O que se corrige
e o DADO DA FONTE, nao um registro do Mimikyu.

-------------------------------------------------------------------------------
O FATO
-------------------------------------------------------------------------------
A TCGdex publica, para a Card me01-086:

    name  = "Mega Absol ex"
    dexId = [351]              <- Castform

Confirmado pelas DUAS vias da fonte, que concordam entre si, em 2026-09-12:

    GraphQL /v2/graphql  cards(filters:{id:"me01-08"})   -> 351
    Detalhe /v2/en/cards/me01-086                        -> 351
        category Pokemon, localId 086, rarity "Double rare", suffix "ex",
        types ["Darkness"], stage Basic, hp 280, illustrator "aky CG Works"
    (/v2/pt-br/cards/me01-086 -> HTTP 404; a fonte nao publica pt-BR aqui.)

Nao ha divergencia entre caminhos a arbitrar. Ha um DEFEITO DE DADO NA FONTE:
o dexId publicado contradiz o nome publicado pela propria fonte.

-------------------------------------------------------------------------------
POR QUE ISTO NAO E AMBIGUIDADE
-------------------------------------------------------------------------------
O fato de dominio esta determinado, nao incerto:

    Card         = Mega Absol ex
    Species      = Absol
    National Dex = 359

Corroboracao, toda ela da propria fonte e do proprio catalogo:
1. o nome publicado pela TCGdex para esta Card e "Mega Absol ex";
2. o nome no Mimikyu (seed 840, checklist oficial PT-BR) e "Mega Absol ex" —
   duas origens independentes concordam no nome;
3. o perfil da Card na fonte (types ["Darkness"], hp 280, suffix "ex",
   stage Basic) e IDENTICO ao de me01-161, tambem "Mega Absol ex", cujo
   dexId a propria TCGdex publica como 359;
4. Castform (351) e tipo Normal, nao possui forma Mega e nao possui carta ex
   neste Card Set.

Esta Card NAO e caso para a futura UI editorial de ambiguidade — aquela fica
reservada as Cards em que a Species realmente nao puder ser determinada com
seguranca (hoje, as 119 ambiguidades historicas: Tag Team GX, LEGEND,
Buried Fossil e afins).

-------------------------------------------------------------------------------
POR QUE NAO INJETAR 359 NO PAYLOAD DA 6115
-------------------------------------------------------------------------------
A 6115 grava resolution_basis = AUTOMATIC_DEXID, e o CHECK
chk_card_primary_species_automatic_evidence_shape (Query 6112 v1.1) obriga
source_evidence a conter "source": "TCGDEX", "tcgdex_dex_ids" e
"resolved_dex_id". Enviar 359 produziria uma linha AUTOMATIC_DEXID afirmando
que a TCGdex observou 359 para me01-086 — uma AFIRMACAO FALSA, gravada como
evidencia duravel, que ainda por cima apagaria o registro do erro da fonte.

Regra do projeto, explicita: nao falsificar o payload da 6115.

A decisao entra pelo que ela e — humana — via
admin_resolve_card_primary_species() (Query 6114), que grava
resolution_basis = EDITORIAL_RECONCILIATION e resolved_by_user_id = auth.uid(),
com source_evidence de forma livre (a CHECK de forma so vale para
AUTOMATIC_DEXID). E nesse source_evidence que a distincao fica PRESERVADA:

    observed_dex_id      = 351   -> DADO OBSERVADO DA FONTE
    resolved_national_dex = 359  -> DECISAO EDITORIAL CORRETIVA

-------------------------------------------------------------------------------
CONTRATO OBRIGATORIO DE source_evidence
-------------------------------------------------------------------------------
{
  "reason":                "SOURCE_DATA_ERROR",
  "provider":              "TCGDEX",
  "external_card_id":      "me01-086",
  "observed_name":         "Mega Absol ex",
  "observed_dex_id":       351,
  "resolved_species":      "Absol",
  "resolved_national_dex": 359,
  ... campos complementares de rastreabilidade (observed_at, observed_via,
      corroboration, mandate, not_an_ambiguity) ...
}

Os sete primeiros campos sao obrigatorios e sao verificados pelas assercoes
A4-A6 abaixo e pela Query 6842, Secao 3.

-------------------------------------------------------------------------------
RESTRICAO DE EXECUCAO — LEIA ANTES DE RODAR
-------------------------------------------------------------------------------
Esta Query NAO pode ser executada como `postgres` anonimo no SQL Editor, e a
razao e estrutural, nao operacional:

- 6114 exige public.is_admin(), que e
  EXISTS (SELECT 1 FROM public.admin_user WHERE id = auth.uid());
- 6114 grava resolved_by_user_id = auth.uid();
- chk_card_primary_species_basis_resolver_coupling (Query 6112) EXIGE
  resolved_by_user_id IS NOT NULL quando resolution_basis =
  EDITORIAL_RECONCILIATION.

Sem sessao autenticada, auth.uid() e NULL: a 6114 falha no guard de admin e,
se passasse, a CHECK rejeitaria a linha. Isso e desenho correto — uma decisao
editorial precisa ter um responsavel nomeado.

DOIS CAMINHOS VALIDOS:

  CAMINHO A (preferido) — chamada RPC autenticada, a partir de sessao de
  administrador real (app Next.js ou cliente supabase-js). auth.uid() vem da
  sessao; nada e declarado manualmente. Parametros na Secao 3.

  CAMINHO B — SQL Editor com request.jwt.claims declarado (Secao 4). O
  operador PRECISA preencher c_admin_user_id com o id do administrador REAL
  responsavel pela decisao, identificado pelo preflight da Secao 2. NAO
  escolher automaticamente qualquer admin_user; NAO usar usuario temporario
  ou de terceiro. resolved_by_user_id e o registro de quem decidiu.

Em ambos: NAO usar service_role. NAO fazer INSERT/UPDATE direto em
card_primary_species — apenas a 6114.

-------------------------------------------------------------------------------
O QUE ESTA QUERY DELIBERADAMENTE NAO FAZ
-------------------------------------------------------------------------------
- nao faz INSERT/UPDATE/DELETE direto em card_primary_species;
- nao altera 6112, 6113, 6114, 6115, 6116 nem 6128;
- nao cria tabela (nem temporaria), funcao, indice ou view;
- nao reescreve a evidencia congelada da 6129 — o par me01-086 -> 351
  permanece la COMO OBSERVADO; apagar o erro seria perder a prova;
- nao toca em nenhuma outra Card;
- nao toca nas 8 Cards SVP nem nas 119 ambiguidades historicas;
- nao abre a UI editorial.
===============================================================================
*/


-- =============================================================================
-- SECAO 1 — PRE-CHECK DA CARD (read-only)
-- =============================================================================
SELECT
    c.id                        AS card_id,
    cs.code                     AS card_set,
    c.collector_number          AS numero,
    c.name                      AS nome_no_mimikyu,
    r.external_card_id          AS external_card_id,
    r.metadata->>'name'         AS nome_no_snapshot_tcgdex,
    cps.card_id IS NOT NULL     AS ja_resolvida,
    sp.id                       AS species_absol_id,
    sp.national_dex_number      AS species_absol_dex,
    sp.canonical_name           AS species_absol_nome
FROM public.card c
JOIN public.card_set cs               ON cs.id = c.card_set_id
JOIN public.card_category cc          ON cc.id = c.category_id
JOIN public.card_external_reference r ON r.card_id = c.id AND r.is_active
LEFT JOIN public.card_primary_species cps ON cps.card_id = c.id
CROSS JOIN LATERAL (
    SELECT id, national_dex_number, canonical_name
    FROM public.pokemon_species
    WHERE national_dex_number = 359 AND is_active
) sp
WHERE r.external_card_id = 'me01-086'
  AND cc.code = 'POKEMON';

-- Esperado: exatamente 1 linha · card_set = ME1 · nome_no_mimikyu =
-- "Mega Absol ex" · ja_resolvida = false · species_absol_nome = "Absol".
-- Se ja_resolvida = true: PARAR. A Card ja tem decisao; esta Query nao
-- sobrescreve nada.


-- =============================================================================
-- SECAO 2 — PREFLIGHT DE IDENTIDADE DO ADMINISTRADOR (read-only)
-- =============================================================================
-- Objetivo: permitir que o responsavel se identifique, sem expor dado
-- desnecessario. O e-mail sai MASCARADO — dois primeiros caracteres e
-- dominio. Nenhuma outra informacao pessoal e lida.
--
-- REGRA: mesmo que exista um unico administrador, a escolha NAO e
-- automatica. Fabrício confirma explicitamente qual id usar antes da Secao 4.

SELECT count(*) AS total_administradores FROM public.admin_user;

SELECT
    au.id                                                        AS admin_user_id,
    left(u.email, 2) || '***@' || split_part(u.email, '@', 2)    AS email_mascarado,
    au.id = auth.uid()                                           AS e_a_sessao_atual
FROM public.admin_user au
JOIN auth.users u ON u.id = au.id
ORDER BY email_mascarado;

-- Copiar o `admin_user_id` do responsavel pela decisao e colar em
-- c_admin_user_id, na Secao 4. Nao usar o id de outra pessoa.


-- =============================================================================
-- SECAO 3 — CAMINHO A (preferido): chamada RPC de sessao autenticada
-- =============================================================================
/*
Com o cliente supabase-js autenticado como o administrador responsavel:

    const { data, error } = await supabase.rpc(
      'admin_resolve_card_primary_species',
      {
        p_card_id: '<card_id da Secao 1>',
        p_pokemon_species_id: '<species_absol_id da Secao 1>',
        p_source_evidence: {
          reason: 'SOURCE_DATA_ERROR',
          provider: 'TCGDEX',
          external_card_id: 'me01-086',
          observed_name: 'Mega Absol ex',
          observed_dex_id: 351,
          resolved_species: 'Absol',
          resolved_national_dex: 359,
          observed_at: '2026-09-12',
          observed_via: ['/v2/graphql', '/v2/en/cards/me01-086'],
          source_error:
            'dexId 351 (Castform) contradiz o name publicado pela propria '
            + 'fonte para esta Card (Mega Absol ex).',
          corroboration: [
            'nome publicado pela TCGdex = Mega Absol ex',
            'nome no Mimikyu (seed 840, checklist oficial PT-BR) = Mega Absol ex',
            'perfil identico ao de me01-161 (Mega Absol ex, dexId 359): '
              + 'types Darkness, hp 280, suffix ex, stage Basic',
            'Castform (351) e tipo Normal, sem forma Mega e sem carta ex neste Set'
          ],
          mandate: 'PRIMARY-SPECIES-ME-SOURCING-01 / CORRECAO DE DECISAO me01-086',
          not_an_ambiguity: true
        }
      }
    );

Conferir no retorno:
    resolution_basis     = 'EDITORIAL_RECONCILIATION'
    pokemon_species_id   = species_absol_id
    resolved_by_user_id  = id do administrador autenticado (NAO NULL)
Depois, rodar a Secao 5 e a Query 6842 Secao 3.
*/


-- =============================================================================
-- SECAO 4 — CAMINHO B: SQL Editor com identidade declarada
-- =============================================================================
-- PREENCHER c_admin_user_id com o id obtido e CONFIRMADO na Secao 2.
-- Sem isso o bloco aborta em P1 — por desenho.

BEGIN;

DO $editorial$
DECLARE
    -- Identidade confirmada explicitamente pelo responsavel em
    -- 6130-ADMIN-IDENTITY-BINDING-01 (2026-09-12).
    c_admin_user_id CONSTANT UUID := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2'::uuid;

    c_external_id   CONSTANT TEXT := 'me01-086';
    c_observed_name CONSTANT TEXT := 'Mega Absol ex';
    c_observed_dex  CONSTANT INT  := 351;   -- Castform — DADO OBSERVADO
    c_resolved_name CONSTANT TEXT := 'Absol';
    c_resolved_dex  CONSTANT INT  := 359;   -- DECISAO EDITORIAL
    c_esperado_apos CONSTANT INT  := 17409; -- 17408 (pos-6129) + 1

    v_card_id    UUID;
    v_species_id UUID;
    v_total      INT;
    v_row        public.card_primary_species;
    v_evidencia  JSONB;
BEGIN
    -- P1 — identidade declarada.
    IF c_admin_user_id IS NULL THEN
        RAISE EXCEPTION 'P1 FALHOU: c_admin_user_id nao preenchido. Uma decisao '
                        'editorial precisa de um responsavel nomeado. ABORTADO.';
    END IF;

    -- P2 — o id declarado e realmente um administrador.
    IF NOT EXISTS (SELECT 1 FROM public.admin_user WHERE id = c_admin_user_id) THEN
        RAISE EXCEPTION 'P2 FALHOU: % nao consta em public.admin_user.', c_admin_user_id;
    END IF;

    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', c_admin_user_id)::text, true);

    -- P3 — a sessao declarada satisfaz o guard da 6114.
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'P3 FALHOU: is_admin() falso apos set_config. ABORTADO.';
    END IF;

    -- P3b — IDENTIDADE EXATA (6130-FINAL-HARDENING-01). Complementar a P3, nao
    --       redundante: is_admin() prova AUTORIZACAO (o uid pertence a
    --       admin_user); P3b prova IDENTIDADE (o uid e exatamente o declarado).
    --       IS DISTINCT FROM falha tambem quando auth.uid() e NULL.
    IF auth.uid() IS DISTINCT FROM c_admin_user_id THEN
        RAISE EXCEPTION 'P3b FALHOU: auth.uid() = %, esperado %. A sessao nao '
                        'corresponde a identidade declarada. ABORTADO.',
            auth.uid(), c_admin_user_id;
    END IF;

    -- P4 — a Card e unica, POKEMON, ativa.
    SELECT c.id INTO v_card_id
    FROM public.card c
    JOIN public.card_category cc          ON cc.id = c.category_id
    JOIN public.card_external_reference r ON r.card_id = c.id AND r.is_active
    WHERE r.external_card_id = c_external_id
      AND cc.code = 'POKEMON'
      AND c.is_active;

    IF v_card_id IS NULL THEN
        RAISE EXCEPTION 'P4 FALHOU: Card % nao encontrada, inativa ou nao POKEMON.',
            c_external_id;
    END IF;

    -- P5 — NAO existe linha anterior. Esta Query resolve, nunca sobrescreve.
    IF EXISTS (SELECT 1 FROM public.card_primary_species WHERE card_id = v_card_id) THEN
        RAISE EXCEPTION 'P5 FALHOU: % ja possui card_primary_species. Esta Query e '
                        'uma RESOLUCAO, nao uma sobrescrita. ABORTADO.', c_external_id;
    END IF;

    -- P6 — o nome no Mimikyu continua sendo o que sustenta a decisao.
    IF NOT EXISTS (SELECT 1 FROM public.card
                   WHERE id = v_card_id AND name = c_observed_name) THEN
        RAISE EXCEPTION 'P6 FALHOU: o nome de % mudou no Mimikyu. A premissa da '
                        'decisao nao vale mais. ABORTADO.', c_external_id;
    END IF;

    -- P7 — Species Absol existe, ativa, e corresponde ao dex decidido.
    SELECT id INTO v_species_id
    FROM public.pokemon_species
    WHERE national_dex_number = c_resolved_dex AND is_active;

    IF v_species_id IS NULL THEN
        RAISE EXCEPTION 'P7 FALHOU: nenhuma pokemon_species ativa com national_dex_number %.',
            c_resolved_dex;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.pokemon_species
                   WHERE id = v_species_id AND canonical_name = c_resolved_name) THEN
        RAISE EXCEPTION 'P8 FALHOU: national_dex_number % nao corresponde a %.',
            c_resolved_dex, c_resolved_name;
    END IF;

    -- P9 — o dex observado e o decidido sao necessariamente distintos; se
    --      forem iguais, a fonte foi corrigida e este artefato perdeu objeto.
    IF c_observed_dex = c_resolved_dex THEN
        RAISE EXCEPTION 'P9 FALHOU: observed_dex_id = resolved_national_dex. '
                        'Nao ha erro de fonte a registrar. ABORTADO.';
    END IF;

    -- Evidencia editorial: preserva o ERRO DA FONTE ao lado da DECISAO.
    v_evidencia := jsonb_build_object(
        'reason',                'SOURCE_DATA_ERROR',
        'provider',              'TCGDEX',
        'external_card_id',      c_external_id,
        'observed_name',         c_observed_name,
        'observed_dex_id',       c_observed_dex,
        'resolved_species',      c_resolved_name,
        'resolved_national_dex', c_resolved_dex,
        'observed_at',           '2026-09-12',
        'observed_via',          jsonb_build_array('/v2/graphql',
                                                   '/v2/en/cards/me01-086'),
        'source_error',          'dexId 351 (Castform) contradiz o name publicado '
                              || 'pela propria fonte para esta Card (Mega Absol ex).',
        'corroboration',         jsonb_build_array(
            'nome publicado pela TCGdex = Mega Absol ex',
            'nome no Mimikyu (seed 840, checklist oficial PT-BR) = Mega Absol ex',
            'perfil identico ao de me01-161 (Mega Absol ex, dexId 359): types '
                || 'Darkness, hp 280, suffix ex, stage Basic',
            'Castform (351) e tipo Normal, sem forma Mega e sem carta ex neste Set'
        ),
        'mandate',               'PRIMARY-SPECIES-ME-SOURCING-01 / '
                              || 'CORRECAO DE DECISAO me01-086',
        'not_an_ambiguity',      true
    );

    -- ESCRITA — exclusivamente via a funcao governada. Nenhum INSERT direto.
    SELECT * INTO v_row
    FROM public.admin_resolve_card_primary_species(
        v_card_id, v_species_id, v_evidencia
    );

    -- A1 — basis editorial.
    IF v_row.resolution_basis <> 'EDITORIAL_RECONCILIATION' THEN
        RAISE EXCEPTION 'A1 FALHOU: resolution_basis = %, esperado EDITORIAL_RECONCILIATION. ROLLBACK.',
            v_row.resolution_basis;
    END IF;

    -- A1b — CARD_ID DO RETORNO (6130-FINAL-HARDENING-01, fecha L1). A linha
    --        devolvida pela 6114 tem de ser a da Card resolvida em P4, nao
    --        outra qualquer.
    IF v_row.card_id IS DISTINCT FROM v_card_id THEN
        RAISE EXCEPTION 'A1b FALHOU: card_id do retorno = %, esperado %. ROLLBACK.',
            v_row.card_id, v_card_id;
    END IF;

    -- A2 — Species correta.
    IF v_row.pokemon_species_id <> v_species_id THEN
        RAISE EXCEPTION 'A2 FALHOU: Species gravada diverge de %. ROLLBACK.', c_resolved_name;
    END IF;

    -- A3 — responsavel nomeado.
    IF v_row.resolved_by_user_id IS DISTINCT FROM c_admin_user_id THEN
        RAISE EXCEPTION 'A3 FALHOU: resolved_by_user_id = %, esperado %. ROLLBACK.',
            v_row.resolved_by_user_id, c_admin_user_id;
    END IF;

    -- A4 — contrato obrigatorio de source_evidence presente e correto.
    IF  v_row.source_evidence ->> 'reason'   IS DISTINCT FROM 'SOURCE_DATA_ERROR'
     OR v_row.source_evidence ->> 'provider' IS DISTINCT FROM 'TCGDEX'
     OR v_row.source_evidence ->> 'external_card_id' IS DISTINCT FROM c_external_id
     OR v_row.source_evidence ->> 'observed_name'    IS DISTINCT FROM c_observed_name
     OR v_row.source_evidence ->> 'resolved_species' IS DISTINCT FROM c_resolved_name
    THEN
        RAISE EXCEPTION 'A4 FALHOU: contrato de source_evidence incompleto. ROLLBACK.';
    END IF;

    -- A5 — o dado OBSERVADO (351) ficou preservado.
    IF (v_row.source_evidence ->> 'observed_dex_id')::int IS DISTINCT FROM c_observed_dex THEN
        RAISE EXCEPTION 'A5 FALHOU: observed_dex_id nao preservado (esperado %). ROLLBACK.',
            c_observed_dex;
    END IF;

    -- A6 — a DECISAO (359) ficou registrada e distinta do observado.
    IF (v_row.source_evidence ->> 'resolved_national_dex')::int IS DISTINCT FROM c_resolved_dex THEN
        RAISE EXCEPTION 'A6 FALHOU: resolved_national_dex nao registrado (esperado %). ROLLBACK.',
            c_resolved_dex;
    END IF;

    -- A7 — a evidencia NAO pode se passar por automatica.
    IF v_row.source_evidence ? 'tcgdex_dex_ids'
    OR v_row.source_evidence ? 'resolved_dex_id' THEN
        RAISE EXCEPTION 'A7 FALHOU: source_evidence contem campos de evidencia '
                        'AUTOMATIC_DEXID. ROLLBACK.';
    END IF;

    -- A8 — total global.
    SELECT count(*) INTO v_total FROM public.card_primary_species;
    IF v_total <> c_esperado_apos THEN
        RAISE EXCEPTION 'A8 FALHOU: card_primary_species = %, esperado % '
                        '(a 6129 foi executada antes?). ROLLBACK.',
            v_total, c_esperado_apos;
    END IF;

    -- A9 — EXATAMENTE 1 EDITORIAL_RECONCILIATION nos seis Card Sets ME*
    --      (6130-FINAL-HARDENING-01, fecha L2, parte 1). Antes desta Query o
    --      contador era 0 (Gate A, assert A2 do 6842); depois tem de ser 1.
    SELECT count(*) INTO v_total
    FROM public.card_primary_species cps
    JOIN public.card c           ON c.id  = cps.card_id
    JOIN public.card_set cs      ON cs.id = c.card_set_id
    JOIN public.card_category cc ON cc.id = c.category_id
    WHERE cc.code = 'POKEMON'
      AND cs.code IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')
      AND cps.resolution_basis = 'EDITORIAL_RECONCILIATION';
    IF v_total <> 1 THEN
        RAISE EXCEPTION 'A9 FALHOU: % linhas EDITORIAL_RECONCILIATION nos Sets ME*, '
                        'esperado 1. ROLLBACK.', v_total;
    END IF;

    -- A10 — e essa unica linha editorial e a propria me01-086, apontando para
    --       Absol / National Dex 359 (fecha L2, parte 2). Nao basta haver UMA:
    --       tem de ser ESTA.
    SELECT count(*) INTO v_total
    FROM public.card_primary_species cps
    JOIN public.card c                    ON c.id  = cps.card_id
    JOIN public.card_set cs               ON cs.id = c.card_set_id
    JOIN public.card_category cc          ON cc.id = c.category_id
    JOIN public.pokemon_species sp        ON sp.id = cps.pokemon_species_id
    JOIN public.card_external_reference r ON r.card_id = cps.card_id AND r.is_active
    WHERE cc.code = 'POKEMON'
      AND cs.code IN ('ME1','ME2','ME2.5','ME3','ME4','MEP')
      AND cps.resolution_basis = 'EDITORIAL_RECONCILIATION'
      AND r.external_card_id     = c_external_id
      AND sp.canonical_name      = c_resolved_name
      AND sp.national_dex_number = c_resolved_dex
      AND cps.card_id            = v_card_id;
    IF v_total < 1 THEN
        RAISE EXCEPTION 'A10 FALHOU: a unica linha EDITORIAL_RECONCILIATION nos Sets ME* '
                        'nao e % -> % / %. ROLLBACK.',
            c_external_id, c_resolved_name, c_resolved_dex;
    END IF;

    RAISE NOTICE 'RESOLUCAO 6130 OK: % -> % (%), EDITORIAL_RECONCILIATION, '
                 'responsavel %, dado observado da fonte (%) preservado.',
        c_external_id, c_resolved_name, c_resolved_dex, c_admin_user_id, c_observed_dex;
END;
$editorial$;

COMMIT;


-- =============================================================================
-- SECAO 5 — POS-CHECK (read-only), valido para qualquer um dos dois caminhos
-- =============================================================================
SELECT
    r.external_card_id,
    c.name                                       AS card,
    sp.canonical_name                            AS species,
    sp.national_dex_number                       AS national_dex,
    cps.resolution_basis,
    cps.resolved_by_user_id IS NOT NULL          AS tem_responsavel,
    cps.source_evidence ->> 'reason'             AS reason,
    cps.source_evidence ->> 'provider'           AS provider,
    (cps.source_evidence ->> 'observed_dex_id')::int       AS observado_da_fonte,
    (cps.source_evidence ->> 'resolved_national_dex')::int AS decidido_editorialmente,
    NOT (cps.source_evidence ? 'tcgdex_dex_ids') AS nao_se_passa_por_automatica
FROM public.card_primary_species cps
JOIN public.card c                    ON c.id = cps.card_id
JOIN public.card_external_reference r ON r.card_id = cps.card_id AND r.is_active
JOIN public.pokemon_species sp        ON sp.id = cps.pokemon_species_id
WHERE r.external_card_id = 'me01-086';

-- Esperado: 1 linha — card "Mega Absol ex" · species "Absol" · national_dex 359
-- · EDITORIAL_RECONCILIATION · tem_responsavel true · reason SOURCE_DATA_ERROR
-- · provider TCGDEX · observado_da_fonte 351 · decidido_editorialmente 359
-- · nao_se_passa_por_automatica true.
