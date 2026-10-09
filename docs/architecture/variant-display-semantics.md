# Semântica de exibição de Card Variant — `VARIANT-DISPLAY-SEMANTICS-01`

| Campo | Valor |
|--------|-------|
| **Documento** | Arquitetura de frontend — semântica e contrato de exibição de Card Variant |
| **Arquivo** | `docs/architecture/variant-display-semantics.md` |
| **Versão** | 1.3 |
| **Status** | **EM ANDAMENTO** — F1, REACT-KEY, F2.1, F2.2 e F2.3 concluídas; G-COMP PASS. Restam a F2.4 (opcional) e a experiência editorial das `NEEDS_REVIEW` |
| **Criado em** | 2026-10-09, em `VARIANT-DISPLAY-SEMANTICS-01-F2.1-DOCUMENTATION-CLOSEOUT-01` |
| **Objetivo** | Registrar de forma canônica as decisões, o contrato de dados e o estado das fases da frente que leva a identidade completa de Card Variant (Finish + Printing + Edition Context) até a interface. |
| **Dependências** | [`ADR-028`](../adr/ADR-028-card-variant-governance.md), [`05b-cartas-e-raridade.md`](../05b-cartas-e-raridade.md), [`STD-004`](../standards/STD-004-frontend-standards.md), `database/proposals/2026-09-18-edition-context-axis/FRONTEND-DISPLAY-CONTRACT.md` (diagnóstico de origem) |

---

## 1. Problema

A galeria `/catalogo/cartas` e os relatórios mostravam cada variante só pelo nome do acabamento (`card_variant_type.name`).

- Variantes distintas da mesma carta, diferentes apenas em Printing ou Edition Context, apareciam como rótulos idênticos (por exemplo, `Holográfica ×4`).
- Depois da `2213` (Batch 13), isso ficou mais frequente: variantes legadas decompostas passaram a compartilhar o acabamento com variantes irmãs.
- A identidade da linha (`card_variant.id`) era descartada no mapper. Por isso a chave React era o nome (`key={variantName}`), duplicada.

Diagnóstico completo: `FRONTEND-DISPLAY-CONTRACT.md`, linkado nas dependências.

## 2. Decisões permanentes

| ID | Decisão | Origem |
|---|---|---|
| **M1** | Modelo estruturado sem perda: identidade, apresentação e metadados administrativos ficam separados. Eixo opcional ausente = `null`. | F1 |
| **M2** | Legado só por **evidência positiva**: código desconhecido nunca vira legado; sem evidência, o estado é `INDETERMINATE`. | F1 |
| **M3** | Rótulos iguais não implicam variantes iguais: a colisão é detectada; nunca há deduplicação nem UUID acrescentado ao rótulo. | F1 |
| **D1** | Separador textual entre eixos: **`" / "`** (`CARD_VARIANT_LABEL_SEPARATOR`). A fronteira real entre eixos continua estrutural (partes da F1). Colisões do texto renderizado com esse separador também são detectadas. | F2.0 |
| **D2** | Estado de erro por carta: a interface mostra a **contagem bruta** com o aviso **"Detalhes indisponíveis"**. Não há fallback silencioso para os nomes antigos. | F2.0 |
| **D3** | A classificação de legado **nunca atravessa para o cliente**: ela fica no servidor. A exibição administrativa futura (Nível 3) depende de mandato próprio. | F2.0 |

**Invariantes da F1** (testadas em `card-variant-display.test.ts`):

| | Invariante | | Invariante |
|---|---|---|---|
| I1 | identidade = `card_variant.id` | I5 | ordem: Finish → Printing → EC → id |
| I2 | nenhum id de eixo se perde | I6 | colisão detectada, nunca removida |
| I3 | N entradas → N saídas | I7 | separador sempre por parâmetro; sem parse reverso |
| I4 | `NULL` legítimo não gera texto | I8 | fail-closed: dado inválido → erro, sem fallback |

A unicidade que sustenta o modelo é `uq_card_variant_identity` (Query `2209`): `(card_id, variant_type_id, printing_profile_id, edition_context_profile_id)` com `NULLS NOT DISTINCT`. `name` não é único em nenhuma das três entidades de eixo; por isso vale M3.

## 3. Componentes

| Módulo | Papel |
|---|---|
| `web/lib/catalogo/card-variant-display.ts` (F1) | Biblioteca pura, sem React, Supabase ou rede. Valida, ordena, monta partes do rótulo, detecta colisões e classifica legado. Ponto de entrada: `buildCardVariantDisplays()`. |
| `web/lib/catalogo/carta-variants.ts` | `mapCartaVariants` (legado). Desde a F2.3 não tem consumidor de UI: os campos `variants`/`variantNames` continuam em `CartaCompletaRow` por compatibilidade. Desde a F2.1, também contém o adaptador PostgREST → F1 e as projeções. |
| `web/lib/catalogo/carta-variant-summary.ts` (F2.2/F2.3) | Modelo puro do indicador, mais `hasCartaVariants` (filtros; ERROR conta como "com") e `cartaVariantCount` (`rawCount`; `null` = desconhecida). Decide o que o pill e o popover mostram a partir do `variantView`: linhas com acabamento primário e qualificadores, rótulo D1, sinal de rótulo repetido e estado D2. Não reimplementa regra da F1. |
| `web/components/catalogo/carta-variants-summary.tsx` (F2.2) | Indicador da galeria, Nível 2. É um botão focável (pill ícone + quantidade) com popover ancorado (`useAnchoredPopover`, mesmo padrão do pill de preço). Abre por hover, foco ou toque e fecha com Esc (o foco volta ao gatilho) ou clique fora. |
| `web/lib/catalogo/queries.ts` → `getCartasCompletas` | Consulta única por Card Set. Desde a F2.1, lê os três eixos e `card_set(code)` e preenche `CartaCompletaRow.variantView`. |

## 4. Contrato de dados (F2.1)

Três camadas. Só a terceira atravessa para o cliente.

1. **Linha bruta do PostgREST**: só no servidor.
2. **`CartaVariantDisplayState`**: resultado integral da F1, inclusive `admin.legacy`. Existe só no servidor e transitoriamente; não entra em `CartaCompletaRow`.
3. **`CartaVariantViewState`**: projeção serializada em `CartaCompletaRow.variantView`. Estados possíveis:
   - `NONE { rawCount: 0 }`
   - `OK { rawCount, variants: [{ id, parts, collidesWith, renderedCollidesWith }] }`, na ordem da F1
   - `ERROR { rawCount: number | null, errors: [{ code, index, variantId }], fault }`

   Sem legado (D3), sem mensagens internas e sem ids de eixo.

Regras do adaptador:

- Só renomeia chaves **presentes**. Chave ausente continua ausente, e `null` continua `null`.
- Não fabrica valores. Estruturas inválidas seguem intactas para a F1 acusar.
- FK preenchida com embed nulo (por exemplo, RLS ocultando o eixo) resulta em `ERROR`, nunca em "sem eixo".
- Cada carta é isolada em `try/catch`: uma exceção vira `ERROR` com `fault: "UNEXPECTED_EXCEPTION"` só daquela carta.
- Nenhuma regra de validação, ordenação, colisão ou legado é reimplementada fora da F1.

**`rawCount`** é o número de linhas `card_variant` **recebidas na consulta**, antes de qualquer transformação. Não é a contagem persistida no banco.

- **G-COMP PASS (2026-10-09):** `rawCount` é igual à contagem persistida e pode ser exibido como "variantes cadastradas" (§6). Na F2.1 ele ainda não é exibido.

**Segurança.** Sem RLS, GRANT, policy ou migration nova:

- as tabelas lidas (`card_printing_profile`, `card_edition_context_profile`, `card_set`) já estão sob `catalog_admin_select`;
- as rotas já exigem admin.

## 5. Fases

| Fase | Escopo | Estado |
|---|---|---|
| **F1** | Biblioteca semântica pura + 14 testes | **CONCLUÍDA**, commit `2b83b98` |
| **REACT-KEY** | `card_variant.id` como chave React na galeria; o mapper preserva o id | **CONCLUÍDA**, commit `94b64ba` |
| **F2.0** | Decisões D1, D2 e D3 (Fabrício) | **CLOSED** |
| **F2.1** | Integração de dados: adaptador, estados, projeção `variantView` e consulta ampliada. Nenhum consumidor visual (sem mudança de UI). | **CONCLUÍDA** (2026-10-09). Gates na §6 |
| **F2.2** | Galeria, Nível 2: popover acessível, uma linha por variante na ordem da F1, Finish em peso normal e Printing/EC como qualificadores, `aria-label` com D1, erro D2, contagem = `rawCount` | **CONCLUÍDA** (2026-10-09), §6.1. Commit desta rodada |
| **F2.3** | Relatório "Card Variants por Carta": uma variante por linha com a identidade completa, D2, quantidade e total por `rawCount` (total marcado com "+" quando há contagem desconhecida); filtros Com/Sem variantes do relatório e da galeria via `variantView` | **CONCLUÍDA** (2026-10-09), §6.2. Commit desta rodada |
| **F2.4** | (Opcional) Nível 3 no detalhe/zoom da carta | **NÃO INICIADA** |

Fora desta frente:
- os 5 consumidores mapeados em `FRONTEND-DISPLAY-CONTRACT.md` §1 (inclusive Pricing), cada um com mandato próprio;
- a experiência editorial das 1.642 `NEEDS_REVIEW`.

## 6. Gates da F2.1

| # | Critério | Estado | Evidência |
|---|---|---|---|
| P1 | Diff restrito a 3 arquivos (`carta-variants.ts`, `queries.ts`, `carta-variant-display-state.test.ts`) | PASS | `git status` |
| P2 | `tsc --noEmit` sem alterar artefatos gerados | PASS | exit 0; `tsconfig.tsbuildinfo` inalterado |
| P3 | Testes: estado F2.1 30/30 + F1 14/14 + REACT-KEY 6/6 = **50/50** | PASS | `node --experimental-strip-types --test` |
| P4 | Legado (`mapCartaVariants`) idêntico ao baseline | PASS | diff só de acréscimos; S16 e S29 |
| P5 | Sem duplicar regras da F1 | PASS | S20 (paridade) |
| P6 | Sem mudança visual | PASS | `variantView` sem consumidor |
| P7 | Sem SQL, migration, policy ou GRANT | PASS | escopo de arquivos |
| P8 | `next build` aceita o import `./card-variant-display.ts` | **PASS** | `next build` de produção da árvore F2.1 em cópia isolada (protocolo P9, Fase 4), seguido de `next start` servindo a galeria |
| P9 | Gate de payload real | **PASS** | §7 |
| P10 | `next lint` isolado | **NÃO EXECUTADO** | `next lint` não roda no sandbox do agente (sem binário SWC); fica para a máquina de Fabrício |
| P11 | **G-COMP**: completude de `rawCount` | **PASS** (2026-10-09) | G-COMP-1 (Σ `rawCount`) e G-COMP-2 (cartas devolvidas) iguais ao banco em ME2.5 (295/630), BASE5 (83/167) e SVE (24/112). G-COMP-3: casos F0 = 2/2/6/6/6 nos dois lados. Banco: `G-COMP-DB-01` (1 SELECT, autorizado). Aplicação: galeria lida no navegador. Evidência: [`gcomp-2026-10-09/`](../history/development/variant-display-semantics-01/gcomp-2026-10-09/README.md) |
| P12 | Sem exceção não tratada; isolamento entre cartas | PASS | S13, S22–S28 |

### 6.1 Gates da F2.2

| Critério | Estado | Evidência |
|---|---|---|
| Testes | **PASS** — 74/74 | 9 novos em `carta-variant-summary.test.ts` (M0–M8: separador D1, NONE oculto, ordem e partes, qualificadores, rótulo repetido, colisão renderizada, ERROR sem nomes legados, contagem) + K6 ajustado ao novo local da lista |
| `tsc --noEmit` | **PASS** | exit 0 |
| Dark | **PASS** (inspeção) | BASE5 Dark Alakazam #18: "Padrão" / "Padrão / 1ª Edição" |
| Light, viewport estreito (~315 px) | **PASS** (inspeção) | SVE Energias: 6 linhas com EC como qualificador; o popover reposiciona abaixo do gatilho |
| Teclado | **PASS** | o foco abre; Esc fecha e devolve o foco ao gatilho; Tab segue para o pill de preço e fecha o popover |
| Sem dependência nova | **PASS** | reutiliza `useAnchoredPopover` |
| Sem mudança de dado/banco | **PASS** | só UI |
| `next lint` / `next build` | **NÃO EXECUTADOS** no sandbox | rodar na máquina de Fabrício |

O estado ERROR (D2) é coberto por teste (M6 e M7). Não foi observado nos dados reais, porque o G-COMP deu 0 ERROR.

### 6.2 Gates da F2.3

| Critério | Estado | Evidência |
|---|---|---|
| Testes | **PASS** — 76/76 | M9 (presença) e M10 (contagem, inclusive ERROR e contagem desconhecida) |
| `tsc --noEmit` | **PASS** | exit 0 |
| Relatório BASE1 | **PASS** (inspeção, print de Fabrício) | Holográfica / Tiragem Ilimitada · / Sem Sombra · / Sem Sombra · 1ª Edição · / Copyright 1999–2000; quantidade 4. O "·" do nome da tiragem não se confunde com o separador D1 |
| Relatório BASE5 | **PASS** | 83 linhas; total 167 = G-COMP; 0 sem variante; Dark Alakazam #01 e #18 com 2 linhas cada |
| Filtro "Sem variantes" | **PASS** | SVE (relatório): estado vazio; BASE5 (galeria): 0 cartas |
| Filtro "Com variantes" (galeria) | **PASS** | BASE5: 83 de 83 |
| Nenhum consumidor de UI de `variantNames` | **PASS** | grep em `app/` e `components/` (fora de `experimental/`) |
| `next lint` / `next build` | **NÃO EXECUTADOS** no sandbox | rodar na máquina de Fabrício |

## 7. Gate de payload (P9) — resultado

**Método.** A medição rodou dentro do navegador embutido do app Claude, autenticado pelo próprio Fabrício.

- Sem cookie copiado e sem DevTools: a sessão nunca saiu do navegador.
- Requisições `fetch` same-origin; tamanho gzip via Resource Timing (`encodedBodySize`).
- Builds de produção isolados em cópias fora do repositório: baseline `94b64ba` na porta 3101 e F2.1 na 3102.
- Set **ME2.5** (seleção S1): 295 cartas, 630 variantes.
- 1 aquecimento + 5 amostras por ambiente e cenário, com a ordem dos ambientes alternada.
- Decisão pelo `p9-decide` (limites: aumento comprimido ≤ 10 % **e** ≤ 50.000 B, por cenário).

| Cenário | Baseline (mediana gzip) | F2.1 (mediana gzip) | Δ | Veredito |
|---|---|---|---|---|
| A — HTML inicial | 83.744 B | 88.049 B | +4.305 B (+5,14 %) | **PASS** |
| B — RSC navegação | 57.561 B | 61.731 B | +4.170 B (+7,24 %) | **PASS** |

Descomprimido:
- **A:** 710.892 → 830.842 B
- **B:** 402.779 → 508.439 B

A dispersão do gzip ficou ≤ 0,02 %.

**Verificações funcionais**, todas confirmadas:
- 295 cartas e 630 variantes nas 24 amostras.
- `cardIdsSha256` e `legacyPairsSha256` idênticos nos dois ambientes.
- `variantView`: ausente no baseline; na F2.1, OK 295 / NONE 0 / ERROR 0, com `sumRawCount` 630.
- HTTP 200, sem redirect, `no-store`.
- Os headers RSC foram capturados do roteador real e são idênticos nas duas portas.

**Integridade.** O repositório continuou íntegro: HEAD, working tree, hashes, `.next` e `node_modules` foram verificados pelo script de encerramento.

Evidência sanitizada (só números, enums e hashes; sem cookie, token ou corpo de resposta): [`history/development/variant-display-semantics-01/p9-2026-10-09/`](../history/development/variant-display-semantics-01/p9-2026-10-09/README.md).

## 8. Riscos e dívidas registrados

| ID | Item | Tratamento |
|---|---|---|
| R7 | `max-rows` do PostgREST sobre a raiz | **Mitigado (G-COMP):** o maior Set tem 300 cartas (SWSHP) e nenhum passa de 1.000; o máximo é 9 variantes por carta. Gatilho de revisão: um Set acima de ~1.000 cartas exige paginação ou `range()` em `getCartasCompletas` |
| A1-L1 | A F1 não distingue `finish.code` ausente de `null`; o impacto fica só na classificação de legado, que é interna (D3) | Teste S21 fixa o comportamento. "Modo estrito" na F1 = melhoria futura |
| A1-L2 | A F1 não tem código para exceção inesperada | Sinalizada à parte como `fault`, sem fabricar código F1 |
| — | Payload: +~4,2 KB gzip por página de Set grande | Dentro do limite. Nova medição se a projeção ganhar campos |

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | **Criação (2026-10-09, `VARIANT-DISPLAY-SEMANTICS-01-F2.1-DOCUMENTATION-CLOSEOUT-01`).** Consolida as decisões M1–M3 (F1) e D1–D3 (F2.0), o contrato de três camadas da F2.1, o estado das fases (F1 `2b83b98` e REACT-KEY `94b64ba` publicadas; F2.1 concluída localmente, a publicar no commit desta rodada) e os gates P1–P12. Destaques: P9 **PASS** (A +5,14 % / +4.305 B; B +7,24 % / +4.170 B; ME2.5, 295/630) e P8 PASS por build de produção isolado. P10 não foi executado isoladamente; G-COMP está pendente. |
| 1.1 | **G-COMP PASS (2026-10-09, `VARIANT-DISPLAY-SEMANTICS-01-G-COMP-01`).** P11 passou de pendente a PASS: banco e aplicação coincidem em cartas e Σ `rawCount` para ME2.5, BASE5 e SVE, e os casos F0 dão 2/2/6/6/6. R7 foi reclassificado como mitigado, com gatilho de revisão em ~1.000 cartas por Set. Agora `rawCount` pode ser exibido como total na F2.2/F2.3. |
| 1.2 | **F2.2 concluída (2026-10-09, `VARIANT-DISPLAY-SEMANTICS-01-F2.2-GALLERY-N2-01`).** A galeria passou a usar `variantView`. O tooltip legado foi trocado por `CartaVariantsSummary`, um popover acessível com a identidade completa de cada variante; o modelo puro fica em `carta-variant-summary.ts`. Gates na §6.1: testes 74/74 (9 novos + K6 ajustado), `tsc` exit 0 e validação visual em dark, light, viewport estreito e teclado. Os filtros Com/Sem variantes e o relatório continuam no legado até a F2.3. |
| 1.3 | **F2.3 concluída (2026-10-09, `VARIANT-DISPLAY-SEMANTICS-01-F2.3-REPORT-01`).** O relatório e os filtros Com/Sem variantes migraram para `variantView`; nenhuma UI usa mais `variantNames`. Funções novas: `hasCartaVariants` e `cartaVariantCount`. Testes 76/76, `tsc` exit 0, validação na tela em BASE1, BASE5 e SVE (§6.2). |
