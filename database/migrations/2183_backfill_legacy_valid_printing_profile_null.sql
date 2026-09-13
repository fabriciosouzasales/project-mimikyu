/*
===============================================================================
   ███  EXECUTADA / VALIDADA — PHASE D CLOSED  ███

   Executada em 2026-09-13 no LIVE, via execute_sql, em transação única
   com SET LOCAL mimikyu.phase_c_edge_deployed = 'CONFIRMED'.

       GUARD 0 ............ PASS
       GUARD 1 ............ PASS — 5.653 candidatas, 0 ofensores
       UPDATE ............. 5653 rows
       POSTCHECK interno .. PASS — VALID sem a chave = 0
       COMMIT ............. sucesso

   Validada pelo harness: Query 2824 v2.6, BLOCO III (Secao S23) —
   4 assercoes PASS.

   NAO criou entrada em supabase_migrations.schema_migrations: e um
   backfill DML historico, nao uma alteracao estrutural. A rastreabilidade
   vive neste arquivo e no registro de rollout.

   A restricao historica deste arquivo — "NAO aplicar antes do deploy da
   Edge Function nova em producao" — foi cumprida: a PHASE C estava
   fechada e o S22 havia passado. O GUARD 0 abaixo permanece no codigo e
   continua sendo a trava contra reexecucao acidental; o WHERE e
   idempotente e uma reexecucao encontraria 0 candidatas.
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2183 - Backfill Legacy VALID with Explicit printing_profile_id null
Versão......: 1.2
Status......: MIGRATION — CONFIRMADO EXECUTADO / LIVE — PHASE D CLOSED
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Promovida...: 2026-09-13 — TECHNICAL-CLOSEOUT-PROMOTION-01
Origem......: database/proposals/2026-09-12-card-variants-printing-routing/
              2183_backfill_legacy_valid_printing_profile_null.sql
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§13)
               + STAGING-REVISION-01 (R1)
               + PHASE-D-STAGING-CORRECTION-01 (§1, §2) — BLOCKER D-1
Fase........: PHASE D do rollout

Alterações da versão 1.2 (PHASE-D-STAGING-CORRECTION-01, BLOCKER D-1):
- GUARD 1 passa a auditar EXATAMENTE o universo que o UPDATE pode
  atingir, em vez de todas as rows VALID do sistema.

  O guard perguntava:
      "alguma VALID do sistema contém Printing ratificado?"
  quando a pergunta que protege o backfill é:
      "alguma row QUE RECEBERIA null contém Printing ratificado?"

  As duas coincidiam enquanto o writer antigo era o único produtor —
  nenhuma VALID podia carregar token de Impressão, porque o eixo não
  existia. A PHASE C acabou com essa coincidência: a Edge nova resolve
  o token, grava o perfil e marca VALID. Essas rows são o SUCESSO do
  modelo, e o guard as lia como contaminação.

  Medido no LIVE depois da primeira execução real da Edge nova:
      VALID com token Printing ratificado ........... 48
      dessas, JA com a chave printing_profile_id .... 48
      dessas, SEM a chave (candidatas ao UPDATE) .....  0

  Ou seja: o guard abortava por 48 rows que o proprio WHERE do UPDATE
  ja excluia. Fail-closed correto, universo errado.

- A protecao NAO foi enfraquecida. O guard continua abortando a
  transacao inteira se UMA candidata carregar token ratificado. O que
  mudou e que ele parou de olhar para fora do proprio alvo.

- Premissas de cardinalidade historica removidas do cabecalho (§2 do
  mandato). "5.653" passa a ser baseline auditado, nao verdade
  estrutural; "505 NEEDS_REVIEW" some, porque o contrato relevante e
  qualitativo: NEEDS_REVIEW nao sao tocadas, seja qual for a contagem.

Alterações da versão 1.1 (STAGING-REVISION-01, BLOCKER R1):
- GUARD 0 (autorização de fase) acrescentado. A v1.0 tinha um guard que
  checava a coisa certa mas na hora errada: ele PASSA hoje, antes do
  deploy da Edge nova. Ou seja, a v1.0 rodaria com sucesso durante o
  Gate A/B e produziria um backfill incompleto por corrida com o writer
  antigo — exatamente o que a PHASE D existe para evitar.
- Banner DEFERRED / DO NOT PROMOTE no topo.

Descrição resumida:
Adiciona "printing_profile_id": null explicito as rows VALID LEGADAS —
as que tem variant_type_id e ainda nao tem a chave de Impressao. Elas
sao, por construcao, "Printing RESOLVED / sem perfil".

-------------------------------------------------------------------------------
PREMISSA AUDITADA — E REVALIDADA AQUI ANTES DE ESCREVER
-------------------------------------------------------------------------------
A premissa que importa e sobre o CANDIDATE SET — o conjunto que o UPDATE
pode atingir —, nunca sobre a tabela inteira:

    candidates da 2183 com token Printing ratificado = 0

Um candidate e uma row VALID, com variant_type_id, SEM a chave de
Impressao. Se ela tivesse token ratificado, receber null seria afirmar
"sem perfil" sobre uma carta que TEM perfil — e e exatamente isso que o
GUARD 1 impede.

Baseline auditado no LIVE em 2026-09-13, depois da primeira execucao
real da Edge nova (BASE3):

    candidates ............................. 5.653
    candidates com token ratificado ........      0
    candidates pertencentes a BASE3 ........      0
    candidates NEEDS_REVIEW ................      0

Esse 5.653 e uma FOTOGRAFIA, nao um invariante. Ele cai a zero depois
desta Query e nao volta a crescer enquanto a Edge nova for a unica
produtora — porque ela ja nasce gravando a chave. Nenhum guard aqui
depende desse numero.

O GUARD 1 abaixo NAO confia em medicao nenhuma: ele REFAZ a auditoria no
momento da execucao, sobre o candidate set do proprio momento, e ABORTA
a transacao inteira se encontrar um unico ofensor. Premissa envelhece;
guard nao.

-------------------------------------------------------------------------------
O QUE NAO MUDA
-------------------------------------------------------------------------------
variant_type_id · raw_data · decision_status · match_status ·
matched_variant_id · resulting_variant_id · persistence_status ·
validation_status · nenhuma card_variant.

A UNICA escrita e acrescentar uma chave a normalized_data.

-------------------------------------------------------------------------------
NENHUMA NEEDS_REVIEW E TOCADA
-------------------------------------------------------------------------------
Deliberado, e independente de quantas existam. Elas NAO recebem null em
massa: serao reavaliadas pelo routing, e algumas terao perfil de verdade
(as de BASE1, por exemplo). Dar null a elas seria afirmar "sem perfil"
antes de perguntar.

Cuidado para nao confundir dois estados que se parecem no dump e sao
opostos na origem:

    NEEDS_REVIEW + printing_profile_id null DECLARADO em massa
        -> proibido. E o que esta Query se recusa a fazer.

    NEEDS_REVIEW + printing_profile_id null RESOLVIDO pelo routing
        -> legitimo. E o outcome B da Query 2181 v1.2: Impressao
           resolvida, Variant Type nao. O perfil fica explicito; o
           variant_type_id e que sai.

A diferenca nao esta no valor gravado — esta em quem gravou e por que. O
WHERE desta Query so alcanca rows VALID, entao o primeiro caso e
estruturalmente impossivel aqui.

Idempotente: o WHERE exige a chave AUSENTE. Reexecucao nao faz nada.

Pré-requisitos:
- Query 2177 - CHECK de forma + indices de identidade.
- Edge Function nova JA em producao (senao o writer antigo continua
  criando rows sem a chave e o backfill fica incompleto por corrida).
===============================================================================
*/

BEGIN;

-- =========================================================================
-- GUARD 0 — AUTORIZAÇÃO DE FASE. Fail-closed, e intransponível por
-- acidente.
--
-- O operador precisa declarar, na MESMA transação, que a PHASE C está
-- concluída:
--
--     BEGIN;
--     SET LOCAL mimikyu.phase_c_edge_deployed = 'CONFIRMED';
--     \i 2183_backfill_legacy_valid_printing_profile_null.sql
--
-- O QUE ESTE GUC É — E O QUE ELE NÃO É
--
-- É: uma CONFIRMAÇÃO OPERACIONAL EXPLÍCITA DO EXECUTOR. Um ato
-- deliberado, impossível de acontecer por acidente, que serve de trava
-- contra reexecução do lote A/B ou replay por um runner de migrations.
--
-- NÃO é: prova técnica de nada. O banco não tem como verificar que a
-- Edge nova foi deployed nem que o writer antigo deixou de existir.
-- Este SET LOCAL não verifica isso — ele apenas registra que alguém
-- afirmou isso.
--
-- A autorização REAL da PHASE D continua sendo a conjunção de:
--   (a) PASS do harness da fase anterior — Query 2824, BLOCO II (S22),
--       que é a única evidência observável de que o writer vigente
--       honra o contrato de saída;
--   (b) checklist operacional do rollout (README, §4);
--   (c) o operador executar explicitamente o SET LOCAL abaixo.
--
-- O GUC é (c). Sozinho, não substitui (a) nem (b).
-- =========================================================================
DO $phase$
BEGIN
    IF COALESCE(current_setting('mimikyu.phase_c_edge_deployed', true), '') <> 'CONFIRMED' THEN
        RAISE EXCEPTION 'PHASE_D_NOT_AUTHORIZED: esta Query pertence à PHASE D e só pode ser executada depois que a Edge Function nova estiver em produção. Se e somente se isso for verdade, execute na mesma transação: SET LOCAL mimikyu.phase_c_edge_deployed = ''CONFIRMED''; STOP.';
    END IF;
END;
$phase$;

-- =========================================================================
-- GUARD 1 — refaz a auditoria de conteúdo. Fail-closed.
--
-- ESCOPO (v1.2, BLOCKER D-1): o guard audita o CANDIDATE SET — exatamente
-- as rows que o UPDATE abaixo pode atingir —, e o predicado-base aqui e o
-- MESMO WHERE do UPDATE. Isso nao e detalhe de implementacao: e a unica
-- forma de a pergunta do guard coincidir com o risco que ele protege.
--
-- O risco e: "esta Query vai gravar 'sem perfil' em alguma carta que TEM
-- perfil?". Uma row que ja carrega a chave nao recebe nada e nao pode
-- correr esse risco, por mais token de Impressao que o raw_data dela
-- tenha.
--
-- A versao anterior varria TODAS as VALID. Isso foi equivalente enquanto
-- o writer antigo era o unico produtor — sem eixo de Impressao, nenhuma
-- VALID podia carregar token ratificado, e os dois conjuntos coincidiam.
-- A PHASE C rompeu a coincidencia: a Edge nova resolve o token, grava o
-- perfil e marca VALID. O guard antigo lia esse sucesso como contaminacao
-- e abortava a PHASE D por rows que o UPDATE nem alcanca.
--
-- Se o predicado-base do UPDATE mudar algum dia, ele TEM que mudar aqui
-- junto. Os dois descreverem o mesmo conjunto e o contrato desta Query.
-- =========================================================================
DO $guard$
DECLARE
    v_candidates INTEGER;
    v_offenders INTEGER;
BEGIN
    SELECT
        count(*),
        count(*) FILTER (
            WHERE public.normalize_external_catalog_value(r.raw_data ->> 'subtype')
                      IN ('SHADOWLESS', 'UNLIMITED', '1999-2000-COPYRIGHT', 'SHADOWLESS-RED-CHEEK')
               OR (
                    jsonb_typeof(r.raw_data -> 'stamp') = 'array'
                    AND EXISTS (
                        SELECT 1 FROM jsonb_array_elements_text(r.raw_data -> 'stamp') e
                         WHERE public.normalize_external_catalog_value(e) = '1ST-EDITION'
                    )
                  )
        )
      INTO v_candidates, v_offenders
      FROM public.catalog_variant_import_row r
     -- PREDICADO-BASE: identico, termo a termo, ao WHERE do UPDATE.
     WHERE r.validation_status = 'VALID'
       AND (r.normalized_data ->> 'variant_type_id') IS NOT NULL
       AND jsonb_typeof(r.normalized_data -> 'printing_profile_id') IS NULL;

    IF v_offenders <> 0 THEN
        RAISE EXCEPTION 'BACKFILL_PRINTING_NULL_UNSAFE: % de % candidata(s) ao backfill contêm token de Impressão ratificado no raw_data. Elas NÃO são "resolvidas sem perfil" e não podem receber null — reprocesse-as pela Edge, que resolve o eixo de Impressão, em vez de declará-las sem perfil. STOP — reauditar antes de qualquer escrita.', v_offenders, v_candidates;
    END IF;

    RAISE NOTICE 'GUARD 1 OK: % candidata(s), 0 com token de Impressão ratificado.', v_candidates;
END;
$guard$;

-- =========================================================================
-- BACKFILL — só onde a chave está AUSENTE.
-- =========================================================================
UPDATE public.catalog_variant_import_row r
   SET normalized_data = jsonb_set(r.normalized_data, '{printing_profile_id}', 'null'::JSONB, true)
 WHERE r.validation_status = 'VALID'
   AND (r.normalized_data ->> 'variant_type_id') IS NOT NULL
   AND jsonb_typeof(r.normalized_data -> 'printing_profile_id') IS NULL;

-- =========================================================================
-- POSTCHECK — na mesma transacao. Se falhar, nada e commitado.
-- =========================================================================
DO $post$
DECLARE
    v_absent INTEGER;
BEGIN
    SELECT count(*) INTO v_absent
      FROM public.catalog_variant_import_row r
     WHERE r.validation_status = 'VALID'
       AND jsonb_typeof(r.normalized_data -> 'printing_profile_id') IS NULL;

    IF v_absent <> 0 THEN
        RAISE EXCEPTION 'BACKFILL_PRINTING_NULL_INCOMPLETE: ainda restam % row(s) VALID sem a chave printing_profile_id.', v_absent;
    END IF;
END;
$post$;

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   UPDATE <n>, onde <n> e o candidate set no momento da execucao. Baseline
--   auditado em 2026-09-13: 5653. Sera menor se a Edge nova tiver gravado
--   mais rows com a chave nesse meio-tempo — o WHERE e idempotente.
--   NOTICE do GUARD 1 reportando <n> candidatas e 0 ofensores.
--   VALID com printing_profile_id ausente = 0.
--   NEEDS_REVIEW: nenhuma tocada, qualquer que seja a contagem.
--   card_variant: intacta. Bridge: intacto.
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Secao S23 (BLOCO III).
--   Precondicao ja provada no GATE A: Secao S15 (H21 + H22-contrato).
--
-- ----------------------------------------------------------------------------
-- Revision History
-- ----------------------------------------------------------------------------
--  1.0  Versao inicial (2026-09-12). Backfill das rows VALID legadas com
--       "printing_profile_id": null explicito, sob GUARD de conteudo.
--
--  1.1  STAGING-REVISION-01, BLOCKER R1 (2026-09-12). GUARD 0 de
--       autorizacao de fase acrescentado — a v1.0 rodaria com sucesso
--       durante o Gate A/B e produziria backfill incompleto por corrida
--       com o writer antigo. Banner DEFERRED / DO NOT PROMOTE no topo.
--
--  1.2  PHASE-D-STAGING-CORRECTION-01, BLOCKER D-1 (2026-09-13). GUARD 1
--       passa a auditar o CANDIDATE SET (o mesmo predicado-base do UPDATE)
--       em vez de todas as rows VALID. Com a PHASE C em producao, rows
--       VALID legitimamente carregam token de Impressao E a chave ja
--       resolvida — o guard antigo abortava por 48 delas, nenhuma
--       alcancavel pelo UPDATE. Protecao inalterada em forca; universo
--       corrigido. Premissas de cardinalidade historica ("VALID com token
--       ratificado = 0", "505 NEEDS_REVIEW") substituidas pelo invariante
--       do candidate set. Revision History criada.
--
--       PROMOCAO (2026-09-13, TECHNICAL-CLOSEOUT-PROMOTION-01). Copiada de
--       database/proposals/ para database/migrations/ nesta mesma versao
--       1.2. O SQL executavel permanece identico ao artefato executado no
--       LIVE; so o cabecalho registra o estado final (Status, Promovida,
--       Origem). A proposal original e preservada como historico.
-- ============================================================================
