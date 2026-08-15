/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2140 - Create card_variant_type_external_mapping Table
Versão......: 1.1
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Cria public.card_variant_type_external_mapping — traduz a combinação
bruta de variante de uma Fonte externa (type/foil/subtype/stamp da
TCGdex) para o Card Variant Type canônico correspondente, por
Game+Fonte. Mesmo espírito de rarity_external_mapping (Query 2096,
emenda 2026-08-07 do ADR-024), generalizado para 4 dimensões em vez
de 1 — a raridade é um único valor de texto; uma variante é uma
combinação de até 4 campos, e o mapeamento precisa distinguir a
combinação completa, não só type (ex.: reverse+foil:pokeball e
reverse+foil:energy são combinações diferentes, mapeando para
POKE_BALL_REVERSE e ENERGY_REVERSE respectivamente).

Correção v1.1 (2026-08-15, mesma sessão, antes da execução): revisão
pedida por Fabrício sobre a proposta v1.0. Duas mudanças, nenhuma
outra decisão já aprovada foi alterada:
1. stamp deixou de ser TEXT (que forçaria serialização de um array em
   texto, ex. join por vírgula — lossy e ambíguo se um valor real
   contivesse o separador) e passou a TEXT[] (external_stamp e
   normalized_stamp), preservando fielmente zero, um ou múltiplos
   stamps, exatamente como a TCGdex pode devolver (ex.
   ["1st-edition"], ou combinações futuras com mais de um elemento).
   normalized_stamp é gravado ORDENADO (elementos normalizados via
   normalize_external_catalog_value(), depois ordenados) por quem
   grava — mesma responsabilidade de quem grava já valia para os
   demais campos normalized_*; ordenar é o que torna duas combinações
   com os mesmos stamps em ordem diferente na fonte equivalentes para
   fins de unicidade/match (arrays do Postgres comparam posição a
   posição, não como conjunto, então a ordenação é o que garante a
   semântica de "conjunto de stamps").
2. Eliminada a redundância entre a CONSTRAINT UNIQUE original (que
   tratava NULL como sempre distinto, nunca detectando de fato uma
   combinação repetida quando foil/subtype/stamp eram nulos) e o
   ÍNDICE ÚNICO com COALESCE que já existia para cobrir esse caso.
   Mantido só o índice com COALESCE
   (uq_card_variant_type_external_mapping_combo) como único mecanismo
   de unicidade — é o único que de fato garante a regra de negócio
   (combinação completa, inclusive quando algum campo é ausente).

Regras de Negócio:
- external_type/external_foil/external_subtype/external_stamp
  preservam o dado original exato da fonte (auditoria/exibição). Só
  external_type é NOT NULL — os demais são nulos quando a fonte não
  reporta aquela dimensão para a combinação (ex.: "normal" não tem
  foil nem subtype nem stamp).
- normalized_type/normalized_foil/normalized_subtype/normalized_stamp
  usam normalize_external_catalog_value() (Query 2095, já existente e
  compartilhada com rarity_external_mapping) — toda busca/comparação
  usa os campos normalizados, nunca os brutos. Mesmo padrão de
  rarity_external_mapping: normalização é responsabilidade de quem
  grava (função futura ou, nesta Query, a seed), não de um trigger da
  tabela.
- Unicidade por (game_id, asset_source_id, normalized_type,
  COALESCE(normalized_foil,''), COALESCE(normalized_subtype,''),
  COALESCE(normalized_stamp, '{}'::TEXT[])) — único mecanismo de
  unicidade da tabela (ver Correção v1.1, item 2). Distingue a
  combinação completa, não só o tipo. COALESCE necessário porque NULL
  <> NULL no Postgres tornaria duas linhas com o mesmo type mas
  foil/stamp ausentes indistinguíveis de duplicatas sem essa
  normalização defensiva.
- CHECKs de guarda em external_stamp/normalized_stamp: quando não
  nulo, o array não pode ser vazio (cardinality > 0 — vazio e NULL
  seriam duas formas redundantes de dizer "sem stamp") nem conter
  elemento NULL (array_position(..., NULL) IS NULL).
- FKs para game/asset_source/card_variant_type, todas ON DELETE
  RESTRICT — mesmo raciocínio de rarity_external_mapping.
- RLS habilitado com leitura restrita a administradores
  (catalog_admin_select, USING ((select is_admin()))) — diferente de
  rarity_external_mapping (que hoje não tem nenhuma policy, achado
  confirmado via pg_policies nesta mesma sessão, não replicado aqui
  deliberadamente): esta tabela nasce com a policy explícita, mesmo
  padrão já consolidado no restante do projeto. GRANT SELECT para
  authenticated e service_role; nenhum GRANT de escrita ainda — a
  seed desta Query grava diretamente (mesma via usada para os 25
  aliases de raridade, Query 2104); escrita self-service via RPC fica
  para um incremento futuro, fora do escopo aprovado agora.
- updated_at mantido por trigger compartilhado (Query 2141).

Pré-requisitos:
- Query 100 - Create Game Table.
- Query 990 - Create Asset Source Table.
- Query 150 - Create Card Variant Type Table.
- Query 2095 - Create normalize_external_catalog_value() Function.
================================================================
*/

BEGIN;

CREATE TABLE public.card_variant_type_external_mapping (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.game (id) ON DELETE RESTRICT,
    asset_source_id UUID NOT NULL REFERENCES public.asset_source (id) ON DELETE RESTRICT,

    external_type TEXT NOT NULL,
    external_foil TEXT,
    external_subtype TEXT,
    external_stamp TEXT[],

    normalized_type TEXT NOT NULL,
    normalized_foil TEXT,
    normalized_subtype TEXT,
    normalized_stamp TEXT[],

    variant_type_id UUID NOT NULL REFERENCES public.card_variant_type (id) ON DELETE RESTRICT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_card_variant_type_external_mapping_type_not_blank
        CHECK (btrim(external_type) <> ''),
    CONSTRAINT ck_card_variant_type_external_mapping_normalized_type_not_blank
        CHECK (btrim(normalized_type) <> ''),
    CONSTRAINT ck_card_variant_type_external_mapping_stamp_not_empty
        CHECK (external_stamp IS NULL OR cardinality(external_stamp) > 0),
    CONSTRAINT ck_card_variant_type_external_mapping_stamp_no_null_elements
        CHECK (external_stamp IS NULL OR array_position(external_stamp, NULL) IS NULL),
    CONSTRAINT ck_card_variant_type_external_mapping_normalized_stamp_not_empty
        CHECK (normalized_stamp IS NULL OR cardinality(normalized_stamp) > 0),
    CONSTRAINT ck_card_variant_type_external_mapping_normalized_stamp_no_null_elements
        CHECK (normalized_stamp IS NULL OR array_position(normalized_stamp, NULL) IS NULL)
);

-- Único mecanismo de unicidade da tabela (ver Correção v1.1, item 2 no
-- cabeçalho) — COALESCE trata a ausência de foil/subtype/stamp como um
-- valor comparável, não como "sempre distinto" (comportamento padrão
-- de NULL numa UNIQUE constraint comum).
CREATE UNIQUE INDEX uq_card_variant_type_external_mapping_combo
    ON public.card_variant_type_external_mapping (
        game_id, asset_source_id, normalized_type,
        COALESCE(normalized_foil, ''),
        COALESCE(normalized_subtype, ''),
        COALESCE(normalized_stamp, '{}'::TEXT[])
    );

CREATE INDEX ix_card_variant_type_external_mapping_variant_type
    ON public.card_variant_type_external_mapping (variant_type_id);

COMMENT ON TABLE public.card_variant_type_external_mapping IS
    'Traduz a combinação bruta de variante (type/foil/subtype/stamp) de uma Fonte externa para o Card Variant Type canônico, por Game+Fonte. Incremento 1 do bloco Card Variant, ADR-028.';

COMMENT ON COLUMN public.card_variant_type_external_mapping.external_stamp IS
    'Array bruto de stamps da fonte (ex. TCGdex), preservado integralmente — zero, um ou múltiplos elementos. Não usado por nenhuma seed desta Query (vintage em aberto).';

COMMENT ON COLUMN public.card_variant_type_external_mapping.normalized_stamp IS
    'Array normalizado e ORDENADO (elementos via normalize_external_catalog_value(), ordem canônica) — garante que duas combinações com os mesmos stamps em ordem diferente na fonte sejam tratadas como a mesma combinação.';

COMMENT ON COLUMN public.card_variant_type_external_mapping.normalized_type IS
    'Via normalize_external_catalog_value() (Query 2095) — toda busca/comparação usa os campos normalizados, nunca os brutos.';

ALTER TABLE public.card_variant_type_external_mapping ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select ON public.card_variant_type_external_mapping
    FOR SELECT USING ((select public.is_admin()));

GRANT SELECT ON public.card_variant_type_external_mapping TO authenticated, service_role;

COMMIT;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), depois de dry-run em BEGIN...ROLLBACK
-- que incluiu dois testes reais de idempotência: (a) inserir "Normal"
-- quando "normal" já existia — rejeitado por unique_violation; (b)
-- inserir os mesmos 2 stamps em ordem/caixa diferente de uma
-- combinação já existente — também rejeitado, confirmando que a
-- normalização ordenada trata a combinação como conjunto, não
-- sequência. Repetido com sucesso na execução real (produção),
-- também dentro de BEGIN...ROLLBACK, sem persistir a duplicata de
-- teste. pg_policies confirma catalog_admin_select com
-- qual = "( SELECT is_admin() AS is_admin)"; role_table_grants
-- confirma SELECT para authenticated e service_role, nenhum grant de
-- escrita, nenhum grant para anon. EXPLAIN (FORMAT JSON) de uma busca
-- pela combinação reverse+foil:pokeball confirma Index Scan via
-- uq_card_variant_type_external_mapping_combo (Total Cost 7.1), sem
-- Seq Scan.
-- ================================================================
