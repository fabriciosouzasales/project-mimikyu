-- ============================================================================
-- Query 2207 — card_edition_context_external_mapping (+ N:N de traits + guards)
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 4.0
--
-- v4.0 (MAPPING-LIFECYCLE-CORRECTION-02) — LIFECYCLE DO CABEÇALHO FECHADO
--   A v3.0 partializou os índices, mas parou aí. A auditoria da Query 2174
--   (LIVE) mostrou que o contrato do mapping tem CINCO guards, não três.
--   Faltavam os dois que protegem o CABEÇALHO:
--     GUARD A — normalização canônica do token na entrada. Sem ele, um
--               token não-canônico é persistido, NUNCA casa com o residual
--               (que a 2176 já normaliza) e cai no ramo "desconhecido":
--               fail-OPEN silencioso para o eixo de Finish.
--     GUARD B — identidade imutável + `is_active` só TRUE→FALSE. Sem ele,
--               um mapping aposentado podia ser RESSUSCITADO sempre que não
--               houvesse outro ativo — o índice parcial não cobre esse caso,
--               e é justamente o mais perigoso.
--   Agora são cinco, em paridade 1:1 com a 2174.
--
-- v3.0 (MAPPING-LIFECYCLE-CORRECTION-01) — HISTÓRICO + UM ÚNICO ATIVO
--   BLOCKER: os dois UNIQUE eram ABSOLUTOS. Com a composição imutável da
--   v2.0, um mapping errado ficava impossível de corrigir — não dava para
--   alterar nem para substituir. Mesmo beco que a Printing resolveu na
--   Query 2172 (linhas 36-50). Os índices passam a ser PARCIAIS em
--   `is_active`, + índice de lookup independente de is_active.
--   `supersedes_mapping_id` avaliado e DELIBERADAMENTE não adicionado.
--   Ver bloco "LIFECYCLE" antes dos índices.
--
-- v2.0 (BATCH1-RUNTIME-CORRECTION-02) — FIM DA COLUNA DORMENTE
--   A v1.1 deixou traits_signature sem selo e registrou isso como "observação
--   de escopo". Auditoria independente mostrou que não era observação: era
--   BLOCKER. Ver bloco "POR QUE traits_signature NÃO PODE FICAR DORMENTE",
--   antes dos guards, com as linhas exatas de 2211 e do patch da Edge.
--   Acrescentados três guards (selo deferido no cabeçalho · imutabilidade da
--   N:N · selo não falsificável), invariantes das Queries 2172/2173/2174.
--
-- v1.1 (BATCH1-RUNTIME-CORRECTION-01) — CORREÇÃO DE RUNTIME PREVENTIVA
--   Este arquivo carregava a MESMA subquery-em-CHECK que abortou a 2204 v1.0
--   no LIVE (SQLSTATE 0A000). A 2207 ainda não havia sido executada, então o
--   defeito foi corrigido ANTES de causar um segundo abort na retomada do
--   Batch 1. Substituído por dois CHECKs escalares, paridade literal com as
--   linhas 187 e 190 da Query 2172 (card_printing_external_mapping), LIVE.
--
-- CONTRATO DE ROUTING — FAIL CLOSED
--   Um token externo só alimenta Edition Context se existir mapping CANÔNICO
--   EXPLÍCITO para este eixo. Proibido, sem exceção:
--     · inferir por substring / regex / heurística;
--     · derivar `code` automaticamente do vocabulário TCGdex;
--     · consumir token indeterminado;
--     · "adivinhar" família por padrão de nome.
--   Token desconhecido NÃO vira contexto: permanece no residual de Finish e a
--   linha termina NEEDS_REVIEW. É o mesmo princípio de 2172.
--
-- RAW_FIELDS AUTORIZADOS — decisão explícita, medida
--   'stamp'   : autorizado. 1.145 ocorrências em A; principal alimentador.
--   'subtype' : autorizado. Necessário porque Printing já consome subtype e o
--               que sobra pode ser contexto (ex.: bordas promocionais).
--   'foil'    : **PROIBIDO** (BLOCKER 6 / CORRECTION-01). Ver nota abaixo.
--   'type'    : PROIBIDO. É o eixo de acabamento por definição.
--   'size'    : PROIBIDO. É escopo (2198), nunca identidade.
--
--   POR QUE `foil` FICOU FORA — decisao da CORRECTION-01
--   O campo e semanticamente misto na fonte: carrega padrao fisico (COSMOS,
--   CRACKED-ICE, ENERGY) E nome de programa (LEAGUE, PLAYER-REWARD,
--   PROFESSOR-PROGRAM). O legado JA materializou os tres ultimos como contexto
--   (STANDARDS_LEAGUE, PLAYER_REWARD_REVERSE, COSMOS_PROFESSOR_REVERSE), mas as
--   57 rows modernas equivalentes seguem INDETERMINADAS.
--   Autorizar raw_field='foil' aqui legitimaria no schema uma semantica ainda
--   nao decidida e abriria porta para classificacao futura acidental.
--   Decisao: dominio FECHADO em ('stamp','subtype'). O legado e tratado por
--   migracao via lineage (nao precisa de mapping externo). Se B3 for resolvido,
--   uma migration propria amplia o CHECK conscientemente.
-- ============================================================================

-- Fronteira transacional EXPLÍCITA (TRANSACTION-BOUNDARY-CORRECTION-01).
-- Paridade com as Queries 2172/2173. Este arquivo cria DUAS tabelas ligadas
-- por FK: aplicar só a primeira deixaria o mapping sem vínculo de traits.
-- Ver nota completa na Query 2203.
BEGIN;

CREATE TABLE public.card_edition_context_external_mapping (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id          UUID NOT NULL REFERENCES public.game (id)
                          ON UPDATE RESTRICT ON DELETE RESTRICT,
    asset_source_id  UUID NOT NULL REFERENCES public.asset_source (id)
                          ON UPDATE RESTRICT ON DELETE RESTRICT,
    -- Escopo por Set da fonte. NULL = GLOBAL. Mesmo contrato de 2140 v2.0:
    -- o mesmo token pode ter alvo distinto por era/Set (set-logo é o caso real).
    external_set_id  TEXT,
    raw_field        TEXT NOT NULL,
    normalized_token TEXT NOT NULL,
    is_active        BOOLEAN NOT NULL DEFAULT TRUE,
    traits_signature UUID[],
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- BLOCKER 6 (CORRECTION-01): dominio FECHADO em stamp/subtype.
    -- `foil` FORA. Legitimar foil no DDL permitiria classificacao futura
    -- acidental de uma semantica que segue INDETERMINADA (as 57 rows modernas
    -- continuam HOLD). O legado que ja carrega LEAGUE/PLAYER-REWARD/
    -- PROFESSOR-PROGRAM recebe Edition Context por MIGRACAO VIA LINEAGE, que
    -- nao passa por esta tabela. Ampliar o dominio exige migration propria e
    -- consciente, depois de B3 resolvido.
    CONSTRAINT ck_cecem_raw_field
        CHECK (raw_field IN ('stamp','subtype')),
    CONSTRAINT ck_cecem_token_not_blank
        CHECK (btrim(normalized_token) <> ''),
    CONSTRAINT ck_cecem_external_set_not_blank
        CHECK (external_set_id IS NULL OR btrim(external_set_id) <> ''),
    -- Mesma classe de defeito da 2204 v1.0, corrigida em
    -- BATCH1-RUNTIME-CORRECTION-01. Paridade literal com as linhas 187 e 190
    -- da Query 2172 (card_printing_external_mapping), LIVE.
    CONSTRAINT ck_cecem_signature_not_empty
        CHECK (traits_signature IS NULL OR cardinality(traits_signature) >= 1),
    CONSTRAINT ck_cecem_signature_shape
        CHECK (traits_signature IS NULL OR array_ndims(traits_signature) = 1),
    CONSTRAINT uq_cecem_id_game UNIQUE (id, game_id)
);

-- ----------------------------------------------------------------------------
-- LIFECYCLE: HISTÓRICO + EXATAMENTE UM ATIVO  (v3.0)
--
-- BLOCKER CORRIGIDO (MAPPING-LIFECYCLE-CORRECTION-01). A v2.0 tinha os dois
-- UNIQUE ABSOLUTOS — sem `AND is_active`. Combinado com a composição imutável
-- do GUARD B, isso tornava um mapping errado IMPOSSÍVEL de corrigir:
--
--     M1: token X -> trait A        (selado)
--     · alterar a composição de M1  -> proibido (COMPOSITION_SEALED)
--     · desativar M1 e criar M2     -> proibido (colide no UNIQUE absoluto)
--     => beco sem saída: nem corrige, nem substitui.
--
-- É EXATAMENTE o mesmo beco que a Printing já encontrou e resolveu. Query
-- 2172 (LIVE), linhas 36-50, literal:
--
--     "CONTRACT-CORRECTION-02 identificou uma incompatibilidade real no
--      desenho anterior: UNIQUE ABSOLUTO por token + composicao IMUTAVEL
--      tornavam um mapping errado impossivel de corrigir (...)
--      Correcao: o UNIQUE passa a ser PARCIAL, restrito a is_active."
--
-- Adotado aqui o MESMO contrato, adaptado ao eixo `external_set_id`:
--   · composição de cada mapping continua selada e imutável;
--   · o token pode ter HISTÓRICO ilimitado de inativos;
--   · existe no MÁXIMO UM ativo GLOBAL e UM ativo SCOPED por token;
--   · corrigir = desativar o predecessor + criar mapping ativo novo,
--     na MESMA transação.
--
-- FLUXO DE CORREÇÃO (determinístico, sem reescrever histórico):
--     BEGIN;
--       SELECT id FROM ..._external_mapping
--        WHERE game_id=? AND asset_source_id=? AND raw_field=?
--          AND normalized_token=? AND external_set_id IS NOT DISTINCT FROM ?
--          AND is_active
--        FOR UPDATE;                         -- serializa concorrentes
--       UPDATE ..._external_mapping SET is_active = FALSE WHERE id = <M1>;
--       INSERT INTO ..._external_mapping (...) VALUES (..., TRUE);  -- M2
--       INSERT INTO ..._external_mapping_trait (...);               -- composição
--     COMMIT;                                -- selo de M2 dispara aqui
--
-- CONCORRÊNCIA — a autoridade é o ÍNDICE, não uma leitura de aplicação.
-- Duas transações corrigindo o mesmo token: a segunda ou bloqueia no row
-- lock de M1, ou — se nem tocar M1 — colide no índice parcial ao inserir
-- seu próprio ativo. Nos dois caminhos: `unique_violation`. Vale inclusive
-- quando as composições são DISJUNTAS ({A,B} vs {C,D}), que é o caso que
-- derrubaria um modelo baseado em UNIQUE por (token, trait_id) — ver 2172,
-- linhas 68-72.
--
-- DESATIVAR NÃO DEVOLVE O TOKEN AO RESIDUAL. Um token com histórico só
-- inativo é "Edition Context conhecido sem routing ativo" e leva a
-- NEEDS_REVIEW_INACTIVE_EC_MAPPING (2211) — nunca a fail-open silencioso.
--
-- supersedes_mapping_id — DELIBERADAMENTE NÃO ADICIONADO. A 2172 o tem, mas
-- a auditoria de uso mostra que: (a) quem o ESCREVE é a RPC editorial 2181
-- (linha 457) e quem o LÊ é só o action log (linha 573); (b) o routing —
-- 2176 em Printing, 2211 aqui — NUNCA o consulta. Este pacote não tem RPC
-- editorial equivalente para Edition Context, então a coluna nasceria sem
-- escritor e sem leitor. A cadeia de sucessão já é reconstituível por
-- (token, external_set_id, created_at, is_active). Acrescentá-la agora seria
-- overengineering pelo próprio critério do mandato. GATILHO PARA REVISITAR:
-- quando existir uma `admin_resolve_edition_context_mapping()` espelhando a
-- 2181, ela deve trazer a coluna junto — não antes.
-- ----------------------------------------------------------------------------

-- Dois índices parciais DISJUNTOS entre si (external_set_id IS NULL vs NOT
-- NULL) e ambos restritos a is_active. A disjunção preserva a precedência de
-- UM nível (scoped > global) como decisão determinística da 2211.
-- is_active é NOT NULL DEFAULT TRUE (ver DDL acima): NULL escaparia do
-- índice parcial e furaria a invariante — mesma nota da 2172, linha 96.
CREATE UNIQUE INDEX uq_cecem_active_global
    ON public.card_edition_context_external_mapping
       (game_id, asset_source_id, raw_field, normalized_token)
    WHERE external_set_id IS NULL AND is_active;

CREATE UNIQUE INDEX uq_cecem_active_scoped
    ON public.card_edition_context_external_mapping
       (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
    WHERE external_set_id IS NOT NULL AND is_active;

-- Lookup do token INDEPENDENTE de is_active. É este índice que sustenta a
-- pergunta "este token já foi conhecido alguma vez?" — a que distingue
-- NEEDS_REVIEW_INACTIVE_EC_MAPPING (histórico existe) de residual de Finish
-- (nunca conhecido). Sem ele, a prova de "known" seria um seq scan.
-- Paridade com ix_card_printing_external_mapping_token (2172, linha 228).
CREATE INDEX ix_cecem_token
    ON public.card_edition_context_external_mapping
       (game_id, asset_source_id, raw_field, normalized_token);

COMMENT ON INDEX public.uq_cecem_active_global IS
'No maximo UM mapping ATIVO GLOBAL por (Game, Fonte, raw_field, token). Historico inativo ilimitado. E ESTE INDICE que serializa substituicoes concorrentes, inclusive com composicoes disjuntas.';

COMMENT ON INDEX public.uq_cecem_active_scoped IS
'No maximo UM mapping ATIVO SCOPED por (Game, Fonte, external_set_id, raw_field, token). Disjunto do global por construcao (external_set_id IS NOT NULL), o que mantem a precedencia scoped > global deterministica.';

COMMENT ON INDEX public.ix_cecem_token IS
'Suporta "este token ja foi conhecido alguma vez?", independente de is_active — distingue INACTIVE_EC_MAPPING de residual de Finish.';

CREATE TABLE public.card_edition_context_external_mapping_trait (
    mapping_id UUID NOT NULL,
    trait_id   UUID NOT NULL,
    game_id    UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_cecemt PRIMARY KEY (mapping_id, trait_id),
    CONSTRAINT fk_cecemt_mapping
        FOREIGN KEY (mapping_id, game_id)
        REFERENCES public.card_edition_context_external_mapping (id, game_id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_cecemt_trait
        FOREIGN KEY (trait_id, game_id)
        REFERENCES public.card_edition_context_trait (id, game_id)
        ON UPDATE RESTRICT ON DELETE RESTRICT
);

COMMENT ON TABLE public.card_edition_context_external_mapping IS
'Unica ponte entre vocabulario da fonte externa e o eixo Edition Context. Fail-closed: token sem mapping ativo NAO vira contexto, permanece no residual de Finish. raw_field FECHADO em (stamp, subtype) — foil, type e size estao FORA do dominio por CHECK. foil ficou fora deliberadamente (CORRECTION-01/Blocker 6): e semanticamente misto na fonte e legitima-lo no schema permitiria classificacao futura acidental das 57 rows que seguem INDETERMINADAS. Ampliar o dominio exige migration propria.';

-- ----------------------------------------------------------------------------
-- SEGURANÇA — paridade EXATA com as Queries 2172 e 2173
-- ----------------------------------------------------------------------------
-- Corrigido em SECURITY-SEED-HARDENING-01 (B3): as duas tabelas tinham
-- GRANT sem RLS, e a de cabeçalho ainda concedia INSERT/UPDATE ao
-- service_role. Ver comentário completo na 2203.
ALTER TABLE public.card_edition_context_external_mapping       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.card_edition_context_external_mapping_trait ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select
    ON public.card_edition_context_external_mapping
    FOR SELECT
    USING ((SELECT public.is_admin()));

CREATE POLICY catalog_admin_select
    ON public.card_edition_context_external_mapping_trait
    FOR SELECT
    USING ((SELECT public.is_admin()));

REVOKE ALL ON public.card_edition_context_external_mapping       FROM anon, authenticated, service_role;
REVOKE ALL ON public.card_edition_context_external_mapping_trait FROM anon, authenticated, service_role;
GRANT SELECT ON public.card_edition_context_external_mapping       TO authenticated;
GRANT SELECT ON public.card_edition_context_external_mapping_trait TO authenticated;
-- service_role: SELECT e SÓ, e SÓ no cabeçalho — é dele que a Edge resolve
-- token -> traits_signature + is_active, igual ao recorte da Query 2182 para
-- card_printing_external_mapping. A tabela de vínculo fica SEM grant, mesma
-- decisão da Query 2173.
GRANT SELECT ON public.card_edition_context_external_mapping TO service_role;

-- ----------------------------------------------------------------------------
-- GUARDS DO MAPPING — CINCO (v4.0, MAPPING-LIFECYCLE-CORRECTION-02)
--   A  normalizacao canonica do token na entrada        [NOVO v4.0]
--   B  identidade imutavel + lifecycle de is_active     [NOVO v4.0]
--   C  nao-vazio + selamento deferido
--   D  composicao imutavel apos o selo
--   E  selo nao falsificavel
-- Paridade 1:1 com os cinco guards da Query 2174 (LIVE).
-- (bloco original v2.0, BATCH1-RUNTIME-CORRECTION-02, abaixo)
--
-- POR QUE AQUI, E NÃO EM ARQUIVO NOVO — implementação mínima
--   Em Printing, os guards do mapping moram na 2174, separada da 2172, porque
--   lá a 2174 também carrega normalização de token e imutabilidade de
--   identidade. Aqui não há nada disso a acrescentar: os três guards abaixo
--   são o conjunto completo, e as duas tabelas que eles protegem nascem neste
--   mesmo arquivo. Criar uma 2233 só para hospedá-los acrescentaria um 24º
--   artefato ao manifesto de 23, renumeraria batches e abriria uma janela
--   entre "mapping existe" e "mapping é selado" — exatamente o tipo de estado
--   intermediário que o rollout evita. Colocar aqui mantém a criação e a
--   proteção ATÔMICAS na mesma fronteira transacional.
--
-- POR QUE traits_signature NÃO PODE FICAR DORMENTE — divergência medida
--   Antes desta correção existia divergência DETERMINÍSTICA entre os dois
--   consumidores do mesmo mapping:
--     · 2211 (SQL)  — linhas 111 e 159: COALESCE(m.traits_signature,
--                     ARRAY(SELECT mt.trait_id ... ORDER BY mt.trait_id)).
--                     Tolera NULL porque cai na N:N.
--     · Edge patch  — linha 309: const sig = (m.traits_signature ?? [])
--                     linhas 376 e 390: if (sig.length === 0) ->
--                     NEEDS_REVIEW_INVALID_EC_MAPPING.
--                     NÃO consulta a N:N: NULL vira [] e o mapping ATIVO é
--                     tratado como composição vazia.
--   Com o seed 2232 deixando traits_signature NULL, os 122 mappings ativos
--   resolveriam no SQL e falhariam na Edge. Selar na origem elimina a
--   divergência SEM tocar a arquitetura da Edge, SEM query nova e SEM
--   round-trip adicional: a Edge continua lendo exatamente a mesma coluna do
--   mesmo SELECT (linha 169 do patch), que agora nunca é NULL.
--   O COALESCE da 2211 permanece — passa a ser defesa redundante, não o
--   caminho normal. N:N segue sendo a fonte da verdade; a coluna é derivada.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- GUARD A — CANONICIDADE DO TOKEN NA ENTRADA        (v4.0)
--
-- POR QUE NÃO É CONVENÇÃO DE SEED — é correção de routing.
--   A 2176 (`compute_variant_residual_signature`, LIVE) produz o residual
--   JÁ NORMALIZADO, com `public.normalize_external_catalog_value()`:
--       linha 250 (type) · 258 (foil) · 262 (subtype) · 267 (stamp) · 296 (size)
--   A 2211 compara `m.normalized_token = v_res_st` e `= v_tok`, onde esses
--   valores vêm direto de `p.residual_subtype` / `p.residual_stamp`.
--
--   Consequência de um token NÃO-canônico persistido (ex.: 'set-logo',
--   'Pokébola', 'BLUE  BORDER'): ele NUNCA casa com o residual. O mapping
--   fica morto — e pior que morto: o token cai no ramo "desconhecido" e
--   volta ao RESIDUAL DE FINISH. Isso é fail-OPEN silencioso para o eixo
--   errado, exatamente o que a 2207 diz proibir no cabeçalho.
--   O CHECK `btrim(normalized_token) <> ''` não detecta nada disso.
--
-- POR QUE TRIGGER E NÃO CHECK — mesma razão da 2172, linhas 78-84:
--   `normalize_external_catalog_value()` depende de `extensions.unaccent()`,
--   que é STABLE. O PostgreSQL exige IMMUTABLE em CHECK. Normalizar na
--   ENTRADA é mais forte que validar: não existe caminho pelo qual um token
--   não-canônico entre.
--
-- ESCOPO — o que é normalizado e o que NÃO é, com a razão medida:
--   · normalized_token  -> normalize_external_catalog_value()
--       upper + unaccent + trim + colapso de espaços. Confere com o corpus
--       semeado pela 2232: 'BLUE-BORDER', 'SET-LOGO', 'POKEBALL'.
--   · external_set_id   -> SOMENTE btrim. NÃO pode sofrer upper().
--       É a chave de junção com `card_set_external_reference`, cujo próprio
--       trigger (Query 241, linha 21) faz apenas `btrim`. O corpus da 2232
--       usa MINÚSCULAS ('dp1', 'swsh9', 'svp', 'mfb'). Aplicar upper() aqui
--       quebraria a junção da precedência scoped e o gate de cobertura.
--   · raw_field         -> INTOCADO.
--       O domínio já é fechado por `ck_cecem_raw_field` em ('stamp',
--       'subtype'), minúsculas. upper() tornaria TODA inserção inválida.
--
-- Deliberadamente BEFORE INSERT apenas: a identidade é imutável depois
-- (GUARD B), então não há UPDATE legítimo que precise re-normalizar.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.normalize_edition_context_external_mapping()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    NEW.normalized_token := public.normalize_external_catalog_value(NEW.normalized_token);

    IF btrim(NEW.normalized_token) = '' THEN
        RAISE EXCEPTION 'EDITION_CONTEXT_MAPPING_EMPTY_TOKEN: o token normalizado ficou vazio — token externo inválido.';
    END IF;

    -- NÃO normalizar: apenas aparar. Ver bloco ESCOPO acima.
    IF NEW.external_set_id IS NOT NULL THEN
        NEW.external_set_id := btrim(NEW.external_set_id);
        IF NEW.external_set_id = '' THEN
            RAISE EXCEPTION 'EDITION_CONTEXT_MAPPING_EMPTY_SET_SCOPE: external_set_id em branco. Use NULL para escopo GLOBAL.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cecem_normalize
    ON public.card_edition_context_external_mapping;

CREATE TRIGGER trg_cecem_normalize
BEFORE INSERT ON public.card_edition_context_external_mapping
FOR EACH ROW
EXECUTE FUNCTION internal.normalize_edition_context_external_mapping();

-- ----------------------------------------------------------------------------
-- GUARD B — IDENTIDADE HISTÓRICA IMUTÁVEL + LIFECYCLE DE is_active   (v4.0)
--
-- Paridade com `internal.enforce_card_printing_external_mapping_header()`
-- (2174, linhas 122-158). Sem este guard, os índices parciais garantem
-- unicidade concorrente mas NÃO impedem:
--   (a) reescrever a identidade externa de um mapping já selado — o que
--       apagaria a história do routing em vez de acrescentar um capítulo;
--   (b) RESSUSCITAR um mapping aposentado com `is_active = TRUE`. O índice
--       parcial só recusaria isso se já houvesse OUTRO ativo; sem ativo
--       algum, a reativação passaria — e é justamente o caso em que ela é
--       mais perigosa, porque restaura um mapeamento que foi julgado errado.
--
-- `external_set_id` entra na identidade protegida (Printing não o tem):
-- mover um mapping de GLOBAL para SCOPED, ou entre Sets, trocaria o índice
-- parcial sob o qual ele vive e poderia criar um segundo ativo por vias
-- transversas.
--
-- INTERAÇÃO COM O SELO — verificada, não assumida (mesma análise da 2174,
-- linhas 35-47):
--   · GUARD E é `BEFORE UPDATE OF traits_signature`. Um
--     `UPDATE ... SET is_active = FALSE` NÃO o dispara — a coluna do selo
--     não está na lista de colunas do evento.
--   · O `UPDATE` de selamento emitido pelo GUARD C não toca identidade nem
--     is_active, então atravessa ESTE guard sem reclamação.
--   Ou seja: composição continua imutável E o mapping ainda pode ser
--   aposentado. É isso que torna a correção editorial possível sem abrir
--   exceção no selo.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.enforce_edition_context_mapping_header()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.game_id          IS DISTINCT FROM OLD.game_id
    OR NEW.asset_source_id  IS DISTINCT FROM OLD.asset_source_id
    OR NEW.external_set_id  IS DISTINCT FROM OLD.external_set_id
    OR NEW.raw_field        IS DISTINCT FROM OLD.raw_field
    OR NEW.normalized_token IS DISTINCT FROM OLD.normalized_token THEN
        RAISE EXCEPTION 'EDITION_CONTEXT_MAPPING_IDENTITY_IMMUTABLE: a identidade externa de um mapeamento de Contexto de Edição não pode ser alterada. Crie um mapeamento novo e aposente este.';
    END IF;

    -- FALSE -> TRUE é o ÚNICO caminho proibido. TRUE -> FALSE é a
    -- aposentadoria legítima; TRUE -> TRUE e FALSE -> FALSE são no-ops.
    IF OLD.is_active = FALSE AND NEW.is_active = TRUE THEN
        RAISE EXCEPTION 'EDITION_CONTEXT_MAPPING_REACTIVATION_FORBIDDEN: um mapeamento aposentado não pode ser reativado, nem quando não existe outro ativo. A correção editorial é criar um mapeamento novo.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cecem_header
    ON public.card_edition_context_external_mapping;

CREATE TRIGGER trg_cecem_header
BEFORE UPDATE ON public.card_edition_context_external_mapping
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_edition_context_mapping_header();

-- GUARD C — não-vazio + selamento (deferido, 1x por mapping)
-- Mesmo mecanismo da 2174: CONSTRAINT TRIGGER sobre o CABEÇALHO, nunca sobre
-- a N:N. Dispara uma vez por mapping, no COMMIT — inclusive quando nenhum
-- vínculo existe, que é justamente o caso que precisa falhar.
CREATE OR REPLACE FUNCTION internal.seal_edition_context_external_mapping()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_signature UUID[];
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.card_edition_context_external_mapping m WHERE m.id = NEW.id
    ) THEN
        RETURN NULL;
    END IF;

    -- DISTINCT por construção (pk_cecemt é (mapping_id, trait_id)) e ORDENADO.
    -- ARRAY(SELECT ...) devolve '{}' quando não há linhas — nunca NULL.
    v_signature := ARRAY(
        SELECT t.trait_id
          FROM public.card_edition_context_external_mapping_trait t
         WHERE t.mapping_id = NEW.id
         ORDER BY t.trait_id
    );

    IF cardinality(v_signature) = 0 THEN
        RAISE EXCEPTION 'EDITION_CONTEXT_EXTERNAL_MAPPING_EMPTY_COMPOSITION: o mapeamento de Contexto de Edição % chegou ao COMMIT sem nenhum Traço. Mapeamento parcial não é permitido — seria lido como composição vazia pela Edge.', NEW.id;
    END IF;

    UPDATE public.card_edition_context_external_mapping
       SET traits_signature = v_signature,
           updated_at       = now()
     WHERE id = NEW.id;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_cecem_seal
    ON public.card_edition_context_external_mapping;

CREATE CONSTRAINT TRIGGER trg_cecem_seal
AFTER INSERT ON public.card_edition_context_external_mapping
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION internal.seal_edition_context_external_mapping();

-- GUARD D — imutabilidade da composição do mapping
CREATE OR REPLACE FUNCTION internal.guard_edition_context_mapping_composition_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_mapping_id UUID;
    v_signature  UUID[];
    v_exists     BOOLEAN;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'EDITION_CONTEXT_MAPPING_TRAIT_UPDATE_FORBIDDEN: vínculo de composição nunca pode ser atualizado. Crie um mapeamento novo e reconcilie.';
    END IF;

    v_mapping_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.mapping_id ELSE NEW.mapping_id END;

    SELECT m.traits_signature, TRUE INTO v_signature, v_exists
      FROM public.card_edition_context_external_mapping m
     WHERE m.id = v_mapping_id;

    IF v_exists IS NULL THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;

    IF v_signature IS NULL THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;

    -- SELADO. Reinserção IDÊNTICA não é mudança semântica — deixa passar para
    -- que o seed 2232 (ON CONFLICT DO NOTHING) continue idempotente. O ramo é
    -- obrigatório: trigger BEFORE INSERT dispara ANTES da arbitragem do
    -- ON CONFLICT. Mesma nota da 2174.
    IF TG_OP = 'INSERT'
       AND EXISTS (
           SELECT 1 FROM public.card_edition_context_external_mapping_trait t
            WHERE t.mapping_id = NEW.mapping_id
              AND t.trait_id   = NEW.trait_id
       ) THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'EDITION_CONTEXT_MAPPING_COMPOSITION_SEALED: o mapeamento de Contexto de Edição % já está selado e sua composição é imutável. Crie um mapeamento novo.', v_mapping_id;
END;
$$;

DROP TRIGGER IF EXISTS trg_cecemt_immutable
    ON public.card_edition_context_external_mapping_trait;

CREATE TRIGGER trg_cecemt_immutable
BEFORE INSERT OR UPDATE OR DELETE ON public.card_edition_context_external_mapping_trait
FOR EACH ROW
EXECUTE FUNCTION internal.guard_edition_context_mapping_composition_immutable();

-- GUARD E — o selo do mapping não pode ser destravado nem falsificado
CREATE OR REPLACE FUNCTION internal.enforce_edition_context_mapping_signature_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_real UUID[];
BEGIN
    IF NEW.traits_signature IS NOT DISTINCT FROM OLD.traits_signature THEN
        RETURN NEW;
    END IF;

    IF OLD.traits_signature IS NOT NULL THEN
        RAISE EXCEPTION 'EDITION_CONTEXT_MAPPING_SIGNATURE_IMMUTABLE: a assinatura de composição do mapeamento % já foi selada e não pode ser alterada nem removida.', OLD.id;
    END IF;

    v_real := ARRAY(
        SELECT t.trait_id
          FROM public.card_edition_context_external_mapping_trait t
         WHERE t.mapping_id = NEW.id
         ORDER BY t.trait_id
    );

    IF NEW.traits_signature IS DISTINCT FROM v_real THEN
        RAISE EXCEPTION 'EDITION_CONTEXT_MAPPING_SIGNATURE_MISMATCH: a assinatura informada para o mapeamento % não corresponde à composição real registrada.', NEW.id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cecem_signature_write
    ON public.card_edition_context_external_mapping;

CREATE TRIGGER trg_cecem_signature_write
BEFORE UPDATE OF traits_signature ON public.card_edition_context_external_mapping
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_edition_context_mapping_signature_write();

-- ACL: mesma disciplina estrita da 2206. Cinco funcoes (v4.0).
REVOKE ALL ON FUNCTION internal.normalize_edition_context_external_mapping()          FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.enforce_edition_context_mapping_header()              FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.seal_edition_context_external_mapping()                FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.guard_edition_context_mapping_composition_immutable()  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.enforce_edition_context_mapping_signature_write()      FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
