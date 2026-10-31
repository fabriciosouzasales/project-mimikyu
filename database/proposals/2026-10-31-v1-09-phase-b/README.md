# V1-09 Fase B — preço NM em Set, Master Set e Pokédex

| Campo | Valor |
|---|---|
| Frente | V1-09 PHASE B IMPLEMENTATION-01 |
| Status | **5333 e 5334 CONFIRMADO EXECUTADO no LIVE em 2026-10-31** (ledger `20261031181928` / `20261031182002`; corpos = arquivos; EXECUTE só `authenticated`). **5866 v1.1: GATE 12/12 PASS**, resíduo zero; 4.1 (8 coleções de Set/Master Set, 0 divergências) e 3.1–3.3 com fixture; 4.2 sem dados na execução; **ressalva resolvida na LOCAL HOMOLOGATION-04 pela `5867` (somente leitura)**: vínculo real criado pelo proprietário pela interface (Nº 0001, ME1 001 + ME1 133), 5204 × 5209 × 5334 iguais em número, Set, variante e imagem, desempate pelo vínculo mais antigo, conferido na grade. `NOTIFY pgrst` executado. **5333 e 5334 promovidas a `database/schema`** (corpos = LIVE). Frontend sem commit. |
| Data | 2026-10-31 |
| Arquivos | `5333_create_get_my_collection_card_variants_function.sql`, `5334_create_get_my_pokedex_representative_variants_function.sql`, `5866_validate_v1_09_phase_b_reads.sql` v1.1 (harness, 12 checagens; READINESS-02: uma única leitura de R1 na Parte 4), `5867_verify_pokedex_representative_equivalence.sql` (equivalência real da Pokédex, somente leitura) |
| Numeração | 5333, 5334 e 5866 conferidas livres em `database/` e `docs/` |

## Por que SQL novo

As leituras de posições (5169 Set, 5189/5198 Master Set, 5204 Pokédex) não devolvem a variante dos exemplares, e `card_variant` não é legível pelo usuário (RLS admin). O preço NM é por variante (3983). Sem uma leitura aditiva, a grade não consegue associar o preço à variante certa — registrado em `docs/05f-pricing.md` desde a Fase A.

## Regra de apresentação (implementada em `web/lib/pricing/position-pricing.ts`, 11 testes)

- Set: posição com exemplares de **uma única** variante → etiqueta dessa variante (preço unitário, mesmo com várias cópias); variantes diferentes → nenhuma etiqueta; sem exemplar → nada.
- Master Set: posição = carta + acabamento; só contam exemplares desse acabamento. Duas variantes do mesmo acabamento (ex.: carimbos) → nenhuma etiqueta. Secreta genérica: todos os exemplares da carta, mesma regra.
- Pokédex: a arte é de um exemplar (representante, mesma regra da 5204); preço da variante desse exemplar, só se número + Set lidos pela 5334 coincidirem com os da 5204.
- Etiqueta idêntica à Fase A (`VariantPriceSummary` overlay, canto inferior esquerdo, detalhe interativo). Na Pokédex, o selo do número nacional sobe para logo acima da etiqueta quando há preço.
- Privacidade: só o titular (rotas `get_my_*`; 5333/5334 conferem o dono). A grade compartilhada (`PositionTile` do VIEWER) não recebe preço.

## Desempenho

Por abertura: uma leitura de variantes restrita às posições da página com exemplar (≤ 500 ids) + o lote de preços da Fase A (3983, blocos de 100), em paralelo com o logo/capa. Nenhum cálculo de progresso novo; `get_my_collection` (5332) intocada. Pokédex "Mostrar mais": a ação devolve os preços da página carregada.

## Publicação (ordem obrigatória)

1. ~~Aplicar 5333 e 5334~~ — feito (2026-10-31).
2. ~~Executar 5866~~ — 12/12.
3. ~~`NOTIFY pgrst`~~ — feito. ~~Equivalência real da Pokédex (5867)~~ — comprovada. Homologação visual desktop de Set/Master Set: Fabrício. **READINESS-05 (2026-10-31):** reexecução da 5867 para o representante manual (ME1 133) retornou 0 posições — os dois exemplares estão livres no acervo (fora de qualquer coleção); o estado não existe mais no LIVE e não pôde ser comprovado por SQL (evidência disponível: captura do proprietário). Para comprovar: revincular ME1 001 e ME1 133 ao Nº 0001, escolher a ME1 133 em "Mostrar na grade" e rodar a 5867.
4. Commit/push/deploy autorizados por Fabrício.

Frontend antes do banco: as chamadas falham com `PGRST202`, são registradas em `pricing.positions.read` e a grade aparece sem etiquetas.

## Rollback

Reverter o commit do frontend. `DROP FUNCTION public.get_my_collection_card_variants(uuid, uuid[]);` e `DROP FUNCTION public.get_my_pokedex_representative_variants(uuid, uuid[]);` — nada depende delas, somente leitura.
