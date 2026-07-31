# ADR-023 — Catalog Editorial Write Authorization

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-023 |
| **Título** | Catalog Editorial Write Authorization |
| **Status** | Aprovado |
| **Data** | 2026-07-26 |
| **Decisores** | Fabrício Sales |
| **Decisão** | Toda escrita administrativa das entidades `game`, `expansion`, `card_set` e `card` passa por função `SECURITY DEFINER` específica por operação — nunca por política de RLS ampla de `INSERT`/`UPDATE`. A lógica real de validação e persistência vive numa camada interna (ex. `internal.write_card()`), num schema não exposto pela API (`internal`), com `EXECUTE` revogado de `PUBLIC`, `anon` e `authenticated`, `search_path` explícito (`SET search_path = ''`) e toda referência qualificada por schema — não é um contrato RPC público, e o prefixo `_` não é tratado como mecanismo de proteção. `Game`, `Expansion` e `Card Set` recebem apenas create/update nesta fase, sem desativação por UI — **emenda 2026-07-26**: `Game` passa a ter também exclusão real via UI (`admin_delete_game()`), distinta de desativação, bloqueada pela `FK` existente quando há Expansions associadas; `Expansion`/`Card Set` não são afetados por esta emenda. `Card` recebe create/update/deactivate/reactivate: `is_active` é um soft delete real, não condicionado à ausência de dependentes — `card_variant`, `card_asset` e `card_external_reference` nunca são tocados pela desativação; toda leitura operacional filtra `is_active = true` por padrão, com uma via explícita para consultas administrativas incluírem inativas; a `UNIQUE(card_set_id, collector_number)` permanece válida independente de `is_active`, então qualquer cadastro ou importação que colida com uma carta inativa resolve como conflito explícito, nunca reativação silenciosa. `card_set_id` e `collector_number` nunca são alteráveis por atualização, mesmo sob decisão administrativa explícita. Toda operação bem-sucedida grava uma linha numa auditoria editorial própria, separada de `admin_action_log`. |
| **Documentos Relacionados** | `ADR-021-administrative-role-model.md`, `ADR-022-catalog-editorial-admin-only-access.md`, `ADR-024-catalog-card-ingestion-strategy.md`, `../05-modelo-de-dados.md`, `../standards/STD-001-database-standards.md` |

---

# Context

`ADR-022` liberou leitura administrativa do Catálogo Editorial e uma única função de escrita pontual (`admin_set_card_set_logo()`). Nenhuma outra via controlada de escrita existe: todas as 927 Cards, as 7 Card Sets e as demais entidades estruturais entraram no banco por SQL direta, escrita por sessão de IA e executada por Fabrício, fora de qualquer autorização de aplicação. O próprio pipeline de importação de imagens (`import-card-assets`, `ADR-018`) reforça essa lacuna por decisão deliberada: ele consulta `card`, nunca insere — `card`/`card_variant` são explicitamente congeladas fora do escopo daquele pipeline.

Ao retomar o desenvolvimento do módulo Catálogo Editorial (telas de listagem de Jogos, Expansões, Card Sets, Cartas e Importações já implementadas), Fabrício solicitou telas de cadastro reais para essas entidades. A análise que motivou este ADR identificou que isso exige, antes de qualquer formulário, uma camada de autorização de escrita — o mecanismo tratado aqui — distinta da estratégia de ingestão de Cards em lote (PDF/TCGdex), tratada em `ADR-024`. Os dois ADRs são deliberadamente separados: este define **como** qualquer escrita administrativa acontece; `ADR-024` define **quais** canais alimentam `Card` e como convergem para o mecanismo definido aqui.

---

# Decision

## Escrita administrativa sempre por função `SECURITY DEFINER`, nunca por política ampla

Nenhuma das quatro tabelas (`game`, `expansion`, `card_set`, `card`) recebe política de RLS de `INSERT`/`UPDATE`/`DELETE`. Toda escrita passa por uma função `SECURITY DEFINER` específica por operação, mesmo padrão já estabelecido em `admin_set_card_set_logo()` (`ADR-022`) e em `admin_grant_admin()`/`admin_revoke_admin()` (`ADR-021`): cada função valida `is_admin()` internamente, aceita apenas os parâmetros da operação que existe para fazer, e usa `GET DIAGNOSTICS`/`RAISE EXCEPTION` para confirmar o efeito real da escrita — nunca assume sucesso apenas porque a chamada não retornou erro.

## Camada interna canônica, isolada de qualquer contrato RPC público

A validação de FK, a proteção dos campos estruturalmente sensíveis (ver seção própria abaixo) e o `INSERT`/`UPDATE` real de `card` vivem numa função interna única (ex. `internal.write_card(p_mode, ...)`, com `p_mode` distinguindo criação de atualização), reutilizada por `admin_create_card()`, `admin_update_card()` e, em `ADR-024`, por `admin_confirm_catalog_import()`. Essa função não é um contrato RPC público — é explicitamente protegida contra chamada direta do frontend, por quatro medidas independentes, nenhuma delas sozinha suficiente:

- **Schema não exposto pela API** — vive num schema novo, `internal`, fora da lista de schemas expostos pela API do Supabase (que hoje só expõe `public`); PostgREST não alcança objetos fora dos schemas configurados como expostos, independentemente de `GRANT`.
- **`EXECUTE` revogado explicitamente** — `REVOKE EXECUTE ON FUNCTION internal.write_card(...) FROM PUBLIC, anon, authenticated;`, como defesa em profundidade — não depende só do isolamento de schema para ser segura.
- **`search_path` explícito e seguro** — `SET search_path = ''`, mesmo padrão já usado em `admin_set_card_set_logo()` — a função nunca resolve um nome de objeto por busca implícita de schema.
- **Referências sempre qualificadas por schema** — todo objeto citado dentro da função usa o nome completo (`public.card`, `public.card_set`, etc.), nunca um nome ambíguo que dependeria do `search_path` de quem chama.

O prefixo `_` (usado informalmente na proposta inicial deste ADR) é abandonado como convenção de nomenclatura para essa função — não tem nenhum efeito de controle de acesso em PostgreSQL, e sua presença no nome poderia sugerir erroneamente que a proteção real já estivesse garantida por ali.

O schema `internal` nasce com este ADR, mas não é exclusivo do Catálogo Editorial — é a convenção do projeto, a partir de agora, para qualquer função auxiliar `SECURITY DEFINER` que não deva ser um contrato RPC público, em qualquer módulo futuro.

## Funções públicas por entidade

`admin_create_game()`/`admin_update_game()`, `admin_create_expansion()`/`admin_update_expansion()`, `admin_create_card_set()`/`admin_update_card_set()`, `admin_create_card()`/`admin_update_card()`/`admin_deactivate_card()`/`admin_reactivate_card()`. Parâmetros exatos, mensagens de erro e a numeração das Queries que as criam ficam para `05-modelo-de-dados.md` no momento da implementação — este ADR fixa a existência e o papel de cada função, não a assinatura completa.

## `Game`, `Expansion` e `Card Set`: sem desativação nesta fase

Nenhuma das três entidades recebe `admin_deactivate_*` neste incremento. `Game`/`Expansion` têm hoje um único registro cada — desativar o único Game ou Expansion existente é uma ação existencial, não uma correção pontual. `Card Set` já tem sete registros com Cards/importações associadas — introduzir `is_active` ali exigiria adaptar praticamente toda consulta já implementada (`getCardSetsOverview`, `getEstadoDoCatalogo`, `getCartasPorCardSet`, o seletor de Cartas) para um caso de uso ainda sem necessidade concreta. Um Card Set cadastrado por engano e ainda sem nenhuma Card associada pode ser removido por SQL direta, como qualquer outra correção rara já tratada assim neste projeto (ex. recódigo de `MEP`).

Esta seção trata de **desativação** (`is_active`) — permanece integralmente válida para as três entidades. Sobre **exclusão real** de `Game`, ver a emenda abaixo.

## Emenda (2026-07-26) — `Game`: exclusão real via UI

Durante a implementação do ciclo vertical de `Game`, Fabrício solicitou um caminho de exclusão pela própria tela, em vez de depender de SQL direta para corrigir um Jogo cadastrado por engano — o caso que a versão original deste ADR já prescrevia resolver "por SQL direta, como qualquer outra correção rara". Fabrício optou por formalizar essa correção como uma função administrativa real (`admin_delete_game()`) em vez de manter a via manual.

- `admin_delete_game(p_id)` executa um `DELETE` real e definitivo — não é desativação, não usa `is_active` (Game continua sem essa coluna). Não há "lixeira" nem forma de desfazer pela UI.
- A `FOREIGN KEY fk_expansion_game` (`ON DELETE RESTRICT`, Query `110`) já impede a exclusão de um Game com Expansions associadas — a função apenas antecipa esse erro bruto com uma mensagem administrativa clara (`ADMIN_DELETE_GAME_HAS_DEPENDENTS`), mesmo padrão de "antecipar o erro" já usado em `admin_set_card_set_logo()`/`admin_create_game()`.
- Toda exclusão bem-sucedida grava uma linha em `catalog_admin_action_log` (`GAME_DELETED`) **antes** da linha do Game deixar de existir — captura `code`/`name` em `metadata`, já que não há mais registro para consultar depois.
- Esta emenda cobria, na origem, exclusivamente `Game`. Ver a emenda seguinte para a extensão a `Expansion`; `Card Set` continua sem `admin_delete_*` — se o mesmo padrão for desejado para ele, é uma decisão própria, a ser registrada quando (e se) o ciclo vertical dele chegar a essa necessidade.
- Números de Query: `2041` (adiciona `GAME_DELETED` ao `CHECK` de `catalog_admin_action_log`) e `2042` (`admin_delete_game()`), ambos no milhar `2000`–`2999` já reservado (`STD-001` v1.17 §10).

## Emenda (2026-07-31) — `Expansion`: exclusão real via UI

Fabrício pediu o mesmo caminho de exclusão real já usado por `Game` — inclusão de um botão de ação rápida "excluir" na galeria de Expansões (`web/components/catalogo/expansao-gallery-card.tsx`), ao lado do já existente "editar". Mesma decisão de fundo da emenda anterior, agora estendida à segunda entidade do módulo.

- `admin_delete_expansion(p_id)` executa um `DELETE` real e definitivo — não é desativação, não usa `is_active` (Expansion continua sem essa coluna). Não há "lixeira" nem forma de desfazer pela UI.
- A `FOREIGN KEY fk_card_set_expansion` (`ON DELETE RESTRICT`, Query `120`) já impede a exclusão de uma Expansion com Card Sets associados — a função apenas antecipa esse erro bruto com uma mensagem administrativa clara (`ADMIN_DELETE_EXPANSION_HAS_DEPENDENTS`), mesmo padrão de "antecipar o erro" já usado em `admin_delete_game()`.
- Toda exclusão bem-sucedida grava uma linha em `catalog_admin_action_log` (`EXPANSION_DELETED`) **antes** da linha da Expansion deixar de existir — captura `code`/`name` em `metadata`, já que não há mais registro para consultar depois.
- `Card Set` continua sem `admin_delete_*` — não é abrangido por esta emenda.
- Números de Query: `2043` (adiciona `EXPANSION_DELETED` ao `CHECK` de `catalog_admin_action_log`) e `2044` (`admin_delete_expansion()`), ambos no milhar `2000`–`2999` já reservado (`STD-001` v1.17 §10).

## `Card`: `is_active` como soft delete real

`card` recebe uma coluna `is_active boolean not null default true`. A desativação **não** é condicionada à ausência de dependentes — essa era a proposta inicial deste ADR, revisada por Fabrício por não resolver o problema real: a maioria dos erros de cadastro só é percebida depois que a Card já tem ao menos uma imagem ou variante associada, não antes.

Consequências obrigatórias dessa escolha, registradas explicitamente porque não se limitam a `queries.ts`:

- Toda consulta operacional (as já implementadas em `web/lib/catalogo/queries.ts` e qualquer nova) considera `is_active = true` por padrão.
- Indicadores e contagens do catálogo (Estado do Catálogo, cobertura de imagens, Card Sets overview) consideram apenas Cards ativas — uma Card desativada deixa de contar para "cartas catalogadas", mesmo que seus `card_asset`/`card_variant` continuem fisicamente intactos no banco.
- Consultas administrativas podem solicitar Cards inativas explicitamente — a via padrão exclui, a inclusão é um pedido deliberado, nunca o inverso.
- `card_variant`, `card_asset` e `card_external_reference` **nunca** são tocados por `admin_deactivate_card()` — permanecem exatamente como estavam, preservando histórico e rastreabilidade por completo. Não há cascata de desativação.
- Fluxos normais (formulário individual, confirmação de importação) não adicionam novas variantes, assets ou referências externas a uma Card inativa — isso exigiria reativação explícita primeiro, nunca acontece implicitamente como efeito colateral de outra operação.
- A `UNIQUE(card_set_id, collector_number)` já existente na tabela permanece válida independentemente de `is_active` — uma Card inativa continua ocupando sua chave natural. Por isso, qualquer verificação de correspondência (cadastro individual ou importação, `ADR-024`) precisa localizar Cards ativas **e** inativas ao comparar por essa chave: se ignorasse as inativas, trataria um número já ocupado como livre, e uma tentativa de criação falharia na constraint sem explicação, ou pior, um fluxo de importação tentaria recriar silenciosamente algo que já existe (ainda que inativo). O resultado correto é sempre um conflito explícito, nunca uma reativação implícita.
- `admin_reactivate_card()` apenas restaura `is_active = true`. Como nenhum dependente foi removido ou ocultado individualmente, a Card volta a aparecer nas consultas operacionais automaticamente — não há nada para "recriar".

## Campos estruturalmente protegidos nunca são alteráveis por atualização

`admin_update_card()` — e, por construção, a camada interna que ele chama — nunca aceita alterar `card_set_id` nem `collector_number`, mesmo sob decisão administrativa explícita (inclusive ao resolver um conflito de importação em `ADR-024`). Mudar esses dois campos muda a identidade da Card, não o seu conteúdo; se a fonte sugerir um número diferente para o que parece ser "a mesma" Card, isso é matéria de revisão manual fora da UI, no mesmo espírito já aplicado a `card_set.code`/`set_type` (correção rara, deliberada, nunca uma ação de botão).

## Auditoria editorial própria, separada de `admin_action_log`

Nenhuma função deste ADR grava em `admin_action_log` — essa tabela pertence ao domínio de Identidade & Acesso (`ADR-021`), com um `CHECK` deliberadamente restrito a `GRANT_ADMIN`/`REVOKE_ADMIN`, e ampliá-la misturaria dois domínios distintos. Uma nova tabela própria do Catálogo Editorial (nome definitivo a fixar em `05-modelo-de-dados.md` na implementação, ex. `catalog_admin_action_log`) registra toda operação administrativa bem-sucedida deste ADR — ator, ação, entidade, identificador, timestamp. Em `ADR-024`, a confirmação em lote grava exatamente uma linha agregada por chamada (referenciando o job, não uma por Card) — o detalhe linha a linha da importação já vive em `catalog_import_row`, sem necessidade de duplicação.

---

# Consequences

## Benefícios

- Pela primeira vez desde o início do projeto, existe uma via de escrita administrativa real para `game`/`expansion`/`card_set`/`card` — cadastro deixa de depender de SQL direta escrita fora da aplicação.
- A camada interna canônica elimina uma classe inteira de erro (esquecer de proteger `card_set_id`/`collector_number` numa das três vias de escrita) por construção — a proteção existe num único lugar, não replicada em três funções públicas.
- O isolamento do schema `internal` (não exposto + `EXECUTE` revogado + `search_path` seguro) estabelece uma convenção reutilizável por qualquer módulo futuro que precise de lógica interna não exposta, não apenas o Catálogo Editorial.
- `is_active` como soft delete real resolve o problema que a alternativa original não resolvia: permite corrigir um cadastro errado mesmo depois que ele já acumulou imagens/variantes, sem perder histórico.

## Restrições / Pendências

- `Game`/`Expansion`/`Card Set` seguem sem caminho de **desativação** (`is_active`) por UI — se isso se tornar necessário, é uma decisão futura própria, fora deste ADR. `Game` (`admin_delete_game()`, emenda 2026-07-26) e `Expansion` (`admin_delete_expansion()`, emenda 2026-07-31) passaram a ter **exclusão real** via UI — as duas coisas são distintas de desativação; `Card Set` não recebe nenhuma das duas por estas emendas.
- O nome definitivo da tabela de auditoria editorial e as assinaturas completas de cada função (`admin_create_*`/`admin_update_*`/`admin_deactivate_card`/`admin_reactivate_card`, `internal.write_card`) ficam para `05-modelo-de-dados.md`, no momento da implementação — este ADR fixa a decisão conceitual, não a DDL.
- O pipeline de importação de imagens (`import-card-assets`) não é alterado por este ADR e não passa a verificar `is_active` de forma nenhuma — se uma Card for desativada depois de já ter um `card_asset`, o pipeline continua sem saber disso. Tratar essa interação (ex. impedir novo asset num card inativo em uma reexecução futura do pipeline) fica sinalizado, não resolvido aqui.

---

# Alternatives Considered

## Prefixar a função interna com `_` como sinal de privacidade

Considerada na proposta inicial deste ADR, rejeitada explicitamente por Fabrício antes da implementação. Um prefixo no nome não é um mecanismo de controle de acesso em PostgreSQL — qualquer função `GRANT`ada continua invocável independentemente do nome. A proteção real (schema não exposto, `EXECUTE` revogado, `search_path` explícito) substitui inteiramente essa convenção.

## Restringir `admin_deactivate_card()` a Cards sem `card_variant`/`card_asset`/`card_external_reference`

Proposta inicial deste próprio processo de revisão, rejeitada por Fabrício. Resolveria apenas o caso degenerado (erro percebido antes de qualquer dependente existir), que é raro na prática — a maioria das correções reais surge depois que a Card já acumulou histórico. `is_active` como soft delete irrestrito, preservando dependentes intactos, resolve o problema real.

## Política de RLS ampla de `UPDATE`/`INSERT` nas quatro tabelas

Rejeitada pelo mesmo raciocínio já registrado em `ADR-021`/`ADR-022`: autoriza qualquer coluna da tabela, inclusive colunas futuras ainda não previstas hoje. Funções específicas por operação eliminam esse risco por construção.

## Reaproveitar `admin_action_log` para a auditoria editorial

Rejeitada por instrução explícita de Fabrício. Identidade & Acesso e Catálogo Editorial são domínios diferentes; o `CHECK` de `admin_action_log` é deliberadamente estreito (`GRANT_ADMIN`/`REVOKE_ADMIN`), e ampliá-lo misturaria dois domínios de auditoria sem necessidade.

## Desativação de `Game`/`Expansion`/`Card Set` neste incremento

Considerada, adiada. Volume baixíssimo (1 Game, 1 Expansion, 7 Card Sets, todos corretos hoje) e o risco de uma ação de UI existencial (Game/Expansion) ou de alto impacto em consultas já implementadas (Card Set) não justificam antecipar essa necessidade sem um caso de uso concreto.

## Manter a exclusão de `Game` apenas via SQL direta (emenda 2026-07-26)

Era a decisão original deste ADR — revisada por pedido explícito de Fabrício durante a implementação do ciclo vertical de `Game`. Motivo da mudança: uma correção que já era esperada e rara (Jogo cadastrado por engano) ganha uma via administrativa auditável em vez de depender de acesso direto ao banco fora da aplicação, mesmo racional que já motivou toda a arquitetura de `ADR-023`. Estender o mesmo padrão a `Expansion`/`Card Set` não foi pedido nesta emenda e permanece em aberto.

---

# Related Documents

- `ADR-021-administrative-role-model.md`
- `ADR-022-catalog-editorial-admin-only-access.md`
- `ADR-024-catalog-card-ingestion-strategy.md`
- `../05-modelo-de-dados.md`
- `../standards/STD-001-database-standards.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação — formaliza a escrita administrativa de `game`/`expansion`/`card_set`/`card` exclusivamente por função `SECURITY DEFINER`, nunca por política de RLS ampla. Introduz o schema `internal` (não exposto pela API, `EXECUTE` revogado de `PUBLIC`/`anon`/`authenticated`, `search_path` explícito) como convenção do projeto para lógica interna não exposta, corrigindo a suposição inicial de que um prefixo `_` seria suficiente. Define `is_active` em `card` como soft delete real e irrestrito (não condicionado à ausência de dependentes), com as consequências obrigatórias sobre consultas operacionais, contagens, correspondência de chave natural e reativação. Protege `card_set_id`/`collector_number` contra alteração por qualquer via administrativa. Cria uma auditoria editorial própria, deliberadamente separada de `admin_action_log`. Motivado pela retomada do desenvolvimento do módulo Catálogo Editorial e pela ausência histórica de qualquer via de escrita controlada para essas quatro entidades. |
| 1.1 | **Emenda: `Game` ganha exclusão real via UI (`admin_delete_game()`, Queries `2041`/`2042`).** Pedido de Fabrício durante o ciclo vertical de `Game` — substitui a correção antes prevista "por SQL direta" por uma função administrativa auditável, bloqueada pela `FK` já existente (`fk_expansion_game`, `ON DELETE RESTRICT`) quando há Expansions associadas. Exclusão, não desativação — `Game` continua sem `is_active`. Restrita a `Game`; `Expansion`/`Card Set` não recebem `admin_delete_*` por esta emenda. |
| 1.2 | **Emenda: `Expansion` ganha exclusão real via UI (`admin_delete_expansion()`, Queries `2043`/`2044`).** Pedido de Fabrício — mesmo padrão da emenda 1.1, agora estendido a `Expansion`: função administrativa auditável, bloqueada pela `FK` já existente (`fk_card_set_expansion`, `ON DELETE RESTRICT`) quando há Card Sets associados. Exclusão, não desativação — `Expansion` continua sem `is_active`. `Card Set` continua sem `admin_delete_*`. Queries `2043` e `2044` confirmadas executadas por Fabrício em 2026-07-31 (validadas via `pg_get_constraintdef` e `has_function_privilege`, respectivamente); validação funcional dos 4 cenários (`2809`) ainda pendente. |
