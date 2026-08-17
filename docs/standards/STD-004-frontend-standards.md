# STD-004 — Frontend Standards

| Campo | Valor |
|--------|-------|
| **Documento** | STD-004 |
| **Título** | Frontend Standards |
| **Versão** | 1.6 |
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

`components/` é organizado por domínio de produto (`catalogo/`, `pesquisa/`, `auth/`, `app-shell/`, `ui/` para primitives puros) — mais um domínio novo, **`card/`** (2026-08-17, `ADR-030` revisão `1.3`): componentes de apresentação de carta genuinamente compartilhados entre duas ou mais telas de domínios diferentes (hoje `/catalogo/cartas` e `/pesquisa`), sem qualquer prop ou lógica exclusiva de um domínio específico. Critério para um componente entrar em `components/card/` em vez de morar dentro de um domínio: ser consumido por mais de um domínio E não receber props de edição/ativação/importação/filtros administrativos/Pricing/Collection — no primeiro sinal de acoplamento a um domínio, o componente deve voltar a morar dentro dele.

---

# 2. Tokens e Tema

Cores, tipografia e raio de borda vivem como CSS variables em `app/globals.css` (blocos `:root`/`.dark`), conectadas às classes utilitárias do Tailwind via `tailwind.config.ts`. Nenhuma cor literal (`#hex`, `rgb()`) fora desses dois arquivos (exceção registrada: as folhas de impressão da Central de Relatórios, ver nota no fim desta seção) — todo componente consome os tokens semânticos (`bg-surface`, `text-muted-foreground`, `border-border`, etc.), nunca uma cor bruta.

**Arquitetura cromática (2026-08-16)** — validada em três rodadas de prova visual isolada em Catálogo Editorial > Visão Geral ("onyx-preview") e promovida a baseline de toda a aplicação autenticada:

- **Workspace** (conteúdo — `--background`/`--surface`/`--surface-muted`/`--border`/`--input`/`--foreground`/`--muted-foreground`) inverte por tema: off-white contemporâneo no claro, preto/grafite profundo no escuro. Cards, tabelas, painéis, modais e demais superfícies herdam esses tokens sem escopo adicional.
- **Navegação** (`PrimaryRail`/`SecondaryPanel`) é uma âncora fixa da identidade — permanece escura nos dois temas, não inverte com o workspace. Mecanismo: as classes `.app-nav-rail`/`.app-nav-panel` (`app/globals.css`) sobrescrevem LOCALMENTE os mesmos tokens genéricos (`--surface`/`--border`/`--foreground`/`--muted-foreground`/etc.) — qualquer componente compartilhado renderizado dentro da navegação (`SidebarFooter`, por exemplo) herda o tratamento escuro automaticamente via as mesmas classes Tailwind de sempre, sem precisar de edição própria. Só o indicador de item ativo/seleção tem tokens dedicados sem equivalente genérico: `--nav-gold`, `--nav-active-surface`, `--nav-active-ink`, `--nav-panel-active-surface`.
- **`--primary`** deixou de ser um tom bege dessaturado e passa a ser o dourado real da marca (mesmo valor de `--auth-accent` na Auth Experience) — accent color (CTA, foco, indicadores, seleção), nunca cor dominante de texto corrido ou de grandes áreas.
- **`--primary-ink`** — tom de dourado mais escuro/legível, específico para uso como COR DE TEXTO (links, nomes em destaque, ícones pequenos sobre fundo claro); `--primary` puro tem contraste insuficiente como texto sobre o workspace off-white. Distinção direta de `--auth-accent`/`--auth-accent-ink` já validada na Auth Experience — nunca usar `text-primary` para texto corrido, sempre `text-primary-ink`.
- **`--accent`** é neutro (wash quente sem tingimento dourado) — evita que duas cores de marca (accent + primary) compitam entre si.
- **`--destructive`/`--success`/`--warning`** nunca são tocados por essa arquitetura — permanecem os únicos portadores de estado semântico; dourado nunca substitui cor de estado.

**Tokens de controle de formulário (2026-08-16)** — `--control-surface`/`--control-border`/`--control-muted-foreground`/`--control-radius`, dedicados e distintos de `--surface`/`--border`/`--muted-foreground`/`--radius` genéricos (que também respondem por cards/tabelas/dialogs — alterá-los diretamente teria efeito colateral fora do escopo de formulário). Valores herdados byte-a-byte do padrão já aprovado no Login (antigos `--auth-form-surface`/`--auth-form-line`/`--auth-form-ink-muted`); não existe `--control-foreground` nem token de foco dedicado porque esses já eram idênticos a `--foreground`/`--primary` — sem necessidade de duplicar. `Input` e `Select` (ver Seção 6) são os únicos consumidores; `auth-tokens.module.css` (`.scope`) hoje aliasa `--auth-form-surface`/`--auth-form-ink`/`--auth-form-ink-muted`/`--auth-form-line`/`--auth-radius-control` para esses mesmos tokens globais (`var(--control-*)`) em vez de duplicar valor — Login e formulários internos consomem literalmente a mesma variável CSS resolvida pela cascata, em claro e escuro. Isolamento do namespace `--auth-*` preservado só para o que é genuinamente exclusivo da Auth Experience (`--auth-page`, `--auth-hero-*`, `--auth-accent*`, `--auth-ease-signature`).

Exceção registrada de cor literal: as folhas de impressão da Central de Relatórios (`app/catalogo/relatorios/*`, `RelatorioFolha`/`RelatorioCabecalho`/`RelatorioRodape`) usam cor fixa (`#FFFFFF`/`#F7F5ED`/`#F0EEE3`) deliberadamente — são documentos pensados para impressão em papel A4, sempre claros independente do tema da tela, aprovados por Fabrício em 2026-08-09 ("Checklist por Coleção... Visualmente excelente"). Fora do escopo da arquitetura cromática de tela — não devem ser alteradas para seguir claro/escuro.

Tipografia: Inter (`--font-sans`, corpo e navegação), Manrope (`--font-heading`, exclusivo para `PageTitle`/títulos de página), Geist Mono (`--font-mono`). Claro/escuro via `next-themes`, alternância manual sempre visível (`ThemeToggle`) — nunca só a preferência do sistema.

---

# 3. Navegação

Duas camadas, sem alteração de interação prevista (ver `components/app-shell/`):

- **`PrimaryRail`** — trilha compacta e fixa (`w-14`, reduzida de `w-16` em 2026-08-16), só ícones, rigorosamente centralizados no estado recolhido (o rótulo usa `w-0`/`flex-none` em vez de `flex-1` com opacidade zero, que ocupava espaço de layout e descentralizava o ícone); expande no hover/focus (`group-hover`/`group-focus-within`, CSS puro, sem JS) revelando o rótulo. Sempre escura (`.app-nav-rail`, ver Seção 2), nos dois temas. Um item por módulo (`NAV_SECTIONS`, `nav-config.ts`), nunca por página individual.
- **`SecondaryPanel`** — coluna contextual, aparece só quando a seção ativa tem `children`; agrupa itens por `section` (título maiúsculo + divisória) quando o módulo tiver mais de um agrupamento lógico. Mesma âncora escura (`.app-nav-panel`), um degrau de luminosidade sutilmente diferente da rail para as duas colunas continuarem distinguíveis entre si.
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

**Referência visual (2026-08-16)**: os componentes de formulário (`Input`, `Select`, `Label`, links, botão primário) seguem o tratamento visual aprovado no Login (`components/auth/`) — radius, contraste, espaçamento, e principalmente o estado de foco (borda + halo de 3px em baixa opacidade na cor de destaque, sem offset, em vez do anel sólido com offset genérico). `Button variant="default"` usa o mesmo CTA em gradiente dourado animado do botão "Entrar" (`components/ui/button-cta.module.css`, extraído de `components/auth/auth-panel.module.css`, ambos consumindo os mesmos tokens globais — sem duplicar valores literais). Isso não significa copiar dimensões: o Login é um formulário hero de tela cheia, o backoffice é UI densa/tabular — altura padrão de controles internos (`h-9`) permanece distinta da Auth (`h-11`, via `authInputClassName`); só a LINGUAGEM visual (cor, foco, precisão) é compartilhada, nunca a dimensão. Variantes de densidade legítimas continuam preservadas onde já existiam (filtros compactos com seta própria em `catalogo-filter-select.tsx`/`log-atualizacoes-filtros.tsx`/`relatorio-colecao-seletor.tsx`, `h-9`/`text-xs`/`bg-surface-muted` em `cartas-gallery.tsx`) — a regra é mesma linguagem visual + densidade apropriada ao contexto, não dimensão idêntica em todo lugar.

**`Select` compartilhado (2026-08-16)**: `components/ui/select.tsx` — primitive novo, `<select>` nativo (sem lib adicional; o objetivo era governança visual, não substituir por um componente complexo), visualmente alinhado a `Input`: mesmos tokens de controle (`--control-*`, ver Seção 2), mesmo `rounded-control`, mesma lógica de borda/foco/disabled, prop `invalid` com o mesmo contrato de `Input` (borda + halo destrutivo, sempre depois de `className` na composição de `cn()` — corrige uma ordem antiga em que um `className` de consumidor podia silenciosamente sobrepor o estado de erro). Todos os 18 usos reais de `<select>` cru identificados no repositório foram migrados para `Select`, preservando integralmente `value`/`defaultValue`/`onChange`/`name`/`disabled`/opções/validações/Server Actions. Exceção documentada e fora do escopo: `importar-cartas-view.tsx` usa `CardSetCombobox`, componente próprio, por decisão de produto anterior (conteúdo de opção em duas linhas, não cabe num `<select>` nativo) — não migrado, nunca foi um `<select>` cru.

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
- **`Textarea` compartilhado**: ainda não extraído — nenhuma tela hoje usa `<textarea>` com volume suficiente para justificar um primitive dedicado (diferente de `<select>`, resolvido em 2026-08-16, ver Seção 6). Candidato a um próximo incremento, caso surja um formulário real que precise dele.
- **`Panel` vs. `Card density="compact"`**: a Seção 5 já registrava `Panel` como descontinuado para uso em telas novas, com Jogos/Visão Geral como os consumidores remanescentes a migrar "individualmente". Como `Panel` já é inteiramente token-based, a promoção do baseline cromático desta versão não exigiu tocá-lo — a migração para `Card` continua uma decisão de organização de código, não uma pendência visual.

---

# 11. Pesquisa Global de Cartas — combobox e página com filtros via URL

Introduzido em 2026-08-17 (Incremento "Pesquisa Global de Cartas", `ADR-030`) — primeiro combobox real do projeto e primeira página com estado inteiramente derivado da URL.

**Combobox do header (`components/app-shell/global-search.tsx`)**: padrão ARIA combobox/listbox por `aria-activedescendant` — o foco do DOM nunca sai do `<input>`; a opção "ativa" é só uma marcação visual + `aria-activedescendant` apontando para o `id` do `<li role="option">`, nunca `focus()` programático no item. Evita qualquer conflito de foco entre o campo de texto e o botão interno de pesquisa avançada (`SlidersHorizontal`, `aria-label="Abrir pesquisa avançada"`). Desktop: campo inline centralizado no header (`flex-1` entre os grupos de título e ações, que continuam `shrink-0` — nenhum dos dois se desloca). Mobile: não comprime o campo completo no header — um botão de ícone (`md:hidden`) abre um overlay dedicado (Radix Dialog, topo da tela) com o mesmo combobox em tamanho real.

**Página com filtros via URL (`app/pesquisa/`)**: `q`/`card`/`set`/`category`/`rarity` são a única fonte de verdade do estado — a página não mantém estado de filtro em `useState` independente da URL (só o valor do campo de texto, para permitir digitação fluida antes do debounce escrever na URL). Qualquer alteração de filtro sempre passa por `router.replace()`, nunca `router.push()` (não polui o histórico a cada tecla/seleção). **Sem filtro de Jogo nesta versão** — decisão de escopo explícita, corrigida em 2026-08-17 (mesma data, rodada de aceite): a v1.4 desta seção descrevia incorretamente um filtro de Jogo escopando Card Set/Categoria/Raridade, nunca aprovado para esta versão; removido da URL, do contrato público (`search_cards`/`search_card_filter_options`, ver `ADR-030` revisão `1.1`) e da UI.

**Preview de carta estruturalmente compartilhado com `Cartas` (2026-08-17, mesmo dia, correção de UX)**: o zoom de carta em `/pesquisa` deixou de ser um `Dialog` genérico com rodapé de texto e passou a usar exatamente os mesmos componentes do preview aprovado de `/catalogo/cartas` — `CardImagePreview`/`CardPreviewOverlay` (`components/card/`, ver Seção 1) e `web/lib/view-transitions.ts`. Mesmo `HoloCard` (motion senoidal via `requestAnimationFrame`, `prefers-reduced-motion` já respeitado), mesmo backdrop/sombra, mesmo morph por View Transitions API a partir da miniatura do grid quando disponível, sem rodapé de nome/Card Set/raridade (o preview oficial de `Cartas` nunca teve um). Ver `ADR-030` revisão `1.3` para o racional completo da extração. `CartaZoomDialogReadOnly` (hub de Card Set, `card-set-cartas-grid.tsx`) permanece uma terceira implementação não unificada — candidato a uma futura consolidação, não resolvido nesta rodada.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação — formaliza os padrões de navegação, composição de página, superfície (`Card`, absorvendo `Panel`), formulários (Dialog), tabelas e feedback estabelecidos na sessão de correção e sincronização de frontend de 2026-07-30 (Ciclos A-D), com Expansões como tela piloto. Área identificada como pendente desde a auditoria de 26/07 (`docs/README.md`, revisão `1.55`). |
| 1.1 | Correção pós-auditoria da tela piloto (Ciclos D.1-D.3, 2026-07-30). Seção 6: corrigido "uso atual: Game, Expansion" para apenas Expansion — Game continua no formulário permanente, migração fica para o Ciclo E, mesma lógica transitória já registrada para `Panel` (Seção 5). Seção 8: suavizada a redação de "nunca toast flutuante" para refletir que é a baseline atual, não uma proibição permanente (a ressalva de reavaliação já existia na Seção 10, mas não no corpo normativo). Seção 7: documentados `overflow-x-auto` e `hover` como padrão de `DataTable`/`DataTableRow`, e o agrupamento por entidade-pai como padrão de apresentação para listagens com essa relação. |
| 1.2 | **Consolidação visual MMKYU — a direção cromática da Visão Geral e o padrão de formulário do Login viram baseline (2026-08-16).** A arquitetura preto/off-white/dourado, testada em 3 rodadas de prova visual isolada só em Catálogo Editorial > Visão Geral ("onyx-preview"), foi aprovada por Fabrício e propagada para TODAS as páginas internas via consolidação de tokens globais (`app/globals.css`) — não por edição individual de cada tela. Seção 2: workspace (conteúdo) inverte por tema (off-white claro / preto-grafite profundo escuro); navegação é âncora fixa, sempre escura, via classes de escopo `.app-nav-rail`/`.app-nav-panel` que sobrescrevem localmente os tokens genéricos (mesmo mecanismo que `SidebarFooter` e qualquer componente compartilhado dentro da navegação já herdam sem edição própria); `--primary` passa a ser o dourado real da marca (accent, não cor dominante); `--primary-ink` (novo) é o tom de texto legível, distinto do `--primary` decorativo; `--accent` perde tingimento dourado; estados semânticos (`--destructive`/`--success`/`--warning`) nunca tocados. Seção 3: `PrimaryRail` de `w-16` para `w-14`, ícones rigorosamente centralizados no estado recolhido. Seção 6: componentes de formulário (Input, botão primário) seguem o tratamento visual aprovado no Login — `Button variant="default"` passa a usar o mesmo CTA em gradiente dourado (`ui/button-cta.module.css`, extraído de `auth-panel.module.css`, tokens globais em vez de duplicar valores); `Input` troca o anel de foco sólido com offset pelo halo suave sem offset do Login. Mecanismo por CSS Module condicional da prova (`onyx-preview.module.css`, prop `chromeVariant`/`preview` em `AppShell`/`Sidebar`/`PrimaryRail`/`SecondaryPanel`/`StatCard`/`CardSetsTable`/`AtividadeRecente`) foi removido — não é mais opcional. Exceção registrada: folhas de impressão da Central de Relatórios (`app/catalogo/relatorios/*`) mantêm cor literal fixa, fora do escopo (documentos sempre claros, independente do tema da tela). Pendências abertas na Seção 10: `Select`/`Textarea` compartilhados (~9 telas com `<select>` nativo repetido). |
| 1.3 | **Select vira primitive compartilhado; tokens de controle de formulário promovidos a globais (2026-08-16, mesmo dia, rodada seguinte).** Pendência da Seção 10 (v1.2) resolvida. Seção 2: novos tokens dedicados `--control-surface`/`--control-border`/`--control-muted-foreground`/`--control-radius`, derivados byte-a-byte do padrão já aprovado no Login, distintos de `--surface`/`--border`/`--radius` genéricos para não afetar cards/tabelas/dialogs; `auth-tokens.module.css` (`.scope`) passa a aliasar `--auth-form-surface`/`--auth-form-ink`/`--auth-form-ink-muted`/`--auth-form-line`/`--auth-radius-control` para esses tokens globais em vez de duplicar valor — Login e formulários internos resolvem a mesma variável CSS pela cascata; isolamento do namespace `--auth-*` preservado só para o genuinamente exclusivo da Auth (`--auth-page`, `--auth-hero-*`, `--auth-accent*`, `--auth-ease-signature`). Seção 6: `components/ui/select.tsx` criado — `<select>` nativo (sem lib), mesmos tokens/radius/foco/disabled de `Input`, prop `invalid` com o mesmo contrato; corrigida também em `Input` uma ordem latente de `cn()` em que `className` do consumidor podia sobrepor silenciosamente o estado `invalid` (agora `invalid` sempre resolve por último). 18 ocorrências reais de `<select>` cru migradas para `Select` em 10 arquivos (contagem corrigida do diagnóstico original, que por um padrão de grep restrito a tags multi-linha havia contado 17), preservando `value`/`onChange`/`name`/validações/Server Actions integralmente; variantes de densidade legítimas mantidas via composição de `className` (filtros compactos com seta própria, densidade de galeria). `CardSetCombobox` (`importar-cartas-view.tsx`) confirmado fora do escopo — nunca foi `<select>` cru. Seção 10: pendência de `Select` removida; `Textarea` compartilhado permanece em aberto (nenhum uso real ainda). |
| 1.4 | **Nova Seção 11 — Pesquisa Global de Cartas (2026-08-17, ver `ADR-030`).** Primeiro combobox real do projeto (`components/app-shell/global-search.tsx`, header autenticado) — padrão ARIA por `aria-activedescendant`, nunca move o foco do DOM para as opções; desktop inline centralizado sem deslocar título/ações, mobile via overlay dedicado (nunca comprime o campo no espaço do header). Primeira página com estado 100% derivado da URL (`app/pesquisa/`) — filtros sempre via `router.replace()`, nunca `push()`; troca de Jogo limpa filtros dependentes (Card Set/Categoria/Raridade), mesmo princípio já usado em `/catalogo/cartas`. Zoom de carta em `/pesquisa` usa o `Dialog` genérico da Seção 6, não a transição View Transitions de `CartaZoomDialog` — candidato a unificação futura, registrado como não resolvido. |
| 1.5 | **Correção de escopo — remoção do filtro de Jogo (2026-08-17, mesmo dia, rodada de aceite).** A Seção 11 (v1.4) descrevia um filtro de Jogo na página `/pesquisa` (URL `game`, select "Todos os jogos", escopando Card Set/Categoria/Raridade), nunca aprovado para esta versão — divergência identificada em revisão de aceite por Fabrício. Corpo da Seção 11 corrigido: URL passa a ser `q`/`card`/`set`/`category`/`rarity`; select de Jogo removido de `pesquisa-view.tsx`; opções de filtro (`search_card_filter_options`, ver `ADR-030` revisão `1.1`) carregadas uma única vez, sem escopo por Jogo. Nenhuma mudança nos demais padrões desta seção (combobox do header, `router.replace()`, `Dialog` de zoom). |
| 1.6 | **Preview de carta estruturalmente compartilhado entre `Cartas` e `Pesquisa` (2026-08-17, mesmo dia, correção de UX pedida por Fabrício) — nova convenção de pasta `components/card/`.** Seção 1: documentado o domínio `components/card/` (componentes de apresentação de carta reutilizados por mais de um domínio, sem qualquer prop administrativa) — primeiro consumidor do critério. Seção 11: substituído o parágrafo desatualizado "Zoom de carta simplificado" (que descrevia `/pesquisa` usando um `Dialog` genérico sem a transição de `Cartas`) — `/pesquisa` passa a consumir exatamente `CardImagePreview`/`CardPreviewOverlay` (`components/card/`) e `web/lib/view-transitions.ts`, os mesmos artefatos agora extraídos de `CartaZoomDialog` (`cartas-gallery.tsx`, fonte oficial). Nenhuma fórmula/constante do motion senoidal (`HoloCard`, movido — não recriado — de `components/catalogo/` para `components/card/`) foi copiada manualmente; `prefers-reduced-motion` já era respeitado antes desta rodada, sem alteração. `CartaZoomDialogReadOnly` (hub de Card Set) permanece fora do escopo, registrado como consolidação futura. Ver `ADR-030` revisão `1.3` para o racional completo. |
