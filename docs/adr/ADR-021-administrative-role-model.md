# ADR-021 — Administrative Role Model

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-021 |
| **Título** | Administrative Role Model |
| **Status** | Aprovado |
| **Data** | 2026-07-26 |
| **Decisores** | Fabrício Sales |
| **Decisão** | O papel de administrador é modelado como presença de linha em uma tabela dedicada (`admin_user`), sem nenhuma política de RLS — nunca como atributo em `user_profile`. Existe um único papel (`admin`), não um sistema de papéis/permissões genérico. Todo acesso administrativo (listagem de usuários, concessão/revogação do papel) passa por funções `SECURITY DEFINER` que verificam a identidade do próprio chamador; nenhuma função aceita um UUID arbitrário como parâmetro de checagem. Toda concessão/revogação é registrada em `admin_action_log`, com FKs anuláveis (`ON DELETE SET NULL`) e um retrato (`metadata`) dos dados relevantes, garantindo que a auditoria sobreviva à exclusão futura de usuários. |
| **Documentos Relacionados** | `ADR-020-user-profile-and-username-identity-model.md`, `../05-modelo-de-dados.md`, `../standards/STD-001-database-standards.md` |

---

# Context

ADR-020 registrou `user_profile` como identidade básica do usuário e deixou explicitamente em aberto onde papéis e permissões seriam modelados no futuro — "como atributos de `user_profile` ou como entidades relacionadas próprias" — condicionando qualquer correção administrativa de `username` à existência de um modelo de papéis aprovado.

Com o Incremento 1 ("Meu Perfil") concluído e validado em produção, Fabrício solicitou o Incremento 2 ("Administração de Usuários"): visibilidade administrativa sobre a base de usuários, com o requisito explícito de não construir antecipadamente um sistema genérico e completo de RBAC — apenas o mínimo necessário para uma administração segura.

Detalhes de implementação (estrutura exata das tabelas, paginação, numeração de Queries) ficam registrados em `05-modelo-de-dados.md`, não neste ADR.

---

# Decision

## Papel administrativo como entidade relacionada, não como atributo de `user_profile`

`admin_user` é uma tabela própria — presença de uma linha (`id` referenciando `auth.users.id`) significa que o usuário é administrador. Não existe coluna `is_admin` em `user_profile`. Motivo: as políticas de RLS de `user_profile` autorizam `UPDATE` por linha (`auth.uid() = id`), não por coluna — um booleano administrativo ali seria autopromovível pelo próprio usuário via API, a menos que blindado por um trigger adicional. Uma tabela separada, sem nenhuma política de RLS (mesmo padrão já usado por `reserved_username`), elimina esse risco por construção: só funções `SECURITY DEFINER` a leem ou escrevem.

Isso resolve a pendência deixada em aberto por ADR-020: papéis são modelados como entidade relacionada, não como atributo de `user_profile`.

## Um único papel, não um sistema genérico de papéis e permissões

Existe exatamente um papel (`admin`), representado por presença/ausência de linha — não uma tabela de papéis, escopos ou permissões granulares. Se o produto precisar de mais papéis no futuro, isso será um incremento próprio, com sua própria proposta arquitetural. Este ADR deliberadamente não antecipa essa generalização.

## Funções `SECURITY DEFINER` verificam apenas o chamador, nunca um UUID arbitrário

`is_admin()` não aceita parâmetro de usuário — verifica somente `auth.uid()`, o usuário autenticado da própria sessão. Nenhuma função deste módulo permite que um usuário consulte o status administrativo de outro UUID livremente. As funções de mutação (`admin_grant_admin()`/`admin_revoke_admin()`) reutilizam essa mesma checagem internamente para autorizar o chamador, e usam trava consultiva de transação (`pg_advisory_xact_lock`) para serializar concessões/revogações concorrentes — evitando que duas revogações simultâneas removam o último administrador ao mesmo tempo.

## Listagem de usuários paginada desde a origem

`admin_list_users()` nasce com paginação (`limit`/`offset`, com teto máximo controlado na própria function), mesmo sem busca ou filtros nesta fase — uma listagem ilimitada não é adequada à evolução comercial do produto, ainda que a base atual seja pequena.

## Auditoria sobrevive à exclusão de usuários

`admin_action_log` referencia `auth.users` com FKs anuláveis (`ON DELETE SET NULL`), não com exclusão em cascata — perder o usuário ator ou alvo não apaga o registro da ação. Um retrato (`metadata`, JSONB) captura os dados relevantes (username/e-mail) no momento da ação, preservando contexto útil mesmo depois que a referência direta se torna `NULL`.

## Correção administrativa de `username` permanece fora deste incremento

A pendência registrada em ADR-020 sobre correção administrativa de `username` não é resolvida por este ADR. Com o papel administrativo agora existente, o mecanismo se torna tecnicamente possível (uma função `SECURITY DEFINER` com uma flag local à transação, sinalizando ao trigger `enforce_user_profile_invariants()` que aquela alteração específica é autorizada) — mas Fabrício decidiu tratá-la como incremento futuro separado, não como parte do Incremento 2, para manter este incremento controlado.

## E-mail exposto apenas via função vetada, nunca por acesso direto a `auth.users`

O frontend nunca consulta `auth.users` diretamente. `admin_list_users()` é a única via de leitura de e-mail para fins administrativos — verifica internamente que o chamador é administrador antes de expor qualquer dado, e retorna somente os campos estritamente necessários (username, nome de exibição, avatar, e-mail, data de criação, status administrativo).

---

# Consequences

## Benefícios

- Elimina por construção o risco de autopromoção a administrador — a tabela `admin_user` não é alcançável por nenhuma política de RLS, só por funções vetadas.
- Resolve a pendência de modelagem de papéis deixada em aberto por ADR-020, sem comprometer prematuramente um design de RBAC completo.
- Auditoria administrativa (`admin_action_log`) e paginação da listagem já nascem corretas, evitando retrabalho quando a base de usuários crescer.
- Trava consultiva de transação torna a salvaguarda do "último administrador" correta sob concorrência, não apenas sob uso sequencial.

## Restrições / Pendências

- Um único papel administrativo nesta fase — múltiplos níveis administrativos, se necessários futuramente, exigem nova proposta.
- Correção administrativa de `username` permanece indisponível até um incremento futuro dedicado.
- Visualização do `admin_action_log` pela interface não faz parte deste incremento — o dado é gravado desde já, sem tela própria ainda.
- Bootstrap do primeiro administrador é uma operação manual única, não uma migration replicável entre ambientes (ver `05-modelo-de-dados.md`).

---

# Alternatives Considered

## Coluna `is_admin` em `user_profile`

Rejeitada. A política de RLS de `UPDATE` de `user_profile` autoriza por linha, não por coluna — um usuário poderia se autopromover via API, exigindo um trigger adicional só para blindar essa coluna. Uma tabela separada, sem política alguma, é estruturalmente mais simples e segura.

## Sistema de papéis e permissões genérico (RBAC completo) desde já

Rejeitada por Fabrício. Nenhum caso de uso concreto exige múltiplos papéis ou permissões granulares hoje — construir essa generalização agora seria especular sobre necessidade futura, contrariando o princípio de simplicidade inicial do projeto (AP-004).

## `is_admin(p_user_id UUID)` aceitando qualquer UUID

Considerada na proposta inicial, rejeitada por Fabrício antes da implementação. Permitiria que qualquer usuário autenticado consultasse o status administrativo de outro UUID arbitrário — informação que não deveria ser publicamente consultável. A versão final não aceita parâmetro: verifica somente o chamador.

## Exclusão em cascata (`ON DELETE CASCADE`) em `admin_action_log`

Considerada na proposta inicial, rejeitada por Fabrício. Apagaria o histórico administrativo junto com a exclusão futura de um usuário — incompatível com o propósito de um log de auditoria, que deve sobreviver ao evento que ele documenta.

---

# Related Documents

- `ADR-020-user-profile-and-username-identity-model.md`
- `../05-modelo-de-dados.md`
- `../standards/STD-001-database-standards.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação — formaliza o papel administrativo como entidade relacionada (`admin_user`), sem política de RLS, distinta de `user_profile`; um único papel, sem RBAC genérico; funções `SECURITY DEFINER` que verificam somente o próprio chamador; listagem paginada desde a origem; auditoria (`admin_action_log`) com FKs anuláveis e retrato em `metadata`, sobrevivendo à exclusão de usuários; correção administrativa de `username` reconhecida como tecnicamente viável a partir deste incremento, mas deliberadamente adiada para um incremento futuro separado. Resolve a pendência de modelagem de papéis deixada em aberto por ADR-020. |
