/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2172 - Create Card Printing External Mapping Table
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Promovida...: 2026-09-13 — TECHNICAL-CLOSEOUT-PROMOTION-01
Origem......: database/proposals/2026-09-12-card-variants-printing-routing/
              2172_create_card_printing_external_mapping_table.sql
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§3, §4)
Contratos...: AUDIT-GATE-01 · CONTRACT-CORRECTION-01 · CONTRACT-CORRECTION-02

Descrição resumida:
Cria public.card_printing_external_mapping — o CABEÇALHO do routing de
Printing: token externo (raw_field + normalized_token) -> conjunto de
Print Traits.

Descrição:
Este e o objeto que transforma a assinatura externa em dois resultados
INDEPENDENTES:

    raw signature  ->  Printing traits          (esta tabela)
                   ->  residual signature       (Query 2176)
                       -> Variant Type          (card_variant_type_external_mapping)

O token externo representa SEMANTICAMENTE UM CONJUNTO de traits, logo
tem identidade propria. A composicao real vive na N:N da Query 2173;
traits_signature aqui e materializacao derivada, exatamente como em
card_printing_profile (Query 2166).

-------------------------------------------------------------------------------
POR QUE HISTORICO COM UM UNICO ATIVO
-------------------------------------------------------------------------------
CONTRACT-CORRECTION-02 identificou uma incompatibilidade real no desenho
anterior: UNIQUE ABSOLUTO por token + composicao IMUTAVEL tornavam um
mapping errado impossivel de corrigir — nao da para alterar a composicao
(imutavel) nem criar outro mapping para o mesmo token (UNIQUE absoluto).

Correcao: o UNIQUE passa a ser PARCIAL, restrito a is_active.

    UNIQUE (game_id, asset_source_id, raw_field, normalized_token)
    WHERE is_active

Assim:
- cada mapping continua com composicao selada e imutavel;
- o token pode ter HISTORICO (varios inactive);
- existe EXATAMENTE UM ativo por token;
- correcao = novo mapping ativo + predecessor desativado.

supersedes_mapping_id vive no mapping NOVO e aponta para o predecessor.
Nunca o contrario: o predecessor ja existe quando o novo nasce, entao a
FK nunca aponta para uma linha futura. A cadeia fica M3 -> M2 -> M1.

-------------------------------------------------------------------------------
CONCORRENCIA — A AUTORIDADE E O INDICE
-------------------------------------------------------------------------------
    T1: UPDATE M1 is_active=FALSE ; INSERT M2 is_active=TRUE
    T2: UPDATE M1 is_active=FALSE ; INSERT M3 is_active=TRUE

Caminho 1 (ambas desativam M1): a segunda bloqueia no row lock de M1 ate
a primeira comitar; ao inserir seu proprio ativo colide com o da
primeira no indice parcial -> unique_violation.

Caminho 2 (T2 nao toca M1): o INSERT ainda colide no mesmo indice.

Caminho 3 (conjuntos DISJUNTOS, ex.: {A,B} vs {C,D}): irrelevante aqui.
As duas disputam a MESMA linha de indice, independentemente do conteudo
da composicao. Era exatamente este o caso que derrubava o modelo de uma
tabela so com UNIQUE por (token, trait_id): conjuntos disjuntos nao
colidiam e produziam MERGE ACIDENTAL {A,B,C,D}.

Em todos os caminhos: exatamente um ativo comita. Nunca
SELECT-entao-INSERT como protecao.

-------------------------------------------------------------------------------
NORMALIZACAO — POR QUE TRIGGER E NAO CHECK
-------------------------------------------------------------------------------
public.normalize_external_catalog_value() depende de
extensions.unaccent(), que e STABLE, nao IMMUTABLE. O Postgres recusa
funcao nao-IMMUTABLE em CHECK. Por isso a canonicidade do token e
garantida por TRIGGER BEFORE INSERT (Query 2174), que normaliza o valor
recebido — e nao por CHECK.

Mesma razao pela qual card_variant_type_external_mapping (Query 2140)
guarda colunas normalized_* preenchidas por quem escreve.

Regras de Negócio:
- raw_field restrito a 'subtype' e 'stamp' (os dois unicos campos da
  assinatura externa que podem carregar Printing).
- type e foil NUNCA sao roteados para Printing: sao acabamento.
- Um mapping pertence a exatamente um Game e uma Fonte.
- Identidade (game_id, asset_source_id, raw_field, normalized_token) e
  IMUTAVEL apos a criacao (Query 2174).
- is_active NOT NULL DEFAULT TRUE — NULL escaparia do indice parcial e
  abriria um segundo ativo pela porta dos fundos.
- Todo mapping precisa de >= 1 trait no COMMIT (Query 2174).
- RLS habilitado; leitura admin-only.

Pré-requisitos:
- Query 000 - Infrastructure.
- Tabelas public.game, public.asset_source.
- Query 2165 - Create Card Printing Trait Table.
- Função public.set_updated_at().

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Criação da tabela (2026-09-12).** Executada e confirmada no banco
        físico na PHASE A da frente CARD-VARIANTS — PRINTING-ROUTING.
        Promovida de database/proposals/ para database/schema/ em 2026-09-13
        (TECHNICAL-CLOSEOUT-PROMOTION-01). O SQL executável permanece
        idêntico ao artefato executado; só o cabeçalho registra o estado
        final. A proposal original é preservada como histórico. |
===============================================================================
*/

BEGIN;

CREATE TABLE public.card_printing_external_mapping (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    game_id UUID NOT NULL,
    asset_source_id UUID NOT NULL,

    -- Campo da assinatura externa de onde o token veio. type e foil sao
    -- deliberadamente inelegiveis: acabamento nao vira Printing.
    raw_field VARCHAR(20) NOT NULL,

    -- Token JA normalizado por public.normalize_external_catalog_value().
    -- A canonicidade e garantida pelo trigger da Query 2174.
    normalized_token TEXT NOT NULL,

    -- Token exatamente como veio da fonte, para auditoria editorial.
    external_token TEXT NOT NULL,

    -- DERIVADA + ESTADO DE SELAMENTO, mesmo contrato de
    -- card_printing_profile.traits_signature (Query 2166):
    --   NULL     -> em montagem (transacao de criacao)
    --   NOT NULL -> selado, composicao imutavel
    traits_signature UUID[],

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    -- Aponta para o PREDECESSOR. Vive no mapping novo, nunca no antigo.
    supersedes_mapping_id UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_card_printing_external_mapping_game
        FOREIGN KEY (game_id)
        REFERENCES public.game (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_card_printing_external_mapping_source
        FOREIGN KEY (asset_source_id)
        REFERENCES public.asset_source (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_card_printing_external_mapping_supersedes
        FOREIGN KEY (supersedes_mapping_id)
        REFERENCES public.card_printing_external_mapping (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    -- Alvo das FKs compostas da N:N (same-Game estrutural, Query 2173).
    CONSTRAINT uq_card_printing_external_mapping_id_game
        UNIQUE (id, game_id),

    CONSTRAINT ck_card_printing_external_mapping_raw_field
        CHECK (raw_field IN ('subtype', 'stamp')),

    CONSTRAINT ck_card_printing_external_mapping_token_not_blank
        CHECK (btrim(normalized_token) <> ''),

    CONSTRAINT ck_card_printing_external_mapping_external_not_blank
        CHECK (btrim(external_token) <> ''),

    -- Um mapping selado nunca pode ter assinatura vazia. A garantia
    -- principal e o trigger deferido da 2174; este CHECK impede o estado
    -- invalido mesmo por escrita direta.
    CONSTRAINT ck_card_printing_external_mapping_signature_not_empty
        CHECK (traits_signature IS NULL OR cardinality(traits_signature) >= 1),

    CONSTRAINT ck_card_printing_external_mapping_signature_shape
        CHECK (traits_signature IS NULL OR array_ndims(traits_signature) = 1),

    -- Um mapping nunca sucede a si mesmo.
    CONSTRAINT ck_card_printing_external_mapping_no_self_supersede
        CHECK (supersedes_mapping_id IS NULL OR supersedes_mapping_id <> id)
);

COMMENT ON TABLE public.card_printing_external_mapping IS
    'Cabecalho do routing de Printing: token externo (raw_field + normalized_token) -> conjunto de Print Traits. Historico permitido; exatamente um ativo por token. A composicao real vive em card_printing_external_mapping_trait.';

COMMENT ON COLUMN public.card_printing_external_mapping.raw_field IS
    'De qual campo da assinatura externa o token veio. Restrito a subtype e stamp — type e foil sao acabamento e NUNCA sao roteados para Printing.';

COMMENT ON COLUMN public.card_printing_external_mapping.normalized_token IS
    'Token normalizado por normalize_external_catalog_value(). Match e por IGUALDADE EXATA — sem prefix, substring, LIKE, fuzzy ou split de hifen. 1st-edition-error e um token DIFERENTE de 1st-edition.';

COMMENT ON COLUMN public.card_printing_external_mapping.traits_signature IS
    'DERIVADO — conjunto de trait_id ORDENADO ASCENDENTE como UUID[]. Igualdade exata, sem hash. Dupla funcao: materializa a composicao para o preload da Edge Function e e o ESTADO DE SELAMENTO (NULL = em montagem; NOT NULL = selado). Escrito uma unica vez pelo trigger deferido da Query 2174.';

COMMENT ON COLUMN public.card_printing_external_mapping.is_active IS
    'Exatamente um ativo por token, imposto por indice unico parcial. Desativar NAO devolve o token ao residual: um token com historico inativo e "Printing conhecido sem routing ativo" e leva a NEEDS_REVIEW (Query 2176).';

COMMENT ON COLUMN public.card_printing_external_mapping.supersedes_mapping_id IS
    'Aponta para o PREDECESSOR. Vive no mapping novo — o predecessor ja existe quando o novo nasce, entao a FK nunca aponta para linha futura. Cadeia: M3 -> M2 -> M1.';

-- ---------------------------------------------------------------------------
-- ACTIVE UNIQUENESS — a autoridade da invariante, inclusive sob concorrencia
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX uq_card_printing_external_mapping_active_token
    ON public.card_printing_external_mapping
       (game_id, asset_source_id, raw_field, normalized_token)
    WHERE is_active;

COMMENT ON INDEX public.uq_card_printing_external_mapping_active_token IS
    'Exatamente um mapping ACTIVE por (Game, Fonte, raw_field, token). Historico inativo ilimitado. E ESTE INDICE, nao uma leitura de aplicacao, que serializa substituicoes concorrentes — inclusive quando as composicoes sao disjuntas.';

-- Lookup do token INDEPENDENTE de is_active: e o que sustenta o caso B
-- (token conhecido so por historico -> NEEDS_REVIEW, nao residual).
CREATE INDEX ix_card_printing_external_mapping_token
    ON public.card_printing_external_mapping
       (game_id, asset_source_id, raw_field, normalized_token);

COMMENT ON INDEX public.ix_card_printing_external_mapping_token IS
    'Suporta a pergunta "este token ja foi conhecido alguma vez?", que distingue o caso B (historico inativo -> NEEDS_REVIEW) do caso C (nunca conhecido -> residual).';

CREATE INDEX ix_card_printing_external_mapping_game_source
    ON public.card_printing_external_mapping (game_id, asset_source_id);

ALTER TABLE public.card_printing_external_mapping ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select
    ON public.card_printing_external_mapping
    FOR SELECT
    USING ((SELECT public.is_admin()));

REVOKE ALL ON public.card_printing_external_mapping FROM anon, authenticated, service_role;
GRANT SELECT ON public.card_printing_external_mapping TO authenticated;
-- GRANT ao service_role vive na Query 2182, junto com as demais decisoes
-- de least privilege do runtime da Edge Function.

DROP TRIGGER IF EXISTS trg_card_printing_external_mapping_set_updated_at
    ON public.card_printing_external_mapping;

CREATE TRIGGER trg_card_printing_external_mapping_set_updated_at
BEFORE UPDATE ON public.card_printing_external_mapping
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   CREATE TABLE, COMMENT x6, CREATE INDEX x3 (1 unico parcial),
--   ALTER TABLE, CREATE POLICY, REVOKE, GRANT, DROP TRIGGER, CREATE TRIGGER.
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Secoes S1 e S2.
-- ============================================================================
