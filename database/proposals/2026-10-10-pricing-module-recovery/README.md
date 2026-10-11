# PRICING-MODULE-RECOVERY-01 — diagnóstico e plano (2026-10-10)

| Campo | Valor |
|---|---|
| **Status** | Diagnóstico concluído · **Fase 2 (3978) e Fase 1 (3979) EXECUTADAS 2026-10-10** · **Fase 3: ferramenta de descoberta em lote entregue (3980 + Edge + UI); confirmações pendentes de execução por Fabrício** · Fases 4–5 pendentes |
| **Gatilho** | Tela "Visão Geral" do Valor de Mercado em ATENÇÃO após a expansão do catálogo |
| **Fonte** | JustTCG, plano Starter: 10.000 req/mês · 1.000 req/dia · 50 req/min · até 100 cartas/req |

## Diagnóstico (LIVE, 2026-10-10 14:48 UTC)

### O que está saudável

- Refresh diário funcionando: 46 Sets com sucesso nas últimas 24 h, ~125 requisições/dia (~3.800/mês),
  0,5% de execuções com erro. A barra baixa de 10/10 é só o dia em andamento (os Sets vencem entre 18h e 22h UTC).
- Vínculo produto → variante implantado (Pricing 80): 49.899 de 50.470 produtos ligados.
- FX (PTAX) rodando nos dias úteis.

### O que está defasado

| # | Achado | Números | Causa |
|---|---|---|---|
| A1 | **Cobertura de Sets** | 49 de 201 Sets mapeados; **152 sem mapeamento** (13.061 cartas, 62% do catálogo) | O catálogo cresceu (BW, XY, SM, SWSH antigos, EX, DP, HGSS, Neo, e-Card, POP, Trainer Kits, ME5.5/ME5.5CC, CEL25CC, promos); o mapeamento de Set é manual e nunca foi feito para eles |
| A2 | **3 Sets travados "aguardando primeira sincronização"** (é o alerta "fila atrasada há mais de 1 hora") | SM12 (271 cartas) e SWSH10.5 (88): bootstrap COMPLETE com **0 cartas** · MFB: 34/34 NOT_FOUND | SM12/SWSH10.5 foram mapeados em 10/09, quando ainda não tinham cartas no catálogo; o bootstrap é one-shot e nunca reprocessa. MFB não casa nenhuma carta na fonte |
| A3 | **Bootstrap não acompanha cartas novas** | Hoje 359 cartas em Sets mapeados sem `pricing_card_mapping` (todas de SM12/SWSH10.5) | Não há gatilho para reabrir o bootstrap quando um Set mapeado ganha cartas. Vai se repetir a cada importação/recuperação de catálogo |
| A4 | **Orçamento de API não comporta cobertura total no ritmo diário** | 49 Sets/8.105 cartas = ~125 req/dia. Os 152 Sets adicionais (muitos pequenos: POP, TK, promos) somam ~+200 req/dia → ~330 req/dia ≈ **9.900/mês**, no limite do plano sem margem para bootstrap/retry | `pricing_refresh_policy` só tem frequência por fonte (1/2/3/5 dias), não por Set |
| A5 | **"Evolução das confirmações" vazia** (0 de 7.747) | Nenhum mapping novo confirmado em 10 dias | Consequência de A1: nada novo entrou na fila |
| A6 | **52 cartas NOT_FOUND** | MFB 34, SVP 15, SVE 2, BASE1 1 | Revisão manual (fila "Não encontrados") |
| A7 | **Preço por variante não é consumido** | `pricing_product.card_variant_id` preenchido, mas `get_cards_pricing_summary` e telas ainda agregam por carta | Contrato do Pricing 80 é novo; consumidores não foram adaptados |
| A8 | **Resíduo operacional** | 30 jobs `justtcg-price-refresh-wave-*` inativos no cron; 571 produtos sem variante (Pricing 80) | Legado do modelo por ondas, substituído pelo dispatcher por Set |

## Plano proposto

Ordem pensada para destravar a tela primeiro, depois a cobertura, sem estourar o plano da API.

### Fase 1 — Destravar o que já existe (sem custo de API relevante)

1. **Reabrir o bootstrap de SM12 e SWSH10.5** (mesma RPC/estado do pipeline; ~4 req) → +359 cartas no refresh.
2. **MFB:** revisar o mapeamento de Set (provável Set errado ou fonte sem as cartas); se a fonte não tiver,
   marcar o Set como NOT_FOUND e tirá-lo da fila — o alerta "atrasada" some.
3. **Regra permanente para A3:** quando um Set mapeado ganha cartas novas (import/recuperação), reabrir o
   bootstrap só para as cartas sem mapping (gatilho no fechamento da importação de catálogo ou varredura
   diária barata no dispatcher). Idempotente, sem tocar mapeamentos confirmados.
4. **Limpeza:** remover os 30 jobs de cron de ondas inativos.

### Fase 2 — Orçamento antes de ampliar (decisão de Fabrício)

5. **Frequência por Set** em vez de por fonte: ex. Sets modernos (SV/ME/SWSH recentes) diário; Sets antigos,
   POP, Trainer Kits e promos a cada 3–7 dias. Modelo: coluna/override de frequência no estado de refresh do
   Set + dispatcher respeitando o orçamento diário (teto configurável, ex. 800/dia, deixando folga para bootstrap).
6. **Projeção na tela:** consumo previsto do mês × limite do plano, para a decisão ser visível.

### Fase 3 — Ampliar a cobertura (152 Sets)

7. Rodar o `pricing-set-matching-preview` para os 152 Sets e confirmar em lote os casamentos de alta confiança
   (data de lançamento + nome); os ambíguos vão para a fila "Sets aguardando configuração".
   Prioridade sugerida: ME5.5 → SV/SWSH/SM faltantes → XY/BW → EX/DP/HGSS/Neo/e-Card → POP/TK/promos.
8. Bootstrap em lotes respeitando 1.000 req/dia (≈ 130 req para 13 mil cartas, mais o matching).
   Conjuntos que a JustTCG não tiver (alguns TK, CEL25CC, ME5.5CC) ficam NOT_FOUND documentados.

### Fase 4 — Preço por variante chegando ao produto

9. Adaptar `get_cards_pricing_summary`/relatórios para usar `card_variant_id` (preço da variante quando
   existir, fallback para a carta) — base para a avaliação de Collection.
10. Fila residual do Pricing 80 (571) e NOT_FOUND (52): revisão editorial pela UI de resolução.

### Fase 5 — Saúde contínua

11. Alertas da Visão Geral recalibrados: distinguir "Set sem cartas no catálogo" e "Set NOT_FOUND" de
    "fila atrasada"; incluir "Sets mapeados com cartas sem mapping" e "consumo projetado do mês".

## Decisões pedidas a Fabrício

- Fase 2: política de frequência por Set (quais grupos diário / 3 dias / 7 dias) e teto diário de requisições.
- Fase 3: ordem de prioridade dos 152 Sets e se Trainer Kits/POP/promos entram agora.

## Execução

### Fase 2 — Frequência por Expansão (3978, CONFIRMADO EXECUTADO 2026-10-10)

Decisão de Fabrício: **Mega Evolution, Scarlet & Violet, Sword & Shield e Sun & Moon diárias; demais a cada 3 dias.**

- `pricing_refresh_expansion_policy` (override por fonte × Expansão, RLS admin) com ME/SV/SWSH/SM = 1 dia.
- Padrão da fonte JUSTTCG: 1 → 3 dias (registrado em `pricing_admin_action_log`).
- `close_pricing_set_refresh_attempt`: próxima execução = override da Expansão > padrão da fonte > 1.
  Vale a partir do próximo sucesso de cada Set (sem reagendamento forçado).
- Hoje: 41 Sets mapeados diários (ME 8, SV 19, SWSH 13, SM 1) e 8 a cada 3 dias (Base 6, Gym 2).
- `get_pricing_admin_overview` devolve `expansion_overrides`; o Hero da Visão Geral mostra
  "Ativa · diária (ME, SM, SV, SWSH) · demais a cada 3 dias". Typecheck `web` OK.
- O formulário de política em /pricing/sincronizacoes continua editando só o padrão da fonte; overrides por
  Expansão são alterados por migration (sem UI nesta rodada).

### Fase 1 — Destravar (3979, CONFIRMADO EXECUTADO 2026-10-10)

- `internal.reopen_stale_pricing_set_bootstraps()`: reabre o bootstrap COMPLETE de Set CONFIRMED que tenha
  carta ativa sem `pricing_card_mapping` **criada depois** da última conclusão (sem loop; matching idempotente).
  Agendada no pg_cron diariamente às 05:15 UTC (`pricing-reopen-stale-set-bootstraps`), só SQL — sem custo de API.
- Execução imediata (gate exato `SM12:271, SWSH10.5:88`). O dispatcher existente processou em ~20 min:

| Set | Cartas confirmadas | Pendentes | Produtos | Ligados à variante (trigger 3974) | 1º refresh |
|---|---:|---:|---:|---:|---|
| SM12 | 271 | 0 | 1.988 | 1.988 | SUCCESS 15:25 UTC |
| SWSH10.5 | 85 | 3 | 630 | 630 | SUCCESS 15:20 UTC |

  Custo: ~5 requisições de bootstrap + o refresh normal.
- **MFB:** a JustTCG não devolveu nenhuma das 34 cartas → refresh pausado (`MANUAL_PAUSE`, log
  `PRICING_SET_REFRESH_PAUSED`); reversível pela UI. Revisão do mapeamento do Set fica na Fase 3.
- **Limpeza:** 30 jobs `justtcg-price-refresh-wave-*` (inativos) removidos do pg_cron.
- Novas ações no `pricing_admin_action_log`: `PRICING_SET_BOOTSTRAP_REOPENED`, `PRICING_SET_REFRESH_PAUSED`.
- Resultado na Visão Geral: Sets com refresh atrasado > 1 h = **0** (era 3); pausados = 1 (MFB).

### Fase 3 — Descoberta de correspondências em lote (3980, CONFIRMADO EXECUTADO 2026-10-10)

Em vez de 152 diálogos "Sincronizar" (2 requisições cada, ~300 no total), uma revisão única:

- **3980** `public.pricing_set_discovery_targets(p_pricing_source_id)`: Sets POKEMON sem mapping CONFIRMED,
  com Expansão, data, cartas ativas e status atual. STABLE, SECURITY INVOKER, `EXECUTE` só para `service_role`.
- **Edge `pricing-set-matching-preview` v2** (deploy 2026-10-10, `verify_jwt` + `is_admin` inalterados): novo corpo
  `{ "mode": "batch" }` → **1 única GET /sets** classifica todos os Sets com a mesma regra do modo single
  (`resolveSetMatchV2`, data de lançamento exata). Proteções novas do lote:
  `CONFLICT` (2+ Sets locais no mesmo candidato, ex.: Set principal e Galeria de Treinador) e
  `TAKEN` (candidato já CONFIRMED para outro Set — o índice `uq_pricing_set_mapping_source_external_confirmed`
  recusaria). `NOT_FOUND` traz sugestões por data próxima (±45 dias), nunca confirmadas automaticamente.
  Modo single intacto. Suíte offline: 13 cenários antigos + 10 novos (B1–B10) passando
  (executada com Node `--experimental-transform-types`; Deno não disponível no sandbox). O bundle publicado é
  equivalente ao código do repositório, com os módulos só-de-tipo inlinados.
- **Server Actions** (`web/app/pricing/mapeamentos-sets/descoberta/actions.ts`): `descobrirCorrespondenciasEmLote`
  (somente leitura) e `confirmarCorrespondenciasEmLote` — refaz a consulta no servidor (+1 requisição) e só grava,
  via `admin_confirm_pricing_set_mapping` com a sessão do admin, o que continua válido: Set ainda sem CONFIRMED,
  Set externo existente e livre, sem o mesmo externo duas vezes no lote. Nome/método/evidência vêm do servidor;
  `match_method` = `RELEASE_DATE_EXACT_MATCH` (seguro) ou `ADMIN_MANUAL_SELECTION` (escolha do admin);
  `match_evidence.flow = BATCH_DISCOVERY`. Resultado por item (falha parcial não interrompe), teto de 200 por lote.
- **UI** `/pricing/mapeamentos-sets/descoberta` (botão "Descobrir correspondências" em Mapeamentos de Sets):
  três grupos — Prontos para confirmar (pré-selecionados), Revisar (escolha entre opções), Sem correspondência
  (sugestões por data + lista completa sob demanda) —, busca, barra de confirmação fixa com contagem de cartas e
  confirmação em dois passos. Typecheck `web` OK; validação visual (light/dark/mobile) pendente com Fabrício.
- Custo: 1 requisição por consulta + 1 por confirmação. Cada Set confirmado entra no bootstrap existente
  (1 Set a cada 5 min, ~1–3 requisições por Set).
- **Execução (Fabrício, UI, 2026-10-10 ~15:50 BRT):** 87 Sets confirmados (66 por data exata, 21 por escolha manual — SWSH9–12 e Galerias,
  Crown Zenith/GG, ME5.5/ME5.5CC, CEL25CC, SM1, SM8, BW1, BW11/RC, G1, DP1/DPP). Conferência LIVE: nomes externos coerentes com
  os Sets locais; única diferença de data relevante é DP1 → "Diamond and Pearl" (22 dias, correto). Mapeamentos CONFIRMED: 49 → 136.
  Bootstrap das cartas em fila (1 Set a cada 5 min, ~7 h).
- **Restante:** 65 Sets (15 para revisar, 50 sem correspondência por data), na maioria POP, Trainer Kits, McDonald's,
  promos (NP/HGSSP/BWP/XYP/SMP) e alguns principais (EX1/EX4–EX6/EX8/EX10/EX16, DP2–DP7, HGSS2, SM9, SM115/SMA). Sets sem
  cartas ativas (SP, EXU) não devem ser vinculados. MFB segue pausado.

### Fase 3b — Set externo compartilhado (3981, CONFIRMADO EXECUTADO 2026-10-10)

Achado de Fabrício: a JustTCG publica os **dois decks de cada Trainer Kit num único Set** (ex.: "XY Trainer Kit:
Bisharp & Wigglytuff"), enquanto o catálogo tem um Set por deck (TK-XY-B, TK-XY-W). O índice único
`(fonte, Set externo)` impedia o 2º vínculo, e a numeração das cartas (1–30) se repete entre os decks.
Decisão de Fabrício (2026-10-10): **permitir Set compartilhado**, com opt-in explícito e matching por número + nome.

- **3981:** `pricing_set_mapping.is_shared_external` (default false); o índice único passa a valer só para vínculos
  não compartilhados; trigger `trg_pricing_set_mapping_shared_external` impede misturar vínculo compartilhado com
  comum no mesmo Set externo (advisory lock por par); `admin_confirm_pricing_set_mapping` ganha
  `p_shared_external` (default false — chamadas antigas inalteradas). Testes transacionais (rollback):
  dois compartilhados OK; compartilhar Set já usado sem compartilhamento (XY4) bloqueado; comum sobre compartilhado
  bloqueado; dois comuns bloqueado.
- **Matching:** `classifyCardMatchShared` (`_shared/pricing-justtcg-matching/card-matching.ts`) — em Set compartilhado,
  SAFE só quando exatamente um candidato de mesmo número tem nome compatível; nunca promove por número sozinho; empate
  vira PENDING. O bootstrap lê a flag do mapping (`loadSetMappingShared`) e escolhe a regra. Segurança no nível da carta
  segue no índice `uq_pricing_card_mapping_source_external_confirmed`. Refresh não muda: ele filtra por Set local, então
  cartas do outro deck são ignoradas (custo: o Set externo é lido uma vez por deck).
- **Edge `justtcg-set-bootstrap` v2** publicada (bundle equivalente ao repositório, sem comentários). Testes: matching
  50/50 (6 novos para Set compartilhado), bootstrap e preview completos passando (Node `--experimental-transform-types`).
- **UI:** em Revisar/Sem correspondência, quando a opção desejada está em uso aparece "Set da JustTCG compartilhado com
  outro deck do mesmo produto"; marcado numa linha, vale para todos os Sets do lote que escolheram o mesmo Set externo.
- Escopo esperado: 10 pares de Trainer Kits (20 Sets, ~510 cartas).

### Fase 3c — Validação das confirmações manuais e fila do bootstrap (2026-10-10)

- **Validação (LIVE):** 56 Sets confirmados manualmente após a 1ª rodada — McDonald's 2015–2019/2023/2024, Detective
  Pikachu, 8 pares de Trainer Kits (compartilhados), DP2–DP7, EX1/EX4/EX5/EX6/EX8/EX10/EX16, HGSS2, SM9, SM115, SMA,
  SWSH4.5SV, BWP, HGSSP, XYP, SMP, NP, RU1, POP1–POP9. Nomes externos coerentes com os Sets locais; diferenças de data
  ≤ 3 meses (fonte com datas próprias para promos). Total CONFIRMED: **193 Sets**.
- **Correção:** SWSH4.5SV e SMP estavam marcados como compartilhados sem dividir o Set externo com ninguém (isso só
  endureceria o matching). Flag revertida antes do bootstrap, com registro em `pricing_admin_action_log`.
- **Sem correspondência na JustTCG (ficam sem preço, documentado):** FUT2020 (5), TK-EX-M (12), TK-EX-P (12),
  EX5.5 (5), TK-EX-LATIA (10), TK-EX-LATIO (10). Sem cartas no catálogo (nada a vincular): SP, EXU.
- **3982 (CONFIRMADO EXECUTADO):** `open_pricing_set_bootstrap_attempt` prioriza Sets em MATCHING — antes, com ~140 Sets
  confirmados no mesmo minuto, o dispatcher fazia todas as aquisições antes de qualquer matching (preço só ~20 h depois).

### Fase 4 — Preço por Card Variant (3983, CONFIRMADO EXECUTADO 2026-10-10)

- **`get_card_variants_pricing_summary(uuid[])`**: contrato de leitura por variante, base da avaliação de Collection
  (Physical Card referencia `card_variant_id`). Retorna `price_basis`:
  - `VARIANT` — observação MARKET/NM mais recente de produto ativo ligado à própria variante;
  - `CARD_FALLBACK` — sem preço da variante, usa `get_cards_pricing_summary` (hierarquia de printing + manual);
  - `NULL` — sem preço (`has_pricing=false`).
- Segurança idêntica ao resumo por carta: SECURITY DEFINER, `search_path` vazio, `auth.uid()` obrigatório, ≤100 ids,
  array 1-D; EXECUTE só para `authenticated` (anon sem acesso). Não expõe ids externos.
- **Validação LIVE:** amostras dos 3 caminhos (VARIANT, CARD_FALLBACK, sem mapping) corretas; 5 guards
  (sem auth, vazio, NULL, 2-D, 101 ids) com os códigos `VARIANT_PRICING_SUMMARY_*`; 100 ids ≈ 13 ms a quente
  (1ª chamada fria ≈ 1,1 s, igual ao resumo por carta).
- **Residual — catálogo/editorial, não defeito de Pricing** (LIVE 2026-10-10, cresce enquanto o bootstrap roda):
  870 produtos ativos sem variante ligada de 53.425 — `UNIQUE_CONTEXT_ONLY` 440, `NO_CANDIDATE` 405 (variante ausente
  no catálogo: SVP Holofoil, SVE, ME2.5 Reverse, MEP, BASEP, 2022SWSH, GYM2 1st Ed…), `AMBIGUOUS` 25; 52 cartas
  `NOT_FOUND`. Essas variantes recebem `CARD_FALLBACK` até a revisão editorial (UI de resolução existente).

### Fase 5 — Saúde contínua: alertas recalibrados + orçamento da API (3984, CONFIRMADO EXECUTADO 2026-10-10)

Falsos alarmes encontrados no LIVE e corrigidos:

| Antes | Causa | Agora |
|---|---|---|
| Visão Geral em "Atenção" com 139 Sets "aguardando primeira sincronização" | implantação (bootstrap) tratada como problema | nota neutra no Hero ("Implantação em andamento: X de Y prontos, ≈ N h"); Atenção só se a fila parar > 2 h (`onboarding.stalled`) |
| "Fila de atualização atrasada há mais de 1 hora" | `next_due_at` incluía Sets ainda sem 1º refresh (hora da confirmação) | só Sets que já tiveram o 1º refresh entram |
| "Sets aguardando configuração: 8" | 6 Sets que a JustTCG não publica + 2 Sets sem cartas (SP, EXU) | 6 registrados como `pricing_set_mapping` NOT_FOUND (log `PRICING_SET_MAPPING_NOT_FOUND`, reversível pela confirmação manual); Sets sem cartas fora do denominador; tile só conta pendência real e leva à Descoberta |
| "Saúde dos Sets 53/193" | denominador incluía Sets em implantação | `saudáveis / em operação` + "+N em implantação" |
| sem visão de orçamento | — | faixa "Orçamento da API": consumido no mês, projeção até o fim do mês (% do plano), hoje × limite diário, barra contra o limite mensal |

- `pricing_source.monthly_request_limit` / `daily_request_limit` (JUSTTCG 10.000 / 1.000, ADR-029).
- `get_pricing_admin_overview()` ganhou `coverage.{confirmed,not_found,unconfigured,without_cards}`, `onboarding`,
  `api_budget`, `cards_without_mapping`, `products_without_variant` (payload anterior preservado).
- Projeção = consumo do mês (UTC) + regime diário estimado (custo do último refresh de cada Set ÷ frequência; sem
  histórico, páginas de 100 cartas) até o fim do mês + aquisições restantes da implantação. LIVE 10/10: 1.309
  consumidas, regime ≈ 241/dia, projeção ≈ 6.583 (66% do plano).
- Atenção de orçamento: projeção > 90% do plano ou consumo do dia > 90% do limite diário.
- UI (skill impeccable, polish): `pricing-api-budget.tsx` (novo, Server Component), `pricing-overview-stats.tsx`
  (tiles condicionais "Sets aguardando configuração" → Descoberta e "Implantação de Sets" com progresso/ETA; rodapé com
  Sets sem fonte, Sets sem cartas e produtos sem variante), `pricing-overview-hero.tsx` + `hero-fact.tsx` (`hint`),
  `pricing-overview-status.ts` (`notes`, regras novas). Typecheck OK. Validação visual (light/dark, mobile): pendente
  na máquina do Fabrício.

### Pós-Fase 5 — Produtos com variante única "só por contexto" (3985, CONFIRMADO EXECUTADO 2026-10-10)

- Fila `UNIQUE_CONTEXT_ONLY` (cresceu de 440 para 560 com o bootstrap) auditada carta a carta por grupo:
  SVP Prerelease 169 (nome externo "(Prerelease)"; a outra variante é a Staff), McDonald's 2021 (250) / 2012 (60) /
  2014 (60), Worlds 2023–2025 (8, versão base sem colocação) e BASEP Pokémon 4Ever (10) — em todos, o catálogo
  **não tem variante sem Edition Context**: o contexto é a identidade da carta.
- Exceção: SWSH4 League Staff (3) — o catálogo tem a versão comum (sem contexto) e só o Reverse com `ROLE_STAFF`;
  o produto "Reverse Holofoil" deve ser o reverse comum, que falta no catálogo. **Não vinculado** (fica no fallback
  da carta) — pendência editorial: provável variante REVERSE_HOLO sem contexto ausente / trait aplicado ao Reverse errado.
- Regra permanente `UNIQUE_INHERENT_CONTEXT` no resolver; aceita pelo trigger de inserção e pelo
  `admin_reconcile_pricing_product_variants` (produtos novos desses Sets já entram ligados).
- Execução: dry-run 557/3 → apply **557** (log `PRICING_PRODUCT_VARIANT_RECONCILED`, rule 3974+3977+3985). Produtos
  ativos sem variante: 1.029 → **472** (NO_CANDIDATE 444, AMBIGUOUS 25, UNIQUE_CONTEXT_ONLY 3). Prova: 0 produtos
  ligados a variante de outra carta; `get_card_variants_pricing_summary` devolve VARIANT nas variantes vinculadas e
  CARD_FALLBACK nas Staff/colocações (sem produto próprio na fonte).
