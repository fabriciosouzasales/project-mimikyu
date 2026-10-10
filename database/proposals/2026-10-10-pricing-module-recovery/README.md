# PRICING-MODULE-RECOVERY-01 — diagnóstico e plano (2026-10-10)

| Campo | Valor |
|---|---|
| **Status** | Diagnóstico concluído · **Fase 2 (frequência) EXECUTADA 2026-10-10 (3978)** · demais fases pendentes |
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
