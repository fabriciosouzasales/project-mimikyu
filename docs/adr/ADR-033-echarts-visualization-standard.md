## ADR-033 — Apache ECharts como Padrão de Visualização Analítica/Interativa

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-033 |
| **Título** | Apache ECharts como Padrão de Visualização Analítica/Interativa |
| **Status** | Aprovado |
| **Data** | 2026-08-23 |
| **Decisores** | Fabrício Sales |
| **Decisão** | Apache ECharts passa a ser o padrão do MMKYU Collector para visualizações **analíticas/interativas** (crosshair, tooltip rico, múltiplas séries, legenda interativa, zoom/pan) — não para todo gráfico simples. Uso via `echarts/core` com imports seletivos de módulos, nunca o pacote `echarts` completo. `SVGRenderer` como renderer padrão (tela e impressão). Nenhuma dependência de wrapper React não oficial (`echarts-for-react` descartado) — um componente interno único e fino, `MMKYUChart`, encapsula lifecycle/resize/tema/renderer. |
| **Documentos Relacionados** | `../standards/STD-004-frontend-standards.md`, `ADR-029-pricing-domain-model.md` |

---

## Context

O relatório "Preço por Carta" (Pricing Admin, `/pricing/relatorios/preco-por-carta`) tinha seu gráfico de Histórico de Preço implementado como SVG desenhado à mão (`components/pricing/price-history-chart.tsx`), sem nenhuma biblioteca de charts — decisão original motivada pela ausência de qualquer dependência de visualização no projeto e pela suficiência do caso de uso na época.

Ao longo de sucessivas rodadas de refinamento visual (2026-08-23), o gráfico manual acumulou features adicionadas uma a uma diretamente no SVG (densidade de escala, rótulos de último ponto, legenda enriquecida) sem nunca alcançar o nível de acabamento e interatividade esperado para um relatório "premium" (crosshair, tooltip rico por eixo, zoom/pan, legenda clicável para show/hide de série). Fabrício interrompeu essa evolução manual explicitamente ("PARE a evolução visual do gráfico manual... Não quero continuar adicionando features manualmente ao SVG antes de avaliarmos uma biblioteca de gráficos") e pediu uma avaliação formal de biblioteca de charts como padrão de produto, antecipando necessidade crescente de gráficos em Valor de Mercado, Catálogo, Collections e Analytics.

Quatro bibliotecas foram avaliadas contra 18 critérios (integração Next 15/React 19, qualidade visual, tooltip, crosshair, múltiplas séries, legenda interativa, show/hide de série, zoom/range/brush, responsividade, dark mode, impressão, acessibilidade, customização visual, performance com séries de preço, tamanho/dependências, manutenção, maturidade/ecossistema, facilidade de componentes reutilizáveis, adequação a Analytics futuro): Recharts, Apache ECharts, visx (Airbnb) e, como quarta alternativa justificada, TradingView Lightweight Charts (especializada em séries financeiras, avaliada por ser exatamente o caso de uso do gráfico em questão, mesmo sabendo de antemão que não serve como padrão geral).

Avaliação completa (tabela comparativa e recomendação) apresentada e aprovada por Fabrício em chat, nesta mesma data — não reproduzida por extenso aqui; ver seção "Alternatives Considered" para o resumo do porquê de cada alternativa não ter sido escolhida.

`package.json` (`web/`), antes desta decisão, não continha nenhuma dependência de charting. Stack confirmado: Next.js 15.5.18, React 19.1.1.

---

## Decision

### Apache ECharts é o padrão para visualização analítica/interativa — não para todo gráfico

Apache ECharts é adotado como a biblioteca padrão do MMKYU Collector especificamente para visualizações que exigem interatividade real: séries temporais com crosshair/tooltip por eixo, múltiplas séries com legenda que liga/desliga série, zoom/pan, e — no futuro — tipos mais ricos (heatmap, funil, treemap, sankey, mapas) que o produto vai precisar em Catálogo/Collections/Analytics.

Isso **não** é uma regra de que todo gráfico simples do produto precisa passar a usar ECharts. Barras de participação, indicadores percentuais isolados, sparklines decorativas e qualquer visualização estática de baixa complexidade continuam podendo ser resolvidas com CSS/SVG simples ou pequenos componentes próprios, caso a caso — o padrão existe para o caso analítico/interativo, não para substituir toda superfície visual do produto.

### Uso modular via `echarts/core`, nunca o pacote completo

Import sempre a partir de `echarts/core`, com registro explícito só dos módulos necessários por gráfico (`LineChart`, `GridComponent`, `TooltipComponent`, `LegendComponent`, `DataZoomComponent`, `SVGRenderer`, etc. — nunca `import * as echarts from 'echarts'` nem `import 'echarts'` do pacote agregado, que traz o motor inteiro (canvas, todos os tipos de série, todos os componentes) independentemente do que a tela realmente usa. Cada tela declara seus próprios imports seletivos; não existe um "kit" pré-registrado global que force todo consumidor a pagar pelo custo de todos os módulos já usados em qualquer lugar do produto.

### `SVGRenderer` como renderer padrão — tela e impressão

Renderer fixo em `SVGRenderer`, nunca o `CanvasRenderer` (default do ECharts caso nenhum renderer seja registrado). Motivo direto: `SVGRenderer` não borra ao ampliar/imprimir (SVG é vetorial), enquanto `CanvasRenderer` pode perder nitidez em impressão de alta resolução — e toda folha impressa do Pricing Admin (`RelatorioFolha`/`RelatorioCabecalho`/`RelatorioRodape`) é um requisito transversal já estabelecido, não uma exceção. Um único renderer para os dois contextos (tela e papel) evita manter dois caminhos de renderização — mesmo princípio que já levou `PriceHistoryChart` (implementação anterior) a usar uma única prop `printSafe` em vez de dois componentes.

Volume de dados típico do produto (séries de preço com dezenas a poucas centenas de pontos por variante/fonte) não se aproxima da escala onde `CanvasRenderer` seria necessário por performance — a escolha de `SVGRenderer` não tem custo de performance relevante no caso de uso atual nem no roadmap próximo (Catálogo/Collections/Analytics administrativo, não terminal de alta frequência).

### Wrapper interno compartilhado (`MMKYUChart`) — nunca `echarts-for-react`

Decisão explícita de **não** adotar `echarts-for-react` (ou qualquer outro wrapper React de terceiros) como dependência estrutural, apesar de ser uma opção madura e amplamente usada (839K downloads/semana). Motivo: controle direto sobre lifecycle (init/dispose), estratégia de resize (`ResizeObserver` em vez do listener de `window.resize` que a maioria dos wrappers usa por padrão), aplicação de tema (light/dark do próprio design system, não um tema genérico do pacote), garantia de `SVGRenderer` sempre ativo, e liberdade de evolução (zoom/brush, marcadores, temas adicionais) sem depender do roadmap ou das convenções de API de um pacote de terceiros não mantido pela Apache Foundation.

Em vez disso: um componente interno único, fino, `MMKYUChart` (`web/components/charts/mmkyu-chart.tsx` — local a definir na Fase 2 da implementação), que encapsula:

- Inicialização da instância ECharts (`echarts.init(element, theme, { renderer: 'svg' })`) e `dispose()` correto no unmount — nenhuma instância órfã sobrevive à navegação entre páginas.
- Resize via `ResizeObserver` no container (não `window.resize` — o container pode mudar de tamanho sem a janela mudar, ex.: sidebar colapsando).
- Aplicação de `option` via `setOption()`, com merge não-destrutivo quando aplicável.
- Troca de tema light/dark, sincronizada com o `next-themes` já usado no restante do app.
- Client Component (`"use client"`) — inevitável, ECharts precisa executar no navegador; o restante da árvore (Server Components) permanece intocado, o boundary Client fica restrito a este componente.
- Acessibilidade mínima (região com `role`/`aria-label` descrevendo o gráfico, mesmo padrão já usado pelo `<svg role="img" aria-label="...">` da implementação anterior).

O wrapper **não** deve virar uma abstração grande ou um DSL próprio por cima do ECharts — ele existe para resolver lifecycle/resize/tema/renderer de forma centralizada, não para reimplementar ou esconder a API de `option` do ECharts. Cada tela consumidora continua escrevendo seu próprio objeto `option` (tipado), passando-o como prop ao `MMKYUChart` — a expressividade nativa do ECharts permanece disponível a quem precisar dela, só o boilerplate de integração com React é centralizado uma vez.

### Alternativas exigem justificativa específica

Qualquer visualização analítica/interativa fora deste padrão (outra biblioteca de charts, ou uma nova extensão manual em SVG/canvas) exige justificativa explícita registrada (emenda a este ADR ou ADR próprio), não decisão implícita por conveniência pontual de uma tela. Visualizações simples/estáticas (barras de participação, badges numéricos, sparklines triviais) continuam fora do escopo deste padrão, como já esclarecido acima — não precisam de justificativa para não usar ECharts.

---

## Consequences

### Benefícios

- Cobertura nativa de praticamente todo o checklist "premium" que motivou esta decisão (crosshair, tooltip por eixo, `dataZoom`, legenda com `selectedMode` nativo) sem precisar reimplementar cada feature manualmente, como vinha ocorrendo no SVG desenhado à mão.
- `SVGRenderer` único resolve nitidez de impressão sem manter dois caminhos de renderização.
- Ecossistema do ECharts (projeto da Apache Foundation, alto volume de produção real) cobre com folga os tipos de visualização que Analytics/Catálogo/Collections vão eventualmente precisar (heatmap, funil, treemap, sankey, mapas), evitando uma segunda migração de biblioteca no médio prazo.
- Controle total sobre lifecycle/resize/tema por não depender de wrapper de terceiros — risco de manutenção do produto não fica amarrado à cadência de um pacote comunitário não oficial.

### Custos / Riscos assumidos

- Bundle maior que Recharts se os imports não forem mantidos disciplinadamente seletivos — mitigado pela regra explícita de `echarts/core` + módulos nomeados, nunca o pacote agregado; a Fase 6 da implementação mede e reporta o tamanho real introduzido.
- API de `option` é mais imperativa que a composição declarativa de componentes React — mitigado por concentrar essa fricção inteiramente dentro do `MMKYUChart`; o restante da aplicação nunca importa `echarts` diretamente.
- Manutenção do wrapper interno é responsabilidade do próprio projeto (não terceirizada a um pacote comunitário) — custo aceito conscientemente em troca do controle descrito acima.

---

## Alternatives Considered

### Recharts

Maior comunidade React pura (50M+ downloads/semana), integração declarativa idiomática, SSR-safe sem fricção. Descartado como padrão analítico/interativo porque tooltip rico e crosshair exigem construção manual (mesmo problema que motivou esta decisão), zoom/brush (`Brush`) tem limitações conhecidas de sincronização, e a cobertura de tipos de visualização (sem heatmap/funil/sankey/treemap nativos) é insuficiente para o roadmap de Analytics. Continua sendo uma opção legítima para gráficos simples fora do escopo deste ADR, se algum dia fizer sentido — não proibida, só não é o padrão analítico.

### visx (Airbnb)

Controle máximo (primitivas d3 + React), bundle modular pequeno (~30–40KB gzip típico). Descartado por ser puramente um kit de primitivas, não uma biblioteca de gráficos pronta — adotá-lo moveria o problema atual (construção manual feature a feita) de SVG cru para primitivas d3, sem resolver a instrução explícita de não continuar investindo em construção manual. Cadência de manutenção também historicamente mais lenta (atrasos em upgrades de React registrados no próprio repositório do projeto).

### TradingView Lightweight Charts

Avaliada com seriedade por ser exatamente o caso de uso do gráfico de Histórico de Preço (crosshair e tooltip desenhados especificamente para séries de preço, motor mais performático dos quatro, menor bundle). Descartada como **padrão do produto** por dois motivos: (1) escopo estritamente financeiro — não cobre nenhum dos tipos de visualização mais amplos que Catálogo/Collections/Analytics vão precisar; (2) renderiza exclusivamente em `<canvas>`, sem modo SVG, risco real de perda de nitidez na impressão — requisito transversal já estabelecido em todos os relatórios do Pricing Admin. Não descartada permanentemente: se um caso de uso futuro for exclusivamente financeiro/trading e a impressão não for requisito, pode ser reavaliada com ADR próprio.

### `echarts-for-react` como dependência estrutural

Avaliada como a integração padrão de mercado para ECharts + React (839K downloads/semana, madura). Descartada por decisão explícita de Fabrício: controle sobre lifecycle/resize/tema/renderer/evolução sem depender de convenções de um wrapper não oficial e não mantido pela Apache Foundation. Ver seção "Decision" acima.

---

## Related Documents

- `../standards/STD-004-frontend-standards.md`
- `ADR-029-pricing-domain-model.md`

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação — formaliza Apache ECharts como padrão de visualização analítica/interativa do MMKYU Collector (não regra geral para todo gráfico), uso modular via `echarts/core` com imports seletivos, `SVGRenderer` como renderer padrão (tela e impressão), e um wrapper interno fino (`MMKYUChart`) em vez de `echarts-for-react` ou qualquer wrapper React de terceiros, para manter controle sobre lifecycle/resize/tema/evolução. Motivado pela interrupção explícita da evolução manual do gráfico SVG de Histórico de Preço (Preço por Carta) e pela avaliação comparativa de quatro bibliotecas (Recharts, Apache ECharts, visx, TradingView Lightweight Charts) apresentada e aprovada por Fabrício em chat na mesma data. Nenhuma dependência instalada nem código implementado por este ADR — só a decisão de governança; a fundação técnica (`MMKYUChart`) e a substituição do gráfico de Preço por Carta são incrementos de implementação subsequentes. |
