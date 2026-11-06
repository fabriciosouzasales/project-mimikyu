# V1-14 R1-B — Inventário e valor do Acervo

| Campo | Valor |
|---|---|
| Status | **EM REAVALIAÇÃO — NÃO APLICAR.** Escrita para o relatório combinado "Inventário e valor", rejeitado em 2026-11-06 (`REPORT CATALOG RESTRUCTURING-03`): o catálogo do Acervo passou a ter 8 relatórios independentes e Valor, Top 10 e Cobertura serão relatórios distintos. Antes de qualquer execução, decidir se esta leitura agregada atende os três (cada um apresentando só a sua parte) ou se deve ser dividida. Nenhum SQL executado no LIVE. Reavaliada em 2026-11-06 (`INVENTORY BY CARD SET`): **não é necessária** para o Inventário detalhado por Card Set (quantidade × unitário da 3983 por linha, via 5159/3983); segue candidata a Valor estimado total, Top 10 e Cobertura. |
| Data | 2026-11-06 (`V1-14 R1-B INVENTORY & VALUE-01`) |
| Pré-requisitos | 5159–5162 (Meu acervo) e 3983 (`get_card_variants_pricing_summary`) no LIVE |
| Executor | Fabrício, com autorização explícita |

## Por que (lacuna comprovada)

O relatório pede valor **por exemplar físico** com cobertura e Top 10 (contrato D7 §D7.6). As leituras existentes não bastam:

1. **5160** (`get_my_inventory_summary`) dá exemplares, diferentes e repetidas — sem valor.
2. **3983** dá a referência NM por variante, até 100 ids por chamada, e não conhece o Inventory; valorar o acervo pelo app exigiria ler todos os exemplares (5159 pagina grupos, não exemplares) e N chamadas.
3. **5340/5347** valoram Favoritos/Wishlist UMA vez por carta/variante — não é patrimônio.

## O que muda

| Query | Objeto | Tipo |
|---|---|---|
| 5353 | `get_my_inventory_value_report(p_top integer default 10)` | leitura agregada do titular: totais (= 5160), cartas distintas, variantes cotadas, exemplares com/sem preço, valor somado por exemplar (NULL sem cobertura), datas de observação mín./máx. e Top N (1–50) exemplares cotados em `jsonb` |
| 5879 | harness | 14 checagens (estrutura, ACL, anon, sem identidade, p_top inválido, acervo vazio, cálculo por exemplar, coerência com 5160, Top determinístico e só cotados, limite do Top, isolamento A×B, somente leitura, volume 2.000 exemplares < 3 s, resíduo zero) |

Sem tabela, sem índice, sem alterar 3983/5159–5162 nem qualquer regra de Pricing. Identidade só por `auth.uid()`; EXECUTE só `authenticated`. Nenhuma escrita.

**Regras efetivas.** Cada exemplar vale a referência NM da sua variante (3983: VARIANT ou CARD_FALLBACK, PTAX da data da observação); idioma e condição física não entram. Referência ausente, sem câmbio ou ≤ 0 = exemplar sem preço — fora da soma, contado em `unpriced_copies`. Top: só exemplares cotados; ordem `brl desc, nome, Set, número, variante, idioma, data de cadastro, id do exemplar` (total e determinística); cópia identificada como N de M dentro do mesmo Card Variant + idioma, por data de cadastro.

**Desempenho.** Variantes distintas do usuário lidas uma vez (`ix_physical_card_inventory_variant`); 3983 em blocos de 100 dentro do banco (uma ida do app); totais e Top num único agrupamento. Custo: `ceil(variantes/100)` chamadas da 3983 + O(exemplares). O 3.8 do harness mede 2.014 exemplares sobre até 300 variantes.

## Plano de aplicação

1. Aplicar `5353_create_get_my_inventory_value_report_function.sql`.
2. Executar `5879_validate_inventory_value_report.sql` (uma chamada) — esperado `GATE PASS 14/14`. Exige no catálogo, entre as 300 primeiras variantes ativas, ao menos uma com referência NM e uma sem (senão `X.1` com `TR_FIXTURE`, sem fabricar preço).
3. Homologar. Antes da 5353, o relatório abre e informa "Relatório ainda não disponível" (PGRST202/42883) — nada quebra no Acervo e nada é gravado.

## Rollback

```sql
drop function if exists public.get_my_inventory_value_report(integer);
```
Sem dados a desfazer.
