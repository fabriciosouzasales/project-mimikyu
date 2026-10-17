# Collection North Star — Referência Normativa de Experiência

| Campo | Valor |
|---|---|
| **Documento** | Referência normativa de experiência do módulo Collection (visão, fluxos, nomenclatura, critérios de base funcional) |
| **Arquivo** | `docs/domain-modeling/collections/north-star-2026-10-16.md` |
| **Versão** | 1.6 |
| **Status** | **NORMATIVO** — aprovado por Fabrício em 2026-10-16 (`COLLECTION-NORTH-STAR-02`, decisões D1–D4). Itens marcados **[H]**, entradas **PENDENTE** e as recomendações ainda abertas do §0.2 **não são normativos** até homologação formal de Fabrício. |
| **Rodadas** | `COLLECTION-NORTH-STAR-01` (proposta, v0.1–0.2) → `COLLECTION-NORTH-STAR-02` (consolidação normativa, v1.0) → … → `COLLECTIONS-NORMATIVE-REALIGNMENT-01` (v1.5: NS-15–NS-18 e matriz de rastreabilidade §7) |
| **Fontes** | `concept-decisions.md` (C-01–C-186), `logical-model.md`, `checkpoint-2026-08-28.md` §7, `checkpoint-2026-08-29.md`, `ux-exploration-2026-08-29.md`, `checkpoint-2026-10-15.md`, `05d-colecoes-e-usuarios.md`, `architecture/ubiquitous-language.md`, `MMKYU-FRONTEND-REPERTOIRE-DRAFT.md` §13 |
| **Legenda** | **[D]** decisão anterior aprovada e vigente · **[NS]** decisão normativa desta North Star · **[F]** fato do repositório/LIVE · **[H]** hipótese, não normativa |
| **Fora de escopo** | Implementação, SQL, migrations, contratos técnicos (registrados apenas como necessidade), novos spikes visuais, BULK-05/06 (não autorizados). |

---

## 0. Governança

1. **Autoridade.** Este documento é a referência normativa da **experiência** de Collection: o que o usuário vê, faz, lê e como a qualidade da entrega é aprovada.
2. **Precedência.** Em **domínio** (entidades, invariantes, regras de dados), as decisões `C-*` e `LDM-*` prevalecem sempre. Se uma regra desta North Star contradisser uma `C-*`/`LDM-*`, vale a `C-*`/`LDM-*` e esta North Star deve ser corrigida. Nenhuma `C-*`/`LDM-*` é alterada por este documento.
3. **Escopo normativo.** São normativos: as decisões **NS-01–NS-18** (§0.1), a visão (§1), as jornadas dos fluxos (§2), as entradas de nomenclatura com status **HOMOLOGADO** (§3) e os critérios **B1–B8** (§4). Itens **[H]**, entradas **PENDENTE** e o §5.2 não são normativos.
4. **Contratos técnicos.** Necessidades técnicas são registradas aqui só quando indispensáveis (hoje, apenas CT-01, §2.6). Cada contrato exige proposta própria, harness, gate de segurança e aprovação de Fabrício antes de qualquer implementação.
5. **Alteração.** Mudanças neste documento exigem aprovação de Fabrício, nova entrada de Revision History e linha correspondente em `docs/log.md`.

### 0.1 Decisões normativas

| ID | Decisão | Origem |
|---|---|---|
| NS-01 | Visão: "Collection é a própria coleção do colecionador em forma digital — ver o que tem, saber o que falta e organizar do seu jeito, sem sentir que está preenchendo um banco de dados." Promessas, em ordem: registrar rápido; progresso que motiva; organizar com prazer. | D4 |
| NS-02 | Públicos: primário, colecionador de Sets (iniciante a intermediário); secundário, avançado; terciário, Pokédex (condicionado a P7). | D4 |
| NS-03 | Simplicidade na superfície, profundidade sob demanda: o iniciante usa o produto sem conhecer Master Set, local físico, fichário, conteúdo planejado ou fixação. | D4 |
| NS-04 | Os cinco fluxos centrais e suas jornadas são os do §2. | D4 |
| NS-05 | A coleção abre na grade de cartas com progresso; o fichário é visão opcional criada pelo usuário. | D4 |
| NS-06 | Primeira coleção sem nenhuma configuração física e sem estado parcial, por operação atômica e idempotente (opção A, §2.6). | **D1** |
| NS-07 | Contratos existentes (`5022`, `5034`, `5065` e demais) são preservados; a operação de NS-06 é um contrato novo e aditivo (CT-01), não implementado nesta rodada. | **D1** |
| NS-08 | "Coleção" para Collection e "Set" para Card Set em todo o produto, inclusive no catálogo administrativo (K1-A). | **D2** |
| NS-09 | "Fichário" designa exclusivamente o Layout digital; "Onde guardo" designa o armazenamento físico (K2-A). | **D2** |
| NS-10 | B1–B8 são critérios obrigatórios da base funcional que libera P7–P9; nenhuma meta pode ser flexibilizada sem aprovação de Fabrício. | **D3** |
| NS-11 | Qualidade visual premium só é aprovada por homologação expressa de Fabrício (B2). | **D3** |
| NS-12 | Segurança (B7), performance (B4), responsividade (B3) e acessibilidade (B5) são requisitos obrigatórios, não melhorias. | **D3** |
| NS-13 | Local padrão (K8, caminho 1): o CT-01 cria um local físico com nome provisório **"Local padrão"**, que representa um lugar físico real ainda não identificado pelo usuário. Nenhuma carta recebe localização não confirmada: o local padrão nunca é destino automático. **Toda operação que atribui carta ao local padrão — inclusive Fluxo 2, Fluxo 5 e mudança de local (`5024`) — exige confirmação explícita do usuário antes de gravar.** A presença de cartas no local **não** é evidência de confirmação física. Como não existe, nem é criado nesta rodada, registro persistente de confirmação, a confirmação é pedida em cada operação de atribuição ao local padrão (o que cobre a primeira). Cartas sem local exibem **"Sem localização definida"** (C-26). | K8 (`COLLECTION-NORTH-STAR-K8`), corrigida em `COLLECTION-NORTH-STAR-05` |
| NS-14 | N8: `STANDARD_SET` é apresentado como **Set padrão**, subtítulo "uma de cada carta". | `COLLECTION-NORTH-STAR-05` |
| NS-15 | **Regra D-A — local da coleção na criação (fecha R4/P4).** Se o usuário **não possui nenhum local**, o CT-01 cria o "Local padrão" atomicamente com a coleção, sem pergunta. Se possui **um ou mais locais**, ele **escolhe explicitamente** um deles, mesmo quando houver apenas um; o sistema nunca escolhe automaticamente (nem o mais antigo, nem o único). A criação **nunca** atribui localização física a cartas. O local escolhido é o **local padrão da coleção** (Default Storage Container, C-36: destino sugerido, alterável), distinto da **localização física individual de cada exemplar** (C-26, C-28), que só muda por operação explícita com as confirmações de NS-13. | Decisão de Fabrício em `MY-COLLECTIONS-FOUNDATION-01` (2026-10-17, implementada em `5167`), consolidada em `COLLECTIONS-NORMATIVE-REALIGNMENT-01` |
| NS-16 | **Capa do fichário — evolução da direção visual aprovada.** Preserva o objeto fichário tridimensional, com acabamento premium, zíper e identidade MMKYU (baseline `binder-cover-closed.tsx`, 29/08). Passa a admitir **cor personalizável e persistente por coleção**. Em coleções de Set, a capa usa a **identidade oficial do Set** (logo) quando disponível; sem imagem oficial, usa **identidade tipográfica** adequada (nome/código do Set, ou o nome da coleção quando não há Set). **Nenhuma imagem de carta individual é usada automaticamente como capa** (Hero Card / Hero Artwork continuam AVOID). A mesma capa aparece na Biblioteca e na página da coleção. **Paleta aprovada para a versão atual (decisão K12, Fabrício, 2026-10-17):** vocabulário **fechado** de seis cores — Ônix (`onix`), Vinho (`vinho`), Floresta (`floresta`), Marinho (`marinho`), Caramelo (`caramelo`) e Pérola (`perola`) —, idêntico ao CHECK da proposta 5171, à validação da RPC 5172 e a `BINDER_FINISHES` no frontend. A paleta pode evoluir no futuro, mas qualquer ampliação exige nova decisão e mudança conjunta dos três pontos; nenhuma outra personalização (textura, material, imagem própria) está no escopo atual. **Ainda não decidido:** detalhes de acabamento (placa do logo, foil do código, materiais), pendentes de homologação B2. Persistência de cor e leitura de logos dependem da proposta não executada `2026-10-17-collection-cover-finish` (5171–5174, 5831). | Direção aprovada por Fabrício em `MY-COLLECTIONS-LIBRARY-VISUAL-02` (2026-10-17), consolidada em `COLLECTIONS-NORMATIVE-REALIGNMENT-01`. Substitui, só neste ponto, "identidade só por nome + código" (`MMKYU-FRONTEND-REPERTOIRE-DRAFT.md` §13) |
| NS-17 | **Biblioteca em três modos permanece requisito.** Cards (padrão), Lista e Carrossel (N3, B1, B2). Implementação parcial não altera o conceito; o Carrossel é aprovado como experiência e deve ser nativo (a implementação em iframe do spike não é base). | Reafirmação de [D 29/08] em `COLLECTIONS-NORMATIVE-REALIGNMENT-01` |
| NS-18 | **Taxonomia de criação reafirmada.** A criação oferece **"Completar um Set"**, **"Coleção livre"** e, somente após a liberação da P7, **"Completar a Pokédex"** (sem opção desabilitada visível antes disso). **Master Set não é tipo de criação:** é política de completude de uma coleção de Set, configurada em "Ajustes da coleção" (C-23, LDM-21/22, Fluxo 3.4, NS-03). | Reafirmação do Fluxo 1 e de N5–N9 em `COLLECTIONS-NORMATIVE-REALIGNMENT-01` |

### 0.2 Recomendações registradas para homologação formal (`COLLECTION-NORTH-STAR-03`)

Decididas por Fabrício como **recomendadas para homologação**. Ficam registradas aqui, mas **não são normativas** até a homologação formal.

| ID | Recomendação | Situação |
|---|---|---|
| R1 | N8: `STANDARD_SET` apresentado como **Set padrão**, subtítulo "uma de cada carta" | **Homologada como NS-14** |
| R2 | N25: nome inicial "Local padrão" e exibição "Sem localização definida" | **Consolidada como NS-13** (K8 fechado; compatibilidade com C-26, C-36, C-55 e C-59 verificada) |
| R3 | B4 (e toda métrica com volume representativo) medida em **ambiente isolado com dados sintéticos representativos**, sem contaminar dados reais | Aguarda homologação formal. Aplicada ao §4.1 como definição |
| R4 | CT-01: a regra de seleção do local quando o usuário já possui locais permanece **pendente para a proposta técnica** | **Resolvida como NS-15** (regra D-A, `5167`) |

---

## 1. Visão do produto

**Frase-guia [NS-01]:** *Collection é a própria coleção do colecionador em forma digital — ver o que tem, saber o que falta e organizar do seu jeito, sem sentir que está preenchendo um banco de dados.*

1. **Registrar rápido.** Do "tenho estas cartas" ao registro em segundos, inclusive dezenas ou um Set inteiro de uma vez — "explícito não significa manual um a um" [D C-03].
2. **Progresso que motiva.** Ver quanto falta, o que falta e celebrar a completude, calculada pelo sistema e nunca marcada à mão [D C-19, C-20].
3. **Organizar com prazer.** O fichário digital como camada de expressão pessoal, independente da ordem do catálogo [D C-24, C-38].

Princípios vigentes:

- Collection é a primeira superfície para o colecionador e não herda a linguagem administrativa do Catálogo/Pricing: visual-first, premium, motion com propósito, manipulação direta, ações rápidas, operações em lote, responsividade e performance de primeira classe [D checkpoint-08-28 §7].
- `Posse ≠ Composição ≠ Completude ≠ Desejo` [D C-01]. A interface nunca mistura "o que tenho", "o que está nesta coleção", "o que falta" e "o que quero".
- A carta é o conteúdo principal; o chrome é estrutura de apresentação [D diretrizes do projeto].
- Simplicidade na superfície, profundidade sob demanda [NS-03].

### 1.1 Públicos prioritários [NS-02]

| Público | Quem é | O que precisa primeiro | Profundidade que pode ignorar |
|---|---|---|---|
| **Primário — colecionador de Sets** (iniciante a intermediário) | Tem cartas soltas ou caixas de boosters; quer saber "quanto do Set eu tenho" | Fluxos 1, 2, 3 e 5 | Master Set, fichário, local físico, conteúdo planejado |
| **Secundário — colecionador avançado** | Persegue Master Set, organiza fichários, mantém várias coleções e locais físicos | Fluxo 4, Master Set, várias coleções por referência [D C-32] | — |
| **Terciário — colecionador Pokédex** | Quer "um de cada Pokémon" | Coleção Pokédex [D LDM-177–179] | Depende de P7 (condicionada à base funcional) |

Dados de mercado sobre esses públicos: **NÃO DEFINIDOS**.

---

## 2. Os cinco fluxos centrais [NS-04]

As jornadas abaixo são normativas. Tratamentos visuais marcados **[H]** são hipóteses a validar na homologação. "Leitura de tela" significa read model ainda inexistente: o catálogo `card`/`card_variant` só é legível por administradores via RLS [F].

### Fluxo 1 — Primeira coleção

**Objetivo do usuário:** sair da tela vazia para uma coleção com sentido em menos de um minuto.

1. **Estado vazio** que explica o valor (registro rápido, progresso, fichário) e oferece **uma** ação principal: "Criar minha primeira coleção".
2. **Escolha do tipo**, em linguagem de colecionador [NS-18]:
   - "Completar um Set" → Collection com referência Card Set [D C-02, LDM-04–07];
   - "Coleção livre" → curadoria aberta, sem progresso [D C-20];
   - "Completar a Pokédex" → Collection Pokédex [D LDM-177] — só quando P7 for liberada.
   Master Set não aparece aqui (Fluxo 3.4).
3. **Configuração pertinente ao tipo:** "Completar um Set" → escolha do Set com busca visual (logo, nome, código); a referência é definida **antes** da primeira carta, porque a primeira alocação a consolida [D C-11]. "Coleção livre" → nenhuma configuração além do nome. "Completar a Pokédex" → Pokédex e escopo (inteira ou gerações, LDM-177), quando liberada.
4. **Nome sugerido** a partir do Set (ou do tipo), editável; nome não é identidade nem único [D C-07, C-34].
5. **Local da coleção** segundo NS-15: sem nenhum local, nenhuma pergunta [NS-06]; com locais, escolha explícita — ver §2.6.
6. Sucesso leva direto ao Fluxo 2 (todas as coleções) ou ao Fluxo 5 (coleção de Set), nunca a uma tela neutra.

**Backend existente:** `create_storage_container` (`5022`), `create_collection` (`5034`/`5068`), `create_reference_based_card_set_collection` (`5065`/`5069`) [F]. **Necessário:** CT-01 (§2.6); leitura da Biblioteca; busca de Sets para o usuário.

### Fluxo 2 — Adicionar cartas

**Objetivo:** registrar uma ou dezenas de cartas com o mínimo de ações.

1. Botão "Adicionar cartas" sempre presente na coleção.
2. **Seletor de cartas** com busca por nome, número e Set, imagem real em 8:11 e escolha da variante só quando houver mais de uma. Padrão combobox explorado no spike [H].
3. Seleção múltipla com quantidade por carta; idioma escolhido uma vez por lote.
4. **Revisão** antes de confirmar: o que será criado e impedimentos em linguagem humana — nunca códigos internos [F `preview_bulk_operation`].
5. Confirmação com feedback imediato e contagem final; repetir o envio é seguro (idempotência) [F BULK-02].

**Backend existente:** `preview_bulk_operation` (`5151`/`5158`) e `register_physical_cards_bulk` (`5150`/`5155`), até 1.000 cartas por operação, com alocação à coleção e Storage opcionais no mesmo envelope [F]. "Adicionar à coleção uma carta que já tenho" usa `allocate_physical_cards_to_collection` (`5046`, teto 500) [F]. **Necessário:** leitura de catálogo para o seletor; leitura do conteúdo da coleção.

### Fluxo 3 — Ver progresso

**Objetivo:** responder "quanto tenho" e "o que falta" num relance.

1. Cabeçalho da coleção com **progresso como protagonista**: percentual e "X de Y".
2. Alternância "Tenho" / "Faltam" sobre a mesma grade, com faltantes visualmente atenuadas [H].
3. Repetidas visíveis, sem inflar o progresso [D C-21].
4. Profundidade sob demanda: trocar entre Set padrão e Master Set em "Ajustes da coleção" [D C-23, LDM-21], com explicação curta do que muda.
5. Cartas elegíveis que o usuário já possui fora desta coleção podem ser **sugeridas**, nunca alocadas automaticamente [D C-19].
6. Coleção livre não exibe progresso [D C-20].

**Backend existente:** `collection_completion_summary` (`5070`), `collection_completion_positions` (`5071`), `collection_master_set_scope_positions` (`5084`), troca de política (`5080`/`5081`) [F]. **Necessário:** composição dessas leituras com imagem e nome da carta.

### Fluxo 4 — Organizar no fichário

**Objetivo:** dar ao avançado um fichário digital que ele monta do seu jeito.

1. O fichário é **visão opcional** da coleção, criada pelo usuário ("Montar fichário") [NS-05; D C-38: a coleção existe sem Layout].
2. Ao abrir: capa fechada → miolo em páginas 3×3 com navegação explícita (botões, teclado, swipe) [D capa e navegação explícita]. Transição de abertura com continuidade espacial [H].
3. Manipulação direta: mover e trocar cartas entre bolsos, Bandeja para reorganizar, fixar posição, ações rápidas por bolso [D C-43–C-45; H apresentação do spike].
4. Bolsos vazios podem mostrar o conteúdo planejado [D C-42] — avançado, sob demanda.
5. Fichário é organização digital, nunca localização física [D C-44]; a interface não sugere o contrário [NS-09].
6. Bandeja segue a C-45 sem extensão.

**Backend existente:** Layout completo (`5122`–`5137`) [F]. **Necessário:** leitura do fichário com dados de carta. Limitação conhecida: cada bolso é preenchido individualmente (`5131`); não é requisito desta North Star nem do BULK-06.

### Fluxo 5 — Adicionar um Set inteiro

**Objetivo:** "Tenho o Set completo" em uma ação.

1. Disponível no Fluxo 1 (após escolher o Set) e em "Adicionar cartas" de uma coleção de Set.
2. Revisão mostra quantas cartas serão criadas, na variante padrão, e quais Cards não têm padrão definido [F BULK-04].
3. Confirmação com celebração proporcional e convite a ajustar exceções depois [H no tratamento visual].

**Backend existente:** `register_card_set_bulk` (`5157`) e Revisão B2 (`5158`) [F]. **Necessário:** as leituras já citadas.

### 2.6 Primeira coleção sem configuração física e sem estado parcial [NS-06, NS-07]

**Requisitos:** o usuário não configura nada físico; a C-36 é respeitada (toda Collection nasce com Default Storage Container); nenhuma falha deixa estado parcial.

**Experiência normativa:**

1. O usuário só vê: tipo → configuração do tipo (Set, quando houver) → nome → **"Criar coleção"**. Quem já possui locais vê também a escolha explícita do local da coleção, sem pré-seleção (NS-15).
2. Um único botão, uma única espera; durante o processamento o botão mostra progresso e fica inerte; o formulário preserva tudo o que foi preenchido.
3. **Sucesso:** a coleção aparece em "Minhas coleções" e o usuário segue para o Fluxo 2 ou 5.
4. **Falha:** "Não conseguimos criar sua coleção. Nada foi salvo. Tente novamente." — mesmo formulário preenchido, ação "Tentar novamente". O usuário nunca vê coleção pela metade nem local físico órfão.
5. O local padrão só aparece ao usuário avançado, em "Ajustes da coleção → Onde guardo", editável e trocável (`set_collection_default_storage`, `5036`) [F]. Nome provisório "Local padrão"; o usuário identifica ou confirma o lugar real antes da primeira carta atribuída a ele; nenhuma carta é atribuída automaticamente; cartas sem local exibem "Sem localização definida" [NS-13].

**Por que os contratos atuais não bastam [F]:** `create_storage_container` (`5022`) e `create_collection`/`create_reference_based_card_set_collection` (`5034`/`5065`) são atômicas individualmente, mas duas chamadas não formam uma transação; `5022` não é idempotente. Orquestrá-las no cliente ou numa Server Action pode deixar container sem coleção ou containers duplicados.

**Decisão D1:** opção A — operação atômica e idempotente. As opções B (duas chamadas) e C (provisionar no cadastro) estão descartadas.

#### CT-01 — necessidade de contrato técnico (registrada, não implementada)

Requisitos mínimos que a proposta técnica de CT-01 deverá atender:

1. Uma única transação: ou o local padrão e a coleção (com ou sem referência) são gravados juntos, ou nada é gravado.
2. Idempotência por chave do cliente: repetir a mesma requisição devolve o mesmo resultado, sem duplicar coleção nem local.
3. Respeitar integralmente C-36 (Default Storage Container na criação), C-57 (container mediado pelo Inventory do usuário), C-11 (referência consolidada pela primeira alocação) e as regras de `5034`/`5065`.
4. Não alterar nem substituir `5022`, `5034`, `5065` ou qualquer contrato existente.
5. Padrão de segurança vigente: `SECURITY DEFINER` com `search_path` vazio, dono derivado de `auth.uid()`, `EXECUTE` só para `authenticated`, mensagens que não revelam dados de outros usuários.
6. Regra **determinística** para escolher o local padrão quando o usuário já possui um ou mais locais (reaproveitar ou criar) — **resolvida por NS-15** (escolha explícita do usuário; sem escolha automática).
8. *(Nota de rastreabilidade, 2026-10-17.)* A primeira implementação do CT-01 (`5167`, `create_my_card_set_collection`) cobre só coleção de Set (Set padrão). O requisito 1 vale também para coleção **sem** referência (Coleção livre): sua extensão é contrato aditivo ainda não proposto.
7. Harness com isolamento entre usuários, idempotência, falha induzida (prova de ausência de estado parcial) e concorrência de duplo envio.

---

## 3. Nomenclatura da interface [NS-08, NS-09]

Interface em pt-BR, na linguagem do colecionador. Nenhum termo técnico aparece na UI: Physical Card, Allocation, Slot Assignment, Inventory, Layout, Storage Container, `REFERENCE_BASED`, `STANDARD_SET`, `REFERENCE_POSITION`, UUIDs ou códigos de erro.

### 3.1 Conferência N1–N26

Status: **HOMOLOGADO** (normativo) · **HOMOLOGADO COM RESSALVA** (normativo, com a restrição indicada) · **PENDENTE** (não normativo até decisão).

| # | Conceito de domínio | Termo na interface | Fundamento conferido | Status |
|---|---|---|---|---|
| N1 | Collection | **Coleção / Coleções** | D2 (K1-A); C-01 | HOMOLOGADO |
| N2 | Biblioteca de Collections | **Minhas coleções** | Consequência de N1; Biblioteca [D 29/08] | HOMOLOGADO |
| N3 | Modos da Biblioteca | **Lista · Cards · Carrossel** | [D 29/08], REPERTOIRE §13 | HOMOLOGADO |
| N4 | Card Set | **Set / Sets** | D2 (K1-A); glossário já usa "Set" | HOMOLOGADO COM RESSALVA — no catálogo administrativo o rótulo atual "Coleções"/"Coleção" (menu, telas, indicadores, log de atualizações) só muda em tarefa de implementação própria, ainda não autorizada |
| N5 | Curadoria aberta | **Coleção livre** | C-02, C-20 | HOMOLOGADO |
| N6 | Referência Card Set | **Completar um Set** | C-02, LDM-04–07 | HOMOLOGADO |
| N7 | Referência Pokédex | **Completar a Pokédex** | LDM-177 | HOMOLOGADO COM RESSALVA — visível só quando P7 for liberada |
| N8 | STANDARD_SET | **Set padrão** — subtítulo "uma de cada carta" | C-23 | HOMOLOGADO (NS-14) |
| N9 | MASTER_SET | **Master Set** + subtítulo "todas as variantes" | C-23, LDM-21 | HOMOLOGADO |
| N10 | Completion | **Progresso** · "X de Y" · **Faltam** | C-19, C-20 | HOMOLOGADO COM RESSALVA — não aparece em Coleção livre (C-20) |
| N11 | Physical Card | **Carta / Cartas**; no detalhe, **exemplar** | C-47 | HOMOLOGADO |
| N12 | Duplicata | **Repetida(s)** | C-21 | HOMOLOGADO |
| N13 | Inventory | **Meu acervo** | C-48; "Acervo" já usado em `checkpoint-2026-08-28.md` | HOMOLOGADO |
| N14 | Allocation | Verbos: **Adicionar à coleção / Tirar da coleção** | C-03, C-04 | HOMOLOGADO COM RESSALVA — "Tirar da coleção" nunca exclui a carta do acervo; o texto da ação deve deixar isso explícito |
| N15 | Registro em lote / Preview | **Revisar e adicionar** | C-03; BULK-03 | HOMOLOGADO |
| N16 | REGISTER_CARD_SET | **Adicionar o Set inteiro** | BULK-04 | HOMOLOGADO |
| N17 | Collection Layout | **Fichário** | D2 (K2-A); C-38 | HOMOLOGADO |
| N18 | Page | **Página** | C-39 | HOMOLOGADO |
| N19 | Slot | **Bolso** | C-41 | HOMOLOGADO |
| N20 | Spread | *(não aparece; "páginas 3–4" quando necessário)* | C-39 (apresentação) | HOMOLOGADO |
| N21 | Lock | **Fixar / Desafixar** | C-43 | HOMOLOGADO COM RESSALVA — fixa a **posição**; a mensagem nunca sugere que a carta fica presa (C-43) |
| N22 | Expected Content | **Planejado para este bolso** | C-42 | HOMOLOGADO COM RESSALVA — nunca apresentado como faltante nem como parte do progresso (C-42) |
| N23 | Bandeja | **Bandeja** | C-45 | HOMOLOGADO — comportamento estritamente conforme C-45 |
| N24 | Storage Container | **Onde guardo** | D2 (K2-A); C-55 | HOMOLOGADO COM RESSALVA — tipos ("Fichário físico", "Caixa", "ETB") existem só conceitualmente (C-55, enum aberto); o modelo físico atual tem apenas `name` (`5020`). Até haver atributo de tipo, a UI mostra só o nome |
| N25 | Default Storage Container / Physical Card sem Storage | Local: **Local padrão** (nome provisório, renomeável). Carta sem local: **Sem localização definida** | C-36, C-55, C-59, C-26 | HOMOLOGADO COM RESSALVA (NS-13) — confirmação obrigatória do lugar antes da primeira atribuição de carta; nunca destino automático |
| N26 | Archive | **Arquivar / Arquivadas** | C-06, C-37 | HOMOLOGADO |

Resultado: 18 homologados e 8 homologados com ressalva (inclusive N25, regida por NS-13). Nenhuma entrada pendente; nenhuma contraria `C-*`/`LDM-*`.

### 3.2 K1 — resolvido por D2 (K1-A)

"Coleção" para Collection; "Set" para Card Set em todo o produto. Fato [F]: hoje o rótulo "Coleções"/"Coleção" para Card Set existe só no catálogo administrativo (`/catalogo/card-sets`, `requireCatalogoAdmin`; `nav-config.ts`; indicadores; `log-atualizacoes-labels.ts`). A troca desses rótulos é tarefa de implementação separada (ver N4).

### 3.3 K2 — resolvido por D2 (K2-A)

"Fichário" = Layout digital; "Onde guardo" = armazenamento físico; a capa "Binder MMKYU" é identidade visual da coleção e não implica Layout. Na Biblioteca, uma coleção sem fichário continua exibindo a capa.

---

## 4. Critérios normativos de base funcional para P7–P9 [NS-10, NS-11, NS-12]

A base funcional que libera P7, P8 e P9 está pronta somente quando **B1–B8 forem todos aprovados**. O escopo detalhado de P7–P9 continua **NÃO DEFINIDO**; o Fluxo 4 (fichário) não é pré-requisito.

### 4.1 Definições comuns

| Termo | Definição |
|---|---|
| **Ambiente de produção** | Build de produção do `web/` (`next build` + `next start`) ou o deploy oficial, autenticado, apontando para o projeto Supabase `mimikyu-core`. Nunca o servidor de desenvolvimento. Usado só para métricas com dados reais (B1). |
| **Ambiente isolado (R3)** | Build de produção do `web/` apontando para um banco **separado** do projeto de produção, populado só com dados sintéticos. Nenhum dado sintético é gravado em `mimikyu-core`. Forma concreta (ex.: branch do Supabase) a definir antes da primeira medição. |
| **Perfil desktop** | Chrome estável, janela 1440 × 900, sem limitação de CPU ou rede. |
| **Perfil mobile** | Chrome DevTools, emulação de dispositivo com largura de 390 px, CPU 4× mais lenta e rede "Slow 4G" (preset mobile do Lighthouse). |
| **Volume representativo (VR)** | Por usuário de teste: ≥ 20.000 cartas, ≥ 100 coleções, ao menos uma coleção com ≥ 1.000 cartas e uma coleção de Set com ≥ 200 Cards de referência. **Só existe no ambiente isolado (R3):** toda métrica cuja coluna "Volume" indica VR é executada no ambiente isolado. |
| **Usuários de teste** | No mínimo dois usuários (A e B), ambos com VR, além do papel `anon`. |
| **Telas de B1** | Minhas coleções (3 modos), criação da primeira coleção, coleção (grade + progresso), seletor de cartas, Revisão, Adicionar o Set inteiro. |
| **Verificação** | **[auto]** automática · **[med]** medição registrada · **[insp]** inspeção com checklist · **[homol]** homologação expressa de Fabrício. Nenhum critério é declarado aprovado sem a evidência indicada. |

### 4.2 Critérios

**B1 — Fluxos centrais em produção (obrigatório).**

| Métrica | Ambiente | Volume | Método | Critério de aprovação |
|---|---|---|---|---|
| Fluxos 1, 2, 3 e 5 ponta a ponta | Produção | Usuários A e B com dados reais | Roteiro de homologação por fluxo [homol] | 100% dos passos concluídos sem erro |
| Primeira coleção sem estado parcial | Banco do projeto, transação revertida | Fixture do harness de CT-01 | Falha induzida em cada etapa [auto] | Zero linhas residuais de coleção e de local após falha |
| Duplo envio / repetição | Produção e harness | — | Mesma requisição enviada 2× [auto] | Exatamente 1 coleção e 1 local resultantes |
| Lote repetido | Produção | — | Reenvio da mesma confirmação de Fluxo 2 e 5 [auto] | Nenhuma carta duplicada |

**B2 — Qualidade visual premium (obrigatório; aprovação somente por homologação expressa).**

| Métrica | Ambiente | Volume | Método | Critério de aprovação |
|---|---|---|---|---|
| Conformidade com o Design System | Produção, Light e Dark | VR | Checklist por tela [insp]: navegação escura nos dois temas; dourado só em CTA, seleção, foco e destaques; componentes exclusivamente do Design System, sem estilos locais duplicados | 100% dos itens do checklist em todas as telas de B1 |
| Fidelidade das cartas | Produção | VR | Inspeção [insp] | Todas as imagens em 8:11, sem corte, sem distorção |
| Biblioteca | Produção | ≥ 100 coleções | Inspeção [insp] | Três modos aprovados; Cards como padrão; capa "Binder MMKYU" |
| Aprovação final | Produção | VR | **Homologação expressa de Fabrício [homol]**, registrada em `docs/log.md` com data e telas | Aprovação explícita; sem ela B2 não está aprovado, mesmo com checklist completo |

**B3 — Responsividade (obrigatório).**

| Métrica | Ambiente | Volume | Método | Critério de aprovação |
|---|---|---|---|---|
| Ausência de rolagem horizontal | Produção, Light e Dark | VR | Larguras 360, 390, 768, 1024, 1280 e 1440 px; verificação `scrollWidth ≤ largura da janela` [auto/insp] | Zero ocorrências em todas as telas de B1 |
| Ações principais alcançáveis | Mesmo | VR | Inspeção [insp] | Ação principal de cada tela visível ou fixa sem rolagem lateral em todas as larguras |
| Composição adaptada | Mesmo | VR | Inspeção [insp] | Grade reflui; nenhum conteúdo essencial oculto ou truncado sem alternativa de acesso |

**B4 — Fluidez e performance (obrigatório).**

| Métrica | Ambiente | Volume | Método | Critério de aprovação |
|---|---|---|---|---|
| LCP | Ambiente isolado, perfis desktop e mobile | VR | Lighthouse, mediana de 5 execuções por tela [med] | ≤ 2,5 s em cada tela de B1, nos dois perfis |
| CLS | Mesmo | VR | Lighthouse + biblioteca `web-vitals` durante o roteiro de B1 [med] | ≤ 0,1 em cada tela, nos dois perfis |
| INP | Ambiente isolado, perfis desktop e mobile | VR | `web-vitals` (`onINP`) durante o roteiro de B1, 3 execuções [med] | Maior valor por tela ≤ 200 ms |
| Leituras de tela no servidor | Banco do projeto, transação revertida (padrão dos harnesses `5807`/`5813`) | VR em fixture sintética | ≥ 30 execuções por leitura, tempo por execução [med] | p95 ≤ 150 ms por leitura |
| Feedback visual após ação | Ambiente isolado, perfis desktop e mobile | VR | Trace do painel Performance: do evento de entrada ao primeiro quadro com mudança visível [med] | ≤ 100 ms nos dois perfis |
| Ausência de loading artificial | Ambiente isolado | VR | Inspeção de código e de trace [insp] | Nenhum atraso intencional; skeleton no formato do conteúdo final |
| Listas grandes | Ambiente isolado | VR | Inspeção de rede [insp] | Nenhuma requisição carrega o acervo inteiro; listas paginadas ou virtualizadas, com tamanho de página definido na proposta técnica |
| Animações | Ambiente isolado, perfil desktop | VR | Trace durante cada transição [med] | Apenas `transform`/`opacity`; zero tarefas longas (> 50 ms) durante a transição |

**B5 — Acessibilidade (obrigatório).**

| Métrica | Ambiente | Volume | Método | Critério de aprovação |
|---|---|---|---|---|
| Regras WCAG 2.1 A/AA | Produção, Light e Dark | VR | axe-core em todas as telas de B1 [auto] | Zero violações *critical* e *serious* |
| Teclado | Produção | VR | Roteiro manual de B1 só com teclado [insp] | 100% dos fluxos concluídos; foco sempre visível; sem armadilha de foco |
| Leitor de tela | Produção, Windows + Chrome + NVDA | VR | Roteiro manual [insp] | Rótulos, estados e resultados assíncronos anunciados (`aria-live`), inclusive criação, erro e conclusão de lote |
| Contraste | Produção, Light e Dark | — | Medição [med] | Texto ≥ 4,5:1; texto grande ≥ 3:1; componentes e foco ≥ 3:1 |
| Alvos de toque | Perfil mobile | — | Medição [med] | ≥ 44 × 44 px |
| Informação não só por cor | Produção | — | Inspeção [insp] | Progresso e "Faltam" sempre com texto |
| Movimento reduzido | Produção com `prefers-reduced-motion: reduce` | — | Inspeção [insp] | Nenhuma animação não essencial |

**B6 — Estados e feedback (obrigatório).**

| Métrica | Ambiente | Volume | Método | Critério de aprovação |
|---|---|---|---|---|
| Estados por tela | Produção | Usuário vazio e usuário com VR | Checklist [insp]: vazio, carregando, sucesso, erro, parcial (lote), nova tentativa | 100% dos estados presentes em todas as telas de B1 |
| Linguagem | Produção | — | Inspeção [insp] | Nenhum código interno, UUID ou enum visível; toda mensagem diz o que aconteceu e o que fazer |
| Estado vazio da Biblioteca | Produção | Usuário sem coleções | Inspeção [insp] | Explica o valor e oferece uma única ação principal |

**B7 — Segurança e isolamento (obrigatório).**

| Métrica | Ambiente | Volume | Método | Critério de aprovação |
|---|---|---|---|---|
| Isolamento entre usuários | Banco do projeto, transação revertida | Usuários A e B + `anon` | Harness de cada leitura e operação nova [auto] | 100% PASS: A não lê, altera nem descobre a existência de dados de B; `anon` sem acesso; resíduo zero |
| Privilégios | Banco do projeto | — | Harness estrutural [auto] | Funções privilegiadas com `search_path` vazio; `EXECUTE` mínimo; helpers internos sem `EXECUTE` para `authenticated` |
| Security Advisor | Banco do projeto | — | Comparação antes × depois [auto] | Nenhum alerta novo sem aceitação expressa e específica de Fabrício |
| Rotas experimentais | Deploy de produção | — | Requisição não autenticada a `/experimental/*` [auto] | Nenhuma rota experimental acessível sem proteção |

**B8 — Documentação reconciliada (obrigatório).**

| Métrica | Ambiente | Volume | Método | Critério de aprovação |
|---|---|---|---|---|
| Coerência documental | Repositório | — | Lint documental registrado em `docs/log.md` [insp] | Zero contradições entre 05d, ROADMAP, README, HANDOFF, glossário e esta North Star |

### 4.3 Onde cada dimensão é avaliada

| Dimensão | Critério principal | Apoio |
|---|---|---|
| Qualidade visual premium | **B2** (homologação expressa) | B1, B6 |
| Responsividade | **B3** | B5 (alvos de toque) |
| Fluidez | **B4** | B6 |
| Acessibilidade | **B5** | B3 |
| Segurança | **B7** | B1 (idempotência, estado parcial) |

---

## 5. Conceitos de UX: homologados × hipóteses × descartados

Critério: **homologado** = aprovado por Fabrício e registrado; **hipótese** = explorado em spike, sem aprovação de produto; **descartado** = rejeitado e registrado. Validação em spike não equivale a homologação: o checkpoint de 29/08 registra o `binder-nav-01` como "validado para informar o domínio", não como produto [F].

### 5.1 Homologados

| Conceito | Registro da aprovação |
|---|---|
| Biblioteca em três modos (Lista, Cards, Carrossel), mesmo núcleo de dados, Cards como padrão | `docs/log.md` 29/08 (`COLLECTION-LIBRARY-VIEW-MODES-01`); `checkpoint-2026-08-29.md` §3 |
| Nomes "Lista / Cards / Carrossel" na UI | `MMKYU-FRONTEND-REPERTOIRE-DRAFT.md` §13 |
| Capa "Binder MMKYU" como referência visual | Aprovação após 23 rodadas; `checkpoint-2026-10-15.md` §D; `.claude/skills/mmkyu-frontend-experience/SKILL.md` §6. **Evoluída por NS-16** (cor por coleção, identidade oficial do Set, fallback tipográfico) — direção aprovada, implementação pendente de homologação |
| Carrossel com engine Character Filmstrip e skin Binder MMKYU — **como experiência**; a implementação atual em iframe não é base | log 29/08; `checkpoint-2026-10-15.md` §D |
| Navegação explícita entre páginas do fichário (sem virada física) | Decisão de 28/08 |
| Bandeja como estado transitório da sessão de edição, descartada ao sair | C-45 |
| Fixação protege o bolso, não a carta | C-43 |
| Fichário independente da ordem do catálogo; spread é só apresentação | C-24, C-39 |
| Hero da página interna da coleção como baseline visual: fichário 3D com seleção direta das seis cores, título e identidade, régua de evolução, leque das cinco cartas do Set (curadoria por Set quando definida), sombras e enquadramento, separação editorial hero/galeria. Novos microajustes só com problema concreto identificado na homologação | `docs/log.md` 17/10 (`COLLECTION DETAIL HERO — ENCERRAMENTO VISUAL`); `05d` (nota da página da coleção). Validações funcionais e responsivas no navegador continuam pendentes |
| Direção visual-first, premium, manipulação direta, ações rápidas, lote | `checkpoint-2026-08-28.md` §7 |
| Visão, públicos, cinco fluxos, fichário opcional, primeira coleção sem configuração física, nomenclatura homologada, B1–B8 | **Esta North Star (NS-01–NS-12; complementada por NS-13–NS-18)** |

Correção de fidelidade, não decisão de UX: proporção 8:11 medida em assets reais [F].

### 5.2 Hipóteses — não normativas

| Hipótese | Origem | O que precisa para virar decisão |
|---|---|---|
| Alternador "Tenho / Faltam" com faltantes atenuadas | North Star (Fluxo 3) | Homologação com dados reais |
| Celebração visual ao completar ou adicionar o Set inteiro | North Star (Fluxo 5) | Homologação com dados reais |
| Arrastar e soltar acessível (mouse, toque, teclado, anúncios pt-BR) | `binder-nav-01` | Homologação no Fluxo 4 |
| Seletor de cartas no padrão combobox | `binder-nav-01` | Homologação no Fluxo 2 |
| Ações rápidas por bolso com menu de overflow | `binder-nav-01` | Validar densidade com dados reais |
| Seleção múltipla com ações em lote no fichário | `binder-nav-01` | Validar no Fluxo 4 |
| Tool Rail com botões sempre visíveis, inclusive desabilitados | `binder-nav-01` | Conflita com NS-03 (K6) |
| Navegação por borda durante arraste (~650 ms) | `binder-nav-01` | Teclado não atravessa páginas [F] |
| Abertura do fichário com View Transition | `binder-spike`, `collection-space` | Cumprir B4 e B5 |
| Acabamento da capa: placa do logo e foil do código *(a paleta de 6 cores saiu desta lista — aprovada na decisão K12, NS-16)* | `MY-COLLECTIONS-LIBRARY-VISUAL-02` (`web/components/colecoes/colecoes/binder-cover.tsx`) | Homologação B2 |
| Bandeja sobrevivendo à troca de páginas na mesma sessão | `binder-nav-01` | Não adotada; vale a C-45 |
| Máquina de estados Estante → Foco → Abrir | `mmkyu-shelf` | Só para Showcase/perfil futuro |
| Wave em Social/Perfil | `collection-wave-spike-01` | Fora do escopo de Collection |

### 5.3 Descartados

| Conceito | Registro |
|---|---|
| Virada de página física (scroll ou 3D) | Rejeitada em 28/08 |
| Hero Card pura (variante B) e Binder + Hero Artwork (variante C) | `COLLECTION-FILMSTRIP-BINDER-FIDELITY-01` — "AVOID, não reabrir" |
| Character Wave na Biblioteca | `ux-exploration` §G |
| Complete Shelf / 3D WebGL na tela operacional | `ux-exploration` §G |
| Visual Gallery como modo principal | `MMKYU-FRONTEND-REPERTOIRE-DRAFT.md` |
| Barras de ações em lote horizontais (`BulkActionBar`, `BulkActionRail`) | `ux-exploration` §G |
| Opções B e C da primeira coleção | D1 |

Fora da classificação de UX: o componente `binder-pages-nav.tsx` (1.848 linhas) é limitação técnica do spike [F] e não serve de base de implementação.

---

## 6. Conflitos e pendências

| # | Item | Situação |
|---|---|---|
| K1 | "Coleções" nomeia Card Set no catálogo administrativo | **Resolvido (D2, K1-A).** Troca dos rótulos admin pendente de tarefa de implementação autorizada (N4) |
| K2 | "Fichário/Binder" com três sentidos | **Resolvido (D2, K2-A)** |
| K3 | C-36 × criação sem estado parcial | **Resolvido (D1, opção A).** Depende de CT-01, ainda não proposto |
| K4 | Texto de C-10 ("Visual Collection Space / Carousel de Storage Containers") descreve direção superada pela Biblioteca de 29/08 | **Pendente.** C-10 já tem status "Superseded / Evoluída", mas seu texto não aponta para a Biblioteca. Esta North Star não altera C-*; a anotação de C-10 depende de autorização específica |
| K6 | Tool Rail sempre visível × NS-03 | **Pendente.** Hipótese; decidir na homologação do Fluxo 4 |
| K7 | Rotas `/experimental/*` sem verificação de sessão | Coberto por B7 |
| P1 | N8 — nome de STANDARD_SET | **Resolvido** (NS-14) |
| P2 | N25 — nome do local padrão e exibição de carta sem local | **Resolvido** (NS-13) |
| P3 | Ambiente de dados para VR (B4) | **Recomendado (R3):** ambiente isolado com dados sintéticos; forma concreta a definir antes da primeira medição |
| P4 | CT-01 — regra de seleção do local | **Resolvido (NS-15, regra D-A).** *(Antes: pendente para a proposta técnica, R4.)* |
| K8 | Local padrão × C-26, C-36, C-55, C-59 | **Resolvido** (`COLLECTION-NORTH-STAR-K8`, caminho 1 → NS-13). **C-36:** o local é criado junto com a coleção e segue como destino sugerido, alterável. **C-55:** representa um lugar físico real; o nome é só atributo descritivo (`5020`), e nenhuma decisão exige que o lugar esteja identificado na criação. **C-59:** container pode existir vazio, e nenhuma carta recebe localização não confirmada, logo toda localização registrada é confiável. **C-26:** carta sem local continua sem Storage. Requisito para propostas futuras: toda tela que atribui carta ao local padrão (Fluxo 2, Fluxo 5, `5024`) pede confirmação explícita a cada operação; a presença de cartas não comprova confirmação; o backend não a impõe |

| K9 | Capa: "identidade só por nome + código" (`MMKYU-FRONTEND-REPERTOIRE-DRAFT.md` §13, 29/08) × cor por coleção e logo do Set (`MY-COLLECTIONS-LIBRARY-VISUAL-02`, 17/10) | **Resolvido (NS-16).** O registro de 29/08 é preservado como histórico, com nota de evolução no DRAFT §13 e no SKILL §6 |
| K10 | NS-06/§2.6 "nenhuma pergunta sobre local físico" × regra D-A da `5167` (escolha explícita quando há locais) | **Resolvido (NS-15).** NS-06 vale integralmente para quem não tem locais |
| K11 | Comentário da R1 (`5168`) descreve um campo de "capa" com a arte da carta alocada mais recentemente | **Pendente, não bloqueante.** O campo existe no contrato LIVE, mas pela NS-16 nunca é usado como capa automática. Corrigir o comentário exige nova versão da função (fora desta rodada) ou anotação em 05d (feita) |
| K12 | Proposta `5171` fixa por CHECK um vocabulário fechado de 6 cores × NS-16 (paleta não decidida) | **Resolvido (decisão K12, 2026-10-17):** Fabrício aprovou a paleta fechada de seis cores da 5171 para a versão atual (NS-16). *(Antes: pendente — proposta não executável sem fechar a paleta.)* |
| K13 | Coleção livre: tipo homologado (N5) × README de `my-collections-foundation` ("não indispensável nesta rodada") | **Resolvido.** O recorte foi só de rodada de implementação; N5/NS-18 permanecem vigentes |

Bandeja: C-45 vigente, sem extensão. Preenchimento em lote do fichário: limitação conhecida, não requisito do BULK-06.

---

## 7. Rastreabilidade conceito → experiência → implementação

**Governança desta seção.** Colunas "Decisão/fonte" e "Referência visual" são normativas (alteração segue §0.5). Colunas "Implementação", "Homologação" e "Dependência" são **informativas**: devem ser atualizadas no mesmo ciclo de qualquer implementação de Collection, com linha em `docs/log.md`, sem nova versão normativa. Estado físico detalhado continua em `05d-colecoes-e-usuarios.md`.

Legenda — Implementação: **LIVE** (backend no banco) · **FE-pub** (frontend publicado) · **FE-local** (frontend local, não commitado) · **—** (não implementado). Homologação: **HOM** (homologação expressa registrada) · **dir.** (direção aprovada, sem homologação final) · **pend.** (pendente) · **n/a**.

| Capacidade | Decisão / fonte normativa | Referência visual / spike | Implementação (2026-10-17) | Homologação | Dependência / lacuna |
|---|---|---|---|---|---|
| Biblioteca — Cards (padrão) | N2, N3, NS-17; log 29/08 | `collection-library-view-modes-01`; `premium-grid.tsx` | FE-local (`library-view.tsx`) | pend. | B2 |
| Biblioteca — Lista | N3, NS-17 | `collection-list-view.tsx` | FE-local (`library-list.tsx`, seletor `library-modes.tsx`) | pend. | Só frontend (R1 existente); homologação visual B2 |
| Biblioteca — Carrossel | N3, NS-17; NS §5.1 (experiência, não iframe) | `collection-library-carousel-mmkyu-*.html` (referência) | FE-local, nativo (`library-carousel.tsx`, motor do Filmstrip, capa do fichário) | pend. | Só frontend (R1 existente); homologação visual e de interação (mouse, teclado, toque) |
| Tipos de criação | NS-18; Fluxo 1.2; N5–N7 | — | Parcial: só "Completar um Set", sem passo de tipo | pend. | Coleção livre exige CT-01 estendido |
| Criação atômica e idempotente | NS-06, NS-07, D1, CT-01 | — | LIVE `5166`/`5167` (Set); FE-local | pend. | Extensão do CT-01 para Coleção livre |
| Local da coleção na criação | NS-13, NS-15 (D-A), C-36 | — | LIVE `5167`; FE-local | pend. | — |
| Continuidade após criar (Fluxo 2/5) | Fluxo 1.6 | — | — (termina em texto + "Adicionar as que já tenho") | pend. | Reaproveitar ações do Meu acervo (contratos LIVE) |
| Adicionar cartas (Fluxo 2) | Fluxo 2; N14, N15 | `binder-nav-01` (combobox, [H]) | FE-pub no Meu acervo (sem alocação à coleção) | dir. | Na coleção: envelope de alocação de `5150` (LIVE) |
| Adicionar o Set inteiro (Fluxo 5) | Fluxo 5; N16 | — | FE-pub no Meu acervo (sem alocação à coleção) | dir. | Na coleção: envelope de `5157` (LIVE) |
| Vincular exemplares que já tenho | C-03, C-19, C-04; Fluxo 3.5 | — | LIVE `5170`/`5046`; FE-local ("1 de cada", D-C) | pend. | Master Set/Pokédex sem leitura de candidatos |
| Progresso / Tenho · Faltam / repetidas | C-19–C-21; Fluxo 3; N10, N12 | — | LIVE `5168`/`5169`; FE-local | pend. | Tenho/Faltam é [H] |
| Coleção livre | N5, NS-18; C-20 (sem progresso) | — | Backend parcial: `5034` (exige local; não atômico com ele); R1 já devolve progresso nulo | n/a | **SQL:** CT-01 para coleção sem referência. Conteúdo: `5159` filtrada (LIVE) |
| Ajustes da coleção — nome | C-07, C-34 | — | FE-local (`5035`) | pend. | — |
| Ajustes — Onde guardo | Fluxo 3/§2.6.5; N24; NS-13 | — | LIVE `5036`; — FE | n/a | Só frontend |
| Ajustes — Set padrão ↔ Master Set | C-23; LDM-21/22; Fluxo 3.4; N8/N9 | — | LIVE `5080`–`5084`; — FE | n/a | **SQL:** leitura das versões do Set para o colecionador (escopo explícito) e posições com imagem |
| Coleção Pokédex | LDM-175–185; N7; NS-18 | — | LIVE Fatias A–E; — FE | n/a | **Bloqueada:** P7 / B1–B8 |
| Capa do fichário (fechado) | NS-16; SKILL §6 (baseline 29/08) | `binder-cover-closed.tsx` (aprovado); `binder-cover.tsx` (evolução) | FE-local; LIVE `5171`–`5174` (cor persistida, logos legíveis) | dir. + paleta aprovada / pend. (acabamento, B2) | Homologação visual B2 |
| Fichário aberto | NS-05; Fluxo 4; navegação explícita [D 28/08]; virada física rejeitada | `binder-nav-01` (hipóteses) | LIVE Layout `5104`–`5141`; — FE | n/a | Leitura do fichário com dados de carta; fora da base funcional |
| Manipulação no fichário | C-41–C-46; N19–N23 | `binder-nav-01` (DnD, Tool Rail, Bandeja = [H]) | LIVE (RPCs de Layout); — FE | n/a | Homologação no Fluxo 4; K6; Bandeja conforme C-45 |
| Organização física (Onde guardo / local dos exemplares) | C-55–C-66; C-26; NS-09, NS-13 | `collection-space` (superado) | LIVE `5020`–`5024`; — FE dedicado | n/a | Confirmação a cada atribuição ao local padrão |

---

## Revision History

| Versão | Descrição |
|---|---|
| 0.1 | **Proposta inicial (2026-10-16, `COLLECTION-NORTH-STAR-01`).** Visão, públicos, cinco fluxos sobre o backend existente, nomenclatura, critérios de base funcional, classificação dos spikes, conflitos e questões. Status PROPOSTO. |
| 0.2 | **Complementos pedidos por Fabrício (2026-10-16), após aprovação conceitual da direção.** §2.6 (primeira coleção sem configuração física, alternativas A/B/C); tabela N1–N26 com alternativas para K1 e K2; texto integral de B1–B8; separação entre homologados, hipóteses e descartados. Bandeja conforme C-45; preenchimento em lote do fichário desvinculado do BULK-06. |
| 1.0 | **Consolidação normativa (2026-10-16, `COLLECTION-NORTH-STAR-02`).** Status passa a NORMATIVO após as decisões D1–D4 de Fabrício. §0 novo (governança, precedência de `C-*`/`LDM-*`, NS-01–NS-12). D1: opção A, CT-01 registrado com requisitos mínimos e não implementado. D2: K1-A e K2-A; conferência N1–N26 com 17 homologados, 8 com ressalva e 1 pendente (N8), além do nome inicial de N25. D3: B1–B8 normativos, cada métrica com ambiente, volume, método e critério; B2 exige homologação expressa. D4: North Star como referência normativa de experiência. Pendências K4, K6, P1–P3 registradas. Nenhuma `C-*`/`LDM-*` alterada. |
| 1.1 | **Fechamento documental (2026-10-16, `COLLECTION-NORTH-STAR-03`).** §0.2 novo com as recomendações R1–R4 (N8 "Set padrão", N25 "Sem localização definida", B4 em ambiente isolado com dados sintéticos, regra de seleção do CT-01 pendente), todas não normativas até homologação formal. §4.1: "Ambiente isolado" definido; volume representativo restrito a ele; métricas de B4 movidas para o ambiente isolado. Conflito K8 (R2 × C-26/C-36/C-55/C-59) registrado sem resolução. C-10, K6 e contratos existentes preservados; nenhuma `C-*`/`LDM-*` alterada. |
| 1.2 | **Correção de nomenclatura N25 (2026-10-16, `COLLECTION-NORTH-STAR-04`).** R2 revisada: nome inicial "Local padrão" para o local criado pelo CT-01, sem atribuição automática de cartas; "Sem localização definida" para cartas sem local (C-26). K8 passa a STOP parcial: compatível com C-26 e C-36; contradição residual com C-55/C-59 registrada, sem homologação. R1, R3 e R4 inalteradas; nenhuma `C-*`/`LDM-*` alterada. |
| 1.3 | **K8 fechado (2026-10-16, `COLLECTION-NORTH-STAR-K8`).** Caminho 1 adotado e verificado compatível com C-26, C-36, C-55 e C-59; consolidado como NS-13 ("Local padrão" como nome provisório de um lugar real, confirmação antes da primeira carta, nenhuma atribuição automática, "Sem localização definida" para carta sem local). R2, N25, §2.6, P2 e K8 atualizados. Nenhuma `C-*`/`LDM-*` alterada. |
| 1.4 | **Fechamento (2026-10-16, `COLLECTION-NORTH-STAR-05`).** N8 homologado como "Set padrão — uma de cada carta" (NS-14; R1 e P1 encerrados). NS-13 corrigida: a presença de cartas deixa de valer como evidência de confirmação; confirmação explícita exigida em toda operação de atribuição ao local padrão (Fluxos 2 e 5, `5024`), sem campo novo. K8 segue resolvido; R3 e R4 mantidas. Nenhuma `C-*`/`LDM-*` alterada. |
| 1.5 | **Realinhamento normativo (2026-10-17, `COLLECTIONS-NORMATIVE-REALIGNMENT-01`, decisões D1–D6 de Fabrício).** Novas NS-15 (regra D-A do local na criação; fecha R4/P4; distingue local padrão da coleção de localização física do exemplar), NS-16 (capa: fichário 3D premium com zíper e identidade MMKYU, cor persistente por coleção, identidade oficial do Set quando disponível, fallback tipográfico, nunca carta como capa automática; paleta e acabamento **não** decididos, pendentes de B2), NS-17 (Biblioteca em três modos permanece requisito) e NS-18 (taxonomia de criação: Set, Coleção livre, Pokédex só com P7; Master Set é ajuste, não tipo). Fluxo 1 e §2.6 ajustados (configuração por tipo, local conforme NS-15, continuidade Fluxo 2/5); nota de rastreabilidade do CT-01 (requisito 1 inclui coleção sem referência). §5.1/§5.2 anotados; conflitos K9–K13 registrados (K9, K10 e K13 resolvidos; K11 e K12 pendentes, não bloqueantes). §7 novo: matriz de rastreabilidade com colunas normativas e informativas. Fluxo 4/fichário: sem mudança (D6 preserva a classificação do §5). Nenhuma `C-*`/`LDM-*` alterada. **Adendo (2026-10-17, decisão K12 de Fabrício):** paleta fechada de seis cores (Ônix, Vinho, Floresta, Marinho, Caramelo, Pérola) aprovada para a versão atual e registrada na NS-16, com evolução futura condicionada a nova decisão; §5.2 deixa de listar a paleta como hipótese; K12 resolvido; matriz §7 atualizada. Capa e logos não reabertos. |
| 1.6 | **Hero da coleção aprovado como baseline visual (2026-10-17, `COLLECTION DETAIL HERO — ENCERRAMENTO VISUAL`).** §5.1: nova linha homologando a composição do hero da página interna (fichário 3D + seis cores, título/identidade, régua, cinco cartas, sombras/enquadramento, separação hero/galeria). Encerra as rodadas de refinamento estético desse componente; homologação funcional/responsiva no navegador segue pendente. |
