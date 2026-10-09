# Semântica de exibição de Card Variant — `VARIANT-DISPLAY-SEMANTICS-01`

| Campo | Valor |
|--------|-------|
| **Documento** | Arquitetura de frontend — semântica e contrato de exibição de Card Variant |
| **Arquivo** | `docs/architecture/variant-display-semantics.md` |
| **Versão** | 1.0 |
| **Status** | **EM ANDAMENTO** — F1, REACT-KEY e F2.1 concluídas; F2.2 não iniciada |
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
| `web/lib/catalogo/carta-variants.ts` | `mapCartaVariants` (legado, inalterado até a F2.2/F2.3 migrarem os consumidores). Desde a F2.1, também contém o adaptador PostgREST → F1 e as projeções. |
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

- Exibi-lo como "variantes cadastradas" depende do gate **G-COMP** (§6).
- Na F2.1, `rawCount` não é exibido em lugar nenhum.

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
| **F2.2** | Galeria, Nível 2: popover/tooltip acessível, uma linha por variante na ordem da F1, Finish em peso normal e Printing/EC como qualificadores, `aria-label` com D1, erro D2 | **NÃO INICIADA**; exige mandato. Exibir `rawCount` como total depende do G-COMP |
| **F2.3** | Relatório "Variantes por carta": estrutura por eixos e total pela contagem bruta | **NÃO INICIADA** |
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
| P11 | **G-COMP**: completude de `rawCount` | **PENDENTE** (bloqueia só a exibição de `rawCount` como total na F2.2) | G-COMP-1: Σ `rawCount` = `count(card_variant)` do Set · G-COMP-2: cartas devolvidas = `count(card)` do Set · G-COMP-3: casos F0 = 2/6/6/6. Exige leitura read-only autorizada à parte |
| P12 | Sem exceção não tratada; isolamento entre cartas | PASS | S13, S22–S28 |

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
| R7 | `max-rows` do PostgREST sobre raiz/embeds não verificado | Coberto pelo G-COMP antes de exibir totais |
| A1-L1 | A F1 não distingue `finish.code` ausente de `null`; o impacto fica só na classificação de legado, que é interna (D3) | Teste S21 fixa o comportamento. "Modo estrito" na F1 = melhoria futura |
| A1-L2 | A F1 não tem código para exceção inesperada | Sinalizada à parte como `fault`, sem fabricar código F1 |
| — | Payload: +~4,2 KB gzip por página de Set grande | Dentro do limite. Nova medição se a projeção ganhar campos |

---

## Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | **Criação (2026-10-09, `VARIANT-DISPLAY-SEMANTICS-01-F2.1-DOCUMENTATION-CLOSEOUT-01`).** Consolida as decisões M1–M3 (F1) e D1–D3 (F2.0), o contrato de três camadas da F2.1, o estado das fases (F1 `2b83b98` e REACT-KEY `94b64ba` publicadas; F2.1 concluída localmente, a publicar no commit desta rodada) e os gates P1–P12. Destaques: P9 **PASS** (A +5,14 % / +4.305 B; B +7,24 % / +4.170 B; ME2.5, 295/630) e P8 PASS por build de produção isolado. P10 não foi executado isoladamente; G-COMP está pendente. |
