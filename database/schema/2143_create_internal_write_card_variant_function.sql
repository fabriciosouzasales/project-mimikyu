/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2143 - Create internal.write_card_variant() Function
Versão......: 2.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15 (v1.0) · 2026-09-13 (v2.0)
Reconciliada: 2026-09-13 — CANONICAL-RECONCILIATION-01

Descrição...:
Cria internal.write_card_variant() — camada de escrita canônica e
isolada para public.card_variant, mesmo papel de
internal.write_card() (Query 2030) para public.card. Único caminho
pelo qual card_variant é fisicamente gravada a partir do fluxo de
importação (Incremento 3 do bloco Card Variant, ADR-028). Chamada
só por public.admin_confirm_catalog_variant_import() (Query 2145),
nunca diretamente por um cliente.

----------------------------------------------------------------
v2.0 — ASSINATURA DE SEIS ARGUMENTOS, SEM DEFAULT
----------------------------------------------------------------
Esta versão é o ESTADO TERMINAL do rollout CARD-VARIANTS —
PRINTING-ROUTING: o que as Queries 2143 v1.0 + 2178 + 2187
produziram no banco físico, expresso diretamente.

    v1.0  (p_mode, p_variant_id, p_card_id, p_variant_type_id,
           p_variant_order)
    2178  + p_printing_profile_id UUID DEFAULT NULL   [transitório]
    2187  p_printing_profile_id UUID                  [terminal]

POR QUE O DEFAULT NÃO EXISTE AQUI. O `DEFAULT NULL` da Query 2178
teve UMA razão, e só uma: entre o COMMIT da 2178 e o COMMIT da 2179,
o confirm vivo ainda era a Query 2164, que chamava o writer com CINCO
argumentos posicionais. Sem o DEFAULT, toda confirmação executada
nessa janela falharia com "function does not exist".

Numa instalação limpa essa janela não existe — o confirm nasce já na
forma da Query 2145 v2.0, passando os seis argumentos. Carregar o
DEFAULT para a canônica seria manter uma porta destrancada por um
motivo que não se aplica mais:

    internal.write_card_variant('CREATE', NULL, card, type, 1)

continuaria compilando para sempre, e qualquer writer futuro que
esquecesse o perfil gravaria NULL SILENCIOSAMENTE. NULL aqui não é
placeholder — é um valor semanticamente carregado: "sem perfil de
impressão declarado". Um erro de omissão viraria dado de catálogo
válido e errado.

Sem o DEFAULT, esse erro de omissão é ERRO DE COMPILAÇÃO.

NÃO EXISTE OVERLOAD. Uma única assinatura, de seis argumentos. O
DROP FUNCTION da de cinco (Query 2178) e o DROP + CREATE da Query
2187 foram mecanismos de MIGRAÇÃO — existiam para desfazer um estado
anterior. Numa instalação limpa não há o que desfazer.

Regras de Negócio:
- Schema internal (não public) + REVOKE ALL de PUBLIC/anon/
  authenticated: só alcançável por outra função SECURITY DEFINER do
  mesmo owner, nunca um contrato RPC público — mesmo padrão de
  internal.write_card().
- p_mode = 'CREATE': único modo implementado. Insere
  (card_id, variant_type_id, variant_order, printing_profile_id) —
  is_default NUNCA é incluído no INSERT, nasce sempre FALSE pelo
  default da própria coluna (Query 160), inclusive para a primeira
  variante de uma Card. Tornar uma variante padrão continua sendo
  decisão editorial explícita, fora do escopo de qualquer confirmação
  automática.
- p_mode = 'UPDATE': deliberadamente NÃO implementado — levanta
  exceção explícita. Não existe nenhum cenário em que uma Card
  Variant já existente deva ser sobrescrita pela importação: uma
  variante existe ou não existe para um
  (card_id, variant_type_id, printing_profile_id); não há conteúdo
  interno para divergir e atualizar (diferença estrutural real frente
  a card, que tem name/rarity_id/category_id/collector_total
  mutáveis). O parâmetro p_variant_id já existe na assinatura para
  não exigir uma quebra de contrato se uma necessidade real de
  atualização surgir no futuro.
- p_variant_order é sempre calculado pelo chamador (Query 2145) como
  o próximo inteiro livre para aquele card_id — nunca lido de
  raw_data/normalized_data/TCGdex. Esta função só valida que veio
  preenchido e positivo; não recalcula.
- p_printing_profile_id é OBRIGATÓRIO na assinatura e OPCIONAL no
  valor: NULL significa "sem perfil de impressão declarado" — não é
  Unlimited, não é padrão, não é desconhecido, não é erro. A coluna
  card_variant.printing_profile_id é NULLABLE (Query 2170).
- Se um perfil FOR informado, ele precisa EXISTIR. Esta é a única
  validação de Impressão feita aqui.
- SAME-GAME NÃO É VALIDADO AQUI, de propósito. A autoridade é o
  trigger trg_card_variant_printing_profile_game (Query 2170), que
  retorna cedo quando a coluna é NULL. Duplicar a regra criaria duas
  fontes de verdade para a mesma invariante — e uma delas ficaria
  desatualizada.
- NENHUMA criação automática de Print Profile. Jamais.

Pré-requisitos:
- Query 160 - Create Card Variant Table.
- Query 2166 - Create Card Printing Profile Table.
- Query 2170 - printing_profile_id em card_variant + guard same-Game.
- Query 2171 - dois índices parciais de unicidade de card_variant.

----------------------------------------------------------------
REVISION HISTORY
----------------------------------------------------------------
| 1.0 | **Criação do writer canônico de card_variant (2026-08-15).**
        Cinco argumentos; INSERT sem printing_profile_id. |
| 2.0 | **Assinatura de seis argumentos, sem DEFAULT — estado terminal
        do Printing Routing (2026-09-13).** Reconciliação canônica
        (CANONICAL-RECONCILIATION-01) do estado que hoje resulta de
        2143 v1.0 + 2178 + 2187 no banco físico. Acrescenta
        p_printing_profile_id SEM DEFAULT, a validação de existência
        do perfil e a gravação da coluna no INSERT. Não carrega o
        DEFAULT transitório da 2178 nem os mecanismos de DROP/CREATE
        da 2187, que existiam para desfazer estados anteriores.
        Esta Query NÃO foi reexecutada contra o LIVE: o banco já está
        neste estado desde a PHASE B (ver database/migrations/2178 e
        2187). |
================================================================
*/

CREATE OR REPLACE FUNCTION internal.write_card_variant(
    p_mode TEXT,
    p_variant_id UUID,
    p_card_id UUID,
    p_variant_type_id UUID,
    p_variant_order INTEGER,
    p_printing_profile_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_variant_id UUID;
BEGIN
    IF p_mode NOT IN ('CREATE', 'UPDATE') THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_INVALID_MODE: p_mode deve ser CREATE ou UPDATE (recebido: %).', p_mode;
    END IF;

    IF p_mode = 'UPDATE' THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_UPDATE_NOT_SUPPORTED: nenhum fluxo atual atualiza uma Card Variant existente — ela é tratada como UNCHANGED. Parâmetro reservado para uma necessidade futura ainda não desenhada.';
    END IF;

    -- p_mode = 'CREATE'
    IF p_variant_id IS NOT NULL THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_UNEXPECTED_ID: p_variant_id não deve ser informado em modo CREATE.';
    END IF;
    IF p_card_id IS NULL THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_MISSING_CARD: p_card_id é obrigatório em modo CREATE.';
    END IF;
    IF p_variant_type_id IS NULL THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_MISSING_TYPE: p_variant_type_id é obrigatório em modo CREATE.';
    END IF;
    IF p_variant_order IS NULL OR p_variant_order <= 0 THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_INVALID_ORDER: p_variant_order deve ser um inteiro positivo (recebido: %).', p_variant_order;
    END IF;

    -- Se um perfil foi informado, ele precisa existir. Same-Game NAO e
    -- checado aqui de proposito: o trigger da Query 2170 e a autoridade.
    IF p_printing_profile_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM public.card_printing_profile p WHERE p.id = p_printing_profile_id
       ) THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_PRINTING_PROFILE_NOT_FOUND: Perfil de Impressão % não encontrado.', p_printing_profile_id;
    END IF;

    INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id)
    VALUES (p_card_id, p_variant_type_id, p_variant_order, p_printing_profile_id)
    RETURNING id INTO v_variant_id;

    RETURN v_variant_id;
END;
$$;

REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID) FROM anon;
REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID) FROM authenticated;

-- ================================================================
-- Confirmado executado:
--   v1.0 em 2026-08-15 (via execute_sql/MCP do Supabase, projeto
--   qjfutqujxrbzgrtkpgkg), depois de dry-run em BEGIN...ROLLBACK que
--   exercitou CREATE (variante nova, is_default FALSE, variant_order
--   correto), o bloqueio de UPDATE, e todas as validações de
--   parâmetro obrigatório. role_routine_grants confirma só 'postgres'
--   (owner) com EXECUTE — nenhum grant para anon/authenticated.
--
--   v2.0 NÃO foi reexecutada. O estado terminal que ela descreve já
--   está LIVE desde a PHASE B do rollout CARD-VARIANTS —
--   PRINTING-ROUTING, produzido por:
--     database/migrations/2178_extend_internal_write_card_variant_for_printing.sql
--     database/migrations/2187_remove_write_card_variant_printing_default.sql
--   Esta é a forma que uma INSTALAÇÃO LIMPA deve usar.
--
-- Estado LIVE verificado em 2026-09-13 (read-only, pg_get_functiondef):
--   assinaturas de internal.write_card_variant ......... 1
--   pronargs ........................................... 6
--   pronargdefaults .................................... 0
--   identity args ...................................... p_mode text,
--     p_variant_id uuid, p_card_id uuid, p_variant_type_id uuid,
--     p_variant_order integer, p_printing_profile_id uuid
--   prosecdef .......................................... true
--   proconfig .......................................... search_path=""
--   corpo .............................................. idêntico ao desta Query
-- ================================================================

-- ================================================================
-- Como validar:
-- SELECT p.proname, p.prosecdef, p.proconfig, p.pronargs, p.pronargdefaults
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';
-- Esperado: exatamente 1 linha; prosecdef = true; proconfig contém
-- 'search_path='; pronargs = 6; pronargdefaults = 0.
-- SELECT grantee, privilege_type FROM information_schema.role_routine_grants
-- WHERE routine_name = 'write_card_variant';
-- Esperado: só 'postgres' (owner) — nenhum grant para anon/authenticated.
-- ================================================================
