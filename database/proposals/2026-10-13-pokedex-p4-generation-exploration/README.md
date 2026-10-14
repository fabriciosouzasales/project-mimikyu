# Pokédex P4 — Exploração por Geração (diagnóstico e planejamento)

| Campo | Valor |
|---|---|
| Data | 2026-10-13 |
| Frente | A — Produto e funcionalidades (`docs/adr/ADR-011-pokemon-tcg-domain-scope.md` v1.5) |
| Status | Alternativa A aprovada (P4a → P4b → P4c). **P4a implementada localmente em 2026-10-13, aguardando homologação.** P4b/P4c não iniciadas. Sem SQL, funções ou contratos novos. |
| Base | Código em `web/app/pokedex/`, `web/components/pokedex/`, `web/lib/pokedex/` no commit `54da0a2`; contratos 6131/6132/6133/6134/6135 já no LIVE |

## 1. O que já existe

| Área | Estado atual | Onde |
|---|---|---|
| Pokédex Nacional | `/pokedex` renderizada no servidor; 1.025 cards agrupados por geração, cada grupo com cabeçalho (romano, região, faixa Nº, contagem) | `pokedex-national-view.tsx`, `species-grid.tsx` |
| Régua de gerações | "Nacional" + 9 gerações; largura proporcional ao nº de espécies no desktop, pílulas roláveis no mobile (< 768 px); dourado no ativo, `aria-current` | `generation-filter.tsx` |
| Filtro por geração | Link `?geracao=N` (preserva `?q=`); recarrega a grade só com a geração; geração inválida volta para "todas" | `page.tsx`, `format.ts` |
| Pesquisa | Nome ou número, debounce 300 ms via `router.replace`, funciona sem JS; combinável com a geração | `pokedex-search.tsx` |
| Galeria → ficha | Card leva `?q`/`?geracao` para `/pokedex/[numero]`; "voltar" retorna com âncora `#especie-NNNN` e marca "Última ficha" | `format.ts`, `recent-species-marker.tsx` |
| Ficha | Anterior/próximo pela ordem nacional (±1), atalhos de teclado, busca rápida no indicador "Nº 0006 de 1.025" | `species-detail-view.tsx`, `species-keyboard-nav.tsx`, `species-quick-search.tsx` |
| Performance | SSR sem N+1; tipos em lote (6135); `content-visibility` por geração; prioridade de imagem só no topo; WebP 320 lazy | `species-grid.tsx`, `queries.ts` |
| Internacionalização | Rótulos de geração derivados do código estável; regiões como nomes próprios; rótulos de tipo por idioma | `format.ts`, 6135 |

Conclusão: a navegação por geração **já existe como filtro**. Uma nova "experiência separada" duplicaria a régua e a grade sem ganho; a evolução deve partir do que está aí.

## 2. Lacunas reais

| # | Lacuna | Evidência no código | Impacto |
|---|---|---|---|
| G1 | **Contexto quebra na fronteira da geração.** Com `?geracao=1`, a ficha #151 oferece "Próximo: #152" (geração II) mantendo `geracao=1`; o "voltar" de #152 vai para `/pokedex?geracao=1#especie-0152`, âncora que não existe na grade filtrada | `page.tsx` da ficha busca `n±1` sem considerar o contexto; `nationalPokedexHref` | Perde a posição e o marcador "Última ficha"; o usuário sai da geração sem perceber |
| G2 | **Geração filtrada não tem identidade própria.** O cabeçalho continua "Pokédex Nacional" com o total nacional; a geração só aparece como pílula ativa e na linha de resultado | `pokedex-national-view.tsx` | Explorar uma geração parece "aplicar um filtro", não "entrar em Kanto" |
| G3 | **Sem orientação na lista completa.** A régua não acompanha a rolagem (não é fixa) e não indica em que geração o usuário está entre os 1.025 cards | `generation-filter.module.css` (sem `sticky`) | Em desktop e mobile, voltar à régua exige rolar até o topo |
| G4 | **A ficha não leva à geração.** "Kanto, 1ª geração" é texto | `species-detail-view.tsx` | Caminho natural ficha → geração inexistente |
| G5 | **Nenhuma composição por geração.** Os tipos de todas as espécies já chegam à galeria (6135), mas não são resumidos por geração; lendário/mítico só existe na ficha | `page.tsx`, 6133/6135 | Falta o "retrato" da geração que interessa a iniciantes e avançados |
| G6 | **Mobile: fim de capítulo sem continuidade.** Ao terminar uma geração filtrada não há atalho para a próxima; as pílulas não sinalizam que rolam | `species-grid.tsx`, CSS das pílulas | Exploração sequencial (I → II → III) exige voltar ao topo |

Limites dos dados (não prometer na interface):

- Só formas padrão existem; formas regionais (Alola, Galar, Hisui, Paldea) não estão no banco.
- "Iniciais" e "lendários da capa" não estão armazenados como conceito; rotular espécies assim seria inferência.
- Não há progresso do usuário na galeria; Collections/Pokédex do usuário e Favoritos são frentes futuras.

## 3. Alternativas

**A — Capítulos de geração na própria Pokédex (evolução no lugar).**
- Com `?geracao=N`, o cabeçalho vira o capítulo da geração: numeral romano em contorno no lugar do total, nome da região, faixa Nº, contagem e uma faixa de composição por tipo calculada dos dados já carregados.
- Navegação de capítulo:
  - anterior/próximo da ficha respeita a geração do contexto (G1);
  - a ficha ganha link para a sua geração (G4);
  - o fim da grade oferece "Próxima geração" (G6).
- Na visão Nacional, a régua compacta fica fixa no topo durante a rolagem e destaca a geração visível (G3).
- Mesma rota, mesma grade, mesmos contratos.

**B — Rota dedicada por geração (`/pokedex/geracao/[n]`).**
- Página de capa por geração (arte de destaque, texto de apresentação, composição) e grade própria abaixo.
- A régua passa a apontar para as rotas.
- Duplica cabeçalho, grade e estados de carregamento, vazio e erro.
- Precisa de texto editorial de apresentação por geração, que hoje não existe.

**C — Hub de gerações antes da grade.**
- `/pokedex` abre com 9 capas de geração; a grade só aparece depois da escolha.
- Bom para descoberta inicial.
- Acrescenta um clique a todo uso recorrente e esconde a pesquisa nacional, que hoje é a ação principal.

| Critério | A — Capítulos no lugar | B — Rota por geração | C — Hub antes da grade |
|---|---|---|---|
| Valor para iniciante | Alto: "entrar em Kanto" com identidade e continuidade | Alto | Alto na primeira visita |
| Valor para avançado | Alto: pesquisa, URL e grade intactas, menos atrito | Médio: dois lugares para a mesma lista | Baixo: clique extra recorrente |
| Diferenciação da galeria atual | Média-alta: muda o que importa (identidade, orientação, continuidade) | Alta, mas parcialmente redundante | Alta, à custa do fluxo principal |
| Qualidade visual | Alta: reaproveita a linguagem P3b/P3c (numeral em contorno, lente, luz por tipo) | Alta | Alta |
| Facilidade de navegação | Melhor: corrige G1, G3, G4 e G6 diretamente | Boa, com risco de dois "voltar" | Pior para uso frequente |
| Desempenho | Sem leitura nova; composição calculada no servidor a partir de 6131/6135; uma ilha cliente leve para a régua fixa | Leituras repetidas por rota; mais páginas para cachear | Página extra antes do conteúdo |
| Manutenção | Baixa: um único conjunto de componentes | Alta: duas superfícies sincronizadas | Média |
| Internacionalização | Neutra: rótulos já derivados de códigos e idiomas | Exige texto editorial por geração em cada idioma | Exige textos de capa por idioma |

## 4. Recomendação

**Alternativa A**, em três incrementos, cada um homologável sozinho:

| Incremento | Conteúdo | Dados |
|---|---|---|
| **P4a — Continuidade** | G1: anterior/próximo dentro da geração do contexto, com fronteira explícita. G4: link ficha → geração. G6: "Próxima geração" no fim do capítulo | Nenhum novo; vizinhos já são lidos por número |
| **P4b — Capítulo** | G2/G5: cabeçalho de capítulo (romano, região, faixa, contagem) e composição por tipo da geração; estados vazio/erro preservados | Nenhum novo (6131 + 6135 já carregados) |
| **P4c — Orientação** | G3: régua compacta fixa no desktop com a geração visível destacada (IntersectionObserver só nos 9 cabeçalhos); indicação de rolagem nas pílulas do mobile; respeita `prefers-reduced-motion` | Nenhum novo |

Por que A:

- Resolve as lacunas medidas sem duplicar a régua nem a grade.
- Não depende da Frente B (funciona com textos en ou pt-BR).
- Não cria superfície de segurança nova: mesmas RPCs, `EXECUTE` só para `authenticated`.
- Mantém o estado na URL, compartilhável.

A rota dedicada (B) continua possível no futuro, se houver conteúdo editorial de apresentação por geração que a justifique.

Validação prevista para a implementação:

- typecheck e testes unitários da regra de vizinhos por contexto;
- Light/Dark, desktop/tablet/mobile e navegação por teclado;
- estados vazio/erro;
- checagem de que o número de leituras por página não aumenta.

`npm run lint` e `npm run build` ficam com o responsável pelo MMKYU.

## 5. Decisões necessárias antes de implementar

1. **Alternativa e ordem:** aprovar A com P4a → P4b → P4c, ou reordenar.
2. **Anterior/próximo com `?geracao=N`:** (a) ficar dentro da geração e parar na fronteira com "Próxima geração" (recomendado) ou (b) seguir a ordem nacional trocando o contexto para a nova geração.
3. **Régua na visão Nacional:** manter o clique como filtro (URL, comportamento atual) e acrescentar só o destaque da geração visível (recomendado), ou fazer o clique rolar até a seção.
4. **Arte do capítulo:** (a) sem arte, só tipografia e composição (recomendado para P4b); (b) arte da primeira espécie da geração por número, sem rótulo; (c) escolha curada por geração, que exige decisão editorial.
5. **Lendário/mítico na composição:** fora de P4 (recomendado), ou incluir mais tarde com uma leitura em lote nova (Query futura, com proposta e ensaio próprios).
6. **Régua fixa no mobile:** só no desktop (recomendado, preserva a área útil) ou também no mobile.

## 6. P4a — Continuidade de navegação (implementada localmente, 2026-10-13)

Decisões de produto aprovadas:

- **Sem geração selecionada (Pokédex Nacional):** anterior/próximo seguem a ordem nacional e atravessam gerações; o "voltar" preserva o contexto nacional. Comportamento anterior mantido.
- **Com geração selecionada:**
  - anterior/próximo ficam dentro da geração;
  - na primeira espécie não há anterior;
  - na última, no lugar do "próximo", uma transição explícita "Próxima geração → Geração II · Johto" abre a primeira espécie da geração seguinte com `?geracao=` atualizado;
  - a trilha do topo oferece "Pokédex Nacional / II Johto".

Causa dos problemas:

- a ficha lia os vizinhos `n±1` sem considerar o contexto e repassava `?geracao=` inalterado;
- ao cruzar a fronteira, o filtro antigo seguia junto, e o "voltar" apontava para uma âncora fora da grade filtrada;
- links antigos, editados à mão e a busca rápida para outra geração produziam o mesmo estado.

Implementação:

| Arquivo | Mudança |
|---|---|
| `web/lib/pokedex/navigation.ts` (novo) | Regras puras: `resolveSpeciesNavigation` (vizinhos por contexto e transição para a próxima geração) e `isGenerationContextMismatch` |
| `web/lib/pokedex/navigation.test.ts` (novo) | 9 cenários (nacional #151↔#152, geração I no #151, transição I→II, primeira espécie, voltar com âncora, pesquisa + geração, URL compartilhada, #0001/#1025, cadeia de "Última ficha") |
| `web/app/pokedex/[numero]/page.tsx` | `?geracao=` que não corresponde à espécie redireciona para a mesma ficha no contexto nacional (mantém `?q=`); vizinhos passam pela regra de contexto. Mesmas leituras de antes |
| `web/components/pokedex/detail/species-detail-view.tsx` | Trilha "Pokédex Nacional / geração" no contexto filtrado; transição para a próxima geração (círculo com o numeral romano, sem imagem nova); marcadores discretos "Início · Kanto"/"Fim · Paldea"; "Kanto, 1ª geração" vira link para a geração |
| `web/components/pokedex/detail/species-detail.module.css` | Estilos da trilha, transição, marcadores e link de geração (tokens existentes, claro/escuro, `prefers-reduced-motion`) |
| `web/components/pokedex/pokedex-national-view.tsx` | Fim do capítulo na galeria filtrada: "Próxima geração: Geração II · Johto →" (preserva a pesquisa, como a régua) e "Ver toda a Pokédex Nacional" |

Validação local:

- `npm run typecheck` = 0 erros;
- testes da Pokédex 33/33 PASS (navigation 9, description-presentation 9, detail 3, queries 5, species-search 7).

Pendente de homologação no navegador:

- os 9 cenários de ponta a ponta;
- Light/Dark e mobile (trilha e linha de vizinhos);
- foco e teclado (←/→ não atravessam a fronteira filtrada — a transição é um link visível);
- redirecionamento de URL divergente;
- `npm run lint` e `npm run build`.
