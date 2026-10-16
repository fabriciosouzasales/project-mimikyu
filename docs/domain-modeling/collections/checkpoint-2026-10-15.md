# Collection — Checkpoint do Diagnóstico Integral (2026-10-15)

| Campo | Valor |
|--------|-------|
| **Documento** | Checkpoint histórico-factual — diagnóstico integral de produto, histórico e experiência de Collection |
| **Arquivo** | `docs/domain-modeling/collections/checkpoint-2026-10-15.md` |
| **Data do diagnóstico** | 2026-10-15 (resposta do agente às 2026-10-16 02:19:59 UTC = 2026-10-15 23:19:59, horário de Brasília) |
| **Origem** | Rodada "Collection — Diagnóstico Integral de Produto, Histórico e Experiência" (só leitura), pedida por Fabrício após o encerramento da Pokédex P6. Incorporado em `DOC-GATE-01` (fechamento autorizado após auditoria independente). |
| **SHA-256 do conteúdo original** | `9e6ddea8f51711e9e4952870690468a9b9229b110831b21cf349a242622e5e36` |
| **Natureza** | **Histórico-factual. Não é fonte normativa.** Retrato do estado de Collection em 2026-10-15. Decisões canônicas continuam em `concept-decisions.md`, `logical-model.md` e `05d-colecoes-e-usuarios.md`; números do dia (por exemplo, linhas de código de spikes) não são mantidos atualizados. |
| **Legenda** | **[F]** fato documentado ou visível no código · **[I]** inferência · **[D]** decisão aprovada (já registrada nas fontes canônicas) · **[R]** recomendação nova |
| **Recomendações** | Itens **[R]** **não constituem decisões aprovadas**. Só passam a valer se aprovados por Fabrício e registrados no artefato normativo correspondente (ADR, `concept-decisions.md`, `logical-model.md`, ROADMAP). |
| **Ressalvas abertas citadas no texto** | Conflito da Bandeja (C-45/LDM-36 × `ux-exploration-2026-08-29.md`) e nome "Coleções" na UI — pendentes de decisão; ver `docs/development/HANDOFF-2026-10-15.md` §7. |

**Integridade.** O texto entre os marcadores `ORIGINAL-BEGIN` e `ORIGINAL-END` é a cópia literal do diagnóstico, sem nenhuma edição (seções A–H). Os bytes entre a quebra de linha que encerra a linha `ORIGINAL-BEGIN` e a quebra de linha que antecede a linha `ORIGINAL-END` têm o SHA-256 acima. Verificação:

```
python3 -c "import hashlib,re;s=open('docs/domain-modeling/collections/checkpoint-2026-10-15.md','rb').read();b=re.search(rb'<!-- ORIGINAL-BEGIN[^\n]*-->\n(.*)\n<!-- ORIGINAL-END -->',s,re.S).group(1);print(hashlib.sha256(b).hexdigest())"
```

---

<!-- ORIGINAL-BEGIN sha256=9e6ddea8f51711e9e4952870690468a9b9229b110831b21cf349a242622e5e36 -->
Isto é só diagnóstico. Não alterei código, banco nem documentação, não executei SQL e não fiz nada no git. Cruzei quatro levantamentos independentes: decisões de domínio, backend, spikes visuais e linha do tempo (git e `docs/log.md`).

Marcação usada: **[F]** fato documentado ou visível no código · **[I]** inferência minha · **[D]** decisão aprovada · **[R]** recomendação nova, que depende de autorização.

---

## A. Sumário executivo

**Estado atual em três frases.**
- O domínio está modelado e aprovado: C-01 a C-186 e LDM-01 a LDM-190. O backend está implantado e validado, com 18 fundações confirmadas no LIVE entre 31/08 e 09/09.
- **Não existe nenhuma tela real de Collection.** Nenhum arquivo em `web/app`, `web/lib` ou `web/components` chama RPCs ou tabelas de Collection [F].
- A experiência visual existe apenas em 12 spikes sob `/experimental`, todos com dados simulados. Só dois deles têm aprovação formal: os três modos da Biblioteca e a capa do Binder fechado [F].

**Principais ativos já construídos.**
1. **Backend completo da cadeia patrimonial.** Cobre Inventory, Physical Card, Storage, Collection (criar, arquivar, excluir), Allocation, Reference (Set e Pokédex), Completion (STANDARD_SET, MASTER_SET e REFERENCE_POSITION), Master Set Scope, Binder/Layout (6 tabelas e 14 RPCs) e operações em lote BULK-01 a 03 (ledger idempotente, registro em lote e preview).
   - Segurança: todas as escritas passam por RPCs `SECURITY DEFINER`, com RLS de leitura restrita ao dono e mensagens que não revelam a existência de dados de outros usuários.
   - Gates com resultados registrados, por exemplo 5818 com 196/196, 5812 com 114/114 e 5822 com 64/64.
   - Performance medida com 20 a 32 mil cartas: as leituras de tela ficaram entre 5 e 150 ms [F].
2. **Modelo de domínio maduro.** As distinções "Posse ≠ Composição ≠ Completude ≠ Desejo" estão resolvidas. Favorite de carta, Wishlist, Condition, Grading, Custódia, Colaboração e Histórico estão modelados em nível lógico [F].
3. **Workspace de Binder funcional sobre mock** (`binder-nav-01`, cerca de 6.900 linhas). Tem arrastar e soltar acessível (mouse, toque e teclado), seletor de cartas, Bandeja, seleção múltipla com ações em lote e tela cheia [F].
4. **Decisão de arquitetura da Biblioteca:** três modos (Lista, Cards como padrão e Carrossel) e o visual da capa do Binder fechado [D].

**Lacunas principais.**
- Faltam leituras para a tela (read models) de listagem e navegação: biblioteca, conteúdo da coleção e fichário com dados de carta. O catálogo `card`/`card_variant` só é legível por administradores via RLS, então a tela vai precisar de leituras novas [I].
- Faltam BULK-04, 05 e 06. Só BULK-04 tem escopo identificado; o BULK-06 não tem definição em nenhum documento [F].
- Favorite de carta, Wishlist, Condition, Grading, Histórico e Colaboração não têm modelo físico [F].
- O Carrossel aprovado só existe como HTML num iframe e não consegue receber dados reais [I].

**Riscos de topo.**
1. As rotas `/experimental/*` não exigem login, e o `middleware.ts` foi removido. Se esses arquivos estiverem no deploy, qualquer pessoa com a URL abre os spikes [F na ausência de proteção; I no impacto].
2. A documentação está desatualizada em vários pontos: o `logical-model` e o glossário dizem "físico não iniciado", e o HANDOFF vigente ainda aponta "NEXT = Pricing 80". Isso induz decisões erradas [F].
3. A escala visual é inédita. Os spikes trabalham com até 24 coleções e um fichário de 224 bolsos, enquanto o requisito pede milhares de cartas [I].

---

## B. Linha do tempo

| Data | Marco | Tipo |
|---|---|---|
| 22/07 | ADR-013 (Collection Item) e ADR-014 (Collection Entry) | concepção, depois **substituída** |
| 09/08 | Sequência Catálogo Editorial → Card Variant → Coleções. A posse precisa referenciar uma variante sem ambiguidade | decisão |
| 10/08 | C-01 a C-37 fechadas e gate arquitetural aprovado no repositório paralelo de modelagem | decisão |
| 15/08 | Benchmark PkmnBindr | pesquisa |
| 23 a 26/08 | Collections confirmada como próxima frente | decisão |
| 28/08 | Reconciliação. ADR-013 e 014 substituídas; Inventory 1:1 por usuário; "Collections é a primeira superfície visual para o cliente"; virada de página física rejeitada; spikes collection-space, binder-spike e binder-motion | decisão + spike |
| 29/08 | Shelf, Wave, Filmstrip (de AVOID para USE no mesmo dia), Gallery, View Modes. **Três modos da Biblioteca aprovados**; capa do Binder fechado aprovada como referência visual | spike + **[D]** |
| 30/08 | Fase visual **pausada**. Layout/Page/Slot (C-38 a C-46); Physical Card como termo canônico; Custódia, Storage, Ciclo de vida, Favorite, Wishlist, Condition, Grading, Colaboração e Histórico fechados (até C-186); reconciliação transversal | domínio |
| 31/08 a 02/09 | 01B Inventory/Physical Card · 02A Storage · 02B Collection · 02C Allocation · 02D Reference · 02E STANDARD_SET · 02F MASTER_SET | backend |
| 03 a 06/09 | Pokédex: modelagem, espécies, regiões, carga de 1.025 espécies e Fatias A a E (escopo, posições, representante, completude) | backend |
| 07 a 09/09 | Binder/Layout Foundation · BULK-01 · BULK-02 · BULK-03. **Collections pausa aqui** | backend |
| 09/09 a 11/10 | Fechamento do catálogo de Card Variants (CLOSED em 11/10) → "Próximo: Collections — BULK-04" | decisão |
| 14/10 | Frente A: P5 → P6 → **Módulo Collection (base funcional)** → P7 → P8 → P9 | **[D]** |
| 15/10 | P6 publicada; retomada de Collection | — |

---

## C. Matriz funcional

| Capacidade | Objetivo do usuário | Domínio | Backend | Frontend | Evidência | Dependências e lacunas |
|---|---|---|---|---|---|---|
| Registrar exemplares (Physical Card) | "Tenho esta carta" | [D] C-47/48 | **LIVE/VALIDADO** 5000–5012; 500 por chamada | spike (Picker mock) | 5800 com 23 itens; 52 ms para 500 cartas | Leituras do catálogo para busca e seleção [I] |
| Registro em lote com preview | Cadastrar dezenas de cartas de uma vez | [D] C-03, C.4 | **LIVE** BULK-01/02/03; até 1.000 cartas | nenhum | 5821 39/39; 5822 64/64; 5823 60/60; preview em 338 ms com 1.000 | BULK-04 (Set inteiro), BULK-05 (migrar chamadores antigos), BULK-06 (indefinido); preview deve rejeitar variante inativa |
| Coleções: criar, editar, arquivar, excluir | Organizar a posse | [D] C-01 a C-37 | **LIVE** 02B | spike (Biblioteca mock) | 5804; listagem de 20 mil em 8,5 ms | Read model da biblioteca com contagens e capa [I] |
| Alocar cartas a uma coleção | "Esta carta faz parte desta coleção" | [D] C-04, C-147 | **LIVE** 02C; até 500 | nenhum | 5806 49/0; 500 cartas em 50 ms | — |
| Referência: Set ou Pokédex | Medir contra um universo | [D] LDM-04 a 07, LDM-177 | **LIVE** 02D e Fatia B | nenhum | 5808 25/0 | Fluxo de conversão de modo **não modelado** (C-09/C-11) |
| Progresso: STANDARD, MASTER, POSITION | Ver o quanto falta | [D] C-19 a 23, LDM-20 a 22 | **LIVE** 02E, 02F, Fatia E | nenhum | Telas entre 5 e 145 ms; bloqueio de performance corrigido (1,36 s → 8 ms) | Concorrência da Fatia D (caso 20b) **NÃO PROVADA** |
| Escopo do Master Set | Escolher quais variantes perseguir | [D] LDM-21 | **LIVE** 02F; limite de 10 mil | nenhum | 5812 114/0 | RPCs incrementais de adicionar/remover adiadas |
| Fichário (Layout, Página, Slot, Bloqueio, Região) | Organização visual em páginas | [D] C-38 a C-46 | **LIVE** 5104–5141 | spike funcional (binder-nav-01) | 5818 196/196; 5819 22/22; 5820 27/27 | Desfazer/Refazer, mudança de grade e ordenação de páginas em aberto |
| Bandeja | Área temporária ao reorganizar | [D] C-45 (UX transitória) | — | spike | — | **Conflito:** a ux-exploration diz que a Bandeja sobrevive à troca de spreads e lista sua persistência como pendente; a C-45 a descarta ao sair, e o CP30 removeu a pendência |
| Storage (fichário físico, caixas) | "Onde a carta está guardada" | [D] C-55 a C-66 | **LIVE** 02A, sem hierarquia nem capacidade | spike (collection-space, superado) | 5802; 0,7 ms | Não existe container padrão provisionado automaticamente |
| Favorite de carta | Marcar cartas preferidas | [D] C-82 a C-90 | **inexistente** | spike (toggle local) | — | Distinta da espécie favorita da P6 [D] |
| Wishlist | Declarar desejo por uma variante | [D] C-91 a C-102 | **inexistente** | — | — | "Wishlist ≠ Faltantes da Collection" |
| Condition | Estado da carta | [D] C-103 a C-120 (escala M/NM/LP/MP/HP/DMG) | **apenas** o vocabulário de Pricing | — | — | Ligação física ao exemplar |
| Grading | Carta graduada | [D] C-121 a C-140 | inexistente | — | — | — |
| Colaboração (EDITOR/VIEWER) | Compartilhar | [D] C-141 a C-165 | inexistente; `visibility` só PRIVATE | — | — | — |
| Histórico de atividades | "O que mudou" | [D] C-166 a C-186 | inexistente; `bulk_operation` explicitamente não é Activity | — | — | — |
| Valorização / Pricing | Valor da coleção | princípios apenas (C-81, C-117) | inexistente | — | — | Fallback de preço `CARD_FALLBACK` não pode aparecer como preço da variante |
| Integração com a Pokédex (P7 a P9) | Coleção-Pokédex do usuário | [D] LDM-175 a 190 | **base LIVE** (Fatias B a E), 0 coleções reais | — | 5814 87/87 | P7 a P9 têm só títulos no ROADMAP |

---

## D. Inventário visual

| Spike | O que propõe | Real × simulado | Estado | Aprovação |
|---|---|---|---|---|
| collection-space | Prateleira de containers (fichários, ETB, caixas) que se abre com View Transition | mock | conceito superado | "prova técnica encerrada" (só no código) |
| binder-spike | Fichário premium de couro que abre em 2 páginas 3×3 | mock, cartas em SVG | protótipo superado | "aprovado" só em comentários do código |
| binder-motion-01 | Rolagem vertical comandando a navegação horizontal entre spreads | mock | **rejeitado** em 28/08 | — |
| binder-motion-02 | Virada de página 3D em CSS | mock | **rejeitado** em 28/08 | — |
| **binder-nav-01** | **Workspace completo do fichário** | Estado local com 18 imagens reais; arrastar e soltar **real** (dnd-kit), sem persistência | **implementação parcial** | Capa fechada aprovada como referência (após 23 rodadas); o restante "validado para informar o domínio", não homologado como produto |
| collection-gallery-spike-01 | Carrossel com profundidade × Premium Grid | mock | decidido | "Premium Grid vence" |
| collection-library-visual-01 | Grade refinada com fichário maior | mock | superado | sem registro no log |
| collection-wave-spike-01 | Wave × Filmstrip × Grid em iframe | HTML com dados embutidos | encerrado | Wave rebaixada a REFERENCE ONLY |
| filmstrip-binder-fidelity-01 | Retrato A/B/C no Filmstrip | HTML; a variante C usa imagens reais | encerrado | A vence; B e C AVOID |
| **collection-library-view-modes-01** | **Lista / Cards (padrão) / Carrossel** | Lista e Cards em React com mock; Carrossel em iframe | **referência visual homologada; implementação mock** | **[D] log de 29/08** e skill §6 |
| threeui-complete-shelf-proof | Estante 3D fotorrealista (WebGL) | componente real, three.js via CDN, cerca de 900 KB | prova | REFERENCE ONLY |
| mmkyu-shelf-adaptation-v1 | Estante → Foco → Abrir, com fichários MMKYU | mock, WebGL | conceito | REFERENCE ONLY, para showcase ou rede social |

**Melhores ideias de cada spike, sem eleger uma solução definitiva:**
- **binder-nav-01:**
  - navegação explícita entre spreads, com só o spread visível montado;
  - ações rápidas por slot com menu de overflow;
  - arrastar e soltar acessível com anúncios em português;
  - Bandeja;
  - seleção múltipla com barra de ferramentas;
  - seletor de cartas no padrão combobox;
  - proporção 8:11 medida em assets reais.
- **view-modes:** uma única coleção com três leituras distintas, "Cards" como entrada e a capa de fichário como identidade da coleção.
- **mmkyu-shelf:** a máquina de estados Estante → Foco → Abrir e a continuidade espacial do objeto. Foi aprovada como conceito; o visual foi reprovado.
- **collection-space:** o padrão de View Transition respeitando `prefers-reduced-motion`.
- **Rejeitados com motivo registrado:** virada de página literal, Hero Card, Wave e 3D na tela operacional.

**Limitações conhecidas:**
- `binder-pages-nav.tsx` concentra todo o estado num único componente de 1.848 linhas.
- `bulk-action-bar.tsx` e `bulk-action-rail.tsx` são provavelmente código morto [I].
- Arrastar e soltar pelo teclado não atravessa spreads.
- Desfazer/Refazer e a estratégia do Tool Rail no mobile seguem pendentes.
- As abas de modo não têm `tabpanel`.
- O iframe do Carrossel não herda o tema e não recebe dados.
- O shelf usa `sandbox` com `allow-same-origin` e `allow-scripts` juntos.
- 24 instâncias de `BinderCoverClosed` (646 linhas de CSS pesado) por tela [I].

---

## E. Mapa de prontidão

| Camada | Pronto para aproveitar | Precisa de produto/UX | Precisa de validação | Precisa de implementação |
|---|---|---|---|---|
| Domínio | C/LDM essenciais (posse, alocação, referência, completude, layout) | Nomenclatura da UI ("Coleções" já é usado em `/catalogo/card-sets`); fluxo de conversão de modo; regra da Bandeja | — | — |
| Backend de escrita | Toda a cadeia 01B–02F, Fatias B–E, Binder, BULK-01 a 03 | Comportamento do lote para o usuário (preview, erros parciais) | Caso 20b; comportamento com dados reais (só houve fixtures) | BULK-04, 05, 06; dívida de privilégios do `service_role` |
| Leituras de tela | Read models de completude (02E, 02F, Fatia E) | Quais dados cada tela precisa | — | **Biblioteca, conteúdo da coleção, fichário com dados de carta, busca de catálogo para o seletor** [I] |
| Experiência | Arquitetura de 3 modos [D]; capa do fichário [D]; padrões de interação do binder-nav | **Visão do produto (UX-01 "North Star" em aberto)**, fluxo de entrada, estado vazio, mobile | Homologação real com dados | Tudo em produção |
| Documentação | 05d (física), CD/LM (lógica) | — | — | Reconciliar LM, glossário, HANDOFF, README e ADR-013 |

---

## F. Matriz de riscos

| Categoria | Risco | Nível | Evidência |
|---|---|---|---|
| Segurança | `/experimental/*` sem login; precisa de decisão antes de expor dados reais | Alto | [F] sem guard e sem middleware; [I] alcance público em deploy |
| Segurança | Privilégios estruturais do `service_role` nas 5 tabelas antigas | Baixo | [F] dívida registrada |
| Segurança | Leituras novas sobre catálogo restrito a administradores precisarão de `SECURITY DEFINER` com verificação de dono | Médio (de projeto) | [I] mesmo padrão já usado na 5070 |
| Integridade | Concorrência de atribuição na Pokédex não provada (caso 20b) | Médio | [F] |
| Integridade | Duas RPCs de entrada coexistem (antigas com 500 e lote com 1.000) até a BULK-05 | Baixo | [F] |
| Performance | Biblioteca e fichário nunca testados com dados e imagens reais em volume; o spike de fichário tem 224 bolsos e não milhares de cartas | Médio | [I] |
| Performance | Capa CSS pesada por item na grade de coleções | Médio | [I] |
| Performance | Carrossel em iframe não escala para dados reais | Médio | [I] |
| Performance | Backend medido e saudável com 20 a 32 mil cartas por dono | Baixo | [F] |
| UX | Muitos caminhos explorados e poucos homologados; risco de recomeçar ou de adotar o spike mais recente por inércia | Alto | [F] |
| UX | Conflito sobre a Bandeja; nome "Coleções" em conflito; pendências de mobile | Médio | [F] |
| Manutenção | Documentação desatualizada (LM, glossário, HANDOFF, README, 04-domain-model, ADR-013) | Médio | [F] |
| Manutenção | Componente monolítico de 1.848 linhas e código possivelmente morto | Médio | [F]/[I] |
| Escalabilidade | `bulk_operation` sem política de retenção | Baixo | [F] |
| Produto | P7 a P9 só têm títulos; o escopo de "base funcional" não está mapeado para BULK-04 a 06 + UX + Frontend | Médio | [F] |

---

## G. Alternativas de retomada

**1. Produto primeiro: "Fatia vertical mínima".**
- Escopo: definir a North Star e os fluxos (UX-01). Implementar só as leituras necessárias para Biblioteca, Coleção e Adicionar cartas. Construir em produção Biblioteca (Cards) → Coleção (grade de cartas com progresso) → Adicionar cartas (seletor sobre RPCs existentes).
- BULK-04 a 06 entram quando o fluxo exigir.
- Vantagens: valor real para o usuário e homologação com dados reais mais cedo; aproveita o backend já validado.
- Riscos: adiar o BULK-04 pode deixar o "adicionar Set inteiro" para depois, contra o princípio de baixa fricção.
- Esforço: médio. Impacto na experiência: alto e cedo.

**2. Plano do ROADMAP como está.**
- Escopo: BULK-04 → 05 → 06 → Leituras/Contratos → Fluxos/Wireframes → Frontend.
- Vantagens: segue a sequência aprovada [D] e fecha todo o backend antes da UI.
- Riscos: mais semanas sem nenhuma experiência visível; o BULK-06 nem tem definição; os contratos podem ser desenhados sem uma visão de produto que os valide.
- Esforço: alto antes do primeiro valor. Impacto na experiência: tardio.

**3. Experiência primeiro: "North Star visual" sobre os spikes.**
- Escopo: nova rodada de UX que consolide a melhor ideia de cada spike num conceito único (Biblioteca → Coleção → Fichário), ainda com mock, e depois conecte ao backend.
- Vantagens: atende à avaliação de que o visual "precisa evoluir significativamente".
- Riscos: reabre a fase visual que foi formalmente pausada (exige nova autorização); risco de mais spikes sem produção.
- Esforço: médio. Impacto na experiência: alto, mas sem dados reais.

---

## H. Recomendação [R], que depende de autorização

Recomendo uma variação da alternativa 1, em etapas com gate:

1. **Saneamento documental** (sem código e sem banco):
   - reconciliar o status físico no LM e no glossário;
   - criar um HANDOFF novo e atualizar o README;
   - atualizar o banner do ADR-013;
   - registrar o conflito da Bandeja para decisão.
2. **Definição de produto: Collection North Star.** Um documento curto que decida:
   - visão e público (iniciante × avançado);
   - os 5 fluxos centrais: primeira coleção, adicionar cartas, ver progresso, organizar no fichário, adicionar um Set inteiro;
   - nomenclatura da UI;
   - o que significa "base funcional" para destravar P7 a P9;
   - quais ideias dos spikes são promovidas, e com que critério.
3. **Contratos de leitura para a tela.** Definir as leituras da Biblioteca, da Coleção e do seletor de cartas, além de decidir o escopo do BULK-04 (Set inteiro, com rejeição de variante inativa). Seguir o ritual de propostas e gates.
4. **Fatia vertical em produção:** Biblioteca (Cards) → Coleção → Adicionar cartas, em rota protegida, com dados reais. Só depois:
   - Fichário: reescrever o binder-nav-01 em componentes menores sobre as RPCs de Layout;
   - Lista e Carrossel nativos em React, substituindo o iframe;
   - BULK-05 e 06.
5. **Paralelo, baixo custo:** decidir se `/experimental` sai do deploy ou ganha proteção antes de qualquer dado real.

**Fatos × decisões × recomendações em uma linha:**
- **Fatos:** o backend está pronto e validado; não há UI real; os spikes usam mock e não exigem login.
- **Decisões aprovadas:** domínio C/LDM; três modos da Biblioteca; capa do fichário; sequência P6 → Collection → P7 a P9.
- **Recomendações novas** (sujeitas à sua autorização): a ordem acima, a North Star antes dos contratos de leitura, e tratar BULK-04 a 06 conforme a demanda dos fluxos.

**Registro em arquivo, se quiserem.** Proponho `docs/domain-modeling/collections/checkpoint-2026-10-15.md`, seguindo o padrão dos checkpoints 08-28, 08-29 e 08-30. A estrutura seria A a H deste relatório, mais uma seção de "conflitos documentais a reconciliar", com entradas em `docs/INDEX.md` e `docs/log.md`. Não criei nada. Aguardo a avaliação e a autorização de vocês antes de qualquer passo.
<!-- ORIGINAL-END -->

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | **Criação (2026-10-16, `DOC-GATE-01` — fechamento documental autorizado por Fabrício após auditoria independente).** Incorpora literalmente o diagnóstico integral de Collection de 2026-10-15 (SHA-256 `9e6ddea8…5e36`), com cabeçalho de origem, natureza histórico-factual, legenda e ressalva de que recomendações [R] não são decisões aprovadas. Nenhuma decisão canônica alterada. |
