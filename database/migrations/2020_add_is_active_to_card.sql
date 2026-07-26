/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2020 - Add is_active to Card
Versão......: 1.0
Status......: MIGRATION
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Adiciona public.card.is_active — soft delete real e irrestrito,
não condicionado à ausência de dependentes (ADR-023, seção "Card:
is_active como soft delete real").

Regras de Negócio:
- NOT NULL DEFAULT true: as 927 Cards existentes tornam-se ativas
  automaticamente, sem exigir um backfill separado.
- Desativação nunca é cascateada para card_variant, card_asset ou
  card_external_reference — nenhuma dessas tabelas é tocada por
  esta Query nem pela futura admin_deactivate_card() (Query 2039).
- A UNIQUE(card_set_id, collector_number) já existente
  (uq_card_card_set_collector_number, Query 140) permanece válida
  independentemente de is_active — não é alterada por esta Query.
  Uma Card inativa continua ocupando sua chave natural; qualquer
  cadastro ou importação que colida com ela resolve como conflito
  explícito, nunca reativação silenciosa.
- Toda leitura operacional (web/lib/catalogo/queries.ts e
  qualquer nova) passa a considerar is_active = true por padrão —
  ajuste da camada de leitura fica fora do escopo desta Query,
  tratado no ciclo vertical de Card (backend/tela/validação),
  quando admin_deactivate_card()/admin_reactivate_card() (2039/
  2040) e o controle de inativas na tela existirem de fato.
- Nenhum índice criado nesta Query: volume atual (927 linhas) não
  justifica a manutenção de um índice para um filtro que, na
  prática, seleciona quase 100% das linhas hoje. Reavaliar quando
  o volume de Cards inativas crescer.

Pré-requisitos:
- Query 140 - Create Card Table.
================================================================
*/

ALTER TABLE public.card
    ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN public.card.is_active IS
    'Soft delete real e irrestrito (ADR-023). true = participa de consultas operacionais por padrão. '
    'Desativação nunca cascateia para card_variant/card_asset/card_external_reference.';
