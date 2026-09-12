/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2166 - Create Card Printing Profile Table
Versão......: 1.1
Status......: CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-MODEL-STAGING-01 — GATE-A-01
               + GATE-A-CORRECTION-01 (v1.1)

-------------------------------------------------------------------------------
EXECUÇÃO CONFIRMADA — 2026-09-12
-------------------------------------------------------------------------------
Executado via apply_migration no projeto Supabase qjfutqujxrbzgrtkpgkg.
Ordem de aplicacao: 2165 -> 2166 -> 2167 -> 2168 -> 2169 -> 2170 -> 2171.
Todas as sete aplicadas sem erro.
Estado final validado integralmente pela Query 2823 v1.2:
    12 PASS / 0 FAIL / 0 NOT PROVEN, zero residuo.
O SQL executavel permanece INTOCADO desde a execucao.
-------------------------------------------------------------------------------

v1.1 (GATE-A-CORRECTION-01) sobre a v1.0:
- traits_fingerprint TEXT (md5) foi REMOVIDA e substituida por
  traits_signature UUID[]. Integridade de negocio nao deve depender de
  igualdade PROBABILISTICA (hash) quando igualdade EXATA e simples.
- traits_signature passa a ter DUPLA funcao: alem de impor a unicidade de
  composicao, e o proprio ESTADO DE SELAMENTO do Profile (NULL = em
  montagem; NOT NULL = selado). created_at deixa de ser autoridade.

Descrição resumida:
Cria public.card_printing_profile — o AGREGADO do dominio PRINTING.

Descrição:
Um Print Profile e uma COMBINACAO CANONICA de Print Traits. E ele que a
card_variant referencia (FK escalar, unicidade simples), enquanto a
composicao real vive na N:N da Query 2167.

AUTORIDADE DA COMPOSICAO:
A fonte da verdade e EXCLUSIVAMENTE card_printing_profile_trait. NEM code
NEM name representam a identidade matematica do conjunto. Ninguem deve
derivar composicao fazendo parse do code; filtro por trait e sempre JOIN.

-------------------------------------------------------------------------------
traits_signature — MATERIALIZACAO TECNICA DERIVADA
-------------------------------------------------------------------------------
Tipo: UUID[], sempre ORDENADO ASCENDENTE pelo proprio trait_id.

E o CONJUNTO materializado, nao uma renderizacao dele. Escolha deliberada
sobre a alternativa TEXT: um array de UUID e o proprio dado, comparado
elemento a elemento pelo Postgres. Nao ha serializacao, nao ha separador,
nao ha truncamento, nao ha hash.

Propriedades, por construcao:
- IGUALDADE EXATA. A comparacao de arrays no Postgres e elemento a
  elemento. Dois arrays sao iguais se e somente se tem o mesmo tamanho e
  os mesmos elementos nas mesmas posicoes. Nao existe colisao possivel.
- INDEPENDENTE DA ORDEM DE INSERCAO. O array e sempre montado com
  ORDER BY trait_id, entao {A,B} e {B,A} produzem literalmente o MESMO
  array.
- INDEPENDENTE DO CODE. O code nao participa.
- INDEXAVEL COM UNICIDADE REAL. btree indexa anyarray (array_ops), entao
  UNIQUE (game_id, traits_signature) e uma restricao de verdade do banco,
  nao uma checagem de aplicacao.
- CONJUNTO DIFERENTE -> SIGNATURE DIFERENTE, por construcao: dois
  conjuntos distintos de UUIDs ordenados nao podem produzir o mesmo
  array.

DUPLA FUNCAO — ESTADO DE SELAMENTO:
    traits_signature IS NULL      -> Profile EM MONTAGEM (transacao de criacao)
    traits_signature IS NOT NULL  -> Profile SELADO, composicao imutavel

Isto substitui o uso de created_at = transaction_timestamp() da v1.0.
created_at e metadado temporal; traits_signature e estado semantico
derivado da propria composicao. O selamento passa a ser uma propriedade
do dado, nao uma inferencia sobre o relogio.

Quem escreve: EXCLUSIVAMENTE o trigger deferido da Query 2168, uma unica
vez, no COMMIT da transacao de criacao. A Query 2168 tambem impede que um
UPDATE comum destrave ou falsifique o valor.

Regras de Negócio:
- Cada Profile pertence a exatamente um Game.
- code unico dentro do Game; display_order unico dentro do Game.
- Todo Profile precisa ter >= 1 trait no COMMIT (Query 2168, fail-closed).
- Dois Profiles do mesmo Game nao podem ter o mesmo conjunto de traits.
- Composicao imutavel apos o selamento (Query 2168).
- RLS habilitado; leitura admin-only.

Pré-requisitos:
- Query 000 - Infrastructure.
- Query 2165 - Create Card Printing Trait Table.
- Função public.set_updated_at().
===============================================================================
*/

BEGIN;

CREATE TABLE public.card_printing_profile (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    game_id UUID NOT NULL,

    code VARCHAR(100) NOT NULL,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    display_order INTEGER NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    -- DERIVADA + ESTADO DE SELAMENTO. Escrita apenas pelo trigger deferido
    -- da Query 2168. Sempre ordenada ascendente. Ver header.
    traits_signature UUID[],

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_card_printing_profile_game
        FOREIGN KEY (game_id)
        REFERENCES public.game (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT uq_card_printing_profile_game_code
        UNIQUE (game_id, code),

    CONSTRAINT uq_card_printing_profile_game_display_order
        UNIQUE (game_id, display_order),

    -- Alvo da FK composta de card_printing_profile_trait (same-Game).
    CONSTRAINT uq_card_printing_profile_id_game
        UNIQUE (id, game_id),

    CONSTRAINT ck_card_printing_profile_code_format
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),

    CONSTRAINT ck_card_printing_profile_name_not_blank
        CHECK (btrim(name) <> ''),

    CONSTRAINT ck_card_printing_profile_description_not_blank
        CHECK (description IS NULL OR btrim(description) <> ''),

    CONSTRAINT ck_card_printing_profile_display_order_positive
        CHECK (display_order > 0),

    -- Reforco estrutural do "nao-vazio": um Profile selado nunca pode ter
    -- assinatura vazia. A garantia principal e o trigger deferido da 2168;
    -- este CHECK impede o estado invalido mesmo por escrita direta.
    CONSTRAINT ck_card_printing_profile_signature_not_empty
        CHECK (traits_signature IS NULL OR cardinality(traits_signature) >= 1),

    -- Um array unidimensional, sempre. Protege contra payload malformado.
    CONSTRAINT ck_card_printing_profile_signature_shape
        CHECK (traits_signature IS NULL OR array_ndims(traits_signature) = 1)
);

COMMENT ON TABLE public.card_printing_profile IS
    'Agregado do dominio PRINTING: combinacao canonica de Print Traits. A composicao real vive em card_printing_profile_trait — code e name sao rotulos, nunca autoridade.';

COMMENT ON COLUMN public.card_printing_profile.code IS
    'Rotulo tecnico legivel. NAO representa a identidade matematica da composicao. Nunca fazer parse deste campo.';

COMMENT ON COLUMN public.card_printing_profile.traits_signature IS
    'DERIVADO — conjunto de trait_id ORDENADO ASCENDENTE, materializado como UUID[]. Igualdade exata (sem hash). Tem dupla funcao: impoe a unicidade de composicao via indice unico real, e e o ESTADO DE SELAMENTO do Profile (NULL = em montagem; NOT NULL = selado, composicao imutavel). Escrito uma unica vez pelo trigger deferido da Query 2168. Nunca escrever a mao.';

-- Unicidade de COMPOSICAO — IGUALDADE EXATA, sem hash.
-- NULL nao colide em indice unico, o que permite que o Profile exista
-- durante a transacao de criacao antes do selamento no COMMIT.
CREATE UNIQUE INDEX uq_card_printing_profile_game_signature
    ON public.card_printing_profile (game_id, traits_signature)
    WHERE traits_signature IS NOT NULL;

COMMENT ON INDEX public.uq_card_printing_profile_game_signature IS
    'Impede dois Profiles do mesmo Game com exatamente o mesmo conjunto de traits. Comparacao elemento a elemento de UUID[] — igualdade exata, zero probabilidade de colisao. Independente da ordem de insercao (o array e sempre ordenado) e do code. Esta e a AUTORIDADE FINAL da invariante, inclusive sob concorrencia.';

CREATE INDEX ix_card_printing_profile_game_id
    ON public.card_printing_profile (game_id);

ALTER TABLE public.card_printing_profile ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select
    ON public.card_printing_profile
    FOR SELECT
    USING ((SELECT public.is_admin()));

REVOKE ALL ON public.card_printing_profile FROM anon, authenticated, service_role;
GRANT SELECT ON public.card_printing_profile TO authenticated;

DROP TRIGGER IF EXISTS trg_card_printing_profile_set_updated_at
    ON public.card_printing_profile;

CREATE TRIGGER trg_card_printing_profile_set_updated_at
BEFORE UPDATE ON public.card_printing_profile
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

COMMIT;

-- ============================================================================
-- Como validar:
--   Query 2823 - Validate Card Printing Model, Secoes 1, 2 e 5.
-- ============================================================================
