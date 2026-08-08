# ADR-027 — Catalog Editorial Canonical Metrics Views

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-027 |
| **Título** | Catalog Editorial Canonical Metrics Views |
| **Status** | Aprovado |
| **Data** | 2026-08-08 |
| **Decisores** | Fabrício Sales |
| **Decisão** | Métricas derivadas e reutilizáveis do Catálogo Editorial (volume estrutural, cobertura de imagem por idioma e, futuramente, qualquer métrica equivalente consumida por mais de uma tela) são expostas por `VIEW` comum do PostgreSQL — nunca tabela materializada nem agregação duplicada em código de aplicação — sempre com `WITH (security_invoker = true)` e `GRANT SELECT` restrito a `authenticated`, reaproveitando a política RLS `is_admin()` já definida nas tabelas de origem (`ADR-022`). Métricas estruturais do catálogo (volume, cobertura) nunca se juntam a métricas operacionais do pipeline de importação (`catalog_import_job`) na mesma view. Dimensões com crescimento não fechado (ex.: idioma) são modeladas como uma linha por combinação `(entidade, dimensão)`, nunca como colunas fixas por valor. |
| **Documentos Relacionados** | `ADR-006-separation-of-catalog-ownership-and-analytics.md`, `ADR-022-catalog-editorial-admin-only-access.md`, `ADR-023-catalog-editorial-write-authorization.md`, `../standards/STD-001-database-standards.md` |

---

# Context

A Sprint Gerencial 1 (Visão Geral + métricas canônicas do Catálogo Editorial) precisava de uma fonte única de métricas de volume e cobertura, reutilizável tanto pela tela Visão Geral quanto pela futura Central de Relatórios. Até esta decisão, esses números eram calculados em memória no lado da aplicação (`web/lib/catalogo/queries.ts`, funções como `getEstadoDoCatalogo()`/`getCartasCatalogoStats()`), buscando todas as linhas de `card`/`card_set` via paginação manual e agregando em TypeScript — abordagem que já havia causado um bug real em produção (MEE "desaparecendo" da Visão Geral quando `card` cruzou o limite padrão de 1000 linhas por página do PostgREST, corrigido por `fetchAllRows()`).

`ADR-022` já havia estabelecido o padrão de acesso administrativo do Catálogo Editorial (RLS `USING (is_admin())` tabela a tabela, `GRANT SELECT` só para `authenticated`), mas nenhuma decisão do projeto até aqui cobria como expor *dado derivado* (agregações, contagens, cruzamentos) dessas tabelas sem duplicar essa lógica de segurança nem recalculá-la em cada tela. Esta é a primeira vez que o projeto usa `CREATE VIEW` sobre tabelas com RLS.

Antes de aprovar a Query 2123 (primeira implementação concreta deste padrão), Fabrício revisou o plano técnico em quatro pontos — segurança da view sobre RLS, ambiguidade semântica de contagens agregadas, acoplamento a um conjunto fechado de idiomas, e separação entre métricas estruturais e operacionais — cujas resoluções compõem a Decision abaixo.

---

# Decision

## Toda view administrativa usa `security_invoker = true`, sem exceção

Uma `VIEW` comum do PostgreSQL, por padrão, executa com o contexto de privilégio do seu *owner* — não de quem a consulta. Como o owner de uma view normalmente contorna RLS (é dono das tabelas de origem), uma view sem `security_invoker = true` sobre tabelas protegidas por `is_admin()` exporia os dados a qualquer `authenticated`, administrador ou não, silenciosamente. `WITH (security_invoker = true)` (PostgreSQL 15+, já confirmado disponível no projeto) força a avaliação de RLS e privilégios pela identidade de quem consulta, igualando o comportamento a um `SELECT` direto nas tabelas de origem. Toda `CREATE VIEW` futura sobre dado do Catálogo Editorial usa esta opção — sem ela, a view não deve ser aprovada em revisão.

## `GRANT SELECT` restrito a `authenticated`, nunca a `anon` nem `PUBLIC`

Mesma disciplina de mínimo privilégio já estabelecida em `ADR-022` para as tabelas base: a view em si só recebe `GRANT SELECT ... TO authenticated`. A proteção efetiva contra usuários não-administradores continua sendo a política RLS herdada das tabelas de origem (via `security_invoker`), não a ausência de `GRANT` — mas o `GRANT` a `anon`/`PUBLIC` nunca é concedido, por princípio, mesmo que a RLS já bastasse sozinha.

## Views substituem agregação em memória como fonte canônica de métricas derivadas

Métricas reutilizáveis por mais de uma tela (Visão Geral hoje; Central de Relatórios amanhã) são calculadas uma única vez, em SQL, numa view — nunca recalculadas de forma equivalente (e potencialmente divergente) em cada função de `queries.ts` que precisar delas. Isso estende o princípio de `ADR-006` (dado derivado não deve ser persistido redundantemente sem justificativa técnica) à camada de leitura: a view não persiste nada de novo, só formaliza um cálculo que já acontecia, de forma inconsistente, em múltiplos lugares.

## Métricas estruturais e operacionais nunca se misturam na mesma view

Views de métricas estruturais do catálogo (`card`/`card_set`/`expansion`/`game` — volume, cobertura) não fazem `JOIN` com tabelas do pipeline de importação (`catalog_import_job`/`catalog_import_row`). Decisão de Fabrício na revisão do plano da Query 2123: misturar as duas multiplicaria linhas por job (uma Card Set pode ter múltiplos jobs históricos) e acoplaria uma camada de dado relativamente estável (volume do catálogo) a uma camada de alta cardinalidade e alta frequência de mudança (execuções de importação). Métricas operacionais (contagem de jobs por status, pendências de revisão) são consultadas diretamente onde necessário, sem view dedicada, a menos que uma necessidade concreta de reuso apareça depois.

## Dimensões de crescimento aberto viram grão da view, nunca coluna fixa

Quando uma métrica varia por uma dimensão que pode crescer (ex.: idioma — `language` já é modelada no projeto para suportar novos códigos além de `en`/`pt-BR`, ver `190_create_language_table.sql`), a view usa `CROSS JOIN` contra a tabela dessa dimensão (filtrada por `is_active`), produzindo uma linha por combinação `(entidade, valor-da-dimensão)` sempre — inclusive zero explícito quando não há dado. Rejeitado o desenho alternativo de uma coluna fixa por valor (`cards_com_imagem_en`, `cards_com_imagem_pt_br`), que exigiria alterar a view a cada idioma novo.

## Precisão semântica de contagens agregadas

Nenhuma métrica agregada usa um nome ambíguo que possa esconder populações distintas. Estabelecido concretamente pela Query 2123: `total_set_size` (tamanho oficial esperado, editável manualmente, pode divergir da fonte externa) é distinto de `cards_cadastradas` (toda Card com registro, ativa ou não) e de `cards_ativas` (`is_active = true`); `cards_inativas` é sempre `cards_cadastradas - cards_ativas` (cartas que existiram e foram desativadas), nunca confundido com `cards_pendentes_cadastro` (`GREATEST(total_set_size - cards_cadastradas, 0)`, cartas que nunca foram cadastradas) — populações que uma fórmula ingênua (`total_set_size - cards_ativas`) misturaria incorretamente. Toda coluna de métrica agregada carrega `COMMENT ON COLUMN` com sua fórmula e a população exata que representa.

## Definições de negócio canônicas ficam documentadas na própria view

Quando uma view formaliza uma regra de negócio que já existia de forma implícita em código de aplicação (ex.: "Card com imagem" = existe `card_asset` com `is_primary = true` E `card_asset_type.code = 'CARD_FRONT'` para o idioma, sem checar `is_active` — critério já usado em `getCartasCatalogoStats()`/`getImagesImportadasPorCardSet()`), a view adota exatamente a mesma regra, documentada via `COMMENT ON COLUMN`, para não criar uma segunda definição divergente entre telas. Uma limitação conhecida e pré-existente (não checar `is_active`) é preservada deliberadamente nesse momento, não corrigida silenciosamente por baixo de uma tela nova.

## Validação de segurança usa simulação de papel com `SET LOCAL ROLE`, dentro de transação com `ROLLBACK`

Toda view administrativa nova é validada provando os três papéis relevantes — administrador lê; `authenticated` não-administrador não lê (RLS filtra para zero linhas); `anon` não acessa (`permission denied`, sem `GRANT`) — via `SET LOCAL ROLE` + `set_config('request.jwt.claim.sub', ...)` dentro de uma transação sempre desfeita por `ROLLBACK` (nunca `COMMIT`), mesmo padrão já usado em `2814_validate_catalog_import_functions.sql`. Armadilha real encontrada e documentada na validação da Query 2123 (`2820`): `SET LOCAL ROLE` executado dentro de um bloco PL/pgSQL `BEGIN...EXCEPTION` é desfeito junto com o rollback do savepoint implícito desse bloco quando uma exceção esperada é capturada — a troca de role deve sempre ficar fora de qualquer bloco protegido por `EXCEPTION`. Cada papel testado deve se autoafirmar por `RAISE EXCEPTION` em caso de resultado incorreto, para que "Success" no SQL Editor já seja prova suficiente, sem depender de ler texto de `RAISE NOTICE` (que nem sempre aparece na interface usada por Fabrício).

---

# Consequences

## Benefícios

- Fonte única e reutilizável de métricas do Catálogo Editorial — Visão Geral e a futura Central de Relatórios consomem a mesma view, sem risco de divergência entre telas.
- Segurança reaproveitada, não duplicada: `security_invoker = true` faz a view herdar exatamente a mesma política RLS já provada em produção pelas tabelas base — nenhuma lógica de autorização nova para manter.
- Elimina a classe de bug já vivida em produção (paginação de 1000 linhas mascarando contagens): a agregação acontece no banco, não em memória na aplicação.
- Desenho extensível a novos idiomas sem alteração de schema, alinhado à intenção já registrada em `190_create_language_table.sql`.

## Restrições / Pendências

- Nenhum mecanismo automático (lint/CI) garante hoje que uma `CREATE VIEW` futura sobre o Catálogo Editorial use `security_invoker = true` — depende de revisão manual contra este ADR. Candidato futuro para a Operação de Lint (`CLAUDE.md`).
- A armadilha de `SET LOCAL ROLE` dentro de bloco `EXCEPTION` (ver seção de validação acima) não é óbvia e pode se repetir em validações futuras se não for lembrada explicitamente — registrada aqui e no cabeçalho de `2820_validate_catalog_card_set_metrics_views.sql` para mitigar.
- Contagem operacional de `catalog_import_job` por status permanece fora de qualquer view por ora — se uma necessidade concreta de reuso surgir (ex.: mesma contagem exibida em três telas diferentes), este ADR já autoriza uma view própria para isso, desde que não misturada à view estrutural.

---

# Alternatives Considered

## Manter agregação em memória na aplicação (status quo)

Rejeitada como fonte canônica de longo prazo. Já havia causado um bug real de produção (contagem de MEE mascarada pela paginação padrão de 1000 linhas do PostgREST) e exigiria reimplementar a mesma lógica de agregação de forma equivalente para a futura Central de Relatórios, dobrando a superfície de manutenção e o risco de divergência.

## View materializada em vez de view comum

Rejeitada por falta de justificativa técnica concreta na escala atual do catálogo (37 Card Sets, milhares de Cards) — aplicação direta de `ADR-006` (dado derivado não deve ser persistido redundantemente sem necessidade comprovada). Pode ser reavaliada se o volume ou a frequência de consulta um dia justificarem.

## Colunas fixas por idioma na view de cobertura (`cards_com_imagem_en`/`cards_com_imagem_pt_br`)

Considerada e rejeitada por Fabrício na revisão do plano: acopla a fonte canônica de métricas a uma lista fechada de idiomas, exigindo alteração de schema a cada idioma novo — contradiz a intenção de extensibilidade já registrada na tabela `language`.

## Integrar `catalog_import_job` à view estrutural de métricas

Considerada e rejeitada por Fabrício: multiplicaria linhas por job histórico e misturaria uma camada relativamente estável (volume do catálogo) com uma de alta cardinalidade e mudança frequente (execuções de importação). Métricas operacionais seguem consultadas diretamente, sem view dedicada, até que uma necessidade real de reuso justifique uma.

---

# Related Documents

- `ADR-006-separation-of-catalog-ownership-and-analytics.md`
- `ADR-022-catalog-editorial-admin-only-access.md`
- `ADR-023-catalog-editorial-write-authorization.md`
- `../standards/STD-001-database-standards.md`
- `database/schema/2123_create_catalog_card_set_metrics_views.sql`
- `database/validations/2820_validate_catalog_card_set_metrics_views.sql`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação — formaliza `security_invoker = true` e `GRANT SELECT` restrito a `authenticated` como padrão obrigatório para toda `VIEW` administrativa sobre dado do Catálogo Editorial; views (nunca tabelas materializadas nem agregação em memória na aplicação) como mecanismo canônico de métricas derivadas reutilizáveis; separação obrigatória entre métricas estruturais e operacionais; grão por dimensão de crescimento aberto (ex.: idioma) em vez de coluna fixa; precisão semântica de contagens agregadas; e o procedimento de validação de segurança por simulação de papel, incluindo a armadilha de `SET LOCAL ROLE` dentro de bloco `EXCEPTION`. Motivado pela Query 2123 (`catalog_card_set_metrics`/`catalog_card_set_image_coverage`), primeira `VIEW` do projeto sobre tabelas com RLS, implementada como parte da Sprint Gerencial 1 (Visão Geral + métricas canônicas). |
