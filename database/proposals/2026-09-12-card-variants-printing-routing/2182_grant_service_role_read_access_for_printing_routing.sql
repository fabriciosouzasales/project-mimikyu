/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2182 - Grant service_role Read Access for Printing Routing
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§22)
Precedente..: Query 2148 (mesma decisao para o pipeline de Variant Type)

Descrição resumida:
Concede SELECT ao service_role em EXATAMENTE tres tabelas de Printing —
as unicas que o runtime da Edge Function precisa ler.

-------------------------------------------------------------------------------
ESTADO CONFIRMADO NO LIVE (antes desta Query)
-------------------------------------------------------------------------------
    card_variant_type_external_mapping   service_role SELECT = TRUE
    card_printing_trait                  service_role SELECT = FALSE
    card_printing_profile                service_role SELECT = FALSE
    card_printing_profile_trait          service_role SELECT = FALSE

A Edge Function import-card-variants usa o client service_role. Sem estes
grants, o preload de Printing falha e o routing nao acontece.

-------------------------------------------------------------------------------
LEAST PRIVILEGE — O QUE FICA DE FORA, E POR QUE
-------------------------------------------------------------------------------
CONCEDIDO (3):
  card_printing_external_mapping  token -> traits_signature + is_active.
                                  O cabecalho selado basta: a assinatura
                                  ja carrega os trait_id.
  card_printing_trait             SO para saber is_active (estado 3:
                                  trait inativo -> NEEDS_REVIEW).
  card_printing_profile           id + game_id + traits_signature +
                                  is_active, para o match exato de
                                  conjunto (estados 2 e 5).

NAO CONCEDIDO (2):
  card_printing_external_mapping_trait   redundante — a assinatura do
                                         cabecalho ja entrega os trait_id.
  card_printing_profile_trait            redundante — idem, pela
                                         assinatura do profile.

As duas tabelas de composicao sao a FONTE DA VERDADE semantica e ficam
acessiveis so a admin. O runtime opera exclusivamente sobre assinaturas
seladas. Esse foi o criterio que reduziu o escopo de 5 tabelas para 3.

NENHUMA escrita. service_role nao recebe INSERT/UPDATE/DELETE em
nenhuma tabela de Printing — toda mutacao passa por RPC admin.

Pré-requisitos:
- Query 2165, 2166 - Print Trait / Print Profile (LIVE).
- Query 2172 - Card Printing External Mapping.
===============================================================================
*/

BEGIN;

GRANT SELECT ON public.card_printing_external_mapping TO service_role;
GRANT SELECT ON public.card_printing_trait            TO service_role;
GRANT SELECT ON public.card_printing_profile          TO service_role;

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   GRANT x3. Nenhum grant de escrita. Nenhum grant em
--   card_printing_external_mapping_trait nem em card_printing_profile_trait.
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Secao S19 (SEGURANCA).
-- ============================================================================
