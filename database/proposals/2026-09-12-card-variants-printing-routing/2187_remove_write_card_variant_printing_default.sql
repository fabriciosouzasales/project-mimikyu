/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2187 - Remove write_card_variant() Printing DEFAULT
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-CORRECTION-04 (§5)
               (decisão D-01, aprovada em PHASE-B-FINAL-AUDIT-01)
Fase........: PHASE B do rollout — aplicar IMEDIATAMENTE APÓS a Query 2179
Sucede......: Query 2178 (mesma função, mesmo corpo, sem o DEFAULT)

Descrição resumida:
Remove o DEFAULT NULL de p_printing_profile_id em
internal.write_card_variant(). Fecha a janela transitória aberta pela 2178.

-------------------------------------------------------------------------------
POR QUE O DEFAULT EXISTIU — E POR QUE ELE NÃO PODE FICAR
-------------------------------------------------------------------------------
A Query 2178 criou a assinatura de 6 argumentos com
`p_printing_profile_id UUID DEFAULT NULL` por UM motivo, e só um:

    entre o COMMIT da 2178 e o COMMIT da 2179, o corpo LIVE da Query 2164
    ainda chama o writer com CINCO argumentos posicionais:

        internal.write_card_variant('CREATE', NULL, v_row.card_id,
                                    v_variant_type_id, v_next_order)

    Sem o DEFAULT, qualquer confirmação executada nessa janela falharia
    com "function does not exist". Com ele, a chamada liga na de 6
    argumentos recebendo NULL — que é literalmente o comportamento de
    hoje, já que nenhuma linha tem perfil de Impressão ainda.

Depois que a 2179 comita, esse caller deixa de existir: a 2179 passa os
SEIS argumentos explicitamente. O DEFAULT vira, a partir daí, apenas uma
porta destrancada.

O risco não é hipotético nem estético. Com o DEFAULT permanente,

    internal.write_card_variant('CREATE', NULL, card, type, 1)

continua compilando para sempre. Qualquer writer futuro que esqueça o
perfil grava NULL SILENCIOSAMENTE — e NULL aqui não é um placeholder, é
um valor semanticamente carregado: "sem perfil de impressão declarado".
Um erro de omissão viraria um dado de catálogo válido e errado, do tipo
que só aparece meses depois como divergência de identidade de variante.

Remover o DEFAULT converte esse erro de omissão em ERRO DE COMPILAÇÃO.
É a diferença entre um bug de catálogo e uma exceção na primeira chamada.

-------------------------------------------------------------------------------
POR QUE UM ARQUIVO PRÓPRIO, E NÃO INLINE NA 2179
-------------------------------------------------------------------------------
Não existe ALTER FUNCTION para remover um default: a única forma é
CREATE OR REPLACE com o corpo INTEIRO. Colocar isso dentro do arquivo do
confirm faria DOIS arquivos donos do mesmo corpo de
internal.write_card_variant() — a forma mais comum de drift silencioso
neste repositório. Um arquivo, um objeto.

Do ponto de vista de risco as duas rotas são equivalentes: depois da 2179
não resta nenhum caller de 5 argumentos, então não há janela entre a 2179
e esta Query. O que esta Query acrescenta é a PROVA de que essa premissa
vale no instante da execução — ver os guards abaixo.

-------------------------------------------------------------------------------
O CORPO É SEMANTICAMENTE IDÊNTICO AO DA 2178
-------------------------------------------------------------------------------
Nenhuma regra muda. Modo UPDATE continua desabilitado; same-Game continua
sendo responsabilidade exclusiva do trigger
trg_card_variant_printing_profile_game (Query 2170); nenhuma criação
automática de Print Profile; REVOKE preservado.

A ÚNICA diferença textual frente à 2178 é a ausência de `DEFAULT NULL`
na assinatura.

-------------------------------------------------------------------------------
ESTADO FINAL DA PHASE B
-------------------------------------------------------------------------------
    EXATAMENTE UMA assinatura de internal.write_card_variant
    6 parâmetros: (TEXT, UUID, UUID, UUID, INTEGER, UUID)
    pronargdefaults = 0
    Nenhum caller de 5 argumentos sobrevive.

Pré-requisitos:
- Query 2178 - write_card_variant() com 6 args e DEFAULT NULL.
- Query 2179 - admin_confirm_catalog_variant_import() chamando com 6 args.
  OBRIGATÓRIA E ANTERIOR — verificada pelo GUARD 2 abaixo.
===============================================================================
*/

BEGIN;

-- =========================================================================
-- GUARD 1 — ESTADO DE PARTIDA.
-- Tem que existir exatamente UMA write_card_variant, com 6 parâmetros.
-- Se houver duas, a 2178 não rodou por completo (o DROP da de 5 falhou)
-- e o CREATE OR REPLACE abaixo deixaria o overload ambíguo de pé.
-- =========================================================================
DO $guard1$
DECLARE
    v_n INTEGER;
    v_nargs INTEGER;
BEGIN
    SELECT count(*) INTO v_n
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

    IF v_n <> 1 THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_OVERLOAD_UNEXPECTED: encontradas % assinaturas de internal.write_card_variant, esperada exatamente 1. A Query 2178 foi aplicada por completo? STOP.', v_n;
    END IF;

    SELECT p.pronargs INTO v_nargs
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

    IF v_nargs <> 6 THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_ARITY_UNEXPECTED: internal.write_card_variant tem % parâmetros, esperados 6. Estado inesperado — reauditar antes de qualquer DDL. STOP.', v_nargs;
    END IF;
END;
$guard1$;

-- =========================================================================
-- GUARD 2 — O ÚNICO CALLER EXECUTÁVEL JÁ É A VERSÃO 2179.
--
-- Esta é a prova que autoriza fechar a porta. Se o confirm ainda for a
-- 2164 (5 argumentos posicionais), remover o DEFAULT quebraria TODA
-- confirmação de importação de variantes no instante do COMMIT.
--
-- Duas evidências independentes, ambas source-level:
--   (a) o confirm cita PRINTING_NOT_RESOLVED — marcador exclusivo da 2179;
--   (b) o confirm cita v_printing_profile_id na chamada do writer.
-- =========================================================================
DO $guard2$
DECLARE
    v_src TEXT;
BEGIN
    SELECT p.prosrc INTO v_src
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'admin_confirm_catalog_variant_import';

    IF v_src IS NULL THEN
        RAISE EXCEPTION 'CONFIRM_NOT_FOUND: public.admin_confirm_catalog_variant_import() não existe. STOP.';
    END IF;

    IF position('PRINTING_NOT_RESOLVED' IN v_src) = 0 THEN
        RAISE EXCEPTION 'CONFIRM_NOT_YET_2179: o confirm vivo não conhece Printing (marcador PRINTING_NOT_RESOLVED ausente). Aplicar a Query 2179 ANTES desta. Remover o DEFAULT agora quebraria toda confirmação de importação. STOP.';
    END IF;

    IF position('v_printing_profile_id' IN v_src) = 0 THEN
        RAISE EXCEPTION 'CONFIRM_NOT_PASSING_PROFILE: o confirm vivo não repassa o perfil ao writer. Estado incoerente com a Query 2179. STOP.';
    END IF;
END;
$guard2$;

-- =========================================================================
-- A ÚNICA MUDANÇA: p_printing_profile_id SEM DEFAULT.
-- Corpo semanticamente idêntico ao da Query 2178.
-- =========================================================================
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

-- =========================================================================
-- GUARD 3 — ESTADO FINAL, na MESMA transação.
-- Se o objetivo não foi atingido, nada comita.
-- =========================================================================
DO $guard3$
DECLARE
    v_n INTEGER;
    v_nargs INTEGER;
    v_ndefaults INTEGER;
BEGIN
    SELECT count(*) INTO v_n
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

    IF v_n <> 1 THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_OVERLOAD: % assinaturas apos a alteracao, esperada exatamente 1. STOP.', v_n;
    END IF;

    SELECT p.pronargs, p.pronargdefaults INTO v_nargs, v_ndefaults
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

    IF v_nargs <> 6 THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_ARITY: % parametros, esperados 6. STOP.', v_nargs;
    END IF;

    IF v_ndefaults <> 0 THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_DEFAULT_SURVIVED: pronargdefaults = %, esperado 0. O DEFAULT sobreviveu — a rota de 5 argumentos continua aberta. STOP.', v_ndefaults;
    END IF;
END;
$guard3$;

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   3 blocos DO (guards) + CREATE OR REPLACE FUNCTION + REVOKE x3.
--   Nenhum DROP: a assinatura de 5 argumentos já foi removida pela 2178.
--
--   Estado final:
--     internal.write_card_variant — 1 assinatura
--     pronargs        = 6
--     pronargdefaults = 0
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Secao S12.
--   S12 NAO passa se o DEFAULT sobreviver.
-- ============================================================================
