/*
===============================================================================
   ███  DEFERRED — DO NOT PROMOTE / DO NOT APPLY DURING GATE A/B  ███

   Este arquivo NÃO faz parte do lote de migrations do Gate A/B.

   NÃO promover para database/migrations/ junto com 2172–2182/2185.
   NÃO aplicar antes do deploy da Edge Function nova em produção.

   A promoção deste arquivo ocorre SOMENTE no gate da PHASE D, depois de
   executado e confirmado — como manda a convenção do projeto ("scripts
   só entram em database/ depois de confirmadamente executados").

   O script se RECUSA a rodar sem autorização explícita de fase. Ver
   "GUARD 0" abaixo. Isto não é decoração: é o que impede que uma
   reexecução acidental do lote A/B dispare a PHASE D.
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2183 - Backfill Legacy VALID with Explicit printing_profile_id null
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADA — DEFERRED (PHASE D)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§13)
               + STAGING-REVISION-01 (R1)
Fase........: PHASE D do rollout

Alterações da versão 1.1 (STAGING-REVISION-01, BLOCKER R1):
- GUARD 0 (autorização de fase) acrescentado. A v1.0 tinha um guard que
  checava a coisa certa mas na hora errada: ele PASSA hoje, antes do
  deploy da Edge nova. Ou seja, a v1.0 rodaria com sucesso durante o
  Gate A/B e produziria um backfill incompleto por corrida com o writer
  antigo — exatamente o que a PHASE D existe para evitar.
- Banner DEFERRED / DO NOT PROMOTE no topo.

Descrição resumida:
Adiciona "printing_profile_id": null explicito as 5.653 rows VALID
legadas, que semanticamente ja sao "Printing RESOLVED / sem perfil".

-------------------------------------------------------------------------------
PREMISSA AUDITADA — E REVALIDADA AQUI ANTES DE ESCREVER
-------------------------------------------------------------------------------
Medicao no LIVE (2026-09-12):
    catalog_variant_import_row VALID        = 5.653
    VALID com token Printing ratificado     = 0
    69 mappings de Variant Type com subtype = 0
    69 mappings com stamp 1st-edition       = 0

Portanto as 5.653 sao, por construcao, Printing RESOLVED sem perfil.

O GUARD 1 abaixo NAO confia nessa medicao: ele a REFAZ no momento da
execucao e ABORTA a transacao inteira se qualquer row VALID contiver um
token Printing ratificado. Premissa envelhece; guard nao.

-------------------------------------------------------------------------------
O QUE NAO MUDA
-------------------------------------------------------------------------------
variant_type_id · raw_data · decision_status · match_status ·
matched_variant_id · resulting_variant_id · persistence_status ·
validation_status · nenhuma card_variant.

A UNICA escrita e acrescentar uma chave a normalized_data.

-------------------------------------------------------------------------------
AS 505 NEEDS_REVIEW NAO SAO TOCADAS
-------------------------------------------------------------------------------
Deliberado. Elas NAO recebem null em massa: serao reavaliadas pelo
routing, e algumas terao perfil de verdade (as 410 de BASE1). Dar null a
elas seria afirmar "sem perfil" antes de perguntar.

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
-- =========================================================================
DO $guard$
DECLARE
    v_offenders INTEGER;
BEGIN
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
        RAISE EXCEPTION 'BACKFILL_PRINTING_NULL_UNSAFE: % row(s) VALID contêm token de Impressão ratificado. Elas NÃO são "resolvidas sem perfil" e não podem receber null. STOP — reauditar antes de qualquer escrita.', v_offenders;
    END IF;
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
--   UPDATE 5653 (ou menos, se a Edge nova ja tiver gravado algumas com a
--   chave — o WHERE e idempotente).
--   VALID com printing_profile_id ausente = 0.
--   505 NEEDS_REVIEW inalteradas.
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Secao S23 (BLOCO III).
--   Precondicao ja provada no GATE A: Secao S15 (H21 + H22-contrato).
-- ============================================================================
