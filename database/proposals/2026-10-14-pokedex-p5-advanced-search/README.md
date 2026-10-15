# Pokédex P5 — Pesquisa Avançada (diagnóstico e planejamento)

| Campo | Valor |
|---|---|
| Data | 2026-10-14 |
| Frente | A — Produto e funcionalidades (`docs/adr/ADR-011-pokemon-tcg-domain-scope.md` v1.5; sequência em `docs/ROADMAP.md` 2.26) |
| Status | Alternativa A aprovada (2026-10-14). **P5a implementada localmente em 2026-10-14, aguardando homologação** (seção 8). P5b não iniciada — possibilidade futura (seção 8.6). Sem SQL, funções ou contratos novos. |
| Base | Commit `1478323` (P4 concluída); contratos 6131/6133/6135 no LIVE; medições LIVE somente leitura em 2026-10-14 |

## 1. Inventário do que existe

| Capacidade | Estado | Detalhe (onde) |
|---|---|---|
| Pesquisa por nome | **Implementada** | `?q=`; servidor (6131), sem acento/maiúsculas/pontuação, trecho em qualquer posição (`strpos`). Debounce 300 ms, `router.replace`, funciona sem JS (`pokedex-search.tsx`) |
| Pesquisa por número | **Implementada (exata)** | "25", "#25", "0025" → só a espécie 25. Sem prefixo/faixa. Na ficha, a busca rápida (P3b, cliente) faz prefixo e ranking — semânticas diferentes entre galeria e ficha |
| Filtro por geração | **Implementado** | `?geracao=N`, régua + barra compacta (P4c), capítulo (P4b), navegação por contexto (P4a) |
| Pesquisa × geração | **Implementada** | Combinam; estado vazio oferece "Limpar pesquisa" e "Pesquisar em todas as gerações" |
| Tipos primário/secundário | **Exibidos, não filtráveis** | 6135 entrega código + rótulo pt-BR das 1.025 espécies em lote; chips nos cards; composição por tipo no capítulo (P4b). Nenhum filtro |
| Lendário / Mítico / Bebê | **Dado existe, só na ficha** | `pokemon_species_profile`; exposto apenas por `get_pokedex_species_detail` (uma espécie por chamada). Sem leitura em lote → **ausente** para a galeria |
| URLs compartilháveis | **Implementadas** | Todo o estado em `?q`/`?geracao`; ficha preserva contexto; "voltar" com âncora `#especie-NNNN` + "Última ficha" |
| Desktop / mobile | **Implementados** | Régua proporcional ≥ 768 px, pílulas roláveis abaixo; barra compacta só ≥ 1024 px; grade responsiva (639/539 px) |
| Estados vazios | **Implementados** | Nenhum resultado (com saídas), erro de leitura (tentar novamente) |
| Ordenação | **Ausente** | Sempre número nacional, agrupado por geração (decisão de produto coerente) |

**Custo atual de uma pesquisa:** cada `?q` debounced refaz no servidor as três leituras da página (6131 gerações, 6131 espécies filtradas, 6135 índice de 1.025 tipos). É aceitável hoje, mas qualquer filtro novo deve **reaproveitar** esse ciclo, não somar consultas.

## 2. Dados disponíveis (LIVE, 2026-10-14, somente leitura)

| Dado | Cobertura | Contrato em lote para a galeria? | Serve como filtro? |
|---|---|---|---|
| Nome oficial, nº nacional, geração | 1.025/1.025 | Sim (6131) | Já usado |
| Tipos (18 ativos, rótulos pt-BR) | 1.025/1.025; 499 monotipo, 136 combinações duplas | **Sim (6135)** | **Sim — sem consulta nova** |
| Lendário / Mítico / Bebê | 1.025 perfis importados, 0 nulos; 71 / 23 / 19 | **Não** (só ficha) | Sim, mas exige contrato de leitura em lote |
| Classificação (genus) | pt-BR 60, en 1.025 | Não | **Não** — texto editorial (Frente B), cobertura pt-BR de 6% |
| Altura / peso | 1.025 (forma padrão) | Não | Não — pouco valor de descoberta |
| Formas alternativas | 0 não padrão | — | Não existe |
| Cor, habitat, forma corporal, evolução, grupos de ovo | — | — | **Não existem no modelo** — fora de escopo |

## 3. Lacunas e oportunidades reais

1. **Tipo é o critério ausente de maior valor.** É o principal eixo mental do colecionador ("todos os Fogo", "Dragão/Voador"), já está na tela e já está carregado. Filtrar não exige dado novo.
2. **Lendários/Míticos/Bebês** são um recorte de alto apelo para colecionador (113 espécies), mas exigem uma leitura em lote nova — decisão separada.
3. **Combinação de critérios** (nome + geração + tipo) com contagem de resultado e remoção individual de cada filtro.
4. Não são lacunas reais: ordenação alternativa, altura/peso, genus como filtro, prefixo numérico na galeria ("1" listaria 1, 10–19, 100–199, 1000–1025 — ruído).

## 4. Alternativas de experiência

**A — Filtros progressivos na galeria.** Abaixo da régua, uma linha de filtro por tipo: um botão "Tipo" abre a grade de 18 tipos (ícones do sprite existente); escolhidos viram chips removíveis ao lado da linha de resultado. Estado em `?tipo=FIRE,FLYING`. Filtragem no servidor sobre os dados já lidos.

**B — Painel de pesquisa avançada sob demanda.** Botão "Filtros" ao lado da pesquisa abre um painel (lateral no desktop, folha inferior no mobile) com todos os critérios — geração, tipos, classificação — e "Aplicar". Mais espaço para crescer; mais um passo para o uso mais comum.

**C — Pesquisa e descoberta combinadas.** O campo de pesquisa entende critérios ("fogo", "lendário", "gen 3") e sugere atalhos; mais "coleções prontas" (Lendários, Iniciais, Bebês). Mais encantadora, porém ambígua (nome × tipo: "Psíquico" não é espécie, mas "Mr. Mime" contém "mime"), difícil de tornar acessível e cara de manter.

| Critério | A | B | C |
|---|---|---|---|
| Facilidade de uso | Alta — um toque a partir da galeria | Média — abre, escolhe, aplica | Alta para experientes, ambígua para iniciantes |
| Clareza visual | Alta; chips no ponto do resultado | Alta no painel; filtros ativos ficam escondidos se não houver resumo | Média; critérios implícitos |
| Acessibilidade | Simples: botões com `aria-pressed`, links | Exige gestão de foco/diálogo | Difícil (combobox com múltiplas semânticas) |
| Desempenho | Zero consulta nova (tipos) | Igual a A | Parser no cliente + possíveis leituras extras |
| Escalabilidade | Boa até 2–3 critérios; depois satura | Melhor para muitos critérios | Boa, mas cresce a ambiguidade |
| Manutenção | Baixa | Média | Alta |
| Coerência P3/P4 | Alta — mesmo padrão de links/URL da régua | Média | Baixa |

## 5. Recomendação

**Alternativa A**, com o seletor de tipo aberto sob demanda (progressive disclosure) e preparada para receber um segundo critério sem virar painel. Razões: resolve a lacuna de maior valor (tipo) sem consulta nova; mantém a galeria como protagonista; segue o padrão já homologado (estado na URL, links do servidor, funciona sem JS); custo de acessibilidade e manutenção baixo. B só se justifica quando houver ≥ 4 critérios; C fica como evolução de descoberta, não como base.

Semântica proposta para tipos: **até dois tipos, combinação "E"** — "Fogo" = espécies com Fogo (primário ou secundário, mesma regra da composição do capítulo P4b); "Fogo + Voador" = espécies que têm os dois. Não usar "OU" (a lista cresceria em vez de afunilar). Contagem de resultado e estado vazio contextual ("Nenhum Pokémon Gelo + Fogo em Geração III").

## 6. Escopo mínimo proposto

**P5a — Filtro por tipo (sem SQL).**

- `?tipo=` com 1–2 códigos estáveis (`FIRE`, `FLYING`); parser estrito no padrão de `parseGenerationParam` (códigos desconhecidos/duplicados descartados, nunca erro).
- Filtragem no `page.tsx` sobre `species` × índice 6135 já carregados; lógica pura em `lib/pokedex/` com testes.
- Seletor de 18 tipos com ícones e cores da paleta existente; chips ativos removíveis; preserva `?q`/`?geracao`; régua, barra compacta, capítulo e fim de capítulo propagam `?tipo`.
- Contexto levado à ficha e de volta (`PokedexContext` ganha `types`); anterior/próximo da ficha **não** passam a respeitar tipo nesta fatia (ver decisão D3).
- Sem índice de tipos (6135 indisponível): seletor oculto, `?tipo` ignorado com aviso discreto.
- Desktop e mobile; teclado; leitores de tela; claro/escuro; `prefers-reduced-motion`.

**P5b — Lendário / Mítico / Bebê (condicionado a aprovação de contrato).** Uma leitura em lote nova, somente leitura, mesmo padrão de 6131/6135 (`SECURITY DEFINER`, `search_path=''`, `auth.uid()` obrigatório, sem `anon`), devolvendo só as ~113 espécies marcadas. Exige ciclo SQL próprio (proposta → execução por Fabrício → promoção).

Fora do escopo: ordenação, altura/peso, genus, prefixo/faixa numérica, painel avançado, linguagem natural, favoritos (P6), Collection e P7–P9.

## 7. Riscos e decisões antes da implementação

| # | Decisão / risco | Recomendação |
|---|---|---|
| D1 | Aprovar Alternativa A e a semântica "até 2 tipos, E" | Aprovar |
| D2 | Formato da URL: códigos (`?tipo=FIRE`) ou rótulos pt-BR (`?tipo=fogo`) | Códigos estáveis — independem de idioma, como `GENERATION_*` |
| D3 | Anterior/próximo na ficha respeitarem o filtro de tipo | Não na P5a (exigiria vizinhança calculada, hoje vinda de ±1 nacional); "voltar" preserva o filtro |
| D4 | Régua e barra compacta: contagens por geração continuam totais ou passam a refletir o filtro | Manter totais na P5a (sem cálculo novo); avaliar contagem filtrada depois |
| D5 | P5b (Lendário/Mítico/Bebê) entra na P5 ou fica para depois | Aprovar como fatia separada, após P5a homologada |
| R1 | 6135 indisponível desliga o filtro | Degradação explícita, sem quebrar a galeria |
| R2 | Pesquisa por número exata na galeria × prefixo na ficha | Manter; documentar a diferença (galeria filtra, ficha sugere) |
| R3 | Custo por pesquisa (3 leituras a cada `?q`) | Não piora com P5a; otimização de cache fica como item próprio se medida justificar |
| R4 | Interação com P4c: barra compacta e âncoras com tipo filtrado | Barra continua só na visão nacional; seções vazias não renderizam (comportamento atual) |

## 8. P5a — Filtro por tipo (implementação local, 2026-10-14)

Escopo aprovado: Alternativa A com decisões D1–D4 da seção 7. A ordem dos tipos na URL segue a escolha do usuário (ver 8.2). Sem SQL, sem consulta nova e sem dependência nova. A única API nova usada é `useLinkStatus`, que já vem no Next 15.5 instalado.

### 8.1 Solução

| Peça | O que faz | Onde |
|---|---|---|
| Regras puras | `parseTypeParam`, `canonicalTypes`, `toggleType`, `speciesMatchesTypes`, `applyTypeFilter`, `typeLabels`, `joinTypeLabels` | `web/lib/pokedex/type-filter.ts` |
| Filtragem | Na própria página (servidor), numa passagem sobre a lista de 6131 (já reduzida por pesquisa/geração) e o índice 6135 já carregado. A mesma passagem gera as contagens do seletor | `pokedex-national-view.tsx` |
| URL | `?tipo=FIRE,FLYING`. Parâmetro fora da forma canônica redireciona antes de qualquer leitura: minúsculas, repetido, código desconhecido ou mais de dois | `app/pokedex/page.tsx` |
| Links | Fonte única `pokedexContextSearch`/`pokedexHref` (`q`, `geracao`, `tipo`) usada por régua, barra compacta (P4c), pesquisa (inclusive o formulário sem JS), fim de capítulo, estado vazio, cards e ficha | `lib/pokedex/format.ts` |
| Seletor | Botão "Tipo" recolhido, com dourado e contador quando ativo. Chips removíveis e "Limpar" ficam ao lado. O painel abre no fluxo da página com os 18 tipos na ordem oficial; cada tipo mostra quantas espécies o resultado teria. Combinações vazias e, no limite de dois, os demais tipos ficam indisponíveis | `type-filter.tsx`, `type-filter-disclosure.tsx` (ilha cliente: abrir/fechar, Esc, indicador de carregamento), `type-filter.module.css` |
| Chip | `PokemonTypeChip` ganhou `children` opcional (contagem/✓/×), sem mudar o uso existente | `pokemon-type-chip.tsx` |
| Ficha | `?tipo` entra no contexto. Vizinhos, busca rápida e "voltar" o preservam; anterior/próximo seguem a regra nacional/de geração. O "voltar" só leva âncora quando a espécie tem os tipos do filtro; senão volta ao topo da galeria filtrada | `app/pokedex/[numero]/page.tsx`, `species-detail-view.tsx` |
| P4a | A transição para a próxima geração mantém pesquisa **e** tipos (`{ ...context, generation }`) | `lib/pokedex/navigation.ts` |

### 8.2 Decisões tomadas na implementação

- **Ordem na URL:** é a ordem em que o usuário escolheu os tipos (`FIRE,FLYING` e `FLYING,FIRE` são ambas canônicas e dão o mesmo resultado). Assim o exemplo aprovado não é reescrito e os chips aparecem na ordem da escolha. Só a grafia é normalizada.
- **Contagem no seletor:** cada opção mostra o tamanho do resultado se ela for acrescentada. Opção que esvaziaria o resultado fica indisponível — o seletor nunca leva a grade vazia. Grade vazia ainda é possível por link direto, e aí o estado vazio oferece "Remover filtro de tipo".
- **Contagens totais mantidas:** régua, barra compacta e capítulo (P4b) continuam com os totais da geração (D4). A linha de resultado e os cabeçalhos de seção mostram o resultado filtrado, como já acontecia com a pesquisa.
- **Índice de tipos indisponível:** o seletor não aparece. Um `?tipo=` presente não é aplicado e um aviso explica que as espécies aparecem sem esse filtro, com "Tentar novamente" e "Remover filtro de tipo". Nenhum resultado parcial.
- **Sem JavaScript:** chips, "Limpar", régua e pesquisa funcionam; abrir o seletor exige JS.

### 8.3 Testes executados (local)

- `node --experimental-strip-types --test lib/pokedex/*.test.ts`: **64/64 PASS** (52 anteriores + 12 novos em `type-filter.test.ts`). Os novos cobrem:
  - 1 tipo; 2 tipos com semântica E; ordem;
  - limite de dois; combinação com pesquisa e geração;
  - contagens do seletor;
  - URL e ficha (inclusive o "voltar" sem âncora);
  - transição P4a com tipos;
  - parâmetros inválidos; ausência do índice; resultado vazio; rótulos.
- `npm run typecheck`: **PASS**.
- `npm run lint` e `npm run build`: **pendentes** (executados por Fabrício; o sandbox do agente não roda SWC).
- Responsividade, teclado, leitor de tela e temas claro/escuro: **pendentes de validação visual/manual** (8.5).

### 8.4 Desempenho

- Nenhuma consulta nova: a página continua fazendo as mesmas três leituras (6131 gerações, 6131 espécies, 6135 tipos), em paralelo.
- Filtro, contagens e rótulos: uma passagem linear sobre ≤ 1.025 espécies, mais uma varredura curta do índice para os rótulos. Custo desprezível no servidor.
- Cada clique em tipo é uma navegação suave com o mesmo custo de um clique na régua. Com filtro, a grade renderiza menos cards e o HTML fica menor.
- Cliente: uma ilha pequena (estado aberto/fechado e indicador de carregamento). Ícones e cores de tipo reutilizam a paleta existente; sem dependência nova.

### 8.5 Cenários para homologação

1. `/pokedex` → "Tipo" → Fogo: resultado e chip "Fogo"; o painel continua aberto e as opções mostram as contagens com Fogo.
2. Fogo + Voador: só espécies com os dois (ex.: Charizard, Moltres); demais opções indisponíveis; "Limpar tipos".
3. `?tipo=FLYING,FIRE` e `?tipo=FIRE,FLYING`: mesmo resultado; `?tipo=fire` redireciona para `?tipo=FIRE`.
4. `?tipo=FIRE,WATER,GRASS` → `?tipo=FIRE,WATER`; `?tipo=XYZ` → `/pokedex`.
5. Pesquisa "char" + Fogo; Geração I + Voador; trocar a geração pela régua e pela barra compacta mantém os tipos.
6. Abrir um card filtrado, navegar com anterior/próximo (inclusive para espécie fora do filtro) e voltar: galeria filtrada; âncora/"Última ficha" só quando a espécie está no resultado.
7. Fim de capítulo (P4a) e capítulo (P4b) com tipo ativo: transição mantém tipos; indicadores do capítulo inalterados.
8. Estado vazio por link direto (ex.: `?geracao=1&tipo=DARK`): mensagem e "Remover filtro de tipo".
9. Teclado: Tab até "Tipo", Enter abre, Tab pelas opções, Esc fecha e devolve o foco; foco visível em botão, opções, chips e "Limpar".
10. Leitor de tela: botão anuncia expandido/recolhido e o filtro ativo; opções com contagem; indisponíveis anunciadas como tal; linha de resultado anunciada.
11. Mobile estreito: botão + chips quebram linha; seletor em duas colunas; régua e grade sem regressão.
12. Temas claro e escuro: contraste dos chips, estado selecionado, indisponível, dourado do ativo.
13. Barra compacta (P4c) com tipo ativo: aparece só na visão nacional; geração visível correta.

### 8.6 P5b — possibilidade futura

Lendário / Mítico / Bebê **não foi iniciado**. Fica como possibilidade futura, condicionada à avaliação, por Fabrício, do valor dos filtros especiais depois do uso da P5a. Se aprovada, exige um ciclo SQL próprio (leitura em lote nova, seção 6).
