/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2096 - Create rarity_external_mapping Table
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Cria public.rarity_external_mapping — traduz o valor bruto de
raridade de uma Fonte externa (ex. "Rara Holo" da TCGdex) para a
Raridade canônica correspondente, por Game+Fonte. Substitui
RARITY_NAME_ALIASES (mapa hardcoded em
import-catalog-cards/services/normalize.ts) por dado, permitindo
cadastro/correção self-service via UI (/catalogo/raridades) sem
deploy de código.

Regras de Negócio:
- Unicidade por (game_id, asset_source_id, normalized_external_value)
  — o mesmo valor bruto normalizado não pode mapear para duas
  Raridades diferentes na mesma Fonte/Game; case/acento/espaço não
  distinguem duas linhas (uq_rarity_external_mapping).
- external_value preserva o texto original exato (auditoria/
  exibição); normalized_external_value (via Query 2095) é usado
  em toda busca/comparação — nunca comparar contra external_value
  diretamente.
- FKs para game/asset_source/rarity, todas ON DELETE RESTRICT —
  nenhuma das três pode ser excluída enquanto houver mapeamento
  dependente (nenhuma das três tem exclusão real via UI hoje,
  mas a proteção existe por construção).
- updated_at mantido por trigger (Query 2097), mesmo padrão de
  set_updated_at() já usado em outras tabelas do módulo.

Pré-requisitos:
- Query 100/990 - Create Game / Asset Source Tables.
- Query 130 - Create Rarity Table.
================================================================
*/

CREATE TABLE public.rarity_external_mapping (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.game(id) ON DELETE RESTRICT,
    asset_source_id UUID NOT NULL REFERENCES public.asset_source(id) ON DELETE RESTRICT,
    external_value TEXT NOT NULL,
    normalized_external_value TEXT NOT NULL,
    rarity_id UUID NOT NULL REFERENCES public.rarity(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_rarity_external_mapping_external_value_not_blank
        CHECK (btrim(external_value) <> ''),
    CONSTRAINT ck_rarity_external_mapping_normalized_value_not_blank
        CHECK (btrim(normalized_external_value) <> ''),
    CONSTRAINT uq_rarity_external_mapping
        UNIQUE (game_id, asset_source_id, normalized_external_value)
);

ALTER TABLE public.rarity_external_mapping ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.rarity_external_mapping TO authenticated, service_role;

-- ================================================================
-- Confirmado executado (2026-08-07): 7 colunas, 5 constraints (PK,
-- 3 FKs, 2 CHECKs) + UNIQUE, RLS habilitado, GRANT SELECT presente
-- para authenticated e service_role (information_schema.columns/
-- pg_constraint/role_table_grants). 30 linhas em produção (backfill
-- da Query 2104 + cadastros self-service via UI).
-- ================================================================
