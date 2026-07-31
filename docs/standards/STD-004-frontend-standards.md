# STD-004 — Frontend Standards

| Campo | Valor |
|--------|-------|
| **Documento** | STD-004 |
| **Título** | Frontend Standards |
| **Versão** | 1.1 |
| **Status** | Aprovado |
| **Objetivo** | Definir os padrões permanentes de interface — navegação, composição de página, tabelas, formulários, feedback e tema — aplicados ao frontend web do Project Mimikyu. |
| **Escopo** | Todo o código em `web/` (App Router, componentes, hooks). Não redefine regras de negócio, contratos de dados, autenticação ou autorização — essas permanecem nos ADRs e em `05-modelo-de-dados.md`. |
| **Dependências** | `adr/ADR-019-web-application-as-primary-interface.md` |
| **Documentos Relacionados** | `adr/ADR-021-administrative-role-model.md`, `adr/ADR-022-catalog-editorial-admin-only-access.md`, `adr/ADR-023-catalog-editorial-write-authorization.md` |

---

# Purpose

Este documento define os padrões oficiais de interface do frontend web do Project Mimikyu — o "porquê" arquitetural fica nos ADRs referenciados acima; este documento registra apenas o "como" permanente, verificável em qualquer tela nova.

Criado em 2026-07-30, formalizando a área que a auditoria de 26/07 (`docs/README.md`, revisão `1.55`) já havia identificado como pendente (`docs/frontend/`/`web/README.md`/`STD-004`), retomada nesta sessão dedicada de correção e sincronização de frontend.

Este documento registra apenas padrões permanentes — não é um diário de sessão. Decisões pontuais, arquivos alterados e histórico de implementação ficam no handoff vigente (`docs/development/`) e, quando relevante, comentados no próprio código.

---

# 1. Stack e Organização

Next.js (App Router) + React + TypeScript + Tailwind CSS, Supabase (Auth, Storage, Postgres via `@supabase/ssr`) — ver `adr/ADR-019-web-application-as-primary-interface.md`. Componentes primitivos seguem a convenção shadcn/Radix (`class-variance-authority`, `@radix-ui/react-*`, `cn()` para merge de classes).

Server Components por padrão; um componente só vira Client Component (`"use client"`) quando precisa de estado, evento de interação ou hook do React. Autorização real (sessão, `is_admin()`) sempre verificada no servidor, nunca inferida no cliente — o cliente só decide o que **mostrar**, nunca o que **permitir**.

---

# 2. Tokens e Tema

Cores, tipografia e raio de borda vivem como CSS variables em `app/globals.css` (blocos `:root`/`.dark`), conectadas às classes utilitárias do Tailwind via `tailwind.config.ts`. Nenhuma cor literal (`#hex`, `rgb()`) fora desses dois arquivos — todo componente consome os tokens semânticos (`bg-surface`, `text-muted-foreground`, `border-border`, etc.), nunca uma cor bruta.

Tipografia: Inter (`--font-sans`, corpo e navegação), Manrope (`--font-heading`, exclusivo para `PageTitle`/títulos de página), Geist Mono (`--font-mono`). Claro/escuro via `next-themes`, alternância manual sempre visível (`ThemeToggle`) — nunca só a preferência do sistema.

---

# 3. Navegação

Duas camadas, sem alteração de interação prevista (ver `components/app-shell/`):

- **`PrimaryRail`** — trilha compacta e fixa (`w-16`), só ícones; expande no hover/focus (`group-hover`/`group-focus-within`, CSS puro, sem JS) revelando o rótulo. Um item por módulo (`NAV_SECTIONS`, `nav-config.ts`), nunca por página individual.
- **`SecondaryPanel`** — coluna contextual, aparece só quando a seção ativa tem `children`; agrupa itens por `section` (título maiúsculo + divisória) quando o módulo tiver mais de um agrupamento lógico.
- **Mobile** — Drawer lateral (`MobileNav`, Radix Dialog), sem hover — a lista já nasce expandida.
- Perfil, configurações e logout ficam fixos no rodapé da `PrimaryRail` (`SidebarFooter`), fora de `NAV_SECTIONS`.
- Item de menu com `adminOnly: true` é checagem de UX — a autorização real está sempre na página/RLS, nunca só no menu.

---

# 4. Composição de Página

Toda página autenticada usa `AppShell` (sidebar + header) e, dentro dele, os primitives de `components/ui/page.tsx`:

- **`PageContainer`** — largura máxima da página. Variantes: `default` (`max-w-6xl`, listagens/tabelas), `wide` (`max-w-7xl`, telas com mais colunas), `full` (sem limite), `settings` (`max-w-2xl`, formulários de coluna única).
- **`PageHeader`** — linha superior, título+descrição à esquerda (`PageHeading` > `PageTitle`/`PageDescription`), ações primárias à direita (`PageActions`).
- **`PageToolbar`** — linha de busca/filtros, só renderiza quando a página tem algo a filtrar.
- **`PageSection`** — bloco temático dentro de uma página com mais de uma seção (fora do padrão Settings, que usa `SettingsSection` própria).

`PageTitle` sempre usa `font-heading` (Manrope); nenhuma página escreve `<h1>` cru.

---

# 5. Superfície (Card)

`components/ui/card.tsx` é o único primitive de superfície de conteúdo — `Card`/`CardHeader`/`CardTitle`/`CardDescription`/`CardContent`, com a prop `density`:

- **`density="default"`** (implícita) — `shadow-panel`, padding generoso (`p-6`). Uso: telas de formulário único (Login, Cadastro, Perfil) e placeholders (`ComingSoonPage`).
- **`density="compact"`** — sem sombra, padding reduzido (`px-4`), título sem tracking forçado. Uso: telas de listagem/tabela densas (Expansões, e as próximas migradas do Catálogo Editorial).

`components/catalogo/panel.tsx` (`Panel`) está **descontinuado para uso em telas novas** — sua receita foi absorvida por `Card density="compact"`. As telas que ainda usam `Panel` (Jogos, Visão Geral do Catálogo) continuam funcionando sem alteração até serem migradas individualmente; `Panel` não deve ganhar novos consumidores.

---

# 6. Formulários

Nenhum formulário de criação/edição fica permanentemente renderizado na página ou expandindo uma linha de tabela. Padrão por complexidade:

- **Dialog** (`components/ui/dialog.tsx`) — formulários curtos (até ~5 campos, sem necessidade de navegação interna). Uso atual: Expansion. Game continua no formulário permanente anterior (`Panel`/`AdminToolbar`) — migração prevista para o Ciclo E, não uma exceção permanente: mesma lógica transitória já registrada para `Panel` na Seção 5.
- **Drawer** — reservado para formulários mais longos ou com conteúdo relacionado (Card Set, Card). Ainda não implementado — sem tela real que precise dele até este momento; construir apenas quando o ciclo vertical correspondente chegar.
- **Edição inline** (célula/linha, sem modal) — só para alterações de um único campo trivial, com justificativa registrada no próprio componente.

Todo Dialog controlado (`open`/`onOpenChange`, nunca `DialogTrigger` não controlado) quando o gatilho de abertura já vive em estado de página (`useAdminListState` ou equivalente). Durante o envio (`pending`), o Dialog ignora Esc e clique fora (`onEscapeKeyDown`/`onInteractOutside` com `preventDefault`) para não perder um envio em andamento. Confirmação de descarte de dados não salvos (digitados, não enviados) é uma melhoria deliberadamente adiada — reavaliar quando um formulário maior (Drawer de Card) tornar o custo de perda de dados mais alto.

---

# 7. Tabelas

`components/ui/data-table.tsx` fornece a mecânica comum (`DataTable`, `DataTableHead`, `DataTableHeadRow`, `DataTableHeadCell`, `DataTableRow`, `DataTableCell`) — não é uma DataTable genérica com ordenação/seleção/filtro embutidos; cada tela continua decidindo suas próprias colunas e dados. `DataTable` já embrulha a tabela em `overflow-x-auto` (rola horizontalmente dentro do card em vez de estourar a página) e `DataTableRow` já tem estado de `hover`, ambos por padrão — nenhuma tela precisa adicionar isso por conta própria. Ação de linha reaproveita `Button variant="outline" size="icon-sm"`, nunca um componente próprio. Linha recém-afetada por uma operação recebe destaque temporário (`DataTableRow highlighted`), coordenado por `useAdminListState`. Uma listagem com dados de mais de uma entidade-pai (ex.: Expansões, que pertencem a um Jogo) agrupa por essa entidade — grupos ordenados por nome, itens ordenados pelo campo relevante dentro do grupo, separador visual discreto (sem accordion/estado de expansão) — para não intercalar valores que só fazem sentido dentro do próprio grupo (ex.: "ordem de lançamento" é relativa a cada Jogo, não comparável entre Jogos).

Paginação real (cursor/offset) só é formalizada quando uma tela precisar dela de fato (hoje, só `UsersTable` tem uma versão própria, ainda não migrada para um primitive compartilhado).

---

# 8. Feedback e Estados

- **`InlineFeedback`** (`components/ui/feedback.tsx`) — sucesso/erro/aviso, inline. Baseline atual: nenhuma tela usa toast flutuante, para evitar depender de `@radix-ui/react-toast` sem necessidade comprovada — não é uma proibição permanente; ver Seção 10 para o critério de reavaliação. Substitui qualquer `<p className="text-destructive">` solto para erro de submissão.
- **`EmptyState`** (`components/ui/empty-state.tsx`) — estado vazio padrão de listas/tabelas.
- **`Skeleton`** (`components/ui/skeleton.tsx`) — bloco de carregamento (`animate-pulse`), para quando uma tela buscar dado no cliente (a maioria busca no servidor, antes da renderização, e não precisa dele).

---

# 9. Acessibilidade

Todo controle interativo tem rótulo acessível (`Label`+`htmlFor`, ou `aria-label` quando não há texto visível). Foco visível obrigatório (`:focus-visible`, já global em `globals.css`) — nunca removido via `outline: none` sem substituto. Dialog sempre com `DialogTitle` (Radix exige; nunca omitir). Navegação por teclado funcional em toda a `PrimaryRail`/`SecondaryPanel` (`group-focus-within` já cobre isso).

---

# 10. Em Aberto

- **Identidade visual/marca**: o app usa hoje arte do personagem Mimikyu (Pokémon) como logo/ícone (`brand-logo.tsx`/`brand-mark.tsx`), em tensão com o compromisso já registrado de que "Mimikyu" é um codinome interno, não uma marca pública confirmada. Pendente de decisão explícita de Fabrício — não resolvido por este Standard.
- **Drawer**: primitive ainda não construído — sem tela real que precise dele até este momento (ver Seção 6).
- **Paginação compartilhada**: ver Seção 7.
- **Toast flutuante**: decisão atual é não usar (Seção 8); reavaliar se um fluxo assíncrono mais longo justificar.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação — formaliza os padrões de navegação, composição de página, superfície (`Card`, absorvendo `Panel`), formulários (Dialog), tabelas e feedback estabelecidos na sessão de correção e sincronização de frontend de 2026-07-30 (Ciclos A-D), com Expansões como tela piloto. Área identificada como pendente desde a auditoria de 26/07 (`docs/README.md`, revisão `1.55`). |
| 1.1 | Correção pós-auditoria da tela piloto (Ciclos D.1-D.3, 2026-07-30). Seção 6: corrigido "uso atual: Game, Expansion" para apenas Expansion — Game continua no formulário permanente, migração fica para o Ciclo E, mesma lógica transitória já registrada para `Panel` (Seção 5). Seção 8: suavizada a redação de "nunca toast flutuante" para refletir que é a baseline atual, não uma proibição permanente (a ressalva de reavaliação já existia na Seção 10, mas não no corpo normativo). Seção 7: documentados `overflow-x-auto` e `hover` como padrão de `DataTable`/`DataTableRow`, e o agrupamento por entidade-pai como padrão de apresentação para listagens com essa relação. |
