# Repertório de Frontend MMKYU — Curadoria para Revisão (REVISÃO 2)

| Campo | Valor |
|--------|-------|
| **Status** | CURADORIA APROVADA por Fabrício (2026-08-29). Discovery técnico COLLECTION-GALLERY-01 concluído na mesma data (achados confirmados por leitura de código-fonte real), spike visual COLLECTION-GALLERY-SPIKE-01 executado em seguida (sem instalar nenhuma dependência nova) e **decidido no mesmo dia: Premium Grid/List vence** — ver seção 11. Discovery técnico do ThreeUI (Complete Shelf e família Character Carousel) concluído e decidido, mesma data — ver seção 12. **FRENTE VISUAL DA COLLECTION LIBRARY ENCERRADA em 2026-08-29** — três modos oficiais fechados (Lista, Cards, Carrossel), consolidados em COLLECTION-LIBRARY-VIEW-MODES-01 — ver seção 13. |
| **Versão** | 2 (revisão crítica da V1 de 2026-08-29), com decisões fechadas em 2026-08-29 e atualização pós-discovery/pós-spike/pós-decisão na mesma data |
| **Escopo** | Pesquisa apenas. Nenhum componente foi instalado, nenhum código foi alterado, o Binder não foi tocado, a skill `mmkyu-frontend-experience` não foi criada. |
| **Objetivo** | Separar engenharia de frontend (Foundation Stack) de repertório de experiência (Experience Repertoire), corrigir a avaliação do React Bits (por componente, não em bloco), reabrir a decisão de Collection Gallery, reavaliar Vaul, e produzir um Core Experience Set enxuto — tudo como base da futura skill visual. |

Baseline técnica (inalterada desde a V1, confirmada em `web/package.json` e `web/components/ui/`): Next.js 15.5 + React 19.1 + Tailwind CSS 3.4 (v3, não v4) + Radix UI parcial (`Dialog`, `Tooltip`, `Collapsible`, `Slot`) + `class-variance-authority`/`clsx`/`tailwind-merge` + ECharts + `lucide-react` + `next-themes`. Já existe `components/ui/` no estilo shadcn (button, card, dialog, input, select, empty-state, feedback, data-table, skeleton). Sem motion, DnD ou WebGL instalados. O grid de Pesquisa/Catálogo já tem um efeito de brilho/motion próprio (`HoloCard`) — relevante para a seção 3, porque alguns candidatos do React Bits fariam o mesmo trabalho que esse componente já faz.

---

## 1. Foundation Stack (camada A — engenharia de base)

Ferramentas e primitivos técnicos: resolvem *como construir*, não *como a experiência deveria parecer*. A skill deve consultar esta camada quando a pergunta for "que peça técnica sustenta isso", nunca para decidir estética.

| Ferramenta | Papel técnico | Regra de adoção |
|---|---|---|
| **Radix UI (existente)** | Primitivos já em uso (`Dialog`, `Tooltip`, `Collapsible`, `Slot`) | Continua em uso enquanto funcionar. Sem migração automática (ver seção 6). |
| **Base UI** | Sucessor oficial do Radix, default do shadcn desde jul/2026 | Considerar para **componentes novos** a partir de agora. Não migrar o que já existe sem benefício funcional claro. |
| **cmdk (Command)** | Motor de busca/paleta com fuzzy match e teclado | USE — sem substituto melhor identificado para Card Picker/busca global. |
| **Sonner** | Toast/feedback assíncrono | USE — padrão de fato no ecossistema shadcn/Base UI. |
| **dnd-kit** | Drag-and-drop acessível (teclado/touch/leitor de tela) | USE quando Drag and Drop entrar em pauta — não instalar antecipadamente sem uma tela que precise dele. |
| **Motion (ex-Framer Motion)** | Motor de animação JS | Disponível como motor preferencial, **não como dependência automática** — ver regra na seção 7. |
| **View Transitions API (nativa)** | Transições de navegação/estado, zero dependência | Primeira opção sempre que suficiente — ver seção 7. |
| **Origin UI** | Registry de formulários/inputs copy-paste | ADAPT pontual para Add/Replace Card, filtros, bulk onboarding — não importar em bloco. |
| **Kibo UI** | Componentes compostos com lógica (upload, multi-step) | ADAPT pontual para Bulk Onboarding. |
| **use-gesture** | Primitivos de gesto (drag/pinch/swipe) de baixo nível | ADAPT quando o gesto físico do binder/card entrar em pauta. |
| **Vaul** | Drawer/bottom sheet | **Rebaixado nesta revisão — ver seção 5.** Não é mais Core automático. |

---

## 2. Experience Repertoire (camada B — padrões visuais/interativos)

Isto não é uma lista de bibliotecas para instalar — é o vocabulário de *o que a experiência deveria parecer e como deveria reagir*, para o Claude consultar antes de inventar uma solução do zero. Cada entrada aponta para candidatos concretos (que moram na camada A ou em fontes específicas), mas a decisão de adotar um candidato é sempre local, por tela.

- **Collection Gallery** — como apresentar "Minhas Collections". **FECHADO em 2026-08-29** — três modos oficiais: Lista, Cards (padrão inicial), Carrossel (Character Filmstrip + Binder MMKYU). Ver seção 13 para o fechamento completo; frente visual encerrada, não reabrir sem pedido explícito.
- **Hero Object Stage** — o Binder fechado. Já resolvido e aprovado como baseline; esta camada só documenta que o padrão existe, não reabre a discussão.
- **Contextual Quick Actions** — ação que se expande no próprio lugar do slot/card em vez de abrir um modal separado (referência: Cult UI, padrão "botão que expande em painel").
- **Card Detail Overlay** — como a carta se revela em detalhe (desktop: overlay/dialog; mobile: superfície de baixo — ver seção 5 sobre qual mecanismo).
- **Card Picker** — busca e seleção de carta para Add/Replace (cmdk como motor).
- **Motion Patterns** — vocabulário de easing/duração para hover, entrada de lista, layout shift — não uma biblioteca específica, é a consistência entre telas (Motion Primitives como referência de vocabulário, não pacote obrigatório).
- **Hover/Selection** — feedback visual ao passar o mouse/tocar um slot ou card (Spotlight Card do React Bits é candidato pontual — ver seção 3; MMKYU já tem `HoloCard`, checar sobreposição antes de adicionar algo novo).
- **Showcase/Social** — perfil público, grade de destaques, badges. Fonte de referência são os concorrentes diretos (Kollect, Bindify, Collectr Social — ver V1, mantido sem alteração nesta revisão). **Depth Carousel (React Bits) passa a referência futura para este padrão** (adicionado em 2026-08-29, após perder o spike de Collection Library) — a mecânica de profundidade/imersão que não se justificou para a tela operacional "Minhas Collections" pode ter valor real numa vitrine/perfil público, onde exploração visual é o próprio objetivo. Não avaliado ainda para este caso — só registrado como candidato a reconsiderar quando essa tela entrar em pauta. **Character Wave (ThreeUI) soma-se como ADAPT CANDIDATE para este mesmo contexto** (discovery técnico concluído em 2026-08-29, ver seção 12); **Character Filmstrip e Complete Shelf (ambos ThreeUI) ficam como REFERENCE ONLY** para este contexto — mesmo destino do Depth Carousel, nenhum dos dois avaliado em profundidade para Social/Profile ainda.
- **Progress/Celebration Feedback** — Sonner para eventos pontuais; confete para marcos (Set completo, binder completo).
- **Mobile Contextual Surface** — como uma ação ou detalhe aparece no celular sem tirar o usuário do contexto (bottom sheet — mecanismo concreto em reavaliação, seção 5).

---

## 3. React Bits reavaliado — por componente, não em bloco

A V1 tratou o React Bits como uma fonte única e o descartou (nota 3, "tom de landing page"). Isso foi conservador demais: a biblioteca é distribuída componente a componente (cada um copia só o próprio código-fonte + a dependência mínima que usa — OGL, GSAP ou Motion —, sem trazer o catálogo inteiro). Avaliação individual dos componentes indicados por Fabrício, mais os que apareceram com aderência real na pesquisa:

| Componente | Dependência | Modelo técnico | Caso de uso MMKYU | Tier | Recomendação |
|---|---|---|---|---|---|
| **Circular Gallery** | OGL (WebGL leve, não é Three.js) — confirmado no código-fonte real (`import { Camera, Mesh, Plane, Program, Renderer, Texture, Transform } from 'ogl'`) | Galeria em órbita circular, imagens desenhadas como textura WebGL num canvas único | Visualmente interessante para "Minhas Collections", mas ver rebaixamento abaixo | C** | **REFERENCE ONLY (rebaixado em 2026-08-29, discovery COLLECTION-GALLERY-01)** — não descartado (não é AVOID), mas a implementação atual não passa os critérios de corte da skill. Motivos confirmados lendo o código-fonte real (`DavidHDev/react-bits`, MIT): (1) os listeners de touch/mouse/wheel estão presos em `window`, não no container do componente — qualquer scroll/drag na página inteira moveria a galeria; (2) nenhuma verificação de `prefers-reduced-motion` em lugar nenhum do código — o loop de animação roda sempre; (3) conteúdo (imagem + legenda) é desenhado como textura de canvas/WebGL, não DOM real — legendas não são lidas por leitor de tela, só existe uma única região focável (`role="region"`) para o componente inteiro; (4) a lista de itens é duplicada internamente para o loop parecer contínuo (30 Collections viram 60 texturas carregadas de uma vez, sem lazy loading); (5) usar os renders do Binder como item exigiria gerar uma textura/snapshot estático antes — o componente vivo do Binder não pode ser embutido diretamente, só uma imagem plana. O conceito visual (órbita) continua interessante como referência futura, se a implementação for corrigida. |
| **Depth Carousel** | GSAP — **confirmado no código-fonte real** (`import gsap from 'gsap'`), sem WebGL/canvas | Cards recuam em profundidade sobre um trilho 3D, usando `transform` CSS real (`translateZ`/`rotateY`) em `<div>`s de verdade, com GSAP só animando um valor numérico de posição (tween de objeto proxy, não de propriedades DOM) | Rebaixado para Collection Library após o spike (2026-08-29) — ver seção 4 e 11 | B | **REFERENCE ONLY para Collection Library** (rebaixado de ADAPT em 2026-08-29, resultado do spike COLLECTION-GALLERY-SPIKE-01: Premium Grid/List venceu, ganho visual da Visual Gallery não justificou a complexidade). Pontos fortes técnicos confirmados no código-fonte continuam válidos e registrados para referência futura: DOM real (`<div>`/`<img>`) em vez de canvas — mesma família de `transform`/`perspective` já usada no Binder fechado aprovado; Pointer Events (`onPointerDown/Move/Up`) corretamente escopados no elemento raiz, sem vazar para a página; ARIA de carousel completo; verificação explícita de `prefers-reduced-motion`; escala bem para 30 itens. **Preservado como referência futura para experiências de Social Showcase/Profile** (ver seção 2, Experience Repertoire) — exploração visual pode ter valor real num perfil público/vitrine, mesmo não tendo vencido para a tela operacional "Minhas Collections". GSAP segue confirmado como dependência real e **não autorizado a instalar** em nenhum contexto até uma justificativa Tier B específica para esse caso futuro. |
| **Dome Gallery** | Motion | Cúpula 3D imersiva, imagens projetadas numa superfície hemisférica | Visualmente marcante, mas mais pesado/experimental que os dois acima; risco de "efeito demo" sem ganho funcional claro para uma grade de coleções | C | **REFERENCE ONLY** — só reconsiderar se os dois candidatos acima não performarem bem no spike |
| **Spotlight Card** | CSS/JS, sem dependência pesada | Spotlight de cursor com gradiente radial | Hover em cards do grid — mas MMKYU já tem `HoloCard` fazendo um trabalho parecido | A/B | **REFERENCE ONLY** — avaliar se substitui ou duplica o `HoloCard` antes de qualquer adoção |
| **Reflective Card** | Nenhuma (CSS/JS puro) | Reflexo/glare que reage ao cursor | Mesmo risco de sobreposição com `HoloCard` citado acima | A | **REFERENCE ONLY** — mesma ressalva do Spotlight Card |
| **Glass Surface** | Canvas/WebGL (distorção em tempo real) | Vidro estilo Apple com distorção e luz | Nenhum caso de uso claro identificado; estética de vidro contrasta com o couro/analógico já estabelecido no Binder | C | **AVOID** — risco estético direto contra a identidade já aprovada |
| **Lightfall** | OGL | Feixes de luz coloridos caindo em túnel com luz de cursor | Nenhum caso de uso MMKYU — é decoração de landing page | B/C | **AVOID** |
| **Side Rays** | A confirmar (provável OGL/GSAP, mesma família de efeitos de fundo) | Raios de luz decorativos de fundo | Mesmo problema do Lightfall — efeito de impacto sem função | B/C | **AVOID** |

\* Depth Carousel permanece Tier B tecnicamente (mecânica DOM+CSS válida), mas **fora do escopo de Collection Library** desde a decisão de 2026-08-29 — a classificação de tier não muda o veredito de UX, só a facilidade/risco de adoção técnica caso um caso de uso futuro (Social Showcase/Profile) o justifique.

\*\* Circular Gallery foi reclassificado de "B/C" (a definir) para C efetivamente — o discovery confirmou que é WebGL real via OGL, não uma alternativa leve de CSS. OGL é bem mais leve que Three.js completo, mas a classificação de Tier segue a regra da skill (WebGL real = Tier C, aprovação explícita de Fabrício antes de instalar), independentemente do peso relativo dentro da família WebGL.

**Conclusão da reavaliação (atualizada após o spike COLLECTION-GALLERY-SPIKE-01, 2026-08-29)**: React Bits segue não sendo "avoid em bloco". Da leitura de código-fonte real e do spike visual construído em seguida: **Depth Carousel** foi implementado (sem GSAP) como Modo A do spike, comparado lado a lado com Premium Grid/List (Modo B) — **Premium Grid/List venceu**, e Depth Carousel foi rebaixado para **REFERENCE ONLY na Collection Library**, preservado como referência para Social Showcase/Profile; **Circular Gallery** permanece **REFERENCE ONLY** (não é AVOID — o conceito de órbita continua interessante, mas a implementação atual falha critérios de corte de acessibilidade e escopo de evento); 2 componentes seguem sinalizados como possivelmente redundantes com o `HoloCard` já existente (Spotlight Card, Reflective Card); 1 componente de reserva fora do primeiro spike (Dome Gallery); e 2-3 efeitos puramente decorativos sem caso de uso continuam fora (Glass Surface, Lightfall, Side Rays).

---

## 4. Collection Gallery — DECIDIDO (2026-08-29): Premium Grid/List vence

A V1 sugeria bento/masonry como resposta única. A V2 reabriu como alternativas para spike, incluindo a hipótese híbrida. O spike visual **COLLECTION-GALLERY-SPIKE-01** foi construído e avaliado por Fabrício na mesma data, com resultado fechado: **B — Premium Grid/List vence**. A Visual Gallery não demonstrou ganho de UX suficiente para justificar sua maior complexidade na tela "Minhas Collections".

**Decisões derivadas:**

- **Visual Gallery NÃO é o modo principal de "Minhas Collections".**
- **Modelo híbrido descartado por ora** — o ganho não justifica manter dois padrões de navegação na mesma tela.
- **Depth Carousel** rebaixado de ADAPT para **REFERENCE ONLY para Collection Library**; preservado como referência futura para experiências de **Social Showcase/Profile**, onde exploração visual pode ter maior valor (perfil público, vitrine) do que numa tela operacional de gestão da própria coleção.
- **Circular Gallery** permanece **REFERENCE ONLY** (sem mudança — ver seção 3).
- **Premium Grid/List** aprovado como **arquitetura de UX** para "Minhas Collections". O visual construído no spike (`web/components/experimental/collection-gallery-spike-01/premium-grid.tsx`) **não é baseline de produto** — é só a prova operacional que venceu a comparação. O refinamento visual da Collection Library é tratado como rodada separada (COLLECTION-LIBRARY-VISUAL-01, ver seção 11).

---

## 5. Vaul — reavaliado

Verificação de manutenção: o próprio ecossistema shadcn confirma, em discussão oficial do repositório (`shadcn-ui/ui`, "Vaul is unmaintained"), que a Vaul parou de receber manutenção ativa. Como consequência direta, o shadcn/ui **migrou o próprio componente `Drawer` de Vaul para o Drawer nativo do Base UI** (disponível a partir da Base UI 1.2.0), exatamente para reduzir dependência de um pacote não mantido.

**Decisão desta revisão**: Vaul sai do Core Set automático.

- **Substituto primário**: Drawer nativo do Base UI — mesma função (bottom sheet/drawer mobile), mantido ativamente, e já alinhado com a decisão da seção 1 de tratar Base UI como o caminho para componentes novos.
- **Alternativa de transição**: `vaul-base` (fork que usa o Dialog do Base UI por baixo, mantendo a API do Vaul) — só relevante se a migração completa para o Drawer nativo do Base UI não for viável no momento da implementação.
- Vaul propriamente dito passa a **REFERENCE ONLY** — pode ser citado como referência de UX (drag-to-close, snap points), mas não deve ser a dependência instalada.

---

## 6. Base UI / Radix — regra de convivência (sem migração automática)

Regra fixada nesta revisão, para a skill herdar sem reabrir a discussão a cada pedido:

- Componentes Radix já existentes (`Dialog`, `Tooltip`, `Collapsible`, `Slot`) **continuam em uso enquanto estiverem funcionando**. Não há gatilho para reescrevê-los.
- **Componentes novos** podem considerar Base UI diretamente, já que é o caminho oficial de longo prazo do próprio shadcn.
- Migração de um componente Radix existente para Base UI só acontece **mediante benefício funcional claro e específico** (ex.: um caso real de acessibilidade ou de bug que o Base UI resolve e o Radix não) — nunca como troca por preferência de stack.

---

## 7. Motion — regra de uso (não é dependência automática)

Regra fixada nesta revisão:

1. **CSS puro / View Transitions API primeiro**, sempre que a transição ou animação for simples o suficiente para isso (fade, slide, layout shift pontual, transição de navegação). Zero dependência, já nativo no React 19.2/Next.js 15+.
2. **Motion entra apenas quando há ganho real de UX** que CSS/View Transitions não conseguem entregar de forma razoável — orquestração de múltiplos elementos, gestos combinados com animação, `layout` animation automática em listas que mudam de forma imprevisível.
3. Qualquer adoção de Motion (ou de um componente que dependa dele, como Motion Primitives ou Dome Gallery) deve vir acompanhada de uma frase curta justificando por que CSS/View Transitions não bastam — essa justificativa é obrigatória na proposta da skill (seção 8 do documento original, ver seção 7 revisada abaixo).

---

## 8. MMKYU Core Experience Set (8 padrões — substitui o "Core Set" de 12 itens da V1)

A V1 misturava ferramenta (Sonner, dnd-kit) com padrão de experiência (Quick Actions, Card Detail) num único "Core Set" de 12. Esta revisão separa: as ferramentas já vivem no Foundation Stack (seção 1) e não precisam de uma segunda lista. O que segue é **só padrão de experiência**, o vocabulário que a skill deve reconhecer e aplicar — nenhum item aqui é uma dependência obrigatória por si só.

| # | Pattern | Problema que resolve | Componentes/fontes candidatas | Tier | Quando usar | Quando NÃO usar |
|---|---|---|---|---|---|---|
| 1 | **Collection Library — 3 modos oficiais (Lista/Cards/Carrossel)** | Apresentar "Minhas Collections" — **FECHADO em 2026-08-29**, ver seção 13: três modos oficiais, mesmo núcleo de informação (Binder, nome, código, progresso), variando só densidade/apresentação | **Lista** (`CollectionListView`) — máxima densidade/escaneabilidade, uso operacional. **Cards** (`PremiumGrid`, vencedor do spike COLLECTION-GALLERY-SPIKE-01) — equilíbrio informação/presença visual, **modo padrão inicial**. **Carrossel** — Character Filmstrip (ThreeUI) + skin "Binder MMKYU" (textura do Binder real, sem borda colorida, costura periférica, marca d'água central, círculo de progresso) — exploração visual/premium, Binder como protagonista. Character Filmstrip passa de `AVOID` (seção 12) para **`USE`** nesta tela após avaliação visual direta (reversão documentada na seção 13). Character Wave passa a `REFERENCE ONLY` para esta tela (não foi o escolhido para Carrossel). Depth Carousel e Circular Gallery seguem `REFERENCE ONLY`; Complete Shelf segue `REFERENCE ONLY`; Hero Card/Hero Artwork testados e rejeitados, não reabrir | A | Sempre, para "Minhas Collections" — Cards por padrão; usuário troca para Lista (muitas Collections/escaneabilidade) ou Carrossel (poucas/médias, exploração visual) | Não criar um quarto modo sem pedido explícito |
| 2 | **Hero Object Stage** | Apresentar um objeto único como protagonista (Binder fechado) | Já resolvido — CSS 3D próprio do MMKYU | A | Sempre que o objeto for singular e merecer protagonismo total | Quando o "objeto" na verdade é uma lista/coleção — aí é Collection Gallery |
| 3 | **Contextual Quick Actions** | Ação rápida sem sair do contexto do slot/card | Cult UI (botão→painel) | A | Ações de 1-2 passos ligadas a um item específico visível na tela | Fluxos de múltiplas etapas — aí é um Dialog/Drawer completo |
| 4 | **Card Detail Overlay** | Revelar detalhe completo de uma carta | Base UI Dialog (desktop) / Base UI Drawer (mobile) | A | Sempre que o usuário pedir "ver mais" sobre um item específico | Quando a informação cabe inteira no hover/tooltip — aí não precisa de overlay |
| 5 | **Card Picker** | Buscar e selecionar uma carta para Add/Replace | cmdk | A | Qualquer fluxo que exija encontrar uma carta específica entre muitas | Listas curtas (menos de ~10 itens) — um select simples já resolve |
| 6 | **DnD Layout Manipulation** | Reorganizar cartas/slots manualmente | dnd-kit | A | Quando o usuário precisa definir uma ordem própria (Wishlist, slots do binder) | Quando a ordem é sempre derivada de um critério automático (data, raridade) — aí não precisa de DnD |
| 7 | **Progress/Celebration Feedback** | Comunicar avanço e marcos | Sonner + confete pontual | A/B | Eventos reais de conclusão (Set 100%, import finalizado) | Nunca usar confete/celebração em ações rotineiras — perde o efeito e vira ruído |
| 8 | **Mobile Contextual Surface** | Ação ou detalhe em contexto no celular | Base UI Drawer (ver seção 5) | A | Telas pequenas, ação ligada a um item visível | Desktop — lá o Dialog/overlay já resolve melhor |

---

## 9. Avoid List (atualizada)

Mantido da V1, com dois ajustes desta revisão:

- **React Bits deixa de ser "avoid em bloco"** — ver seção 3. O que continua evitado é usar o catálogo inteiro como identidade visual (texto que se monta, partículas de impacto, "screenshot-bait"), não os componentes individuais com aderência real.
- **Glass Surface, Lightfall, Side Rays** (React Bits) entram explicitamente na Avoid List — efeitos decorativos sem caso de uso MMKYU e, no caso do Glass Surface, em conflito estético direto com o couro/analógico do Binder.

Itens já descartados na V1 e reconfirmados sem alteração: Vanta.js/tsParticles como fundo decorativo, Spline em produção, Aceternity UI como base ampla (componentes pontuais continuam permitidos), Uiverse.io como fonte sistemática, misturar duas bibliotecas de motion (Motion + GSAP) sem necessidade.

---

## 10. Proposta revisada da futura skill

`.claude/skills/mmkyu-frontend-experience/SKILL.md` (segue não criada)

Ajustada para as duas camadas e as regras desta revisão. A skill deve ensinar o Claude a, nesta ordem:

1. **Consultar primeiro o Foundation Stack** (seção 1) para saber que ferramenta técnica já está disponível ou é o caminho oficial — nunca escolher uma ferramenta nova sem checar se já existe uma aprovada.
2. **Consultar o Experience Repertoire** (seção 2) antes de inventar uma solução de UI do zero — o vocabulário de padrões já mapeado é o primeiro lugar a olhar, não o último.
3. **Preferir padrões já aprovados** (Core Experience Set, seção 8) sobre soluções novas, salvo quando o problema genuinamente não se encaixa em nenhum dos 8.
4. **Adaptar a estética ao MMKYU sempre** — nunca copiar a aparência de origem de uma biblioteca (cores, tipografia, densidade) sem passar pelo vocabulário visual já estabelecido no Binder e no Design System.
5. **Nunca copiar aparência de referência 1:1** — bibliotecas como Aceternity/React Bits são fonte de mecânica/comportamento, não de skin.
6. **Justificar qualquer Tier B por escrito** — uma frase objetiva de por que CSS/View Transitions não bastam (regra da seção 7), antes de propor Motion ou qualquer dependência de motion.
7. **Exigir aprovação explícita de Fabrício para qualquer Tier C** — WebGL/Three/OGL pesado nunca entra por iniciativa própria da skill, mesmo que um candidato pareça visualmente superior.
8. **Preservar performance, mobile e acessibilidade como critério de corte**, não como checklist posterior — um candidato que falha aqui é descartado antes de chegar à comparação estética.
9. **Nunca reabrir baseline já aprovado** (o Binder fechado é o caso concreto hoje) **sem pedido explícito** — a skill referencia a memória/documentação da aprovação em vez de propor mudanças por conta própria.

### Estrutura final do arquivo (proposta — ainda não criada)

```
.claude/skills/mmkyu-frontend-experience/SKILL.md
```

**Frontmatter**: `name: mmkyu-frontend-experience`, `description` cobrindo os gatilhos (adicionar componente novo, resolver padrão de interação, avaliar biblioteca não mapeada, decidir Collection Gallery/Card Detail/Quick Actions e afins).

**Seções do corpo, na ordem em que a skill deve ser lida/aplicada:**

1. **Como consultar esta skill** — a ordem de 3 passos (Foundation Stack → Experience Repertoire → Core Experience Set) antes de propor qualquer UI nova.
2. **Foundation Stack** — tabela compacta (ferramenta → regra de adoção), igual à seção 1 deste documento.
3. **Core Experience Set** — os 8 padrões completos (problema/candidatos/tier/quando usar/quando não usar), igual à seção 8.
4. **Avoid List** — curta, direta, igual à seção 9.
5. **Regras de comportamento** — as 9 regras já listadas acima nesta seção.
6. **Regra de baseline aprovado** — hoje só o Binder fechado; formato pensado para crescer (lista, não prosa), conforme mais telas forem aprovadas como baseline.
7. **Como atualizar esta skill** — processo curto: quando um item `REFERENCE ONLY` for validado por spike e promovido a `ADAPT`/`USE`, ou vice-versa, a skill é editada nesse momento — nunca fica desatualizada esperando uma revisão geral.

**O que entra resumido/embutido direto no arquivo da skill** (porque é pequeno, muda pouco, e é consultado toda vez): Foundation Stack (tabela), Core Experience Set (8 padrões), Avoid List, as 9 regras de comportamento, a lista de baselines aprovados.

**O que fica só referenciado** (aponta para este documento de curadoria — ou para onde ele for formalizado em `docs/` — em vez de duplicar): o detalhamento completo do Experience Repertoire (a nuance de cada padrão, não só o nome), a reavaliação do React Bits componente a componente (seção 3 — só a conclusão de cada um entra no Foundation/Core/Avoid, o raciocínio completo fica na curadoria), e o histórico/critério do spike de Collection Gallery (seção 4 — uma vez decidido, a skill registra só o resultado final, não o processo).

---

## 11. Resumo final — V1 → V2

**O que mudou:**

- A shortlist única de 27 itens foi separada em **Foundation Stack** (ferramenta/engenharia) e **Experience Repertoire** (padrão visual/interativo) — a V1 misturava as duas coisas na mesma tabela.
- **React Bits** deixou de ser avaliado como biblioteca única (nota 3, avoid) e passou a ser avaliado componente a componente: 2 candidatos oficiais para spike (Circular Gallery, Depth Carousel), 2 sinalizados como possivelmente redundantes com o `HoloCard` já existente (Spotlight Card, Reflective Card), 1 de reserva (Dome Gallery), 3 mantidos fora (Glass Surface, Lightfall, Side Rays).
- **Collection Gallery** deixou de estar implicitamente decidida como bento/grid e voltou a ter duas alternativas oficiais em aberto (Visual Gallery vs. Premium Grid/List), com critério de decisão por spike, não por preferência.
- **Vaul** saiu do Core automático depois de confirmado que está sem manutenção ativa (o próprio shadcn/ui migrou seu Drawer para o Base UI por esse motivo) — substituto primário indicado é o Drawer nativo do Base UI.
- **Base UI/Radix**: fixada a regra de não-migração automática (só com benefício funcional claro), que a V1 não deixava explícita.
- **Motion**: fixada a regra de CSS/View Transitions primeiro, Motion só com ganho de UX justificado — a V1 já recomendava Motion no Core Set sem essa condição.
- O **Core Set de 12 itens** (que misturava ferramenta e padrão) foi substituído pelo **MMKYU Core Experience Set de 8 padrões** (camada B pura), com quando-usar/quando-não-usar explícitos por item.
- A proposta da skill ganhou as 9 regras de comportamento pedidas (ordem de consulta, adaptação estética, proibição de cópia 1:1, justificativa obrigatória para Tier B, aprovação obrigatória para Tier C, corte por performance/mobile/a11y, não reabrir baseline).

**Decisões — fechadas por Fabrício em 2026-08-29:**

1. **Collection Gallery, candidatos oficiais**: aprovados Circular Gallery e Depth Carousel. Dome Gallery fica de fora do spike — risco de virar "efeito demo" em vez de produto, maior que o ganho esperado.
2. **Quando rodar o spike**: agora, mas como spike curto e não bloqueador — uma única rodada comparando Visual Gallery vs. Premium Grid/List. Sem ganho visual claro, encerra e segue com Premium Grid.
3. **Vaul → Base UI Drawer**: aprovado como direção para componentes mobile novos. Vaul permanece só como referência de comportamento (drag-to-close, snap points), não como dependência.
4. **Spotlight Card / Reflective Card**: mantidos `REFERENCE ONLY`, não descartados. `HoloCard` já cobre parte do problema; só entra algo novo se uma comparação direta mostrar ganho real sobre o que já existe.
5. **MMKYU Core Experience Set (8 padrões)**: aprovado como vocabulário oficial da futura skill, no nível de abstração certo.

**Ajuste incorporado após a aprovação (mesma data)**: o pattern "Collection Visual Gallery" deixou de tratar Visual Gallery × Premium Grid/List como escolha necessariamente excludente. A seção 4 e o pattern #1 do Core Experience Set (seção 8) agora registram explicitamente a hipótese híbrida — Visual Gallery como experiência principal para poucas/médias Collections, Premium Grid como modo alternativo para muitas Collections/necessidade de escaneabilidade — como um dos três desfechos possíveis do spike (A vence, B vence, ou híbrido), não como decisão tomada.

**Estrutura final da skill**: proposta na seção 10 (subseção "Estrutura final do arquivo"), com frontmatter, 7 seções de corpo, e a divisão explícita do que entra resumido/embutido no arquivo (Foundation Stack, Core Experience Set, Avoid List, as 9 regras, lista de baselines) versus o que fica só referenciado nesta curadoria (nuance do Experience Repertoire, detalhamento do React Bits por componente, histórico do spike de Collection Gallery). A skill em si **não foi criada** nesta rodada.

**Próximo passo em aberto**: o spike de Collection Gallery (decisão 2) envolve instalar uma dependência nova (OGL, para Circular Gallery — e possivelmente Motion, dependendo de como o Depth Carousel for implementado), o que ainda está coberto pela restrição de "não instalar nada" desta rodada de pesquisa/curadoria. Isso precisa de uma autorização explícita e separada antes de eu começar a construir o spike ou a criar o arquivo da skill.

**Discovery COLLECTION-GALLERY-01 (2026-08-29) — achados confirmados e decisões novas:**

Antes do spike visual, foi feita uma leitura direta do código-fonte real do React Bits (`DavidHDev/react-bits`, GitHub, MIT) para Circular Gallery e Depth Carousel, substituindo as suposições da V2 por fatos confirmados:

- **Depth Carousel**: dependência confirmada é GSAP (não Motion, como a V2 supunha). Usa DOM real (`<div>`/`<img>` com `transform` CSS), Pointer Events corretamente escopados no próprio elemento (não vazam para a página), ARIA de carousel completo, verificação explícita de `prefers-reduced-motion`, e escala bem até a ordem de 30 itens sem virtualização. **Permanece ADAPT e passa a candidato principal do primeiro spike** — mas GSAP não está autorizado a ser instalado agora; o spike reimplementa a mecânica só com React + CSS 3D + Pointer Events.
- **Circular Gallery**: **rebaixado de ADAPT para REFERENCE ONLY** (não para AVOID). Motivos confirmados no código: listeners de touch/mouse/wheel presos em `window` em vez do container (vazamento de evento para a página inteira); nenhuma verificação de `prefers-reduced-motion`; conteúdo principal desenhado em canvas/textura WebGL, não DOM real (limitação de acessibilidade — legendas não são lidas por leitor de tela); duplicação interna da lista de itens para o loop (sem lazy loading); maior custo de adaptação para usar renders do Binder (exigiria gerar uma textura/snapshot estático antes, o componente vivo não pode ser embutido). O conceito visual de órbita continua interessante como referência futura, se a implementação for corrigida.
- Registrado na seção 3 (tabela do React Bits) e na seção 4 (Collection Gallery) e propagado para a seção 8 (Core Experience Set, pattern #1) e para a skill `mmkyu-frontend-experience`.

Este discovery foi seguido pelo spike visual **COLLECTION-GALLERY-SPIKE-01** (rota experimental isolada, sem instalar GSAP/Motion/OGL) — ver relatório de implementação entregue a Fabrício na mesma data.

**Resultado do spike COLLECTION-GALLERY-SPIKE-01 (2026-08-29) — DECIDIDO:**

Fabrício avaliou os dois modos (A — Visual Gallery / B — Premium Grid/List) com 6 e 24 Collections mockadas e decidiu: **B — Premium Grid/List vence**. A experiência visual de navegação entre Binders não agregou valor suficiente para ser superior ou complementar ao grid operacional.

Decisões derivadas, já propagadas nas seções 3, 4 e 8 e na skill:

1. Visual Gallery não é o modo principal de "Minhas Collections".
2. Modelo híbrido descartado — não compensa manter dois padrões de navegação.
3. Depth Carousel rebaixado de ADAPT para REFERENCE ONLY para Collection Library; preservado como referência futura para Social Showcase/Profile.
4. Circular Gallery permanece REFERENCE ONLY (sem mudança).
5. Premium Grid/List aprovado como arquitetura de UX para "Minhas Collections" — o visual construído no spike não é baseline de produto.

**Próximo passo, executado na sequência (mesma data): COLLECTION-LIBRARY-VISUAL-01** — rodada única de refinamento visual do Premium Grid aprovado, objetivo "biblioteca digital premium de Binders" em vez de "cards contendo Binders" (Binder maior e protagonista, menos chrome de card, profundidade via sombra/hover, sem dashboard/estatísticas/filtros/segunda modalidade novos, sem dependência nova, sem redesenhar o Binder fechado). Ver relatório de implementação entregue a Fabrício.

---

## 12. ThreeUI reavaliado — Complete Shelf e Character Carousel (2026-08-29)

Depois do COLLECTION-LIBRARY-VISUAL-01, foi avaliado o pacote real `@designcodeio/threeui` (Meng To/Design+Code, MIT, instalado nos spikes) como fonte adicional de padrões — primeiro `CompleteShelfLandingPage`, depois, num discovery de extensão, o componente-pai completo `Character Carousel` (`https://threeui.com/ui-elements/character-carousel`), para mapear todas as variantes reais e comparar contra os candidatos já em uso (Premium Grid, Depth Carousel).

**Achado estrutural — só existem duas variantes reais de Character Carousel:**

Leitura direta do código-fonte (`lib-dist/shaders/character-carousel/CharacterCarousel.js`, motor compartilhado) e da própria descrição oficial do produto ThreeUI confirmam: `Character Wave` (`variant:"wave"`) e `Character Filmstrip` (`variant:"filmstrip"`) são as únicas duas variantes. `Character Carousel` sem `variant` explícito **é o próprio Filmstrip** — não existe uma terceira variante "base"/default distinta. A hipótese de uma variante intermediária "mais premium que Premium Grid, mais estável que Wave" não se confirmou: não há terceira variante para preencher esse meio-termo.

| Critério | Character Wave | Character Filmstrip | Complete Shelf |
|---|---|---|---|
| Tier | A — DOM + CSS 3D puro (`perspective`/`translate3d`/`rotate`), zero Three.js/WebGL/GSAP/CDN | A — mesmo motor DOM + CSS 3D, zero Three.js/WebGL/GSAP/CDN | C — Three.js/WebGL real, iframe pesado |
| Estética | Dark theme (`#121212`), hook de cor por item via `--card-color` | Light/editorial "contact-sheet" (`#d8c9ad`, Arial Narrow), sem hook de cor por item | Prateleira 3D fotorrealista de livros |
| Falloff de profundidade | Mais suave (`focus×95 − distance×78`) — mais itens legíveis simultaneamente | Mais agressivo (`focus×145 − distance×148`) — menos itens legíveis | N/A (câmera 3D livre) |
| Interação extra | `pointerdown` + `dblclick` para alternar orientação | Nenhuma | Seleção de livro, câmera orbital |
| a11y/reduced-motion | `<button>` reais, `aria-current`/`aria-label` dinâmicos, `prefers-reduced-motion` tratado em CSS+JS | Idêntico ao Wave (mesmo motor) | Não avaliado a fundo (fora de escopo, Tier C) |
| Adequação MMKYU (Binder como protagonista) | Boa — dark theme e cor por item conversam com o design system | Fraca — estética editorial pouco aderente, sem vantagem confirmada sobre o Wave | Fora de cogitação para Collection Library (WebGL pesado) |

**Classificação MMKYU, por contexto — DECIDIDO por Fabrício em 2026-08-29:**

- **Complete Shelf**: `REFERENCE ONLY`, fora da Collection Library — preservado para uma eventual experiência futura de showcase/social, mesmo destino do Depth Carousel. Nenhuma mudança de escopo.
- **Character Wave**: `ADAPT CANDIDATE` para Collection Library, como Signature View experimental — único candidato ativo da família para esta tela, sem substituir o Premium Grid como modo operacional (spike ativo: COLLECTION-WAVE-SPIKE-01, aguardando avaliação visual). `ADAPT CANDIDATE` também para Social/Profile. `REFERENCE ONLY` para Pokédex/Favoritos.
- **Character Filmstrip**: `AVOID` para Collection Library — estética editorial/contact-sheet pouco aderente ao MMKYU, falloff de profundidade mais agressivo (menos itens legíveis), sem hook de cor por item, nenhuma vantagem relevante confirmada sobre o Wave. `REFERENCE ONLY` para Social/Profile e para Pokédex/Favoritos. Nenhum spike novo será aberto para o Filmstrip.
- **Premium Grid**: permanece `USE` como modo operacional de Collection Library — decisão da seção 11 não é reaberta por este discovery.

**Próximo passo, já definido**: só a avaliação visual do spike COLLECTION-WAVE-SPIKE-01 já existente. Nenhuma variante nova da família Character Carousel, nem do pacote ThreeUI de modo geral, será pesquisada sem pedido explícito de Fabrício.

---

## 13. Collection Library — FECHAMENTO FINAL (2026-08-29): três modos oficiais

Depois do discovery ThreeUI (seção 12), a avaliação visual direta de COLLECTION-WAVE-SPIKE-01 (Wave × Filmstrip × Grid, Light/Dark, 6/12/24) levou a um resultado diferente do previsto pelo discovery técnico isolado: **Character Filmstrip**, não Character Wave, foi o escolhido para seguir como engine da experiência de Carrossel. As rodadas seguintes — COLLECTION-FILMSTRIP-BINDER-FIDELITY-01 (comparação A/B/C: Binder puro × Hero Card × Binder + Hero Artwork) e COLLECTION-FILMSTRIP-HERO-COVER-01 (refinamento final da variante A) — desenvolveram essa direção até a skin final "Binder MMKYU". A consolidação COLLECTION-LIBRARY-VIEW-MODES-01 (mesma data) uniu essa direção com Lista e Cards num único seletor, mesmo dataset, e fechou a frente visual da Collection Library.

**Divergência sinalizada explicitamente** (não aplicada silenciosamente, conforme convenção deste repositório): a seção 12 havia classificado `Character Filmstrip` como `AVOID` para Collection Library, com base em leitura de código-fonte (estética editorial/"contact-sheet", falloff de profundidade mais agressivo, sem hook de cor por item). Essa classificação **é revertida para `USE`** nesta seção. Os fatos técnicos do discovery continuam corretos (o Filmstrip original de fato tinha essa estética e esse falloff) — o que mudou foi a avaliação visual direta com a skin "Binder MMKYU" substituindo a identidade "contact-sheet" original: o falloff mais agressivo, que parecia uma desvantagem em abstrato, funciona bem quando o objetivo do modo é justamente profundidade/exploração/Binder como protagonista (diferente do Wave, pensado para leitura simultânea de mais itens). A ausência de hook de cor por item deixou de ser relevante porque a decisão final removeu a borda colorida também do Wave/Grid — identidade passou a vir só de nome+código.

**Decisão fechada:**

1. **Três modos oficiais de "Minhas Collections"**: **Lista**, **Cards**, **Carrossel**. Nomenclatura para o usuário final é só essa — termos internos de discovery (Signature View, Operational View, Filmstrip, Premium Grid) não aparecem na UI.
2. **Cards é o modo padrão inicial.**
3. Os três modos representam a MESMA Collection com o MESMO núcleo de informação (Binder, nome, código, progresso) — o que muda é só densidade/apresentação, nunca dado exibido.
4. **Lista** = `USE`, novo padrão (`CollectionListView`, `collection-library-view-modes-01/collection-list-view.tsx`) — modo compacto operacional, não é tabela administrativa.
5. **Cards** = `USE`, base é o `PremiumGrid` já aprovado (seção 4/11), com o refinamento de exibir `code` nesta rodada.
6. **Carrossel** = `USE`, engine é o Character Filmstrip (ThreeUI, Tier A, DOM+CSS 3D, mecânica intocada) com a skin "Binder MMKYU" (textura portada de `binder-cover-closed.tsx`, sem borda colorida, costura periférica, marca d'água central, círculo de progresso coletadas/total).
7. **Character Wave** passa a `REFERENCE ONLY` para Collection Library (não foi o escolhido) — permanece `ADAPT CANDIDATE` só para Social/Profile, sem mudança nesse outro contexto.
8. **Hero Card / Hero Artwork**, testados em COLLECTION-FILMSTRIP-BINDER-FIDELITY-01 (variantes B/C), foram descartados a favor de A (Binder puro) — `AVOID`, não reabrir sem pedido explícito.
9. Complete Shelf, Depth Carousel, Circular Gallery: sem mudança, seguem `REFERENCE ONLY` (seções 3, 4, 12).

**Escopo explicitamente fora desta rodada/decisão**: domínio, backend, persistência de preferência de modo, filtros avançados, busca, ordenação — nenhum desses foi tocado.

**Registrado como baseline aprovado** — ver `.claude/skills/mmkyu-frontend-experience/SKILL.md`, seção 6. **Esta decisão encerra a frente visual da Collection Library** — qualquer novo modo, ou reabertura de Hero Card/Hero Artwork/Complete Shelf/Wave para este contexto, exige pedido explícito novo de Fabrício.

Implementação de referência: `web/components/experimental/collection-library-view-modes-01/` (`collection-library-view-modes-view.tsx`, `collection-list-view.tsx`) + `web/components/experimental/collection-gallery-spike-01/premium-grid.tsx` (refinado) + `web/public/ui-elements/collection-library-carousel-mmkyu-{6,12,24}{,-light}.html`.
