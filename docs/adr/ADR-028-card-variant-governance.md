# ADR-028 — Card Variant Governance

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-028 |
| **Título** | Card Variant Governance |
| **Status** | Aprovado |
| **Data** | 2026-08-14 |
| **Decisores** | Project Mimikyu |
| **Decisão** | `Card Variant` é entidade mestre do Catálogo Editorial. Criação, alteração, ativação/inativação e manutenção são exclusivas de administradores. Usuários finais nunca criam ou modificam uma `card_variant` — apenas selecionam uma variante já existente ao cadastrar um Collection Item (item físico) no Inventário. A restrição é garantida no backend/RLS, nunca apenas pela ausência de UI. |
| **Documentos Relacionados** | `ADR-022-catalog-editorial-admin-only-access.md`, `ADR-023-catalog-editorial-write-authorization.md`, `ADR-013-collection-item-identity-model.md`, `ADR-009-card-variant-scope.md`, `ADR-010-card-rarity-and-finish-model.md`, `ADR-016-card-variant-naming-convention.md` |

---

# Context

`Card Variant` (`card_variant`/`card_variant_type`, Queries 150/151/160/161, ver `05-modelo-de-dados.md`) já existe fisicamente no repositório desde 2026-07-18, com RLS habilitado, mas nunca teve uma decisão de governança própria registrada — a leitura administrativa de `card_variant` foi liberada de forma incidental pela Query 274 (ADR-022, tabela a tabela, junto com as demais 9 tabelas consultadas pela Visão Geral), sem nenhuma decisão específica sobre quem pode escrever nesta entidade.

Essa lacuna se tornou relevante em 2026-08-09, quando Fabrício decidiu que Card Variant é um bloco intermediário obrigatório entre o Catálogo Editorial e Coleções (`ROADMAP.md`): `Collection Item` (o exemplar físico possuído pelo colecionador, `ADR-013`) referencia uma `Card Variant`, não a `Card` genérica — a identidade colecionável precisa estar correta e sob controle exclusivamente editorial antes que o domínio de posse física seja modelado sobre ela.

O checkpoint técnico de 2026-08-14 (auditoria do que já existe, ver `docs/log.md`) confirmou: `card_variant` já tem policy de leitura administrativa (`catalog_admin_select`) e é consumida indiretamente por `getCartasCatalogoStats()` (`/catalogo/cartas`); `card_variant_type` está com RLS habilitado mas sem nenhuma policy nem GRANT (ninguém lê, nem admin); não existe nenhuma via de escrita (CRUD) para nenhuma das duas tabelas. Este ADR formaliza a governança antes de qualquer escrita ser implementada — decisão de processo, não decisão técnica isolada de uma migration.

---

# Decision

## Card Variant é entidade mestre do Catálogo Editorial

`card_variant_type` e `card_variant` seguem exatamente o mesmo modelo de autorização já estabelecido para o restante do Catálogo Editorial (`ADR-022`): acesso de leitura restrito a administradores, liberado tabela a tabela via RLS (`is_admin()`) somente onde uma tela real consulta — nunca leitura ampla concedida antecipadamente. Toda futura escrita (criação, alteração, ativação/inativação) segue o mesmo padrão de `ADR-023`: função `SECURITY DEFINER` específica, nunca política de `UPDATE`/`INSERT`/`DELETE` ampla, `EXECUTE` revogado de `PUBLIC`/`anon`/`authenticated` não-admin.

## Usuários finais nunca escrevem em Card Variant

O colecionador final (usuário autenticado não-administrador) nunca cria, altera, ativa/inativa ou exclui uma `card_variant`. A única interação prevista é **seleção**: ao cadastrar um Collection Item no futuro Inventário, o usuário escolhe entre as variantes já existentes de uma Card — a variante em si é sempre um dado editorial, mantido exclusivamente por administradores, igual a `Game`/`Expansion`/`Card Set`/`Card`.

Isso implica uma futura decisão de leitura (não resolvida por este ADR, porque Coleções ainda não começou, ver `ROADMAP.md`): quando o Inventário existir, o usuário final precisará de leitura pública (autenticado, não só admin) de `card_variant` para popular o seletor — uma policy nova, adicional à `catalog_admin_select` hoje existente, não uma substituição dela. Registrado aqui como consequência conhecida, não como decisão antecipada.

## A restrição é efetiva no backend, nunca apenas na ausência de UI

Nenhuma tela ou action é, por si só, controle de acesso. Toda leitura e escrita de `card_variant`/`card_variant_type` deve continuar sendo impossível para quem não tem permissão, independentemente de existir ou não uma interface que a exponha — mesmo princípio já aplicado a todo o Catálogo Editorial desde `ADR-022`, reafirmado aqui explicitamente porque Card Variant é a base de identidade sobre a qual o domínio de posse (Coleções) será construído: uma falha de autorização nesta camada se propagaria para todo o domínio do colecionador.

---

# Consequences

## Benefícios

- Card Variant entra no bloco intermediário já com o mesmo padrão de autorização comprovado do resto do Catálogo Editorial, sem precisar de uma exceção ou de um modelo de permissão novo;
- qualquer leitura ou escrita futura (view de cobertura, CRUD administrativo, seletor de Coleções) tem uma decisão de governança já registrada para se apoiar, em vez de decidir authorization ad hoc a cada Query;
- a separação leitura-admin (hoje) vs. leitura-autenticado-para-seleção (futuro, quando Coleções existir) fica registrada como consequência conhecida, evitando que uma implementação futura amplie a policy de leitura administrativa por engano em vez de criar uma policy nova e específica.

## Restrições / Pendências

- a policy de leitura para o seletor de Coleções (usuário final, não-admin) permanece em aberto — só será desenhada quando o módulo Coleções começar;
- nenhuma função de escrita (`admin_create_card_variant()` e equivalentes) existe ainda; este ADR autoriza o padrão que ela deverá seguir quando for implementada, não implementa nenhuma agora.

---

# Alternatives Considered

## Tratar Card Variant como parte da governança geral de ADR-022, sem ADR próprio

Rejeitada: Card Variant tem uma implicação de governança específica (é a base de identidade referenciada por Collection Item, futuro domínio de posse do usuário) que justifica registro e rastreabilidade próprios, mesmo reaproveitando integralmente o modelo de `ADR-022`/`ADR-023` — mesmo raciocínio já usado para não emendar `ADR-006` na criação de `ADR-027`.

## Permitir que usuários finais sugiram novas variantes

Rejeitada nesta rodada: Card Variant é dado editorial (mesma natureza de `Card`/`Card Set`), e qualquer inclusão de conteúdo por usuário final abriria uma superfície de curadoria/moderação fora do escopo atual do projeto. Pode ser reavaliada no futuro como proposta explícita, nunca como escrita direta.

---

# Related Documents

- `ADR-022-catalog-editorial-admin-only-access.md`
- `ADR-023-catalog-editorial-write-authorization.md`
- `ADR-013-collection-item-identity-model.md`
- `ADR-009-card-variant-scope.md`
- `ADR-010-card-rarity-and-finish-model.md`
- `ADR-016-card-variant-naming-convention.md`
- `../ROADMAP.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação — formaliza a decisão de governança de Card Variant (referência de trabalho: CV-01), aprovada por Fabrício em 2026-08-14, logo após o checkpoint técnico que auditou o estado real de `card_variant`/`card_variant_type` no repositório. |
