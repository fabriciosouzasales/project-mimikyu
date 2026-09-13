/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2187 - Remove write_card_variant() Printing DEFAULT
Versão......: 1.1
Status......: MIGRATION — CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Promovida...: 2026-09-13 — TECHNICAL-CLOSEOUT-PROMOTION-01
Origem......: database/proposals/2026-09-12-card-variants-printing-routing/
              2187_remove_write_card_variant_printing_default.sql
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-CORRECTION-04 (§5)
               (decisão D-01, aprovada em PHASE-B-FINAL-AUDIT-01)
               + 2187-CORRECTION-01 (§1..§7) — defeito 42P13
Fase........: PHASE B do rollout — aplicar IMEDIATAMENTE APÓS a Query 2179
Sucede......: Query 2178 (mesma função, mesmo corpo, sem o DEFAULT)

Descrição resumida:
Remove o DEFAULT NULL de p_printing_profile_id em
internal.write_card_variant(). Fecha a janela transitória aberta pela 2178.

-------------------------------------------------------------------------------
VERSÃO 1.1 — A v1.0 NÃO ERA EXECUTÁVEL (PostgreSQL 42P13)
-------------------------------------------------------------------------------
A v1.0 tentava remover o default com CREATE OR REPLACE FUNCTION, e
justificava isso no cabeçalho com a afirmação:

    "Não existe ALTER FUNCTION para remover um default: a única forma é
     CREATE OR REPLACE com o corpo INTEIRO."

A primeira metade é verdadeira. A SEGUNDA É FALSA, e a Query abortou na
execução LIVE de PHASE-B-EXECUTION-01 com:

    ERROR: 42P13: cannot remove parameter defaults from existing function
    HINT:  Use DROP FUNCTION internal.write_card_variant(
           text,uuid,uuid,uuid,integer,uuid) first.

CREATE OR REPLACE FUNCTION pode ACRESCENTAR defaults a uma assinatura
existente; não pode REMOVÊ-LOS. Nem ALTER FUNCTION, nem CREATE OR
REPLACE: a ÚNICA rota é DROP FUNCTION seguido de CREATE FUNCTION.

O defeito atravessou PHASE-B-FINAL-AUDIT-01, STAGING-CORRECTION-04 (que
criou o arquivo), -05 e -06 porque toda a auditoria foi estática, e este
erro só é diagnosticável pelo parser do PostgreSQL. O rollback em LIVE
foi total: os dois guards de entrada passaram, o CREATE OR REPLACE
abortou, e nada comitou.

O que a v1.1 muda — e o que ela deliberadamente NÃO muda:

  MUDA: a estratégia de DDL passa a ser DROP + CREATE, sem CASCADE,
        dentro da MESMA transação; e, porque o DROP destrói o objeto
        antigo junto com sua identidade, a v1.1 passa a capturar o
        contrato PRE (owner, ACL, atributos, corpo) ANTES do DROP e a
        PROVAR que o estado POST é idêntico exceto pelo default.

  NÃO MUDA: nada do corpo, nada da semântica, nada do contrato de
        privilégio. A única diferença funcional frente à Query 2178
        continua sendo a ausência de `DEFAULT NULL`.

-------------------------------------------------------------------------------
POR QUE O DROP É SEGURO — E POR QUE NÃO LEVA CASCADE
-------------------------------------------------------------------------------
`DROP FUNCTION` sem modificador é RESTRICT: se existir QUALQUER objeto
catalogado dependente, o comando falha e a transação inteira aborta.
Isso é exatamente o comportamento desejado — fail-closed.

CASCADE está PROIBIDO aqui. Um CASCADE silenciosamente destruiria o
dependente junto com a função, e o dependente de uma rotina de escrita
de catálogo é, por construção, algo que ninguém quer perder sem ver.

O único caller real — public.admin_confirm_catalog_variant_import() —
NÃO gera entrada em pg_depend: PL/pgSQL resolve chamadas dentro do corpo
em tempo de execução, não registra dependência de catálogo. Por isso o
DROP não é bloqueado por ele, e por isso mesmo o GUARD 2 existe: a única
forma de saber que o caller sobrevive à mudança é INSPECIONAR O CORPO
dele, o que o GUARD 2 faz, e o GUARD 5 reconfere depois.

O GUARD 3 abaixo enumera qualquer dependência catalogada real e aborta
com a lista legível antes de tentar o DROP, para que a mensagem de erro
seja um diagnóstico e não um código do Postgres.

-------------------------------------------------------------------------------
DROP + CREATE TROCA O OID — A ACL NÃO SOBREVIVE
-------------------------------------------------------------------------------
Privilégios em PostgreSQL são atributos do objeto, indexados pelo OID.
DROP + CREATE produz um objeto NOVO, com OID novo, ACL zerada e owner
igual ao role que executou o CREATE.

Duas consequências, ambas tratadas explicitamente:

  A. OWNER. internal.write_card_variant() é SECURITY DEFINER — ela roda
     com os privilégios do DONO. Se o DROP + CREATE trocasse o owner, os
     privilégios EFETIVOS da função mudariam sem que nenhuma linha de
     GRANT aparecesse no diff. É a classe de mudança de segurança mais
     fácil de não enxergar. O GUARD 4 captura o owner PRE; após o CREATE
     ele é reafirmado por ALTER FUNCTION ... OWNER TO quando divergir.

  B. ACL. Sem ACL explícita, uma função nasce com EXECUTE para PUBLIC —
     o padrão do PostgreSQL. Para uma rotina que grava em card_variant,
     esse padrão é inaceitável. Os três REVOKE abaixo são os mesmos da
     Query 2178 e continuam necessários; a diferença é que agora eles
     não são redundantes, e sim a ÚNICA coisa entre o objeto novo e o
     default permissivo do Postgres.

     O GUARD 6 não confia na intenção: ele compara a ACL POST com a ACL
     PRE capturada e aborta se divergirem. Se alguém tiver concedido
     algo fora deste staging, a divergência aparece como erro, não como
     privilégio silenciosamente perdido.

-------------------------------------------------------------------------------
ATOMICIDADE
-------------------------------------------------------------------------------
DDL em PostgreSQL é transacional. DROP, CREATE, REVOKE e todos os guards
vivem na MESMA transação, sem nenhum COMMIT intermediário. Não existe
instante observável por outra sessão em que internal.write_card_variant()
não exista: a troca é atômica do lado de fora.

Se qualquer guard falhar — antes ou depois do DDL — a transação inteira
volta, e o estado LIVE continua sendo exatamente o da Query 2178.

NOTA OPERACIONAL: se esta Query for aplicada por uma ferramenta que já
abre a própria transação (por exemplo `apply_migration` do MCP do
Supabase), o BEGIN/COMMIT literais deste arquivo devem ser omitidos na
submissão — a ferramenta fornece o envelope transacional. A garantia de
atomicidade é a mesma; o que não pode acontecer, em nenhuma das duas
rotas, é o DDL ser partido em transações separadas.

-------------------------------------------------------------------------------
POR QUE O DEFAULT NÃO PODE FICAR
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
Colocar este DDL dentro do arquivo do confirm faria DOIS arquivos donos
do mesmo corpo de internal.write_card_variant() — a forma mais comum de
drift silencioso neste repositório. Um arquivo, um objeto.

Do ponto de vista de risco as duas rotas são equivalentes: depois da 2179
não resta nenhum caller de 5 argumentos, então não há janela entre a 2179
e esta Query. O que esta Query acrescenta é a PROVA de que essa premissa
vale no instante da execução — ver os guards abaixo.

-------------------------------------------------------------------------------
O CORPO É IDÊNTICO AO DA 2178 — E ISSO É PROVADO, NÃO PROMETIDO
-------------------------------------------------------------------------------
Nenhuma regra muda. Modo UPDATE continua desabilitado; same-Game continua
sendo responsabilidade exclusiva do trigger
trg_card_variant_printing_profile_game (Query 2170); nenhuma criação
automática de Print Profile; REVOKE preservado.

A ÚNICA diferença textual frente à 2178 é a ausência de `DEFAULT NULL`
na assinatura. O GUARD 5 prova isso pelo próprio catálogo: captura
md5(prosrc) ANTES do DROP e exige igualdade DEPOIS do CREATE. Se o corpo
tiver sido alterado — por esta Query ou por qualquer drift LIVE não
documentado — a transação aborta. Refatorar aqui é, literalmente,
impossível sem que a migration recuse.

-------------------------------------------------------------------------------
ESTADO FINAL DA PHASE B
-------------------------------------------------------------------------------
    EXATAMENTE UMA assinatura de internal.write_card_variant
    6 parâmetros: (TEXT, UUID, UUID, UUID, INTEGER, UUID)
    pronargdefaults = 0
    Nenhum caller de 5 argumentos sobrevive.
    Owner, ACL, atributos e corpo idênticos aos da Query 2178.

Pré-requisitos:
- Query 2178 - write_card_variant() com 6 args e DEFAULT NULL.
- Query 2179 - admin_confirm_catalog_variant_import() chamando com 6 args.
  OBRIGATÓRIA E ANTERIOR — verificada pelo GUARD 2 abaixo.

-------------------------------------------------------------------------------
ESTADO FINAL (registro pós-rollout)
-------------------------------------------------------------------------------
Esta é a forma LIVE de internal.write_card_variant(): 6 parâmetros, sem
DEFAULT. O arquivo é MIGRATION porque sucede a Query 2178 (também
MIGRATION) alterando uma função já existente; a forma canônica de
internal.write_card_variant() continua sendo a Query 2143, que será
consolidada na rodada CANONICAL-RECONCILIATION-01 — é lá que o estado
final (6 args, sem DEFAULT) passa a ser a instalação limpa.

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Versão inicial (2026-09-12).** Usava CREATE OR REPLACE FUNCTION.
        NÃO era executável: PostgreSQL 42P13 — não se remove default de
        função existente por CREATE OR REPLACE. Abortou em LIVE com
        rollback total, sem efeito. |
| 1.1 | **DROP + CREATE com captura de estado PRE e sete guards
        (2026-09-12).** Fecha o defeito 42P13 e prova que owner, ACL,
        atributos e corpo sobrevivem idênticos. Esta é a versão executada e
        confirmada no banco físico na PHASE B da frente CARD-VARIANTS —
        PRINTING-ROUTING. Promovida de database/proposals/ para
        database/migrations/ em 2026-09-13
        (TECHNICAL-CLOSEOUT-PROMOTION-01). O SQL executável permanece
        idêntico ao artefato executado; só o cabeçalho registra o estado
        final. A proposal original é preservada como histórico. |
===============================================================================
*/

BEGIN;

-- =========================================================================
-- ESTADO PRE — capturado UMA vez, em tabela temporária ON COMMIT DROP.
--
-- Uma tabela temporária, e não variáveis de um bloco DO, porque o estado
-- precisa SOBREVIVER ao DROP e atravessar blocos DO distintos. Variáveis
-- de um DO morrem no END daquele bloco; o que se quer comparar aqui nasce
-- antes do DROP e é verificado depois do CREATE.
--
-- ON COMMIT DROP garante zero resíduo: a tabela desaparece no COMMIT,
-- tenha a migration tido sucesso ou não.
-- =========================================================================
CREATE TEMP TABLE _wcv_pre_state ON COMMIT DROP AS
SELECT
    p.oid                                              AS pre_oid,
    pg_catalog.pg_get_userbyid(p.proowner)             AS pre_owner,
    p.proacl                                           AS pre_acl,
    p.pronargs                                         AS pre_pronargs,
    p.pronargdefaults                                  AS pre_pronargdefaults,
    p.prorettype                                       AS pre_prorettype,
    p.proargtypes::text                                AS pre_proargtypes,
    p.prolang                                          AS pre_prolang,
    p.provolatile                                      AS pre_provolatile,
    p.proisstrict                                      AS pre_proisstrict,
    p.prosecdef                                        AS pre_prosecdef,
    p.proleakproof                                     AS pre_proleakproof,
    p.proretset                                        AS pre_proretset,
    p.proparallel                                      AS pre_proparallel,
    p.proconfig::text                                  AS pre_proconfig,
    pg_catalog.md5(p.prosrc)                           AS pre_src_md5,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS pre_identity_args
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

-- =========================================================================
-- GUARD 1 — ESTADO DE PARTIDA.
-- Tem que existir exatamente UMA write_card_variant, com 6 parâmetros e
-- com o DEFAULT ainda presente. Se houver duas, a 2178 não rodou por
-- completo (o DROP da de 5 falhou). Se pronargdefaults já for 0, esta
-- Query já rodou — e o DROP + CREATE seria uma troca de OID gratuita,
-- destruindo a ACL viva por nada.
-- =========================================================================
DO $guard1$
DECLARE
    v_n INTEGER;
    v_nargs INTEGER;
    v_ndefaults INTEGER;
BEGIN
    SELECT count(*) INTO v_n FROM _wcv_pre_state;

    IF v_n <> 1 THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_OVERLOAD_UNEXPECTED: encontradas % assinaturas de internal.write_card_variant, esperada exatamente 1. A Query 2178 foi aplicada por completo? STOP.', v_n;
    END IF;

    SELECT pre_pronargs, pre_pronargdefaults
      INTO v_nargs, v_ndefaults
      FROM _wcv_pre_state;

    IF v_nargs <> 6 THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_ARITY_UNEXPECTED: internal.write_card_variant tem % parâmetros, esperados 6. Estado inesperado — reauditar antes de qualquer DDL. STOP.', v_nargs;
    END IF;

    IF v_ndefaults <> 1 THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_DEFAULT_ALREADY_ABSENT: pronargdefaults = %, esperado 1. O estado de partida desta Query é a assinatura da 2178 COM o DEFAULT. Se já vale 0, esta Query já foi aplicada e reexecutá-la trocaria o OID — e portanto a ACL viva — sem nenhum ganho. STOP.', v_ndefaults;
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
--
-- PL/pgSQL não registra o caller em pg_depend, então esta inspeção de
-- corpo é a ÚNICA forma de saber. O GUARD 7 a repete após o DDL.
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
-- GUARD 3 — DEPENDÊNCIAS CATALOGADAS.
--
-- DROP FUNCTION sem modificador é RESTRICT e já falharia sozinho. Este
-- guard existe para que a falha seja um DIAGNÓSTICO — com a lista dos
-- objetos dependentes em texto legível — em vez de um 2BP01 seco.
--
-- Dependências ignoradas de propósito: a do próprio schema (deptype 'n'
-- vindo do namespace) e a de extensão (deptype 'e'), que não bloqueiam.
--
-- CASCADE está proibido: destruir o dependente junto seria trocar um
-- erro visível por um dano invisível.
-- =========================================================================
DO $guard3$
DECLARE
    v_oid OID;
    v_deps TEXT;
    v_count INTEGER;
BEGIN
    SELECT pre_oid INTO v_oid FROM _wcv_pre_state;

    SELECT count(*), string_agg(d.descr, ' | ' ORDER BY d.descr)
      INTO v_count, v_deps
      FROM (
        SELECT DISTINCT pg_catalog.pg_describe_object(dep.classid, dep.objid, dep.objsubid) AS descr
          FROM pg_catalog.pg_depend dep
         WHERE dep.refclassid = 'pg_catalog.pg_proc'::regclass
           AND dep.refobjid   = v_oid
           AND dep.deptype IN ('n', 'a')
           AND dep.classid <> 'pg_catalog.pg_namespace'::regclass
      ) d;

    IF v_count > 0 THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_HAS_DEPENDENTS: % objeto(s) catalogado(s) dependem de internal.write_card_variant e impediriam o DROP RESTRICT: %. CASCADE é PROIBIDO nesta Query — destruir o dependente junto trocaria um erro visível por um dano invisível. Reauditar cada dependente antes de prosseguir. STOP.', v_count, v_deps;
    END IF;
END;
$guard3$;

-- =========================================================================
-- O DDL. DROP RESTRICT (sem CASCADE) + CREATE, na MESMA transação.
--
-- `DROP FUNCTION` sem CASCADE é RESTRICT por padrão. Está escrito
-- explicitamente abaixo para que a intenção fique no arquivo e não na
-- memória de quem lê.
--
-- Não há `IF EXISTS`: a ausência da função neste ponto seria um estado
-- que o GUARD 1 já teria recusado, e silenciá-la aqui só esconderia o
-- problema do CREATE seguinte.
-- =========================================================================
DROP FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID) RESTRICT;

-- A ÚNICA mudança frente à Query 2178: p_printing_profile_id SEM DEFAULT.
-- Corpo, atributos e configuração idênticos — provado pelo GUARD 5.
CREATE FUNCTION internal.write_card_variant(
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

-- =========================================================================
-- GUARD 4 — OWNER REAFIRMADO.
--
-- O CREATE acima produziu um objeto cujo dono é o role que executou esta
-- migration. Se esse role não for o dono anterior, os privilégios
-- EFETIVOS da função mudaram — ela é SECURITY DEFINER, roda com os
-- direitos do DONO — sem que nenhuma linha de GRANT apareça no diff.
--
-- Este bloco restaura o dono ORIGINAL, capturado antes do DROP. Se o
-- role executor não puder fazê-lo, a transação aborta: melhor não
-- aplicar do que aplicar com privilégio efetivo diferente.
-- =========================================================================
DO $guard4$
DECLARE
    v_pre_owner TEXT;
    v_post_owner TEXT;
BEGIN
    SELECT pre_owner INTO v_pre_owner FROM _wcv_pre_state;

    SELECT pg_catalog.pg_get_userbyid(p.proowner) INTO v_post_owner
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

    IF v_post_owner IS DISTINCT FROM v_pre_owner THEN
        EXECUTE format(
            'ALTER FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID) OWNER TO %I',
            v_pre_owner);

        SELECT pg_catalog.pg_get_userbyid(p.proowner) INTO v_post_owner
          FROM pg_catalog.pg_proc p
          JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

        IF v_post_owner IS DISTINCT FROM v_pre_owner THEN
            RAISE EXCEPTION 'WRITE_CARD_VARIANT_OWNER_NOT_RESTORED: dono esperado %, obtido % após ALTER FUNCTION. A função é SECURITY DEFINER — dono diferente significa privilégio efetivo diferente. STOP.', v_pre_owner, v_post_owner;
        END IF;
    END IF;
END;
$guard4$;

-- =========================================================================
-- ACL. Os mesmos três REVOKE da Query 2178 — mas aqui eles NÃO são
-- redundantes: o objeto é novo, e sem eles vale o default do PostgreSQL,
-- que concede EXECUTE a PUBLIC.
-- =========================================================================
REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID) FROM anon;
REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID) FROM authenticated;

-- =========================================================================
-- GUARD 5 — ESTADO FINAL: SÓ O DEFAULT PODE TER MUDADO.
--
-- Compara, item a item, os atributos capturados antes do DROP com os do
-- objeto recriado. Qualquer divergência ALÉM de pronargdefaults aborta.
--
-- md5(prosrc) na lista é deliberado: torna impossível "aproveitar a
-- rodada para refatorar". Se o corpo diferir em um único caractere, a
-- migration recusa.
-- =========================================================================
DO $guard5$
DECLARE
    r RECORD;
    v_n INTEGER;
BEGIN
    SELECT count(*) INTO v_n
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

    IF v_n <> 1 THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_OVERLOAD: % assinaturas apos a alteracao, esperada exatamente 1. STOP.', v_n;
    END IF;

    SELECT pre.*,
           p.pronargs          AS post_pronargs,
           p.pronargdefaults   AS post_pronargdefaults,
           p.prorettype        AS post_prorettype,
           p.proargtypes::text AS post_proargtypes,
           p.prolang           AS post_prolang,
           p.provolatile       AS post_provolatile,
           p.proisstrict       AS post_proisstrict,
           p.prosecdef         AS post_prosecdef,
           p.proleakproof      AS post_proleakproof,
           p.proretset         AS post_proretset,
           p.proparallel       AS post_proparallel,
           p.proconfig::text   AS post_proconfig,
           pg_catalog.md5(p.prosrc) AS post_src_md5,
           pg_catalog.pg_get_function_identity_arguments(p.oid) AS post_identity_args,
           pg_catalog.format_type(p.proargtypes[5], NULL) AS post_sixth_type
      INTO r
      FROM _wcv_pre_state pre
      CROSS JOIN pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

    -- O objetivo da Query.
    IF r.post_pronargdefaults <> 0 THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_DEFAULT_SURVIVED: pronargdefaults = %, esperado 0. O DEFAULT sobreviveu — a rota de 5 argumentos continua aberta. STOP.', r.post_pronargdefaults;
    END IF;

    -- Aridade e tipo do sexto argumento.
    IF r.post_pronargs <> 6 THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_ARITY: % parametros, esperados 6. STOP.', r.post_pronargs;
    END IF;

    IF r.post_sixth_type <> 'uuid' THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_SIXTH_TYPE: sexto argumento e %, esperado uuid. STOP.', r.post_sixth_type;
    END IF;

    -- Tudo o mais tem que ser IDENTICO ao estado PRE.
    IF r.post_identity_args IS DISTINCT FROM r.pre_identity_args THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_SIGNATURE_DRIFT: assinatura PRE [%] != POST [%]. STOP.', r.pre_identity_args, r.post_identity_args;
    END IF;

    IF r.post_prorettype IS DISTINCT FROM r.pre_prorettype THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_RETTYPE_DRIFT: tipo de retorno mudou. STOP.';
    END IF;

    IF r.post_proargtypes IS DISTINCT FROM r.pre_proargtypes THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_ARGTYPES_DRIFT: tipos dos argumentos mudaram. STOP.';
    END IF;

    IF r.post_prolang IS DISTINCT FROM r.pre_prolang THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_LANG_DRIFT: linguagem mudou. STOP.';
    END IF;

    IF r.post_provolatile IS DISTINCT FROM r.pre_provolatile THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_VOLATILITY_DRIFT: volatility PRE [%] != POST [%]. STOP.', r.pre_provolatile, r.post_provolatile;
    END IF;

    IF r.post_proisstrict IS DISTINCT FROM r.pre_proisstrict THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_STRICT_DRIFT: STRICT mudou. STOP.';
    END IF;

    IF r.post_prosecdef IS DISTINCT FROM r.pre_prosecdef THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_SECDEF_DRIFT: SECURITY DEFINER/INVOKER mudou. STOP.';
    END IF;

    IF r.post_proleakproof IS DISTINCT FROM r.pre_proleakproof THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_LEAKPROOF_DRIFT: LEAKPROOF mudou. STOP.';
    END IF;

    IF r.post_proretset IS DISTINCT FROM r.pre_proretset THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_RETSET_DRIFT: RETURNS SETOF mudou. STOP.';
    END IF;

    IF r.post_proparallel IS DISTINCT FROM r.pre_proparallel THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_PARALLEL_DRIFT: modo de paralelismo mudou. STOP.';
    END IF;

    IF r.post_proconfig IS DISTINCT FROM r.pre_proconfig THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_CONFIG_DRIFT: proconfig PRE [%] != POST [%]. search_path = '''' precisa sobreviver. STOP.', COALESCE(r.pre_proconfig, '<null>'), COALESCE(r.post_proconfig, '<null>');
    END IF;

    IF r.post_src_md5 IS DISTINCT FROM r.pre_src_md5 THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_POSTCHECK_BODY_DRIFT: o corpo da funcao mudou (md5 PRE % != POST %). Esta Query so pode remover o DEFAULT — nao refatorar. STOP.', r.pre_src_md5, r.post_src_md5;
    END IF;
END;
$guard5$;

-- =========================================================================
-- GUARD 6 — ACL IDÊNTICA À DE ANTES DO DROP.
--
-- Não basta os REVOKE terem rodado: é preciso provar que o conjunto de
-- privilégios do objeto NOVO é o mesmo do objeto DESTRUÍDO. Se alguém
-- tiver concedido algo fora deste staging, a divergência tem que aparecer
-- como ERRO — não como privilégio silenciosamente perdido.
--
-- A comparação normaliza a ordem dos aclitem: ACL é um conjunto, e a
-- ordem em que o Postgres a materializa não é contrato.
-- =========================================================================
DO $guard6$
DECLARE
    v_pre_acl TEXT;
    v_post_acl TEXT;
    v_public_exec BOOLEAN;
BEGIN
    SELECT COALESCE(
             (SELECT string_agg(a::text, ',' ORDER BY a::text)
                FROM unnest(pre.pre_acl) AS a),
             '<default>')
      INTO v_pre_acl
      FROM _wcv_pre_state pre;

    SELECT COALESCE(
             (SELECT string_agg(a::text, ',' ORDER BY a::text)
                FROM unnest(p.proacl) AS a),
             '<default>')
      INTO v_post_acl
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

    -- Invariante absoluta, independente da comparação: PUBLIC nunca pode
    -- executar esta função. Um objeto recriado sem ACL explícita herda
    -- EXECUTE para PUBLIC — este é exatamente o acidente que o DROP+CREATE
    -- torna possível.
    SELECT pg_catalog.has_function_privilege('public', p.oid, 'EXECUTE')
      INTO v_public_exec
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';

    IF v_public_exec THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_PUBLIC_EXECUTE: PUBLIC tem EXECUTE sobre a funcao recriada. O DROP zerou a ACL e os REVOKE nao foram suficientes. STOP.';
    END IF;

    IF v_post_acl IS DISTINCT FROM v_pre_acl THEN
        RAISE EXCEPTION 'WRITE_CARD_VARIANT_ACL_DRIFT: a ACL do objeto recriado difere da capturada antes do DROP. PRE [%] POST [%]. Privilegios nao sobrevivem ao DROP: se havia GRANT fora deste staging, ele precisa ser reafirmado explicitamente aqui. STOP.', v_pre_acl, v_post_acl;
    END IF;
END;
$guard6$;

-- =========================================================================
-- GUARD 7 — PROVA COMPORTAMENTAL DE RESOLUÇÃO.
--
-- Os guards anteriores leem o catálogo. Este exercita o RESOLVEDOR de
-- funções do próprio PostgreSQL, que é quem de fato decide se uma
-- chamada compila.
--
-- Nenhuma linha é escrita: p_mode = '__PROBE_2187__' aborta no primeiro
-- IF do corpo, muito antes do INSERT. Os dois probes rodam em
-- subtransações (bloco BEGIN/EXCEPTION) que revertem sozinhas.
-- =========================================================================
DO $guard7$
DECLARE
    v_src TEXT;
BEGIN
    -- (a) CHAMADA DE 5 ARGUMENTOS — TEM que ser irresolvível.
    --     É o objetivo inteiro desta Query.
    --
    --     Os casts são obrigatórios, não decorativos: um parâmetro
    --     `unknown` que falhasse na resolução de TIPO levantaria
    --     undefined_function também — e seria contabilizado aqui como
    --     sucesso. Com os tipos fixos, o único motivo possível para
    --     undefined_function é o que se quer provar: a aridade.
    BEGIN
        EXECUTE 'SELECT internal.write_card_variant($1::TEXT, $2::UUID, $3::UUID, $4::UUID, $5::INTEGER)'
          USING '__PROBE_2187__'::TEXT, NULL::UUID, NULL::UUID, NULL::UUID, 1::INTEGER;

        RAISE EXCEPTION 'WRITE_CARD_VARIANT_5ARG_STILL_RESOLVABLE: a chamada de 5 argumentos ainda compila. O DEFAULT nao foi removido. STOP.';
    EXCEPTION
        WHEN undefined_function THEN
            NULL;  -- esperado: a rota de 5 argumentos morreu.
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%WRITE_CARD_VARIANT_5ARG_STILL_RESOLVABLE%' THEN
                RAISE;
            END IF;
            RAISE EXCEPTION 'WRITE_CARD_VARIANT_5ARG_STILL_RESOLVABLE: a chamada de 5 argumentos resolveu e executou o corpo (erro obtido: %). O DEFAULT nao foi removido. STOP.', SQLERRM;
    END;

    -- (b) CHAMADA DE 6 ARGUMENTOS — TEM que ser resolvível.
    --     Sem isto, teriamos provado apenas que quebramos a funcao.
    BEGIN
        EXECUTE 'SELECT internal.write_card_variant($1::TEXT, $2::UUID, $3::UUID, $4::UUID, $5::INTEGER, $6::UUID)'
          USING '__PROBE_2187__'::TEXT, NULL::UUID, NULL::UUID, NULL::UUID, 1::INTEGER, NULL::UUID;

        RAISE EXCEPTION 'WRITE_CARD_VARIANT_PROBE_DID_NOT_ABORT: o probe de 6 argumentos deveria ter abortado com INVALID_MODE. Corpo inesperado. STOP.';
    EXCEPTION
        WHEN undefined_function THEN
            RAISE EXCEPTION 'WRITE_CARD_VARIANT_6ARG_NOT_RESOLVABLE: a chamada de 6 argumentos NAO compila. A funcao foi recriada com assinatura errada. STOP.';
        WHEN OTHERS THEN
            IF SQLERRM NOT LIKE '%INTERNAL_WRITE_CARD_VARIANT_INVALID_MODE%' THEN
                RAISE EXCEPTION 'WRITE_CARD_VARIANT_6ARG_UNEXPECTED_ERROR: o probe de 6 argumentos falhou por motivo inesperado: %. STOP.', SQLERRM;
            END IF;
            -- esperado: resolveu, entrou no corpo, recusou o modo.
    END;

    -- (c) O CALLER continua coerente DEPOIS do DDL.
    SELECT p.prosrc INTO v_src
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'admin_confirm_catalog_variant_import';

    IF v_src IS NULL
       OR position('PRINTING_NOT_RESOLVED' IN v_src) = 0
       OR position('v_printing_profile_id' IN v_src) = 0 THEN
        RAISE EXCEPTION 'CONFIRM_BROKEN_AFTER_DDL: admin_confirm_catalog_variant_import nao esta mais coerente com a Query 2179 apos o DROP+CREATE. STOP.';
    END IF;
END;
$guard7$;

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   CREATE TEMP TABLE (ON COMMIT DROP) + 7 blocos DO (guards)
--   + DROP FUNCTION ... RESTRICT + CREATE FUNCTION + REVOKE x3.
--
--   Nenhum CASCADE. Nenhum COMMIT intermediario. Nenhuma linha de dado
--   tocada. Zero residuo: a temp table morre no COMMIT.
--
--   Estado final:
--     internal.write_card_variant — 1 assinatura
--     pronargs        = 6
--     pronargdefaults = 0
--     owner, ACL, atributos e corpo IDENTICOS aos da Query 2178
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Secao S12.
--   S12 NAO passa se o DEFAULT sobreviver.
-- ============================================================================
