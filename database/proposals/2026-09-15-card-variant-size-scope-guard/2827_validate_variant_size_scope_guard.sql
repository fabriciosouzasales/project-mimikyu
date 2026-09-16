/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2827 - Validate Variant Size Scope Guard
Versão......: 1.1.1
Status......: CONFIRMADO EXECUTADO — 29 PASS / 0 FAIL (2026-09-16)
              Fechamento documental: DOCUMENTATION-CLOSEOUT-01 (2026-09-16).
              Zero resíduo comprovado por postcheck independente.
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-15
Mandato.....: CARD-VARIANTS — JUMBO INCIDENT /
              SIZE-SCOPE-SERVER-GUARD-HARNESS-CORRECTION-01
Valida......: Query 2198 - Guard Variant Size Scope in Residual Signature

-------------------------------------------------------------------------------
>>> HISTÓRICO DE EXECUÇÃO <<<
-------------------------------------------------------------------------------
v1.0 — executada UMA vez em 2026-09-16 contra o LIVE (2198 já aplicada).
       Resultado: GATE_2827_FAILED — 15 PASS / 5 FAIL / 20 registros.
       ZERO RESÍDUO comprovado por postcheck independente.
       As 5 falhas foram TODAS de fixture/ambiente do harness; NENHUMA
       falha do guard 2198 (CT1–CT6 passaram integralmente).

       D1  Seções 2 e 4 abortaram com VARIANT_IMPORT_SCOPE_MISMATCH:
           o harness inventava `external_set_id` sintético, mas
           internal.variant_type_mapping_decision (Query 2192) trata
           divergência declarada contra card_set_external_reference ATIVA
           como fail-closed.
       D2  F1 chamava uma RPC PÚBLICA guardada por is_admin() — que o
           próprio cabeçalho desta v1.0 já declarava inalcançável neste
           canal. Contradição interna do harness.
       D3  F2 escolhia o primeiro trait ativo (FIRST_EDITION), cuja
           assinatura singleton JÁ tem Perfil — colidia com
           CREATE_CARD_PRINTING_PROFILE_DUPLICATE_SIGNATURE.
       D4  O aborto de uma seção revertia junto os vereditos já gravados
           na TEMP table pela mesma subtransação, apagando evidência.
       D5  I falhou por dependência (I_VT/I_PR nunca registraram).

v1.1 — correções D1..D5 + D6 aplicadas. Ver ">>> CORREÇÕES DA v1.1 <<<".

v1.1 RUN-02 — executada UMA vez em 2026-09-16 (pre-flight PASS em 4/4).
       Resultado: GATE_2827_FAILED — 27 PASS / 2 FAIL / 29 registros.
       ZERO RESÍDUO comprovado por postcheck independente.

       PASSARAM (27): CT1–CT6, A, A_ZW, B, C, D, E_CONTRATO, I_VT,
       S2_ZERO_RESIDUO, F1_CONTRATO, F2, I_PR, S3_ZERO_RESIDUO, G, I,
       S4_ZERO_RESIDUO, J, REG1–REG5.
       Ou seja: as correções C1 (escopo canônico), C2 (F1_CONTRATO),
       C3 (composição livre) e C4 (buffer de vereditos) funcionaram —
       G foi reportado mesmo com a seção abortando depois, e H apareceu
       como AUSENTE em vez de sumir.

       D7  Único defeito material: Seção 4 abortou com
           [23505] duplicate key value violates unique constraint
           "uq_cvir_job_card_type_no_printing".
           G e H usavam o MESMO job_id, o MESMO card_id e o MESMO
           variant_type_id, ambos sem Printing Profile. O índice é
           INVARIANTE CORRETO do staging; o defeito é da fixture.
           Consequência: H AUSENTE, S4_ABORT e S2_ABORT_OK em FAIL.
           A v1.0 nunca chegou a esse ponto (abortava antes, no
           SCOPE_MISMATCH), por isso D7 só apareceu agora.

v1.1.1 — correção C6 (D7). NÃO EXECUTADA. Nenhum outro caso alterado.

-------------------------------------------------------------------------------
>>> CORREÇÕES DA v1.1 <<<
-------------------------------------------------------------------------------
C1 (D1) — ESCOPO CANÔNICO DAS FIXTURES.
   A Seção 0.2 passa a exigir, do candidato, uma
   card_set_external_reference ATIVA da fonte TCGDEX, e usa
   EXATAMENTE aquele external_set_id em TODAS as fixtures de job
   (Seções 2, 3A, 3B e 4). Nenhum valor é inventado, nenhum sufixo é
   concatenado. O valor escolhido é ainda CONFRONTADO contra
   internal.resolve_variant_mapping_scope() — a mesma autoridade que o
   writer consulta —, e divergência aborta. Candidato sem referência
   ativa é PULADO (o JOIN o elimina); ausência total de candidato é
   ABORT em voz alta. O filtro de job ativo continua excluindo
   RECEIVED, PROCESSING, STAGED e CONFIRMING — condição que também
   garante que inserir UM job ativo não viola
   uq_catalog_variant_import_job_fingerprint_active.
   Reutilizar o mesmo par (Card Set, referência) entre seções é seguro
   porque cada seção reverte por sentinela ANTES da seguinte começar.

C2 (D2) — F1 DEIXA DE FINGIR E2E.
   O caso F1 foi RENOMEADO para F1_CONTRATO e redesenhado. Ele prova
   apenas o que este canal alcança legitimamente:
     (a) o motor devolve BLOCKED_SIZE_UNSUPPORTED para a linha;
     (b) esse estado está FORA do par-whitelist
         ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE') — o MESMO
         predicado que a Query 2181 usa para classificar em outcome C;
     (c) a definição LIVE da RPC de Printing realmente contém esse
         predicado e o ramo ->'C' (evidência dirigida, não genérica);
     (d) a linha permanece NEEDS_REVIEW/PENDING e sem variant_type_id;
     (e) zero write.
   NÃO é E2E da RPC pública e o detalhe do caso diz isso literalmente.
   O E2E autenticado da RPC pública de Printing será feito SEPARADO,
   com a sessão real do administrador no navegador, DEPOIS de 2827
   PASS. Nada de JWT fabricado, request.jwt.claims, SET ROLE,
   service_role manual, admin temporário ou bypass de RLS.

C3 (D3) — COMPOSIÇÃO LIVRE PARA F2.
   A fixture de F2 procura, de forma determinística e no MENOR tamanho
   possível (singletons por id, depois pares por (id,id) com b.id >
   a.id — portanto já distinta e ordenada ascendente, como o contrato
   canônico exige), uma composição de traits ATIVOS cuja
   traits_signature NÃO exista em card_printing_profile para o mesmo
   Game. Nenhum Perfil existente é alterado ou inativado; nenhum
   conflito é fabricado. Sem composição livre -> FAIL HIGH / ABORT.

C4 (D4) — VEREDITOS SOBREVIVEM AO ABORTO.
   Vereditos produzidos DENTRO de uma subtransação passam a ser
   acumulados num array PL/pgSQL (pg_temp._rec2827) — memória, não
   estado transacional — e só são gravados na TEMP table pelo
   pg_temp._flush2827 DEPOIS que a subtransação termina. Assim o
   aborto reverte as fixtures mas NÃO apaga a prova já produzida, e o
   relatório identifica o primeiro contrato quebrado sem destruir os
   anteriores. É a menor mudança que resolve D4: nenhuma subtransação
   adicional foi criada, e os casos que dependem de fixture comum
   (A -> B -> C -> I_VT -> E) continuam na mesma subtransação, como o
   contrato exige.
   Casos que realmente não rodaram continuam AUSENTES e o gate
   continua fail-closed sobre eles.

C5 (D5) — CASO I.
   I continua sendo derivado de I_VT e I_PR (sem hardcode). O detalhe
   agora imprime os vereditos REAIS de ambos, inclusive quando
   ausentes, para não descrever sucesso ao falhar.

-------------------------------------------------------------------------------
>>> CORREÇÃO DA v1.1.1 <<<
-------------------------------------------------------------------------------
C6 (D7) — G E H EM SUBTRANSAÇÕES SEPARADAS (Seção 4).

   AUDITORIA DE PROPAGAÇÃO, feita ANTES de escolher a correção
   (Query 2193 -> universo da Query 2192):

       WHERE j.source = <fonte> AND e.game_id = <game>
         AND (GLOBAL, ou source-set casando)
         AND sg.printing_state IN ('RESOLVED_NO_PRINTING',
                                   'RESOLVED_WITH_PROFILE')
         AND sg.residual_type/foil/subtype/stamp = os do mapping

   Três fatos que essa leitura estabelece:
     1. o universo NÃO é escopado por job — um mapping alcança
        qualquer linha do mesmo Game+Fonte cuja RESIDUAL case,
        inclusive em outros jobs;
     2. `size` NÃO participa do filtro (é estado, não identidade),
        exatamente como a 2198 determinou;
     3. o que hoje separa H de G é só o token de stamp
        (HARNESS-REG-TOK vs HARNESS-REG-TOK2) — ou seja, um
        ARGUMENTO, não uma garantia estrutural.

   Por isso a opção escolhida foi (A) e não (B): trocar o card_id
   resolveria a colisão do índice e deixaria a independência de H
   apoiada no fato 3. Com (A), H roda em subtransação própria criada
   DEPOIS do rollback integral de G: quando H executa, o mapping de G
   não existe mais. Independência estrutural.

   Além disso H deixou de ser uma asserção única e passou a provar,
   diretamente:
     (i)   compute_variant_residual_signature devolve
           RESOLVED_NO_PRINTING para size=standard — o motor NÃO o
           bloqueia por tamanho;
     (ii)  a linha chega ao apply ainda NEEDS_REVIEW — prova positiva
           de que não herdou resolução de ninguém;
     (iii) após o mapping PRÓPRIO, resolve para VALID.

   Nenhum mecanismo novo: é o mesmo padrão S3A/S3B já validado.
   Nenhum contrato de produção foi criado ou alterado.
   O índice uq_cvir_job_card_type_no_printing NÃO foi tocado — ele
   estava certo; a fixture é que estava errada.
   S4_ZERO_RESIDUO usa contagens capturadas ANTES de S4A, logo cobre
   as duas subtransações. `H` permanece no roster obrigatório: se S4B
   abortar, H fica AUSENTE e S4_ABORT é registrado — nunca silencioso.

-------------------------------------------------------------------------------
>>> ARQUITETURA — HERDADA DE 2825 v3.6 / 2826 v4.0 <<<
-------------------------------------------------------------------------------
NÃO existe BEGIN/COMMIT/ROLLBACK de topo. Provado contra o LIVE em 2026-09-13:
o canal `execute_sql` do Supabase Management API já entrega o payload dentro de
uma transação aberta; um ROLLBACK interno encerraria a transação EXTERNA e
objetos TEMP não sobrevivem entre chamadas.

O mandato pediu "harness BEGIN/ROLLBACK". A intenção — nenhum resíduo — é
cumprida integralmente; o MECANISMO é o já provado nesta casa:

    BEGIN
        <writes reais>
        <PROVAS de que os writes aconteceram>   -- nunca depois da sentinela
        RAISE EXCEPTION 'HARNESS_<CASO>_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_<CASO>_ROLLBACK' THEN <reverteu> ELSE <falhou> END IF;
    END;
    <PROVAS de que nada sobreviveu>

Divergência registrada de propósito, não silenciada.

-------------------------------------------------------------------------------
>>> O QUE ESTE HARNESS AFIRMA — E O QUE NÃO AFIRMA <<<
-------------------------------------------------------------------------------
Neste canal: current_user = postgres (não superuser), auth.uid() = NULL,
public.is_admin() = FALSE. Logo TODA RPC pública guardada por is_admin() é
INALCANÇÁVEL aqui.

Portanto:
  * o COMPORTAMENTO é provado pelas funções internal.* (SECURITY DEFINER,
    alcançáveis como postgres) — que são o motor real de todos os writers;
  * a FRONTEIRA PÚBLICA é provada estaticamente, por catálogo (casos J e
    F1_CONTRATO item (c));
  * nenhum caso declara ter executado positivamente uma RPC pública protegida.

A v1.0 violava a própria regra acima no caso F1, que chamava
public.admin_resolve_catalog_variant_import_printing_mapping — is_admin()
guarded. Corrigido em v1.1 (C2). A prova E2E dessa RPC fica para uma rodada
SEPARADA, com sessão administrativa real no navegador, após 2827 PASS.

Nada de JWT fabricado, request.jwt.claims alterado, admin temporário ou
service_role.

-------------------------------------------------------------------------------
>>> J É SUPLEMENTAR — E ISSO É EXPLÍCITO <<<
-------------------------------------------------------------------------------
O caso J é meta-integridade por catálogo (pg_get_functiondef). Ele NÃO
substitui nenhum caso comportamental: A–I provam runtime real, com writes
reais e reversão provada. J existe só para travar regressão arquitetural —
um writer NOVO que promova a VALID sem passar pelo ponto único.

-------------------------------------------------------------------------------
ROSTER — 29 CASOS OBRIGATÓRIOS

(v1.1: o roster do Gate passou a listar TODOS os casos de um run saudável;
a v1.0 checava ausência de apenas 20. Fora do roster ficam SOMENTE
S2_ABORT e S4_ABORT, que por construção só existem QUANDO há aborto fora
da sentinela — a ausência deles é o resultado desejado, e o par positivo
S2_ABORT_OK está no roster justamente para que "ausente" nunca seja
confundido com "sumiu".)
-------------------------------------------------------------------------------
Seção 1 — contrato puro da função (read-only)
  CT1  size ausente              -> comportamento atual, bit a bit
  CT2  size = 'standard'         -> comportamento atual, bit a bit
  CT3  size = 'jumbo'            -> BLOCKED_SIZE_OUT_OF_SCOPE
  CT4  size = 'oversized' (novo) -> BLOCKED_SIZE_UNSUPPORTED
  CT5  residual coerente nos dois estados bloqueados + trait/profile vazios
  CT6  normalização: 'JUMBO', ' jumbo ' e 'Jumbo' caem no mesmo ramo

Seção 2 — eixo Variant Type
  A    origem UNSUPPORTED + GLOBAL      -> bloqueia, zero write
  A_ZW zero write do caso A
  B    origem UNSUPPORTED + SOURCE_SET  -> bloqueia, zero write
  C    mapping legítimo da gêmea NÃO promove a UNSUPPORTED
  D    preview (decision) e execute (apply) concordam
  E_CONTRATO  create-type-with-mapping: fronteira pública fechada +
              prova dirigida de que ela delega ao worker e não escreve
              validation_status por conta própria; nenhum VT órfão.
              (v1.1 / D6 — a asserção da v1.0 teria dado PASS MASCARADO
              porque a RPC é is_admin()-guarded e aborta antes do guard
              de tamanho. E2E atômico fica para a rodada de navegador.)
  I_VT linha JUMBO intocada pelo eixo Variant Type
  S2_ABORT_OK / S2_ZERO_RESIDUO

Seção 3 — eixo Printing
  F1_CONTRATO  o motor devolve BLOCKED_SIZE_UNSUPPORTED, estado FORA da
               whitelist que a Query 2181 usa para classificar; a linha
               não é promovida e nada é escrito.
               NÃO é E2E da RPC pública (ver C2 acima).
  F2   create_card_printing_profile_with_backfill não promove UNSUPPORTED
       (writer internal.*, alcançável — teste comportamental real)

Seção 3 (cont.)
  I_PR linha JUMBO intocada pelo eixo Printing
  S3_ZERO_RESIDUO

Seção 4 — não-regressão comportamental
  (v1.1.1: DUAS subtransações independentes — S4A para G, S4B para H)
  G    NEEDS_REVIEW comum (sem size) continua resolvendo normalmente  [S4A]
  H    size='standard' não é bloqueado por size, não herda resolução
       de G e resolve para VALID pelo seu próprio mapping           [S4B]
  I    linha JUMBO INVALID/SKIPPED permanece intocada por todos os writers
       (derivado de I_VT + I_PR, nunca hardcoded)
  S4_ZERO_RESIDUO  (cobre S4A e S4B)

Seção 5 — meta-integridade e baseline
  J    whitelist RESOLVED_* em todos os consumidores + nenhum writer novo
  REG1 corpus continua 6340 linhas
  REG2 zero raw_data.size no baseline pré-Edge
  REG3 contadores/status dos jobs atuais inalterados
  REG4 85 mappings de VT e 89 Variant Types intocados
  REG5 card_variant intocado (7461)

-------------------------------------------------------------------------------
BASELINE MEDIDO EM 2026-09-15 (pré-2198)
-------------------------------------------------------------------------------
catalog_variant_import_row ......... 6340 linhas, 0 com chave raw_data.size
card_variant_type_external_mapping .. 85
card_variant_type .................. 89
card_variant ....................... 7461
md5(pg_get_functiondef) da 2176 LIVE  5411b79a6b8e8c8d739a1f282bc43868
===============================================================================
*/

-- =============================================================================
-- SEÇÃO 0 — INFRAESTRUTURA, PRÉ-REQUISITOS E BASELINE (somente leitura)
-- =============================================================================

CREATE TEMP TABLE _r2827 (
    caso     TEXT PRIMARY KEY,
    veredito TEXT NOT NULL,
    detalhe  TEXT
);

CREATE TEMP TABLE _ctx2827 (k TEXT PRIMARY KEY, v TEXT);

CREATE OR REPLACE FUNCTION pg_temp._chk2827(p_caso TEXT, p_ok BOOLEAN, p_detalhe TEXT)
RETURNS VOID LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO _r2827(caso, veredito, detalhe)
    VALUES (p_caso, CASE WHEN p_ok THEN 'PASS' ELSE 'FAIL' END, p_detalhe)
    ON CONFLICT (caso) DO UPDATE
       SET veredito = EXCLUDED.veredito, detalhe = EXCLUDED.detalhe;
END;
$f$;

-- ---------------------------------------------------------------------------
-- (v1.1 / C4) BUFFER DE VEREDITOS PARA DENTRO DE SUBTRANSAÇÃO.
--
-- _chk2827 grava numa TEMP table — estado TRANSACIONAL. Quando uma
-- subtransação aborta, esses INSERTs são revertidos junto com as fixtures e
-- a evidência já produzida DESAPARECE (defeito D4 da v1.0).
--
-- Variáveis PL/pgSQL não são estado transacional: sobrevivem ao aborto do
-- bloco. Portanto, DENTRO de subtransação, o veredito é serializado por
-- _rec2827 num array TEXT[] do bloco externo e só é gravado por _flush2827
-- DEPOIS que a subtransação termina — abortada ou não.
--
-- Separador: US (E'\x1f'), caractere de controle que nenhum detalhe emite.
-- p_ok NULL cai em 'FAIL' (fail-closed), mesma disciplina de _chk2827.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp._rec2827(p_caso TEXT, p_ok BOOLEAN, p_detalhe TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $g$
    SELECT p_caso || E'\x1f'
        || CASE WHEN p_ok THEN 'PASS' ELSE 'FAIL' END || E'\x1f'
        || COALESCE(p_detalhe, '');
$g$;

CREATE OR REPLACE FUNCTION pg_temp._flush2827(p_buf TEXT[])
RETURNS VOID LANGUAGE plpgsql AS $h$
DECLARE
    v_item TEXT;
BEGIN
    IF p_buf IS NULL THEN
        RETURN;
    END IF;
    FOREACH v_item IN ARRAY p_buf LOOP
        INSERT INTO _r2827(caso, veredito, detalhe)
        VALUES (split_part(v_item, E'\x1f', 1),
                split_part(v_item, E'\x1f', 2),
                split_part(v_item, E'\x1f', 3))
        ON CONFLICT (caso) DO UPDATE
           SET veredito = EXCLUDED.veredito, detalhe = EXCLUDED.detalhe;
    END LOOP;
END;
$h$;

-- ---------------------------------------------------------------------------
-- S0.1 — A 2198 PRECISA ESTAR APLICADA. Sem ela o harness inteiro é ruído:
-- todos os casos "passariam" por ausência do guard, afirmando o contrário
-- do que medem. ABORT, nunca FAIL mascarado.
-- ---------------------------------------------------------------------------
DO $s0$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_functiondef('internal.compute_variant_residual_signature(jsonb,uuid,uuid)'::regprocedure)
      INTO v_def;

    IF v_def NOT ILIKE '%BLOCKED_SIZE_OUT_OF_SCOPE%'
       OR v_def NOT ILIKE '%BLOCKED_SIZE_UNSUPPORTED%' THEN
        RAISE EXCEPTION 'S0 ABORT: Query 2198 nao aplicada — os estados BLOCKED_SIZE_* nao existem na funcao LIVE. NAO registrar nenhum caso como PASS.';
    END IF;

    IF v_def NOT ILIKE '%NEEDS_REVIEW_INVALID_PRINTING_MAPPING%' THEN
        RAISE EXCEPTION 'S0 ABORT: o marcador da v1.1 (NEEDS_REVIEW_INVALID_PRINTING_MAPPING) sumiu. A 2198 nao derivou da v1.1 canonica — regressao silenciosa do BLOCKER B-01.';
    END IF;
END;
$s0$;

-- ---------------------------------------------------------------------------
-- S0.2 — CONTEXTO: Game, Fonte, Card Set SEM job ativo, Card real e
--        external_set_id CANÔNICO.
--
-- Duas condições independentes, ambas obrigatórias:
--
--  (i) O Card Set precisa estar LIVRE de job ativo, porque as fixtures criam
--      um job STAGED e uq_catalog_variant_import_job_fingerprint_active
--      proíbe dois ativos para o mesmo (card_set_id, external_set_id). O
--      filtro exclui exatamente RECEIVED, PROCESSING, STAGED, CONFIRMING.
--
-- (ii) (v1.1 / C1) O Card Set precisa ter card_set_external_reference ATIVA
--      da fonte TCGDEX, e o job fixture tem de declarar EXATAMENTE aquele
--      external_set_id. A v1.0 inventava `harness2827-*` e era corretamente
--      barrada por VARIANT_IMPORT_SCOPE_MISMATCH: a Query 2192 trata
--      divergência declarada contra a referência canônica como fail-closed.
--      O JOIN elimina candidatos sem referência ativa — "procurar outro" é
--      a semântica natural do JOIN, não um caso especial.
--
-- O valor escolhido é confrontado contra internal.resolve_variant_mapping_scope(),
-- a MESMA autoridade que o writer consulta. Divergência -> ABORT.
--
-- Reutilizar este par (Card Set, referência) nas Seções 2, 3A, 3B e 4 é
-- seguro: cada seção reverte por sentinela ANTES da seguinte começar, então
-- nunca existem dois jobs ativos simultâneos para o mesmo fingerprint.
-- ---------------------------------------------------------------------------
DO $s0b$
DECLARE
    v_game UUID; v_src UUID; v_set UUID; v_card UUID; v_ext TEXT;
    v_canon TEXT;
BEGIN
    SELECT id INTO v_src FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_src IS NULL THEN
        RAISE EXCEPTION 'S0 ABORT: asset_source TCGDEX inexistente.';
    END IF;

    SELECT cs.id, e.game_id, c.id, r.external_set_id
      INTO v_set, v_game, v_card, v_ext
      FROM public.card_set cs
      JOIN public.expansion e ON e.id = cs.expansion_id
      JOIN public.card c ON c.card_set_id = cs.id
      JOIN public.card_set_external_reference r
        ON r.card_set_id     = cs.id
       AND r.asset_source_id = v_src
       AND r.is_active
     WHERE NOT EXISTS (
             SELECT 1 FROM public.catalog_variant_import_job j
              WHERE j.card_set_id = cs.id
                AND j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING'))
     ORDER BY cs.code, c.collector_number
     LIMIT 1;

    IF v_set IS NULL THEN
        RAISE EXCEPTION 'S0 ABORT: nenhum Card Set que satisfaca AS DUAS condicoes — (i) ter Cards e NENHUM job de variante em RECEIVED/PROCESSING/STAGED/CONFIRMING; (ii) ter card_set_external_reference ATIVA da fonte TCGDEX. Sem isso as fixtures nao podem ser criadas nem com escopo canonico nem sem violar uq_catalog_variant_import_job_fingerprint_active. NAO mascarar como PASS.';
    END IF;

    IF v_ext IS NULL OR btrim(v_ext) = '' THEN
        RAISE EXCEPTION 'S0 ABORT: a referencia ATIVA do Card Set escolhido tem external_set_id vazio. Dado de catalogo inconsistente — NAO inventar valor.';
    END IF;

    -- Confronto com a autoridade que o writer realmente consulta.
    SELECT s.external_set_id INTO v_canon
      FROM internal.resolve_variant_mapping_scope(v_set, v_src) s;

    IF v_canon IS DISTINCT FROM v_ext THEN
        RAISE EXCEPTION 'S0 ABORT: external_set_id lido da referencia (%) diverge do resolvido por internal.resolve_variant_mapping_scope (%). O harness NAO pode adivinhar qual vale.',
            v_ext, COALESCE(v_canon, 'NULL');
    END IF;

    INSERT INTO _ctx2827 VALUES
        ('game_id', v_game::TEXT),
        ('asset_source_id', v_src::TEXT),
        ('card_set_id', v_set::TEXT),
        ('card_id', v_card::TEXT),
        ('external_set_id', v_ext),
        ('external_set_id_origem', 'card_set_external_reference ATIVA (TCGDEX), confirmada por internal.resolve_variant_mapping_scope'),
        ('filtro_job_ativo', 'RECEIVED, PROCESSING, STAGED, CONFIRMING');
END;
$s0b$;

-- ---------------------------------------------------------------------------
-- S0.3 — BASELINE CONGELADO. Tudo em REG* compara contra esta foto.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE _base2827 AS
SELECT
    (SELECT count(*) FROM public.catalog_variant_import_row)                AS rows_total,
    (SELECT count(*) FROM public.catalog_variant_import_row
      WHERE raw_data ? 'size')                                              AS rows_com_size,
    (SELECT count(*) FROM public.card_variant_type_external_mapping)        AS vt_mappings,
    (SELECT count(*) FROM public.card_variant_type)                         AS vts,
    (SELECT count(*) FROM public.card_variant)                              AS card_variants,
    (SELECT count(*) FROM public.card_printing_external_mapping)            AS pr_mappings,
    (SELECT count(*) FROM public.card_printing_profile)                     AS pr_profiles,
    (SELECT md5(string_agg(j.id::TEXT || '|' || j.status || '|' ||
                           COALESCE(j.total_rows,-1)::TEXT || '|' ||
                           COALESCE(j.valid_rows,-1)::TEXT, ',' ORDER BY j.id))
       FROM public.catalog_variant_import_job j)                            AS jobs_md5;

-- =============================================================================
-- SEÇÃO 1 — CONTRATO PURO DA FUNÇÃO (read-only, sem fixtures)
-- =============================================================================
DO $s1$
DECLARE
    v_game UUID := (SELECT v::UUID FROM _ctx2827 WHERE k='game_id');
    v_src  UUID := (SELECT v::UUID FROM _ctx2827 WHERE k='asset_source_id');
    r RECORD; r2 RECORD; r3 RECORD;
    v_ok BOOLEAN;
BEGIN
    -- CT1 — size ausente: nada muda.
    SELECT * INTO r FROM internal.compute_variant_residual_signature(
        '{"type":"normal","foil":null,"subtype":null,"stamp":null}'::JSONB, v_game, v_src);
    PERFORM pg_temp._chk2827('CT1',
        r.printing_state = 'RESOLVED_NO_PRINTING' AND r.residual_type = 'NORMAL',
        format('size ausente -> state=%s residual_type=%s (esperado RESOLVED_NO_PRINTING/NORMAL)',
               r.printing_state, r.residual_type));

    -- CT2 — size = standard: nada muda.
    SELECT * INTO r FROM internal.compute_variant_residual_signature(
        '{"type":"normal","foil":null,"subtype":null,"stamp":null,"size":"standard"}'::JSONB, v_game, v_src);
    PERFORM pg_temp._chk2827('CT2',
        r.printing_state = 'RESOLVED_NO_PRINTING',
        format('size=standard -> state=%s (esperado RESOLVED_NO_PRINTING)', r.printing_state));

    -- CT3 — jumbo.
    SELECT * INTO r FROM internal.compute_variant_residual_signature(
        '{"type":"normal","foil":null,"subtype":null,"stamp":["pikachu"],"size":"jumbo"}'::JSONB, v_game, v_src);
    PERFORM pg_temp._chk2827('CT3',
        r.printing_state = 'BLOCKED_SIZE_OUT_OF_SCOPE',
        format('size=jumbo -> state=%s (esperado BLOCKED_SIZE_OUT_OF_SCOPE)', r.printing_state));

    -- CT4 — valor desconhecido: fail-closed, NUNCA fluxo normal.
    SELECT * INTO r FROM internal.compute_variant_residual_signature(
        '{"type":"normal","foil":null,"subtype":null,"stamp":null,"size":"oversized"}'::JSONB, v_game, v_src);
    PERFORM pg_temp._chk2827('CT4',
        r.printing_state = 'BLOCKED_SIZE_UNSUPPORTED',
        format('size=oversized -> state=%s (esperado BLOCKED_SIZE_UNSUPPORTED)', r.printing_state));

    -- CT5 — residual COERENTE e sem efeito de Printing nos dois bloqueios.
    SELECT * INTO r FROM internal.compute_variant_residual_signature(
        '{"type":"holo","foil":"cosmos","subtype":null,"stamp":["set-logo","staff"],"size":"jumbo"}'::JSONB, v_game, v_src);
    v_ok := r.residual_type = 'HOLO'
        AND r.residual_foil = 'COSMOS'
        AND r.residual_subtype IS NULL
        AND r.residual_stamp = ARRAY['SET-LOGO','STAFF']::TEXT[]
        AND cardinality(COALESCE(r.trait_ids,'{}')) = 0
        AND r.printing_profile_id IS NULL;
    PERFORM pg_temp._chk2827('CT5', v_ok,
        format('residual no bloqueio: type=%s foil=%s subtype=%s stamp=%s traits=%s profile=%s (size fora da assinatura, traits/profile vazios)',
               r.residual_type, r.residual_foil, COALESCE(r.residual_subtype,'NULL'),
               r.residual_stamp::TEXT, cardinality(COALESCE(r.trait_ids,'{}')),
               COALESCE(r.printing_profile_id::TEXT,'NULL')));

    -- CT6 — normalização: caixa e espaços caem no MESMO ramo.
    SELECT * INTO r  FROM internal.compute_variant_residual_signature(
        '{"type":"normal","size":"JUMBO"}'::JSONB, v_game, v_src);
    SELECT * INTO r2 FROM internal.compute_variant_residual_signature(
        '{"type":"normal","size":"  jumbo  "}'::JSONB, v_game, v_src);
    SELECT * INTO r3 FROM internal.compute_variant_residual_signature(
        '{"type":"normal","size":"Jumbo"}'::JSONB, v_game, v_src);
    PERFORM pg_temp._chk2827('CT6',
        r.printing_state = 'BLOCKED_SIZE_OUT_OF_SCOPE'
        AND r2.printing_state = 'BLOCKED_SIZE_OUT_OF_SCOPE'
        AND r3.printing_state = 'BLOCKED_SIZE_OUT_OF_SCOPE',
        format('JUMBO=%s | "  jumbo  "=%s | Jumbo=%s (os tres devem bloquear — comparacao pos-normalizacao)',
               r.printing_state, r2.printing_state, r3.printing_state));
END;
$s1$;

-- =============================================================================
-- SEÇÃO 2 — EIXO VARIANT TYPE (fixtures reais, revertidas por sentinela)
--
-- Fixture comum: um job STAGED + TRES linhas para o MESMO card:
--   L_UNS   type=normal, stamp=[harness-tok], size=oversized  (UNSUPPORTED)
--   L_TWIN  type=normal, stamp=[harness-tok]                  (gêmea, sem size)
--   L_JUMBO type=normal, stamp=[harness-tok], size=jumbo, INVALID/SKIPPED
--
-- L_UNS e L_TWIN têm assinatura residual IDÊNTICA — é exatamente essa
-- identidade que torna o risco 2 real.
-- =============================================================================
DO $s2$
DECLARE
    v_game UUID := (SELECT v::UUID FROM _ctx2827 WHERE k='game_id');
    v_src  UUID := (SELECT v::UUID FROM _ctx2827 WHERE k='asset_source_id');
    v_set  UUID := (SELECT v::UUID FROM _ctx2827 WHERE k='card_set_id');
    v_card UUID := (SELECT v::UUID FROM _ctx2827 WHERE k='card_id');
    -- (v1.1 / C1) external_set_id CANÔNICO, vindo da referência ATIVA.
    v_ext  TEXT := (SELECT v FROM _ctx2827 WHERE k='external_set_id');

    v_job UUID; v_uns UUID; v_twin UUID; v_jumbo UUID;
    v_vt UUID; v_actor UUID;
    v_maps_antes INTEGER; v_vts_antes INTEGER;
    v_jobs_antes INTEGER; v_rows_antes INTEGER;
    v_dec RECORD;
    v_sqlstate TEXT; v_msg TEXT;
    v_uns_status TEXT; v_twin_status TEXT; v_jumbo_status TEXT; v_jumbo_dec TEXT;
    v_det TEXT;
    v_sig RECORD; v_def2158 TEXT; v_def2150 TEXT;
    -- (v1.1 / C4) vereditos produzidos DENTRO da subtransação.
    v_buf TEXT[] := '{}';
BEGIN
    SELECT id INTO v_actor FROM public.admin_user LIMIT 1;
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'S2 ABORT: nenhum administrador em public.admin_user. apply_variant_type_mapping exige p_actor_id admin — o contrato NAO pode ser provado nesta base.';
    END IF;

    SELECT id INTO v_vt FROM public.card_variant_type
     WHERE game_id = v_game AND is_active ORDER BY display_order LIMIT 1;
    IF v_vt IS NULL THEN
        RAISE EXCEPTION 'S2 ABORT: nenhum Card Variant Type ativo para o Game.';
    END IF;

    SELECT count(*) INTO v_maps_antes FROM public.card_variant_type_external_mapping;
    SELECT count(*) INTO v_vts_antes  FROM public.card_variant_type;
    -- (v1.1 / C1) Zero resíduo passa a ser provado por CONTAGEM, não por
    -- external_set_id: agora o valor é canônico e pode legitimamente já
    -- existir em jobs COMPLETED/CANCELLED do mesmo Card Set. Contar é a
    -- prova correta; procurar pelo external_set_id daria falso FAIL.
    SELECT count(*) INTO v_jobs_antes FROM public.catalog_variant_import_job;
    SELECT count(*) INTO v_rows_antes FROM public.catalog_variant_import_row;

    BEGIN
        -- ---------------- FIXTURES ----------------
        INSERT INTO public.catalog_variant_import_job
            (card_set_id, source, external_set_id, status)
        VALUES (v_set, 'TCGDEX', v_ext, 'STAGED')
        RETURNING id INTO v_job;

        INSERT INTO public.catalog_variant_import_row
            (job_id, card_id, raw_data, normalized_data,
             validation_status, match_status, decision_status, persistence_status)
        VALUES
            (v_job, v_card,
             '{"type":"normal","foil":null,"subtype":null,"stamp":["harness-tok"],"size":"oversized"}'::JSONB,
             '{"review_reason":"UNSUPPORTED_SIZE_VALUE","size":"OVERSIZED"}'::JSONB,
             'NEEDS_REVIEW','NEW','PENDING','PENDING')
        RETURNING id INTO v_uns;

        INSERT INTO public.catalog_variant_import_row
            (job_id, card_id, raw_data, normalized_data,
             validation_status, match_status, decision_status, persistence_status)
        VALUES
            (v_job, v_card,
             '{"type":"normal","foil":null,"subtype":null,"stamp":["harness-tok"]}'::JSONB,
             '{}'::JSONB,
             'NEEDS_REVIEW','NEW','PENDING','PENDING')
        RETURNING id INTO v_twin;

        INSERT INTO public.catalog_variant_import_row
            (job_id, card_id, raw_data, normalized_data,
             validation_status, match_status, decision_status, persistence_status)
        VALUES
            (v_job, v_card,
             '{"type":"normal","foil":null,"subtype":null,"stamp":["harness-tok"],"size":"jumbo"}'::JSONB,
             '{"skip_reason":"SIZE_OUT_OF_SCOPE","size":"JUMBO"}'::JSONB,
             'INVALID','NEW','SKIPPED','PENDING')
        RETURNING id INTO v_jumbo;

        -- ---------------- CASO A: origem UNSUPPORTED + GLOBAL ----------------
        SELECT * INTO v_dec
          FROM internal.variant_type_mapping_decision(v_uns, v_vt, 'GLOBAL');

        v_buf := v_buf || pg_temp._rec2827('A',
            v_dec.ok = FALSE AND v_dec.block_reason IS NOT NULL
            AND v_dec.block_reason <> 'SCOPE_MISMATCH',
            format('decision GLOBAL sobre origem UNSUPPORTED: ok=%s block_reason=%s block_detail=%s (esperado ok=false por motivo de TAMANHO; SCOPE_MISMATCH aqui seria defeito de fixture, nao prova do guard)',
                   v_dec.ok, COALESCE(v_dec.block_reason,'NULL'), COALESCE(v_dec.block_detail,'NULL')));

        -- ---------------- CASO D (metade 1): preview concorda ----------------
        v_det := format('preview ok=%s reason=%s', v_dec.ok, COALESCE(v_dec.block_reason,'NULL'));

        -- execute deve levantar excecao, e NAO escrever nada
        BEGIN
            PERFORM internal.apply_variant_type_mapping(v_actor, v_uns, v_vt, 'GLOBAL');
            v_buf := v_buf || pg_temp._rec2827('D', FALSE,
                v_det || ' | execute NAO levantou excecao — preview e execute DIVERGEM.');
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            v_buf := v_buf || pg_temp._rec2827('D',
                v_dec.ok = FALSE AND v_msg NOT LIKE 'VARIANT_IMPORT_SCOPE_MISMATCH%',
                v_det || format(' | execute levantou: %s — preview e execute CONCORDAM na recusa. (SCOPE_MISMATCH aqui reprova: seria defeito de fixture, nao o guard de tamanho.)', left(v_msg, 180)));
        END;

        -- zero write: nenhum mapping novo
        v_buf := v_buf || pg_temp._rec2827('A_ZW',
            (SELECT count(*) FROM public.card_variant_type_external_mapping) = v_maps_antes,
            format('mappings antes=%s depois=%s (GLOBAL bloqueado nao pode ter escrito)',
                   v_maps_antes, (SELECT count(*) FROM public.card_variant_type_external_mapping)));

        -- ---------------- CASO B: origem UNSUPPORTED + SOURCE_SET ----------------
        SELECT * INTO v_dec
          FROM internal.variant_type_mapping_decision(v_uns, v_vt, 'SOURCE_SET');

        BEGIN
            PERFORM internal.apply_variant_type_mapping(v_actor, v_uns, v_vt, 'SOURCE_SET');
            v_buf := v_buf || pg_temp._rec2827('B', FALSE,
                'SOURCE_SET NAO bloqueou origem UNSUPPORTED — bypass de escopo.');
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            v_buf := v_buf || pg_temp._rec2827('B',
                v_dec.ok = FALSE
                AND v_dec.block_reason IS DISTINCT FROM 'SCOPE_MISMATCH'
                AND v_msg NOT LIKE 'VARIANT_IMPORT_SCOPE_MISMATCH%'
                AND (SELECT count(*) FROM public.card_variant_type_external_mapping) = v_maps_antes,
                format('decision SOURCE_SET ok=%s reason=%s | execute: %s | mappings=%s (esperado ok=false por TAMANHO, excecao, mappings inalterados; SCOPE_MISMATCH reprova)',
                       v_dec.ok, COALESCE(v_dec.block_reason,'NULL'), left(v_msg,140),
                       (SELECT count(*) FROM public.card_variant_type_external_mapping)));
        END;

        -- ---------------- CASO C: mapping legitimo da GEMEA ----------------
        -- A gemea NAO tem size -> e origem valida. O mapping criado por ela
        -- tem assinatura residual IDENTICA a da UNSUPPORTED.
        PERFORM internal.apply_variant_type_mapping(v_actor, v_twin, v_vt, 'GLOBAL');

        SELECT validation_status INTO v_twin_status
          FROM public.catalog_variant_import_row WHERE id = v_twin;
        SELECT validation_status INTO v_uns_status
          FROM public.catalog_variant_import_row WHERE id = v_uns;

        v_buf := v_buf || pg_temp._rec2827('C',
            v_twin_status = 'VALID' AND v_uns_status = 'NEEDS_REVIEW',
            format('gemea=%s (esperado VALID — propagacao legitima aconteceu) | UNSUPPORTED=%s (esperado NEEDS_REVIEW — NAO capturada apesar da assinatura residual identica)',
                   v_twin_status, v_uns_status));

        -- ---------------- CASO I: JUMBO intocado pelo eixo VT ----------------
        SELECT validation_status, decision_status INTO v_jumbo_status, v_jumbo_dec
          FROM public.catalog_variant_import_row WHERE id = v_jumbo;
        v_buf := v_buf || pg_temp._rec2827('I_VT',
            v_jumbo_status = 'INVALID' AND v_jumbo_dec = 'SKIPPED',
            format('linha JUMBO apos propagacao VT: validation=%s decision=%s (esperado INVALID/SKIPPED)',
                   v_jumbo_status, v_jumbo_dec));

        -- ================================================================
        -- CASO E_CONTRATO — (v1.1 / D6) ACHADO NOVO DESTA CORREÇÃO
        -- ----------------------------------------------------------------
        -- public.admin_create_card_variant_type_with_import_mapping É
        -- is_admin()-guarded (Query 2158, linha 94). Neste canal ela SEMPRE
        -- aborta em FORBIDDEN, ANTES de qualquer lógica de tamanho.
        --
        -- A asserção da v1.0 era "abortou E nenhum VT orfao sobreviveu" —
        -- e isso seria satisfeito pelo aborto de AUTORIZAÇÃO. Ou seja: a
        -- v1.0 teria produzido um PASS MASCARADO se a Secao 2 tivesse
        -- chegado ate aqui. Mesma classe de defeito do D2; descoberto ao
        -- implementar C2 e corrigido aqui em vez de silenciado.
        --
        -- O que este caso prova agora, sem fingir E2E:
        --  (a) a fronteira publica esta FECHADA neste canal (FORBIDDEN);
        --  (b) 2158 NAO escreve validation_status por conta propria: ela
        --      delega a public.admin_resolve_catalog_variant_import_mapping,
        --      que delega ao worker internal.apply_variant_type_mapping —
        --      o MESMO worker que os casos A/B/D acabaram de provar que
        --      levanta excecao para esta linha. Logo o aborto do worker
        --      aborta a RPC inteira, e o VT criado antes nao sobrevive.
        --  (c) nenhum VT orfao HARNESS_2827_ORPHAN existe.
        --
        -- O E2E ATOMICO de verdade (admin real criando o tipo pela UI) fica
        -- para a rodada autenticada no navegador, junto com F1_CONTRATO.
        -- ================================================================
        SELECT pg_get_functiondef(p.oid) INTO v_def2158
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE p.prokind = 'f' AND n.nspname = 'public'
           AND p.proname = 'admin_create_card_variant_type_with_import_mapping'
         LIMIT 1;

        SELECT pg_get_functiondef(p.oid) INTO v_def2150
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE p.prokind = 'f' AND n.nspname = 'public'
           AND p.proname = 'admin_resolve_catalog_variant_import_mapping'
         LIMIT 1;

        BEGIN
            PERFORM public.admin_create_card_variant_type_with_import_mapping(
                v_uns, 'HARNESS_2827_ORPHAN', 'Harness 2827 Orphan', NULL, 9827);
            v_buf := v_buf || pg_temp._rec2827('E_CONTRATO', FALSE,
                'create-type-with-mapping NAO abortou. Neste canal is_admin() e FALSE, entao ela deveria ter recusado por FORBIDDEN — fronteira publica aberta e um achado grave.');
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            v_buf := v_buf || pg_temp._rec2827('E_CONTRATO',
                    v_msg LIKE 'ADMIN_CREATE_CARD_VARIANT_TYPE_WITH_IMPORT_MAPPING_FORBIDDEN%'
                AND v_def2158 IS NOT NULL
                AND v_def2158 ILIKE '%admin_resolve_catalog_variant_import_mapping%'
                AND v_def2158 NOT ILIKE '%validation_status%'
                AND v_def2150 IS NOT NULL
                AND v_def2150 ILIKE '%apply_variant_type_mapping%'
                AND NOT EXISTS (SELECT 1 FROM public.card_variant_type
                                 WHERE code = 'HARNESS_2827_ORPHAN'),
                format('NAO e E2E da RPC publica: neste canal ela recusa por autorizacao. (a) erro=%s; (b) 2158 delega a admin_resolve_catalog_variant_import_mapping=%s e NAO escreve validation_status=%s; 2150 delega ao worker apply_variant_type_mapping=%s — o mesmo worker que A/B/D provaram recusar esta linha; (c) VT orfao HARNESS_2827_ORPHAN ausente=%s. E2E atomico autenticado fica para a rodada de navegador.',
                       left(v_msg,90),
                       (v_def2158 ILIKE '%admin_resolve_catalog_variant_import_mapping%'),
                       (v_def2158 NOT ILIKE '%validation_status%'),
                       (v_def2150 ILIKE '%apply_variant_type_mapping%'),
                       NOT EXISTS (SELECT 1 FROM public.card_variant_type
                                    WHERE code = 'HARNESS_2827_ORPHAN')));
        END;

        RAISE EXCEPTION 'HARNESS_S2_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        IF v_msg <> 'HARNESS_S2_ROLLBACK' THEN
            v_buf := v_buf || pg_temp._rec2827('S2_ABORT', FALSE,
                format('Secao 2 abortou fora da sentinela: [%s] %s', v_sqlstate, v_msg));
        END IF;
    END;

    -- (v1.1 / C4) A subtransacao acabou. AGORA os vereditos sao gravados:
    -- eles viveram num array PL/pgSQL e por isso sobreviveram ao aborto.
    PERFORM pg_temp._flush2827(v_buf);

    -- zero residuo da Secao 2 — por CONTAGEM (v1.1 / C1)
    PERFORM pg_temp._chk2827('S2_ZERO_RESIDUO',
        (SELECT count(*) FROM public.catalog_variant_import_job) = v_jobs_antes
        AND (SELECT count(*) FROM public.catalog_variant_import_row) = v_rows_antes
        AND NOT EXISTS (SELECT 1 FROM public.card_variant_type
                         WHERE code = 'HARNESS_2827_ORPHAN')
        AND (SELECT count(*) FROM public.card_variant_type_external_mapping) = v_maps_antes
        AND (SELECT count(*) FROM public.card_variant_type) = v_vts_antes,
        format('jobs %s->%s | rows %s->%s | mappings %s->%s | VTs %s->%s | VT orfao ausente=%s (nada da Secao 2 sobreviveu a sentinela)',
               v_jobs_antes, (SELECT count(*) FROM public.catalog_variant_import_job),
               v_rows_antes, (SELECT count(*) FROM public.catalog_variant_import_row),
               v_maps_antes, (SELECT count(*) FROM public.card_variant_type_external_mapping),
               v_vts_antes,  (SELECT count(*) FROM public.card_variant_type),
               NOT EXISTS (SELECT 1 FROM public.card_variant_type
                            WHERE code = 'HARNESS_2827_ORPHAN')));
END;
$s2$;

-- =============================================================================
-- SEÇÃO 3 — EIXO PRINTING
--
-- Os DOIS writers de Printing promovem a VALID por conta propria. Ambos
-- classificam por printing_state; com os estados BLOCKED_SIZE_* a linha cai
-- em outcome 'C' e permanece NEEDS_REVIEW.
-- =============================================================================
DO $s3$
DECLARE
    v_game UUID := (SELECT v::UUID FROM _ctx2827 WHERE k='game_id');
    v_src  UUID := (SELECT v::UUID FROM _ctx2827 WHERE k='asset_source_id');
    v_set  UUID := (SELECT v::UUID FROM _ctx2827 WHERE k='card_set_id');
    v_card UUID := (SELECT v::UUID FROM _ctx2827 WHERE k='card_id');
    -- (v1.1 / C1) external_set_id CANÔNICO. Sem sufixo: 3A reverte por
    -- sentinela ANTES de 3B começar, logo nunca há dois jobs ativos.
    v_ext  TEXT := (SELECT v FROM _ctx2827 WHERE k='external_set_id');

    v_job UUID; v_uns UUID; v_jumbo UUID;
    v_actor UUID; v_trait UUID;
    v_sqlstate TEXT; v_msg TEXT;
    v_st TEXT; v_dec TEXT; v_nd JSONB;
    v_pr_maps_antes INTEGER; v_pr_prof_antes INTEGER;
    v_jobs_antes INTEGER; v_rows_antes INTEGER;
    v_sig RECORD; v_def2181 TEXT;
    v_comp UUID[]; v_comp_sz INTEGER;
    v_buf TEXT[] := '{}';
BEGIN
    SELECT id INTO v_actor FROM public.admin_user LIMIT 1;
    SELECT id INTO v_trait FROM public.card_printing_trait
     WHERE game_id = v_game AND is_active ORDER BY id LIMIT 1;

    IF v_actor IS NULL OR v_trait IS NULL THEN
        PERFORM pg_temp._chk2827('F1_CONTRATO', FALSE,
            'FALHA HIGH: sem admin_user ou sem card_printing_trait ativo — o eixo Printing NAO pode ser provado. Nao mascarar como PASS.');
        PERFORM pg_temp._chk2827('F2', FALSE,
            'FALHA HIGH: mesma causa de F1_CONTRATO.');
        RETURN;
    END IF;

    -- ================================================================
    -- (v1.1 / C3) COMPOSIÇÃO LIVRE PARA F2.
    -- Determinística, MENOR tamanho primeiro, distinta e ordenada
    -- ascendente (o par usa b.id > a.id, então já sai ordenado — mesma
    -- disciplina do contrato canônico de traits_signature).
    -- Nenhum Perfil existente é lido para alteração, nem inativado.
    -- ================================================================
    SELECT ARRAY[t.id] INTO v_comp
      FROM public.card_printing_trait t
     WHERE t.game_id = v_game AND t.is_active
       AND NOT EXISTS (SELECT 1 FROM public.card_printing_profile pp
                        WHERE pp.game_id = v_game
                          AND pp.traits_signature = ARRAY[t.id])
     ORDER BY t.id
     LIMIT 1;

    IF v_comp IS NULL THEN
        SELECT ARRAY[a.id, b.id] INTO v_comp
          FROM public.card_printing_trait a
          JOIN public.card_printing_trait b
            ON b.game_id = a.game_id AND b.is_active AND b.id > a.id
         WHERE a.game_id = v_game AND a.is_active
           AND NOT EXISTS (SELECT 1 FROM public.card_printing_profile pp
                            WHERE pp.game_id = v_game
                              AND pp.traits_signature = ARRAY[a.id, b.id])
         ORDER BY a.id, b.id
         LIMIT 1;
    END IF;

    IF v_comp IS NULL THEN
        PERFORM pg_temp._chk2827('F2', FALSE,
            'FALHA HIGH: nenhuma composicao LIVRE de traits ativos (tamanho 1 ou 2) sem Perfil correspondente neste Game. F2 exige criar um Perfil NOVO; fabricar conflito ou reaproveitar/inativar Perfil existente seria adulterar o teste. Nao mascarar como PASS.');
    END IF;

    v_comp_sz := cardinality(COALESCE(v_comp, '{}'::UUID[]));

    SELECT count(*) INTO v_pr_maps_antes FROM public.card_printing_external_mapping;
    SELECT count(*) INTO v_pr_prof_antes FROM public.card_printing_profile;
    SELECT count(*) INTO v_jobs_antes FROM public.catalog_variant_import_job;
    SELECT count(*) INTO v_rows_antes FROM public.catalog_variant_import_row;

    BEGIN
        INSERT INTO public.catalog_variant_import_job
            (card_set_id, source, external_set_id, status)
        VALUES (v_set, 'TCGDEX', v_ext, 'STAGED')
        RETURNING id INTO v_job;

        -- O token 'harness-pr-tok' esta no STAMP da linha: e exatamente o
        -- gatilho do universo `touched` dos dois writers de Printing.
        INSERT INTO public.catalog_variant_import_row
            (job_id, card_id, raw_data, normalized_data,
             validation_status, match_status, decision_status, persistence_status)
        VALUES
            (v_job, v_card,
             '{"type":"normal","foil":null,"subtype":null,"stamp":["harness-pr-tok"],"size":"oversized"}'::JSONB,
             '{"review_reason":"UNSUPPORTED_SIZE_VALUE","size":"OVERSIZED"}'::JSONB,
             'NEEDS_REVIEW','NEW','PENDING','PENDING')
        RETURNING id INTO v_uns;

        INSERT INTO public.catalog_variant_import_row
            (job_id, card_id, raw_data, normalized_data,
             validation_status, match_status, decision_status, persistence_status)
        VALUES
            (v_job, v_card,
             '{"type":"normal","foil":null,"subtype":null,"stamp":["harness-pr-tok"],"size":"jumbo"}'::JSONB,
             '{"skip_reason":"SIZE_OUT_OF_SCOPE","size":"JUMBO"}'::JSONB,
             'INVALID','NEW','SKIPPED','PENDING')
        RETURNING id INTO v_jumbo;

        -- ================================================================
        -- F1_CONTRATO — (v1.1 / C2) PROVA DO MOTOR, NÃO E2E DA RPC PÚBLICA
        -- ----------------------------------------------------------------
        -- A v1.0 chamava aqui
        -- public.admin_resolve_catalog_variant_import_printing_mapping,
        -- que é is_admin()-guarded (Query 2181, linha 312). Neste canal
        -- auth.uid() é NULL e is_admin() é FALSE: a chamada só podia
        -- devolver FORBIDDEN. Era uma contradição com o próprio cabeçalho
        -- deste harness. Nada de JWT fabricado, request.jwt.claims,
        -- SET ROLE, service_role manual, admin temporário ou bypass de RLS
        -- para "resolver" isso — a RPC simplesmente NÃO é testável aqui.
        --
        -- Prova-se então, e apenas, o que este canal alcança de fato:
        --  (a) o motor devolve BLOCKED_SIZE_UNSUPPORTED para esta linha;
        --  (b) esse estado esta FORA do par-whitelist;
        --  (c) a definicao LIVE da 2181 realmente classifica por esse
        --      predicado e manda o que esta fora dele para o outcome 'C';
        --  (d) a linha segue NEEDS_REVIEW/PENDING e sem variant_type_id;
        --  (e) zero write no eixo Printing.
        -- ================================================================
        SELECT * INTO v_sig
          FROM internal.compute_variant_residual_signature(
                   (SELECT raw_data FROM public.catalog_variant_import_row
                     WHERE id = v_uns),
                   v_game, v_src);

        SELECT pg_get_functiondef(p.oid) INTO v_def2181
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE p.prokind = 'f' AND n.nspname = 'public'
           AND p.proname = 'admin_resolve_catalog_variant_import_printing_mapping'
         LIMIT 1;

        SELECT validation_status, decision_status, normalized_data
          INTO v_st, v_dec, v_nd
          FROM public.catalog_variant_import_row WHERE id = v_uns;

        v_buf := v_buf || pg_temp._rec2827('F1_CONTRATO',
                v_sig.printing_state = 'BLOCKED_SIZE_UNSUPPORTED'
            AND v_sig.printing_state NOT IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE')
            AND cardinality(COALESCE(v_sig.trait_ids,'{}')) = 0
            AND v_sig.printing_profile_id IS NULL
            AND v_def2181 IS NOT NULL
            AND v_def2181 ILIKE '%RESOLVED_NO_PRINTING%'
            AND v_def2181 ILIKE '%RESOLVED_WITH_PROFILE%'
            AND v_def2181 ~* 'printing_state[[:space:]]+NOT[[:space:]]+IN'
            AND v_st = 'NEEDS_REVIEW'
            AND v_dec = 'PENDING'
            AND NOT (v_nd ? 'variant_type_id')
            AND (SELECT count(*) FROM public.card_printing_external_mapping) = v_pr_maps_antes,
            format('PROVA DE MOTOR/CONTRATO — NAO e E2E da RPC publica (is_admin() e FALSE neste canal; E2E autenticado fica para a rodada de navegador). (a) state=%s; (b) fora da whitelist=%s; traits=%s profile=%s; (c) 2181 LIVE classifica por NOT IN da whitelist=%s; (d) linha validation=%s decision=%s variant_type_id_presente=%s; (e) printing mappings %s->%s',
                   v_sig.printing_state,
                   (v_sig.printing_state NOT IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE')),
                   cardinality(COALESCE(v_sig.trait_ids,'{}')),
                   COALESCE(v_sig.printing_profile_id::TEXT,'NULL'),
                   (v_def2181 ~* 'printing_state[[:space:]]+NOT[[:space:]]+IN'),
                   v_st, v_dec, (v_nd ? 'variant_type_id'),
                   v_pr_maps_antes,
                   (SELECT count(*) FROM public.card_printing_external_mapping)));

        -- JUMBO tambem intocado pelo eixo Printing
        SELECT validation_status, decision_status INTO v_st, v_dec
          FROM public.catalog_variant_import_row WHERE id = v_jumbo;
        v_buf := v_buf || pg_temp._rec2827('I_PR',
            v_st = 'INVALID' AND v_dec = 'SKIPPED',
            format('linha JUMBO no eixo Printing: validation=%s decision=%s (esperado INVALID/SKIPPED)', v_st, v_dec));

        RAISE EXCEPTION 'HARNESS_S3A_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        IF v_msg <> 'HARNESS_S3A_ROLLBACK' THEN
            v_buf := v_buf || pg_temp._rec2827('F1_CONTRATO', FALSE,
                format('Secao 3A abortou fora da sentinela: [%s] %s', v_sqlstate, v_msg));
        END IF;
    END;

    PERFORM pg_temp._flush2827(v_buf);
    v_buf := '{}';

    -- ---------------- F2: create profile + backfill ----------------
    -- Writer internal.* — alcançável, então este continua sendo teste
    -- COMPORTAMENTAL real, com escrita real revertida por sentinela.
    IF v_comp IS NOT NULL THEN
    BEGIN
        INSERT INTO public.catalog_variant_import_job
            (card_set_id, source, external_set_id, status)
        VALUES (v_set, 'TCGDEX', v_ext, 'STAGED')
        RETURNING id INTO v_job;

        INSERT INTO public.catalog_variant_import_row
            (job_id, card_id, raw_data, normalized_data,
             validation_status, match_status, decision_status, persistence_status)
        VALUES
            (v_job, v_card,
             '{"type":"normal","foil":null,"subtype":null,"stamp":["harness-pr-tok"],"size":"oversized"}'::JSONB,
             '{"review_reason":"UNSUPPORTED_SIZE_VALUE","size":"OVERSIZED"}'::JSONB,
             'NEEDS_REVIEW','NEW','PENDING','PENDING')
        RETURNING id INTO v_uns;

        PERFORM internal.create_card_printing_profile_with_backfill(
            v_actor, 'HARNESS_2827_PROFILE', 'Harness 2827 Profile', NULL, 9827, v_comp);

        SELECT validation_status, decision_status, normalized_data
          INTO v_st, v_dec, v_nd
          FROM public.catalog_variant_import_row WHERE id = v_uns;

        v_buf := v_buf || pg_temp._rec2827('F2',
            v_st = 'NEEDS_REVIEW'
            AND v_dec = 'PENDING'
            AND NOT (v_nd ? 'variant_type_id'),
            format('composicao LIVRE de tamanho %s escolhida deterministicamente (nenhum Perfil existente tocado); apos create profile + backfill: validation=%s decision=%s variant_type_id_presente=%s (esperado NEEDS_REVIEW/PENDING/false)',
                   v_comp_sz, v_st, v_dec, (v_nd ? 'variant_type_id')));

        RAISE EXCEPTION 'HARNESS_S3B_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        IF v_msg <> 'HARNESS_S3B_ROLLBACK' THEN
            v_buf := v_buf || pg_temp._rec2827('F2', FALSE,
                format('Secao 3B abortou fora da sentinela: [%s] %s', v_sqlstate, v_msg));
        END IF;
    END;
    END IF;

    PERFORM pg_temp._flush2827(v_buf);

    -- zero residuo da Secao 3 — por CONTAGEM (v1.1 / C1)
    PERFORM pg_temp._chk2827('S3_ZERO_RESIDUO',
        (SELECT count(*) FROM public.card_printing_external_mapping) = v_pr_maps_antes
        AND (SELECT count(*) FROM public.card_printing_profile) = v_pr_prof_antes
        AND (SELECT count(*) FROM public.catalog_variant_import_job) = v_jobs_antes
        AND (SELECT count(*) FROM public.catalog_variant_import_row) = v_rows_antes
        AND NOT EXISTS (SELECT 1 FROM public.card_printing_profile
                         WHERE code = 'HARNESS_2827_PROFILE'),
        format('printing mappings %s->%s | profiles %s->%s | jobs %s->%s | rows %s->%s | Perfil HARNESS_2827_PROFILE ausente=%s',
               v_pr_maps_antes, (SELECT count(*) FROM public.card_printing_external_mapping),
               v_pr_prof_antes, (SELECT count(*) FROM public.card_printing_profile),
               v_jobs_antes, (SELECT count(*) FROM public.catalog_variant_import_job),
               v_rows_antes, (SELECT count(*) FROM public.catalog_variant_import_row),
               NOT EXISTS (SELECT 1 FROM public.card_printing_profile
                            WHERE code = 'HARNESS_2827_PROFILE')));
END;
$s3$;

-- =============================================================================
-- SEÇÃO 4 — NÃO-REGRESSÃO COMPORTAMENTAL
-- =============================================================================
DO $s4$
DECLARE
    v_game UUID := (SELECT v::UUID FROM _ctx2827 WHERE k='game_id');
    v_src  UUID := (SELECT v::UUID FROM _ctx2827 WHERE k='asset_source_id');
    v_set  UUID := (SELECT v::UUID FROM _ctx2827 WHERE k='card_set_id');
    v_card UUID := (SELECT v::UUID FROM _ctx2827 WHERE k='card_id');
    -- (v1.1 / C1) external_set_id CANÔNICO, sem sufixo.
    v_ext  TEXT := (SELECT v FROM _ctx2827 WHERE k='external_set_id');
    v_job UUID; v_plain UUID; v_std UUID;
    v_vt UUID; v_actor UUID;
    v_sqlstate TEXT; v_msg TEXT;
    v_a TEXT; v_b TEXT;
    v_jobs_antes INTEGER; v_rows_antes INTEGER;
    v_i_vt TEXT; v_i_pr TEXT;
    v_sig RECORD; v_h_antes TEXT;
    v_buf TEXT[] := '{}';
BEGIN
    SELECT id INTO v_actor FROM public.admin_user LIMIT 1;
    SELECT id INTO v_vt FROM public.card_variant_type
     WHERE game_id = v_game AND is_active ORDER BY display_order LIMIT 1;

    SELECT count(*) INTO v_jobs_antes FROM public.catalog_variant_import_job;
    SELECT count(*) INTO v_rows_antes FROM public.catalog_variant_import_row;

    -- ================================================================
    -- (v1.1.1 / C6 / D7) G e H EM SUBTRANSAÇÕES SEPARADAS.
    -- ----------------------------------------------------------------
    -- A v1.1 punha G e H no MESMO job, no MESMO card, mapeando AMBOS
    -- para o MESMO Variant Type sem Printing. Isso viola — corretamente —
    -- o índice
    --   uq_cvir_job_card_type_no_printing
    --     (job_id, card_id, (normalized_data->>'variant_type_id'))
    --     WHERE variant_type_id IS NOT NULL
    --       AND jsonb_typeof(printing_profile_id) = 'null'
    -- que é INVARIANTE LEGÍTIMO do staging. O harness estava errado, o
    -- índice não. Nada de schema foi tocado.
    --
    -- Trocar apenas o card_id resolveria a colisão e deixaria a
    -- INDEPENDÊNCIA de H apoiada num argumento frágil (tokens de stamp
    -- diferentes). A propagação de internal.apply_variant_type_mapping
    -- (Query 2193 -> universo da Query 2192) NÃO é escopada por job:
    --
    --   WHERE j.source = <fonte> AND e.game_id = <game>
    --     AND (escopo GLOBAL OU source-set casando)
    --     AND sg.printing_state IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE')
    --     AND sg.residual_type/foil/subtype/stamp = os do mapping
    --
    -- ou seja, alcança QUALQUER linha do mesmo Game+Fonte cuja assinatura
    -- RESIDUAL case — inclusive em outros jobs. `size` não aparece nesse
    -- filtro (ele é estado, não identidade), então a única coisa que hoje
    -- separa H de G é o token de stamp. Isso é argumento, não estrutura.
    --
    -- Correção adotada: H roda em subtransação PRÓPRIA, criada DEPOIS que
    -- a fixture de G foi integralmente revertida pela sentinela. Quando H
    -- executa, o mapping de G NÃO EXISTE MAIS — a independência passa a
    -- ser estrutural, não argumentativa. Mesmo mecanismo já usado e
    -- validado em S3A/S3B; nenhum mecanismo novo foi criado.
    --
    -- H ainda prova, por asserção direta e não por dedução:
    --   (i)  o motor NÃO bloqueia size=standard (RESOLVED_NO_PRINTING);
    --   (ii) a linha chega ao apply ainda NEEDS_REVIEW — não foi
    --        pré-resolvida por efeito colateral de ninguém;
    --   (iii) depois do mapping ela resolve para VALID.
    -- ================================================================

    -- ---------------- S4A: caso G ----------------
    BEGIN
        INSERT INTO public.catalog_variant_import_job
            (card_set_id, source, external_set_id, status)
        VALUES (v_set, 'TCGDEX', v_ext, 'STAGED')
        RETURNING id INTO v_job;

        -- G: NEEDS_REVIEW comum, sem size
        INSERT INTO public.catalog_variant_import_row
            (job_id, card_id, raw_data, normalized_data,
             validation_status, match_status, decision_status, persistence_status)
        VALUES
            (v_job, v_card,
             '{"type":"normal","foil":null,"subtype":null,"stamp":["harness-reg-tok"]}'::JSONB,
             '{}'::JSONB, 'NEEDS_REVIEW','NEW','PENDING','PENDING')
        RETURNING id INTO v_plain;

        PERFORM internal.apply_variant_type_mapping(v_actor, v_plain, v_vt, 'GLOBAL');
        SELECT validation_status INTO v_a FROM public.catalog_variant_import_row WHERE id = v_plain;
        v_buf := v_buf || pg_temp._rec2827('G', v_a = 'VALID',
            format('NEEDS_REVIEW comum sem size apos mapping: %s (esperado VALID — zero regressao). Fixture isolada em subtransacao propria (S4A).', v_a));

        RAISE EXCEPTION 'HARNESS_S4A_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        IF v_msg <> 'HARNESS_S4A_ROLLBACK' THEN
            v_buf := v_buf || pg_temp._rec2827('S4_ABORT', FALSE,
                format('Secao 4A (caso G) abortou fora da sentinela: [%s] %s', v_sqlstate, v_msg));
        END IF;
    END;

    PERFORM pg_temp._flush2827(v_buf);
    v_buf := '{}';

    -- ---------------- S4B: caso H, independente ----------------
    -- Neste ponto a fixture de G e o mapping que ela criou ja foram
    -- revertidos. H comeca de um estado onde G nao existe.
    BEGIN
        INSERT INTO public.catalog_variant_import_job
            (card_set_id, source, external_set_id, status)
        VALUES (v_set, 'TCGDEX', v_ext, 'STAGED')
        RETURNING id INTO v_job;

        -- H: size = standard (deve se comportar como a comum)
        INSERT INTO public.catalog_variant_import_row
            (job_id, card_id, raw_data, normalized_data,
             validation_status, match_status, decision_status, persistence_status)
        VALUES
            (v_job, v_card,
             '{"type":"normal","foil":null,"subtype":null,"stamp":["harness-reg-tok2"],"size":"standard"}'::JSONB,
             '{}'::JSONB, 'NEEDS_REVIEW','NEW','PENDING','PENDING')
        RETURNING id INTO v_std;

        -- (i) o motor NAO bloqueia por size quando size=standard
        SELECT * INTO v_sig
          FROM internal.compute_variant_residual_signature(
                   (SELECT raw_data FROM public.catalog_variant_import_row
                     WHERE id = v_std),
                   v_game, v_src);

        -- (ii) a linha chega ao apply SEM ter sido pre-resolvida
        SELECT validation_status INTO v_h_antes
          FROM public.catalog_variant_import_row WHERE id = v_std;

        -- (iii) o mapping proprio de H resolve a linha
        PERFORM internal.apply_variant_type_mapping(v_actor, v_std, v_vt, 'GLOBAL');
        SELECT validation_status INTO v_b FROM public.catalog_variant_import_row WHERE id = v_std;

        v_buf := v_buf || pg_temp._rec2827('H',
                v_sig.printing_state = 'RESOLVED_NO_PRINTING'
            AND v_h_antes = 'NEEDS_REVIEW'
            AND v_b = 'VALID',
            format('size=standard, subtransacao PROPRIA (S4B) apos rollback integral de G. (i) motor nao bloqueia por size: state=%s (esperado RESOLVED_NO_PRINTING); (ii) antes do apply a linha estava %s (esperado NEEDS_REVIEW — nao herdou resolucao de G, cujo mapping ja nao existe); (iii) apos o mapping proprio: %s (esperado VALID).',
                   v_sig.printing_state, COALESCE(v_h_antes,'NULL'), COALESCE(v_b,'NULL')));

        RAISE EXCEPTION 'HARNESS_S4B_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        IF v_msg <> 'HARNESS_S4B_ROLLBACK' THEN
            v_buf := v_buf || pg_temp._rec2827('S4_ABORT', FALSE,
                format('Secao 4B (caso H) abortou fora da sentinela: [%s] %s', v_sqlstate, v_msg));
        END IF;
    END;

    PERFORM pg_temp._flush2827(v_buf);

    -- zero residuo da Secao 4 — por CONTAGEM (v1.1 / C1)
    -- Contagens capturadas ANTES de S4A: cobrem as DUAS subtransacoes.
    PERFORM pg_temp._chk2827('S4_ZERO_RESIDUO',
        (SELECT count(*) FROM public.catalog_variant_import_job) = v_jobs_antes
        AND (SELECT count(*) FROM public.catalog_variant_import_row) = v_rows_antes,
        format('jobs %s->%s | rows %s->%s (nada de S4A nem de S4B sobreviveu as sentinelas)',
               v_jobs_antes, (SELECT count(*) FROM public.catalog_variant_import_job),
               v_rows_antes, (SELECT count(*) FROM public.catalog_variant_import_row)));

    -- (v1.1 / C5) I consolidado: os dois eixos preservaram a linha JUMBO.
    -- Derivado, NUNCA hardcoded. Veredito ausente conta como falha e o
    -- detalhe imprime o que realmente foi lido — sem descrever sucesso.
    SELECT veredito INTO v_i_vt FROM _r2827 WHERE caso = 'I_VT';
    SELECT veredito INTO v_i_pr FROM _r2827 WHERE caso = 'I_PR';

    PERFORM pg_temp._chk2827('I',
        v_i_vt = 'PASS' AND v_i_pr = 'PASS',
        format('derivado de I_VT=%s e I_PR=%s. PASS aqui significa: a linha JUMBO INVALID/SKIPPED permaneceu intocada pelos eixos Variant Type e Printing. Qualquer valor diferente de PASS (inclusive AUSENTE) reprova.',
               COALESCE(v_i_vt, 'AUSENTE'), COALESCE(v_i_pr, 'AUSENTE')));
END;
$s4$;

-- =============================================================================
-- SEÇÃO 5 — META-INTEGRIDADE (J, suplementar) E REGRESSÃO DE BASELINE
-- =============================================================================
DO $s5$
DECLARE
    b RECORD;
    v_fora TEXT;
    v_novos TEXT;
    c_conhecidos CONSTANT TEXT[] := ARRAY[
        'internal.apply_variant_type_mapping',
        'internal.create_card_printing_profile_with_backfill',
        'public.admin_resolve_catalog_variant_import_printing_mapping',
        'public.admin_confirm_catalog_variant_import'];
BEGIN
    SELECT * INTO b FROM _base2827;

    -- J.1 — todo consumidor da funcao trata RESOLVED_* como whitelist.
    SELECT string_agg(fn, ', ') INTO v_fora
      FROM (
        SELECT n.nspname || '.' || p.proname AS fn
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE p.prokind = 'f'
           AND p.proname <> 'compute_variant_residual_signature'
           AND pg_get_functiondef(p.oid) ILIKE '%compute_variant_residual_signature%'
           AND pg_get_functiondef(p.oid) NOT ILIKE '%RESOLVED_NO_PRINTING%'
      ) t;

    -- J.2 — nenhum writer NOVO promovendo a VALID fora da lista conhecida.
    SELECT string_agg(fn, ', ') INTO v_novos
      FROM (
        SELECT n.nspname || '.' || p.proname AS fn
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE p.prokind = 'f'
           AND pg_get_functiondef(p.oid) ~* 'UPDATE[[:space:]]+public\.catalog_variant_import_row'
           AND pg_get_functiondef(p.oid) ~* 'validation_status[[:space:]]*='
           AND (n.nspname || '.' || p.proname) <> ALL (c_conhecidos)
      ) t;

    PERFORM pg_temp._chk2827('J',
        v_fora IS NULL AND v_novos IS NULL,
        format('consumidores sem whitelist RESOLVED_*: %s | writers novos de validation_status: %s (SUPLEMENTAR — nao substitui A-I)',
               COALESCE(v_fora,'nenhum'), COALESCE(v_novos,'nenhum')));

    PERFORM pg_temp._chk2827('REG1',
        (SELECT count(*) FROM public.catalog_variant_import_row) = b.rows_total,
        format('catalog_variant_import_row: baseline=%s agora=%s',
               b.rows_total, (SELECT count(*) FROM public.catalog_variant_import_row)));

    PERFORM pg_temp._chk2827('REG2',
        (SELECT count(*) FROM public.catalog_variant_import_row WHERE raw_data ? 'size') = 0
        AND b.rows_com_size = 0,
        format('linhas com chave raw_data.size: baseline=%s agora=%s (esperado 0/0 — Edge ainda nao corrigida)',
               b.rows_com_size,
               (SELECT count(*) FROM public.catalog_variant_import_row WHERE raw_data ? 'size')));

    PERFORM pg_temp._chk2827('REG3',
        (SELECT md5(string_agg(j.id::TEXT || '|' || j.status || '|' ||
                               COALESCE(j.total_rows,-1)::TEXT || '|' ||
                               COALESCE(j.valid_rows,-1)::TEXT, ',' ORDER BY j.id))
           FROM public.catalog_variant_import_job j) = b.jobs_md5,
        'md5 de (id|status|total_rows|valid_rows) de TODOS os jobs identico ao baseline');

    PERFORM pg_temp._chk2827('REG4',
        (SELECT count(*) FROM public.card_variant_type_external_mapping) = b.vt_mappings
        AND (SELECT count(*) FROM public.card_variant_type) = b.vts,
        format('mappings VT: baseline=%s agora=%s | Variant Types: baseline=%s agora=%s',
               b.vt_mappings, (SELECT count(*) FROM public.card_variant_type_external_mapping),
               b.vts, (SELECT count(*) FROM public.card_variant_type)));

    PERFORM pg_temp._chk2827('REG5',
        (SELECT count(*) FROM public.card_variant) = b.card_variants,
        format('card_variant: baseline=%s agora=%s (o harness NUNCA escreve em card_variant)',
               b.card_variants, (SELECT count(*) FROM public.card_variant)));
END;
$s5$;

-- =============================================================================
-- GATE FINAL — governança por executor (sem PASS artificial, sem FAIL mudo)
-- =============================================================================
DO $gate$
DECLARE
    -- (v1.1 / C4) O roster agora lista TODOS os casos que o harness produz.
    -- A v1.0 listava 20 de 30 — os 10 de fora não eram cobertos pela
    -- checagem de ausência. Nenhum caso pode sumir em silêncio.
    c_esperado CONSTANT INTEGER := 29;
    v_pass INTEGER; v_fail INTEGER; v_tot INTEGER; v_falhas TEXT; v_ausentes TEXT;
    c_roster CONSTANT TEXT[] := ARRAY[
        'CT1','CT2','CT3','CT4','CT5','CT6',                  -- Secao 1
        'A','A_ZW','B','C','D','E_CONTRATO','I_VT',           -- Secao 2
        'S2_ABORT_OK','S2_ZERO_RESIDUO',
        'F1_CONTRATO','F2','I_PR','S3_ZERO_RESIDUO',          -- Secao 3
        'G','H','I','S4_ZERO_RESIDUO',                        -- Secao 4
        'J','REG1','REG2','REG3','REG4','REG5'];              -- Secao 5
BEGIN
    -- S2_ABORT / S4_ABORT só são registrados QUANDO ha aborto fora da
    -- sentinela. Para que a ausencia deles signifique "correu bem" e nao
    -- "sumiu", o roster pede o par positivo S2_ABORT_OK, gravado abaixo.
    PERFORM pg_temp._chk2827('S2_ABORT_OK',
        NOT EXISTS (SELECT 1 FROM _r2827 WHERE caso IN ('S2_ABORT','S4_ABORT')),
        format('abortos fora da sentinela registrados: %s (esperado nenhum)',
               COALESCE((SELECT string_agg(caso || '=' || COALESCE(detalhe,''), ' | ')
                           FROM _r2827 WHERE caso IN ('S2_ABORT','S4_ABORT')), 'nenhum')));

    SELECT count(*) FILTER (WHERE veredito='PASS'),
           count(*) FILTER (WHERE veredito='FAIL'),
           count(*)
      INTO v_pass, v_fail, v_tot FROM _r2827;

    SELECT string_agg(caso || ': ' || detalhe, E'\n') INTO v_falhas
      FROM _r2827 WHERE veredito='FAIL';

    SELECT string_agg(c, ', ') INTO v_ausentes
      FROM unnest(c_roster) AS t(c)
     WHERE NOT EXISTS (SELECT 1 FROM _r2827 r WHERE r.caso = t.c);

    IF v_fail > 0 OR v_ausentes IS NOT NULL THEN
        RAISE EXCEPTION 'GATE_2827_FAILED: % PASS / % FAIL / % registros (roster completo %).% %',
            v_pass, v_fail, v_tot, c_esperado,
            CASE WHEN v_ausentes IS NULL THEN ''
                 ELSE E'\nCASOS AUSENTES (nao rodaram): ' || v_ausentes END,
            E'\n' || COALESCE(v_falhas, '');
    END IF;
END;
$gate$;

SELECT 'CASO'::TEXT AS tipo, caso AS chave, veredito AS valor, detalhe
  FROM _r2827
 ORDER BY chave;

-- ============================================================================
-- STATUS: v1.1.1 — PROPOSTA, NAO EXECUTADA.
--
-- v1.0 (RUN-01): gate 15 PASS / 5 FAIL — defeitos D1..D5. Zero residuo.
-- v1.1 (RUN-02): gate 27 PASS / 2 FAIL — unico defeito material D7, na
--                fixture da Secao 4. Zero residuo. Todos os contratos do
--                guard passaram.
-- v1.1.1       : corrige D7 (C6) isolando G e H em subtransacoes
--                separadas. NENHUM caso foi reexecutado nesta rodada e
--                nenhum outro caso foi alterado.
--
-- Executar SOMENTE apos a Query 2198 aplicada. A Secao 0 aborta em voz alta
-- se o guard nao estiver presente — um PASS sem 2198 seria falso por
-- construcao.
--
-- PENDENCIA DECLARADA, NAO COBERTA POR ESTE ARQUIVO:
--   E2E autenticado das DUAS RPCs publicas admin-guarded
--     public.admin_resolve_catalog_variant_import_printing_mapping  (F1)
--     public.admin_create_card_variant_type_with_import_mapping     (E)
--   exige sessao administrativa REAL no navegador. Fica para rodada
--   separada, apos 2827 PASS. Este harness nao finge te-las testado.
-- ============================================================================
