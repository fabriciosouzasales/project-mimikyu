/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2824 - Validate Card Printing Routing
Versão......: 2.6
Status......: ROLLOUT COMPLETO — TODOS OS BLOCOS EXECUTADOS E PASS (2026-09-13)

               BLOCO I   (S1..S21, S26..S28) .. PASS HISTORICO — GATE A
               BLOCO II  (S22) ................ PASS — PHASE C
               BLOCO III (S23) ................ PASS — PHASE D
               BLOCO IV  (S24, S25) ........... PASS — PHASE E

-------------------------------------------------------------------------------
AVISO OPERACIONAL — O BLOCO I E PHASE-SCOPED. NAO REEXECUTAR.
-------------------------------------------------------------------------------
O BLOCO I foi escrito para o GATE A e trava BASELINES ABSOLUTOS daquele
momento — entre outros:

    S15.00 .. VALID = 5653
    S21.13 .. staging rows = 6158
    S21.14 .. VALID = 5653
    S21.15 .. NEEDS_REVIEW = 505
    S21.16 .. rows com a chave de Impressao = 0
    S21.18 .. jobs STAGED = 4

Esses numeros NAO sao invariantes do sistema: sao a fotografia do banco
antes da PHASE C. O rollout mudou todos eles POR DESENHO — a Edge v9
importou BASE3 (+177 rows, +1 job), a Query 2183 gravou 5.653 chaves, e a
S21.16 em particular afirma o oposto do contrato atual ("durante o GATE A
ela nao existe em nenhuma row"; hoje existe em 5.768).

Consequencia pratica: REEXECUTAR O BLOCO I HOJE PRODUZIRIA FAIL. Esse
FAIL seria ESPERADO e nao indicaria regressao nenhuma — indicaria apenas
que o baseline historico foi legitimamente superado.

Os baselines NAO foram atualizados de proposito. Eles sao EVIDENCIA
HISTORICA do GATE A e perderiam esse valor se fossem reescritos com os
numeros de hoje. A logica das assercoes tambem permanece intacta.

O ESTADO TERMINAL do sistema e provado por S22, S23, S24 e S25 — nao pelo
BLOCO I. Essas quatro secoes nao dependem de contagem absoluta alguma:
todas provam invariantes de ausencia ou tentam violar o contrato e exigem
que o banco recuse.
-------------------------------------------------------------------------------
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§26)
               + STAGING-REVISION-01 (R3)
               + STAGING-REVISION-02 (§7)
               + STAGING-CORRECTION-03 (§6, §7) — BLOCKER B-02
               + GATE-A-HARNESS-CORRECTION-01 — S11 (fixture)
               + STAGING-CORRECTION-04 (§7..§12) — B-04/B-06/B-07/B-08
               + STAGING-CORRECTION-05 (§1, §2, §5, §6) — B-09/B-10
               + STAGING-CORRECTION-06 (§1..§5) — B-11/F-12
               + PHASE-D-STAGING-CORRECTION-01 (§3, §5) — BLOCKER D-2
Valida......: Queries 2172-2187

-------------------------------------------------------------------------------
Alterações da versão 2.6 (PHASE-D-STAGING-CORRECTION-01, BLOCKER D-2)
-------------------------------------------------------------------------------
- S23.03 — DE SINTOMA PARA CONSEQUENCIA. A v2.5 proibia globalmente
  `NEEDS_REVIEW + printing_profile_id = JSON null`, sob a premissa de que
  so um backfill em massa poderia ter escrito esse estado. A premissa era
  verdadeira enquanto NENHUM produtor gravava perfil em NEEDS_REVIEW.
  A PHASE C a derrubou: o outcome B da Query 2181 v1.2 exige, para
  "Impressao resolvida + Variant Type nao resolvido", exatamente
  `variant_type_id REMOVIDO + printing_profile_id explicito`. A Edge v9
  passou a produzir esse estado por CONTRATO — 51 rows na primeira
  execucao real (BASE3). A assercao antiga acusaria como defeito a saida
  correta do modelo.

  A correcao NAO isenta a Edge por nome, job_id, created_at nem cutoff de
  deploy: isso seria uma excecao ao dado de hoje, que envelheceria na
  proxima frente exatamente como a premissa anterior envelheceu.

  A v2.6 troca o alvo. O valor gravado (`null`) e um SINTOMA que as duas
  origens — a legitima e a ilegitima — compartilham. A CONSEQUENCIA que
  so a origem ilegitima produz e outra: uma row NEEDS_REVIEW que continua
  carregando `variant_type_id`. Os outcomes B e C exigem, os dois, o
  variant_type_id AUSENTE; logo sua presenca em NEEDS_REVIEW viola o
  contrato inteiro e nenhum produtor legitimo consegue cria-la.
  A assercao passa a provar isso — propriedade ESTRUTURAL, valida para
  qualquer row de qualquer origem, hoje e depois.

- S23 permanece com 4 assercoes. S23.01, S23.02 e S23.04 nao foram
  tocadas: continuam corretas e continuam falhando ANTES da Query 2183,
  que e o comportamento desejado de um gate de saida da PHASE D.

- Nenhuma mudanca em S1..S22 e S24..S28. Nenhuma mudanca de baseline do
  BLOCO I.

-------------------------------------------------------------------------------
Alterações da versão 2.5 (STAGING-CORRECTION-06)
-------------------------------------------------------------------------------
- S19 — PROVA SEMÂNTICA DA MATRIZ DE PARES (B-11). A v2.4 provava o
  contrato da terceira CHECK (`action_entity_match`) CONTANDO ocorrências
  de literais quoted no TEXTO da definição, exigindo ocorrência = 1 por
  token em dois laços independentes (um sobre entity_types, outro sobre
  actions). A técnica é defeituosa por construção: `'CATALOG_IMPORT_JOB'`
  é simultaneamente um `entity_type` e uma `action` do universo ratificado
  na Query 2159 — logo o literal aparece DUAS vezes na definição correta,
  e as duas contagens acusariam violação contra a baseline CORRETA. Era
  um falso FAIL garantido, não um defeito do contrato.
  A correção NÃO especializa o token (nada de "se for CATALOG_IMPORT_JOB
  então espere 2"): isso apenas codificaria a colisão léxica atual e
  manteria a prova dependente da representação textual. A v2.5 abandona a
  contagem e passa a AVALIAR SEMANTICAMENTE a expressão real:
    (a) `pg_get_expr(c.conbin, c.conrelid)` renderiza a expressão da CHECK
        com as colunas não-qualificadas `entity_type` e `action`;
    (b) `format()` injeta essa expressão sobre uma tabela derivada que
        expõe exatamente esses dois nomes de coluna, materializando o
        produto cartesiano completo do universo final — 12 entity_types
        × 30 actions = 360 pares — com a coluna `expected` marcando os
        30 pares legítimos;
    (c) `EXECUTE` deixa o PRÓPRIO PostgreSQL decidir cada par.
  Não há parsing, não há contagem, e a posição sintática de cada token
  (entity_type vs. action) é intrinsecamente respeitada — colisão léxica
  deixa de ser representável. Duas provas nominais foram acrescentadas:
  regressão do B-11 (`CATALOG_IMPORT_JOB` × `CATALOG_IMPORT_JOB` DEVE ser
  aceito) e cross-pair inválido (`GAME` × `CARD_CREATED` DEVE ser
  recusado), além da exclusividade de domínio entre os dois mappings.
  As listas planas `action_valid` e `entity_type_valid` continuam
  verificadas por extração textual — ali é legítimo, porque são `IN (...)`
  de coluna única, sem papel sintático a confundir; é exatamente essa
  distinção que o B-11 tornou explícita. 13 → 16 asserções.
- S19 — SUMMARY DUPLICADO REMOVIDO (F-12). A Seção terminava com DUAS
  linhas de resumo consecutivas: a nova e a antiga ('7 assercoes'),
  remanescente da v2.3. A linha obsoleta foi removida e a contagem da
  linha única foi conferida contra os rótulos reais (S19.00 a S19.15 =
  16 asserções, sem lacuna e sem duplicidade).

-------------------------------------------------------------------------------
Alterações da versão 2.4 (STAGING-CORRECTION-05)
-------------------------------------------------------------------------------
- S14 PARTE 2 — IDENTIDADE CANÔNICA PRÓPRIA (B-09). A v2.3 reusava
  `v_job`/`v_card` da PARTE 1, mas a PARTE 1 termina com a identidade
  (job, card, variant_type, printing_profile) OCUPADA por `v_fix_row`.
  Como a PARTE 2 usa o mesmo `type` no raw_data e a mesma composição A
  (UNLIMITED), a sua primeira propagação produziria exatamente a mesma
  identidade — colisão no namespace B, dentro da própria transação,
  transformando a fixture em FALSO FAIL. A PARTE 2 passa a selecionar
  par `(job, card)` próprio por NOT EXISTS contra a identidade final da
  composição A, com três guardas: candidato existe, é DIFERENTE do par
  da PARTE 1, e a identidade final completa está livre.
- S19 — PROVA ESTRUTURAL DO CONTRATO DE AUDITORIA (B-10). Passa a exigir
  que as TRÊS CHECKs existam e a verificar o universo final diretamente
  na definição: 12 ramos (cada entity_type citado 1x), 30 pares (cada
  action citada 1x no match) e nenhum literal fora do universo
  ratificado. Não depende de linha gravada — permissão ainda não
  exercida também é contrato. 7 → 13 asserções.
- S28 — ORDENAÇÃO CANÔNICA DA FIXTURE (§6). `v_sig_no_profile` passa a
  ser derivado com `ORDER BY t.id`, não `ORDER BY t.code`.
  `traits_signature` é UUID[] ordenado ascendente por trait_id; comparar
  um array ordenado por `code` contra um ordenado por UUID daria
  "profile inexistente" para um conjunto que EXISTE sempre que as duas
  ordenações divergirem. Hoje não se materializa; a fragilidade é
  eliminada antes que se materialize.

-------------------------------------------------------------------------------
Alterações da versão 2.3 (STAGING-CORRECTION-04)
-------------------------------------------------------------------------------
- S12 REESCRITA. Passa a provar o estado FINAL da PHASE B, incluindo a
  Query 2187: pronargdefaults = 0. Nenhum PASS se o DEFAULT NULL de
  internal.write_card_variant() sobreviver.
- S14 PARTE 1 — fixture DATA-INDEPENDENT (B-07). A identidade FINAL
  (job, card, variant_type, printing_profile) que a propagação vai
  produzir é escolhida por NOT EXISTS e reconfirmada por precondição
  explícita imediatamente antes da RPC. A v2.2 escolhia job/card por
  LIMIT 1 e derivava o Variant Type de outro LIMIT 1 independente,
  assumindo sem provar que o namespace B estava vazio.
- S14 PARTE 2 — token sintético próprio (B-08). A v2.2 reusava a row da
  PARTE 1 (stamp 'harness-token-s14') para chamadas referentes a
  '1st-edition', token que não existe nessa row. Com o origin-row binding
  da Query 2181 v1.2 isso passa a ser rejeitado — corretamente. A prova
  de NO_CHANGE e de substituição agora usa fixture própria com o token
  HARNESS-S14-REPLACE presente EXPLICITAMENTE na raw_data da origem, e
  não toca mais o mapping real de 1ST-EDITION.
- S28 NOVA. Duas frentes:
    (a) B-06 — reconciliação terminal das rows atingidas, Casos A e B;
    (b) OB1..OB6 — origin-row binding (B-04).
- S13b ganhou a asserção de ORDEM: payload inválido é rejeitado ANTES de
  a origem ser consultada. É o contrato que mantém S13b executável sem
  fixture de origem.

-------------------------------------------------------------------------------
Alterações da versão 2.2.1 (GATE-A-HARNESS-CORRECTION-01)
-------------------------------------------------------------------------------
Rodada aplicada sobre a v2.2 e NÃO registrada no header à época — a
divergência foi apontada em PHASE-B-FINAL-AUDIT-01 (§15) e é fechada
aqui. Mudanças:
- S11 -> v1.1. Fixture data-independent: a tripla
  (job STAGED, card, variant_type do mesmo Game) é escolhida por
  NOT EXISTS contra os TRÊS namespaces, com ORDER BY determinístico,
  precondições fail-loud e regression guard explícito antes do primeiro
  INSERT. Cobertura ampliada de 3 para 9 asserções: H17 e H18
  comportamentais entraram, e H19 passou a ser provado por censo dos três
  namespaces. Motivo: a v1.0 colidiu com dado real
  (uq_cvir_job_card_type_bridge_legacy) durante o SETUP e abortou antes
  de avaliar qualquer asserção — falso FAIL por defeito de fixture.
- S15.00 — baseline VALID = 5653 asserido antes de medir H21.
- S16.06 — complemento explícito de S16.02: nenhuma row de BASE1 pode
  restar em NEEDS_REVIEW por Impressão (resumo 5 -> 6).
- S17.04 — guard de NÃO-VACUIDADE do corpus '1st-edition-error'; a
  asserção antiga virou S17.05 (resumo 4 -> 5).
- S21.12 a S21.20 — resíduo de fixture de staging (marcador
  raw_data ? 'harness') e baseline crítico completo (resumo 10 -> 20).
- Mapa de casos: H17/H18/H20 passaram a apontar para S10 + S11.

Alterações da versão 2.2 (STAGING-CORRECTION-03, BLOCKER B-02):
- S14 REESCRITA. A v2.1 provava apenas `mapping_id IS NOT NULL` e
  `superseded_mapping_id IS NOT NULL` — as duas passariam com a
  propagação VAZIA. Ela teria dado PASS com o B-01 presente.
  Agora a Seção monta uma row de staging real, executa uma ratificação
  editorial real e exige `rows_revalidated = 1`, `jobs_affected = 1`,
  `rows_still_pending = 0`, mais o estado final da própria row
  (validation_status, printing_profile_id e variant_type_id residual).
  Se a Query 2176 voltar a ler só a assinatura selada, S14.02 FALHA.
- S27 NOVA. Prova o contrato temporal DIRETAMENTE, sem passar pela 2181:
  chama a função com o mapping ainda não selado, nos dois casos opostos
  (N:N completa -> resolve; N:N vazia -> fail-closed com estado próprio).
- S21 ganhou a asserção 11 (marcador HARNESS em metadata).

Alterações da versão 2.1 (STAGING-REVISION-02):
- Seção S26 acrescentada — casos L01 a L07 do contrato de leitura do
  Log de Atualizações (Query 2186), mais três asserções de regressão
  (total_count, teto de p_limit, autorização).
- S26 pertence ao BLOCO I e roda DEPOIS de S1..S20 e ANTES de S21.
  Ficou no fim do arquivo para não renumerar seções já referenciadas
  nos rodapés das migrations.

-------------------------------------------------------------------------------
VERSÃO 2.0 — BLOCKER R3
-------------------------------------------------------------------------------
A v1.0 tinha um inventário INCORRETO (o relatório dizia "H01-H20 dentro"
e, três parágrafos abaixo, "H13 deixado fora") e adiava cinco casos que
NÃO dependem do deploy da Edge:

    H13 · H21 · H23 · H24 · H27   -> agora provados no GATE A.

O argumento da v1.0 — "não existe estado pós-Edge" — não se aplicava a
eles. H23 e H24 são testes do RESOLVEDOR contra dados que já existem
hoje; H21 é uma precondição da própria Query 2183, medida sobre dados
reais; H13 e H27 são provados por fixture em transação revertida.

Nada de falso PASS. Mas também nada de adiar prova que já é possível.

-------------------------------------------------------------------------------
SEMANTICA DE EXECUCAO — LEIA ANTES DE RODAR
-------------------------------------------------------------------------------
TODAS as Secoes sao FAIL-CLOSED: cada assercao e um RAISE EXCEPTION
dentro de um bloco DO. PASS = ausencia de excecao; FAIL = excecao
nomeando o caso.

O MCP do Supabase NAO propaga RAISE NOTICE. O sinal de PASS e a ausencia
de excecao, mais o SELECT ... AS resumo ao fim de cada Secao.

Secoes comportamentais rodam dentro de BEGIN ... ROLLBACK. Para observar
o efeito do trigger DEFERIDO de selamento sem commitar, usam
SET CONSTRAINTS ALL IMMEDIATE dentro de sub-bloco com EXCEPTION — a forma
canonica ja validada na Query 2823.

As Secoes que exercitam RPC admin (S13, S14) IMPERSONAM um administrador
real ja existente, via request.jwt.claims, dentro da transacao revertida.
Nenhuma linha de admin_user e criada. Se nao houver nenhum admin
cadastrado, a Secao FALHA ALTO — nunca passa por omissao.

-------------------------------------------------------------------------------
BLOCOS — QUANDO RODAR CADA UM
-------------------------------------------------------------------------------
BLOCO I   — GATE-A HARNESS ......... S1 a S20, S26, S27, S28, e S21 POR ULTIMO
            Depois de 2172-2187 aplicadas. ANTES do deploy da Edge nova.
            Este e o bloco que autoriza a PHASE C.

            ORDEM DE EXECUCAO: S1..S20, depois S26, S27 e S28, e SO ENTAO
            S21. S21 e a prova de zero residuo — ela precisa ser a ultima
            coisa que roda, senao nao prova nada. S26, S27 e S28 foram
            acrescentadas no fim do arquivo (REVISION-02, CORRECTION-03 e
            CORRECTION-04) para nao renumerar secoes ja referenciadas nos
            rodapes das migrations.

            SUBCONJUNTO PHASE-A-ONLY (executado e aprovado em
            PHASE-A-EXECUTION-01 + GATE-A-HARNESS-CORRECTION-01):
            S1..S11, S13 parte (a), S15, S16, S17, S18.01-.04, S27 e S21.
            As demais dependem de objetos das PHASES B/C/D/E.

BLOCO II  — POST-EDGE HARNESS ...... S22
            Depois do deploy da Edge nova em producao. Prova que o
            writer novo honra o contrato de saida. Autoriza a PHASE D.

BLOCO III — POST-BACKFILL HARNESS .. S23
            Depois da Query 2183. Autoriza a PHASE E.

BLOCO IV  — FINAL-E HARNESS ........ S24 a S25
            Depois da Query 2184. Fechamento da frente.

-------------------------------------------------------------------------------
MAPA CASO -> SECAO -> BLOCO
-------------------------------------------------------------------------------
H01 dois ACTIVE mesmo token .................. S3   I
H02 inactive + active ........................ S4   I
H03 composicoes historicas diferentes ........ S4   I
H04 inactive-only -> NEEDS_REVIEW ............ S8   I
H05 never-known -> residual .................. S7   I
H06 replacement concorrente .................. S3   I
H07 extensao de composicao selada ............ S5   I
H08 TRUE->FALSE lifecycle valido ............. S6   I
H09 reativacao silenciosa .................... S6   I
H10 is_active NULL ........................... S6   I
H11 empty composition ........................ S5   I
H12 same-Game ................................ S1   I
H13 duplicate trait .......................... S13  I
H14 exact token .............................. S7   I
H15 1st-edition-error nao casa ............... S7   I
H16 explicit JSON null != absent ............. S9   I
H17 staging no-profile uniqueness ............ S10 + S11  I
H18 staging with-profile uniqueness .......... S10 + S11  I
H19 unresolved fora dos dois indices ......... S11  I
H20 bridge protege writer antigo ............. S10 + S11  I
H21 5.653 VALID seguros para null backfill ... S15  I
H22 contrato de reconciliacao (transacional).. S15  I
H22 contrato de reconciliacao (real) ......... S23  III
H23 BASE1 410/410 ............................ S16  I
H24 BASEP/SVE/SV5 95 intactas ................ S17  I
H25 matching triplo .......................... S12  I
H26 no-profile matching usa NULL ............. S12  I
H27 replacement nao altera card_variant ...... S14  I
B-01 propagacao real (nao vazia) ............. S14  I
B-01 unsealed + N:N completa -> resolve ...... S27  I
B-01 unsealed + N:N vazia -> fail-closed ..... S27  I
B-05 NO_CHANGE antes do selo diferido ........ S14  I
B-06 VALID rebaixada, chaves removidas ....... S28  I
B-06 Printing ok / Variant Type ausente ...... S28  I
B-04 origin-row binding (OB1..OB6) ........... S28  I
D-01 sem DEFAULT no writer (pronargdefaults) . S12  I
H28 service_role somente SELECT necessario ... S18  I
H29 zero residuo de fixtures ................. S21  I
R4  contrato de auditoria .................... S19  I
R2  compatibilidade transitoria do confirm ... S20  I
L01 Printing Mapping -> label legivel ........ S26  I
L02 metadata vence fallback .................. S26  I
L03 metadata ausente -> tabela viva resolve .. S26  I
L04 entidade ausente -> fallback UUID ........ S26  I
L05 Variant Type Mapping -> label legivel .... S26  I
L06 demais entity_types nao regridem ......... S26  I
L07 p_search encontra pelo label humano ...... S26  I
R2  chave ausente volta a ser rejeicao dura .. S25  IV
R5  invariante final de normalized_data ...... S24  IV
===============================================================================
*/


-- #############################################################################
-- ##                                                                         ##
-- ##   B L O C O   I   —   G A T E - A   H A R N E S S   ( S1 .. S21 )        ##
-- ##                                                                         ##
-- #############################################################################


-- =============================================================================
-- SECAO 1 — SCHEMA (read-only, FAIL-CLOSED) · H12
-- =============================================================================
DO $s1$
DECLARE
    v_n INTEGER;
BEGIN
    SELECT count(*) INTO v_n FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relkind='r'
       AND c.relname IN ('card_printing_external_mapping','card_printing_external_mapping_trait');
    IF v_n <> 2 THEN RAISE EXCEPTION 'S1.01 FALHOU: esperadas 2 tabelas de routing, encontradas %.', v_n; END IF;

    -- H12 — same-Game ESTRUTURAL: duas FKs compostas na N:N, sem trigger.
    SELECT count(*) INTO v_n FROM pg_constraint
     WHERE conrelid='public.card_printing_external_mapping_trait'::regclass
       AND contype='f' AND array_length(conkey,1)=2;
    IF v_n <> 2 THEN RAISE EXCEPTION 'S1.02 FALHOU: esperadas 2 FKs compostas na N:N, encontradas %.', v_n; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid='public.card_printing_external_mapping_trait'::regclass
                      AND contype='p' AND array_length(conkey,1)=2)
    THEN RAISE EXCEPTION 'S1.03 FALHOU: PK composta (mapping_id, trait_id) ausente.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                    AND indexname='uq_card_printing_external_mapping_active_token'
                    AND indexdef LIKE '%UNIQUE%' AND indexdef LIKE '%is_active%')
    THEN RAISE EXCEPTION 'S1.04 FALHOU: indice unico parcial de token ativo ausente ou sem o predicado is_active.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                    AND indexname='ix_card_printing_external_mapping_token')
    THEN RAISE EXCEPTION 'S1.05 FALHOU: indice de lookup de token (independente de is_active) ausente.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='card_printing_external_mapping'
                      AND column_name='is_active' AND is_nullable='NO')
    THEN RAISE EXCEPTION 'S1.06 FALHOU: is_active precisa ser NOT NULL.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='card_printing_external_mapping'
                      AND column_name='traits_signature' AND data_type='ARRAY' AND udt_name='_uuid')
    THEN RAISE EXCEPTION 'S1.07 FALHOU: traits_signature nao e UUID[].'; END IF;

    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                WHERE n.nspname='internal' AND p.proname LIKE '%card_printing_external_mapping%'
                  AND (p.prosrc ILIKE '%md5(%' OR p.prosrc ILIKE '%sha256(%' OR p.prosrc ILIKE '%digest(%'))
    THEN RAISE EXCEPTION 'S1.08 FALHOU: guard de routing usa hash — integridade deve ser por igualdade exata.'; END IF;

    SELECT count(*) INTO v_n FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relrowsecurity
       AND c.relname IN ('card_printing_external_mapping','card_printing_external_mapping_trait');
    IF v_n <> 2 THEN RAISE EXCEPTION 'S1.09 FALHOU: RLS habilitado em apenas % das 2 tabelas.', v_n; END IF;

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='internal' AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']
       AND p.proname IN ('normalize_card_printing_external_mapping',
                         'enforce_card_printing_external_mapping_header',
                         'seal_card_printing_external_mapping',
                         'enforce_card_printing_external_mapping_composition_immutable',
                         'enforce_card_printing_external_mapping_signature_write');
    IF v_n <> 5 THEN RAISE EXCEPTION 'S1.10 FALHOU: apenas % dos 5 guards sao SECURITY DEFINER com search_path vazio.', v_n; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgrelid='public.card_printing_external_mapping'::regclass
                      AND tgname='trg_card_printing_external_mapping_seal'
                      AND tgconstraint <> 0 AND tgdeferrable AND tginitdeferred)
    THEN RAISE EXCEPTION 'S1.11 FALHOU: trigger de selamento ausente ou nao e CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='internal' AND p.proname='compute_variant_residual_signature'
                      AND p.provolatile='s')
    THEN RAISE EXCEPTION 'S1.12 FALHOU: compute_variant_residual_signature ausente ou nao e STABLE.'; END IF;
END;
$s1$;

SELECT 'S1 SCHEMA · H12: 12 grupos PASS' AS resumo;


-- =============================================================================
-- SECAO 2 — SEED (read-only, FAIL-CLOSED)
-- =============================================================================
DO $s2$
DECLARE
    v_game UUID; v_src UUID; v_n INTEGER;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code='TCGDEX';
    IF v_game IS NULL OR v_src IS NULL THEN
        RAISE EXCEPTION 'S2.00 FALHOU: Game POKEMON ou Fonte TCGDEX nao encontrados.';
    END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_external_mapping
     WHERE game_id=v_game AND asset_source_id=v_src;
    IF v_n <> 5 THEN RAISE EXCEPTION 'S2.01 FALHOU: % mappings, esperados 5.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_external_mapping
     WHERE game_id=v_game AND asset_source_id=v_src AND is_active;
    IF v_n <> 5 THEN RAISE EXCEPTION 'S2.02 FALHOU: % mappings ativos, esperados 5.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_external_mapping_trait;
    IF v_n <> 6 THEN RAISE EXCEPTION 'S2.03 FALHOU: % vinculos, esperados 6.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_external_mapping
     WHERE traits_signature IS NOT NULL;
    IF v_n <> 5 THEN RAISE EXCEPTION 'S2.04 FALHOU: % de 5 mappings selados.', v_n; END IF;

    -- Composicao exata, prova SET-BASED. Licao da 2823 v1.2: nunca
    -- string_agg global, que depende de collation.
    IF EXISTS (
        WITH expected(raw_field, token, trait_code) AS (
            VALUES ('subtype','SHADOWLESS','SHADOWLESS'),
                   ('subtype','UNLIMITED','UNLIMITED'),
                   ('subtype','1999-2000-COPYRIGHT','COPYRIGHT_1999_2000'),
                   ('subtype','SHADOWLESS-RED-CHEEK','SHADOWLESS'),
                   ('subtype','SHADOWLESS-RED-CHEEK','RED_CHEEK'),
                   ('stamp','1ST-EDITION','FIRST_EDITION')
        ),
        actual(raw_field, token, trait_code) AS (
            SELECT m.raw_field::TEXT, m.normalized_token, t.code::TEXT
              FROM public.card_printing_external_mapping m
              JOIN public.card_printing_external_mapping_trait mt ON mt.mapping_id = m.id
              JOIN public.card_printing_trait t ON t.id = mt.trait_id
             WHERE m.game_id = v_game AND m.asset_source_id = v_src AND m.is_active
        )
        SELECT 1 FROM (SELECT * FROM expected EXCEPT SELECT * FROM actual) a
        UNION ALL
        SELECT 1 FROM (SELECT * FROM actual EXCEPT SELECT * FROM expected) b
    ) THEN RAISE EXCEPTION 'S2.05 FALHOU: composicao do routing divergente do ratificado.'; END IF;

    SELECT cardinality(m.traits_signature) INTO v_n
      FROM public.card_printing_external_mapping m
     WHERE m.game_id=v_game AND m.asset_source_id=v_src
       AND m.raw_field='subtype' AND m.normalized_token='SHADOWLESS-RED-CHEEK' AND m.is_active;
    IF v_n IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'S2.06 FALHOU: shadowless-red-cheek deveria ter assinatura de 2 traits (encontrado: %).', v_n;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.card_printing_external_mapping m
         WHERE m.traits_signature IS DISTINCT FROM (
               SELECT ARRAY(SELECT mt.trait_id FROM public.card_printing_external_mapping_trait mt
                             WHERE mt.mapping_id = m.id ORDER BY mt.trait_id))
    ) THEN RAISE EXCEPTION 'S2.07 FALHOU: traits_signature divergente da composicao real.'; END IF;

    IF EXISTS (
        SELECT 1 FROM public.card_printing_external_mapping m
         WHERE NOT EXISTS (SELECT 1 FROM public.card_printing_external_mapping_trait mt
                            WHERE mt.mapping_id = m.id)
    ) THEN RAISE EXCEPTION 'S2.08 FALHOU: existe mapping sem nenhum trait.'; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_external_mapping
     WHERE supersedes_mapping_id IS NOT NULL;
    IF v_n <> 0 THEN RAISE EXCEPTION 'S2.09 FALHOU: % mapping(s) com supersedes na seed inicial.', v_n; END IF;
END;
$s2$;

SELECT 'S2 SEED: 5 ativos / 6 vinculos / assinaturas exatas PASS' AS resumo;


-- =============================================================================
-- SECAO 3 — H01/H06: DOIS ATIVOS PARA O MESMO TOKEN -> REJEITADO
-- =============================================================================
BEGIN;

DO $s3$
DECLARE
    v_game UUID; v_src UUID; v_fe UUID; v_new UUID; v_msg TEXT; v_ok BOOLEAN;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code='TCGDEX';
    SELECT id INTO v_fe   FROM public.card_printing_trait WHERE game_id=v_game AND code='FIRST_EDITION';

    v_ok := FALSE;
    BEGIN
        -- 'shadowless' JA tem um mapping ativo. Um segundo ativo para o
        -- MESMO token, com composicao DIFERENTE (conjunto disjunto do
        -- original), tem que ser rejeitado — este e exatamente o caso
        -- que derrubava o modelo de uma tabela so.
        INSERT INTO public.card_printing_external_mapping
            (game_id, asset_source_id, raw_field, normalized_token, external_token, is_active)
        VALUES (v_game, v_src, 'subtype', 'SHADOWLESS', 'shadowless', TRUE)
        RETURNING id INTO v_new;

        INSERT INTO public.card_printing_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_new, v_fe, v_game);

        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := TRUE;
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S3.01 FALHOU: dois mappings ACTIVE para o mesmo token foram aceitos.';
    END IF;
END;
$s3$;

SELECT 'S3 H01/H06 DOIS ATIVOS: rejeitado PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 4 — H02/H03: HISTORICO PERMITIDO, COMPOSICOES DIFERENTES
-- =============================================================================
BEGIN;

DO $s4$
DECLARE
    v_game UUID; v_src UUID; v_old UUID; v_new UUID; v_fe UUID; v_msg TEXT;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code='TCGDEX';
    SELECT id INTO v_fe   FROM public.card_printing_trait WHERE game_id=v_game AND code='FIRST_EDITION';

    SELECT id INTO v_old FROM public.card_printing_external_mapping
     WHERE game_id=v_game AND asset_source_id=v_src
       AND raw_field='subtype' AND normalized_token='SHADOWLESS' AND is_active;

    BEGIN
        UPDATE public.card_printing_external_mapping SET is_active=FALSE WHERE id=v_old;

        INSERT INTO public.card_printing_external_mapping
            (game_id, asset_source_id, raw_field, normalized_token, external_token,
             is_active, supersedes_mapping_id)
        VALUES (v_game, v_src, 'subtype', 'SHADOWLESS', 'shadowless', TRUE, v_old)
        RETURNING id INTO v_new;

        INSERT INTO public.card_printing_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_new, v_fe, v_game);

        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION 'S4.01 FALHOU: substituicao legitima foi rejeitada (msg: %).', v_msg;
    END;

    IF (SELECT count(*) FROM public.card_printing_external_mapping
         WHERE game_id=v_game AND asset_source_id=v_src
           AND raw_field='subtype' AND normalized_token='SHADOWLESS') <> 2 THEN
        RAISE EXCEPTION 'S4.02 FALHOU: esperados 2 mappings historicos para o token.';
    END IF;

    IF (SELECT count(*) FROM public.card_printing_external_mapping
         WHERE game_id=v_game AND asset_source_id=v_src
           AND raw_field='subtype' AND normalized_token='SHADOWLESS' AND is_active) <> 1 THEN
        RAISE EXCEPTION 'S4.03 FALHOU: deveria haver exatamente 1 ativo.';
    END IF;

    IF (SELECT supersedes_mapping_id FROM public.card_printing_external_mapping WHERE id=v_new)
       IS DISTINCT FROM v_old THEN
        RAISE EXCEPTION 'S4.04 FALHOU: supersedes_mapping_id nao aponta para o predecessor.';
    END IF;
END;
$s4$;

SELECT 'S4 H02/H03 HISTORICO: aceito, 1 ativo, cadeia correta PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 5 — H07/H11: SELAMENTO E IMUTABILIDADE
-- =============================================================================
BEGIN;

DO $s5a$
DECLARE
    v_game UUID; v_src UUID; v_new UUID; v_msg TEXT; v_ok BOOLEAN;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code='TCGDEX';

    -- H11 — mapping VAZIO nao chega ao COMMIT.
    v_ok := FALSE;
    BEGIN
        INSERT INTO public.card_printing_external_mapping
            (game_id, asset_source_id, raw_field, normalized_token, external_token)
        VALUES (v_game, v_src, 'stamp', 'HARNESS-EMPTY', 'harness-empty')
        RETURNING id INTO v_new;
        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%EMPTY_COMPOSITION%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S5.01 FALHOU: mapping sem trait chegou ao COMMIT (msg: %).', v_msg; END IF;
END;
$s5a$;

SELECT 'S5a H11 MAPPING VAZIO: rejeitado no COMMIT PASS' AS resumo;

ROLLBACK;

BEGIN;

DO $s5b$
DECLARE
    v_game UUID; v_m UUID; v_fe UUID; v_sl UUID; v_msg TEXT; v_ok BOOLEAN;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_fe FROM public.card_printing_trait WHERE game_id=v_game AND code='FIRST_EDITION';
    SELECT id INTO v_sl FROM public.card_printing_trait WHERE game_id=v_game AND code='SHADOWLESS';

    SELECT id INTO v_m FROM public.card_printing_external_mapping
     WHERE game_id=v_game AND raw_field='subtype' AND normalized_token='SHADOWLESS' AND is_active;

    IF (SELECT traits_signature FROM public.card_printing_external_mapping WHERE id=v_m) IS NULL THEN
        RAISE EXCEPTION 'S5.PRE FALHOU: o mapping SHADOWLESS nao esta selado — a seed nao rodou.';
    END IF;

    -- H07 — ADD em mapping selado.
    v_ok := FALSE;
    BEGIN
        INSERT INTO public.card_printing_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m, v_fe, v_game);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%COMPOSITION_SEALED%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S5.02 FALHOU: trait adicionado a mapping selado (msg: %).', v_msg; END IF;

    v_ok := FALSE;
    BEGIN
        DELETE FROM public.card_printing_external_mapping_trait WHERE mapping_id=v_m AND trait_id=v_sl;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%COMPOSITION_SEALED%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S5.03 FALHOU: trait removido de mapping selado (msg: %).', v_msg; END IF;

    v_ok := FALSE;
    BEGIN
        UPDATE public.card_printing_external_mapping_trait SET trait_id=v_fe
         WHERE mapping_id=v_m AND trait_id=v_sl;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%UPDATE_FORBIDDEN%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S5.04 FALHOU: UPDATE de vinculo aceito (msg: %).', v_msg; END IF;

    v_ok := FALSE;
    BEGIN
        UPDATE public.card_printing_external_mapping SET traits_signature = NULL WHERE id=v_m;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%SIGNATURE_IMMUTABLE%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S5.05 FALHOU: selo destravado por UPDATE (msg: %).', v_msg; END IF;

    v_ok := FALSE;
    BEGIN
        UPDATE public.card_printing_external_mapping SET traits_signature = ARRAY[v_fe] WHERE id=v_m;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%SIGNATURE_IMMUTABLE%' OR v_msg LIKE '%SIGNATURE_MISMATCH%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S5.06 FALHOU: assinatura falsificada aceita (msg: %).', v_msg; END IF;

    -- Reinsercao IDENTICA: aceita (idempotencia da seed).
    BEGIN
        INSERT INTO public.card_printing_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m, v_sl, v_game)
        ON CONFLICT (mapping_id, trait_id) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION 'S5.07 FALHOU: reinsercao identica rejeitada — a seed deixaria de ser idempotente (msg: %).', v_msg;
    END;
END;
$s5b$;

SELECT 'S5b H07 IMUTABILIDADE: 6 assercoes PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 6 — H08/H09/H10: LIFECYCLE DE is_active
-- =============================================================================
BEGIN;

DO $s6$
DECLARE
    v_game UUID; v_m UUID; v_msg TEXT; v_ok BOOLEAN;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_m FROM public.card_printing_external_mapping
     WHERE game_id=v_game AND raw_field='stamp' AND normalized_token='1ST-EDITION' AND is_active;

    BEGIN
        UPDATE public.card_printing_external_mapping SET is_active=FALSE WHERE id=v_m;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION 'S6.01 FALHOU: aposentadoria legitima rejeitada (msg: %).', v_msg;
    END;

    v_ok := FALSE;
    BEGIN
        UPDATE public.card_printing_external_mapping SET is_active=TRUE WHERE id=v_m;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%REACTIVATION_FORBIDDEN%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S6.02 FALHOU: mapping aposentado foi reativado (msg: %).', v_msg; END IF;

    v_ok := FALSE;
    BEGIN
        UPDATE public.card_printing_external_mapping SET normalized_token='OUTRO' WHERE id=v_m;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%IDENTITY_IMMUTABLE%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S6.03 FALHOU: identidade externa alterada (msg: %).', v_msg; END IF;

    v_ok := FALSE;
    BEGIN
        UPDATE public.card_printing_external_mapping SET is_active=NULL WHERE id=v_m;
    EXCEPTION WHEN OTHERS THEN v_ok := TRUE;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S6.04 FALHOU: is_active aceitou NULL.'; END IF;
END;
$s6$;

SELECT 'S6 H08/H09/H10 LIFECYCLE: 4 assercoes PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 7 — H05/H14/H15: RESIDUAL, TOKEN EXATO, 1st-edition-error
-- =============================================================================
DO $s7$
DECLARE
    v_game UUID; v_src UUID; r RECORD;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code='TCGDEX';

    SELECT * INTO r FROM internal.compute_variant_residual_signature(
        '{"type":"normal","subtype":"shadowless"}'::JSONB, v_game, v_src);
    IF r.printing_state <> 'RESOLVED_WITH_PROFILE' THEN
        RAISE EXCEPTION 'S7.01 FALHOU: shadowless nao resolveu para profile (estado: %).', r.printing_state;
    END IF;
    IF r.residual_subtype IS NOT NULL THEN
        RAISE EXCEPTION 'S7.02 FALHOU: subtype consumido pelo Printing permaneceu no residual.';
    END IF;
    IF r.residual_type <> 'NORMAL' THEN
        RAISE EXCEPTION 'S7.03 FALHOU: type foi alterado — acabamento nunca vira Printing.';
    END IF;

    SELECT * INTO r FROM internal.compute_variant_residual_signature(
        '{"type":"normal","stamp":["1st-edition-error"]}'::JSONB, v_game, v_src);
    IF r.printing_state <> 'RESOLVED_NO_PRINTING' THEN
        RAISE EXCEPTION 'S7.04 FALHOU: 1st-edition-error foi tratado como Printing (estado: %).', r.printing_state;
    END IF;
    IF NOT ('1ST-EDITION-ERROR' = ANY (r.residual_stamp)) THEN
        RAISE EXCEPTION 'S7.05 FALHOU: 1st-edition-error nao permaneceu no residual.';
    END IF;

    SELECT * INTO r FROM internal.compute_variant_residual_signature(
        '{"type":"normal","stamp":["staff"]}'::JSONB, v_game, v_src);
    IF r.printing_state <> 'RESOLVED_NO_PRINTING' OR NOT ('STAFF' = ANY (r.residual_stamp)) THEN
        RAISE EXCEPTION 'S7.06 FALHOU: token desconhecido nao permaneceu no residual.';
    END IF;

    SELECT * INTO r FROM internal.compute_variant_residual_signature(
        '{"type":"normal","subtype":"shadowless","stamp":["1st-edition"]}'::JSONB, v_game, v_src);
    IF r.printing_state <> 'RESOLVED_WITH_PROFILE' OR cardinality(r.trait_ids) <> 2 THEN
        RAISE EXCEPTION 'S7.07 FALHOU: shadowless + 1st-edition deveria dar 2 traits e profile exato.';
    END IF;
    IF cardinality(r.residual_stamp) <> 0 OR r.residual_subtype IS NOT NULL THEN
        RAISE EXCEPTION 'S7.08 FALHOU: residual deveria estar limpo.';
    END IF;

    SELECT * INTO r FROM internal.compute_variant_residual_signature(
        '{"type":"normal","stamp":["top-eight","staff"]}'::JSONB, v_game, v_src);
    IF r.residual_stamp IS DISTINCT FROM ARRAY(SELECT s FROM unnest(r.residual_stamp) s ORDER BY s) THEN
        RAISE EXCEPTION 'S7.09 FALHOU: residual_stamp nao esta ordenado.';
    END IF;
END;
$s7$;

SELECT 'S7 H05/H14/H15 RESIDUAL: 9 assercoes PASS' AS resumo;


-- =============================================================================
-- SECAO 8 — H04: INACTIVE-ONLY -> NEEDS_REVIEW, NAO RESIDUAL
-- =============================================================================
BEGIN;

DO $s8$
DECLARE
    v_game UUID; v_src UUID; v_m UUID; r RECORD;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code='TCGDEX';

    SELECT id INTO v_m FROM public.card_printing_external_mapping
     WHERE game_id=v_game AND raw_field='subtype' AND normalized_token='UNLIMITED' AND is_active;

    UPDATE public.card_printing_external_mapping SET is_active=FALSE WHERE id=v_m;

    SELECT * INTO r FROM internal.compute_variant_residual_signature(
        '{"type":"normal","subtype":"unlimited"}'::JSONB, v_game, v_src);

    IF r.printing_state <> 'NEEDS_REVIEW_INACTIVE_MAPPING' THEN
        RAISE EXCEPTION 'S8.01 FALHOU: token so com historico inativo deveria dar NEEDS_REVIEW_INACTIVE_MAPPING (estado: %).', r.printing_state;
    END IF;

    -- O PONTO CRITICO: o token NAO pode voltar ao residual, senao viraria
    -- acabamento e recriaria composicao taxonomica.
    IF r.residual_subtype IS NOT NULL THEN
        RAISE EXCEPTION 'S8.02 FALHOU: token conhecido-porem-inativo voltou ao residual — isso o reclassificaria como acabamento.';
    END IF;

    IF r.printing_profile_id IS NOT NULL THEN
        RAISE EXCEPTION 'S8.03 FALHOU: estado NEEDS_REVIEW nao pode devolver profile.';
    END IF;
END;
$s8$;

SELECT 'S8 H04 INACTIVE-ONLY: NEEDS_REVIEW, fora do residual PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 9 — H16: JSON null EXPLICITO != CHAVE AUSENTE
-- =============================================================================
DO $s9$
DECLARE
    v_absent TEXT; v_null TEXT; v_str TEXT;
BEGIN
    v_absent := jsonb_typeof('{"variant_type_id":"x"}'::JSONB -> 'printing_profile_id');
    v_null   := jsonb_typeof('{"printing_profile_id":null}'::JSONB -> 'printing_profile_id');
    v_str    := jsonb_typeof('{"printing_profile_id":"abc"}'::JSONB -> 'printing_profile_id');

    IF v_absent IS NOT NULL THEN RAISE EXCEPTION 'S9.01 FALHOU: chave ausente deveria dar SQL NULL (deu: %).', v_absent; END IF;
    IF v_null <> 'null'    THEN RAISE EXCEPTION 'S9.02 FALHOU: JSON null deveria dar ''null'' (deu: %).', v_null; END IF;
    IF v_str <> 'string'   THEN RAISE EXCEPTION 'S9.03 FALHOU: string deveria dar ''string'' (deu: %).', v_str; END IF;

    IF ('{"variant_type_id":"x"}'::JSONB ->> 'printing_profile_id') IS DISTINCT FROM
       ('{"printing_profile_id":null}'::JSONB ->> 'printing_profile_id') THEN
        RAISE EXCEPTION 'S9.04 FALHOU: premissa errada — esperava-se que ->> colapsasse ausente e null.';
    END IF;

    -- O operador `?` (existencia de chave), usado pela constraint final
    -- da PHASE E, distingue corretamente os dois casos.
    IF ('{"variant_type_id":"x"}'::JSONB ? 'printing_profile_id') THEN
        RAISE EXCEPTION 'S9.05 FALHOU: operador ? afirmou existencia de chave ausente.';
    END IF;
    IF NOT ('{"printing_profile_id":null}'::JSONB ? 'printing_profile_id') THEN
        RAISE EXCEPTION 'S9.06 FALHOU: operador ? negou existencia de chave com valor JSON null.';
    END IF;
END;
$s9$;

SELECT 'S9 H16 null EXPLICITO != AUSENTE: 6 assercoes PASS' AS resumo;


-- =============================================================================
-- SECAO 10 — H17/H18/H20: INDICES DE IDENTIDADE (estrutural)
-- =============================================================================
DO $s10$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                AND indexname='uq_catalog_variant_import_row_job_card_variant_type')
    THEN RAISE EXCEPTION 'S10.01 FALHOU: o indice legado de staging ainda existe.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                    AND indexname='uq_cvir_job_card_type_no_printing'
                    AND indexdef LIKE '%UNIQUE%' AND indexdef LIKE '%''null''%')
    THEN RAISE EXCEPTION 'S10.02 FALHOU: indice no-printing ausente ou sem o predicado jsonb_typeof = ''null''.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                    AND indexname='uq_cvir_job_card_type_printing'
                    AND indexdef LIKE '%UNIQUE%' AND indexdef LIKE '%''string''%'
                    AND indexdef LIKE '%printing_profile_id%')
    THEN RAISE EXCEPTION 'S10.03 FALHOU: indice with-printing ausente, sem predicado ou sem a coluna do perfil.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                    AND indexname='uq_cvir_job_card_type_bridge_legacy')
    THEN RAISE EXCEPTION 'S10.04 FALHOU: bridge de compatibilidade ausente. No GATE A ele PRECISA existir.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid='public.catalog_variant_import_row'::regclass
                      AND conname='ck_catalog_variant_import_row_printing_profile_shape')
    THEN RAISE EXCEPTION 'S10.05 FALHOU: CHECK de forma de printing_profile_id ausente.'; END IF;

    -- A constraint FINAL nao pode existir ainda: ela invalidaria as
    -- 5.653 linhas legadas. Ela e da PHASE E.
    IF EXISTS (SELECT 1 FROM pg_constraint
                WHERE conrelid='public.catalog_variant_import_row'::regclass
                  AND conname='ck_catalog_variant_import_row_valid_requires_printing_key')
    THEN RAISE EXCEPTION 'S10.06 FALHOU: a constraint final da PHASE E ja existe durante o GATE A.'; END IF;
END;
$s10$;

SELECT 'S10 H17/H18/H20 INDICES: 6 assercoes PASS' AS resumo;


-- =============================================================================
-- SECAO 11 — H17/H18/H19/H20 comportamental (v1.1)
--
-- v1.0 escolhia (job, card) por LIMIT 1 e fixava o Variant Type no codigo
-- 'STANDARD'. Isso NAO provava que a tripla
--     (job_id, card_id, variant_type_id)
-- estivesse livre no namespace BRIDGE. No dado real ela estava OCUPADA: o
-- par escolhido ja possuia uma row VALID com esse Variant Type e SEM a
-- chave de Impressao. O INSERT de SETUP colidiu com
-- uq_cvir_job_card_type_bridge_legacy e a Secao abortou antes de avaliar
-- qualquer assercao — falso FAIL por defeito de fixture.
--
-- v1.1 seleciona a tripla de forma DATA-INDEPENDENT: qualquer tripla
-- (job STAGED, card daquele job, Variant Type do mesmo Game) que nao
-- esteja ocupada em NENHUM dos tres namespaces. Nada e fixado por codigo.
-- Antes do primeiro INSERT ha uma PRECONDITION explicita — se a tripla
-- estiver ocupada, a Secao aborta com mensagem dedicada em vez de colidir
-- durante o setup. Isso impede regressao para o LIMIT 1 inseguro.
--
-- O incidente anterior NAO e convertido em PASS: as assercoes abaixo sao
-- avaliadas do zero.
-- =============================================================================
BEGIN;

DO $s11$
DECLARE
    v_game UUID; v_job UUID; v_card UUID; v_type UUID;
    v_profiles UUID[]; v_n BIGINT; v_ok BOOLEAN;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    IF v_game IS NULL THEN
        RAISE EXCEPTION 'S11.PRECONDITION FALHOU: Game POKEMON nao encontrado.';
    END IF;

    -- -------------------------------------------------------------------
    -- SELECAO DA TRIPLA — data-independent e deterministica.
    -- O NOT EXISTS testa (normalized_data ->> 'variant_type_id') sem
    -- filtrar pela forma da chave de Impressao, portanto exclui de uma vez
    -- os tres namespaces: BRIDGE (chave ausente), A ('null') e B ('string').
    -- O ORDER BY torna a escolha estavel entre execucoes.
    -- -------------------------------------------------------------------
    SELECT j.id, r.card_id, t.id
      INTO v_job, v_card, v_type
      FROM public.catalog_variant_import_job j
      JOIN public.catalog_variant_import_row r ON r.job_id = j.id
      JOIN public.card_set cs ON cs.id = j.card_set_id
      JOIN public.expansion e ON e.id = cs.expansion_id
      JOIN public.card_variant_type t ON t.game_id = e.game_id
     WHERE j.status = 'STAGED'
       AND e.game_id = v_game
       AND NOT EXISTS (
           SELECT 1 FROM public.catalog_variant_import_row x
            WHERE x.job_id = j.id
              AND x.card_id = r.card_id
              AND (x.normalized_data ->> 'variant_type_id') = t.id::TEXT)
     ORDER BY j.id, r.card_id, t.id
     LIMIT 1;

    IF v_job IS NULL THEN
        RAISE EXCEPTION 'S11.PRECONDITION FALHOU: nenhuma tripla (job STAGED, card, variant_type do mesmo Game) esta livre nos tres namespaces. H17/H18/H19/H20 NAO PODEM ser provadas nesta base — nao registrar como PASS.';
    END IF;

    -- Quatro perfis de Impressao distintos e ativos do Game, escolhidos
    -- por ordem estavel de codigo. Nenhum codigo fixado no harness.
    SELECT array_agg(p.id ORDER BY p.code) INTO v_profiles
      FROM (SELECT id, code FROM public.card_printing_profile
             WHERE game_id = v_game AND is_active
             ORDER BY code LIMIT 4) p;

    IF v_profiles IS NULL OR cardinality(v_profiles) <> 4 THEN
        RAISE EXCEPTION 'S11.PRECONDITION FALHOU: o Game nao tem 4 perfis de Impressao ativos (encontrados: %). A coexistencia de multiplos perfis NAO PODE ser provada — nao registrar como PASS.',
            COALESCE(cardinality(v_profiles), 0);
    END IF;

    -- -------------------------------------------------------------------
    -- REGRESSION GUARD DA FIXTURE — repete a checagem de forma explicita,
    -- namespace a namespace, imediatamente antes do primeiro INSERT.
    -- Se alguem reverter a selecao para o LIMIT 1 inseguro, esta guarda
    -- falha com mensagem propria em vez de colidir no setup.
    -- -------------------------------------------------------------------
    SELECT count(*) INTO v_n
      FROM public.catalog_variant_import_row x
     WHERE x.job_id = v_job AND x.card_id = v_card
       AND (x.normalized_data ->> 'variant_type_id') = v_type::TEXT
       AND jsonb_typeof(x.normalized_data -> 'printing_profile_id') IS NULL;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'S11.PRE-BRIDGE FALHOU: a tripla escolhida ja esta ocupada no namespace BRIDGE (% row(s)). A selecao da fixture regrediu.', v_n;
    END IF;

    SELECT count(*) INTO v_n
      FROM public.catalog_variant_import_row x
     WHERE x.job_id = v_job AND x.card_id = v_card
       AND (x.normalized_data ->> 'variant_type_id') = v_type::TEXT
       AND jsonb_typeof(x.normalized_data -> 'printing_profile_id') IN ('null','string');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'S11.PRE-AB FALHOU: a tripla escolhida ja esta ocupada nos namespaces A/B (% row(s)). A selecao da fixture regrediu.', v_n;
    END IF;

    -- -------------------------------------------------------------------
    -- H18 — namespace B: N variantes do MESMO (job, card, type) coexistem
    -- desde que o perfil difira.
    -- -------------------------------------------------------------------
    INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
    SELECT v_job, v_card,
           jsonb_build_object('harness', 'S11', 'slot', ord),
           jsonb_build_object('variant_type_id', v_type::TEXT,
                              'printing_profile_id', p::TEXT),
           'VALID'
      FROM unnest(v_profiles) WITH ORDINALITY AS u(p, ord);

    SELECT count(*) INTO v_n
      FROM public.catalog_variant_import_row x
     WHERE x.job_id = v_job AND x.card_id = v_card
       AND (x.normalized_data ->> 'variant_type_id') = v_type::TEXT
       AND jsonb_typeof(x.normalized_data -> 'printing_profile_id') = 'string';
    IF v_n <> 4 THEN
        RAISE EXCEPTION 'S11.01 FALHOU (H18): esperadas 4 variantes coexistindo no namespace B, encontradas %.', v_n;
    END IF;

    -- Duplicata EXATA de (job, card, type, profile) — tentativa deliberada.
    v_ok := FALSE;
    BEGIN
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
        VALUES (v_job, v_card, '{"harness":"S11","slot":"dup-B"}'::JSONB,
                jsonb_build_object('variant_type_id', v_type::TEXT,
                                   'printing_profile_id', v_profiles[1]::TEXT), 'VALID');
    EXCEPTION WHEN unique_violation THEN v_ok := TRUE;
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S11.02 FALHOU (H18): duplicata do mesmo (job, card, type, profile) foi aceita.';
    END IF;

    -- -------------------------------------------------------------------
    -- H17 — namespace A ('null' explicito) e DISJUNTO de B: a mesma tripla
    -- aceita uma row "sem Impressao" alem das 4 com perfil.
    -- -------------------------------------------------------------------
    INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
    VALUES (v_job, v_card, '{"harness":"S11","slot":"A"}'::JSONB,
            jsonb_build_object('variant_type_id', v_type::TEXT)
                || '{"printing_profile_id": null}'::JSONB, 'VALID');

    v_ok := FALSE;
    BEGIN
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
        VALUES (v_job, v_card, '{"harness":"S11","slot":"dup-A"}'::JSONB,
                jsonb_build_object('variant_type_id', v_type::TEXT)
                    || '{"printing_profile_id": null}'::JSONB, 'VALID');
    EXCEPTION WHEN unique_violation THEN v_ok := TRUE;
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S11.03 FALHOU (H17): duas rows "sem Impressao" para a mesma tripla foram aceitas.';
    END IF;

    -- -------------------------------------------------------------------
    -- H20 — BRIDGE: row com a chave AUSENTE (writer legado) e um terceiro
    -- namespace, disjunto de A e de B, e o bridge a protege.
    -- -------------------------------------------------------------------
    INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
    VALUES (v_job, v_card, '{"harness":"S11","slot":"bridge"}'::JSONB,
            jsonb_build_object('variant_type_id', v_type::TEXT), 'VALID');

    v_ok := FALSE;
    BEGIN
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
        VALUES (v_job, v_card, '{"harness":"S11","slot":"dup-bridge"}'::JSONB,
                jsonb_build_object('variant_type_id', v_type::TEXT), 'VALID');
    EXCEPTION WHEN unique_violation THEN v_ok := TRUE;
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S11.04 FALHOU (H20): o bridge nao protegeu o writer legado (duas rows sem a chave, mesma tripla).';
    END IF;

    -- -------------------------------------------------------------------
    -- H19 — a row key-absent NAO entra nos indices finais A/B. Prova pelo
    -- censo dos tres namespaces para a tripla: 4 em B, 1 em A, 1 no bridge.
    -- Se o bridge vazasse para A ou B, estas contagens mudariam.
    -- -------------------------------------------------------------------
    SELECT count(*) INTO v_n
      FROM public.catalog_variant_import_row x
     WHERE x.job_id = v_job AND x.card_id = v_card
       AND (x.normalized_data ->> 'variant_type_id') = v_type::TEXT
       AND jsonb_typeof(x.normalized_data -> 'printing_profile_id') = 'null';
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'S11.05 FALHOU (H19): esperada exatamente 1 row no namespace A, encontradas %.', v_n;
    END IF;

    SELECT count(*) INTO v_n
      FROM public.catalog_variant_import_row x
     WHERE x.job_id = v_job AND x.card_id = v_card
       AND (x.normalized_data ->> 'variant_type_id') = v_type::TEXT
       AND jsonb_typeof(x.normalized_data -> 'printing_profile_id') IS NULL;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'S11.06 FALHOU (H19): esperada exatamente 1 row no namespace BRIDGE, encontradas %.', v_n;
    END IF;

    SELECT count(*) INTO v_n
      FROM public.catalog_variant_import_row x
     WHERE x.job_id = v_job AND x.card_id = v_card
       AND (x.normalized_data ->> 'variant_type_id') = v_type::TEXT;
    IF v_n <> 6 THEN
        RAISE EXCEPTION 'S11.07 FALHOU (H19): esperadas 6 rows na tripla (4 B + 1 A + 1 bridge), encontradas %.', v_n;
    END IF;

    -- -------------------------------------------------------------------
    -- Forma da chave: valor nao-string e nao-null e recusado pelo CHECK.
    -- -------------------------------------------------------------------
    v_ok := FALSE;
    BEGIN
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
        VALUES (v_job, v_card, '{"harness":"S11","slot":"shape"}'::JSONB,
                jsonb_build_object('variant_type_id', v_type::TEXT,
                                   'printing_profile_id', 42), 'VALID');
    EXCEPTION WHEN check_violation THEN v_ok := TRUE;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S11.08 FALHOU: printing_profile_id numerico foi aceito.'; END IF;

    -- String que nao e UUID tambem e recusada.
    v_ok := FALSE;
    BEGIN
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
        VALUES (v_job, v_card, '{"harness":"S11","slot":"shape2"}'::JSONB,
                jsonb_build_object('variant_type_id', v_type::TEXT,
                                   'printing_profile_id', 'nao-e-uuid'), 'VALID');
    EXCEPTION WHEN check_violation THEN v_ok := TRUE;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S11.09 FALHOU: printing_profile_id string nao-UUID foi aceito.'; END IF;
END;
$s11$;

SELECT 'S11 H17/H18/H19/H20 (v1.1, fixture data-independent): 9 assercoes PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 12 — H25/H26: WRITER E MATCHING TRIPLO (source-level) · v2.3
--
-- v2.3 (STAGING-CORRECTION-04 §7): a Secao passa a provar o estado FINAL
-- da PHASE B, e nao apenas o estado pos-2178. A Query 2187 fecha a rota
-- de 5 argumentos removendo o DEFAULT NULL; sem a assercao S12.03 abaixo,
-- o harness daria PASS com a porta ainda destrancada.
-- =============================================================================
DO $s12$
DECLARE
    v_n INTEGER;
    v_nargs INTEGER;
    v_ndefaults INTEGER;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='internal' AND p.proname='write_card_variant';
    IF v_n <> 1 THEN RAISE EXCEPTION 'S12.01 FALHOU: % assinaturas de write_card_variant — esperada exatamente 1.', v_n; END IF;

    SELECT p.pronargs, p.pronargdefaults INTO v_nargs, v_ndefaults
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='internal' AND p.proname='write_card_variant';

    IF v_nargs <> 6 THEN
        RAISE EXCEPTION 'S12.02 FALHOU: write_card_variant tem % parametros, esperados 6.', v_nargs;
    END IF;

    -- ESTADO FINAL DA PHASE B (Query 2187). Enquanto houver default, a
    -- chamada de 5 argumentos continua compilando e um writer futuro que
    -- esqueca o perfil grava NULL SILENCIOSAMENTE — e NULL aqui nao e
    -- placeholder, e "sem perfil de impressao declarado".
    IF v_ndefaults <> 0 THEN
        RAISE EXCEPTION 'S12.03 FALHOU: write_card_variant ainda tem % parametro(s) com DEFAULT. A rota de 5 argumentos continua aberta — a Query 2187 nao foi aplicada.', v_ndefaults;
    END IF;

    -- H25/H26 — `=` nunca dispararia MATCHED para variante sem perfil.
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public' AND p.proname='admin_confirm_catalog_variant_import'
                      AND p.prosrc ILIKE '%printing_profile_id IS NOT DISTINCT FROM%')
    THEN RAISE EXCEPTION 'S12.04 FALHOU: o confirm nao usa IS NOT DISTINCT FROM — variantes sem perfil nunca dariam MATCHED.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public' AND p.proname='admin_confirm_catalog_variant_import'
                      AND p.prosrc ILIKE '%PRINTING_NOT_RESOLVED%')
    THEN RAISE EXCEPTION 'S12.05 FALHOU: o confirm nao recusa row com Printing nao resolvido.'; END IF;

    -- O confirm precisa REPASSAR o perfil ao writer, nao so conhece-lo.
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public' AND p.proname='admin_confirm_catalog_variant_import'
                      AND p.prosrc ILIKE '%write_card_variant%'
                      AND p.prosrc ILIKE '%v_printing_profile_id%')
    THEN RAISE EXCEPTION 'S12.06 FALHOU: o confirm nao repassa o perfil ao writer.'; END IF;

    -- B3 — o resolve de Variant Type precisa usar o residual.
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public' AND p.proname='admin_resolve_catalog_variant_import_mapping'
                      AND p.prosrc ILIKE '%compute_variant_residual_signature%')
    THEN RAISE EXCEPTION 'S12.07 FALHOU: o resolve de Variant Type nao usa a assinatura residual.'; END IF;
END;
$s12$;

SELECT 'S12 H25/H26 WRITER E MATCHING (v2.3, estado final Phase B): 7 assercoes PASS' AS resumo;


-- =============================================================================
-- SECAO 13 — H13: DUPLICATA DE TRAIT
--
-- Duas camadas, ambas provadas:
--   (a) ESTRUTURAL — a PK (mapping_id, trait_id) torna a duplicata
--       fisicamente impossivel, independentemente de quem escreve;
--   (b) CONTRATUAL — a RPC rejeita o payload com mensagem propria em
--       vez de colapsar silenciosamente o conjunto.
--
-- A camada (b) exige contexto de administrador. Impersona-se um admin
-- REAL ja existente; nenhuma linha de admin_user e criada. Sem admin
-- cadastrado, a Secao FALHA ALTO — nunca passa por omissao.
-- =============================================================================
BEGIN;

DO $s13$
DECLARE
    v_game UUID; v_src UUID; v_m UUID; v_sl UUID; v_msg TEXT; v_ok BOOLEAN;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_sl FROM public.card_printing_trait WHERE game_id=v_game AND code='SHADOWLESS';
    SELECT id INTO v_m FROM public.card_printing_external_mapping
     WHERE game_id=v_game AND raw_field='subtype' AND normalized_token='SHADOWLESS' AND is_active;

    -- (a) ESTRUTURAL.
    v_ok := FALSE;
    BEGIN
        INSERT INTO public.card_printing_external_mapping_trait (mapping_id, trait_id, game_id)
        VALUES (v_m, v_sl, v_game);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := TRUE;
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S13.01 FALHOU: par (mapping, trait) duplicado foi aceito.';
    END IF;
END;
$s13$;

DO $s13b$
DECLARE
    v_admin UUID; v_row UUID; v_game UUID; v_sl UUID; v_fe UUID;
    v_msg TEXT; v_ok BOOLEAN; r RECORD;
BEGIN
    SELECT id INTO v_admin FROM public.admin_user LIMIT 1;
    IF v_admin IS NULL THEN
        RAISE EXCEPTION 'S13.SETUP FALHOU: nenhum administrador cadastrado em admin_user. A camada contratual de H13 NAO PODE ser provada nesta base — nao registrar como PASS.';
    END IF;

    SELECT r2.id INTO v_row
      FROM public.catalog_variant_import_row r2
      JOIN public.catalog_variant_import_job j ON j.id = r2.job_id
     WHERE j.status = 'STAGED' AND r2.decision_status = 'PENDING'
     LIMIT 1;
    IF v_row IS NULL THEN
        RAISE EXCEPTION 'S13.SETUP FALHOU: nenhuma row STAGED/PENDING disponivel como origem editorial.';
    END IF;

    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_sl FROM public.card_printing_trait WHERE game_id=v_game AND code='SHADOWLESS';
    SELECT id INTO v_fe FROM public.card_printing_trait WHERE game_id=v_game AND code='FIRST_EDITION';

    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', v_admin::TEXT, 'role', 'authenticated')::TEXT,
                       true);

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'S13.SETUP FALHOU: a impersonacao de administrador nao surtiu efeito — is_admin() continua FALSE. NAO registrar como PASS.';
    END IF;

    -- (b) CONTRATUAL — duplicata explicita no payload.
    v_ok := FALSE;
    BEGIN
        SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
            v_row, 'stamp', 'harness-dup-token', ARRAY[v_sl, v_fe, v_sl]);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%DUPLICATE_TRAIT%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S13.02 FALHOU: a RPC aceitou (ou colapsou silenciosamente) trait duplicado no payload (msg: %).', COALESCE(v_msg, 'sem erro');
    END IF;

    -- Conjunto VAZIO tambem e rejeitado — mapeamento parcial nao existe.
    v_ok := FALSE;
    BEGIN
        SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
            v_row, 'stamp', 'harness-empty-token', ARRAY[]::UUID[]);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%EMPTY_TRAITS%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S13.03 FALHOU: a RPC aceitou conjunto de traits vazio (msg: %).', COALESCE(v_msg, 'sem erro');
    END IF;

    -- =====================================================================
    -- (v2.3) ORDEM DE VALIDACAO — o contrato do qual esta Secao depende.
    --
    -- Os tokens usados acima ('harness-dup-token', 'harness-empty-token')
    -- NAO existem na raw_data de v_row. A Query 2181 v1.2 introduziu o
    -- ORIGIN-ROW BINDING, que rejeitaria exatamente isso — se ele rodasse
    -- ANTES das validacoes puras de payload.
    --
    -- Ele nao roda. E esta assercao existe para que essa ordem nunca seja
    -- invertida por descuido: se algum dia o binding subir para antes do
    -- payload, as mensagens acima deixam de ser DUPLICATE_TRAIT /
    -- EMPTY_TRAITS e viram ORIGIN_TOKEN_NOT_FOUND — e S13.02/S13.03 falham
    -- alto, apontando a causa.
    --
    -- Prova direta: o mesmo payload invalido, agora com um token que
    -- TAMBEM nao existe na row, precisa continuar falhando por PAYLOAD.
    -- =====================================================================
    v_ok := FALSE;
    BEGIN
        SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
            v_row, 'subtype', 'harness-order-token', ARRAY[]::UUID[]);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%EMPTY_TRAITS%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S13.04 FALHOU (ORDEM): payload invalido deveria ser rejeitado ANTES de a origem ser consultada. Mensagem obtida: %. Se for ORIGIN_TOKEN_NOT_FOUND, o binding subiu para antes das validacoes puras de payload — inverter de volta.', COALESCE(v_msg, 'sem erro');
    END IF;
END;
$s13b$;

SELECT 'S13 H13 DUPLICATA DE TRAIT + ORDEM DE VALIDACAO: 4 assercoes PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 14 — H27 + REGRESSAO DIRETA DO BLOCKER B-01
--
-- Duas provas, uma transacao:
--
-- PARTE 1 — PROPAGACAO REAL (regressao do B-01).
--   Uma ratificacao editorial cria o mapping e propaga na MESMA transacao,
--   quando traits_signature ainda e NULL (selo deferido). Se a Query 2176
--   voltar a ler apenas a assinatura selada, a propagacao devolve
--   rows_revalidated = 0 SEM ERRO — e esta Secao FALHA.
--
--   Nao basta conferir que a RPC devolveu um mapping_id: a v1.0 do
--   harness fazia isso e teria passado com a propagacao vazia.
--
-- PARTE 2 — H27: a fronteira mais importante da frente. Corrigir um
--   mapping reavalia STAGING, nunca CATALOGO. Prova por diferenca de
--   CONJUNTOS nos dois sentidos, sem hash.
-- =============================================================================
BEGIN;

DO $s14$
DECLARE
    v_admin UUID; v_row UUID; v_game UUID; v_src UUID; v_fe UUID;
    v_unl_trait UUID; v_unl_profile UUID;
    v_vtem_id UUID; v_vtem_type TEXT; v_vtem_variant_type UUID;
    v_job UUID; v_card UUID; v_fix_row UUID;
    v_before BIGINT; v_after BIGINT; v_diff BIGINT;
    v_msg TEXT; r RECORD;
    v_status TEXT; v_vt TEXT; v_pp TEXT; v_pp_type TEXT;
    -- (v2.3 / B-08) fixture propria da PARTE 2.
    -- (v2.4 / B-09) identidade canonica PROPRIA da PARTE 2.
    v_repl_row UUID; v_repl_first UUID;
    v_repl_job UUID; v_repl_card UUID;
    v_n_active BIGINT; v_n_hist BIGINT;
BEGIN
    SELECT id INTO v_admin FROM public.admin_user LIMIT 1;
    IF v_admin IS NULL THEN
        RAISE EXCEPTION 'S14.SETUP FALHOU: nenhum administrador cadastrado em admin_user. H27 e a regressao do B-01 NAO PODEM ser provados nesta base — nao registrar como PASS.';
    END IF;

    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code='TCGDEX';
    SELECT id INTO v_fe   FROM public.card_printing_trait WHERE game_id=v_game AND code='FIRST_EDITION';
    SELECT id INTO v_unl_trait   FROM public.card_printing_trait   WHERE game_id=v_game AND code='UNLIMITED';
    SELECT id INTO v_unl_profile FROM public.card_printing_profile WHERE game_id=v_game AND code='UNLIMITED';

    IF v_unl_trait IS NULL OR v_unl_profile IS NULL THEN
        RAISE EXCEPTION 'S14.SETUP FALHOU: trait/profile UNLIMITED da seed do Printing Model nao encontrados.';
    END IF;

    -- Snapshot do catalogo ANTES de qualquer coisa (PARTE 2).
    CREATE TEMP TABLE harness_cv_before AS
        SELECT id, card_id, variant_type_id, printing_profile_id, variant_order, is_default
          FROM public.card_variant;

    SELECT count(*) INTO v_before FROM harness_cv_before;

    -- =====================================================================
    -- FIXTURE DA PARTE 1
    --
    -- O residual precisa casar com um mapping de Variant Type REAL. Em vez
    -- de supor que existe um para (NORMAL, -, -, {}), derivamos o raw_data
    -- de um mapping existente cuja assinatura seja so `type`. Assim, ao
    -- consumir o token de Impressao, o residual volta a ser exatamente a
    -- assinatura desse mapping.
    -- =====================================================================
    SELECT vm.id, vm.external_type, vm.variant_type_id
      INTO v_vtem_id, v_vtem_type, v_vtem_variant_type
      FROM public.card_variant_type_external_mapping vm
     WHERE vm.game_id = v_game
       AND vm.asset_source_id = v_src
       AND vm.normalized_foil IS NULL
       AND vm.normalized_subtype IS NULL
       AND COALESCE(cardinality(vm.normalized_stamp), 0) = 0
     LIMIT 1;

    IF v_vtem_id IS NULL THEN
        RAISE EXCEPTION 'S14.SETUP FALHOU: nenhum mapping de Variant Type com assinatura apenas de type. A prova de propagacao nao pode ser montada sem inventar dado.';
    END IF;

    -- =====================================================================
    -- SELECAO DA IDENTIDADE FINAL (v2.3 / B-07)
    --
    -- A v2.2 escolhia (job, card) por LIMIT 1 e derivava o Variant Type de
    -- OUTRO LIMIT 1 independente. O comentario dizia que a row "fica fora
    -- dos tres indices" — verdade no instante do INSERT, porque
    -- normalized_data nasce vazio. Mas depois da PROPAGACAO ela recebe
    -- variant_type_id E printing_profile_id, e entra no namespace B com a
    -- identidade
    --
    --     (job_id, card_id, variant_type_id, printing_profile_id)
    --
    -- que NUNCA foi provada livre. Isso e exatamente a classe de defeito
    -- da S11 v1.0, deslocada para depois da propagacao: hoje nao colide
    -- so porque o namespace B esta vazio — sorte do baseline, nao prova.
    --
    -- A v2.3 escolhe o par (job, card) por NOT EXISTS contra a identidade
    -- FINAL que a propagacao vai produzir, com ORDER BY deterministico.
    -- O Variant Type e o perfil ja sao conhecidos aqui (v_vtem_variant_type
    -- e v_unl_profile), entao a identidade completa e verificavel ANTES.
    -- =====================================================================
    SELECT j.id, r2.card_id INTO v_job, v_card
      FROM public.catalog_variant_import_job j
      JOIN public.catalog_variant_import_row r2 ON r2.job_id = j.id
     WHERE j.status = 'STAGED' AND j.source = 'TCGDEX'
       AND NOT EXISTS (
           SELECT 1 FROM public.catalog_variant_import_row x
            WHERE x.job_id = j.id
              AND x.card_id = r2.card_id
              AND (x.normalized_data ->> 'variant_type_id') = v_vtem_variant_type::TEXT
       )
     ORDER BY j.id, r2.card_id
     LIMIT 1;

    IF v_job IS NULL THEN
        RAISE EXCEPTION 'S14.SETUP FALHOU: nenhum par (job STAGED/TCGDEX, card) tem a identidade final livre para o Variant Type %. A prova de propagacao NAO PODE ser montada sem risco de colisao — nao registrar como PASS.', v_vtem_variant_type;
    END IF;

    -- PRECONDITION EXPLICITA — reconfirma a identidade FINAL completa,
    -- incluindo o perfil que a propagacao vai gravar, imediatamente antes
    -- da RPC. Se alguem reverter a selecao acima para o LIMIT 1 inseguro,
    -- esta guarda falha com mensagem propria em vez de colidir.
    IF EXISTS (
        SELECT 1 FROM public.catalog_variant_import_row x
         WHERE x.job_id = v_job
           AND x.card_id = v_card
           AND (x.normalized_data ->> 'variant_type_id') = v_vtem_variant_type::TEXT
           AND ((x.normalized_data ->> 'printing_profile_id') = v_unl_profile::TEXT
                OR jsonb_typeof(x.normalized_data -> 'printing_profile_id') IS NULL)
    ) THEN
        RAISE EXCEPTION 'S14.PRE FALHOU (B-07): a identidade final (job, card, variant_type, printing_profile) que a propagacao vai produzir JA esta ocupada. A selecao da fixture regrediu.';
    END IF;

    -- Row alvo: normalized_data VAZIO -> no instante do INSERT ela fica
    -- fora dos tres indices de identidade. A identidade FINAL, pos
    -- propagacao, foi provada livre acima.
    INSERT INTO public.catalog_variant_import_row
        (job_id, card_id, raw_data, normalized_data, validation_status, decision_status)
    VALUES (v_job, v_card,
            jsonb_build_object('type', v_vtem_type,
                               'stamp', jsonb_build_array('harness-token-s14')),
            '{}'::JSONB, 'NEEDS_REVIEW', 'PENDING')
    RETURNING id INTO v_fix_row;

    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', v_admin::TEXT, 'role', 'authenticated')::TEXT,
                       true);

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'S14.SETUP FALHOU: impersonacao de administrador sem efeito. NAO registrar como PASS.';
    END IF;

    -- =====================================================================
    -- PARTE 1 — RATIFICACAO REAL. O mapping nasce e propaga aqui, com
    -- traits_signature ainda NULL. Este e o caminho do B-01.
    -- =====================================================================
    SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
        v_fix_row, 'stamp', 'harness-token-s14', ARRAY[v_unl_trait]);

    IF r.mapping_id IS NULL THEN
        RAISE EXCEPTION 'S14.01 FALHOU: a ratificacao nao devolveu mapping_id.';
    END IF;

    IF r.rows_updated IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'S14.02 FALHOU (REGRESSAO B-01): rows_revalidated = %, esperado 1. O mapping foi criado mas NADA foi propagado. Quase certamente a Query 2176 voltou a ler apenas traits_signature, que ainda e NULL antes do selo deferido.', COALESCE(r.rows_updated, -1);
    END IF;

    IF r.jobs_affected IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'S14.03 FALHOU: jobs_affected = %, esperado 1.', COALESCE(r.jobs_affected, -1);
    END IF;

    IF r.rows_still_pending IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'S14.04 FALHOU: % row(s) atingidas ficaram sem resolucao.', r.rows_still_pending;
    END IF;

    -- A row foi de fato RECALCULADA — nao basta o contador.
    SELECT r2.validation_status,
           r2.normalized_data ->> 'variant_type_id',
           r2.normalized_data ->> 'printing_profile_id',
           jsonb_typeof(r2.normalized_data -> 'printing_profile_id')
      INTO v_status, v_vt, v_pp, v_pp_type
      FROM public.catalog_variant_import_row r2
     WHERE r2.id = v_fix_row;

    IF v_status IS DISTINCT FROM 'VALID' THEN
        RAISE EXCEPTION 'S14.05 FALHOU: a row atingida continua em % apos a ratificacao.', COALESCE(v_status, '<nulo>');
    END IF;

    IF v_pp_type IS DISTINCT FROM 'string' OR v_pp IS DISTINCT FROM v_unl_profile::TEXT THEN
        RAISE EXCEPTION 'S14.06 FALHOU: printing_profile_id final = % (tipo %), esperado o perfil UNLIMITED (%).',
            COALESCE(v_pp, '<ausente>'), COALESCE(v_pp_type, '<ausente>'), v_unl_profile;
    END IF;

    IF v_vt IS DISTINCT FROM v_vtem_variant_type::TEXT THEN
        RAISE EXCEPTION 'S14.07 FALHOU: variant_type_id residual = %, esperado % (o mapping de acabamento do proprio type). O residual foi corrompido pelo consumo do token de Impressao.',
            COALESCE(v_vt, '<ausente>'), v_vtem_variant_type;
    END IF;

    -- =====================================================================
    -- PARTE 2 — NO_CHANGE E SUBSTITUICAO (v2.3 / B-05 e B-08)
    --
    -- A v2.2 reusava v_fix_row (cuja raw_data.stamp e ['harness-token-s14'])
    -- para chamadas referentes a '1st-edition' — token que NAO existe nessa
    -- row. Com o ORIGIN-ROW BINDING da Query 2181 v1.2 isso passa a ser
    -- rejeitado, CORRETAMENTE. A RPC nao vai ser enfraquecida para
    -- acomodar o harness: a fixture e que muda.
    --
    -- v2.3: fixture PROPRIA, com o token sintetico HARNESS-S14-REPLACE
    -- presente EXPLICITAMENTE na raw_data da row de origem. O mapping real
    -- de 1ST-EDITION deixa de ser tocado — ele e dado ratificado da seed.
    --
    -- Esta parte prova B-05 DIRETAMENTE: as tres chamadas acontecem na
    -- MESMA transacao, ou seja, o mapping criado na primeira ainda esta
    -- com traits_signature NULL (selo deferido) quando a segunda pergunta
    -- "isso mudou?". Se a RPC voltar a ler a assinatura crua, o NO_CHANGE
    -- nao dispara e S14.09 FALHA.
    --
    -- -------------------------------------------------------------------
    -- IDENTIDADE CANONICA PROPRIA (v2.4 / B-09)
    --
    -- A v2.3 reusava v_job e v_card da PARTE 1. Mas a PARTE 1 termina com
    -- a identidade
    --
    --     (v_job, v_card, v_vtem_variant_type, v_unl_profile)
    --
    -- OCUPADA por v_fix_row. A PARTE 2 usa o MESMO v_vtem_type no raw_data
    -- e a MESMA composicao A (UNLIMITED), entao a sua primeira propagacao
    -- produziria exatamente essa mesma tripla+perfil — colisao no namespace
    -- B, dentro da propria transacao, transformando a fixture em FALSO FAIL.
    --
    -- A PARTE 2 passa a ter par (job, card) proprio, escolhido por
    -- NOT EXISTS contra a identidade final da composicao A. Como esta
    -- selecao roda DEPOIS da PARTE 1, a linha dela ja esta materializada e
    -- o par da PARTE 1 e excluido automaticamente — sem precisar cita-lo.
    -- -------------------------------------------------------------------
    SELECT j.id, r2.card_id INTO v_repl_job, v_repl_card
      FROM public.catalog_variant_import_job j
      JOIN public.catalog_variant_import_row r2 ON r2.job_id = j.id
     WHERE j.status = 'STAGED' AND j.source = 'TCGDEX'
       AND NOT EXISTS (
           SELECT 1 FROM public.catalog_variant_import_row x
            WHERE x.job_id = j.id
              AND x.card_id = r2.card_id
              AND (x.normalized_data ->> 'variant_type_id') = v_vtem_variant_type::TEXT)
     ORDER BY j.id, r2.card_id
     LIMIT 1;

    IF v_repl_job IS NULL THEN
        RAISE EXCEPTION 'S14.SETUP-P2 FALHOU (B-09): nenhum par (job STAGED/TCGDEX, card) tem a identidade final livre para o Variant Type % apos a PARTE 1. A prova de NO_CHANGE/substituicao nao pode ser montada sem colidir — nao registrar como PASS.', v_vtem_variant_type;
    END IF;

    -- A identidade da PARTE 2 tem que ser DIFERENTE da que a PARTE 1
    -- acabou de ocupar. Se for a mesma, o NOT EXISTS acima nao esta vendo
    -- a linha da PARTE 1 — premissa quebrada, aborta.
    IF v_repl_job = v_job AND v_repl_card = v_card THEN
        RAISE EXCEPTION 'S14.SETUP-P2 FALHOU (B-09): a PARTE 2 selecionou o MESMO par (job, card) da PARTE 1, que ja ocupa a identidade final. A selecao data-independent regrediu.';
    END IF;

    -- PRECONDITION EXPLICITA, imediatamente antes da primeira RPC da
    -- PARTE 2: a identidade final completa que a composicao A vai produzir
    -- precisa estar livre.
    IF EXISTS (
        SELECT 1 FROM public.catalog_variant_import_row x
         WHERE x.job_id = v_repl_job
           AND x.card_id = v_repl_card
           AND (x.normalized_data ->> 'variant_type_id') = v_vtem_variant_type::TEXT
           AND ((x.normalized_data ->> 'printing_profile_id') = v_unl_profile::TEXT
                OR jsonb_typeof(x.normalized_data -> 'printing_profile_id') IS NULL)
    ) THEN
        RAISE EXCEPTION 'S14.PRE-P2 FALHOU (B-09): a identidade final da PARTE 2 (job, card, variant_type, printing_profile) ja esta ocupada.';
    END IF;
    -- =====================================================================
    INSERT INTO public.catalog_variant_import_row
        (job_id, card_id, raw_data, normalized_data, validation_status, decision_status)
    VALUES (v_repl_job, v_repl_card,
            jsonb_build_object('harness', 'S14',
                               'type', v_vtem_type,
                               'stamp', jsonb_build_array('harness-s14-replace')),
            '{}'::JSONB, 'NEEDS_REVIEW', 'PENDING')
    RETURNING id INTO v_repl_row;

    -- (1) Cria o mapping do token sintetico com a composicao A.
    SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
        v_repl_row, 'stamp', 'harness-s14-replace', ARRAY[v_unl_trait]);

    IF r.mapping_id IS NULL THEN
        RAISE EXCEPTION 'S14.08 FALHOU: a criacao do mapping sintetico nao devolveu mapping_id.';
    END IF;
    v_repl_first := r.mapping_id;

    -- O selo e DEFERIDO: dentro desta transacao a assinatura ainda e NULL.
    -- Se nao for, o contrato temporal mudou e a prova de B-05 seria vazia.
    IF (SELECT m.traits_signature FROM public.card_printing_external_mapping m
         WHERE m.id = v_repl_first) IS NOT NULL THEN
        RAISE EXCEPTION 'S14.PRE-B05 FALHOU: traits_signature ja preenchida antes do COMMIT — o selo deixou de ser DEFERIDO e a prova de B-05 nao teria valor.';
    END IF;

    -- (2) MESMA composicao, MESMA transacao, ANTES do selo -> NO_CHANGE.
    BEGIN
        SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
            v_repl_row, 'stamp', 'harness-s14-replace', ARRAY[v_unl_trait]);
        RAISE EXCEPTION 'S14.09 FALHOU (REGRESSAO B-05): a RPC aceitou substituir por composicao IDENTICA antes do selo diferido. Quase certamente o guard de NO_CHANGE voltou a ler traits_signature crua, que ainda e NULL.';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg LIKE 'S14.09 FALHOU%' THEN RAISE; END IF;
        IF v_msg NOT LIKE '%NO_CHANGE%' THEN
            RAISE EXCEPTION 'S14.10 FALHOU: erro inesperado na chamada de no-op (msg: %).', v_msg;
        END IF;
    END;

    -- (3) Composicao B, diferente -> substituicao LEGITIMA.
    SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
        v_repl_row, 'stamp', 'harness-s14-replace', ARRAY[v_unl_trait, v_fe]);

    IF r.mapping_id IS NULL THEN
        RAISE EXCEPTION 'S14.11 FALHOU: a substituicao legitima nao devolveu mapping_id.';
    END IF;
    IF r.superseded_mapping_id IS DISTINCT FROM v_repl_first THEN
        RAISE EXCEPTION 'S14.12 FALHOU: supersedes_mapping_id = %, esperado % (o mapping criado no passo 1).',
            COALESCE(r.superseded_mapping_id::TEXT, '<nulo>'), v_repl_first;
    END IF;

    -- Exatamente 1 ACTIVE para o token, e o historico preservado.
    SELECT count(*) INTO v_n_active
      FROM public.card_printing_external_mapping m
     WHERE m.game_id = v_game AND m.raw_field = 'stamp'
       AND m.normalized_token = 'HARNESS-S14-REPLACE' AND m.is_active;
    IF v_n_active <> 1 THEN
        RAISE EXCEPTION 'S14.13 FALHOU: % mapping(s) ACTIVE para o token sintetico, esperado exatamente 1.', v_n_active;
    END IF;

    SELECT count(*) INTO v_n_hist
      FROM public.card_printing_external_mapping m
     WHERE m.game_id = v_game AND m.raw_field = 'stamp'
       AND m.normalized_token = 'HARNESS-S14-REPLACE';
    IF v_n_hist <> 2 THEN
        RAISE EXCEPTION 'S14.14 FALHOU: % mapping(s) historicos para o token sintetico, esperados 2 (predecessor aposentado + sucessor ativo).', v_n_hist;
    END IF;

    IF (SELECT m.is_active FROM public.card_printing_external_mapping m
         WHERE m.id = v_repl_first) IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'S14.15 FALHOU: o predecessor nao foi aposentado.';
    END IF;

    -- O mapping REAL de 1ST-EDITION nao foi tocado por nada disto.
    IF (SELECT count(*) FROM public.card_printing_external_mapping m
         WHERE m.game_id = v_game AND m.raw_field = 'stamp'
           AND m.normalized_token = '1ST-EDITION') <> 1 THEN
        RAISE EXCEPTION 'S14.16 FALHOU: o mapping real de 1ST-EDITION foi alterado pela prova de substituicao.';
    END IF;

    -- H27 — CATALOGO INTACTO, nos dois sentidos.
    SELECT count(*) INTO v_after FROM public.card_variant;
    IF v_after <> v_before THEN
        RAISE EXCEPTION 'S14.17 FALHOU: card_variant passou de % para % linhas.', v_before, v_after;
    END IF;

    SELECT count(*) INTO v_diff FROM (
        SELECT id, card_id, variant_type_id, printing_profile_id, variant_order, is_default
          FROM public.card_variant
        EXCEPT
        SELECT id, card_id, variant_type_id, printing_profile_id, variant_order, is_default
          FROM harness_cv_before
    ) a;
    IF v_diff <> 0 THEN
        RAISE EXCEPTION 'S14.18 FALHOU: % linha(s) de card_variant foram criadas ou alteradas pela substituicao de routing.', v_diff;
    END IF;

    SELECT count(*) INTO v_diff FROM (
        SELECT id, card_id, variant_type_id, printing_profile_id, variant_order, is_default
          FROM harness_cv_before
        EXCEPT
        SELECT id, card_id, variant_type_id, printing_profile_id, variant_order, is_default
          FROM public.card_variant
    ) b;
    IF v_diff <> 0 THEN
        RAISE EXCEPTION 'S14.19 FALHOU: % linha(s) de card_variant desapareceram ou foram alteradas.', v_diff;
    END IF;

    DROP TABLE harness_cv_before;
END;
$s14$;

SELECT 'S14 v2.3 PROPAGACAO REAL (B-01) + NO_CHANGE PRE-SELO (B-05) + H27: 19 assercoes PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 15 — H21 + H22 (contrato, transacional)
--
-- H21 e a PRECONDICAO da Query 2183. Ela e medida sobre dados REAIS,
-- agora, sem depender de deploy nenhum.
--
-- H22-contrato: o backfill da 2183 e simulado dentro de BEGIN/ROLLBACK
-- e a reconciliacao e verificada. Isso NAO substitui H22 real (S23),
-- mas prova o contrato antes de qualquer escrita definitiva.
-- =============================================================================
BEGIN;

DO $s15$
DECLARE
    v_valid BIGINT; v_offenders BIGINT; v_absent BIGINT;
    v_needs_review BIGINT; v_needs_review_after BIGINT;
BEGIN
    SELECT count(*) INTO v_valid
      FROM public.catalog_variant_import_row WHERE validation_status='VALID';

    -- Baseline ratificado. Se mudou, H21 esta sendo medida sobre outro
    -- universo e o resultado nao pode ser lido como a mesma garantia.
    IF v_valid <> 5653 THEN
        RAISE EXCEPTION 'S15.00 FALHOU: baseline VALID = %, esperado 5653. Reauditar antes de prosseguir.', v_valid;
    END IF;

    SELECT count(*) INTO v_needs_review
      FROM public.catalog_variant_import_row WHERE validation_status='NEEDS_REVIEW';

    -- H21 — nenhuma VALID pode conter token de Impressao ratificado.
    -- Este e EXATAMENTE o guard da 2183, executado como assercao.
    SELECT count(*) INTO v_offenders
      FROM public.catalog_variant_import_row r
     WHERE r.validation_status = 'VALID'
       AND (
            public.normalize_external_catalog_value(r.raw_data ->> 'subtype')
                IN ('SHADOWLESS', 'UNLIMITED', '1999-2000-COPYRIGHT', 'SHADOWLESS-RED-CHEEK')
            OR (
                jsonb_typeof(r.raw_data -> 'stamp') = 'array'
                AND EXISTS (
                    SELECT 1 FROM jsonb_array_elements_text(r.raw_data -> 'stamp') e
                     WHERE public.normalize_external_catalog_value(e) = '1ST-EDITION'
                )
            )
       );

    IF v_offenders <> 0 THEN
        RAISE EXCEPTION 'S15.01 FALHOU (H21): % row(s) VALID contem token de Impressao ratificado. A Query 2183 NAO pode rodar — essas linhas nao sao "sem perfil".', v_offenders;
    END IF;

    -- Prova independente da premissa: nenhum mapping de Variant Type
    -- consome subtype ou o stamp 1ST-EDITION.
    IF EXISTS (
        SELECT 1 FROM public.card_variant_type_external_mapping
         WHERE COALESCE(normalized_subtype, '') <> ''
            OR '1ST-EDITION' = ANY (COALESCE(normalized_stamp, '{}'::TEXT[]))
    ) THEN
        RAISE EXCEPTION 'S15.02 FALHOU (H21): existe mapping de Variant Type consumindo subtype ou 1ST-EDITION. O roteamento mudaria a semantica de mappings ja ratificados.';
    END IF;

    -- H22-contrato — simula o backfill e verifica a reconciliacao.
    UPDATE public.catalog_variant_import_row r
       SET normalized_data = jsonb_set(r.normalized_data, '{printing_profile_id}', 'null'::JSONB, true)
     WHERE r.validation_status = 'VALID'
       AND (r.normalized_data ->> 'variant_type_id') IS NOT NULL
       AND jsonb_typeof(r.normalized_data -> 'printing_profile_id') IS NULL;

    SELECT count(*) INTO v_absent
      FROM public.catalog_variant_import_row r
     WHERE r.validation_status = 'VALID'
       AND jsonb_typeof(r.normalized_data -> 'printing_profile_id') IS NULL;

    IF v_absent <> 0 THEN
        RAISE EXCEPTION 'S15.03 FALHOU (H22-contrato): apos o backfill simulado, % row(s) VALID continuam sem a chave. Existe VALID sem variant_type_id resolvido — o WHERE do backfill nao as alcanca.', v_absent;
    END IF;

    -- A constraint final PODERIA ser validada neste estado.
    IF EXISTS (
        SELECT 1 FROM public.catalog_variant_import_row
         WHERE validation_status = 'VALID'
           AND NOT (normalized_data ? 'printing_profile_id')
    ) THEN
        RAISE EXCEPTION 'S15.04 FALHOU: a constraint final da PHASE E nao validaria neste estado.';
    END IF;

    -- As NEEDS_REVIEW nao foram tocadas pelo backfill.
    SELECT count(*) INTO v_needs_review_after
      FROM public.catalog_variant_import_row WHERE validation_status='NEEDS_REVIEW';

    IF v_needs_review_after <> v_needs_review THEN
        RAISE EXCEPTION 'S15.05 FALHOU: o backfill alterou a contagem de NEEDS_REVIEW (% -> %).', v_needs_review, v_needs_review_after;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.catalog_variant_import_row
         WHERE validation_status = 'NEEDS_REVIEW'
           AND normalized_data ? 'printing_profile_id'
    ) THEN
        RAISE EXCEPTION 'S15.06 FALHOU: o backfill deu a chave a alguma linha NEEDS_REVIEW. Elas devem ser reavaliadas pelo routing, nao declaradas "sem perfil".';
    END IF;

    RAISE NOTICE 'S15: VALID=% NEEDS_REVIEW=%', v_valid, v_needs_review;
END;
$s15$;

SELECT 'S15 H21 + H22-contrato: 6 assercoes PASS' AS resumo,
       (SELECT count(*) FROM public.catalog_variant_import_row WHERE validation_status='VALID')         AS valid_rows,
       (SELECT count(*) FROM public.catalog_variant_import_row WHERE validation_status='NEEDS_REVIEW')  AS needs_review_rows;

ROLLBACK;


-- =============================================================================
-- SECAO 16 — H23: BASE1 410/410
--
-- Teste do RESOLVEDOR contra dados que JA EXISTEM. Nao depende de
-- deploy. Toda row NEEDS_REVIEW de BASE1 tem que resolver — Printing E
-- Variant Type — quando passada pelo roteamento.
-- =============================================================================
DO $s16$
DECLARE
    v_game UUID; v_src UUID;
    v_total BIGINT; v_printing_ok BIGINT; v_fully_ok BIGINT; v_profiles BIGINT;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code='TCGDEX';

    CREATE TEMP TABLE harness_base1 AS
        SELECT r.id, r.raw_data, s.*
          FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          JOIN public.card_set cs ON cs.id = j.card_set_id
          CROSS JOIN LATERAL internal.compute_variant_residual_signature(
              r.raw_data, v_game, v_src) s
         WHERE cs.code = 'BASE1'
           AND r.validation_status = 'NEEDS_REVIEW';

    SELECT count(*) INTO v_total FROM harness_base1;

    IF v_total <> 410 THEN
        RAISE EXCEPTION 'S16.01 FALHOU (H23): BASE1 tem % rows NEEDS_REVIEW, esperadas 410. O baseline mudou — reauditar antes de prosseguir.', v_total;
    END IF;

    SELECT count(*) INTO v_printing_ok FROM harness_base1
     WHERE printing_state IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE');

    IF v_printing_ok <> 410 THEN
        RAISE EXCEPTION 'S16.02 FALHOU (H23): apenas % de 410 rows de BASE1 tiveram a Impressao resolvida.', v_printing_ok;
    END IF;

    -- Resolucao COMPLETA: Printing resolvido E Variant Type encontrado
    -- para o residual. E isso que produz VALID.
    SELECT count(*) INTO v_fully_ok
      FROM harness_base1 t
      JOIN public.card_variant_type_external_mapping vm
        ON vm.game_id = v_game
       AND vm.asset_source_id = v_src
       AND vm.normalized_type = t.residual_type
       AND COALESCE(vm.normalized_foil, '')    = COALESCE(t.residual_foil, '')
       AND COALESCE(vm.normalized_subtype, '') = COALESCE(t.residual_subtype, '')
       AND COALESCE(vm.normalized_stamp, '{}'::TEXT[]) = COALESCE(t.residual_stamp, '{}'::TEXT[])
     WHERE t.printing_state IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE');

    IF v_fully_ok <> 410 THEN
        RAISE EXCEPTION 'S16.03 FALHOU (H23): apenas % de 410 rows de BASE1 resolveriam para VALID (Printing + Variant Type).', v_fully_ok;
    END IF;

    -- Os perfis usados tem que ser os da seed — nenhum perfil novo.
    SELECT count(DISTINCT printing_profile_id) INTO v_profiles
      FROM harness_base1 WHERE printing_profile_id IS NOT NULL;

    IF v_profiles = 0 THEN
        RAISE EXCEPTION 'S16.04 FALHOU (H23): nenhuma row de BASE1 resolveu para um perfil de Impressao. Se BASE1 nao tem Impressao, a premissa da frente inteira esta errada.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM harness_base1 t
         WHERE t.printing_profile_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM public.card_printing_profile p
                            WHERE p.id = t.printing_profile_id AND p.game_id = v_game AND p.is_active)
    ) THEN
        RAISE EXCEPTION 'S16.05 FALHOU (H23): BASE1 resolveu para perfil inexistente, de outro Game ou inativo.';
    END IF;

    -- Nenhuma row de BASE1 pode restar em NEEDS_REVIEW *por causa da
    -- Impressao*. S16.02 conta os estados RESOLVED_*; esta assercao fecha
    -- o complemento de forma explicita, para que um estado NEEDS_REVIEW
    -- novo (ex.: INVALID_PRINTING_MAPPING) nao passe despercebido.
    IF EXISTS (SELECT 1 FROM harness_base1 WHERE printing_state LIKE 'NEEDS_REVIEW%') THEN
        RAISE EXCEPTION 'S16.06 FALHOU (H23): existe row de BASE1 em NEEDS_REVIEW residual por Impressao.';
    END IF;

    DROP TABLE harness_base1;
END;
$s16$;

SELECT 'S16 H23 BASE1 410/410: 6 assercoes PASS' AS resumo;


-- =============================================================================
-- SECAO 17 — H24: BASEP/SVE/SV5 — AS 95 OUTRAS INTACTAS
--
-- "Intactas" tem significado preciso: o roteamento de Impressao NAO
-- pode mexer nelas. Elas continuam NEEDS_REVIEW pelo mesmo motivo de
-- antes (Variant Type desconhecido), e nenhum token delas e consumido
-- como Impressao.
-- =============================================================================
DO $s17$
DECLARE
    v_game UUID; v_src UUID;
    v_total BIGINT; v_touched BIGINT; v_resolvable BIGINT; v_err BIGINT;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code='TCGDEX';

    CREATE TEMP TABLE harness_others AS
        SELECT r.id, cs.code AS set_code, r.raw_data, s.*
          FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          JOIN public.card_set cs ON cs.id = j.card_set_id
          CROSS JOIN LATERAL internal.compute_variant_residual_signature(
              r.raw_data, v_game, v_src) s
         WHERE cs.code <> 'BASE1'
           AND r.validation_status = 'NEEDS_REVIEW';

    SELECT count(*) INTO v_total FROM harness_others;

    IF v_total <> 95 THEN
        RAISE EXCEPTION 'S17.01 FALHOU (H24): fora de BASE1 existem % rows NEEDS_REVIEW, esperadas 95. O baseline mudou — reauditar.', v_total;
    END IF;

    -- Nenhuma delas pode ter token de Impressao consumido.
    SELECT count(*) INTO v_touched FROM harness_others
     WHERE printing_state <> 'RESOLVED_NO_PRINTING';

    IF v_touched <> 0 THEN
        RAISE EXCEPTION 'S17.02 FALHOU (H24): % das 95 rows fora de BASE1 tiveram token consumido/bloqueado pelo roteamento de Impressao. Elas deveriam ser inertes a esta frente.', v_touched;
    END IF;

    -- E nenhuma passa a resolver: o motivo do NEEDS_REVIEW delas
    -- continua sendo Variant Type, nao Impressao.
    SELECT count(*) INTO v_resolvable
      FROM harness_others t
      JOIN public.card_variant_type_external_mapping vm
        ON vm.game_id = v_game
       AND vm.asset_source_id = v_src
       AND vm.normalized_type = t.residual_type
       AND COALESCE(vm.normalized_foil, '')    = COALESCE(t.residual_foil, '')
       AND COALESCE(vm.normalized_subtype, '') = COALESCE(t.residual_subtype, '')
       AND COALESCE(vm.normalized_stamp, '{}'::TEXT[]) = COALESCE(t.residual_stamp, '{}'::TEXT[]);

    IF v_resolvable <> 0 THEN
        RAISE EXCEPTION 'S17.03 FALHOU (H24): % das 95 rows passariam a resolver so pelo roteamento. Isso muda o escopo da frente sem decisao editorial.', v_resolvable;
    END IF;

    -- Prova nominal: 1ST-EDITION-ERROR continua no residual, ou seja,
    -- 1ST-EDITION-ERROR <> 1ST-EDITION. Guard de nao-vacuidade primeiro:
    -- se o corpus nao tiver nenhuma ocorrencia, a assercao seguinte
    -- passaria por vazio e nao provaria nada.
    SELECT count(*) INTO v_err
      FROM harness_others WHERE raw_data::TEXT ILIKE '%1st-edition-error%';
    IF v_err = 0 THEN
        RAISE EXCEPTION 'S17.04 FALHOU (H24): nenhuma row com 1st-edition-error no corpus — a prova nominal seria vacua. Nao registrar como PASS.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM harness_others
         WHERE raw_data::TEXT ILIKE '%1st-edition-error%'
           AND NOT ('1ST-EDITION-ERROR' = ANY (COALESCE(residual_stamp, '{}'::TEXT[])))
    ) THEN
        RAISE EXCEPTION 'S17.05 FALHOU (H24): alguma row com 1st-edition-error teve o token consumido.';
    END IF;

    DROP TABLE harness_others;
END;
$s17$;

SELECT 'S17 H24 OUTRAS 95 INTACTAS: 5 assercoes PASS' AS resumo;


-- =============================================================================
-- SECAO 18 — H28: SEGURANCA / LEAST PRIVILEGE
-- =============================================================================
DO $s18$
DECLARE
    v_n INTEGER;
BEGIN
    SELECT count(*) INTO v_n FROM information_schema.role_table_grants
     WHERE grantee='service_role' AND table_schema='public'
       AND table_name IN ('card_printing_external_mapping','card_printing_trait','card_printing_profile')
       AND privilege_type='SELECT';
    IF v_n <> 3 THEN RAISE EXCEPTION 'S18.01 FALHOU: service_role tem SELECT em apenas % das 3 tabelas necessarias.', v_n; END IF;

    IF EXISTS (SELECT 1 FROM information_schema.role_table_grants
                WHERE grantee='service_role' AND table_schema='public'
                  AND table_name LIKE 'card_printing%'
                  AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE'))
    THEN RAISE EXCEPTION 'S18.02 FALHOU: service_role tem privilegio de ESCRITA em tabela de Printing.'; END IF;

    IF EXISTS (SELECT 1 FROM information_schema.role_table_grants
                WHERE grantee='service_role' AND table_schema='public'
                  AND table_name IN ('card_printing_external_mapping_trait','card_printing_profile_trait'))
    THEN RAISE EXCEPTION 'S18.03 FALHOU: service_role recebeu acesso a tabela de composicao — desnecessario, o cabecalho selado basta.'; END IF;

    IF EXISTS (SELECT 1 FROM information_schema.role_table_grants
                WHERE grantee='anon' AND table_schema='public' AND table_name LIKE 'card_printing%')
    THEN RAISE EXCEPTION 'S18.04 FALHOU: anon tem privilegio em tabela de Printing.'; END IF;

    IF EXISTS (SELECT 1 FROM information_schema.role_routine_grants
                WHERE routine_name='admin_resolve_catalog_variant_import_printing_mapping'
                  AND grantee NOT IN ('authenticated','postgres'))
    THEN RAISE EXCEPTION 'S18.05 FALHOU: grant inesperado de EXECUTE na RPC de Printing.'; END IF;
END;
$s18$;

SELECT 'S18 H28 SEGURANCA: 5 assercoes PASS' AS resumo;


-- =============================================================================
-- SECAO 19 — R4: CONTRATO PROPRIO DE AUDITORIA (Query 2185)
-- =============================================================================
DO $s19$
DECLARE
    v_action_def TEXT; v_entity_def TEXT; v_match_def TEXT;
    -- (v2.5 / B-11) prova semantica da matriz de pares.
    v_expr TEXT; v_sql TEXT;
    v_missing_pairs INTEGER; v_extra_pairs INTEGER; v_ok BOOLEAN;
BEGIN
    SELECT pg_get_constraintdef(c.oid) INTO v_action_def FROM pg_constraint c
     WHERE c.conrelid='public.catalog_admin_action_log'::regclass
       AND c.conname='ck_catalog_admin_action_log_action_valid';
    SELECT pg_get_constraintdef(c.oid) INTO v_entity_def FROM pg_constraint c
     WHERE c.conrelid='public.catalog_admin_action_log'::regclass
       AND c.conname='ck_catalog_admin_action_log_entity_type_valid';
    SELECT pg_get_constraintdef(c.oid) INTO v_match_def FROM pg_constraint c
     WHERE c.conrelid='public.catalog_admin_action_log'::regclass
       AND c.conname='ck_catalog_admin_action_log_action_entity_match';

    -- (v2.4 / B-10) As TRES CHECKs precisam existir. A terceira era a
    -- unica que nem o guard da 2185 v1.1 nem esta Secao verificavam.
    IF v_action_def IS NULL OR v_entity_def IS NULL OR v_match_def IS NULL THEN
        RAISE EXCEPTION 'S19.00 FALHOU: uma das TRES CHECKs de catalog_admin_action_log nao existe (action=%, entity=%, match=%).',
            (v_action_def IS NOT NULL), (v_entity_def IS NOT NULL), (v_match_def IS NOT NULL);
    END IF;

    IF position('''CARD_PRINTING_EXTERNAL_MAPPING_CREATED''' IN v_action_def) = 0 THEN
        RAISE EXCEPTION 'S19.01 FALHOU: a action CARD_PRINTING_EXTERNAL_MAPPING_CREATED nao foi acrescentada. A Query 2185 rodou?';
    END IF;

    IF position('''CARD_PRINTING_EXTERNAL_MAPPING''' IN v_entity_def) = 0 THEN
        RAISE EXCEPTION 'S19.02 FALHOU: o entity_type CARD_PRINTING_EXTERNAL_MAPPING nao foi acrescentado.';
    END IF;

    IF position('''CARD_PRINTING_EXTERNAL_MAPPING''' IN v_match_def) = 0 THEN
        RAISE EXCEPTION 'S19.03 FALHOU: nao existe ramo de action_entity_match para a entidade de Printing.';
    END IF;

    -- Aditividade: os valores de Variant Type continuam la, intactos.
    IF position('''CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED''' IN v_action_def) = 0
       OR position('''CARD_PRIMARY_SPECIES_RESOLVED''' IN v_action_def) = 0 THEN
        RAISE EXCEPTION 'S19.04 FALHOU: a Query 2185 removeu valores preexistentes. Ela deveria ser estritamente aditiva.';
    END IF;

    -- =====================================================================
    -- (v2.5 / B-11) CONTRATO DE PARES — PROVA SEMANTICA
    --
    -- A v2.4 contava ocorrencias de literais no TEXTO da terceira CHECK,
    -- exigindo 1 por nome. A premissa e FALSA no proprio contrato:
    --
    --     entity_type = 'CATALOG_IMPORT_JOB'
    --       AND action IN ('CATALOG_IMPORT_JOB', ...)
    --
    -- 'CATALOG_IMPORT_JOB' e entity_type E action ao mesmo tempo, e
    -- aparece DUAS vezes em papeis sintaticos diferentes. Contagem global
    -- nao distingue papel. Caso especial `esperado := 2` nao resolve —
    -- so codificaria a colisao lexical de hoje.
    --
    -- v2.5 AVALIA a expressao real da CHECK, obtida por
    -- pg_get_expr(conbin, conrelid), contra o cross-product
    -- 12 entity_types x 30 actions = 360 pares. Quem decide se um par e
    -- permitido e o proprio Postgres executando o predicado — nao ha
    -- parsing, nao ha contagem, e papel sintatico deixa de importar.
    --
    -- Duas contagens fecham o contrato nos dois sentidos:
    --   A. nenhum dos 30 pares esperados pode ser recusado;
    --   B. nenhum dos 330 restantes pode ser aceito.
    -- =====================================================================
    SELECT pg_get_expr(c.conbin, c.conrelid) INTO v_expr
      FROM pg_constraint c
     WHERE c.conrelid='public.catalog_admin_action_log'::regclass
       AND c.conname='ck_catalog_admin_action_log_action_entity_match';

    IF v_expr IS NULL OR btrim(v_expr) = '' THEN
        RAISE EXCEPTION 'S19.08 FALHOU: nao foi possivel renderizar a expressao de action_entity_match.';
    END IF;

    v_sql := format($q$
        SELECT
            count(*) FILTER (WHERE x.expected     AND NOT (%1$s)),
            count(*) FILTER (WHERE NOT x.expected AND     (%1$s))
          FROM (
              SELECT e.v AS entity_type,
                     a.v AS action,
                     (e.v, a.v) IN (
                         VALUES
                           ('GAME','GAME_CREATED'),
                           ('GAME','GAME_UPDATED'),
                           ('GAME','GAME_DELETED'),
                           ('EXPANSION','EXPANSION_CREATED'),
                           ('EXPANSION','EXPANSION_UPDATED'),
                           ('EXPANSION','EXPANSION_DELETED'),
                           ('CARD_SET','CARD_SET_CREATED'),
                           ('CARD_SET','CARD_SET_UPDATED'),
                           ('CARD_SET','CARD_SET_DELETED'),
                           ('CARD_SET','CARD_ASSET_MANUAL_IMPORT_COMPLETED'),
                           ('CARD','CARD_CREATED'),
                           ('CARD','CARD_UPDATED'),
                           ('CARD','CARD_DEACTIVATED'),
                           ('CARD','CARD_REACTIVATED'),
                           ('CATALOG_IMPORT_JOB','CATALOG_IMPORT_JOB'),
                           ('CATALOG_IMPORT_JOB','CATALOG_IMPORT_CONFIRMED'),
                           ('CATALOG_IMPORT_JOB','CATALOG_IMPORT_ROWS_REVALIDATED'),
                           ('RARITY','RARITY_CREATED'),
                           ('RARITY','RARITY_UPDATED'),
                           ('RARITY_EXTERNAL_MAPPING','RARITY_EXTERNAL_MAPPING_CREATED'),
                           ('RARITY_EXTERNAL_MAPPING','RARITY_EXTERNAL_MAPPING_UPDATED'),
                           ('CATALOG_VARIANT_IMPORT_JOB','CARD_VARIANT_IMPORT_CONFIRMED'),
                           ('CARD_VARIANT_TYPE_EXTERNAL_MAPPING','CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED'),
                           ('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_CREATED'),
                           ('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_UPDATED'),
                           ('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_DEACTIVATED'),
                           ('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_REACTIVATED'),
                           ('CARD_PRIMARY_SPECIES','CARD_PRIMARY_SPECIES_RESOLVED'),
                           ('CARD_PRIMARY_SPECIES','CARD_PRIMARY_SPECIES_CORRECTED'),
                           ('CARD_PRINTING_EXTERNAL_MAPPING','CARD_PRINTING_EXTERNAL_MAPPING_CREATED')
                     ) AS expected
                FROM unnest(ARRAY[
                         'GAME','EXPANSION','CARD_SET','CARD','CATALOG_IMPORT_JOB',
                         'RARITY','RARITY_EXTERNAL_MAPPING','CATALOG_VARIANT_IMPORT_JOB',
                         'CARD_VARIANT_TYPE_EXTERNAL_MAPPING','CARD_VARIANT_TYPE',
                         'CARD_PRIMARY_SPECIES','CARD_PRINTING_EXTERNAL_MAPPING']::text[]) AS e(v)
                CROSS JOIN unnest(ARRAY[
                         'GAME_CREATED','GAME_UPDATED','GAME_DELETED',
                         'EXPANSION_CREATED','EXPANSION_UPDATED','EXPANSION_DELETED',
                         'CARD_SET_CREATED','CARD_SET_UPDATED','CARD_SET_DELETED',
                         'CARD_CREATED','CARD_UPDATED','CARD_DEACTIVATED','CARD_REACTIVATED',
                         'CATALOG_IMPORT_JOB','CATALOG_IMPORT_CONFIRMED','CATALOG_IMPORT_ROWS_REVALIDATED',
                         'RARITY_CREATED','RARITY_UPDATED',
                         'RARITY_EXTERNAL_MAPPING_CREATED','RARITY_EXTERNAL_MAPPING_UPDATED',
                         'CARD_ASSET_MANUAL_IMPORT_COMPLETED','CARD_VARIANT_IMPORT_CONFIRMED',
                         'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
                         'CARD_VARIANT_TYPE_CREATED','CARD_VARIANT_TYPE_UPDATED',
                         'CARD_VARIANT_TYPE_DEACTIVATED','CARD_VARIANT_TYPE_REACTIVATED',
                         'CARD_PRIMARY_SPECIES_RESOLVED','CARD_PRIMARY_SPECIES_CORRECTED',
                         'CARD_PRINTING_EXTERNAL_MAPPING_CREATED']::text[]) AS a(v)
          ) x
    $q$, v_expr);

    EXECUTE v_sql INTO v_missing_pairs, v_extra_pairs;

    IF v_missing_pairs <> 0 THEN
        RAISE EXCEPTION 'S19.09 FALHOU: % dos 30 pares finais esperados NAO sao aceitos pela CHECK real. O contrato encolheu.', v_missing_pairs;
    END IF;

    IF v_extra_pairs <> 0 THEN
        RAISE EXCEPTION 'S19.10 FALHOU: % par(es) fora da matriz final de 30 sao aceitos pela CHECK real — permissao desconhecida, inclusive uma que nenhuma linha usou ainda.', v_extra_pairs;
    END IF;

    -- Exclusividade da Impressao: a action nova casa SO com a entidade
    -- nova, e a entidade nova aceita SO a action nova. Provado par a par,
    -- sem contar texto.
    EXECUTE format(
        'SELECT (%s) FROM (SELECT %L::text AS entity_type, %L::text AS action) t',
        v_expr, 'CARD_PRINTING_EXTERNAL_MAPPING', 'CARD_PRINTING_EXTERNAL_MAPPING_CREATED') INTO v_ok;
    IF v_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'S19.11 FALHOU: o par (CARD_PRINTING_EXTERNAL_MAPPING, CARD_PRINTING_EXTERNAL_MAPPING_CREATED) nao e aceito.';
    END IF;

    EXECUTE format(
        'SELECT (%s) FROM (SELECT %L::text AS entity_type, %L::text AS action) t',
        v_expr, 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING', 'CARD_PRINTING_EXTERNAL_MAPPING_CREATED') INTO v_ok;
    IF v_ok IS NOT FALSE THEN
        RAISE EXCEPTION 'S19.12 FALHOU: a action de Printing casa com o entity_type de Variant Type. Os dominios voltaram a se misturar.';
    END IF;

    -- REGRESSAO NOMINAL DO B-11: par legitimo em que entity_type e action
    -- sao o MESMO literal. Se falhar, a prova voltou a confundir papel
    -- sintatico com ocorrencia textual.
    EXECUTE format(
        'SELECT (%s) FROM (SELECT %L::text AS entity_type, %L::text AS action) t',
        v_expr, 'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_JOB') INTO v_ok;
    IF v_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'S19.13 FALHOU (REGRESSAO B-11): o par LEGITIMO (CATALOG_IMPORT_JOB, CATALOG_IMPORT_JOB) foi recusado.';
    END IF;

    -- Contraprova: cross-pair que nunca foi permitido.
    EXECUTE format(
        'SELECT (%s) FROM (SELECT %L::text AS entity_type, %L::text AS action) t',
        v_expr, 'GAME', 'CARD_CREATED') INTO v_ok;
    IF v_ok IS NOT FALSE THEN
        RAISE EXCEPTION 'S19.14 FALHOU: o par ILEGITIMO (GAME, CARD_CREATED) e aceito pela CHECK real.';
    END IF;

    -- Nenhum literal desconhecido nas tres definicoes.
    IF EXISTS (
        SELECT 1 FROM (
            SELECT (regexp_matches(v_match_def || v_action_def || v_entity_def,
                                   '''([A-Z][A-Z_]*)''', 'g'))[1] AS t
        ) f
         WHERE f.t NOT IN (
            'GAME','EXPANSION','CARD_SET','CARD','CATALOG_IMPORT_JOB',
            'RARITY','RARITY_EXTERNAL_MAPPING','CATALOG_VARIANT_IMPORT_JOB',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING','CARD_VARIANT_TYPE',
            'CARD_PRIMARY_SPECIES','CARD_PRINTING_EXTERNAL_MAPPING',
            'GAME_CREATED','GAME_UPDATED','GAME_DELETED',
            'EXPANSION_CREATED','EXPANSION_UPDATED','EXPANSION_DELETED',
            'CARD_SET_CREATED','CARD_SET_UPDATED','CARD_SET_DELETED',
            'CARD_CREATED','CARD_UPDATED','CARD_DEACTIVATED','CARD_REACTIVATED',
            'CATALOG_IMPORT_CONFIRMED','CATALOG_IMPORT_ROWS_REVALIDATED',
            'RARITY_CREATED','RARITY_UPDATED',
            'RARITY_EXTERNAL_MAPPING_CREATED','RARITY_EXTERNAL_MAPPING_UPDATED',
            'CARD_ASSET_MANUAL_IMPORT_COMPLETED','CARD_VARIANT_IMPORT_CONFIRMED',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
            'CARD_VARIANT_TYPE_CREATED','CARD_VARIANT_TYPE_UPDATED',
            'CARD_VARIANT_TYPE_DEACTIVATED','CARD_VARIANT_TYPE_REACTIVATED',
            'CARD_PRIMARY_SPECIES_RESOLVED','CARD_PRIMARY_SPECIES_CORRECTED',
            'CARD_PRINTING_EXTERNAL_MAPPING_CREATED')
    ) THEN
        RAISE EXCEPTION 'S19.15 FALHOU: as CHECKs citam valor(es) fora do universo ratificado de 12 entity_types + 30 actions.';
    END IF;

    -- ---------------------------------------------------------------------
    -- S19.05 a S19.07 — CONTRATO DA RPC (nao da CHECK). Os rotulos sao
    -- ANTERIORES aos de S19.08+ e foram preservados: rotulo e identificador
    -- estavel de assercao, nao ordem de execucao. Renumerar quebraria a
    -- rastreabilidade das rodadas anteriores sem ganho algum. Total real
    -- desta Secao: 16 assercoes (S19.00 a S19.15), sem lacuna e sem
    -- duplicidade.
    -- ---------------------------------------------------------------------

    -- A RPC de Printing NAO pode mais usar o par de Variant Type.
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                WHERE n.nspname='public'
                  AND p.proname='admin_resolve_catalog_variant_import_printing_mapping'
                  AND p.prosrc ILIKE '%''CARD_VARIANT_TYPE_EXTERNAL_MAPPING''%')
    THEN RAISE EXCEPTION 'S19.05 FALHOU: a RPC de Printing ainda grava no entity_type de Variant Type.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public'
                      AND p.proname='admin_resolve_catalog_variant_import_printing_mapping'
                      AND p.prosrc ILIKE '%CARD_PRINTING_EXTERNAL_MAPPING_CREATED%')
    THEN RAISE EXCEPTION 'S19.06 FALHOU: a RPC de Printing nao usa a action propria.'; END IF;

    -- metadata.domain era a muleta da v1.0. Nao deve sobreviver.
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                WHERE n.nspname='public'
                  AND p.proname='admin_resolve_catalog_variant_import_printing_mapping'
                  AND p.prosrc ILIKE '%''domain'', ''PRINTING''%')
    THEN RAISE EXCEPTION 'S19.07 FALHOU: metadata.domain continua sendo gravado — redundante e enganoso agora que o entity_type e correto.'; END IF;
END;
$s19$;

SELECT 'S19 R4 CONTRATO DE AUDITORIA (v2.5, prova semantica: 3 CHECKs + 360 pares avaliados): 16 assercoes PASS' AS resumo;


-- =============================================================================
-- SECAO 20 — R2: COMPATIBILIDADE TRANSITORIA DO CONFIRM
-- =============================================================================
DO $s20$
DECLARE
    v_src TEXT;
BEGIN
    SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='admin_confirm_catalog_variant_import';

    IF v_src IS NULL THEN RAISE EXCEPTION 'S20.00 FALHOU: admin_confirm_catalog_variant_import nao existe.'; END IF;

    -- O ramo legado precisa estar amarrado ao BRIDGE — e nao a um flag
    -- solto, que ninguem lembraria de desligar.
    IF position('uq_cvir_job_card_type_bridge_legacy' IN v_src) = 0 THEN
        RAISE EXCEPTION 'S20.01 FALHOU: o confirm nao condiciona a compatibilidade legada a existencia do bridge. A compatibilidade transitoria viraria permanente.';
    END IF;

    -- E a prova de ausencia de Impressao precisa vir do RESOLVEDOR,
    -- nao de uma suposicao.
    IF position('compute_variant_residual_signature' IN v_src) = 0 THEN
        RAISE EXCEPTION 'S20.02 FALHOU: o confirm aceita chave ausente sem provar, pelo roteamento, que nao ha Impressao conhecida.';
    END IF;

    IF position('RESOLVED_NO_PRINTING' IN v_src) = 0 THEN
        RAISE EXCEPTION 'S20.03 FALHOU: o confirm nao exige RESOLVED_NO_PRINTING para aceitar linha legada.';
    END IF;

    -- E continua recusando quando ha Impressao conhecida.
    IF position('PRINTING_NOT_RESOLVED' IN v_src) = 0 THEN
        RAISE EXCEPTION 'S20.04 FALHOU: o confirm perdeu a rejeicao de Impressao nao resolvida.';
    END IF;
END;
$s20$;

SELECT 'S20 R2 COMPATIBILIDADE TRANSITORIA: 4 assercoes PASS' AS resumo;


-- =============================================================================
-- SECAO 21 — H29: ZERO RESIDUO (read-only, FAIL-CLOSED)
-- =============================================================================
DO $s21$
DECLARE
    v_n BIGINT;
BEGIN
    SELECT count(*) INTO v_n FROM public.card_printing_external_mapping
     WHERE normalized_token LIKE 'HARNESS%';
    IF v_n <> 0 THEN RAISE EXCEPTION 'S21.01 FALHOU: % mapping(s) HARNESS residual(is) — algum ROLLBACK nao aconteceu.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_external_mapping;
    IF v_n <> 5 THEN RAISE EXCEPTION 'S21.02 FALHOU: % mappings, esperados 5.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE is_active;
    IF v_n <> 5 THEN RAISE EXCEPTION 'S21.03 FALHOU: % mappings ativos, esperados 5.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_external_mapping_trait;
    IF v_n <> 6 THEN RAISE EXCEPTION 'S21.04 FALHOU: % vinculos, esperados 6.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_external_mapping WHERE supersedes_mapping_id IS NOT NULL;
    IF v_n <> 0 THEN RAISE EXCEPTION 'S21.05 FALHOU: % mapping(s) com supersedes — S4/S14 deixaram residuo.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_variant;
    IF v_n <> 7002 THEN RAISE EXCEPTION 'S21.06 FALHOU: card_variant = %, esperado 7002.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_variant_type_external_mapping;
    IF v_n <> 69 THEN RAISE EXCEPTION 'S21.07 FALHOU: % mappings de Variant Type, esperados 69.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_profile;
    IF v_n <> 6 THEN RAISE EXCEPTION 'S21.08 FALHOU: % profiles, esperados 6.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.catalog_admin_action_log
     WHERE action = 'CARD_PRINTING_EXTERNAL_MAPPING_CREATED';
    IF v_n <> 0 THEN RAISE EXCEPTION 'S21.09 FALHOU: % linha(s) de log de Printing gravadas pelo harness. S13/S14/S26 deixaram residuo.', v_n; END IF;

    -- As fixtures de S26 marcam metadata com HARNESS. A fixture (d) usa a
    -- action de Variant Type, que tem linhas legitimas — so o marcador
    -- distingue residuo de dado real.
    SELECT count(*) INTO v_n FROM public.catalog_admin_action_log
     WHERE metadata::TEXT LIKE '%HARNESS%';
    IF v_n <> 0 THEN RAISE EXCEPTION 'S21.11 FALHOU: % linha(s) de log com marcador HARNESS. A Secao S26 nao reverteu.', v_n; END IF;

    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                WHERE c.relname LIKE 'harness\_%' AND n.nspname LIKE 'pg_temp%')
    THEN RAISE EXCEPTION 'S21.10 FALHOU: tabelas temporarias do harness sobreviveram.'; END IF;

    -- As fixtures de STAGING da S11 v1.1 carregam a chave 'harness' em
    -- raw_data. E o unico marcador que as distingue das 6.158 rows reais.
    SELECT count(*) INTO v_n FROM public.catalog_variant_import_row
     WHERE raw_data ? 'harness';
    IF v_n <> 0 THEN RAISE EXCEPTION 'S21.12 FALHOU: % row(s) de staging com marcador harness — a S11 nao reverteu.', v_n; END IF;

    -- -------------------------------------------------------------------
    -- BASELINE CRITICO — nenhuma row real pode ter sido alterada por
    -- nenhuma Secao. Repetido aqui, no fim, para que o zero-residuo e a
    -- nao-regressao sejam a MESMA prova.
    -- -------------------------------------------------------------------
    SELECT count(*) INTO v_n FROM public.catalog_variant_import_row;
    IF v_n <> 6158 THEN RAISE EXCEPTION 'S21.13 FALHOU: staging rows = %, esperado 6158.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE validation_status='VALID';
    IF v_n <> 5653 THEN RAISE EXCEPTION 'S21.14 FALHOU: VALID = %, esperado 5653.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.catalog_variant_import_row WHERE validation_status='NEEDS_REVIEW';
    IF v_n <> 505 THEN RAISE EXCEPTION 'S21.15 FALHOU: NEEDS_REVIEW = %, esperado 505.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.catalog_variant_import_row
     WHERE normalized_data ? 'printing_profile_id';
    IF v_n <> 0 THEN RAISE EXCEPTION 'S21.16 FALHOU: % row(s) ganharam a chave de Impressao. Durante o GATE A ela nao existe em nenhuma row.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_variant_type;
    IF v_n <> 79 THEN RAISE EXCEPTION 'S21.17 FALHOU: card_variant_type = %, esperado 79.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.catalog_variant_import_job WHERE status='STAGED';
    IF v_n <> 4 THEN RAISE EXCEPTION 'S21.18 FALHOU: jobs STAGED = %, esperado 4.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_variant WHERE printing_profile_id IS NOT NULL;
    IF v_n <> 0 THEN RAISE EXCEPTION 'S21.19 FALHOU: % card_variant com printing_profile_id. Isso e PHASE C/D, nao GATE A.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_trait;
    IF v_n <> 5 THEN RAISE EXCEPTION 'S21.20 FALHOU: printing traits = %, esperado 5.', v_n; END IF;
END;
$s21$;

SELECT 'S21 H29 ZERO RESIDUO + BASELINE: 20 assercoes PASS' AS resumo,
       (SELECT count(*) FROM public.card_printing_external_mapping)       AS mappings,
       (SELECT count(*) FROM public.card_printing_external_mapping_trait) AS vinculos,
       (SELECT count(*) FROM public.card_variant)                          AS card_variant,
       (SELECT count(*) FROM public.catalog_variant_import_row)            AS staging_rows;


-- =============================================================================
-- SECAO 28 — B-06 (RECONCILIACAO TERMINAL) + OB1..OB6 (ORIGIN BINDING)
--
-- NOVA na v2.3 (STAGING-CORRECTION-04 §10 e §11). Pertence ao BLOCO I.
-- Depende da Query 2181 v1.2 — PHASE B. Rodar junto de S13/S14, e sempre
-- ANTES de S21.
--
-- -----------------------------------------------------------------------------
-- PARTE A — B-06: nenhuma row atingida conserva identidade obsoleta
-- -----------------------------------------------------------------------------
-- CASO A. Row previamente VALID pelo mapping antigo; a substituicao leva
--   o Printing a NAO RESOLVIDO (conjunto de traits sem profile exato).
--   Esperado: NEEDS_REVIEW, printing_profile_id REMOVIDO, variant_type_id
--   REMOVIDO. Nunca VALID com o perfil antigo.
--
-- CASO B. Printing resolve, mas o residual nao tem mapping de Variant Type.
--   Esperado: NEEDS_REVIEW, printing_profile_id EXPLICITO e correto,
--   variant_type_id AUSENTE.
--
-- O conjunto "sem profile" do CASO A e derivado por NOT EXISTS contra
-- card_printing_profile — nao e premissa fixada. Com 5 traits existem 31
-- subconjuntos nao vazios e apenas 6 profiles, entao ao menos um par sem
-- assinatura exata existe; a Secao PROVA isso em vez de supor, e falha
-- alto se nao encontrar.
--
-- -----------------------------------------------------------------------------
-- PARTE B — OB1..OB6: origin-row binding (B-04)
-- -----------------------------------------------------------------------------
-- OB1 subtype correto na row .................... aceita
-- OB2 subtype diferente ......................... ORIGIN_TOKEN_NOT_FOUND
-- OB3 stamp presente exatamente ................. aceita
-- OB4 stamp ausente (chave nem existe) .......... ORIGIN_TOKEN_NOT_FOUND
-- OB5 1st-edition-error NAO prova 1st-edition ... ORIGIN_TOKEN_NOT_FOUND
-- OB6 comparacao canonica exata, nao prefixo .... ORIGIN_TOKEN_NOT_FOUND
--
-- OB5 e a prova nominal: e o mesmo par de tokens que a 2176 ja distingue.
-- Se o binding usasse LIKE/prefixo, OB5 e OB6 passariam a ACEITAR — e a
-- Secao falha.
--
-- Tudo em BEGIN/ROLLBACK. Todas as fixtures carregam marcador proprio.
-- =============================================================================
BEGIN;

DO $s28$
DECLARE
    v_admin UUID; v_game UUID; v_src UUID;
    v_job UUID; v_card UUID;
    v_vtem_type TEXT; v_vtem_variant_type UUID;
    v_unl_trait UUID; v_unl_profile UUID;
    v_row_a UUID; v_row_b UUID;
    v_sig_no_profile UUID[];
    v_msg TEXT; v_ok BOOLEAN; r RECORD;
    v_status TEXT; v_has_vt BOOLEAN; v_has_pp BOOLEAN; v_pp TEXT;
    v_row_ob UUID;
BEGIN
    SELECT id INTO v_admin FROM public.admin_user LIMIT 1;
    IF v_admin IS NULL THEN
        RAISE EXCEPTION 'S28.SETUP FALHOU: nenhum administrador cadastrado. B-06 e o origin binding NAO PODEM ser provados nesta base — nao registrar como PASS.';
    END IF;

    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code='TCGDEX';
    SELECT id INTO v_unl_trait   FROM public.card_printing_trait   WHERE game_id=v_game AND code='UNLIMITED';
    SELECT id INTO v_unl_profile FROM public.card_printing_profile WHERE game_id=v_game AND code='UNLIMITED';

    IF v_unl_trait IS NULL OR v_unl_profile IS NULL THEN
        RAISE EXCEPTION 'S28.SETUP FALHOU: trait/profile UNLIMITED nao encontrados.';
    END IF;

    -- Mapping de Variant Type cuja assinatura e SO `type` — o residual
    -- volta a ser exatamente ele quando o token de Impressao e consumido.
    SELECT vm.external_type, vm.variant_type_id
      INTO v_vtem_type, v_vtem_variant_type
      FROM public.card_variant_type_external_mapping vm
     WHERE vm.game_id = v_game AND vm.asset_source_id = v_src
       AND vm.normalized_foil IS NULL AND vm.normalized_subtype IS NULL
       AND COALESCE(cardinality(vm.normalized_stamp), 0) = 0
     ORDER BY vm.id
     LIMIT 1;

    IF v_vtem_variant_type IS NULL THEN
        RAISE EXCEPTION 'S28.SETUP FALHOU: nenhum mapping de Variant Type com assinatura apenas de type. A prova nao pode ser montada sem inventar dado.';
    END IF;

    -- Identidade final livre — mesma disciplina da S11 v1.1 e da S14 v2.3.
    SELECT j.id, r2.card_id INTO v_job, v_card
      FROM public.catalog_variant_import_job j
      JOIN public.catalog_variant_import_row r2 ON r2.job_id = j.id
     WHERE j.status = 'STAGED' AND j.source = 'TCGDEX'
       AND NOT EXISTS (
           SELECT 1 FROM public.catalog_variant_import_row x
            WHERE x.job_id = j.id AND x.card_id = r2.card_id
              AND (x.normalized_data ->> 'variant_type_id') = v_vtem_variant_type::TEXT)
     ORDER BY j.id, r2.card_id
     LIMIT 1;

    IF v_job IS NULL THEN
        RAISE EXCEPTION 'S28.SETUP FALHOU: nenhuma identidade final livre disponivel — nao registrar como PASS.';
    END IF;

    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', v_admin::TEXT, 'role', 'authenticated')::TEXT, true);
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'S28.SETUP FALHOU: impersonacao de administrador sem efeito. NAO registrar como PASS.';
    END IF;

    -- =====================================================================
    -- CASO A — VALID vira NEEDS_REVIEW quando o Printing deixa de resolver
    -- =====================================================================
    INSERT INTO public.catalog_variant_import_row
        (job_id, card_id, raw_data, normalized_data, validation_status, decision_status)
    VALUES (v_job, v_card,
            jsonb_build_object('harness', 'S28-A', 'type', v_vtem_type,
                               'stamp', jsonb_build_array('harness-s28-a')),
            '{}'::JSONB, 'NEEDS_REVIEW', 'PENDING')
    RETURNING id INTO v_row_a;

    -- Ratificacao 1: composicao que RESOLVE para um profile real.
    SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
        v_row_a, 'stamp', 'harness-s28-a', ARRAY[v_unl_trait]);

    SELECT r2.validation_status,
           r2.normalized_data ? 'variant_type_id',
           r2.normalized_data ->> 'printing_profile_id'
      INTO v_status, v_has_vt, v_pp
      FROM public.catalog_variant_import_row r2 WHERE r2.id = v_row_a;

    IF v_status IS DISTINCT FROM 'VALID' OR NOT v_has_vt
       OR v_pp IS DISTINCT FROM v_unl_profile::TEXT THEN
        RAISE EXCEPTION 'S28.01 FALHOU (setup do CASO A): a row deveria estar VALID com o perfil UNLIMITED antes da substituicao (status=%, tem_vt=%, perfil=%).',
            COALESCE(v_status,'<nulo>'), v_has_vt, COALESCE(v_pp,'<ausente>');
    END IF;

    -- Conjunto de traits SEM profile exato, derivado — nao fixado.
    --
    -- (v2.4 / §6) ORDENACAO CANONICA POR UUID, nao por code.
    -- traits_signature e UUID[] ordenado ASCENDENTE por trait_id — e assim
    -- que o selo (Query 2174) a grava e assim que a Query 2176 monta a
    -- composicao efetiva. Comparar um array ordenado por `code` contra um
    -- array ordenado por UUID daria "profile inexistente" para um conjunto
    -- que EXISTE, sempre que as duas ordenacoes divergirem — falso positivo
    -- que faria a fixture provar ausencia por artefato de ordenacao, nao
    -- por identidade canonica real. Hoje nao se materializa; a correcao
    -- elimina a fragilidade antes que se materialize.
    SELECT ARRAY(SELECT t.id FROM public.card_printing_trait t
                  WHERE t.game_id = v_game AND t.is_active
                  ORDER BY t.id)
      INTO v_sig_no_profile;

    IF EXISTS (SELECT 1 FROM public.card_printing_profile p
                WHERE p.game_id = v_game AND p.traits_signature = v_sig_no_profile) THEN
        -- O conjunto COMPLETO tem profile; tenta o conjunto completo menos
        -- o primeiro elemento na ordem canonica.
        SELECT ARRAY(SELECT t.id FROM public.card_printing_trait t
                      WHERE t.game_id = v_game AND t.is_active
                        AND t.id <> v_sig_no_profile[1]
                      ORDER BY t.id)
          INTO v_sig_no_profile;
    END IF;

    IF cardinality(v_sig_no_profile) < 1
       OR EXISTS (SELECT 1 FROM public.card_printing_profile p
                   WHERE p.game_id = v_game AND p.traits_signature = v_sig_no_profile) THEN
        RAISE EXCEPTION 'S28.02 FALHOU: nao foi possivel derivar um conjunto de traits SEM profile exato. A premissa do CASO A nao pode ser fixada sem prova — nao registrar como PASS.';
    END IF;

    -- Ratificacao 2: substituicao que leva o Printing a NAO RESOLVIDO.
    SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
        v_row_a, 'stamp', 'harness-s28-a', v_sig_no_profile);

    SELECT r2.validation_status,
           r2.normalized_data ? 'variant_type_id',
           r2.normalized_data ? 'printing_profile_id'
      INTO v_status, v_has_vt, v_has_pp
      FROM public.catalog_variant_import_row r2 WHERE r2.id = v_row_a;

    IF v_status IS DISTINCT FROM 'NEEDS_REVIEW' THEN
        RAISE EXCEPTION 'S28.03 FALHOU (REGRESSAO B-06): a row continua em % apos o Printing deixar de resolver. Ela ficaria VALID com o perfil ANTIGO, e o confirm a aceitaria.', COALESCE(v_status,'<nulo>');
    END IF;
    IF v_has_pp THEN
        RAISE EXCEPTION 'S28.04 FALHOU (B-06): printing_profile_id nao foi removido. O perfil antigo sobreviveu a uma decisao editorial que o invalidou.';
    END IF;
    IF v_has_vt THEN
        RAISE EXCEPTION 'S28.05 FALHOU (B-06): variant_type_id nao foi removido. Sem Printing resolvido o residual nao e identidade canonica confiavel.';
    END IF;

    IF r.rows_updated <> 0 OR r.rows_still_pending < 1 THEN
        RAISE EXCEPTION 'S28.06 FALHOU (§4): contadores incoerentes — rows_revalidated=%, rows_still_pending=%. A row rebaixada tem que aparecer em rows_still_pending, nunca sumir.',
            r.rows_updated, r.rows_still_pending;
    END IF;

    -- =====================================================================
    -- CASO B — Printing resolve, Variant Type residual nao
    --
    -- raw_data usa um `type` SINTETICO que nao existe em nenhum mapping de
    -- Variant Type. O token de Impressao e consumido normalmente, mas o
    -- residual nao casa com nada.
    -- =====================================================================
    INSERT INTO public.catalog_variant_import_row
        (job_id, card_id, raw_data, normalized_data, validation_status, decision_status)
    VALUES (v_job, v_card,
            jsonb_build_object('harness', 'S28-B', 'type', 'harness-s28-unknown-type',
                               'stamp', jsonb_build_array('harness-s28-b')),
            '{}'::JSONB, 'NEEDS_REVIEW', 'PENDING')
    RETURNING id INTO v_row_b;

    IF EXISTS (SELECT 1 FROM public.card_variant_type_external_mapping vm
                WHERE vm.game_id = v_game AND vm.asset_source_id = v_src
                  AND vm.normalized_type = 'HARNESS-S28-UNKNOWN-TYPE') THEN
        RAISE EXCEPTION 'S28.SETUP-B FALHOU: o type sintetico ja tem mapping de Variant Type — o CASO B nao provaria nada.';
    END IF;

    SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
        v_row_b, 'stamp', 'harness-s28-b', ARRAY[v_unl_trait]);

    SELECT r2.validation_status,
           r2.normalized_data ? 'variant_type_id',
           r2.normalized_data ->> 'printing_profile_id',
           jsonb_typeof(r2.normalized_data -> 'printing_profile_id')
      INTO v_status, v_has_vt, v_pp, v_msg
      FROM public.catalog_variant_import_row r2 WHERE r2.id = v_row_b;

    IF v_status IS DISTINCT FROM 'NEEDS_REVIEW' THEN
        RAISE EXCEPTION 'S28.07 FALHOU (CASO B): esperado NEEDS_REVIEW, obtido %.', COALESCE(v_status,'<nulo>');
    END IF;
    IF v_has_vt THEN
        RAISE EXCEPTION 'S28.08 FALHOU (CASO B): variant_type_id presente sem mapping de Variant Type correspondente.';
    END IF;
    IF v_msg IS DISTINCT FROM 'string' OR v_pp IS DISTINCT FROM v_unl_profile::TEXT THEN
        RAISE EXCEPTION 'S28.09 FALHOU (CASO B): o Printing RESOLVEU — printing_profile_id deveria permanecer explicito e correto (tipo=%, valor=%).',
            COALESCE(v_msg,'<ausente>'), COALESCE(v_pp,'<ausente>');
    END IF;

    -- =====================================================================
    -- PARTE B — ORIGIN-ROW BINDING (OB1..OB6)
    -- =====================================================================
    INSERT INTO public.catalog_variant_import_row
        (job_id, card_id, raw_data, normalized_data, validation_status, decision_status)
    VALUES (v_job, v_card,
            jsonb_build_object('harness', 'S28-OB',
                               'type', v_vtem_type,
                               'subtype', 'harness-s28-sub',
                               'stamp', jsonb_build_array('harness-s28-stamp', '1st-edition-error')),
            '{}'::JSONB, 'NEEDS_REVIEW', 'PENDING')
    RETURNING id INTO v_row_ob;

    -- OB1 — subtype correto na row -> ACEITA.
    SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
        v_row_ob, 'subtype', 'harness-s28-sub', ARRAY[v_unl_trait]);
    IF r.mapping_id IS NULL THEN
        RAISE EXCEPTION 'OB1 FALHOU: subtype que EXISTE na row de origem foi recusado.';
    END IF;

    -- OB2 — subtype diferente do da row -> RECUSA.
    v_ok := FALSE;
    BEGIN
        SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
            v_row_ob, 'subtype', 'harness-s28-outro-sub', ARRAY[v_unl_trait]);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%ORIGIN_TOKEN_NOT_FOUND%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'OB2 FALHOU: subtype que NAO existe na row de origem foi aceito (msg: %).', COALESCE(v_msg,'sem erro');
    END IF;

    -- OB3 — stamp presente exatamente -> ACEITA.
    SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
        v_row_ob, 'stamp', 'harness-s28-stamp', ARRAY[v_unl_trait]);
    IF r.mapping_id IS NULL THEN
        RAISE EXCEPTION 'OB3 FALHOU: stamp que EXISTE no array da row foi recusado.';
    END IF;

    -- OB4 — a row do CASO A nao tem a chave `subtype`; pedir subtype nela
    -- tem que ser recusado (chave AUSENTE, nao apenas diferente).
    v_ok := FALSE;
    BEGIN
        SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
            v_row_a, 'subtype', 'harness-s28-sub', ARRAY[v_unl_trait]);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%ORIGIN_TOKEN_NOT_FOUND%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'OB4 FALHOU: campo AUSENTE na raw_data foi aceito como origem (msg: %).', COALESCE(v_msg,'sem erro');
    END IF;

    -- OB5 — PROVA NOMINAL. A row tem '1st-edition-error' no stamp. Isso
    -- NAO prova a origem de '1st-edition'. Se o binding usasse prefixo ou
    -- LIKE, esta chamada seria ACEITA.
    v_ok := FALSE;
    BEGIN
        SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
            v_row_ob, 'stamp', '1st-edition', ARRAY[v_unl_trait]);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%ORIGIN_TOKEN_NOT_FOUND%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'OB5 FALHOU: 1st-edition-error foi aceito como prova de origem para 1st-edition. O binding esta usando comparacao aproximada (msg: %).', COALESCE(v_msg,'sem erro');
    END IF;

    -- OB6 — prefixo do token real tambem nao prova origem.
    v_ok := FALSE;
    BEGIN
        SELECT * INTO r FROM public.admin_resolve_catalog_variant_import_printing_mapping(
            v_row_ob, 'stamp', 'harness-s28', ARRAY[v_unl_trait]);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%ORIGIN_TOKEN_NOT_FOUND%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'OB6 FALHOU: um PREFIXO do token real foi aceito como origem. A comparacao tem que ser por igualdade canonica exata (msg: %).', COALESCE(v_msg,'sem erro');
    END IF;
END;
$s28$;

SELECT 'S28 B-06 (CASOS A/B) + ORIGIN BINDING (OB1..OB6): 15 assercoes PASS' AS resumo;

ROLLBACK;


-- #############################################################################
-- ##                                                                         ##
-- ##   B L O C O   I I   —   P O S T - E D G E   H A R N E S S   ( S22 )      ##
-- ##                                                                         ##
-- ##   RODAR SOMENTE APOS O DEPLOY DA EDGE NOVA EM PRODUCAO.                  ##
-- ##   Executar S22 antes disso e um FALSO FAIL garantido.                    ##
-- ##   O PASS desta Secao autoriza a PHASE D (Query 2183).                    ##
-- ##                                                                         ##
-- #############################################################################

-- =============================================================================
-- SECAO 22 — CONTRATO DE SAIDA DA EDGE NOVA
-- =============================================================================
DO $s22$
DECLARE
    v_cutoff TIMESTAMPTZ;
    v_new_rows BIGINT; v_without_key BIGINT; v_bad_shape BIGINT;
BEGIN
    -- Janela: linhas criadas depois do deploy. O operador ajusta o
    -- cutoff para o instante real do deploy antes de rodar.
    v_cutoff := COALESCE(
        NULLIF(current_setting('mimikyu.edge_deploy_at', true), '')::TIMESTAMPTZ,
        now() - INTERVAL '1 day');

    SELECT count(*) INTO v_new_rows
      FROM public.catalog_variant_import_row WHERE created_at >= v_cutoff;

    IF v_new_rows = 0 THEN
        RAISE EXCEPTION 'S22.00 NAO PROVADO: nenhuma linha criada apos o cutoff (%). Rode uma importacao real com a Edge nova antes de validar. NAO registrar como PASS.', v_cutoff;
    END IF;

    -- INVARIANTE DE SAIDA: toda linha VALID nova tem a chave.
    SELECT count(*) INTO v_without_key
      FROM public.catalog_variant_import_row
     WHERE created_at >= v_cutoff
       AND validation_status = 'VALID'
       AND jsonb_typeof(normalized_data -> 'printing_profile_id') IS NULL;

    IF v_without_key <> 0 THEN
        RAISE EXCEPTION 'S22.01 FALHOU: % linha(s) VALID criadas pela Edge nova estao SEM a chave printing_profile_id. O writer antigo ainda esta ativo, ou o deploy nao contemplou o contrato. STOP — a PHASE D nao pode comecar.', v_without_key;
    END IF;

    SELECT count(*) INTO v_bad_shape
      FROM public.catalog_variant_import_row
     WHERE created_at >= v_cutoff
       AND jsonb_typeof(normalized_data -> 'printing_profile_id') NOT IN ('null','string');

    IF v_bad_shape <> 0 THEN
        RAISE EXCEPTION 'S22.02 FALHOU: % linha(s) novas com printing_profile_id de tipo JSON invalido.', v_bad_shape;
    END IF;
END;
$s22$;

SELECT 'S22 POST-EDGE CONTRATO DE SAIDA PASS' AS resumo;


-- #############################################################################
-- ##                                                                         ##
-- ##   B L O C O   I I I   —   P O S T - B A C K F I L L   ( S23 )            ##
-- ##                                                                         ##
-- ##   RODAR SOMENTE APOS A QUERY 2183 (PHASE D).                             ##
-- ##   O PASS desta Secao autoriza a PHASE E (Query 2184).                    ##
-- ##                                                                         ##
-- #############################################################################

-- =============================================================================
-- SECAO 23 — H21/H22 REAIS
-- =============================================================================
DO $s23$
DECLARE
    v_absent BIGINT; v_needs_review_with_key BIGINT; v_bad_shape BIGINT;
BEGIN
    SELECT count(*) INTO v_absent
      FROM public.catalog_variant_import_row
     WHERE validation_status = 'VALID'
       AND jsonb_typeof(normalized_data -> 'printing_profile_id') IS NULL;

    IF v_absent <> 0 THEN
        RAISE EXCEPTION 'S23.01 FALHOU (H22): % row(s) VALID ainda sem a chave apos a Query 2183. A PHASE E nao pode comecar.', v_absent;
    END IF;

    SELECT count(*) INTO v_bad_shape
      FROM public.catalog_variant_import_row
     WHERE validation_status = 'VALID'
       AND jsonb_typeof(normalized_data -> 'printing_profile_id') NOT IN ('null','string');

    IF v_bad_shape <> 0 THEN
        RAISE EXCEPTION 'S23.02 FALHOU: % row(s) VALID com printing_profile_id de tipo invalido.', v_bad_shape;
    END IF;

    -- -------------------------------------------------------------------
    -- S23.03 — NEEDS_REVIEW NAO CARREGA IDENTIDADE CANONICA (v2.6)
    --
    -- A v2.5 proibia globalmente NEEDS_REVIEW + printing_profile_id null.
    -- A premissa era: "so um backfill em massa poderia ter escrito isso".
    -- Verdadeira enquanto NENHUM produtor gravava perfil em NEEDS_REVIEW.
    -- A PHASE C acabou com isso: o outcome B da Query 2181 v1.2 manda,
    -- literalmente, "variant_type_id REMOVIDO + printing_profile_id
    -- explicito (JSON null ou UUID)" quando a Impressao resolve e o
    -- Variant Type nao. Perfil explicito em NEEDS_REVIEW virou CONTRATO.
    --
    -- Proibir o valor gravado nunca foi o alvo certo — e um sintoma que
    -- duas origens opostas compartilham. O alvo certo e a CONSEQUENCIA
    -- que so a origem ilegitima produz.
    --
    -- Contrato A/B/C (Query 2181 v1.2), lado a lado:
    --
    --   A  VALID          variant_type_id PRESENTE   perfil null|UUID
    --   B  NEEDS_REVIEW   variant_type_id AUSENTE    perfil null|UUID
    --   C  NEEDS_REVIEW   variant_type_id AUSENTE    perfil AUSENTE
    --
    -- Nos dois desfechos de NEEDS_REVIEW o variant_type_id esta AUSENTE.
    -- Logo: NEEDS_REVIEW com variant_type_id viola B e C simultaneamente,
    -- e nenhum produtor legitimo consegue cria-lo. E o que um backfill
    -- descuidado produziria — e e o que esta assercao passa a caçar.
    --
    -- A propriedade e ESTRUTURAL, nao temporal: nao depende de job_id,
    -- created_at, cutoff de deploy nem de excecao nominal para a Edge v9.
    -- Vale para toda row, de qualquer origem, hoje e depois.
    --
    -- -------------------------------------------------------------------
    -- KNOWN DEBT — PROVENANCE (registrado em 2026-09-13, NAO resolvido)
    --
    -- Severidade: MEDIA / NAO BLOQUEANTE.
    --
    -- Esta assercao NAO consegue distinguir:
    --
    --   (a) outcome B LEGITIMO — NEEDS_REVIEW que recebeu
    --       printing_profile_id null porque o roteamento resolveu a
    --       Impressao e o Variant Type nao resolveu; de
    --
    --   (b) uma row do outcome C que tivesse recebido
    --       printing_profile_id null por uma escrita externa indevida.
    --
    -- Os dois estados sao byte a byte identicos: mesmo status, mesmo
    -- variant_type_id ausente, mesmo null. Nenhum predicado read-only
    -- estrutural os separa. So provenance (metadado de origem gravado na
    -- propria row) ou reavaliacao pelo roteamento — que e o que a Query
    -- 2181 faz sob demanda — resolveria.
    --
    -- Por que isso NAO bloqueia:
    --   1. A Query 2183 nao consegue produzir (b): o WHERE dela so
    --      alcanca rows VALID.
    --   2. Esta assercao pega a variante MAIS GRAVE do mesmo erro — o
    --      backfill descuidado que tambem mantivesse variant_type_id.
    --   3. O confirm (2179) nao e enganado: sem variant_type_id a row nao
    --      tem identidade canonica e nao chega a criar card_variant.
    --
    -- A v2.5 "pegava" (b) por acidente historico: proibia o estado B
    -- inteiro, que na epoca nao existia. Era cobertura obtida ao preco de
    -- rejeitar o contrato vigente — e foi o que travou a PHASE D.
    --
    -- Endereçar isto exige provenance, NUNCA excecao temporal.
    -- -------------------------------------------------------------------
    SELECT count(*) INTO v_needs_review_with_key
      FROM public.catalog_variant_import_row
     WHERE validation_status = 'NEEDS_REVIEW'
       AND normalized_data ? 'variant_type_id';

    IF v_needs_review_with_key <> 0 THEN
        RAISE EXCEPTION 'S23.03 FALHOU: % row(s) NEEDS_REVIEW carregam variant_type_id. Os outcomes B e C da Query 2181 v1.2 exigem variant_type_id AUSENTE em toda row NEEDS_REVIEW — sem Impressao resolvida o residual nao e identidade canonica confiavel, e com Impressao resolvida mas sem Variant Type nao ha o que gravar. ATENCAO: perfil explicito (null ou UUID) em NEEDS_REVIEW e o outcome B LEGITIMO e nao e erro; o que esta assercao proibe e a identidade canonica sobreviver a uma row que nao a tem.', v_needs_review_with_key;
    END IF;

    -- A constraint final PODE ser validada agora.
    IF EXISTS (
        SELECT 1 FROM public.catalog_variant_import_row
         WHERE validation_status = 'VALID' AND NOT (normalized_data ? 'printing_profile_id')
    ) THEN
        RAISE EXCEPTION 'S23.04 FALHOU: a constraint final da PHASE E nao validaria. STOP.';
    END IF;
END;
$s23$;

SELECT 'S23 POST-BACKFILL H21/H22: 4 assercoes PASS' AS resumo;


-- #############################################################################
-- ##                                                                         ##
-- ##   B L O C O   I V   —   F I N A L - E   ( S24 .. S25 )                   ##
-- ##                                                                         ##
-- ##   RODAR SOMENTE APOS A QUERY 2184 (PHASE E).                             ##
-- ##                                                                         ##
-- #############################################################################

-- =============================================================================
-- SECAO 24 — R5: INVARIANTE FINAL + BRIDGE REMOVIDO
-- =============================================================================
DO $s24$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                AND indexname='uq_cvir_job_card_type_bridge_legacy')
    THEN RAISE EXCEPTION 'S24.01 FALHOU: o bridge ainda existe apos a PHASE E.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                    AND indexname='uq_cvir_job_card_type_no_printing')
       OR NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                    AND indexname='uq_cvir_job_card_type_printing')
    THEN RAISE EXCEPTION 'S24.02 FALHOU: um dos dois indices canonicos desapareceu.'; END IF;

    -- A constraint final existe E esta VALIDADA (convalidated = true).
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid='public.catalog_variant_import_row'::regclass
           AND conname='ck_catalog_variant_import_row_valid_requires_printing_key'
           AND convalidated
    ) THEN
        RAISE EXCEPTION 'S24.03 FALHOU: a constraint final nao existe ou ficou NOT VALID. Uma constraint NOT VALID nao prova nada sobre o passado.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid='public.catalog_variant_import_row'::regclass
           AND conname='ck_catalog_variant_import_row_printing_profile_shape'
    ) THEN
        RAISE EXCEPTION 'S24.04 FALHOU: o CHECK de forma desapareceu. Presenca sem tipo nao e contrato.';
    END IF;
END;
$s24$;

SELECT 'S24 FINAL-E INVARIANTE + BRIDGE: 4 assercoes PASS' AS resumo;


-- =============================================================================
-- SECAO 25 — R2/R5: O ESTADO PROIBIDO E IMPOSSIVEL
-- =============================================================================
BEGIN;

DO $s25$
DECLARE
    v_job UUID; v_card UUID; v_type UUID; v_game UUID; v_ok BOOLEAN; v_src TEXT;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_type FROM public.card_variant_type WHERE game_id=v_game AND code='STANDARD';

    SELECT j.id, r.card_id INTO v_job, v_card
      FROM public.catalog_variant_import_job j
      JOIN public.catalog_variant_import_row r ON r.job_id = j.id
     LIMIT 1;

    IF v_job IS NULL THEN RAISE EXCEPTION 'S25.FIXTURE: nenhum job com rows encontrado.'; END IF;

    -- VALID sem a chave: agora IMPOSSIVEL no banco.
    v_ok := FALSE;
    BEGIN
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
        VALUES (v_job, v_card, '{"type":"holo"}'::JSONB,
                jsonb_build_object('variant_type_id', v_type::TEXT), 'VALID');
    EXCEPTION WHEN check_violation THEN v_ok := TRUE;
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S25.01 FALHOU: uma linha VALID sem a chave printing_profile_id foi aceita apos a PHASE E.';
    END IF;

    -- NEEDS_REVIEW sem a chave continua LEGITIMO.
    BEGIN
        INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status)
        VALUES (v_job, v_card, '{"type":"holo","subtype":"harness-unknown"}'::JSONB,
                '{}'::JSONB, 'NEEDS_REVIEW');
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'S25.02 FALHOU: NEEDS_REVIEW sem a chave foi rejeitada. "Ainda nao sei" e estado legitimo.';
    END;

    -- Zero VALID sem a chave em todo o universo.
    IF EXISTS (
        SELECT 1 FROM public.catalog_variant_import_row
         WHERE validation_status='VALID' AND NOT (normalized_data ? 'printing_profile_id')
    ) THEN RAISE EXCEPTION 'S25.03 FALHOU: existe VALID sem a chave — a constraint nao esta valendo.'; END IF;
END;
$s25$;

ROLLBACK;

DO $s25b$
DECLARE
    v_src TEXT;
BEGIN
    SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='admin_confirm_catalog_variant_import';

    -- O ramo de compatibilidade ainda esta no codigo (nao foi removido
    -- por migration), mas esta EXTINTO na pratica: o bridge sumiu.
    IF position('uq_cvir_job_card_type_bridge_legacy' IN COALESCE(v_src,'')) = 0 THEN
        RAISE EXCEPTION 'S25.04 FALHOU: o confirm perdeu a amarracao ao bridge. Sem ela nao ha como afirmar que a compatibilidade expirou.';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                AND indexname='uq_cvir_job_card_type_bridge_legacy')
    THEN RAISE EXCEPTION 'S25.05 FALHOU: o bridge existe — a compatibilidade transitoria continua ativa.'; END IF;
END;
$s25b$;

SELECT 'S25 FINAL-E ESTADO PROIBIDO IMPOSSIVEL: 5 assercoes PASS' AS resumo;


-- #############################################################################
-- ##                                                                         ##
-- ##   S26   —   B L O C O   I   ( G A T E - A )   —   R E A D E R           ##
-- ##                                                                         ##
-- ##   Acrescentada pela STAGING-REVISION-02. Pertence ao BLOCO I, mas        ##
-- ##   mora no fim do arquivo para nao renumerar secoes ja referenciadas      ##
-- ##   nos rodapes das migrations.                                           ##
-- ##                                                                         ##
-- ##   RODAR DEPOIS de S1..S20 e ANTES de S21 (zero residuo).                 ##
-- ##   Pressupoe 2185 e 2186 aplicadas.                                      ##
-- ##                                                                         ##
-- #############################################################################

-- =============================================================================
-- SECAO 26 — L01..L07: CONTRATO DE LEITURA DO LOG
--
-- Toda a Secao roda em UMA transacao revertida. As linhas de log sao
-- fixtures inseridas aqui e desaparecem no ROLLBACK; S21 prova isso.
--
-- A leitura exige contexto de administrador — mesma impersonacao de
-- S13/S14. Sem admin cadastrado, FALHA ALTO.
-- =============================================================================
BEGIN;

DO $s26$
DECLARE
    v_admin UUID;
    v_game UUID;
    v_src UUID;
    v_pem UUID;
    v_vtem UUID;
    -- UUID sintético válido, deliberadamente inexistente em qualquer
    -- tabela (v4 com corpo zerado). Serve ao caso de entidade removida
    -- ou inacessível.
    v_ghost UUID := '00000000-0000-4000-8000-000000000001'::UUID;
    v_id_meta UUID; v_id_live UUID; v_id_ghost UUID; v_id_vtem UUID;
    v_label TEXT;
    v_n BIGINT;
    v_missing TEXT;
BEGIN
    SELECT id INTO v_admin FROM public.admin_user LIMIT 1;
    IF v_admin IS NULL THEN
        RAISE EXCEPTION 'S26.SETUP FALHOU: nenhum administrador cadastrado em admin_user. L01-L07 NAO PODEM ser provados nesta base — nao registrar como PASS.';
    END IF;

    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code='TCGDEX';

    -- Mapping de Impressao REAL, vindo da seed da Query 2175.
    SELECT id INTO v_pem FROM public.card_printing_external_mapping
     WHERE game_id=v_game AND asset_source_id=v_src
       AND raw_field='subtype' AND normalized_token='SHADOWLESS-RED-CHEEK' AND is_active;
    IF v_pem IS NULL THEN
        RAISE EXCEPTION 'S26.SETUP FALHOU: mapping de Impressao da seed nao encontrado. A Query 2175 rodou?';
    END IF;

    SELECT id INTO v_vtem FROM public.card_variant_type_external_mapping LIMIT 1;
    IF v_vtem IS NULL THEN
        RAISE EXCEPTION 'S26.SETUP FALHOU: nenhum mapping de Tipo de Variacao existe. L05 nao pode ser provado.';
    END IF;

    -- =====================================================================
    -- FIXTURES — tres linhas de log de Impressao, uma por caminho de
    -- resolucao, e uma de Variant Type.
    -- =====================================================================

    -- (a) metadata COMPLETO, apontando para um mapping real.
    --     Serve a L01 e, junto de (b), a L02.
    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (v_admin, 'CARD_PRINTING_EXTERNAL_MAPPING_CREATED',
            'CARD_PRINTING_EXTERNAL_MAPPING', v_pem,
            jsonb_build_object('harness', 'HARNESS-S26',
                               'raw_field', 'stamp',
                               'normalized_token', 'HARNESS-META-WINS'))
    RETURNING id INTO v_id_meta;

    -- (b) SEM as chaves de label, mesmo mapping real -> tabela viva.
    --     O marcador 'harness' existe so para S21 provar zero residuo;
    --     ele nao participa de nenhuma branch de entity_label.
    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (v_admin, 'CARD_PRINTING_EXTERNAL_MAPPING_CREATED',
            'CARD_PRINTING_EXTERNAL_MAPPING', v_pem,
            jsonb_build_object('harness', 'HARNESS-S26'))
    RETURNING id INTO v_id_live;

    -- (c) SEM as chaves de label e entidade INEXISTENTE -> fallback UUID.
    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (v_admin, 'CARD_PRINTING_EXTERNAL_MAPPING_CREATED',
            'CARD_PRINTING_EXTERNAL_MAPPING', v_ghost,
            jsonb_build_object('harness', 'HARNESS-S26'))
    RETURNING id INTO v_id_ghost;

    -- (d) Variant Type Mapping, sem as chaves de label -> tabela viva.
    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
    VALUES (v_admin, 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING', v_vtem,
            jsonb_build_object('harness', 'HARNESS-S26'))
    RETURNING id INTO v_id_vtem;

    -- =====================================================================
    -- IMPERSONACAO — a leitura e admin-only.
    -- =====================================================================
    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', v_admin::TEXT, 'role', 'authenticated')::TEXT,
                       true);

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'S26.SETUP FALHOU: impersonacao de administrador sem efeito. NAO registrar como PASS.';
    END IF;

    -- =====================================================================
    -- L01 — Printing Mapping resolve para label legivel, nao UUID.
    -- =====================================================================
    SELECT r.entity_label INTO v_label
      FROM public.admin_list_catalog_action_log(
               p_entity_type => 'CARD_PRINTING_EXTERNAL_MAPPING', p_limit => 100) r
     WHERE r.id = v_id_meta;

    IF v_label IS NULL THEN
        RAISE EXCEPTION 'S26.L01 FALHOU: a linha de Impressao nao apareceu no reader.';
    END IF;
    IF v_label = v_pem::TEXT THEN
        RAISE EXCEPTION 'S26.L01 FALHOU: entity_label continua sendo o UUID cru. A Query 2186 rodou?';
    END IF;

    -- =====================================================================
    -- L02 — metadata VENCE o fallback da tabela viva.
    -- =====================================================================
    IF v_label <> 'stamp · HARNESS-META-WINS' THEN
        RAISE EXCEPTION 'S26.L02 FALHOU: esperado "stamp · HARNESS-META-WINS" (metadata), obtido "%". A ordem metadata -> tabela viva nao esta sendo respeitada.', v_label;
    END IF;

    -- =====================================================================
    -- L03 — metadata ausente: a tabela viva resolve.
    -- =====================================================================
    SELECT r.entity_label INTO v_label
      FROM public.admin_list_catalog_action_log(
               p_entity_type => 'CARD_PRINTING_EXTERNAL_MAPPING', p_limit => 100) r
     WHERE r.id = v_id_live;

    IF v_label <> 'subtype · SHADOWLESS-RED-CHEEK' THEN
        RAISE EXCEPTION 'S26.L03 FALHOU: sem metadata, esperado "subtype · SHADOWLESS-RED-CHEEK" da tabela viva, obtido "%".', COALESCE(v_label, '<nulo>');
    END IF;

    -- =====================================================================
    -- L04 — entidade inexistente: fallback UUID continua funcionando.
    -- =====================================================================
    SELECT r.entity_label INTO v_label
      FROM public.admin_list_catalog_action_log(
               p_entity_type => 'CARD_PRINTING_EXTERNAL_MAPPING', p_limit => 100) r
     WHERE r.id = v_id_ghost;

    IF v_label IS DISTINCT FROM v_ghost::TEXT THEN
        RAISE EXCEPTION 'S26.L04 FALHOU: para entidade inexistente o label deveria ser o UUID, obtido "%". O fallback final foi perdido.', COALESCE(v_label, '<nulo>');
    END IF;

    -- =====================================================================
    -- L05 — Variant Type Mapping resolve para a assinatura externa.
    -- =====================================================================
    SELECT r.entity_label INTO v_label
      FROM public.admin_list_catalog_action_log(
               p_entity_type => 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING', p_limit => 100) r
     WHERE r.id = v_id_vtem;

    IF v_label IS NULL THEN
        RAISE EXCEPTION 'S26.L05 FALHOU: a linha de Variant Type Mapping nao apareceu no reader.';
    END IF;
    IF v_label = v_vtem::TEXT THEN
        RAISE EXCEPTION 'S26.L05 FALHOU: Variant Type Mapping continua exibindo UUID cru. O mapping irmao ficou para tras.';
    END IF;
    -- A assinatura externa sempre comeca pelo type, que e NOT NULL.
    IF v_label NOT LIKE (SELECT external_type FROM public.card_variant_type_external_mapping WHERE id = v_vtem) || '%' THEN
        RAISE EXCEPTION 'S26.L05 FALHOU: o label "%" nao comeca pela assinatura externa (external_type) do mapping.', v_label;
    END IF;

    -- =====================================================================
    -- L06 — nenhum entity_type existente regrediu.
    --
    -- Para cada entity_type que TEM linhas reais (fora as fixtures desta
    -- Secao), pelo menos uma tem que resolver para algo diferente do UUID.
    -- Tipos sem dado real sao ignorados — exigir label de conjunto vazio
    -- seria um FAIL artificial.
    -- =====================================================================
    SELECT string_agg(t.entity_type, ', ' ORDER BY t.entity_type) INTO v_missing
      FROM (
            SELECT DISTINCT l.entity_type
              FROM public.catalog_admin_action_log l
             WHERE l.id NOT IN (v_id_meta, v_id_live, v_id_ghost, v_id_vtem)
      ) t
     WHERE NOT EXISTS (
            SELECT 1
              FROM public.admin_list_catalog_action_log(
                       p_entity_type => t.entity_type, p_limit => 100) r
             WHERE r.id NOT IN (v_id_meta, v_id_live, v_id_ghost, v_id_vtem)
               AND r.entity_label IS DISTINCT FROM r.entity_id::TEXT
     );

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'S26.L06 FALHOU: entity_type(s) com dado real e NENHUMA linha resolvida para label humano: %. Regressao ou branch faltando.', v_missing;
    END IF;

    -- =====================================================================
    -- L07 — p_search encontra o mapping novo pelo label HUMANO.
    --
    -- Prova direta de que o filtro atua sobre o valor ja resolvido, e nao
    -- contra as colunas cruas da tabela.
    -- =====================================================================
    SELECT count(*) INTO v_n
      FROM public.admin_list_catalog_action_log(
               p_search => 'HARNESS-META-WINS', p_limit => 100) r
     WHERE r.id = v_id_meta;

    IF v_n <> 1 THEN
        RAISE EXCEPTION 'S26.L07 FALHOU: p_search pelo label humano devolveu % linha(s), esperada 1.', v_n;
    END IF;

    SELECT count(*) INTO v_n
      FROM public.admin_list_catalog_action_log(
               p_search => 'SHADOWLESS-RED-CHEEK', p_limit => 100) r
     WHERE r.id = v_id_live;

    IF v_n <> 1 THEN
        RAISE EXCEPTION 'S26.L07 FALHOU: p_search pelo label resolvido da tabela viva devolveu % linha(s), esperada 1.', v_n;
    END IF;

    -- =====================================================================
    -- CONTRATO PRESERVADO — total_count, paginacao e autorizacao.
    -- =====================================================================
    SELECT count(DISTINCT r.total_count) INTO v_n
      FROM public.admin_list_catalog_action_log(p_limit => 5) r;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'S26.L08 FALHOU: total_count divergente entre linhas da mesma pagina.';
    END IF;

    SELECT count(*) INTO v_n FROM public.admin_list_catalog_action_log(p_limit => 500) r;
    IF v_n > 100 THEN
        RAISE EXCEPTION 'S26.L09 FALHOU: p_limit acima do teto devolveu % linhas — o teto de 100 foi perdido.', v_n;
    END IF;
END;
$s26$;

DO $s26b$
DECLARE
    v_ok BOOLEAN := FALSE;
    v_msg TEXT;
    v_n BIGINT;
BEGIN
    -- Autorizacao: sem admin, a funcao levanta excecao (nunca lista vazia).
    PERFORM set_config('request.jwt.claims', '{}', true);

    BEGIN
        SELECT count(*) INTO v_n FROM public.admin_list_catalog_action_log(p_limit => 1) r;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%ADMIN_LIST_CATALOG_ACTION_LOG_FORBIDDEN%';
    END;

    IF NOT v_ok THEN
        RAISE EXCEPTION 'S26.L10 FALHOU: a funcao nao recusou chamador nao-administrador com a excecao esperada.';
    END IF;
END;
$s26b$;

SELECT 'S26 L01-L07 CONTRATO DE LEITURA (+ total_count, teto, autorizacao): 10 assercoes PASS' AS resumo;

ROLLBACK;

-- =============================================================================
-- LEMBRETE: a Secao S21 (zero residuo) deve ser executada DEPOIS desta.
-- Ela e quem prova que as 4 linhas de log inseridas aqui desapareceram.
-- =============================================================================


-- #############################################################################
-- ##                                                                         ##
-- ##   S27  —  B L O C O   I   ( G A T E - A )  —  C O N T R A T O           ##
-- ##            T E M P O R A L   D O   S E L O   D E F E R I D O            ##
-- ##                                                                         ##
-- ##   Acrescentada pela STAGING-CORRECTION-03. Pertence ao BLOCO I.         ##
-- ##   RODAR junto de S26, antes de S21.                                     ##
-- ##                                                                         ##
-- #############################################################################

-- =============================================================================
-- SECAO 27 — B-01 TESTADO DIRETAMENTE, SEM PASSAR PELA 2181
--
-- A S14 prova o B-01 de fora, pelo efeito (propagacao real). Esta Secao
-- prova de dentro, pelo contrato: chama compute_variant_residual_signature()
-- com o mapping AINDA NAO SELADO e verifica o que ele responde.
--
-- Dois casos, e eles sao opostos de proposito:
--
--   (a) ACTIVE + traits_signature NULL + N:N COMPLETA
--         -> tem que RESOLVER pela N:N da propria transacao.
--
--   (b) ACTIVE + traits_signature NULL + N:N VAZIA
--         -> tem que FALHAR FECHADO, com estado proprio.
--            Nao e RESOLVED_NO_PRINTING (o token TEM routing, so esta
--            quebrado) e nao e NEEDS_REVIEW_INACTIVE_MAPPING (o mapping
--            esta ATIVO).
--
-- Nenhum COMMIT acontece: o trigger deferido de selamento nunca chega a
-- disparar, e o caso (b) — que ele rejeitaria — permanece observavel.
-- =============================================================================
BEGIN;

DO $s27a$
DECLARE
    v_game UUID; v_src UUID; v_trait UUID; v_profile UUID; v_map UUID;
    r RECORD;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code='TCGDEX';
    SELECT id INTO v_trait   FROM public.card_printing_trait   WHERE game_id=v_game AND code='UNLIMITED';
    SELECT id INTO v_profile FROM public.card_printing_profile WHERE game_id=v_game AND code='UNLIMITED';

    IF v_trait IS NULL OR v_profile IS NULL THEN
        RAISE EXCEPTION 'S27.SETUP FALHOU: trait/profile UNLIMITED nao encontrados.';
    END IF;

    -- (a) Cabecalho ATIVO, composicao completa, SEM selo.
    INSERT INTO public.card_printing_external_mapping
        (game_id, asset_source_id, raw_field, normalized_token, external_token, is_active)
    VALUES (v_game, v_src, 'stamp', 'HARNESS-S27-OK', 'harness-s27-ok', TRUE)
    RETURNING id INTO v_map;

    INSERT INTO public.card_printing_external_mapping_trait (mapping_id, trait_id, game_id)
    VALUES (v_map, v_trait, v_game);

    -- Pre-condicao do teste: o selo NAO pode ter sido gravado ainda.
    IF (SELECT traits_signature FROM public.card_printing_external_mapping WHERE id = v_map) IS NOT NULL THEN
        RAISE EXCEPTION 'S27.PRE FALHOU: traits_signature ja esta preenchida antes do COMMIT. O trigger de selamento deixou de ser DEFERIDO — o contrato temporal mudou e esta Secao precisa ser reescrita.';
    END IF;

    SELECT * INTO r FROM internal.compute_variant_residual_signature(
        '{"type":"normal","stamp":["harness-s27-ok"]}'::JSONB, v_game, v_src);

    IF r.printing_state <> 'RESOLVED_WITH_PROFILE' THEN
        RAISE EXCEPTION 'S27.01 FALHOU (REGRESSAO B-01): mapping ATIVO com composicao completa porem NAO SELADA devolveu "%". A funcao esta lendo apenas traits_signature em vez da assinatura EFETIVA.', r.printing_state;
    END IF;

    IF r.printing_profile_id IS DISTINCT FROM v_profile THEN
        RAISE EXCEPTION 'S27.02 FALHOU: perfil resolvido = %, esperado UNLIMITED (%).', COALESCE(r.printing_profile_id::TEXT,'<nulo>'), v_profile;
    END IF;

    IF cardinality(r.residual_stamp) <> 0 THEN
        RAISE EXCEPTION 'S27.03 FALHOU: o token foi consumido pelo Printing mas continuou no residual.';
    END IF;

    IF r.residual_type <> 'NORMAL' THEN
        RAISE EXCEPTION 'S27.04 FALHOU: o acabamento foi alterado.';
    END IF;
END;
$s27a$;

SELECT 'S27a UNSEALED + N:N COMPLETA: resolve pela composicao PASS' AS resumo;

ROLLBACK;

BEGIN;

DO $s27b$
DECLARE
    v_game UUID; v_src UUID; v_map UUID; r RECORD;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code='TCGDEX';

    -- (b) Cabecalho ATIVO, SEM composicao e SEM selo. Estado
    -- estruturalmente invalido — que o COMMIT rejeitaria, mas que existe
    -- de fato durante a transacao.
    INSERT INTO public.card_printing_external_mapping
        (game_id, asset_source_id, raw_field, normalized_token, external_token, is_active)
    VALUES (v_game, v_src, 'stamp', 'HARNESS-S27-EMPTY', 'harness-s27-empty', TRUE)
    RETURNING id INTO v_map;

    SELECT * INTO r FROM internal.compute_variant_residual_signature(
        '{"type":"normal","stamp":["harness-s27-empty"]}'::JSONB, v_game, v_src);

    IF r.printing_state = 'RESOLVED_NO_PRINTING' THEN
        RAISE EXCEPTION 'S27.05 FALHOU: mapping ATIVO com composicao vazia foi tratado como "sem Impressao". O token TEM routing — ele so esta quebrado. Isso o devolveria ao residual e o reclassificaria como acabamento.';
    END IF;

    IF r.printing_state = 'NEEDS_REVIEW_INACTIVE_MAPPING' THEN
        RAISE EXCEPTION 'S27.06 FALHOU: mapping ATIVO com composicao vazia foi classificado como INATIVO. O diagnostico esta errado: o mapping existe e esta ativo; o defeito e a composicao.';
    END IF;

    IF r.printing_state <> 'NEEDS_REVIEW_INVALID_PRINTING_MAPPING' THEN
        RAISE EXCEPTION 'S27.07 FALHOU: esperado NEEDS_REVIEW_INVALID_PRINTING_MAPPING, obtido "%".', r.printing_state;
    END IF;

    IF r.printing_profile_id IS NOT NULL OR cardinality(r.trait_ids) <> 0 THEN
        RAISE EXCEPTION 'S27.08 FALHOU: estado de erro nao pode devolver perfil nem traits.';
    END IF;

    -- E o token NAO pode voltar ao residual.
    IF cardinality(r.residual_stamp) <> 0 THEN
        RAISE EXCEPTION 'S27.09 FALHOU: token de mapping invalido voltou ao residual — viraria acabamento.';
    END IF;
END;
$s27b$;

SELECT 'S27b UNSEALED + N:N VAZIA: fail-closed com estado proprio PASS' AS resumo;

ROLLBACK;
