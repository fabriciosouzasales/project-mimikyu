---
name: mmkyu-frontend-experience
description: Repertório oficial de frontend do MMKYU Collector — consultar sempre que for adicionar um componente novo, resolver um padrão de interação (galeria de Collections, quick actions, detalhe de carta, drawer mobile, etc.), avaliar uma biblioteca ainda não mapeada, ou decidir entre alternativas de UX client-facing. Não usar para decisões de backend/dados, nem para reabrir o Binder fechado sem pedido explícito.
---

# MMKYU Frontend Experience

Esta skill é o vocabulário oficial de frontend do MMKYU Collector. Ela existe para que qualquer decisão de UI nova comece pelo que já foi pesquisado e aprovado — não do zero, e não copiando a aparência de uma referência externa.

Fonte completa da pesquisa que originou esta skill: `MMKYU-FRONTEND-REPERTOIRE-DRAFT.md` (raiz do repositório) — Revisão 2, aprovada por Fabrício em 2026-08-29. Esta skill resume o que é estável; a curadoria guarda o raciocínio completo.

---

## 1. Como consultar esta skill

Antes de propor qualquer UI nova, seguir esta ordem:

1. **Foundation Stack (seção 2)** — checar se já existe uma ferramenta técnica aprovada para o que se precisa construir. Nunca escolher uma dependência nova sem antes checar se já existe uma equivalente disponível ou aprovada.
2. **Core Experience Set (seção 3)** — checar se o problema de UX já tem um padrão mapeado. O vocabulário já existente é o primeiro lugar a olhar, não o último.
3. **Avoid List (seção 4)** — checar se o caminho cogitado já foi descartado antes de investir tempo nele.
4. **Se nenhum dos 8 patterns do Core Experience Set cobrir adequadamente o problema, consultar o Experience Repertoire completo no documento de curadoria** (`MMKYU-FRONTEND-REPERTOIRE-DRAFT.md`, seção 2) **antes de pesquisar ou inventar uma solução nova.** O Experience Repertoire completo não é duplicado aqui — mora só na curadoria.

Só depois desses quatro passos considerar uma solução genuinamente nova — e, mesmo assim, aplicando as regras de comportamento da seção 5.

---

## 2. Foundation Stack

Ferramentas e primitivos técnicos: resolvem *como construir*, não *como a experiência deveria parecer*. Consultar esta camada só para decisão técnica, nunca para decisão estética.

| Ferramenta | Papel técnico | Regra de adoção |
|---|---|---|
| **Radix UI (existente)** | Primitivos já em uso (`Dialog`, `Tooltip`, `Collapsible`, `Slot`) | Continua em uso enquanto funcionar. Sem migração automática para Base UI (ver regra de convivência abaixo). |
| **Base UI** | Sucessor oficial do Radix, default do shadcn desde jul/2026 | Considerar para **componentes novos**. Migrar um componente Radix existente só com benefício funcional claro e específico — nunca por preferência de stack. |
| **cmdk (Command)** | Motor de busca/paleta com fuzzy match e teclado | USE — sem substituto melhor identificado para Card Picker/busca global. |
| **Sonner** | Toast/feedback assíncrono | USE — padrão de fato no ecossistema shadcn/Base UI. |
| **dnd-kit** | Drag-and-drop acessível (teclado/touch/leitor de tela) | USE quando Drag and Drop entrar em pauta — não instalar antecipadamente sem uma tela que precise dele. |
| **Motion (ex-Framer Motion)** | Motor de animação JS | Motor preferencial quando animação for necessária, **não é dependência automática** — CSS/View Transitions primeiro (ver regra de uso abaixo). |
| **View Transitions API (nativa)** | Transições de navegação/estado, zero dependência | Primeira opção sempre que suficiente. |
| **Origin UI** | Registry de formulários/inputs copy-paste | ADAPT pontual (Add/Replace Card, filtros, bulk onboarding) — não importar em bloco. |
| **Kibo UI** | Componentes compostos com lógica (upload, multi-step) | ADAPT pontual para Bulk Onboarding. |
| **use-gesture** | Primitivos de gesto (drag/pinch/swipe) de baixo nível | ADAPT quando o gesto físico do binder/card entrar em pauta. |
| **Vaul** | Drawer/bottom sheet | **REFERENCE ONLY** — não mantido ativamente (o próprio shadcn/ui migrou seu `Drawer` para Base UI por esse motivo). Substituto primário: Drawer nativo do Base UI. Alternativa de transição: `vaul-base`. |
| **GSAP** | Motor de animação JS (dependência confirmada do React Bits Depth Carousel) | **Não autorizado a instalar.** Confirmado no discovery COLLECTION-GALLERY-01 (2026-08-29) como dependência real do Depth Carousel. O spike COLLECTION-GALLERY-SPIKE-01 (2026-08-29) decidiu que Premium Grid/List vence para Collection Library — Depth Carousel (e portanto GSAP) fica fora dessa tela, preservado só como referência futura para Social Showcase/Profile. Introduzir GSAP junto de "Motion" seria misturar duas bibliotecas de motion — ver Avoid List. |
| **`@designcodeio/threeui`** | Pacote real do ThreeUI (Meng To/Design+Code), MIT — confirmado instalado para os spikes Complete Shelf, Character Wave e Character Filmstrip (2026-08-29) | **Não autorizado para produção sem aprovação explícita.** Tier misto dentro do próprio pacote: `CompleteShelfLandingPage` é Tier C (Three.js/WebGL real, iframe pesado) — fora da Collection Library. `CharacterWave`/`CharacterFilmstrip` são Tier A (DOM + CSS 3D puro, zero Three.js/WebGL/GSAP, zero CDN externo). **`CharacterFilmstrip` + skin "Binder MMKYU" é o engine aprovado do modo Carrossel da Collection Library** (fechamento 2026-08-29 — reversão do veredito anterior, ver Core Experience Set pattern #1 e curadoria seção 13). Ver Core Experience Set, pattern #1, para status completo por variante e por contexto. |

**Regra de convivência Base UI / Radix:** componentes Radix existentes não são reescritos por iniciativa própria. Base UI é o caminho para componentes novos. Migração de um componente existente exige um motivo funcional concreto (ex.: bug ou lacuna de acessibilidade que o Radix não resolve).

**Regra de uso do Motion:** (1) CSS puro / View Transitions API primeiro, sempre que a animação for simples o suficiente (fade, slide, layout shift pontual, transição de navegação); (2) Motion só entra com ganho real de UX que CSS/View Transitions não entregam de forma razoável (orquestração de múltiplos elementos, gestos combinados com animação, `layout` animation automática em listas imprevisíveis); (3) qualquer adoção de Motion (ou de algo que dependa dele) exige uma frase curta por escrito justificando por que CSS/View Transitions não bastam.

---

## 3. Core Experience Set

Vocabulário de padrões de experiência — **não são dependências obrigatórias por si só**, são o repertório a consultar antes de inventar uma solução nova.

| # | Pattern | Problema que resolve | Componentes/fontes candidatas | Tier | Quando usar | Quando NÃO usar |
|---|---|---|---|---|---|---|
| 1 | **Collection Library — 3 modos oficiais (Lista/Cards/Carrossel)** | Apresentar "Minhas Collections" — **FECHADO em 2026-08-29** (COLLECTION-LIBRARY-VIEW-MODES-01): três modos oficiais, mesmo núcleo de informação (Binder, nome, código, progresso), variando só densidade/apresentação | **Lista** (`CollectionListView`) = `USE`, modo compacto operacional. **Cards** (`PremiumGrid`) = `USE`, **modo padrão inicial**, base do spike COLLECTION-GALLERY-SPIKE-01. **Carrossel** = `USE`, Character Filmstrip (ThreeUI, Tier A) + skin "Binder MMKYU" — exploração visual/premium, Binder como protagonista. Character Wave = `REFERENCE ONLY` para esta tela (não foi o escolhido; segue `ADAPT CANDIDATE` só para Social/Profile). Depth Carousel, Circular Gallery, Complete Shelf: sem mudança, `REFERENCE ONLY`. Hero Card/Hero Artwork: testados e descartados, `AVOID` | A | Sempre, para "Minhas Collections" — Cards por padrão; Lista para muitas Collections/escaneabilidade; Carrossel para poucas/médias/exploração visual | Não criar um quarto modo sem pedido explícito |
| 2 | **Hero Object Stage** | Apresentar um objeto único como protagonista | Já resolvido — CSS 3D próprio do MMKYU (Binder fechado, baseline aprovado) | A | Objeto singular que merece protagonismo total | O "objeto" é na verdade uma lista/coleção — aí é Collection Gallery |
| 3 | **Contextual Quick Actions** | Ação rápida sem sair do contexto do slot/card | Cult UI (botão→painel) | A | Ações de 1-2 passos ligadas a um item específico visível na tela | Fluxos de múltiplas etapas — aí é um Dialog/Drawer completo |
| 4 | **Card Detail Overlay** | Revelar detalhe completo de uma carta | Base UI Dialog (desktop) / Base UI Drawer (mobile) | A | Usuário pede "ver mais" sobre um item específico | Informação cabe inteira no hover/tooltip — não precisa de overlay |
| 5 | **Card Picker** | Buscar e selecionar uma carta para Add/Replace | cmdk | A | Fluxo que exige encontrar uma carta específica entre muitas | Listas curtas (menos de ~10 itens) — um select simples resolve |
| 6 | **DnD Layout Manipulation** | Reorganizar cartas/slots manualmente | dnd-kit | A | Usuário precisa definir ordem própria (Wishlist, slots do binder) | Ordem sempre derivada de critério automático (data, raridade) |
| 7 | **Progress/Celebration Feedback** | Comunicar avanço e marcos | Sonner + confete pontual | A/B | Eventos reais de conclusão (Set 100%, import finalizado) | Nunca em ações rotineiras — perde o efeito e vira ruído |
| 8 | **Mobile Contextual Surface** | Ação ou detalhe em contexto no celular | Base UI Drawer | A | Telas pequenas, ação ligada a um item visível | Desktop — lá o Dialog/overlay já resolve melhor |

**Nota sobre o pattern #1 (Collection Library) — FECHAMENTO FINAL 2026-08-29:** a frente visual da Collection Library está encerrada. Três modos oficiais — Lista, Cards, Carrossel — mesmo dataset, mesmo núcleo de informação, seletor `[Lista][Cards][Carrossel]` (nomenclatura final ao usuário, sem termos internos). Cards é o padrão inicial. O caminho até aqui: spike COLLECTION-GALLERY-SPIKE-01 (Premium Grid/List venceu a Visual Gallery, seção 4/11 da curadoria) → discovery ThreeUI (seção 12) → avaliação visual COLLECTION-WAVE-SPIKE-01 (Wave × Filmstrip × Grid) → COLLECTION-FILMSTRIP-BINDER-FIDELITY-01 e COLLECTION-FILMSTRIP-HERO-COVER-01 (Filmstrip com skin "Binder MMKYU", Hero Card/Hero Artwork testados e descartados) → consolidação COLLECTION-LIBRARY-VIEW-MODES-01. **Reversão registrada explicitamente**: `Character Filmstrip`, classificado `AVOID` para Collection Library no discovery técnico (nota abaixo), foi revertido para `USE` depois de avaliação visual direta com a skin "Binder MMKYU" — ver curadoria seção 13 para o racional completo da divergência. Não reabrir Hero Card/Hero Artwork/Complete Shelf/Wave para esta tela, nem criar um quarto modo, sem pedido explícito novo de Fabrício. Detalhamento completo na curadoria, seção 13.

**Nota ThreeUI — Complete Shelf e Character Carousel (2026-08-29, discovery técnico original — status revisado pela nota acima):** `Complete Shelf` permanece fora da Collection Library (Tier C, Three.js/WebGL real) — `REFERENCE ONLY`, preservado para uma eventual experiência de showcase/social futura, mesmo destino do Depth Carousel. Dentro da família `Character Carousel` do mesmo pacote existem só duas variantes reais — `Character Wave` e `Character Filmstrip` (`Character Carousel` sem `variant` explícito é o próprio Filmstrip, não uma terceira variante base; confirmado tanto no código-fonte quanto na descrição oficial do produto). Neste discovery original, `Character Wave` havia sido classificado `ADAPT CANDIDATE` e `Character Filmstrip` `AVOID` para Collection Library — **esse veredito foi revertido pela avaliação visual posterior** (ver nota acima): `Character Filmstrip` + skin "Binder MMKYU" é hoje `USE` para o modo Carrossel; `Character Wave` passou a `REFERENCE ONLY` para esta tela. Para Social/Profile e Pokédex/Favorites, sem mudança: `Character Wave` `ADAPT CANDIDATE`, `Character Filmstrip` `REFERENCE ONLY`. Nenhuma variante nova da família ou do ThreeUI será pesquisada sem pedido explícito. Detalhamento completo na curadoria, seções 12 e 13.

---

## 4. Avoid List

- **Vanta.js / tsParticles** como fundo decorativo.
- **Spline** em produção.
- **Aceternity UI** como base ampla (componentes pontuais isolados continuam permitidos).
- **Uiverse.io** como fonte sistemática.
- Misturar duas bibliotecas de motion (Motion + GSAP) sem necessidade.
- **React Bits — Glass Surface, Lightfall, Side Rays**: efeitos decorativos sem caso de uso MMKYU; Glass Surface, especificamente, conflita esteticamente com o couro/analógico já estabelecido no Binder.
- Usar o catálogo do React Bits como identidade visual inteira (texto que se monta, partículas de impacto, "screenshot-bait") — componentes individuais com aderência real continuam permitidos, ver Core Experience Set e curadoria seção 3.

---

## 5. Regras de comportamento

1. **Consultar primeiro o Foundation Stack** para saber que ferramenta técnica já está disponível ou é o caminho oficial — nunca escolher uma ferramenta nova sem checar se já existe uma aprovada.
2. **Consultar o Experience Repertoire/Core Experience Set** antes de inventar uma solução de UI do zero — o vocabulário já mapeado é o primeiro lugar a olhar, não o último.
3. **Preferir padrões já aprovados** (Core Experience Set) sobre soluções novas, salvo quando o problema genuinamente não se encaixa em nenhum dos 8.
4. **Adaptar a estética ao MMKYU sempre** — nunca copiar a aparência de origem de uma biblioteca (cores, tipografia, densidade) sem passar pelo vocabulário visual já estabelecido no Binder e no Design System.
5. **Nunca copiar aparência de referência 1:1** — bibliotecas como Aceternity/React Bits são fonte de mecânica/comportamento, não de skin.
6. **Justificar qualquer Tier B por escrito** — uma frase objetiva de por que CSS/View Transitions não bastam, antes de propor Motion ou qualquer dependência de motion.
7. **Exigir aprovação explícita de Fabrício para qualquer Tier C** — WebGL/Three/OGL pesado nunca entra por iniciativa própria da skill, mesmo que um candidato pareça visualmente superior.
8. **Preservar performance, mobile e acessibilidade como critério de corte**, não como checklist posterior — um candidato que falha aqui é descartado antes de chegar à comparação estética.
9. **Nunca reabrir um baseline já aprovado sem pedido explícito** — referenciar a memória/documentação da aprovação em vez de propor mudanças por conta própria (ver seção 6).

### Regra adicional de governança (instalação de dependências)

Esta skill orienta decisões de frontend, mas **NÃO constitui autorização para instalar novas dependências**.

- **Tier A**: ainda deve verificar se a dependência já existe e se é realmente necessária.
- **Tier B**: exige justificativa objetiva de UX antes de propor instalação.
- **Tier C**: exige aprovação explícita de Fabrício antes de qualquer instalação ou implementação.
- **Nenhuma biblioteca deve ser instalada apenas porque aparece como candidata nesta skill.**

---

## 6. Regra de baseline aprovado

Lista de superfícies visuais fechadas — não reabrir nem propor redesenho sem pedido explícito de Fabrício. Formato de lista, pensado para crescer conforme mais telas forem aprovadas:

- **Binder fechado** (`web/components/experimental/binder-nav-01/binder-cover-closed.tsx`) — aprovado como baseline em 2026-08-29, após 23 rodadas de polimento visual. Pequenos ajustes futuros pontuais são aceitáveis; redesenho ou reabertura da discussão visual, não, salvo pedido explícito.
- **Collection Library — três modos oficiais (Lista, Cards, Carrossel)** (`web/components/experimental/collection-library-view-modes-01/`) — aprovado como baseline em 2026-08-29, ver curadoria seção 13. Lista e Cards em React (`collection-list-view.tsx`, `collection-gallery-spike-01/premium-grid.tsx`); Carrossel = Character Filmstrip (ThreeUI) + skin "Binder MMKYU" (`public/ui-elements/collection-library-carousel-mmkyu-*.html`). Cards é o modo padrão. Não criar quarto modo, não reabrir Hero Card/Hero Artwork/Complete Shelf/Wave para esta tela, sem pedido explícito.

---

## 7. Como atualizar esta skill

Quando um item listado como `REFERENCE ONLY` for validado por um spike e promovido a `ADAPT`/`USE` (ou o inverso — um item `ADAPT`/`USE` for rebaixado após não performar bem), esta skill é editada **naquele momento**, atualizando a tabela ou linha correspondente (Foundation Stack, Core Experience Set ou Avoid List). Não esperar uma revisão geral periódica — a skill não deve ficar desatualizada em relação a uma decisão já tomada.

Mudanças que envolvam decisão nova de UX (não apenas promoção/rebaixamento de um candidato já mapeado) devem primeiro passar pela curadoria (`MMKYU-FRONTEND-REPERTOIRE-DRAFT.md` ou seu sucessor formalizado em `docs/`) antes de alterar esta skill.
