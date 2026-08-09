# Modelo de Dados — Catálogo Editorial (Escrita e Ingestão Administrativa)

| Campo | Valor |
|--------|-------|
| **Documento** | Modelo de Dados — Catálogo Editorial |
| **Arquivo** | `docs/05e-catalogo-editorial.md` |
| **Versão** | 1.0 |
| **Status** | Em elaboração |
| **Objetivo** | Modelo físico da autorização de escrita administrativa do catálogo (ADR-022/ADR-023) e da ingestão administrativa de cartas (ADR-024) — o bloco de maior atividade recente do projeto. |
| **Escopo** | Parte de `docs/05-modelo-de-dados.md` (índice) — resultado da divisão de 2026-08-06, motivada pelo tamanho do arquivo original (mais de 700 KB, acima do que ferramentas de leitura processam em uma chamada). |
| **Dependências** | `04-domain-model.md`, `standards/STD-001-database-standards.md`, `05-modelo-de-dados.md`, `07-catalogo-editorial.md`, `adr/ADR-023-catalog-editorial-write-authorization.md`, `adr/ADR-024-catalog-card-ingestion-strategy.md` |

Ver `docs/05-modelo-de-dados.md` para o mapa completo do domínio, a metodologia (Roteiro por Entidade) e o histórico de revisão consolidado até 2026-08-06 (revisões anteriores a esta divisão não foram redistribuídas retroativamente por entidade — ver nota na Revision History de lá).

---

# Autorização do Catálogo Editorial

## Status

**CONFIRMADO EXECUTADO (2026-07-26).** Formaliza `ADR-022` (Catalog Editorial Admin-Only Access): todo o módulo Catálogo Editorial — menu, rota e dado — passa a ser exclusivo de administradores. Motivado pela retomada do frontend do módulo (tela Visão Geral) e pela descoberta, durante a verificação que antecedeu o desenho da tela, de que as 17 tabelas do Catálogo Editorial já tinham Row Level Security habilitado sem nenhuma política — ou seja, ninguém (nem administrador) conseguia ler esses dados pela API. Este incremento torna esse fechamento uma decisão explícita, seguindo exatamente o mesmo rigor já aplicado em Administração de Usuários (acima): leitura mínima necessária, escrita sensível sempre por função vetada.

## Leitura — políticas `catalog_admin_select` (Query `274`, CONFIRMADO EXECUTADO)

Política `SELECT` idêntica em dez tabelas — as únicas efetivamente consultadas pela Visão Geral aprovada: `game`, `expansion`, `card_set`, `card`, `card_variant`, `card_asset`, `language`, `rarity`, `card_category`, `asset_import_run`.

```sql
CREATE POLICY catalog_admin_select ON public.<tabela>
    FOR SELECT USING (is_admin());
GRANT SELECT ON public.<tabela> TO authenticated;
```

Reaproveita `is_admin()` (`ADR-021`). Sem o `GRANT` de nível de tabela do PostgreSQL, a política nunca chega a ser avaliada — mesmo gap já visto nas Queries `250`/`253`/`254`/`272`. As sete tabelas do Catálogo Editorial ainda não consultadas por nenhuma tela real (`card_variant_type`, `card_asset_type`, `storage_bucket`, `asset_source`, `card_external_reference`, `card_set_external_reference`, `asset_import_failure`) permanecem sem nenhuma política — fechadas até que uma tela real precise delas, por decisão explícita (`AP-004`, Simplicidade Inicial), não por esquecimento. Confirmado via `pg_policies`/`information_schema.role_table_grants`. Arquivo em `database/migrations/274_add_admin_only_select_policies_to_catalog_tables.sql`.

## Escrita da logo — `admin_set_card_set_logo()` (Query `275`, CONFIRMADO EXECUTADO)

Nenhuma tabela do Catálogo Editorial recebeu política de `INSERT`/`UPDATE`/`DELETE` neste incremento. A escrita de `card_set.logo_storage_path` passa exclusivamente por uma função `SECURITY DEFINER`, mesmo padrão já usado em `admin_grant_admin()`/`admin_revoke_admin()` (`ADR-021`): restrita a administradores, restrita a este único campo, e que nunca falha silenciosamente — confirma via `GET DIAGNOSTICS ... ROW_COUNT` que exatamente uma linha foi alterada, levantando exceção se o Card Set informado não existir.

```sql
CREATE OR REPLACE FUNCTION public.admin_set_card_set_logo(
    p_card_set_id UUID,
    p_logo_storage_path TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_rows_updated INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_SET_CARD_SET_LOGO_FORBIDDEN: apenas administradores podem alterar a logo de um Card Set.';
    END IF;

    IF p_logo_storage_path IS NOT NULL
       AND p_logo_storage_path ~* '^[a-z][a-z0-9+.-]*://' THEN
        RAISE EXCEPTION 'ADMIN_SET_CARD_SET_LOGO_INVALID_PATH: logo_storage_path deve ser um caminho relativo, nunca uma URL absoluta.';
    END IF;

    UPDATE public.card_set
        SET logo_storage_path = p_logo_storage_path,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_card_set_id;

    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

    IF v_rows_updated <> 1 THEN
        RAISE EXCEPTION 'ADMIN_SET_CARD_SET_LOGO_NOT_FOUND: nenhum Card Set encontrado para o id informado (%).', p_card_set_id;
    END IF;
END;
$$;
```

Confirmado estruturalmente: `SECURITY DEFINER`, `search_path` vazio, `EXECUTE` concedido a `authenticated` e negado a `anon`/`public`. Chamada em tempo real não foi testada nesta rodada (bloqueada pelo classificador automático do ambiente de execução por se parecer com uma ação de escrita) — comportamento validado por revisão do corpo da função. Arquivo em `database/migrations/275_create_admin_set_card_set_logo_function.sql`.

## Storage — bucket `card-set-logo` (Query `276`, CONFIRMADO EXECUTADO)

Bucket privado, dedicado exclusivamente às logos de Card Set — diverge deliberadamente do padrão público já usado por `card-front`/`artwork`/`card-back`/`avatars`, porque o Catálogo Editorial é admin-only por completo. Leitura no frontend ocorre por URL assinada (`createSignedUrl()`), nunca `getPublicUrl()`. Quatro políticas separadas em `storage.objects` — nunca uma única `FOR ALL` — cada uma restrita a `bucket_id = 'card-set-logo' AND is_admin()`:

```sql
INSERT INTO storage.buckets (id, name, public)
VALUES ('card-set-logo', 'card-set-logo', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY card_set_logo_admin_select ON storage.objects
    FOR SELECT USING (bucket_id = 'card-set-logo' AND is_admin());

CREATE POLICY card_set_logo_admin_insert ON storage.objects
    FOR INSERT WITH CHECK (bucket_id = 'card-set-logo' AND is_admin());

CREATE POLICY card_set_logo_admin_update ON storage.objects
    FOR UPDATE USING (bucket_id = 'card-set-logo' AND is_admin())
    WITH CHECK (bucket_id = 'card-set-logo' AND is_admin());

CREATE POLICY card_set_logo_admin_delete ON storage.objects
    FOR DELETE USING (bucket_id = 'card-set-logo' AND is_admin());
```

`card-set-logo` não é registrado na tabela `storage_bucket` — mesmo padrão já usado por `avatars` (bucket module-owned, fora do catálogo multi-bucket de `card_asset`). Confirmado via `storage.buckets`/`pg_policies`. Arquivo em `database/migrations/276_create_card_set_logo_storage_bucket_and_policies.sql`.

## Menu e rota (CONFIRMADO IMPLEMENTADO E VALIDADO EM PRODUÇÃO)

Guarda de menu (`nav-config.ts`, `catalogo.adminOnly = true`) e guarda de servidor compartilhada pelas rotas do módulo (`components/catalogo/catalogo-guard.tsx`, função `requireCatalogoAdmin()`), mesmo padrão já validado em produção em `/usuarios/page.tsx`: sem sessão → `/login`; sem papel administrativo → `Alert` de acesso restrito, nenhum conteúdo real renderizado. Aplicada a `/catalogo`, `/jogos`, `/expansoes`, `/card-sets`, `/cartas`, `/importacoes` e à rota de detalhe `/catalogo/card-sets/[code]`. `tsc --noEmit` confirmado limpo; validação visual em produção real confirmada (2026-08-08) — todas as telas do módulo estão implementadas, nenhuma segue como `ComingSoonPage` (ver auditoria da Frente C em `ROADMAP.md`, seção "Catálogo Editorial — Frentes de Encerramento").

## Sequência

```text
274 - Add Admin-Only SELECT Policies to Catalog Tables   (CONFIRMADO EXECUTADO — database/migrations/274_add_admin_only_select_policies_to_catalog_tables.sql)
275 - Create admin_set_card_set_logo() Function            (CONFIRMADO EXECUTADO — database/migrations/275_create_admin_set_card_set_logo_function.sql)
276 - Create Card Set Logo Storage Bucket and Policies      (CONFIRMADO EXECUTADO — database/migrations/276_create_card_set_logo_storage_bucket_and_policies.sql)
277 - Validate Catalog Editorial Authorization and Logo     (EXECUTADA — database/validations/277_validate_catalog_editorial_authorization_and_logo.sql)
```

(`273 - Add Card Set Logo Column` documentada na seção "Set" acima, não repetida aqui.)

## Frontend — Visão Geral (`/catalogo`, CONFIRMADO IMPLEMENTADO E VALIDADO EM PRODUÇÃO)

Implementada após a fundação de banco acima ser concluída e validada, conforme condicionado por Fabrício. Quatro blocos, todos exclusivos de administradores (guarda de servidor + RLS `catalog_admin_select`):

- **Estado do Catálogo** — KPIs de estado (Card Sets catalogados, cobertura de imagens, cartas catalogadas, importações com pendência), deliberadamente sem Games/Expansions (só 1 registro cada, sem valor visual).
- **Card Sets** — tabela navegável; cada linha leva a `/catalogo/card-sets/{code}`, uma página de detalhe mínima (mesmos dados já resumidos na tabela — galeria de cartas, edição de logo e histórico de importações do Set ficam para um incremento futuro).
- **Cartas por raridade** — distribuição em barras simples (CSS, sem nova dependência de gráfico); deliberadamente por Raridade, não por Card Category, para não expor a discrepância interna da categoria `ENERGY`.
- **Atividade Recente** — últimas execuções de `asset_import_run` traduzidas para linguagem natural; continua sendo informação exclusivamente administrativa (decisão de Fabrício), nunca pública.

Camada de dados em `web/lib/catalogo/queries.ts` — leitura direta das 10 tabelas liberadas pela Query `274`, sem função de banco dedicada (volume atual, ~927 Cards, pequeno o suficiente para agregar no servidor Next.js). Guarda compartilhada em `web/components/catalogo/catalogo-guard.tsx`.

**Ressalva de transparência**: os blocos e o wireframe originais foram aprovados por Fabrício em uma troca anterior à compactação de contexto desta sessão; o texto exato (indicadores linha a linha, wireframe ASCII) não pôde ser recuperado integralmente. Esta implementação reconstrói os quatro blocos e os seis refinamentos já confirmados (rota `/catalogo` separada de `/`, KPIs de estado sem Games/Expansions, Atividade Recente amigável, sem expor `ENERGY`, tabela navegável) a partir do resumo disponível e de nova verificação direta do banco — os indicadores exatos (títulos, agrupamentos) podem não ser idênticos ao que foi aprovado originalmente e valem uma conferência de Fabrício.

## Pendências / Próximos Passos

Validação visual em produção real confirmada (2026-08-08) — nenhuma pendência de validação nesta frente. Único item real, confirmado por auditoria dedicada (2026-08-08) como evolução futura por design original, não como pendência bloqueante: design completo do detalhe de Card Set (`/catalogo/card-sets/[code]`) — galeria de cartas, upload de logo via `admin_set_card_set_logo()`, histórico de importações do Set. Registrado como débito não bloqueante em `ROADMAP.md`, seção "Débitos Técnicos Registrados (Sem Cronograma)". Todas as demais telas do módulo (`/catalogo/jogos`, `/expansoes`, `/card-sets`, `/cartas`, `/importacoes`) estão implementadas, com a guarda de admin aplicada — nenhuma segue como `ComingSoonPage`.

---

# Catálogo Editorial — Escrita e Ingestão

## Status

**EM IMPLEMENTAÇÃO (iniciado em 2026-07-26).** Formaliza `ADR-023` (Catalog Editorial Write Authorization) e `ADR-024` (Catalog Card Ingestion Strategy). Numeração no milhar `2000`–`2999` (`STD-001` v1.17, Seção 10). **Correção real (2026-08-02, auditoria de reconciliação documental)**: `ADR-024` não ficou como "incremento futuro" — Fabrício redirecionou o foco do projeto para ele antes do fechamento total de `ADR-023` (o subciclo `Card` de `ADR-023` segue pausado, não iniciado). `ADR-023`: ciclos verticais de `Game`/`Expansion`/`Card Set` CONCLUÍDOS (backend + tela + validação); só falta o subciclo `Card` (criação/edição; desativação/reativação), pausado. `ADR-024`: Ciclo 1 (infraestrutura comum de staging) CONFIRMADO EXECUTADO E VALIDADO; Ciclo 2 (fluxo vertical TCGdex completo) implementado e em uso ativo em produção, sem o mesmo fechamento formal do Ciclo 1 — ver seção "Ciclo 1 — Infraestrutura comum de staging e confirmação", abaixo, e as revisões `1.1`–`1.50` desta tabela para o detalhe do Ciclo 2; narrativa completa também no handoff vigente (`docs/development/`).

## Schema `internal` (Query `2000`, CONFIRMADO EXECUTADO)

Schema dedicado a rotinas de persistência internas, não expostas pela API (`STD-001` v1.17, Seção 9). Primeira rotina prevista: `internal.write_card()` (Query `2030`).

```sql
CREATE SCHEMA internal;

COMMENT ON SCHEMA internal IS
    'Rotinas de persistência internas do Catálogo Editorial (ADR-023/ADR-024). '
    'Nunca exposto pela API do Supabase. Contém apenas funções SECURITY DEFINER, '
    'nunca tabelas ou views (STD-001 v1.17, Seção 9).';

REVOKE ALL ON SCHEMA internal FROM PUBLIC;
REVOKE ALL ON SCHEMA internal FROM anon;
REVOKE ALL ON SCHEMA internal FROM authenticated;
```

Confirmado: schema existe, comentário gravado, `nspacl = {postgres=UC/postgres}` (nenhuma entrada para `PUBLIC`/`anon`/`authenticated`), `has_schema_privilege('anon'/'authenticated', 'internal', 'USAGE')` = `false` para ambos. Confirmado manualmente por Fabrício: `internal` não consta em Studio → Settings → API → Exposed schemas (só `graphql_public`/`public` expostos). Arquivo em `database/schema/2000_create_internal_schema.sql`; validação em `database/validations/2800_validate_internal_schema.sql`.

## Auditoria — `catalog_admin_action_log` (Query `2010`, CONFIRMADO EXECUTADO)

Auditoria própria do módulo, deliberadamente separada de `admin_action_log` (`ADR-021`, domínio de Identidade & Acesso). Nome definitivo confirmado nesta implementação — `ADR-023` havia registrado apenas um exemplo, deixando a confirmação para este documento.

```sql
CREATE TABLE public.catalog_admin_action_log (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id         UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    action           TEXT NOT NULL,
    entity_type      TEXT NOT NULL,
    entity_id        UUID NOT NULL,
    metadata         JSONB NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT ck_catalog_admin_action_log_action_valid
        CHECK (action IN (
            'GAME_CREATED', 'GAME_UPDATED',
            'EXPANSION_CREATED', 'EXPANSION_UPDATED',
            'CARD_SET_CREATED', 'CARD_SET_UPDATED',
            'CARD_CREATED', 'CARD_UPDATED',
            'CARD_DEACTIVATED', 'CARD_REACTIVATED'
        )),
    CONSTRAINT ck_catalog_admin_action_log_entity_type_valid
        CHECK (entity_type IN ('GAME', 'EXPANSION', 'CARD_SET', 'CARD')),
    CONSTRAINT ck_catalog_admin_action_log_action_entity_match
        CHECK (
            (entity_type = 'GAME' AND action IN ('GAME_CREATED', 'GAME_UPDATED'))
            OR (entity_type = 'EXPANSION' AND action IN ('EXPANSION_CREATED', 'EXPANSION_UPDATED'))
            OR (entity_type = 'CARD_SET' AND action IN ('CARD_SET_CREATED', 'CARD_SET_UPDATED'))
            OR (entity_type = 'CARD' AND action IN (
                    'CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED'
                ))
        )
);

ALTER TABLE public.catalog_admin_action_log ENABLE ROW LEVEL SECURITY;
```

`entity_id` é polimórfico (aponta para `game`/`expansion`/`card_set`/`card` conforme `entity_type`) e por isso não tem FK — `NOT NULL` porque toda ação registrada aqui sempre tem exatamente uma entidade concreta como alvo. `actor_id` anulável com `ON DELETE SET NULL`, mesmo padrão de `admin_action_log`. Terceiro `CHECK` (`action_entity_match`) é reforço de integridade de implementação, adicional ao que `ADR-023` descreveu — garante que uma combinação logicamente inválida (ex. `GAME_CREATED` com `entity_type = 'CARD'`) nunca é gravada. Confirmado via `information_schema`/`pg_constraint`/`pg_tables`/`pg_policies`: 7 colunas, 5 constraints (PK, FK, 3 CHECKs), RLS habilitado, zero políticas. Arquivo em `database/schema/2010_create_catalog_admin_action_log.sql`; validação em `database/validations/2801_validate_catalog_admin_action_log.sql`.

## `card.is_active` (Query `2020`, CONFIRMADO EXECUTADO)

Soft delete real e irrestrito, não condicionado à ausência de dependentes (`ADR-023`).

```sql
ALTER TABLE public.card
    ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT true;
```

`DEFAULT true` evita qualquer backfill separado — as 927 Cards existentes tornaram-se ativas automaticamente, confirmado (`927`/`927`). `uq_card_card_set_collector_number` (Query `140`) permanece inalterada e continua válida independentemente de `is_active` — uma Card inativa continua ocupando sua chave natural. Nenhum índice criado nesta Query (volume atual não justifica; reavaliar quando o número de Cards inativas crescer). Nenhuma cascata para `card_variant`/`card_asset`/`card_external_reference`. O ajuste da camada de leitura (`web/lib/catalogo/queries.ts` filtrar `is_active = true` por padrão) fica para o ciclo vertical de `Card`, junto com `admin_deactivate_card()`/`admin_reactivate_card()` (`2039`/`2040`) e o controle de inativas na tela. Arquivo de execução em `database/migrations/2020_add_is_active_to_card.sql`; canônica `database/schema/140_create_card_table.sql` atualizada para v1.1 (Princípio da Fonte Canônica); validação em `database/validations/2802_validate_card_is_active.sql`.

## `internal.write_card()` (Query `2030`, CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE)

Camada canônica única de persistência de Card — reutilizada por `admin_create_card()` (ainda não escrita) e `admin_update_card()` (Query `2114`, ver abaixo) e, em `ADR-024`, por `admin_confirm_catalog_import()` (`ADR-023`, "Camada interna canônica").

```sql
CREATE OR REPLACE FUNCTION internal.write_card(
    p_mode TEXT, p_card_id UUID, p_card_set_id UUID, p_rarity_id UUID,
    p_category_id UUID, p_collector_number TEXT, p_collector_total INTEGER,
    p_collector_order INTEGER, p_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$ ... $$;

REVOKE ALL ON FUNCTION internal.write_card(...) FROM PUBLIC, anon, authenticated;
```

`p_mode` distingue `CREATE`/`UPDATE` numa função única — evita duplicar a proteção de campos sensíveis em dois lugares. Modo `UPDATE`: se o chamador informar `p_card_set_id`/`p_collector_number` não-nulos, a função levanta `INTERNAL_WRITE_CARD_PROTECTED_FIELD` — nunca ignora silenciosamente um valor divergente. Semântica de substituição integral (não parcial) nos campos editáveis, evitando a ambiguidade de `NULL` como sentinela de "não alterar" em `collector_total` (que também aceita `NULL` como valor real). `is_active` nunca é tocado aqui — pertence exclusivamente a `admin_deactivate_card()`/`admin_reactivate_card()` (`2039`/`2040`).

**Descoberta de implementação**: a consistência de Game (Card Set/Rarity/Card Category no mesmo Game) e `updated_at` já são garantidos pelo trigger existente `trg_card_validate_game_consistency`/`trg_card_set_updated_at` (Query `141`), independentemente de quem faz o `INSERT`/`UPDATE` — a "validação de FK" que `ADR-023` atribui a esta camada já é satisfeita por construção, sem duplicar lógica. Por simetria com `admin_set_card_set_logo()` (que faz sua própria checagem de `is_admin()` por não ter camada interna), esta função **não** verifica `is_admin()` — essa responsabilidade é exclusiva das funções públicas que a chamam (`2037`/`2038`), já que `EXECUTE` é revogado de todos exceto o owner.

Validado estruturalmente (`prosecdef = true`, `search_path = ""`, `anon`/`authenticated` sem `EXECUTE`) **e funcionalmente, com execução real contra o banco** — primeira função deste módulo testada em tempo real, não apenas por revisão de código: cinco cenários (`CREATE` bem-sucedido; `UPDATE` de campos editáveis; tentativa de alterar `card_set_id` bloqueada; `UPDATE` de id inexistente bloqueado; `p_mode` inválido bloqueado), todos dentro de uma transação com `RAISE EXCEPTION` forçado ao final — `ROLLBACK` total confirmado, `0` linhas residuais. Arquivo em `database/schema/2030_create_internal_write_card_function.sql`; validação em `database/validations/2803_validate_internal_write_card.sql`.

## `admin_update_card()` (Query `2114`, CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE)

Tela de edição de Card (`/catalogo/cartas`, botão de ação rápida no canto inferior direito de cada carta do grid — pedido de Fabrício, 2026-08-07: "Encontrei duas cartas cadastradas com a raridade errada... possibilitando editar todas as informações possíveis... incluindo a sua raridade"). Primeira função pública deste módulo a chamar `internal.write_card()` em modo `UPDATE` — `admin_confirm_catalog_import()` (`ADR-024`) já a chamava em modo `CREATE`.

```sql
CREATE OR REPLACE FUNCTION public.admin_update_card(
    p_id UUID,
    p_name TEXT,
    p_collector_total INTEGER,
    p_collector_order INTEGER,
    p_rarity_id UUID,
    p_category_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_card_set_id UUID;
    v_name TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_FORBIDDEN: apenas administradores podem atualizar uma Card.';
    END IF;

    SELECT card_set_id INTO v_card_set_id FROM public.card WHERE id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_NOT_FOUND: nenhuma Card encontrada para o id informado (%).', p_id;
    END IF;

    v_name := btrim(coalesce(p_name, ''));
    IF v_name = '' THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF p_collector_total IS NOT NULL AND p_collector_total <= 0 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_INVALID_COLLECTOR_TOTAL: o total, quando informado, deve ser positivo.';
    END IF;

    IF p_collector_order IS NULL OR p_collector_order <= 0 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_INVALID_COLLECTOR_ORDER: a ordem editorial deve ser um número positivo.';
    END IF;

    IF p_rarity_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.rarity WHERE id = p_rarity_id) THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_RARITY_NOT_FOUND: selecione uma Raridade válida.';
    END IF;

    IF p_category_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.card_category WHERE id = p_category_id) THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_CATEGORY_NOT_FOUND: selecione uma Categoria válida.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.card
        WHERE card_set_id = v_card_set_id AND collector_order = p_collector_order AND id <> p_id
    ) THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_DUPLICATE_COLLECTOR_ORDER: já existe outra Card com a ordem editorial % neste Card Set.', p_collector_order;
    END IF;

    -- p_card_set_id/p_collector_number sempre NULL — nunca editáveis por
    -- esta função (ADR-023); internal.write_card() levantaria
    -- INTERNAL_WRITE_CARD_PROTECTED_FIELD se recebesse qualquer um dos dois.
    PERFORM internal.write_card(
        'UPDATE', p_id, NULL, p_rarity_id, p_category_id,
        NULL, p_collector_total, p_collector_order, v_name
    );

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'CARD_UPDATED', 'CARD', p_id,
            jsonb_build_object(
                'name', v_name, 'collector_total', p_collector_total,
                'collector_order', p_collector_order,
                'rarity_id', p_rarity_id, 'category_id', p_category_id
            )
        );

    RETURN p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_card(UUID, TEXT, INTEGER, INTEGER, UUID, UUID) TO authenticated;
```

`card_set_id`/`collector_number` nunca aparecem na assinatura — nem como parâmetro opcional — mesmo princípio de `expansion_id`/`code` em `admin_update_card_set()` antes da emenda 2026-08-01 (aqui não há emenda equivalente: `collector_number` continua estruturalmente protegido sem exceção, decisão explícita do ADR-023). `uq_card_card_set_collector_order` (Query `140`) já impediria a duplicata na constraint bruta, mas a checagem explícita antecipa um erro administrativo legível, mesmo padrão de `release_order` em `admin_update_card_set()`. `rarity_id`/`category_id` validados contra `rarity`/`card_category` antes do `UPDATE` — `internal.write_card()` não faz essa checagem (confia no trigger `trg_card_validate_game_consistency`, que só dispara *depois* do `UPDATE` já ter sido tentado); validar antes produz uma mensagem mais clara para o mesmo caso. Grava `catalog_admin_action_log` (`CARD_UPDATED`) — ação já prevista no `CHECK` desde a Query `2098` (rodada de Raridade/Mapeamento, mesmo dia mais cedo), nenhuma migration de constraint necessária.

Frontend: `web/app/catalogo/cartas/actions.ts` (`updateCard`), `web/components/catalogo/carta-dialogs.tsx` (`EditCardDialog`), botão de ação rápida em `CartaGridCard` (`web/components/catalogo/cartas-gallery.tsx`). Validado funcionalmente por Fabrício em 2026-08-07 (edição via UI, sem erros).

## `admin_create_card()`/`admin_deactivate_card()`/`admin_reactivate_card()` (Queries `2115`/`2116`/`2117`, CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE)

Fecha o subciclo `Card` deste módulo — pedido explícito de Fabrício, mesmo dia da Query `2114`: "Vamos avançar com o Resto do subciclo `Card` (ADR-023) — criação e desativação/reativação administrativa (edição já está pronta)". Ver `ADR-023`, "Emenda (2026-08-07) — `Card`: cadastro e desativação/reativação real via UI", para o registro conceitual completo; esta seção cobre a implementação.

```sql
CREATE OR REPLACE FUNCTION public.admin_create_card(
    p_card_set_id UUID, p_collector_number TEXT, p_collector_total INTEGER,
    p_collector_order INTEGER, p_rarity_id UUID, p_category_id UUID, p_name TEXT
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;

CREATE OR REPLACE FUNCTION public.admin_deactivate_card(p_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;

CREATE OR REPLACE FUNCTION public.admin_reactivate_card(p_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;
```

`admin_create_card()` deriva `v_game_id` via `card_set → expansion → game_id` e valida que `rarity_id`/`category_id` pertencem a esse mesmo Game **antes** de chamar `internal.write_card('CREATE', ...)` — erro administrativo claro (`ADMIN_CREATE_CARD_RARITY_MISMATCH`/`ADMIN_CREATE_CARD_CATEGORY_MISMATCH`), em vez de depender só do trigger `trg_card_validate_game_consistency` (Query `141`), que dispara com mensagem genérica. Duplicidade de `collector_number` e `collector_order` verificada contra **todas** as Cards do Card Set, ativas e inativas (`ADMIN_CREATE_CARD_DUPLICATE_COLLECTOR_NUMBER`/`ADMIN_CREATE_CARD_DUPLICATE_COLLECTOR_ORDER`) — mesma regra já registrada em `ADR-023` para a chave natural de Card. Grava `CARD_CREATED` exatamente uma vez, depois que `internal.write_card()` retorna com sucesso — `internal.write_card()` nunca grava auditoria própria (Query `2030`), então a responsabilidade é inteiramente desta função.

`admin_deactivate_card()`/`admin_reactivate_card()` são espelhos exatos entre si: `UPDATE` direto de `is_active` em `public.card` (não usam `internal.write_card()` — `is_active` está fora do escopo daquela camada por decisão explícita, mesmo padrão de `admin_set_card_set_logo()`), erro claro se a Card já estiver no estado-alvo (`ADMIN_DEACTIVATE_CARD_ALREADY_INACTIVE`/`ADMIN_REACTIVATE_CARD_ALREADY_ACTIVE` — evita um `UPDATE` sem efeito e uma linha de auditoria sem sentido), `GET DIAGNOSTICS ... ROW_COUNT` confirmando o efeito real, e gravação de `CARD_DEACTIVATED`/`CARD_REACTIVATED`. Nenhuma das duas toca `card_variant`/`card_asset`/`card_external_reference` — sem cascata, histórico preservado por completo.

**Descoberta real durante a validação de `2115`**: `CREATE FUNCTION` concede `EXECUTE` a `PUBLIC` por padrão em PostgreSQL — `GRANT EXECUTE ... TO authenticated` sozinho **não revoga** essa concessão implícita, e `anon` herda `EXECUTE` por ser membro de `PUBLIC`. A primeira validação de `admin_create_card()` mostrou `anon_pode = true` (deveria ser `false`); corrigido com `REVOKE ALL ON FUNCTION ... FROM PUBLIC;`/`REVOKE ALL ON FUNCTION ... FROM anon;` explícitos após o `GRANT`, aplicado retroativamente à própria função e, desde o início, às duas seguintes (ambas validadas corretas já na primeira execução). O mesmo gap provavelmente existe nas demais funções `admin_*` do módulo, criadas antes desta rodada, nenhuma com `REVOKE` explícito — Fabrício optou explicitamente por tratar essa auditoria retroativa como um item futuro separado, não como parte deste subciclo.

Validado estruturalmente (`prosecdef`/`proconfig`/`has_function_privilege` para as três funções) **e funcionalmente, com execução real contra o banco**: 15 cenários dentro de uma fixture `ZZTEST` isolada (`BEGIN`/`DO $...$`/`ROLLBACK`) — criação válida; duplicidade de `collector_number`; duplicidade de `collector_order`; Raridade de outro Game bloqueada; Categoria de outro Game bloqueada; preservação de `card_variant` através de desativação e reativação; desativação válida + auditoria única; desativar já inativa bloqueado; filtro `is_active = true` ocultando a Card desativada; reativação válida + auditoria única; reativar já ativa bloqueado; filtro voltando a mostrar a Card reativada; total de linhas de auditoria para a mesma Card = exatamente 3 (uma por operação, sem duplicação). Arquivos em `database/schema/2115_create_admin_create_card_function.sql`, `2116_create_admin_deactivate_card_function.sql`, `2117_create_admin_reactivate_card_function.sql`; validação em `database/validations/2817_validate_card_create_deactivate_reactivate.sql`.

**Frontend**: `getCartasCompletas()` (`web/lib/catalogo/queries.ts`) ganhou `options.incluirInativas` (default `false`, preserva o comportamento anterior para qualquer chamador futuro) e um campo `isActive` em `CartaCompletaRow`; `page.tsx` de `/catalogo/cartas` passa `incluirInativas: true` sempre, e `CartasGallery` filtra localmente por padrão (ativas), com um toggle "Mostrar inativas" — opção escolhida por Fabrício entre as apresentadas ("Toggle 'Mostrar inativas' na galeria"). Três novas Server Actions em `web/app/catalogo/cartas/actions.ts` (`createCard`/`deactivateCard`/`reactivateCard`); `NewCardDialog` (`web/components/catalogo/carta-dialogs.tsx`) com `collector_total` pré-preenchido a partir de `totalSetSize` do Card Set (já exposto por `getCardSetsForCartas()`, nenhuma consulta nova) e `collector_order` sugerido como `max(existente, ativas e inativas) + 1` — pura sugestão de UX, validação real permanece no banco. `DeactivateCardDialog` (mesmo arquivo) confirma antes de desativar, com linguagem explícita de que a ação é reversível — diferente de `ConfirmDeleteBar` (exclusão real, irreversível), reutilizado por Game/Expansion/Card Set. Cards ativas mostram Editar + Desativar (`EyeOff`); Cards inativas mostram Editar + Reativar (`Eye`), nunca um substituindo o outro — reativação chama a Server Action direto, sem Dialog de confirmação (ação de baixo risco, o próprio botão já é o "desfazer"). `tsc --noEmit` confirmado limpo.

## Sequência

```text
2000 - Create Internal Schema                              (CONFIRMADO EXECUTADO — database/schema/2000_create_internal_schema.sql)
2010 - Create Catalog Admin Action Log Table                (CONFIRMADO EXECUTADO — database/schema/2010_create_catalog_admin_action_log.sql)
2020 - Add is_active to Card                                (CONFIRMADO EXECUTADO — database/migrations/2020_add_is_active_to_card.sql)
2030 - Create internal.write_card() Function                (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE — database/schema/2030_create_internal_write_card_function.sql)
2800 - Validate Internal Schema                             (EXECUTADA — database/validations/2800_validate_internal_schema.sql)
2801 - Validate Catalog Admin Action Log                    (EXECUTADA — database/validations/2801_validate_catalog_admin_action_log.sql)
2802 - Validate Card is_active                              (EXECUTADA — database/validations/2802_validate_card_is_active.sql)
2803 - Validate internal.write_card()                       (EXECUTADA — database/validations/2803_validate_internal_write_card.sql)
2031 - Create admin_create_game() Function                  (CONFIRMADO EXECUTADO — database/schema/2031_create_admin_create_game_function.sql)
2032 - Create admin_update_game() Function                  (CONFIRMADO EXECUTADO — database/schema/2032_create_admin_update_game_function.sql)
2041 - Add GAME_DELETED to Catalog Admin Action Log          (CONFIRMADO EXECUTADO — database/migrations/2041_add_game_deleted_to_catalog_admin_action_log.sql)
2042 - Create admin_delete_game() Function                  (CONFIRMADO EXECUTADO — database/schema/2042_create_admin_delete_game_function.sql)
2804 - Validate Game Admin Functions                        (EXECUTADA — database/validations/2804_validate_game_admin_functions.sql)
2808 - Validate Game Delete                                 (EXECUTADA — database/validations/2808_validate_game_delete.sql)
2033 - Create admin_create_expansion() Function              (CONFIRMADO EXECUTADO — database/schema/2033_create_admin_create_expansion_function.sql)
2034 - Create admin_update_expansion() Function              (CONFIRMADO EXECUTADO — database/schema/2034_create_admin_update_expansion_function.sql)
2805 - Validate Expansion Admin Functions                    (EXECUTADA — database/validations/2805_validate_expansion_admin_functions.sql)
2043 - Add EXPANSION_DELETED to Catalog Admin Action Log     (CONFIRMADO EXECUTADO — database/migrations/2043_add_expansion_deleted_to_catalog_admin_action_log.sql)
2044 - Create admin_delete_expansion() Function              (CONFIRMADO EXECUTADO — database/schema/2044_create_admin_delete_expansion_function.sql)
2809 - Validate Expansion Delete                             (CONFIRMADO EXECUTADO — database/validations/2809_validate_expansion_delete.sql; validação estrutural via SQL + validação funcional via UI por Fabrício)
2045 - Add Expansion Logo Column                             (CONFIRMADO EXECUTADO — database/schema/2045_add_expansion_logo_column.sql)
2046 - Create admin_set_expansion_logo() Function            (CONFIRMADO EXECUTADO — database/schema/2046_create_admin_set_expansion_logo_function.sql)
2047 - Create Expansion Logo Storage Bucket and Policies     (CONFIRMADO EXECUTADO — database/schema/2047_create_expansion_logo_storage_bucket_and_policies.sql)
2810 - Validate Expansion Logo                               (CONFIRMADO EXECUTADO — database/validations/2810_validate_expansion_logo.sql)
2048 - Create admin_update_card_set() Function               (CONFIRMADO EXECUTADO — database/schema/2048_create_admin_update_card_set_function.sql)
2049 - Add CARD_SET_DELETED to Catalog Admin Action Log      (CONFIRMADO EXECUTADO — database/migrations/2049_add_card_set_deleted_to_catalog_admin_action_log.sql)
2050 - Create admin_delete_card_set() Function               (CONFIRMADO EXECUTADO — database/schema/2050_create_admin_delete_card_set_function.sql)
2811 - Validate Card Set Update and Delete                   (validação estrutural CONFIRMADA EXECUTADA; validação funcional pendente — database/validations/2811_validate_card_set_update_and_delete.sql)
2051 - Create admin_create_card_set() Function                (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE, v1.1 com ENERGY — database/schema/2051_create_admin_create_card_set_function.sql)
2052 - Widen admin_update_card_set() for Type and Release Date (CONFIRMADO EXECUTADO — database/migrations/2052_widen_admin_update_card_set_for_type_and_release_date.sql)
2053 - Add card_asset_type Admin Select Policy                (CONFIRMADO EXECUTADO — database/schema/2053_add_card_asset_type_admin_select_policy.sql)
2812 - Validate admin_create_card_set()                       (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE, três cenários — database/validations/2812_validate_admin_create_card_set.sql)
2091 - Widen admin_update_card_set() for Code                (CONFIRMADO EXECUTADO — database/migrations/2091_widen_admin_update_card_set_function_for_code.sql)
2815 - Validate Card Set Code Editable                        (CONFIRMADO EXECUTADO — database/validations/2815_validate_card_set_code_editable.sql)
2092 - Create admin_start_asset_import_run() Function          (v1.1/v1.2/v1.3 CONFIRMADO EXECUTADO — database/schema/2092_create_admin_start_asset_import_run_function.sql)
2816 - Validate admin_start_asset_import_run()                 (v1.1/v1.2 CONFIRMADO EXECUTADO — database/validations/2816_validate_admin_start_asset_import_run.sql)
2114 - Create admin_update_card() Function                     (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE — database/schema/2114_create_admin_update_card_function.sql)
2115 - Create admin_create_card() Function                     (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE — database/schema/2115_create_admin_create_card_function.sql)
2116 - Create admin_deactivate_card() Function                 (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE — database/schema/2116_create_admin_deactivate_card_function.sql)
2117 - Create admin_reactivate_card() Function                 (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE — database/schema/2117_create_admin_reactivate_card_function.sql)
2817 - Validate Card Create/Deactivate/Reactivate              (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE, 15 cenários — database/validations/2817_validate_card_create_deactivate_reactivate.sql)
```

**Reconciliação de gap (2026-08-01):** as quatro linhas acima (`2051`/`2052`/`2053`/`2812`) já estavam confirmadas executadas por Fabrício desde 2026-07-31 (ver revisões anteriores desta tabela de histórico), mas nunca haviam sido incluídas nesta lista de Sequência — mesmo tipo de gap documental já visto antes neste projeto (ex.: `EXPANSION_DELETED` faltando no arquivo canônico de `catalog_admin_action_log`, corrigido na Query `2049` v1.2). Corrigido aqui, sem re-executar nada — só a lista estava desatualizada.

### Ciclo 1 — Infraestrutura comum de staging e confirmação (ADR-024, Catalog Card Ingestion Strategy)

Primeiro ciclo vertical do fluxo de ingestão de Cards (PDF e TCGdex), aprovado por Fabrício em 2026-08-01 após duas rodadas de revisão do plano técnico (ver `HANDOFF`/ata da conversa — nenhuma migration/função/frontend foi escrita antes da aprovação final). Ordem de ciclos definida por Fabrício: (1) infraestrutura comum — esta seção; (2) fluxo TCGdex completo; (3) prova técnica do processador de PDF; (4) fluxo PDF com o processador aprovado. Nenhum processador (Edge Function TCGdex ou PDF) existe ainda — esta seção só cobre staging, decisão e confirmação, exercitadas nesta fase com dados sintéticos (Query `2814`) até o Ciclo 2 existir.

Decisões definitivas do ajuste final de Fabrício (2026-08-01), incorporadas em todas as Queries abaixo:
1. `progress_step` (`catalog_import_job`) é um enum/índice estável (`TEXT` com `CHECK` fechado de 7 valores) — os textos e ícones de exibição pertencem inteiramente ao frontend.
2. `category_confidence` (`HIGH`/`MEDIUM`/`LOW`) e `category_source` (`API`/`ENERGY_PREFIX`/`POKEMON_MATCH`/`TRAINER_FALLBACK`) vivem dentro de `normalized_data` (JSONB) de `catalog_import_row`, junto com `category` — **não** como colunas físicas próprias. Decisão revista por Fabrício em 2026-08-01 (segunda rodada de aprovação): o desenho de dados do ADR-024 não é alterado nesta etapa; category_source/category_confidence são metadados do mesmo processo de resolução que já produz name/collector_number/rarity_id/category_id dentro do JSONB, não um novo eixo de estado da linha — os quatro estados independentes continuam sendo só validation_status/match_status/decision_status/persistence_status. (Uma primeira versão desta Query havia acrescentado os dois como colunas físicas; revertido antes de qualquer execução.)
3. A regra de classificação de categoria é única para os dois canais: a API TCGdex, quando fornece categoria, só aumenta a confiança do mesmo algoritmo (prefixo "Energia" → `ENERGY`; senão correspondência de nome de espécie Pokémon via TCGdex → `POKEMON`; senão `TRAINER` por eliminação) — nunca o substitui. Implementada nos campos `category_source`/`category_confidence` dentro de `normalized_data`; o algoritmo em si só é escrito em código no processador de cada canal (Ciclos 2/3/4), fora do escopo SQL desta Query.
4. O resumo de análise da tela de Revisão (cartas analisadas/classificadas automaticamente/com alerta/com erro) é derivável diretamente dos contadores já recalculados por agregação em `catalog_import_job` — nenhuma coluna nova foi necessária para viabilizá-lo.

Descoberta durante a implementação: `card_set`/`card` não possuem nenhuma coluna de idioma (confirmado em `database/schema/120`/`140`) — `catalog_import_job` não guarda `language_id` (diferente do que uma leitura apressada de `card_asset`, que É localizado por idioma, sugeriria). O idioma de publicação já está implícito em qual Card Set foi escolhido no dropdown.

`admin_start_catalog_import()`/`admin_decide_catalog_import_row()`/`admin_confirm_catalog_import()` são três funções distintas (não uma só) porque cobrem três momentos do fluxo com autorizações e granularidades diferentes: abrir (uma vez, gera auditoria), decidir (muitas vezes por job, reversível, sem auditoria própria — a decisão já fica registrada na própria linha) e confirmar (persiste de fato, sempre em lote, sempre auditada). `admin_confirm_catalog_import()` chama `internal.write_card()` diretamente — mesma camada canônica usada por `admin_update_card()` (Query `2114`, ver seção própria) e, no futuro, `admin_create_card()` (ainda não escrita), nunca duplicando a lógica de proteção de campos.

```sql
CREATE OR REPLACE FUNCTION public.admin_start_catalog_import(
    p_card_set_id UUID, p_source TEXT, p_file_checksum TEXT DEFAULT NULL, p_external_set_id TEXT DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;

CREATE OR REPLACE FUNCTION public.admin_decide_catalog_import_row(
    p_row_ids UUID[], p_decision_status TEXT, p_corrected_normalized_data JSONB DEFAULT NULL
)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;

CREATE OR REPLACE FUNCTION public.admin_confirm_catalog_import(
    p_job_id UUID, p_row_ids UUID[] DEFAULT NULL
)
RETURNS TABLE (inserted_count INTEGER, updated_count INTEGER, unchanged_count INTEGER, failed_count INTEGER, pending_count INTEGER, job_status TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;
```

## Sequência — Ciclo 1 (ADR-024)

```text
2054 - Widen Catalog Admin Action Log for Catalog Import      (CONFIRMADO EXECUTADO, com gap — ver 2055 — database/migrations/2054_widen_catalog_admin_action_log_for_catalog_import.sql)
2055 - Add CATALOG_IMPORT_JOB Entity Type to Action Log       (CONFIRMADO EXECUTADO — corrige gap da 2054 — database/migrations/2055_add_catalog_import_job_entity_type_to_action_log.sql)
2060 - Create Catalog Import Job Table                        (CONFIRMADO EXECUTADO — database/schema/2060_create_catalog_import_job.sql)
2061 - Catalog Import Job Triggers                            (CONFIRMADO EXECUTADO — database/schema/2061_catalog_import_job_triggers.sql)
2070 - Create Catalog Import Row Table                        (CONFIRMADO EXECUTADO — database/schema/2070_create_catalog_import_row.sql)
2071 - Catalog Import Row Triggers                            (CONFIRMADO EXECUTADO — database/schema/2071_catalog_import_row_triggers.sql)
2080 - Create admin_start_catalog_import() Function            (CONFIRMADO EXECUTADO — database/schema/2080_create_admin_start_catalog_import_function.sql)
2081 - Create admin_decide_catalog_import_row() Function       (CONFIRMADO EXECUTADO — database/schema/2081_create_admin_decide_catalog_import_row_function.sql)
2082 - Create admin_confirm_catalog_import() Function          (CONFIRMADO EXECUTADO — v1.1 corrige bug real de status final, ver seção "Validação — Query 2818" abaixo — database/schema/2082_create_admin_confirm_catalog_import_function.sql)
2813 - Validate Catalog Import Staging Tables                 (CONFIRMADO EXECUTADO — validação estrutural conferida nos 9 resultados, database/validations/2813_validate_catalog_import_staging_tables.sql)
2814 - Validate Catalog Import Functions                      (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE — database/validations/2814_validate_catalog_import_functions.sql)
```

**Ciclo 1 concluído e validado (2026-08-01)** — as 11 Queries acima (as 10 originais mais a `2055`, gap descoberto durante a validação funcional) foram executadas uma a uma por Fabrício no Supabase, seguindo o ritual já estabelecido do projeto, cada uma confirmada antes da próxima. Validação estrutural (`2813`) conferida nos 9 resultados retornados. Validação funcional (`2814`, bloco 4) rodou o caminho completo com dados sintéticos (prefixo `ZZTEST`, `ROLLBACK` ao final, nenhum resíduo): abertura de job, bloqueio de fingerprint duplicado, decisão de linhas (aprovar/pular), confirmação com os três desfechos de persistência (`INSERTED`/`UPDATED`/`UNCHANGED`) — incluindo o cenário de conflito já revisado sendo sobrescrito corretamente —, bloqueio de reconfirmação de job já `COMPLETED`, e a auditoria agregada (`CATALOG_IMPORT_JOB`/`CATALOG_IMPORT_CONFIRMED`) gravada nos dois pontos certos. Dois problemas reais encontrados e corrigidos durante a própria execução (não hipotéticos, descobertos ao rodar contra o banco real):
- **Gap na Query 2054** (Query `2055`): `catalog_admin_action_log` tem três constraints de validação, não duas — `ck_catalog_admin_action_log_entity_type_valid` foi esquecida na ampliação original, bloqueando a primeira chamada real de `admin_start_catalog_import()`. Corrigido com uma migration isolada e reconciliado no arquivo canônico da Query `2010` (v1.3).
- **`is_admin()` inalcançável no SQL Editor**: mesma limitação já registrada na Query `1860` (`auth.uid()` não resolve fora de uma sessão JWT real) — mas, diferente de todos os ciclos anteriores, este Ciclo 1 não tem nenhuma tela para validar por lá ainda. Contornado simulando a sessão do primeiro administrador real via `set_config('request.jwt.claim(s)...', true)`, escopo local à transação de teste.

**Atualização real (2026-08-02, auditoria de reconciliação documental)**: a autorização explícita citada acima foi concedida por Fabrício e o Ciclo 2 (fluxo TCGdex completo) avançou — Edge Function `import-catalog-cards`, telas `/catalogo/importar-cartas`/`/catalogo/importar-imagens`, revisão interativa e confirmação em lote implementadas e em uso ativo em produção (múltiplos Card Sets já importados). Diferente do Ciclo 1, o Ciclo 2 não recebeu o mesmo fechamento formal (checklist de validação funcional equivalente à `2814`) — pendência real, registrada no handoff vigente (`docs/development/`), não neste documento como uma nova seção estruturada (fora do escopo desta rodada de correção, que é apenas pontual, não uma reestruturação). O detalhe de implementação do Ciclo 2 estava espalhado pelas revisões `1.1`–`1.50` da tabela de Revision History de `05-modelo-de-dados.md` (antes da divisão de 2026-08-06), não numa seção dedicada — gap de organização documental sinalizado nesta auditoria, fechado pela seção seguinte.

### Ciclo 2 — Fluxo vertical completo via TCGdex (ADR-024, fechamento formal, 2026-08-07)

Consolida numa seção própria o que estava disperso desde 2026-08-01. Diferente do Ciclo 1 (que só teve dados sintéticos até este ponto), o Ciclo 2 já processou múltiplos Card Sets reais em produção (`SV1`–`SV5`, `SV3.5`, `SVE`, `SVP`, `ME5`, entre outros) — a "validação final" correspondente (Query `2818`, ver abaixo) é read-only sobre dado real, não uma transação sintética com `ROLLBACK`.

**Processador — Edge Function `import-catalog-cards`** (sem Query SQL própria — respeita o contrato `fonte → processador → linhas de staging` de `ADR-024`: nunca grava em tabela canônica, só em `catalog_import_row`, sob identidade `service_role`). Fluxo real, `index.ts`: recebe `{ job_id }`; localiza o job (exige `source = TCGDEX`, `status = RECEIVED`, `external_set_id` já resolvido pelo frontend antes da chamada); transiciona para `PROCESSING`; busca `card_set`+`game_id`+`asset_source` (TCGDEX); busca o Set completo na TCGdex em `pt`, com fallback automático para `en` em dois casos (HTTP 404, ou `cardCount` > 0 com lista de cartas vazia — ver ADR-024, emenda 2026-08-05); busca detalhe de cada carta em lotes de 10 (falha isolada de uma carta vira linha `NEEDS_REVIEW`, nunca derruba o job inteiro); resolve cada linha (`validation_status`/`match_status`/`decision_status`/dados normalizados) via o módulo compartilhado `_shared/catalog-normalization/` (ver abaixo); insere todas as linhas em `catalog_import_row`; faz `upsert` idempotente em `card_set_external_reference`; finaliza o job como `STAGED`. Qualquer erro depois que o job já começou fecha o job como `FAILED` explicitamente — nunca fica preso em `PROCESSING`.

**Módulo compartilhado `_shared/catalog-normalization/`** — extraído de dentro de `import-catalog-cards` em 2026-08-06 (emenda "Raridade: mapeamento self-service e revalidação", ver seção própria abaixo) para ser reutilizável também por `revalidate-catalog-import-rows`. `resolveRarity()` consulta `rarity_external_mapping` (Query `2096`) em vez do antigo mapa hardcoded; `resolveCategory()` aplica a mesma regra de classificação por prefixo/heurística descrita em `ADR-024` (Decisão 3 do Ciclo 1); `normalizeExternalCatalogValue()` espelha em TypeScript, byte a byte, `public.normalize_external_catalog_value()` (Query `2095`) — as duas implementações precisam concordar, já que uma normaliza no Postgres (cadastro self-service) e a outra no Deno (processador). **Correção real (2026-08-07, v1.1)**: `listRarityExternalMappingsByGameAndSource()` (`services/database.ts`) falhava com `RARITY_EXTERNAL_MAPPING_QUERY_FAILED` em Coleções como `GYM1`/`SWSH1` — causa raiz era um `select` do PostgREST com relacionamento embutido malformado; corrigido para duas consultas simples com junção em memória.

**Frontend**: `/catalogo/importar-cartas` (`ImportarCartasView`) — combobox de Coleção, `MatchResultPanel` (localização automática do Set na TCGdex, com busca manual como alternativa), hook central `useAnalyzeJob` (abre o job, faz polling, decide linhas, confirma, encadeia a continuação automática de imagens), `ImportProgress` (barra de progresso com trace por etapa), `RevisaoImportacaoTable` (decisão linha a linha antes da confirmação). Server Actions em `tcgdex/actions.ts`: `iniciarImportacaoTcgdex` (`admin_start_catalog_import`, Query `2080`, mais a chamada síncrona à Edge Function), `decidirLinhasImportacao` (`admin_decide_catalog_import_row`, Query `2081`), `confirmarImportacao` (`admin_confirm_catalog_import`, Query `2082`, em lotes de 50 — recomendação operacional do próprio ADR-024 sobre pontos de commit intermediários). As rotas antigas `tcgdex/page.tsx`/`tcgdex/[jobId]/page.tsx` viraram redirects puros para `/catalogo/importar-cartas` (2026-08-01) — navegação por URL de job destruía o estado de progresso visível, corrigido movendo o fluxo inteiro para estado client-side.

**Emenda — continuação automática cartas → imagens** (`admin_start_asset_import_run()`, Query `2092`, ver ADR-024 "Emenda 2026-08-01"): abre uma `asset_import_run` administrada (sem SQL avulso por Coleção) depois que `admin_confirm_catalog_import()` persiste as Cards. Três correções reais em produção, todas incorporadas à versão canônica: **v1.1** — `run_code` ambíguo em PL/pgSQL (variável implícita de `RETURNS TABLE` colidindo com a coluna) impedia qualquer `INSERT` de completar; **v1.2** — Coleções grandes (SV4, 266 cartas) esgotavam o tempo de execução da Edge Function `import-card-assets` antes de `finishImportRun()` rodar, deixando a run presa em `RUNNING` para sempre e bloqueando novas tentativas — corrigido fechando automaticamente runs `PENDING`/`RUNNING` mais velhas que 15 minutos como `FAILED` antes de abrir uma nova; **v1.3** (Migration `2093`) — parametrizou o idioma (`p_language_code`, default `en`), suportando EN+PT-BR simultâneos, e passou a escopar a checagem de "run já ativa" por idioma. Tela `/catalogo/importar-imagens` (`ImportarImagensView`) criada em 2026-08-02 para retomar manualmente Coleções que somem do seletor de "Importar Cartas" assim que já têm alguma carta.

**Divergência de documentação encontrada nesta auditoria, confirmada e corrigida (2026-08-07)**: o cabeçalho de `database/schema/2092_create_admin_start_asset_import_run_function.sql` (v1.3) dizia `Status: PROPOSTA — AGUARDANDO EXECUÇÃO`, mas a Revision History de `05-modelo-de-dados.md` (revisões `1.31`/`1.33`/`1.36`, anteriores à divisão de 2026-08-06) registrava v1.0/v1.1/v1.2 como confirmadas executadas em produção, e o seletor de idioma EN/PT-BR já em uso na tela `/catalogo/importar-imagens` só funcionaria se a assinatura de 4 parâmetros da v1.3 já estivesse instalada. A Query `2818` (item 1) confirmou diretamente contra o banco: `admin_start_asset_import_run(p_card_set_id uuid, p_run_type text, p_initiated_by text, p_language_code text)` — assinatura de 4 parâmetros, `tem_parametro_idioma_v1_3 = true`. Cabeçalho do arquivo canônico corrigido para `CONFIRMADO EXECUTADO` — gap puramente documental, nunca afetou produção.

## Sequência — Ciclo 2 (ADR-024)

```text
2090 - Grant Service Role Read Access for Catalog Import Processor (CONFIRMADO EXECUTADO — database/migrations/2090_grant_service_role_read_access_for_catalog_import_processor.sql)
2092 - Create admin_start_asset_import_run() Function          (v1.0–v1.3 CONFIRMADO EXECUTADO — v1.3 confirmada via Query 2818 item 1, 2026-08-07 — database/schema/2092_create_admin_start_asset_import_run_function.sql)
2093 - Reconcile admin_start_asset_import_run() Signature      (histórica, incorpora v1.3 à versão canônica — database/migrations/2093_reconcile_admin_start_asset_import_run_signature.sql)
2818 - Validate Catalog Import Cycle 2 Production State        (CONFIRMADO EXECUTADO E VALIDADO — 8 de 8 itens confirmados, item 4 investigado e corrigido — ver seção "Validação — Query 2818" abaixo — database/validations/2818_validate_catalog_import_cycle2_production_state.sql)
2118 - Repair catalog_import_job Status for Pending Decisions  (CONFIRMADO EXECUTADO, 2026-08-07 — reparo retroativo dos 2 jobs afetados pelo bug da Query 2082 v1.0, ver abaixo — database/migrations/2118_repair_catalog_import_job_status_for_pending_decisions.sql)
```

Nenhuma Query SQL nova foi necessária para o processador TCGdex em si (`import-catalog-cards`) além dos GRANTs de `service_role` (`2090`) — o contrato de `ADR-024` já previa isso: o processador só escreve em `catalog_import_row`/`card_set_external_reference`, reaproveitando inteiramente `admin_start_catalog_import()`/`admin_decide_catalog_import_row()`/`admin_confirm_catalog_import()` do Ciclo 1 (Queries `2080`–`2082`). `2092`/`2093` pertencem à emenda "continuação automática cartas → imagens", não ao processador TCGdex propriamente dito, mas estão listadas aqui por fazerem parte do mesmo ciclo de trabalho (2026-08-01/02).

## Validação — Query `2818` (CONFIRMADO EXECUTADO E VALIDADO — 8 de 8 itens confirmados por Fabrício, item 4 investigado e corrigido, 2026-08-07)

Diferente da validação do Ciclo 1 (`2814`, dados sintéticos `ZZTEST` numa transação com `ROLLBACK`), esta é somente leitura: audita a integridade do que já está persistido em produção, em vez de exercitar um cenário novo. Oito verificações — assinatura real de `admin_start_asset_import_run()`, distribuição de `catalog_import_job` por status (só `TCGDEX`), ausência de jobs presos em `CONFIRMING`, ausência de linhas `PENDING` dentro de jobs em estado terminal, todo job confirmado com auditoria correspondente em `catalog_admin_action_log`, `card_set_external_reference` ativa para todo Card Set com importação terminal bem-sucedida, contagem cruzada Cards ativas vs. linhas `INSERTED` no staging, e GRANTs de `service_role` (Migration `2090`) ainda em vigor. Arquivo em `database/validations/2818_validate_catalog_import_cycle2_production_state.sql`.

**Resultado dos itens já rodados**:
- **Item 1 (assinatura real)**: `tem_parametro_idioma_v1_3 = true` — confirma a Query `2092` v1.3 em produção, resolve a divergência do cabeçalho (corrigida acima).
- **Item 2 (distribuição por status, só TCGDEX)**: `COMPLETED = 38`, `FAILED = 6`, `STAGED = 1` — nenhum job em `CONFIRMING` presente na distribuição, o que já é evidência forte (ainda que indireta) de que o item 3 também está limpo.
- **Item 4 (linhas `PENDING` dentro de job terminal) — DEVOLVEU 3 LINHAS, DIVERGÊNCIA REAL, INVESTIGADA E CORRIGIDA (2026-08-07)**: três jobs `COMPLETED` (`3ea4752c-cf6d-4fb9-8228-224f96c11030`, `0a067e94-b665-4d74-b47f-2635d12e22a9`, `bae2f19b-223f-42da-9acd-4283da8fc7b3`) tinham linhas ainda `PENDING` — respectivamente `1`/`1`, `9`/`9` (decisão/persistência) e `0`/`270` (persistência). Causa raiz confirmada por diagnóstico direto (`decision_status`/`persistence_status` por job): os 2 primeiros jobs tinham linhas com `decision_status = 'PENDING'` (nunca decididas por um administrador, tipicamente `CONFLICT` nascida `PENDING` e nunca revisada) — bug real em `admin_confirm_catalog_import()` v1.0, cujo cálculo de status final filtrava a checagem de pendência só dentro de `decision_status IN ('APPROVED', 'SKIPPED')`, tornando invisíveis as linhas nunca decididas e permitindo `COMPLETED` em violação direta da regra de `ADR-024`. O terceiro job (`bae2f19b-...`, 270 linhas) é **falso alarme, comportamento correto por desenho**: `decision_status = 'REJECTED'` em todas — linha rejeitada nunca entra no laço de gravação, então `persistence_status` nunca sai de `PENDING`; não deveria bloquear (e não bloqueia) a conclusão do job. Corrigido com **Query `2082` v1.1** (contagem própria de `decision_status = 'PENDING'`, sem o filtro que escondia o problema — se houver qualquer linha assim, o job volta para `STAGED` em vez de `COMPLETED`) e **Migration `2118`** (reparo retroativo dos 2 jobs reais afetados, devolvidos a `STAGED` — confirmado via query de validação: os 2 jobs com `status = 'STAGED'` e as mesmas contagens de linha pendente, `9` e `1`). Ambas confirmadas executadas em produção por Fabrício em 2026-08-07.
- **Item 7 (contagem cruzada)**: `cards_ativas_hoje = 5677`, `linhas_inseridas_via_staging = 3932` — `3932 ≤ 5677`, dentro do esperado (staging nunca supera o total real; a diferença cabe a cadastro manual e outras fontes).
- **Item 8 (GRANTs de `service_role`)**: `SELECT` presente nas seis tabelas, `INSERT`/`UPDATE` presentes em `catalog_import_job`/`catalog_import_row` — sem regressão de `GRANT`.
- **Item 3 (jobs presos em `CONFIRMING`)**: 0 linhas — confirma por leitura direta o que o item 2 já indicava indiretamente. A semântica transacional de `admin_confirm_catalog_import()` (lock na linha do job) está se comportando como o desenho de `ADR-024` previa.
- **Item 5 (job confirmado sem auditoria correspondente)**: 0 linhas — toda confirmação real de fato gravou `CATALOG_IMPORT_JOB`/`CATALOG_IMPORT_CONFIRMED` em `catalog_admin_action_log`, sem exceção.
- **Item 6 (Card Set com job terminal de sucesso sem `card_set_external_reference` ativa)**: 0 linhas — o `upsert` feito pelo processador (`import-catalog-cards`, passo 11 do fluxo) está funcionando para todos os Card Sets já importados, viabilizando a continuação automática de imagens em todos eles.

**Query `2818` fechada — 8 de 8 itens confirmados (2026-08-07).** Único achado real foi o item 4 (bug de `admin_confirm_catalog_import()` v1.0, corrigido pela Query `2082` v1.1 + Migration `2118`, ver acima) — os demais sete itens confirmaram a integridade esperada do Ciclo 2 sem nenhuma outra divergência. Ciclo 2 de `ADR-024` agora formalmente validado de ponta a ponta, no mesmo padrão de rigor já dado ao Ciclo 1 (`2814`).

**Fechamento dos 2 jobs reabertos (`0a067e94-...`/`3ea4752c-...`), 2026-08-07**: investigação adicional, motivada por Fabrício ter percebido que as Coleções envolvidas (SV2, SV5) já não apareciam no seletor de `/catalogo/importar-cartas` mesmo com os 2 jobs em `STAGED`. Causa: `getLatestImportJobIncompleteFlags()` (`web/lib/catalogo/queries.ts`) só considera o job **mais recente** de cada Card Set (`created_at desc`) para decidir se a Coleção está "incompleta" — não qualquer job com linha pendente. Query de diagnóstico confirmou: para os dois Card Sets, existe um job **ainda mais recente** que os dois reabertos, `COMPLETED` com 100% das linhas processadas (SV2: job `8f4d6308-...`, `279/279`; SV5: job `0c238507-...`, `218/218`) — ou seja, uma reimportação completa e bem-sucedida rodou **depois** dos 2 jobs com bug e já resolveu o Card Set inteiro. As 10 linhas `decision_status = PENDING` de `0a067e94-...`/`3ea4752c-...` quase certamente correspondem a Cards já cadastradas corretamente por essa reimportação posterior — confirmado visualmente por Fabrício na galeria (`/catalogo/cartas`) para várias delas. **Decisão de Fabrício**: deixar os 2 jobs como estão (`STAGED`, com as 10 linhas `PENDING`) — são apenas histórico de tentativas antigas e obsoletas, sem efeito no catálogo real (que já está correto via os jobs mais recentes); nenhuma ação adicional de código ou dado necessária. Não altera a conclusão de que a Query `2082` v1.1 corrige um bug real — apenas esclarece que, neste caso específico, os dois jobs afetados já não têm consequência prática pendente.

## Ciclo vertical — `Game` (Queries `2031`/`2032`, CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE)

Primeiro ciclo vertical implementado (Backend → Tela → Validação), por decisão de Fabrício. Sem camada `internal` própria — diferente de Card, `Game` não converge múltiplos canais de entrada nem tem campos protegidos por regra complexa; o `INSERT`/`UPDATE` acontece diretamente na função pública, mesmo padrão de `admin_set_card_set_logo()` (`ADR-022`).

```sql
CREATE OR REPLACE FUNCTION public.admin_create_game(p_code TEXT, p_name TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;

CREATE OR REPLACE FUNCTION public.admin_update_game(p_id UUID, p_name TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;
```

`code` imutável na edição **por construção**: `admin_update_game()` nem tem parâmetro para isso — não é uma checagem em tempo de execução (como o `RAISE EXCEPTION` de campo protegido em `internal.write_card()`), é a ausência do próprio parâmetro na assinatura. `admin_create_game()` normaliza `code` para maiúsculas (`upper(btrim(...))`) antes de validar formato (`^[A-Z][A-Z0-9_]*$`) e duplicidade — duplicidade verificada explicitamente antes do `INSERT`, com mensagem clara (`ADMIN_CREATE_GAME_DUPLICATE_CODE`), antecipando o erro bruto de `uq_game_code`. Ambas gravam em `catalog_admin_action_log` (`GAME_CREATED`/`GAME_UPDATED`) em caso de sucesso.

Validado estruturalmente e **funcionalmente, com execução real contra o banco**: 8 cenários (criação bem-sucedida com normalização de `code`; duplicidade; formato inválido; nome vazio na criação; atualização bem-sucedida; id inexistente; nome vazio na atualização; chamada sem sessão administrativa), todos simulando a sessão do administrador real via `set_config('request.jwt.claim.sub', ...)`, dentro de uma transação com `RAISE EXCEPTION` forçado ao final — `ROLLBACK` total confirmado, incluindo as duas linhas de auditoria geradas pelos cenários de sucesso. Arquivos em `database/schema/2031_create_admin_create_game_function.sql` e `database/schema/2032_create_admin_update_game_function.sql`; validação em `database/validations/2804_validate_game_admin_functions.sql`.

**Frontend (`/catalogo/jogos`, IMPLEMENTADO — validação pela interface pendente)**: `JogosTable` (`web/components/catalogo/jogos-table.tsx`) substitui a tabela estática por um componente client com cadastro (formulário inline acima da tabela) e edição (linha da tabela substituída por um formulário inline, `code` sempre desabilitado). Duas Server Actions em `web/app/catalogo/jogos/actions.ts` (`createGame`/`updateGame`) chamam os RPCs via `supabase.rpc(...)`, traduzem erros com o novo `traduzirErroCatalogo()` (`web/lib/supabase/catalogo-errors.ts` — extrai o texto após o prefixo `CODIGO_MAIUSCULO: `, reutilizável pelas funções futuras de Expansion/Card Set/Card, diferente de `traduzirErroAdmin()` de ADR-021, que faz match exato de frase) e chamam `revalidatePath("/catalogo/jogos")`; o componente força `router.refresh()` após sucesso para repassar dados atualizados do Server Component. `tsc --noEmit` confirmado limpo para todo o código novo (dois erros pré-existentes em `lib/supabase/middleware.ts`/`server.ts`, não tocados nesta revisão, não fazem parte deste incremento).

**Confirmado por Fabrício via interface real** (2026-07-26): listagem e cadastro testados na própria tela (`/catalogo/jogos` exibindo os Jogos reais cadastrados). Dois ajustes visuais pedidos e aplicados: botão "Cadastrar novo jogo" reposicionado para fora do card da tabela (linha do título, alinhado à direita), com borda na cor primária (`outline-primary`, nova variante de `Button`, reutilizável pelos próximos ciclos), ícone `Plus` e altura compacta (`sm`); ação "Editar" na tabela trocada de botão de texto para ícone (`Pencil`, nova variante `icon-sm`).

## Emenda — `Game`: exclusão real via UI (Queries `2041`/`2042`, CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE)

Durante a validação do ciclo de `Game`, Fabrício pediu exclusão de itens pela própria tela. `ADR-023` originalmente previa para `Game`/`Expansion`/`Card Set` apenas "create/update nesta fase, sem desativação por UI", com correção rara resolvida "por SQL direta" — como isto contradizia uma decisão já formalizada e encerrada, a exclusão foi tratada como uma emenda explícita ao ADR (não uma implementação silenciosa), aprovada por Fabrício antes de qualquer Query. Ver `ADR-023`, seção "Emenda (2026-07-26) — `Game`: exclusão real via UI".

```sql
-- 2041: adiciona GAME_DELETED às constraints de catalog_admin_action_log
ALTER TABLE public.catalog_admin_action_log DROP CONSTRAINT ck_catalog_admin_action_log_action_valid;
ALTER TABLE public.catalog_admin_action_log ADD CONSTRAINT ck_catalog_admin_action_log_action_valid
    CHECK (action IN (..., 'GAME_DELETED', ...));
-- (mesma alteração em ck_catalog_admin_action_log_action_entity_match)

-- 2042: admin_delete_game()
CREATE OR REPLACE FUNCTION public.admin_delete_game(p_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;
```

Exclusão real (`DELETE`), não desativação — `Game` continua sem `is_active`. `code`/`name` são capturados por `SELECT` antes do `DELETE` (para a auditoria, já que depois não há mais registro a consultar). A `FK fk_expansion_game` (`ON DELETE RESTRICT`, Query `110`) já impedia a exclusão de um Game com Expansions — a função antecipa esse erro bruto com `ADMIN_DELETE_GAME_HAS_DEPENDENTS`. Toda exclusão bem-sucedida grava `GAME_DELETED` em `catalog_admin_action_log`. Restrita a `Game` — `Expansion`/`Card Set` não recebem `admin_delete_*` por esta emenda.

Validado com **4 cenários reais** (exclusão de um Game de teste sem Expansions — sucesso, auditoria confirmada; tentativa de excluir `POKEMON` — bloqueada por ter Expansion associada, `POKEMON` preservado; id inexistente; sem sessão administrativa), dentro de uma transação com `ROLLBACK` forçado — 0 Jogos/linhas de auditoria residuais, total real de Jogos inalterado. `database/schema/2010_create_catalog_admin_action_log.sql` atualizado para v1.1 (Princípio da Fonte Canônica). Arquivos em `database/migrations/2041_add_game_deleted_to_catalog_admin_action_log.sql` e `database/schema/2042_create_admin_delete_game_function.sql`; validação em `database/validations/2808_validate_game_delete.sql`.

**Frontend**: `JogosTable` ganhou checkbox por linha (+ "selecionar todos" no cabeçalho), uma barra de seleção ("N selecionados" + "Excluir selecionados") e uma confirmação inline antes de excluir (lista os Jogos afetados, aviso de ação irreversível). Nova Server Action `deleteGames` (`web/app/catalogo/jogos/actions.ts`) chama `admin_delete_game()` uma vez por id selecionado — sem função de exclusão em lote no banco, dado o volume — e reporta falhas por item individualmente (ex.: um Jogo bloqueado por ter Expansions não impede a exclusão dos demais selecionados); em caso de falha parcial, a tabela é atualizada para refletir os itens já excluídos, mas a barra de confirmação permanece aberta mostrando o motivo da falha nos itens restantes. `tsc --noEmit` confirmado limpo.

**Pendência explícita**: teste da exclusão pela própria interface ainda não confirmado por Fabrício (o teste de interface já feito nesta revisão cobriu listagem/cadastro, antes desta emenda existir).

## Colunas de auditoria na tela (`created_at`/`updated_at`)

Pedido de Fabrício para fechar o módulo: exibir data de criação e de última atualização na tabela de Jogos — explicitamente **não** no formato numérico `DD/MM/AAAA`. Novo helper `formatarData()` (`web/lib/format-date.ts`, reutilizável pelos ciclos seguintes) formata como `"26 jul 2026"`. `getJogos()` (`web/lib/catalogo/queries.ts`) passou a selecionar `created_at`/`updated_at`; `JogoRow` ganhou `createdAt`/`updatedAt`. `tsc --noEmit` confirmado limpo.

## Fechamento do ciclo de Game — refino e extração para reuso (2026-07-26)

Fabrício aprovou formalmente o ciclo de Game ("implementação consistente com a arquitetura definida, pode ser considerada concluída") e pediu quatro ajustes antes de iniciar `Expansion`, para que a base já sirva aos próximos ciclos sem duplicação:

1. **Exclusão mútua entre edição e seleção em massa.** Entrar em edição limpa a seleção e oculta a barra de ações em massa; checkboxes ficam desabilitados (visualmente esmaecidos) enquanto um formulário de criação/edição está aberto. Centralizado no novo hook `useAdminListState` (`web/hooks/use-admin-list-state.ts`) — `isFormOpen = creating || editingId !== null` é a única fonte de verdade, evitando reimplementar essa regra em cada ciclo.
2. **Componentes extraídos para reuso**: `AdminToolbar` (título + botão de criação), `BulkSelectionBar` (barra "N selecionados"), `ConfirmDeleteBar` (confirmação inline, genérica sobre `DeleteEntitiesActionState`), `SuccessBanner` (aviso de sucesso) — todos em `web/components/catalogo/`. Tipos de retorno das Server Actions centralizados em `web/lib/catalogo/admin-action-types.ts` (`EntityActionState`/`DeleteEntitiesActionState`); `GameActionState`/`DeleteGamesActionState` (em `web/app/catalogo/jogos/actions.ts`) agora são apenas aliases desses tipos compartilhados. O que permanece específico de Game em `jogos-table.tsx`: colunas da tabela, `CreateGameForm`, `EditGameRow` — tudo o que depende dos campos reais da entidade.
3. **Feedback de sucesso**: `useAdminListState.onSuccess(mensagem, id)` mostra um `SuccessBanner` e destaca a linha afetada (`bg-primary/5`, com `transition-colors`) por 3 segundos após criar/editar/excluir.
4. **Contador de Expansões clicável**: o número na coluna "Expansões" agora é um link para `/catalogo/expansoes?game=CODE`. `getExpansoes()` (`web/lib/catalogo/queries.ts`) ganhou um segundo parâmetro opcional `filters.gameCode` (filtra via `game!inner(code)` + `.eq("game.code", ...)`); `ExpansaoRow` ganhou `gameCode`. A tela `/catalogo/expansoes` (ainda somente leitura — cadastro/edição chegam no próprio ciclo de Expansion, a seguir) passou a ler `searchParams.game` e mostra um indicador "Filtrando por Jogo: X — Limpar filtro" quando o filtro está ativo.

`tsc --noEmit` confirmado limpo para todo o código novo/alterado. Escopo deliberadamente contido aos quatro pontos pedidos — nenhuma ordenação, filtro adicional ou exclusão lógica de Game foi introduzida.

## Ciclo vertical — `Expansion` (Queries `2033`/`2034`, CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE)

Segundo ciclo vertical, construído sobre os componentes já extraídos no fechamento de `Game` (`useAdminListState`, `AdminToolbar`, `SuccessBanner`). Nasceu apenas com `create`/`update` — `Expansion` ganhou exclusão real (`admin_delete_expansion()`) numa emenda posterior, ver "Emenda — `Expansion`: exclusão real via UI" mais adiante nesta seção.

```sql
CREATE OR REPLACE FUNCTION public.admin_create_expansion(
    p_game_id UUID, p_code TEXT, p_name TEXT, p_release_order INTEGER
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;

CREATE OR REPLACE FUNCTION public.admin_update_expansion(
    p_id UUID, p_name TEXT, p_release_order INTEGER
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;
```

`game_id` e `code` imutáveis na edição por construção — `admin_update_expansion()` nem tem parâmetro para nenhum dos dois, mesmo princípio já aplicado a `code` em `Game` (Query `2032`). `admin_create_expansion()` verifica explicitamente a existência do `game_id` informado antes do `INSERT`, antecipando o erro bruto de `fk_expansion_game` (`ADMIN_CREATE_EXPANSION_GAME_NOT_FOUND`); `code` é normalizado para maiúsculas e validado por formato e duplicidade dentro do mesmo Game (`uq_expansion_game_code` é por `game_id`+`code`, não global — duas Expansions de Games diferentes podem compartilhar `code`). `release_order` deve ser um inteiro positivo e único dentro do mesmo Game (`uq_expansion_game_release_order`) — duplicidade verificada explicitamente tanto no `CREATE` quanto no `UPDATE` (excluindo a própria linha), antecipando o erro bruto da constraint. Ambas gravam em `catalog_admin_action_log` (`EXPANSION_CREATED`/`EXPANSION_UPDATED`) em caso de sucesso.

Validado estruturalmente e **funcionalmente, com execução real contra o banco**: 11 cenários (criação bem-sucedida com normalização de `code`; duplicidade de `code` no mesmo Game; duplicidade de `release_order` no mesmo Game; `game_id` inexistente; formato de `code` inválido; nome vazio na criação; atualização bem-sucedida; `release_order` colidindo com outra Expansion do mesmo Game na atualização; id inexistente na atualização; nome vazio na atualização; chamada sem sessão administrativa), todos simulando a sessão do administrador real via `set_config('request.jwt.claim.sub', ...)`, dentro de uma transação com `RAISE EXCEPTION` forçado ao final — `ROLLBACK` total confirmado, incluindo as linhas de auditoria geradas pelos cenários de sucesso (2 `EXPANSION_CREATED`, 1 `EXPANSION_UPDATED`), 0 Expansões/linhas de auditoria residuais, total real de Expansões inalterado. Arquivos em `database/schema/2033_create_admin_create_expansion_function.sql` e `database/schema/2034_create_admin_update_expansion_function.sql`; validação em `database/validations/2805_validate_expansion_admin_functions.sql`.

**Frontend (`/catalogo/expansoes`, IMPLEMENTADO — validação pela interface pendente)**: a tela foi redesenhada em 2026-07-31 (`web/components/catalogo/expansoes-gallery.tsx`, galeria de cards no mesmo padrão visual da tela Coleções, substitui a tabela original `ExpansoesTable` — que fica sem uso, mas segue exportando `CreateExpansionDialog`/`EditExpansionDialog`, reaproveitados pela galeria). Cadastro/edição continuam sobre `useAdminListState`/os mesmos Dialogs; seletor de Jogo (`<select>`, populado por `getGameOptions()`) pré-selecionado quando a tela chega filtrada por `?game=CODE`; edição mantém `game_id`/`code` desabilitados (imutáveis). `getExpansoes()`/`ExpansaoRow` ganharam `createdAt`/`updatedAt`/`gameId`; Server Actions em `web/app/catalogo/expansoes/actions.ts` (`createExpansion`/`updateExpansion`, mais `deleteExpansions` — ver emenda de exclusão abaixo). `tsc --noEmit` confirmado limpo para todo o código novo (os dez erros pré-existentes em `lib/supabase/middleware.ts`/`server.ts` não fazem parte deste incremento).

**Pendência explícita**: teste da tela pela própria interface (listar/cadastrar/editar/excluir, inclusive o filtro `?game=`) depende do ambiente de Fabrício — sandbox desta sessão sem acesso a `npm`/CDN.

## Emenda — `Expansion`: exclusão real via UI (Queries `2043`/`2044`/`2809` — CONCLUÍDA, CONFIRMADA EXECUTADA E VALIDADA FUNCIONALMENTE)

Mesmo padrão da emenda de `Game` (Queries `2041`/`2042`), estendido a `Expansion` a pedido de Fabrício — ver ADR-023, emenda 2026-07-31. Ação rápida "excluir" (ícone de lixeira) ao lado de "editar" em cada card da galeria de Expansões, mesmo mecanismo de `useAdminListState.startQuickDelete()`/`ConfirmDeleteBar` já usado em `Game`.

```sql
-- 2043: adiciona EXPANSION_DELETED às constraints de catalog_admin_action_log
ALTER TABLE public.catalog_admin_action_log DROP CONSTRAINT ck_catalog_admin_action_log_action_valid;
ALTER TABLE public.catalog_admin_action_log ADD CONSTRAINT ck_catalog_admin_action_log_action_valid
    CHECK (action IN (..., 'EXPANSION_DELETED', ...));
-- (mesma alteração em ck_catalog_admin_action_log_action_entity_match)

-- 2044: admin_delete_expansion()
CREATE OR REPLACE FUNCTION public.admin_delete_expansion(p_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;
```

`admin_delete_expansion()` segue byte-a-byte o mesmo roteiro de `admin_delete_game()`: exige `is_admin()`, captura `code`/`name` antes do `DELETE`, deixa a `FK fk_card_set_expansion` (`ON DELETE RESTRICT`, Query `120`) bloquear a exclusão quando há Card Sets associados (antecipada como `ADMIN_DELETE_EXPANSION_HAS_DEPENDENTS`), confirma o `DELETE` via `GET DIAGNOSTICS ... ROW_COUNT` e grava `EXPANSION_DELETED` em `catalog_admin_action_log`. Exclusão definitiva, sem "lixeira" nem forma de desfazer pela UI — mesmas garantias de `Game`.

Frontend: `deleteExpansions` (nova Server Action em `web/app/catalogo/expansoes/actions.ts`, mesmo contrato `DeleteEntitiesActionState` de `deleteGames`) chamada uma vez por id via `admin_delete_expansion()`; `ExpansoesGallery` ganhou a mesma `ConfirmDeleteBar` já usada em `JogosTable`.

**Status final**: Query `2043` confirmada executada (validado via `pg_get_constraintdef` — as duas constraints de `catalog_admin_action_log` já incluem `EXPANSION_DELETED`). Query `2044` (`admin_delete_expansion()`) confirmada executada (validado via `has_function_privilege`: `anon` sem `EXECUTE`, `authenticated` com `EXECUTE`). Validação funcional (`2809`) confirmada por Fabrício diretamente pela interface — exclusão bem-sucedida e bloqueio por dependentes testados na tela, "todos funcionando corretamente" (2026-07-31). Emenda encerrada; botão "excluir" da galeria de Expansões está em produção.

## Ajuste — Galeria de Expansões agrupada por Jogo (2026-07-31)

Pedido de Fabrício: "as expansões devem ser exibidas separadamente por cada tipo de Jogo e organizadas pela data de lançamento de forma decrescente." Puramente de apresentação — nenhuma mudança de schema, RPC, RLS ou regra de negócio.

`Expansion` não tem coluna de data de lançamento — só `release_order`, inteiro sequencial único por Jogo (`database/schema/110_create_expansion_table.sql`, `uq_expansion_game_release_order`). "Data de lançamento" foi interpretada como `release_order`, já que é o único campo que expressa ordem cronológica de lançamento ali — maior `release_order` é a Expansão mais recente daquele Jogo, por definição do próprio campo.

Nova função `getExpansoesGroupedByGame()` (`web/lib/catalogo/queries.ts`) substitui `getExpansoesForCatalogo()` no modo galeria (sem busca): agrupa por Jogo, ordena cada grupo por `release_order`, e ordena os próprios grupos alfabeticamente pelo nome do Jogo (mesmo critério de `getGameOptions()`). `ExpansoesGallery` passou a renderizar uma seção por Jogo — nome do Jogo com o mesmo indicador de cor (`getGameAccentColor`) já usado nos cards, seguido do grid daquele grupo.

**Correção de direção (2026-07-31, mesmo dia)**: a primeira versão ordenava `release_order` descendente (literal de "forma decrescente"). Fabrício testou na tela e reportou "a ordem... ficou na ordem inversa" — ajustado para `release_order` **ascendente** (`a.releaseOrder - b.releaseOrder`) a partir desse feedback direto ao vivo, não por reinterpretação teórica do pedido original.

**Ordem dos grupos corrigida (2026-07-31, mesmo dia, terceiro ajuste)**: a primeira versão ordenava os grupos (Jogos) alfabeticamente pelo nome. Fabrício pediu explicitamente o contrário: "primeiro listar todas as expansões do jogo Pokémon e depois Lorcana... Pokémon foi o primeiro game cadastrado" — ordem de cadastro, não alfabética. `game.created_at` passou a ser selecionado junto com a Expansão (só em `fetchExpansoesRawForCatalogo`, não nas demais queries que reaproveitam `ExpansionRawRow`) e os grupos são ordenados por ele, ascendente (Jogo mais antigo primeiro). Deliberadamente diferente do critério de `getGameOptions()` (alfabético, usado só no seletor de Jogo dos formulários de cadastro/edição) — os dois atendem propósitos diferentes e não precisam concordar.

Consequência necessária: o "Carregar mais" flat (paginação de 24 em 24) deixou de existir no modo galeria — carregar tudo de uma vez é a única forma de agrupar corretamente sem paginar grupos individualmente, e o volume atual (1 Jogo, poucas Expansões) não justifica essa complexidade adicional agora. `loadMoreExpansoes` (Server Action) e `getExpansoesForCatalogo()`/`sortExpansoesForCatalogo()` (query) foram removidas por ficarem sem uso. A busca (`mode === "search"`) não foi tocada — continua flat, sem agrupamento, com o "Carregar mais" que já tinha.

`tsc --noEmit` confirmado limpo (mesmos 10 erros pré-existentes de sempre, em `lib/supabase/middleware.ts`/`server.ts`).

## Logo da Expansão (`logo_storage_path`, Queries `2045`/`2046`/`2047`, CONFIRMADO EXECUTADO)

Pedido de Fabrício ("vamos incluir uma imagem para cada expansão"), mesmo dia do ajuste de agrupamento acima. Mesma arquitetura de `card_set.logo_storage_path` (ver seção "Logo do Card Set" mais adiante neste documento; decisão formalizada em `ADR-022`, emenda 2026-07-31) — coluna opcional, escrita só via função `SECURITY DEFINER`, bucket privado, leitura via URL assinada:

```sql
-- 2045: coluna
ALTER TABLE public.expansion ADD COLUMN logo_storage_path TEXT NULL;
ALTER TABLE public.expansion ADD CONSTRAINT ck_expansion_logo_storage_path_not_url
    CHECK (logo_storage_path IS NULL OR logo_storage_path !~* '^[a-z][a-z0-9+.-]*://');

-- 2046: admin_set_expansion_logo(p_expansion_id UUID, p_logo_storage_path TEXT)
-- SECURITY DEFINER, exige is_admin(), única via de escrita.

-- 2047: bucket privado expansion-logo + 4 políticas admin-only em storage.objects
```

Números fora da faixa legada `200`–`299` (onde `card_set.logo_storage_path` foi numerada, `273`/`275`/`276`) porque essa faixa está congelada desde então (`STD-001`, "Esquema Legado — Congelado") — numeradas no milhar `2000`–`2999` em vez disso, mesmo critério já usado na emenda de exclusão de `Expansion`/`Game`. Ver `ADR-022`, nova seção "Emenda", para o registro completo dessa decisão de numeração.

**Diferente de `card_set.logo_storage_path` num ponto importante**: esta é a primeira vez que o fluxo de upload realmente chega à tela — a logo de Card Set tem toda a infraestrutura de banco pronta desde 2026-07-26 (`273`/`275`/`276`), mas o upload nunca foi conectado ao frontend (`card-sets/[code]/page.tsx` marca isso como "incremento futuro"). Para Expansão, o upload foi construído de ponta a ponta nesta mesma rodada:

- `ExpansaoLogoUploader` (`web/components/catalogo/expansao-logo-uploader.tsx`, novo) — adaptado de `AvatarUploader` (`components/perfil/avatar-uploader.tsx`), com duas diferenças impostas pelo bucket ser privado/admin-only: leitura via `createSignedUrl` (não `getPublicUrl`), e a gravação do ponteiro passa pela Server Action `setExpansionLogo()` (que chama `admin_set_expansion_logo()`) em vez de um `.update()` direto do cliente — não existe política de RLS de `UPDATE` em `expansion` para isso.
- Upload disponível só no Dialog de **edição** (`EditExpansionDialog`/`EditExpansionForm`, `expansoes-table.tsx`), não no de criação — a Expansão precisa já existir (ter um `id`) para compor o caminho no bucket e para a função `admin_set_expansion_logo()` ter o que atualizar. Uma Expansão nova é criada sem logo; a logo é adicionada depois, editando.
- `getExpansionLogoUrls()` (`web/lib/catalogo/queries.ts`) gera URLs assinadas em lote (1h de validade), mesmo padrão de `getCardSetLogoUrls()`. Resolvida no Server Component (`expansoes/page.tsx`, para grupos e para a busca inicial) e em `searchExpansoesAction` (`catalogo-actions.ts`, para o "Carregar mais" da busca).
- `ExpansaoGalleryCard` exibe a imagem quando `logoUrl` existe, iniciais como reserva quando não — mesmo comportamento de `CardSetGalleryCard`.
- Novo tipo `ExpansaoWithLogo` (`ExpansaoRow & { logoUrl: string | null }`) — só usado pelas telas de leitura, nunca pela camada de escrita.
- Também é possível remover a logo (`admin_set_expansion_logo(id, NULL)`, já suportado pela função desde a Query `2046`) — botão "Remover" no uploader quando há logo cadastrada.

Todas as três Queries de banco (`2045`/`2046`/`2047`) e a validação (`2810`) confirmadas executadas por Fabrício via o ritual de pareamento (uma de cada vez, resultado conferido antes de avançar). `tsc --noEmit` confirmado limpo.

**Ajuste visual (2026-07-31, mesmo dia, depois de ver as primeiras logos reais na tela)**: a caixa da imagem em `ExpansaoGalleryCard` deixou de ser `aspect-square` — logos de Expansão são wordmarks horizontais (ex.: "Scarlet & Violet"), diferentes do símbolo compacto de Card Set que motivou o quadrado original. Trocada para `aspect-[2/1]`, `object-contain` preservado (nunca corta a imagem), padding reduzido de `p-4` para `p-3`.

## Coleções (`/catalogo/card-sets`) no padrão de Expansões + emenda `Card Set`: atualização e exclusão real via UI (Queries `2048`/`2049`/`2050`/`2811` — CONFIRMADO EXECUTADO)

Pedido de Fabrício (2026-07-31, mesmo dia da logo de Expansão): "faça todos os ajustes necessários para manter o mesmo padrão da página Expansões" na tela Coleções. Sete pontos, todos de apresentação exceto o último:

1. **`CardSetsStats`** (novo, `web/components/catalogo/card-sets-stats.tsx`) — mesmo padrão de `ExpansoesStats`: Jogos/Expansões/Coleções/Sem Cartas (Coleções sem nenhuma Carta catalogada, `tone="danger"`). Sem query nova — reaproveita `getGameOptions()`/`getExpansoes()` (já buscados para o filtro) e `getCardSetsOverview()` (mesma função da tabela de Card Sets da Visão Geral).
2. **Botão "Novo"** sai do `PageHeader` e passa a ficar numa linha própria acima do `Card` que envolve busca/filtro/conteúdo — mesmo lugar de "Nova expansão"/"Novo Jogo". Continua abrindo `NovoCatalogoDialog` (cadastro de Card Set segue fora de escopo — `admin_create_card_set()` não existe).
3. **Busca e filtro** migram para dentro do `Card` (cabeçalho, só `border-b`), tamanho/cor padrão (`h-9`, `bg-surface-muted`, `text-xs`) — deixam de flutuar soltos/`sticky`.
4. **Tamanho da logo**: padding da caixa de imagem reduzido de `p-4` para `p-3` (mesmo valor de `ExpansaoGalleryCard`), uniformizando a "respiração" da arte entre as duas galerias. A altura da caixa passou por duas rodadas de ajuste depois da implementação inicial — ver seção própria "Altura fixa da logo (Expansão e Card Set)" mais adiante, que registra o estado final (`h-28`).
5. **Paginação**: já seguia o mesmo padrão de Expansões ("Carregar mais", sem rolagem infinita) — reconfirmado ao mover o botão para dentro do `Card`, junto do grid.
6. **Botões de edição e exclusão em cada Card Set** — ação rápida (ícones sem borda, lápis/lixeira) no card, mesmo mecanismo de `useAdminListState` + `ConfirmDeleteBar` já usado em Jogos/Expansões. Estrutura do card também migrou para `<Link>` absoluto + botões `relative z-10` sobre ele (mesma técnica de `ExpansaoGalleryCard`, necessária para os ícones não ficarem aninhados dentro do link de navegação para o detalhe).
7. **Outros ajustes de padronização**: `catalogo-gallery.tsx` e `catalogo-content.tsx` (que antes dividiam cabeçalho/busca fixos vs. conteúdo trocável) foram unificados num único componente, espelhando `expansoes-gallery.tsx` (que nunca teve essa divisão) — `catalogo-content.tsx` fica sem uso, marcado no próprio arquivo, não removido. `loading.tsx` da tela também foi atualizado para o mesmo formato de skeleton usado em `expansoes/loading.tsx` (skeletons dos 4 indicadores, botão fora do cabeçalho, busca/filtro/grid dentro do mesmo `Card`).

**O item 6 exigiu escrita nova no banco** — diferente de Expansão (que já tinha `admin_update_expansion()` antes da emenda de exclusão), Card Set não tinha **nenhuma** via administrativa de escrita estrutural além da logo (`admin_set_card_set_logo()`, `ADR-022`). Ver `ADR-023`, nova seção "Emenda (2026-07-31) — `Card Set`: atualização e exclusão real via UI", para o registro completo da decisão.

```sql
-- 2048: admin_update_card_set(p_id UUID, p_name TEXT, p_release_order INTEGER)
-- Mesmo escopo mínimo de admin_update_expansion(): só nome e ordem de
-- lançamento editáveis. expansion_id/code imutáveis por construção;
-- set_type/base_set_size/total_set_size ficam de fora (campos estruturais
-- amarrados a ck_card_set_promo_size). release_order único por Expansion.

-- 2049: adiciona CARD_SET_DELETED às constraints de catalog_admin_action_log
-- (mesma técnica de 2041/2043 — DROP + ADD). Aproveitado para reconciliar
-- um gap: o arquivo canônico 2010 nunca tinha recebido EXPANSION_DELETED,
-- apesar de a migration 2043 já estar confirmada executada contra o banco
-- real desde a emenda de Expansion — corrigido no mesmo commit (2010 bump
-- para v1.2), sem migration própria (valor já existe fisicamente).

-- 2050: admin_delete_card_set(p_id UUID)
-- Mesmo padrão de admin_delete_expansion(): DELETE real, bloqueado pela
-- FK fk_card_card_set (ON DELETE RESTRICT, Query 140) quando há Cards
-- associadas (ADMIN_DELETE_CARD_SET_HAS_DEPENDENTS); grava CARD_SET_DELETED
-- em catalog_admin_action_log com code/name capturados antes do DELETE.
```

Números no milhar `2000`–`2999` (faixa legada `200`–`299` congelada desde `STD-001`), mesmo critério já usado nas emendas de Game/Expansion. Validação em `2811` (`database/validations/2811_validate_card_set_update_and_delete.sql`), mesmo roteiro de `2809`, com um bloco a mais para `admin_update_card_set()`.

**Frontend já com a fiação completa**: `EditCardSetDialog`/`EditCardSetForm` (novo, `web/components/catalogo/card-set-dialogs.tsx`) — cópia fiel do `EditExpansionDialog` já corrigido pelo ciclo de layout daquela tela (campos imutáveis viram `DialogDescription` do cabeçalho — `"{Jogo} · {Expansão} · {Código}"`, um nível a mais que Expansão; `size="lg"`). Duas novas Server Actions em `web/app/catalogo/card-sets/actions.ts` (`updateCardSet`/`deleteCardSets`), mesmo padrão de `expansoes/actions.ts`. `tsc --noEmit` confirmado limpo.

**Queries `2048`/`2049`/`2050` confirmadas executadas por Fabrício (2026-07-31)** via o ritual de pareamento (uma de cada vez, resultado conferido antes de avançar): `2048` e `2050` validadas via `has_function_privilege` (`anon` sem `EXECUTE`, `authenticated` com `EXECUTE`); `2049` validada via `pg_get_constraintdef` (ambas as constraints de `catalog_admin_action_log` incluem `CARD_SET_DELETED`, e também `EXPANSION_DELETED` — confirmando de quebra que o gap do canônico `2010` já estava reconciliado com o banco real). Os botões "editar"/"excluir" da galeria de Coleções estão funcionalmente operantes em produção. Pendência remanescente: validação funcional dos cenários de `2811` pela própria interface.

## Ajuste de contraste — `ConfirmDeleteBar` no tema escuro (2026-07-31)

Pedido de Fabrício, a partir de captura de tela real da galeria de Coleções: "ajustar a cor da tarja vermelha ao selecionar um card set para exclusão no modo escuro". Mesmo problema já diagnosticado e corrigido para o ícone de `tone="danger"` em `StatCard` — `--destructive` no tema escuro é um vermelho muito escuro (20% de luminosidade, `globals.css`), quase invisível sobre o fundo também escuro do app. `ConfirmDeleteBar` (`web/components/catalogo/confirm-delete-bar.tsx`, compartilhado por Jogos/Expansões/Coleções) ganhou `dark:` overrides: borda do container troca para `destructive-foreground` (quase branco no tema escuro) em opacidade baixa, fundo ganha mais opacidade (`/5` → `/20`); mesma troca aplicada aos textos de erro/falha internos. Tema claro inalterado. `tsc --noEmit` confirmado limpo.

## Logo do Card Set conectada ao frontend + "Novo" renomeado para "Nova Coleção" (2026-07-31)

Dois ajustes pedidos por Fabrício depois de testar a tela de Coleções redesenhada:

1. **Botão "Novo" → "Nova Coleção"** — mesma convenção de nome já usada por "Nova expansão"/"Novo Jogo" (identifica a entidade, não um genérico "Novo"). Atualizado em `catalogo-gallery.tsx` (botão + texto do estado vazio), `card-sets/loading.tsx` (skeleton) e `novo-catalogo-dialog.tsx` (título/descrição do Dialog, para não ficar inconsistente com o botão que o abre).
2. **Upload de logo no Dialog de edição** ("tela de edição não permite inclusão, alteração e remoção da logo do card Set. Use o mesmo padrão da tela de edição de Expansão") — diferente da logo de Expansão, aqui **não houve nenhum trabalho de banco**: bucket `card-set-logo` e `admin_set_card_set_logo()` já existiam desde 2026-07-26 (Queries `275`/`276`, ADR-022), CONFIRMADOS EXECUTADOS na época — só nunca tinham sido conectados a um uploader real no frontend (a seção "Logo da Expansão" acima registra esse mesmo fato como o motivo de a Expansão ter sido a "primeira vez que o fluxo de upload realmente chega à tela" — não é mais o caso). Construído nesta rodada:
   - `CardSetLogoUploader` (`web/components/catalogo/card-set-logo-uploader.tsx`, novo) — cópia fiel de `ExpansaoLogoUploader`, adaptada só na entidade/bucket (`card-set-logo`)/Server Action.
   - `setCardSetLogo()` (nova Server Action, `card-sets/actions.ts`) chama `admin_set_card_set_logo()` — mesmo padrão de `setExpansionLogo()`.
   - `EditCardSetDialog`/`EditCardSetForm` (`card-set-dialogs.tsx`) ganharam a seção Logo no corpo do formulário, mesma posição de `EditExpansionForm`; `onLogoUpdated` só chama `router.refresh()`, sem fechar o Dialog nem disparar o banner de sucesso do formulário nome/ordem — ações independentes.
   - `getCardSetLogoUrls()` (já existente, usada pela galeria) segue sendo a única fonte de URL assinada — nenhuma query nova.

`tsc --noEmit` confirmado limpo.

## Altura fixa da logo (Expansão e Card Set) (2026-07-31)

Puramente de apresentação — nenhuma mudança de schema, RPC, RLS ou regra de negócio. Duas rodadas de ajuste, ambas motivadas por feedback direto de Fabrício vendo a tela renderizada, não por reinterpretação teórica:

1. **Primeira rodada** — Fabrício pediu que a caixa da logo de Card Set (`CardSetGalleryCard`) usasse "a mesma altura que foi utilizada para as logos das expansões". A implementação inicial da seção anterior tinha mantido `aspect-square` para Card Set (raciocínio: logo de Card Set é um símbolo compacto, diferente do wordmark horizontal de Expansão) — esse raciocínio não se sustentou contra o pedido explícito, revertido para `aspect-[2/1]` (mesma proporção já usada em `ExpansaoGalleryCard`).
2. **Segunda rodada, mesmo dia** — Fabrício pediu algo mais específico: "gostaria que a altura do local destinado para imagem da logo fosse fixo e padrão para todos os card set, independente das dimensões das imagens... ajuste o tamanho da imagem ao local destinado e não o inverso". `aspect-[2/1]` ainda amarrava a altura da caixa à largura da coluna do grid (variável entre breakpoints, `grid-cols-2` a `grid-cols-6`) — trocado para `h-28` (altura fixa em pixels, igual em qualquer breakpoint). `object-contain` continua responsável por encaixar a imagem no espaço sem cortar nem distorcer — a imagem se adapta à caixa, nunca o inverso.

**Estado final**: `h-28` aplicado em ambas as galerias (`ExpansaoGalleryCard` e `CardSetGalleryCard`, `flex h-28 items-center justify-center bg-surface-muted`), mantendo as duas visualmente idênticas. Os skeletons de carregamento (`expansoes/loading.tsx` e `card-sets/loading.tsx`) foram atualizados junto, trocando `aspect-square`/`aspect-[2/1]` por `h-28 w-full` no bloco de imagem, para não divergir do card real. `tsc --noEmit` confirmado limpo.

## Confirmações de interface real (2026-07-31)

Fabrício confirmou, pela própria tela, as três pendências que vinham em aberto desde revisões anteriores:

- **Validação funcional de `2811`** (Card Set: edição, exclusão, bloqueio por dependentes, upload/remoção de logo) — confirmada.
- **Exclusão de `Game`** — confirmada, com um ajuste de escopo: a exclusão em lote (checkbox + `BulkSelectionBar`) foi desabilitada; só a exclusão individual (ação rápida por linha, mesmo padrão de `Expansion`/`Card Set`) está em produção. Consistente com o redesenho da tela `/catalogo/jogos` para o mesmo padrão de ícones de ação rápida (ver `jogos-table.tsx`) — `BulkSelectionBar` segue sem uso por nenhuma tela do módulo.
- **Tela completa de `Expansion`** (listagem, cadastro, edição, filtro `?game=`) — confirmada.

Com isso, `Game`/`Expansion`/`Card Set` (create/update/delete conforme aplicável) estão validados funcionalmente pela própria interface. Ver seção seguinte para a decisão explícita que resolve a última pendência do módulo — cadastro de `Card Set`.

## Cadastro de Card Set (`admin_create_card_set()`, Query `2051`) — decisão explícita de Fabrício

A decisão futura explícita que a seção anterior deste documento aguardava foi tomada: Fabrício pediu para concluir as funcionalidades de Card Set, especificamente o cadastro pela própria tela (`NovoCatalogoDialog` até então mostrava "Cadastro de Card Set ainda não disponível"). `admin_create_card_set()` deixa de estar fora de escopo.

Diferente de `admin_update_card_set()` (só nome/ordem de lançamento), a criação precisa cobrir todos os campos estruturais obrigatórios de `card_set` que a atualização deliberadamente não toca: `set_type`, `base_set_size`, `total_set_size` (além de `release_date`, opcional). Mesmo padrão de validação de `admin_create_expansion()` (Query `2033`), com as regras de negócio próprias de `card_set` (`database/schema/120_create_card_set_table.sql`) antecipadas como erro administrativo claro:

- `expansion_id` deve existir.
- `code` normalizado para maiúsculas, formato `^[A-Z0-9][A-Z0-9._-]*$` (permite começar com dígito, diferente de `Game`/`Expansion`), único dentro da Expansion.
- `release_order` positivo, único dentro da Expansion.
- `set_type` deve ser `REGULAR`, `SPECIAL` ou `PROMO`.
- `base_set_size` positivo; `total_set_size` maior ou igual a `base_set_size`.
- Se `set_type = PROMO`: `base_set_size` deve ser igual a `total_set_size` (`ck_card_set_promo_size`) e não pode já existir outro Card Set `PROMO` na mesma Expansion (`uq_card_set_expansion_promo`) — os dois antecipados com mensagem clara antes do erro bruto de constraint.
- Toda criação bem-sucedida grava `CARD_SET_CREATED` em `catalog_admin_action_log` — ação já prevista no `CHECK` desde a Query `2049` (v1.2), nenhuma migration de constraint necessária.

Número de Query: `2051`, milhar `2000`–`2999` já reservado (`STD-001` v1.17 §10). **Confirmada executada por Fabrício em 2026-07-31** (validada via `has_function_privilege`: `anon` sem `EXECUTE`, `authenticated` com `EXECUTE`). Validação `2812` — estrutural confirmada; funcional (cadastro real pela tela, incluindo um Card Set `PROMO`) ainda pendente.

Frontend: `NovoCatalogoDialog` ganhou o formulário completo (seletor de Expansão agrupado por Jogo, código, nome, tipo, ordem de lançamento, data de lançamento opcional, quantidade base e total) e nova Server Action `createCardSet` (`web/app/catalogo/card-sets/actions.ts`) — fiação completa e, com a Query `2051` confirmada, funcionalmente operante.

## Validação funcional de `2812` confirmada + dois ajustes visuais (2026-07-31)

Fabrício testou o cadastro de Card Set pela própria tela ("Funcionando perfeitamente bem"), incluindo o cenário `PROMO`: uma segunda tentativa de Card Set `PROMO` na mesma Expansion foi corretamente bloqueada por `uq_card_set_expansion_promo`, com a mensagem administrativa exibida na tela. Validação `2812` encerrada — **o ciclo vertical de `Game`/`Expansion`/`Card Set` do `ADR-023` está funcionalmente completo e confirmado.**

Dois ajustes de apresentação, puramente visuais:

1. **Largura do Dialog "Nova Coleção"**: `max-w-md` (padrão) cortava o texto das opções do seletor "Tipo" (ex.: "Promocional (Black Star..."). `NovoCatalogoDialog` passou a usar `size="lg"` (`DialogContent`, mesmo mecanismo já usado por `EditExpansionDialog`/`EditCardSetDialog`).
2. **Contraste da tarja de erro no tema escuro**: mesmo diagnóstico já repetido nesta sessão (`StatCard tone="danger"`, `ConfirmDeleteBar`) — `--destructive` no tema escuro é quase invisível sobre fundo escuro. Corrigido na fonte, em `InlineFeedback` (`web/components/ui/feedback.tsx`), tom `error`: `dark:border-destructive-foreground/25 dark:bg-destructive/20 dark:text-destructive-foreground`. Por ser um componente compartilhado, o fix vale para toda mensagem de erro inline do catálogo, não só este Dialog. Tema claro e os demais tons (`success`/`warning`) não alterados.

`tsc --noEmit` confirmado limpo.

## Correção — `admin_create_card_set()` rejeitava `ENERGY` + gap canônico em `card_set.set_type` (2026-07-31)

Fabrício testou o cadastro real de Card Set e reportou: "o campo tipo não consta o tipo Energy". Investigação encontrou dois problemas relacionados, não um só:

1. **Bug em `admin_create_card_set()` v1.0**: a validação de `set_type` só aceitava `REGULAR`/`SPECIAL`/`PROMO` — mas `ENERGY` já é um valor válido da coluna desde a **Migration `263`** (`database/migrations/263_add_energy_to_card_set_type.sql`), **confirmada executada em produção desde 2026-07-26**, quando `MEE` (Energia Básica Megaevolução) foi cadastrado com `set_type = 'ENERGY'` (Migration `265`). A função nova não foi checada contra o domínio real da coluna, só contra a leitura do arquivo canônico local — que tinha o mesmo problema (item 2). Corrigido: `admin_create_card_set()` v1.1 passa a aceitar `ENERGY`.
2. **Gap canônico em `database/schema/120_create_card_set_table.sql`**: o arquivo canônico (v2.1) nunca tinha incorporado a Migration `263` — `ck_card_set_type` ali ainda listava só `REGULAR`/`SPECIAL`/`PROMO`, apesar do próprio docstring da migration `263` alegar "incorporada à versão canônica de 120 a partir da v2.1". Uma instalação nova a partir da v2.1 ficaria divergente da produção (rejeitaria `ENERGY`). Mesma classe de problema já encontrada e corrigida nesta sessão para `EXPANSION_DELETED` em `catalog_admin_action_log` (Query `2010`). Corrigido: `120` bump para v2.2, `ck_card_set_type` agora inclui `ENERGY`.

Nenhuma constraint nova foi inventada: `ENERGY` **não** exige `base_set_size = total_set_size` por construção do banco — só `PROMO` tem essa regra (`ck_card_set_promo_size`). Em `MEE`, os dois valores hoje coincidem (`8 = 8`) porque são os únicos conhecidos no momento do cadastro, não por constraint — mesma semântica já esclarecida em `ADR-015`, revisão `1.7`, para Sets evolutivos do tipo `PROMO`/`ENERGY`.

Frontend: `NovoCatalogoDialog` ganhou a opção "Energia" no seletor de tipo; rótulo de `PROMO` simplificado de "Promocional (Black Star Promos)" para "Promocional" (pedido explícito de Fabrício, mesma rodada).

Validação `2812` reaberta (v1.1) para cobrir o novo cenário — depende do `CREATE OR REPLACE` de `admin_create_card_set()` v1.1 ser executado por Fabrício.

**`admin_create_card_set()` v1.1 confirmada por Fabrício em 2026-07-31** ("Teste em tela validado! e resposta da query como esperado") — cadastro de Card Set do tipo Energia funcionando pela própria tela. Validação `2812` (v1.1) encerrada, com os três cenários funcionais cobertos (cadastro geral, bloqueio de `PROMO` duplicado, cadastro `ENERGY`).

## Ordenação de Coleções — desempate por `release_order` (2026-07-31)

Pedido de Fabrício, a partir do teste da tela sem filtro ativo: "os card sets devem ser organizados por data de lançamento e se as datas forem iguais deve ser levado em consideração o número de ordem do lançamento. Sempre em ordem decrescente para os dois parâmetros." Puramente de apresentação — nenhuma mudança de schema/RPC/RLS.

`sortCatalogoCardSets()` (`web/lib/catalogo/queries.ts`), caminho sem filtro (galeria padrão de `/catalogo/card-sets`, cruza Jogos/Expansões por `release_date`): o desempate quando as duas datas coincidem — ou quando as duas estão ausentes — deixou de ser `created_at` (metadado técnico, sem significado editorial) e passou a ser `release_order` descendente. Quando só um dos dois Card Sets tem `release_date`, o comportamento existente (o que tem data vem primeiro) não foi questionado e permanece. Caminho **com** filtro de Jogo/Expansão (clique a partir de um card de Expansão) não foi alterado — continua usando `release_order` como critério primário (decisão já registrada e aprovada anteriormente nesta mesma revisão de sessão), fora do escopo deste pedido específico. `tsc --noEmit` confirmado limpo.

## Ampliação de `admin_update_card_set()` — tipo e data de lançamento editáveis (Query 2048 v2.0, Migration 2052)

Pedido explícito de Fabrício, testando a tela de edição: "deve ser permitido editar o tipo e a data de lançamento. Da forma como está, só consigo editar o nome e a ordem de lançamento." A v1.0 (Query `2048`, confirmada executada em 2026-07-31) só aceitava `name`/`release_order`.

`admin_update_card_set()` passa de 3 para 5 parâmetros (`p_id`, `p_name`, `p_set_type`, `p_release_order`, `p_release_date`). `expansion_id`/`code` continuam imutáveis (não aceitos); `base_set_size`/`total_set_size` continuam de fora — não foram pedidos, e mudar `set_type` sozinho já precisa lidar com as regras de `PROMO` usando o tamanho **já cadastrado** (não editável por esta função):

- Ao mudar `set_type` para `PROMO`, a função antecipa as duas regras que `ck_card_set_promo_size`/`uq_card_set_expansion_promo` reforçariam de qualquer forma, com mensagem administrativa clara: `base_set_size`/`total_set_size` já cadastrados precisam ser iguais (`ADMIN_UPDATE_CARD_SET_PROMO_SIZE_MISMATCH`); nenhum outro Card Set da mesma Expansion pode já ser `PROMO` (`ADMIN_UPDATE_CARD_SET_DUPLICATE_PROMO`).
- `set_type` aceita o mesmo domínio de `admin_create_card_set()`: `REGULAR`/`SPECIAL`/`PROMO`/`ENERGY`.
- `release_date` é opcional (`NULL` = data ainda não confirmada).

Como a assinatura muda (não é só a lógica interna, como na correção de `admin_create_card_set()` v1.1), `CREATE OR REPLACE` sozinho criaria uma segunda função sobrecarregada em vez de substituir a v1.0 — por isso o arquivo canônico (`database/schema/2048_...sql`, bump para v2.0) representa o estado de instalação nova, e uma migration própria (`database/migrations/2052_widen_admin_update_card_set_function.sql`) foi criada para reconciliar o banco já instalado: `DROP FUNCTION` da assinatura de 3 parâmetros, depois `CREATE FUNCTION` da nova.

Frontend: `EditCardSetForm` (`card-set-dialogs.tsx`) ganhou o campo Tipo (mesmo `SET_TYPE_OPTIONS` exportado de `novo-catalogo-dialog.tsx`, evitando duplicação) e Data de lançamento; `updateCardSet` (`card-sets/actions.ts`) envia os dois novos campos. `CatalogoCardSetRow`/`CatalogoCardSetRawRow` (`queries.ts`) ganharam `setType`/`set_type` — não existia antes, nenhuma tela de leitura precisava do tipo até agora. `tsc --noEmit` confirmado limpo.

**Migration `2052` confirmada executada por Fabrício em 2026-07-31** — validada via `pg_get_function_arguments`: uma única `admin_update_card_set` com os 5 parâmetros esperados (`p_id uuid, p_name text, p_set_type text, p_release_order integer, p_release_date date`), confirmando que a assinatura antiga de 3 parâmetros foi de fato removida (não ficou sobrecarregada). **Validação funcional confirmada por Fabrício em 2026-07-31** ("Teste na tela validado!") — edição de tipo e data de lançamento de Card Set pela própria tela funcionando.

## Ampliação de `admin_update_card_set()` — código editável sem Cards cadastradas (Query 2048 v3.0, Migration 2091)

Fabrício percebeu um erro real de cadastro (Coleção "151" registrada com código `SV4` em vez de `MEW`, dentro da Expansão `SV` — Scarlet & Violet) e pediu: "Preciso substituir de SV4 para MEW... Na tela de Edição deveremos permitir alterar o código. Só não será permitido se já houver cartas cadastradas." Isso revisa parcialmente a decisão original do `ADR-023` (`code` "imutável por construção... nunca uma ação de botão") — ver emenda "Card Set: código editável sem Cards cadastradas" no próprio `ADR-023`.

`admin_update_card_set()` passa de 5 para 6 parâmetros (`p_id`, `p_code`, `p_name`, `p_set_type`, `p_release_order`, `p_release_date`). `expansion_id` continua completamente fora da assinatura — só `code` ganhou uma via de correção, condicional:

- `code` normalizado para maiúsculas e validado no mesmo formato de `admin_create_card_set()` (`^[A-Z0-9][A-Z0-9._-]*$`).
- Só é efetivamente alterável enquanto o Card Set não tiver nenhuma `Card` cadastrada (ativa ou inativa — `EXISTS (SELECT 1 FROM card WHERE card_set_id = p_id)`); com pelo menos uma Card existente, tentar mudar o código falha com `ADMIN_UPDATE_CARD_SET_CODE_LOCKED`.
- Duplicidade dentro da mesma Expansion (`uq_card_set_expansion_code`) verificada explicitamente, excluindo a própria linha, só quando o código está de fato mudando (`ADMIN_UPDATE_CARD_SET_DUPLICATE_CODE`).

Como a assinatura muda, arquivo canônico (`database/schema/2048_...sql`, bump para v3.0) mais uma migration própria (`database/migrations/2091_widen_admin_update_card_set_function_for_code.sql`) para reconciliar o banco já instalado — mesmo padrão da Migration `2052`: `DROP FUNCTION` da assinatura de 5 parâmetros, depois `CREATE FUNCTION` da nova.

Frontend: `EditCardSetForm`/`EditCardSetDialog` (`card-set-dialogs.tsx`) ganharam o campo Código — editável quando `cardSet.cardsCatalogados === 0` (campo já existente em `CatalogoCardSetRow`, sem consulta nova), desabilitado com uma explicação inline quando há cartas cadastradas; a `DialogDescription` (antes só "{Jogo} · {Expansão} · {Código}", código sempre estático) passou a refletir o valor sendo digitado. `updateCardSet` (`card-sets/actions.ts`) envia o novo campo.

**Correção pontual da Coleção "151"**: como o Card Set em questão não tinha nenhuma Card cadastrada (`cards_count = 0`, verificado antes de qualquer alteração) e `MEW` não colidia com nenhum outro código já usado na Expansão `SV`, a correção foi aplicada diretamente no banco (`UPDATE card_set SET code = 'MEW' WHERE id = ...`, mesma condição que a função nova passou a impor) com uma linha correspondente gravada em `catalog_admin_action_log` (`actor_id NULL` — ação executada fora de uma sessão de aplicação, antes da Migration `2091` estar confirmada executada; `actor_id` é anulável por construção nesta tabela justamente para sobreviver a este tipo de caso). **Migration `2091` confirmada executada por Fabrício em 2026-08-01** — a partir de agora, qualquer futura correção de código passa a ir pela própria tela.

## Subciclo Card — Galeria de Cartas (leitura, 2026-07-31)

Pedido explícito de Fabrício: "vamos ao subciclo Card... precisamos caprichar no visual. A exibição das cartas é a funcionalidade que deve impressionar qualquer usuário visualmente" (referência: `tcg.pokemon.com/pt-br/galleries/scarlet-violet/`). Escopo desta rodada é **somente leitura/navegação** — a tela `/catalogo/cartas` (antes uma tabela simples por chips de código) foi reescrita como galeria visual completa: 3 Card Sets mais recentes em destaque (logo, em vez de indicadores numéricos), seletor "Coleção" para qualquer Set, busca por nome/número, filtros por raridade e categoria (checkboxes derivados das cartas do Set selecionado), grid de imagens ordenado por `collector_order`, efeito de hover "holográfico" (`HoloCard` — tilt 3D + brilho seguindo o cursor, CSS/JS puro, sem dependência nova) reaproveitado no grid e no modal de ampliação, numeração/nome/símbolo de raridade discretos abaixo de cada carta, paginação inicial (30 cartas) com botão "Ver todas".

**Nenhuma Query SQL nova foi necessária.** `card`, `card_asset`, `rarity`, `card_category` já tinham `SELECT` liberado para `authenticated` + `is_admin()` desde a Query `274` (ADR-022) — a mesma leitura que a tela anterior (`getCartasPorCardSet`) já fazia. O bucket de Storage `card-front` já é público (`Seed 895`, `is_public = TRUE`, diferente dos buckets de logo que são privados/assinados) — `getPublicUrl()` é usado em vez de `createSignedUrl()`, sem round-trip extra por imagem.

Decisões de implementação registradas aqui por não terem um critério objetivo único no pedido original:
- **Idioma da imagem**: prioridade `pt-BR` > `en` > qualquer idioma disponível (`IMAGE_LANGUAGE_PRIORITY`, `queries.ts`) — plataforma é pt-BR-first (`PRODUCT.md`), mas nem todo Card Set tem os dois idiomas importados (ver `06-pipeline-importacao.md`, "idioma é configuração fixa no código").
- **Tamanho de página inicial**: 30 cartas antes do botão "Ver todas" (`PAGE_SIZE`, `cartas-gallery.tsx`) — cobre ~5 linhas em telas largas sem sobrecarregar o primeiro carregamento de um Set grande (ME1 tem 198 cartas).
- **Símbolo de raridade**: `rarity.symbol_code` (Query 130) delega a conversão visual à aplicação — implementado com ícones já existentes de `lucide-react` (`Circle`/`Diamond`/`Star`), monocromático (`text-muted-foreground`, sem dourado real para `GOLD_DOUBLE_STAR`) — "bem discreta" foi lido como discrição de cor, não só de tamanho.

Arquivos novos: `components/catalogo/rarity-symbol.tsx`, `components/catalogo/holo-card.tsx` (+ estilos em `globals.css`), `components/catalogo/cartas-gallery.tsx`. `queries.ts`: `getCardSetOptions`/`CartaRow`/`getCartasPorCardSet` (só usados pela tela antiga) substituídos por `getCardSetsForCartas()` e `getCartasCompletas()`. `tsc --noEmit` confirmado limpo (mesma baseline de 10 erros pré-existentes em `lib/supabase/`, não relacionados). **Validação funcional pela tela ainda pendente de confirmação explícita de Fabrício.**

### Bug encontrado no primeiro teste real + ajustes de UX (2026-07-31, mesmo dia)

Fabrício testou a tela e reportou: "as cartas não [são] listadas, como esperado" (Card Set com cartas reais mostrando "Nenhuma carta catalogada"), além de três pedidos de ajuste visual.

**Causa raiz do bug — correção da afirmação acima ("Nenhuma Query SQL nova foi necessária").** Estava errada: `getCartasCompletas()` embute `card_asset(..., card_asset_type(code), ...)` para resolver qual ativo é a imagem `CARD_FRONT` principal — e `card_asset_type` é uma das 7 tabelas do Catálogo Editorial que a Query `274` (2026-07-26) deliberadamente deixou sem política de SELECT, por não ter, na época, nenhuma tela real que a consultasse. RLS bloqueia o embed aninhado silenciosamente: a query falha, `getCartasCompletas()` cai no `catch`-equivalente (`error || !data`) e retorna lista vazia — sem erro visível na tela, só o "Nenhuma carta catalogada" enganoso. Nova migration `2053_add_admin_select_policy_to_card_asset_type.sql`, mesmo padrão da `274` (uma política `USING (is_admin())` + `GRANT SELECT` para `authenticated`), SQL preparado, **aguardando execução por Fabrício via o ritual de pareamento** — a tela só listará cartas de fato depois disso.

**Três ajustes de UX, a partir do mesmo teste:**
1. Os 3 chips de Card Set mais recentes (antes blocos grandes `h-28`/`h-32`, `grid-cols-3` ocupando a largura da página) viraram uma barra fina de chips compactos (miniatura de 32px + nome) — "visual menos agressivo... não precisa ocupar a página inteira".
2. Um seletor "Outra coleção" (lista completa, agrupada por Jogo) foi adicionado na mesma barra dos chips, para saltar para qualquer Card Set sem depender do top 3.
3. Um seletor "Expansão" foi adicionado ao lado do seletor "Coleção", junto à busca — os dois sempre visíveis. "Expansão" não guarda estado próprio (é sempre derivado do Card Set selecionado, já que todo Card Set pertence a exatamente uma Expansão); trocá-lo navega para o Card Set mais recente daquela Expansão, e "Coleção" passa a listar só os Sets da Expansão atual — o "sincronismo" pedido.

`tsc --noEmit` confirmado limpo. Nenhuma mudança de schema além da Query `2053`.

### Query `2053` confirmada executada + modal de ampliação reduzido a só a imagem (2026-07-31, mesmo dia)

Fabrício executou a Query `2053` no Supabase Studio ("Success. No rows returned") — a galeria de Cartas passou a listar cartas de fato, encerrando o bug. Em seguida, primeiro elogio + um pedido pontual: "ficou espetacular... ao ampliar a carta, só quero enxergar a imagem da carta. Não preciso de nenhuma outra informação. É um modo onde o foco está única e exclusivamente na carta", com print comparando nosso modal (título, número, categoria, raridade visíveis) contra a referência oficial (só a carta, sem nenhum texto).

`CartaZoomDialog` reduzido ao essencial: removidos `DialogHeader`/título/número/categoria visíveis, a linha de raridade abaixo da carta e o botão de fechar (`hideClose`); o `DialogContent` teve fundo/borda/sombra do painel sobrepostos para transparente (só o `HoloCard` com a imagem flutua sobre o overlay escurecido, com sombra própria). Fecha por clique fora ou Esc — comportamento padrão do `Dialog`, preservado. `DialogTitle` continua presente para leitores de tela (`sr-only`, nunca visível) — Radix exige um nome acessível no `Dialog.Content`; removê-lo trocaria "sem informação visível" (o pedido) por "sem informação nenhuma" (acessibilidade quebrada), que não foi pedido. `tsc --noEmit` confirmado limpo.

### Animação idle flutuante no modal + carta maior (2026-07-31, mesmo dia)

Pedido de Fabrício, com dois prints do DevTools da referência oficial capturados em momentos diferentes (mesmos valores de `matrix3d(...)` levemente distintos entre um print e outro): "gostaria que essa carta ficasse com o efeito flutuando na tela... a carta fica se movendo lentamente mesmo sem que o mouse passe por ela. Além disso a imagem ampliada deve ser um pouco maior."

`HoloCard` ganhou uma prop `floating` (só usada por `CartaZoomDialog` — o grid continua estático em repouso, "flutuar" é destaque de uma carta por vez, não do grid inteiro): um loop `requestAnimationFrame` escreve continuamente em `rotateX`/`rotateY`/`translateY` usando três senoides com frequências e fases diferentes (evita um ciclo óbvio de "vai e volta", reproduzindo a deriva orgânica dos dois `matrix3d` capturados), pausado enquanto o mouse está sobre a carta — a interação do usuário sempre vence o automático, e ao tirar o mouse a animação retoma sozinha (sem saltar, a `transition` do CSS já existente suaviza) — e desligado por completo sob `prefers-reduced-motion: reduce`. Tamanho máximo da carta ampliada aumentado de `300px`/`340px` para `380px`/`460px` (mobile/desktop). `tsc --noEmit` confirmado limpo.

### Reformatação da identificação no grid + ampliação do mapa de símbolos de raridade (2026-07-31, mesmo dia)

Novo elogio de Fabrício ("Espetacular!") seguido de dois pedidos pontuais, com print de uma carta (Clefairy) como estava renderizada: (1) a identificação abaixo de cada carta do grid deve virar uma linha única no formato `#003/088 - Shaymim` (número, com o total quando existir, seguido do nome), com o símbolo de raridade numa linha própria logo abaixo — ambos alinhados à esquerda, substituindo o layout anterior (nome em uma linha, número/símbolo em `justify-between` na linha seguinte); (2) "os símbolos não estão exatamente como convencionado em nossa base. Exemplo: cartas do tipo Ilustração rara com símbolo círculo cinza".

O item (1) foi aplicado diretamente em `CartaGridCard` (`cartas-gallery.tsx`) — sem ambiguidade de critério.

O item (2) expôs uma lacuna, não um dado errado. `RaritySymbol` (`rarity-symbol.tsx`) nasceu na primeira rodada deste subciclo cobrindo só os 5 `symbol_code` citados como "Exemplos" no comentário da própria coluna (Query `130`) — `BLACK_CIRCLE`/`BLACK_DIAMOND`/`BLACK_STAR`/`BLACK_DOUBLE_STAR`/`GOLD_DOUBLE_STAR` —, e essa lista não é exaustiva: o seed real (`830_seed_rarity.sql`, Status `CANÔNICA`) usa nove códigos distintos em três famílias (`BLACK_*`, `SILVER_*`, `GOLD_*`, mais o caso isolado `MEGA_ATTACK` para `MEGA_ATTACK_RARE`). Todo `symbol_code` fora daqueles 5 caía no fallback genérico — um círculo cinza monocromático —, então raridades como `ILLUSTRATION_RARE` (`GOLD_STAR`), `SPECIAL_ILLUSTRATION_RARE` (`GOLD_DOUBLE_STAR`, já mapeado mas sem cor), `MEGA_HYPER_RARE` (`GOLD_DIAMOND`) e `ULTRA_RARE` (`SILVER_DOUBLE_STAR`) ficavam visualmente indistinguíveis entre si — plausivelmente exatamente o "círculo cinza" que Fabrício viu em uma carta Ilustração Rara.

`RaritySymbol` reescrito cobrindo os 9 `symbol_code` reais do seed `830`, com um esquema de cor em três tons reaproveitando tokens já existentes do Design System (não cores novas): `BLACK_*` → `text-foreground`, `SILVER_*` → `text-muted-foreground`, `GOLD_*` → `text-primary` (o dourado da marca). `MEGA_ATTACK` recebeu um ícone próprio (`Zap`, `lucide-react`) em tom dourado — não há símbolo oficial documentado para essa raridade em nenhuma fonte do projeto; escolha própria até surgir referência.

**Divergência sinalizada, não resolvida unilateralmente:** o seed `830` (CANÔNICA) mapeia `ILLUSTRATION_RARE` → `GOLD_STAR`, não a um código cinza/prateado. É plausível que o "círculo cinza" relatado por Fabrício fosse só o efeito do fallback genérico acima (agora corrigido — `GOLD_STAR` passa a renderizar em `text-primary`), mas também é possível que a convenção real da carta física seja outra (o TCG oficial usa uma estrela dourada única para Illustration Rare, o que bateria com `GOLD_STAR`) — este documento não assume qual das duas leituras está correta. Pendente confirmação explícita de Fabrício após ver o resultado na tela; se a convenção real divergir do seed, a correção é uma mudança de dado (`UPDATE rarity SET symbol_code = ...`), não de código.

`tsc --noEmit` confirmado limpo (mesma baseline de 10 erros pré-existentes em `lib/supabase/`).

### Transição de zoom com View Transitions API + dois ajustes pontuais (2026-07-31, mesmo dia)

Fabrício testou a tela novamente (print de uma carta Weedle real, Card Set com 86 cartas) e pediu três ajustes: (1) "quero mais fluidez no movimento de zoom ao clicar na imagem da carta... quero que o movimento pareça realmente uma ampliação da carta", rejeitando o zoom+fade genérico que salta direto para o tamanho final; (2) reduzir o espaço entre a identificação da carta e o símbolo de raridade, "achei muito distante"; (3) `collector_total` precisa de 3 dígitos em Card Sets pequenos — "001/086", não "001/86".

**Item 1 — morph de verdade via View Transitions API.** `document.startViewTransition()` (API nativa do navegador, sem dependência nova) substitui o zoom+fade padrão do `Dialog` só nesta tela: `CartaGridCard` e `CartaZoomDialog` passam a compartilhar o mesmo `viewTransitionName` (`carta-img-<id>`, via a nova prop `style` de `HoloCard`) — o navegador anima a miniatura do grid crescendo até virar a imagem ampliada, e o inverso ao fechar. Mecanismo: `runWithViewTransition()` (`cartas-gallery.tsx`) embrulha a troca de `zoomCarta` com `flushSync` dentro do callback do `startViewTransition`, exigido pela API para conseguir capturar o DOM "antigo" e o "novo" em dois instantes bem definidos. Como a mesma carta não pode ter o nome em dois elementos simultâneos (o grid continua montado atrás do modal), o card em processo de ampliação cede seu nome (`isZoomTarget` → `"none"`) exatamente quando o modal assume esse mesmo nome — sem essa cessão a API rejeitaria a transição por nome duplicado. `DialogContent` ganhou uma nova prop `animated` (default `true`, preserva todo Dialog existente) que desliga seu zoom+fade embutido (`animate-dialog-in`/`-out`) só quando a View Transitions API está disponível — sem suporte, ou sob `prefers-reduced-motion: reduce`, cai de volta para esse comportamento padrão, ainda curto o bastante. Nova regra `::view-transition-group(*)` em `globals.css` alinha a duração/curva do morph (420ms, `cubic-bezier(0.22, 1, 0.36, 1)`) com a mesma curva já usada em `.holo-card`.

**Item 2 — aplicado diretamente**: `space-y-1` → `space-y-0.5` entre a linha de identificação e `RaritySymbol`, em `CartaGridCard`.

**Item 3 — `collector_total` é `INTEGER`** (não `VARCHAR` como `collector_number`), perde zeros à esquerda no banco. Em vez de consultar `base_set_size` do Card Set (uma junção a mais), a exibição aplica `padStart(3, "0")` diretamente no valor — cobre exatamente o mesmo caso descrito por Fabrício ("set base inferior a 100 cartas"), já que sets com 100+ cartas já têm 3+ dígitos naturalmente.

`tsc --noEmit` confirmado limpo (mesma baseline de 10 erros pré-existentes em `lib/supabase/`).

### Correção: carta em transição aparecia atrás das vizinhas (2026-07-31, mesmo dia)

Fabrício reportou, com print capturando o meio da animação: "durante a transição a carta fica por trás das demais cartas. Só no estágio final ela aparece na frente."

**Causa raiz.** A implementação original dava `viewTransitionName` único a cada uma das ~122 cartas do grid, o tempo todo (só a carta-alvo cedia o próprio nome para o modal). A View Transitions API não distingue "elemento que de fato vai mudar de posição/tamanho" de "elemento que só por acaso tem um nome" — qualquer elemento com `view-transition-name` diferente de `none` no instante em que `document.startViewTransition()` é chamado é retirado do fluxo normal e repintado através da árvore de pseudo-elementos da transição (`::view-transition-group`), mesmo que sua geometria não mude. Como as ~122 cartas tinham nome simultaneamente, todas eram "hoistadas" junto — e a ordem de pintura entre esses grupos (baseada na ordem de descoberta na árvore, não em z-index) colocava vizinhas posteriores no DOM na frente da carta que estava de fato crescendo.

**Correção.** Nova regra: no máximo uma carta por vez pode ter um `viewTransitionName` não-`"none"` — todas as outras ficam permanentemente `"none"` (não fazem parte de nenhuma transição, nunca são hoistadas). Novo estado `transitionTargetId` (`cartas-gallery.tsx`) marca qual carta é a "fonte" no instante certo: um `flushSync` fora da transição atribui o nome à carta clicada ANTES de chamar `document.startViewTransition` (para existir no snapshot "antigo"); a própria transição então move esse nome da miniatura do grid para a imagem do modal (abrir) ou de volta (fechar), exatamente como antes — só que agora isolado a uma única carta por vez. `tsc --noEmit` confirmado limpo.

### Correção: espaço "solto" entre identificação e símbolo (2026-07-31, mesmo dia)

Fabrício ainda achou o símbolo distante da identificação: "prefiro mais compacto... da forma que está o símbolo parece solto na tela." A causa não era a margem entre os dois elementos (`space-y-0.5`, já pequena) — era o próprio `<span>` do `RaritySymbol`, que não define `line-height` próprio e por isso herda o line-height ambiente de onde é usado (bem maior que os 7px do ícone), deixando uma faixa de espaço em branco embutida em torno do símbolo mesmo sem nenhuma margem visível causando isso. Corrigido com `leading-none` no `RaritySymbol` (e no `<p>` de identificação, para simetria). `tsc --noEmit` confirmado limpo.

## Raridade — mapeamento self-service e revalidação (Queries `2094`–`2113`, CONFIRMADO EXECUTADO)

`ADR-024`, emenda "Raridade: mapeamento self-service e revalidação" (2026-08-07). Substitui `RARITY_NAME_ALIASES` (mapa hardcoded em `import-catalog-cards/services/normalize.ts`) por dado administrável via UI — corrigir ou cadastrar um mapeamento de raridade deixa de exigir deploy de código.

**Extensão e normalização (`2094`/`2095`).** `unaccent` habilitada no schema `extensions`; `normalize_external_catalog_value(p_value TEXT)` (`sql STABLE`) remove acento/caixa/espaçamento (`upper(regexp_replace(trim(extensions.unaccent(...)), '\s+', ' ', 'g'))`) — usada tanto pelo cadastro self-service quanto pelo processador TCGdex, via módulo compartilhado `_shared/catalog-normalization/` (extraído de `import-catalog-cards/services/normalize.ts`, reutilizável por outra Edge Function).

**Modelo (`2096`/`2097`).** `public.rarity_external_mapping` (`game_id`, `asset_source_id`, `external_value`, `normalized_external_value`, `rarity_id`) — `UNIQUE(game_id, asset_source_id, normalized_external_value)`, FKs `ON DELETE RESTRICT`, RLS habilitado, trigger de `updated_at` reaproveitando `set_updated_at()`.

**Ampliação da auditoria (`2098`).** As três `CHECK` de `catalog_admin_action_log` (Query `2010`) ganham `RARITY_CREATED`/`RARITY_UPDATED` (entity_type `RARITY`), `RARITY_EXTERNAL_MAPPING_CREATED`/`RARITY_EXTERNAL_MAPPING_UPDATED` (entity_type `RARITY_EXTERNAL_MAPPING`) e `CATALOG_IMPORT_ROWS_REVALIDATED` (entity_type `CATALOG_IMPORT_JOB`) — mesma técnica de `DROP`+`ADD CONSTRAINT` das Queries `2041`/`2043`/`2049`.

**Cadastro administrativo (`2099`–`2103`).** `admin_create_rarity()`/`admin_update_rarity()` (CRUD de `rarity`, `game_id`/`code` imutáveis na edição); `admin_create_rarity_external_mapping()`/`admin_update_rarity_external_mapping()` (CRUD de `rarity_external_mapping`, valida que `rarity_id` pertence ao mesmo `game_id`); `admin_create_rarity_with_external_mapping()` (wrapper atômico das duas primeiras, fluxo "Nova raridade" da tela). Todas `SECURITY DEFINER`, exigem `is_admin()`, gravam auditoria própria.

```sql
CREATE OR REPLACE FUNCTION public.admin_create_rarity_with_external_mapping(
    p_game_id UUID, p_code TEXT, p_name TEXT, p_symbol_code TEXT, p_display_order INTEGER,
    p_asset_source_id UUID, p_external_value TEXT
)
RETURNS TABLE(rarity_id UUID, mapping_id UUID)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$ ... $$;
```

**Backfill (`2104`).** Os 25 aliases que viviam em `RARITY_NAME_ALIASES` migrados para `rarity_external_mapping` (Game `POKEMON`, Fonte `TCGDEX`, timestamp único de lote) — mesmo conjunto de valores, sem mudança de comportamento observável na importação.

**Revalidação sem reimportação (`2105`/`2106`).** `internal.persist_catalog_import_revalidation(p_job_id, p_row_updates)` — escrita em lote única (`jsonb_to_recordset()` + `UPDATE ... FROM`), `EXECUTE` revogado de `authenticated`/`anon` (só chamada por `2106`, mesmo isolamento de `internal.write_card()`). `public.svc_apply_catalog_import_revalidation(p_job_id, p_row_updates, p_actor_id)` — contrato de `service_role`, chamado pela Edge Function `revalidate-catalog-import-rows`: recalcula linhas de um job `STAGED`/`CONFIRMING`/`COMPLETED_WITH_ERRORS` sem tocar `decision_status` já decidido, destrava linhas que haviam falhado só por raridade não mapeada (`persistence_status FAILED` + `validation_status` recalculado para `VALID` → volta a `PENDING`), e recalcula o status do job — um `COMPLETED_WITH_ERRORS` com pelo menos uma linha destravada volta a `CONFIRMING`.

**GRANTs/policy de apoio (`2110`/`2112`/`2113`).** `SELECT` em `catalog_import_row` para `service_role` (sem isso, a Edge Function de revalidação lia zero linhas — sintoma observado antes da correção: "Revalidar tudo" sempre reportava `updated_count = 0`). `SELECT` em `asset_source` para `authenticated` + política `catalog_admin_select` (`USING (is_admin())`) — necessário para a tela popular a combo de Fonte no formulário de mapeamento.

**Limpeza de jobs (`2111`).** Investigação e correção de jobs presos em `COMPLETED_WITH_ERRORS` cuja causa raiz (raridade não mapeada) já havia sido corrigida antes da revalidação existir — ver `database/migrations/2111_cleanup_completed_with_errors_jobs.sql` para o registro exato do que foi limpo.

**Cadastro real de `RARE_HOLO` (`2109`)** — a raridade mais comum de todo o catálogo (holográfica clássica) só foi percebida como faltante durante o uso real da tela; cadastrada via `admin_create_rarity_with_external_mapping()`, mesmo caminho que qualquer administrador usaria.

**Frontend (`/catalogo/raridades`, CONFIRMADO IMPLEMENTADO).** Lista Raridades cadastradas e valores externos pendentes (staged sem mapeamento), ação "Resolver raridade" (Raridade existente ou Nova raridade) e botão "Revalidar tudo". Guarda de admin (`requireCatalogoAdmin`), mesmo padrão das demais telas do módulo. Camada de dados em `web/lib/catalogo/queries.ts` (`getRaridades`, resumo de revalidação pendente); Server Actions em `web/app/catalogo/raridades/actions.ts`.

### Sequência — Raridade

```text
2094 - Enable unaccent Extension                              (CONFIRMADO EXECUTADO — database/schema/2094_enable_unaccent_extension.sql)
2095 - Create normalize_external_catalog_value() Function      (CONFIRMADO EXECUTADO — database/schema/2095_create_normalize_external_catalog_value_function.sql)
2096 - Create rarity_external_mapping Table                    (CONFIRMADO EXECUTADO — database/schema/2096_create_rarity_external_mapping_table.sql)
2097 - rarity_external_mapping Triggers                        (CONFIRMADO EXECUTADO — database/schema/2097_rarity_external_mapping_triggers.sql)
2098 - Add Rarity Actions to Catalog Admin Action Log          (CONFIRMADO EXECUTADO — database/migrations/2098_add_rarity_actions_to_catalog_admin_action_log.sql)
2099 - Create admin_create_rarity() Function                   (CONFIRMADO EXECUTADO — database/schema/2099_create_admin_create_rarity_function.sql)
2100 - Create admin_update_rarity() Function                   (CONFIRMADO EXECUTADO — database/schema/2100_create_admin_update_rarity_function.sql)
2101 - Create admin_create_rarity_external_mapping() Function  (CONFIRMADO EXECUTADO — database/schema/2101_create_admin_create_rarity_external_mapping_function.sql)
2102 - Create admin_update_rarity_external_mapping() Function  (CONFIRMADO EXECUTADO — database/schema/2102_create_admin_update_rarity_external_mapping_function.sql)
2103 - Create admin_create_rarity_with_external_mapping()      (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE — database/schema/2103_create_admin_create_rarity_with_external_mapping_function.sql)
2104 - Backfill rarity_external_mapping                        (CONFIRMADO EXECUTADO — database/migrations/2104_backfill_rarity_external_mapping.sql)
2105 - Create internal.persist_catalog_import_revalidation()   (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE — database/schema/2105_create_internal_persist_catalog_import_revalidation_function.sql)
2106 - Create svc_apply_catalog_import_revalidation()          (CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE — database/schema/2106_create_svc_apply_catalog_import_revalidation_function.sql)
2109 - Cadastro real de RARE_HOLO                              (CONFIRMADO EXECUTADO — via admin_create_rarity_with_external_mapping())
2110 - Grant SELECT catalog_import_row to service_role         (CONFIRMADO EXECUTADO — database/migrations/2110_grant_select_catalog_import_row_to_service_role.sql)
2111 - Cleanup COMPLETED_WITH_ERRORS jobs duplicados           (CONFIRMADO EXECUTADO — database/migrations/2111_cleanup_completed_with_errors_jobs.sql)
2112 - Grant SELECT asset_source to authenticated              (CONFIRMADO EXECUTADO — database/migrations/2112_grant_select_asset_source_to_authenticated.sql)
2113 - Create asset_source catalog_admin_select Policy         (CONFIRMADO EXECUTADO — database/migrations/2113_create_asset_source_catalog_admin_select_policy.sql)
```

Ver `adr/ADR-024-catalog-card-ingestion-strategy.md`, emenda "Raridade: mapeamento self-service e revalidação" (2026-08-07), para a decisão arquitetural completa.

## Pendências / Próximos Passos

A leitura/galeria de Cartas está implementada, funcional (Query `2053` confirmada executada) e ajustada visualmente conforme três rounds de teste real de Fabrício — nenhuma pendência conhecida na experiência de leitura. O cadastro self-service de Raridade (acima) está implementado e em uso em produção. **Atualizado em 2026-08-07** (esta seção estava desatualizada — o subciclo `Card` do `ADR-023` já tinha fechado no mesmo dia, mas esta lista de pendências nunca foi revisada): o ciclo vertical completo de `Card` está concluído — atualização (`admin_update_card()`, Query `2114`), criação (`admin_create_card()`, Query `2115`) e desativação/reativação (`admin_deactivate_card()`/`admin_reactivate_card()`, Queries `2116`/`2117`), todas confirmadas executadas e validadas funcionalmente (validação `2817`). `ADR-023` está formalmente fechado — ver seção "`admin_create_card()`/`admin_deactivate_card()`/`admin_reactivate_card()`" acima. Pendência isolada, deliberadamente fora deste fechamento: auditoria retroativa de `REVOKE ... FROM PUBLIC/anon` nas demais funções `admin_*` do módulo, criadas antes da descoberta desse gap (item futuro separado, decisão de Fabrício). O fechamento formal do Ciclo 2 de `ADR-024` (ver seção "Ciclo 2 — Fluxo vertical completo via TCGdex" acima) está com a documentação escrita; a validação `2818` correspondente aguarda execução e confirmação de Fabrício.

---

