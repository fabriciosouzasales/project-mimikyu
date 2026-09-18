/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2191 - Add Source-Set Scope to
              card_variant_type_external_mapping
Versão......: 1.0
Status......: MIGRATION / CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-14
Executado...: 2026-09-14, via apply_migration (MCP Supabase), projeto
              qjfutqujxrbzgrtkpgkg. Ledger: 20260914024650 /
              2191_add_source_set_scope_to_card_variant_type_external_mapping
Reclassif..: 2026-09-18, BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01
Canônica....: dobrada em database/schema/2140_create_card_variant_type_
              external_mapping_table.sql v2.0
Mandato.....: CARD-VARIANTS — EDITORIAL-CONVERGENCE-16 /
              SOURCE-SET-SCOPED-FOUNDATION / GATE-A-STAGING-01

Descrição...:
Torna o mapping de Card Variant Type CONTEXTUAL por source-set,
de forma estritamente ADITIVA.

Problema que resolve (provado em EDITORIAL-CONVERGENCE-12/13/14):
a TCGdex anota o MESMO token `foil: galaxy` com dois sentidos
editoriais incompatíveis —

  - em `base3` (Fóssil, 1999) `galaxy` é o padrão holográfico
    DEFAULT do set inteiro (não existe outra holo na fonte);
  - em `sv03.5`/`sv05`/`sv06` `galaxy` é um tratamento ESPECIAL,
    declarado pela fonte como uma TERCEIRA variante ao lado da
    holo default da mesma carta.

O mapping global atual `HOLO·GALAXY → GALAXY_HOLO` não consegue
distinguir os dois. Repontá-lo atingiria 3 card_variant modernos;
repontar `HOLO·NULL` atingiria 1.679. Nenhuma das duas é aceitável.
A divergência é DA FONTE e é POR SET — logo o escopo pertence ao
vocabulário da fonte.

--------------------------------------------------------------
O QUE ESTA QUERY FAZ
--------------------------------------------------------------
1. Adiciona `external_set_id TEXT NULL`.
     NULL      = mapping GLOBAL (comportamento atual)
     preenchido = mapping SOURCE_SET_SCOPED
2. CHECK de não-vazio (string vazia e whitespace-only PROIBIDAS).
3. FK COMPOSTA para a chave canônica de source-set.
4. Troca o mecanismo de unicidade por DOIS índices parciais.

--------------------------------------------------------------
POR QUE FK COMPOSTA, E NÃO TEXT LIVRE
--------------------------------------------------------------
`public.card_set_external_reference` JÁ possui a UNIQUE elegível:

    uq_card_set_external_reference_source_external
        ON (asset_source_id, external_set_id)

197 linhas, `external_set_id TEXT NOT NULL`, collation default —
compatível com a coluna nova. `asset_source_id` é `uuid NOT NULL`
nos dois lados. Confirmado por catálogo em 2026-09-14.

Usar TEXT livre com validação só em RPC seria aceitar campo-lixo
silencioso por conveniência, havendo chave canônica disponível.

--------------------------------------------------------------
>>> MATCH SIMPLE É INTENCIONAL — NÃO TROCAR POR MATCH FULL <<<
--------------------------------------------------------------
- `asset_source_id` é NOT NULL nesta tabela, SEMPRE.
- `external_set_id` é NULL nos mappings GLOBAIS (as 70 linhas
  atuais, e todo mapping global futuro).
- Com MATCH SIMPLE (o default do PostgreSQL), quando QUALQUER
  coluna da FK é NULL a constraint é satisfeita sem checagem.
  Resultado: linha GLOBAL passa; linha SCOPED é validada contra
  card_set_external_reference.
- Com MATCH FULL, o par teria de ser "ambos NULL" ou "ambos NOT
  NULL". Como asset_source_id nunca é NULL, TODA linha global
  seria REJEITADA e os 70 mappings existentes quebrariam na hora.

Se alguém "corrigir" isto para MATCH FULL, o sistema para.
O harness 2826 tem caso dedicado (B) para travar essa regressão.

--------------------------------------------------------------
UNICIDADE — DOIS ÍNDICES PARCIAIS (NÃO sentinela, NÃO NULLS NOT DISTINCT)
--------------------------------------------------------------
Descartadas deliberadamente:

- COALESCE(external_set_id, '') como sentinela: a sentinela ''
  colidiria com um external_set_id vazio literal. Só é segura
  porque o CHECK proíbe '' — ou seja, depende de outra regra para
  não ser ambígua. Índices parciais não dependem de nada.

- UNIQUE NULLS NOT DISTINCT (disponível: PostgreSQL LIVE é 17.6):
  a propriedade vale para o ÍNDICE INTEIRO, não para uma coluna.
  Aplicá-la mudaria também a semântica de normalized_foil/
  normalized_subtype/normalized_stamp, que hoje usam COALESCE
  explícito: hoje `foil = NULL` e `foil = ''` COLIDEM; sob NULLS
  NOT DISTINCT passariam a ser DISTINTOS. Isso é alteração
  semântica silenciosa da unicidade existente — proibido pelo
  requisito de retrocompatibilidade.

O índice GLOBAL é a expressão do índice atual mais o predicado
`WHERE external_set_id IS NULL`. Como as 70 linhas existentes
recebem NULL por default de coluna, todas caem nele e a unicidade
delas fica BYTE-SEMANTICAMENTE IDÊNTICA à de hoje.

--------------------------------------------------------------
O MECANISMO ATUAL É ÍNDICE, NÃO CONSTRAINT
--------------------------------------------------------------
Confirmado por catálogo em 2026-09-14:
  - pg_constraint de contype IN ('u','p') sobre a tabela devolve
    APENAS a PRIMARY KEY;
  - `uq_card_variant_type_external_mapping_combo` existe somente
    em pg_indexes.
Logo `DROP INDEX` é suficiente e correto. Não há
`ALTER TABLE ... DROP CONSTRAINT` a fazer. Isso já era a intenção
da Query 2140 v1.1 (item 2 da correção): índice com COALESCE como
ÚNICO mecanismo de unicidade da tabela.

--------------------------------------------------------------
RETROCOMPATIBILIDADE
--------------------------------------------------------------
- 70 linhas existentes: recebem external_set_id = NULL.
- Nenhum UPDATE de dado. Nenhuma linha reescrita.
- Com ZERO overrides cadastrados, o comportamento do sistema é
  idêntico ao de hoje.
- A contextualização é ADITIVA: nenhum mapping precisa migrar.

Pré-requisitos:
- Query 2140 - Create card_variant_type_external_mapping Table.
- Query 1xxx/2xxx - card_set_external_reference com a UNIQUE
  (asset_source_id, external_set_id) — já existente e populada.

STD-001 §504: migration que altera constraint e estrutura junto
roda dentro de BEGIN; ... COMMIT;.
================================================================
*/

BEGIN;

-- =============================================================
-- 1. COLUNA DE ESCOPO
-- =============================================================

ALTER TABLE public.card_variant_type_external_mapping
    ADD COLUMN external_set_id TEXT NULL;

-- Sem upper/lower, sem regex estreita: o valor PRESERVA
-- literalmente a identidade da fonte (ex. 'base3', 'sv03.5').
-- A restrição de domínio real vem da FK composta abaixo, que é
-- mais forte e mais portável para fontes futuras do que qualquer
-- expressão regular que se pudesse escrever hoje.
ALTER TABLE public.card_variant_type_external_mapping
    ADD CONSTRAINT ck_card_variant_type_external_mapping_external_set_id_not_blank
        CHECK (external_set_id IS NULL OR btrim(external_set_id) <> '');

-- =============================================================
-- 2. FK COMPOSTA — INTEGRIDADE REAL DO SOURCE-SET
--
-- MATCH SIMPLE: ver bloco dedicado no cabeçalho. Declarado
-- explicitamente (e não por omissão) para que a intenção fique
-- registrada no próprio DDL.
-- =============================================================

ALTER TABLE public.card_variant_type_external_mapping
    ADD CONSTRAINT fk_card_variant_type_external_mapping_source_set
        FOREIGN KEY (asset_source_id, external_set_id)
        REFERENCES public.card_set_external_reference (asset_source_id, external_set_id)
        MATCH SIMPLE
        ON DELETE RESTRICT;

-- =============================================================
-- 3. UNICIDADE — DOIS ÍNDICES PARCIAIS DISJUNTOS
-- =============================================================

DROP INDEX public.uq_card_variant_type_external_mapping_combo;

-- A. GLOBAL — expressão idêntica à do índice removido, mais o
--    predicado. Garante: no máximo 1 mapping global por combo.
CREATE UNIQUE INDEX uq_card_variant_type_external_mapping_combo_global
    ON public.card_variant_type_external_mapping (
        game_id, asset_source_id, normalized_type,
        COALESCE(normalized_foil, ''),
        COALESCE(normalized_subtype, ''),
        COALESCE(normalized_stamp, '{}'::TEXT[])
    )
    WHERE external_set_id IS NULL;

-- B. SCOPED — garante: no máximo 1 mapping por (source-set, combo).
--    Dois source-sets diferentes coexistem livremente, porque
--    external_set_id participa da chave.
CREATE UNIQUE INDEX uq_card_variant_type_external_mapping_combo_scoped
    ON public.card_variant_type_external_mapping (
        game_id, asset_source_id, external_set_id, normalized_type,
        COALESCE(normalized_foil, ''),
        COALESCE(normalized_subtype, ''),
        COALESCE(normalized_stamp, '{}'::TEXT[])
    )
    WHERE external_set_id IS NOT NULL;

-- Os dois índices são DISJUNTOS por construção (os predicados são
-- complementares e exaustivos). Um mapping global e um scoped para
-- o mesmo combo vivem em índices diferentes e coexistem — é
-- exatamente o estado que a precedência scoped > global exige.

-- Suporte ao lookup com precedência (Query 2198): o LATERAL filtra
-- por (game_id, asset_source_id) e por
-- `external_set_id IS NULL OR external_set_id = <escopo>`.
CREATE INDEX ix_card_variant_type_external_mapping_scope_lookup
    ON public.card_variant_type_external_mapping
       (game_id, asset_source_id, external_set_id);

-- =============================================================
-- 4. DOCUMENTAÇÃO NO CATÁLOGO
-- =============================================================

COMMENT ON COLUMN public.card_variant_type_external_mapping.external_set_id IS
    'Escopo do mapping no vocabulário da FONTE. NULL = GLOBAL (vale para todos os Sets daquela Fonte/Game). Preenchido = SOURCE_SET_SCOPED (vale só para aquele source-set). Precedência de UM nível: scoped vence, global é fallback, ausência = NEEDS_REVIEW. Integridade por FK composta (asset_source_id, external_set_id) -> card_set_external_reference, MATCH SIMPLE (intencional: permite a linha global, em que external_set_id e NULL).';

COMMENT ON CONSTRAINT fk_card_variant_type_external_mapping_source_set
    ON public.card_variant_type_external_mapping IS
    'MATCH SIMPLE E INTENCIONAL. asset_source_id e NOT NULL; external_set_id e NULL nos mappings globais. Sob MATCH SIMPLE, qualquer coluna NULL satisfaz a FK sem checagem -> global passa, scoped e validado. MATCH FULL rejeitaria TODA linha global e quebraria os mappings existentes.';

COMMIT;

-- ================================================================
-- VALIDAÇÃO: database/proposals/2026-09-14-card-variant-mapping-
-- source-set-scope/2826_validate_source_set_scoped_variant_type_
-- mapping.sql (casos A, B, C, D, E, F, G, H, Y).
--
-- CONFIRMADO EXECUTADO em 2026-09-14 (GATE-B-EXECUTION-01). Cópia mantida em
-- proposals/ como evidência histórica do ciclo.
-- ================================================================
