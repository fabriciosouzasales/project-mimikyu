# D2 — Reconciliação dos tipos legados de Finish

| Campo | Valor |
|---|---|
| **Status** | Parte 1 EXECUTADA (`D2-01`, 2026-10-09); parte 2 EXECUTADA (`D2-02`, 2026-10-09); parte 3 EXECUTADA (`D2-03`, 2026-10-09) — **D2 CONCLUÍDA** |
| **Data** | 2026-10-09 |
| **Mandato** | Decisões de Fabrício em 2026-10-09 (ver abaixo) |
| **Sequência** | Item 5b do `docs/ROADMAP.md` |

## Problema

Alguns tipos de Finish (`card_variant_type`) foram criados antes dos eixos Printing e
Edition Context e misturam acabamento com contexto: `SET_LOGO_STANDARDS`,
`SET_LOGO_REVERSE`, `STAFF_HOLO`, `STANDARDS_LEAGUE`, Worlds, campeonatos etc. Com os três
eixos em produção, essas combinações geram identidades paralelas para a mesma carta.

## Diagnóstico (LIVE, 2026-10-09, read-only)

- 709 Card Variants usam 5 tipos legados mistos. Nenhuma é referenciada por
  `physical_card`, `pricing_product` ou Collections. A simulação deu 0 colisões de identidade.
- A lineage (`catalog_variant_import_row.raw_data`) mostra o que a fonte dizia:
  - `SET_LOGO_STANDARDS`: `normal + set-logo` (469 em EX11–EX16, 11 fora);
  - `SET_LOGO_REVERSE`: `holo + set-logo` (86 em EX11–EX16, 99 fora);
  - `SET_LOGO_COSMOS_HOLO`: `holo cosmos/galaxy + set-logo` (3);
  - `STAFF_HOLO`: 39 com `[set-logo, staff]` e 1 só com `[staff]`;
  - `SET_LOGO_STAFF_HOLO`: `[staff, set-logo]` (1).
- Cerca de 60 tipos legados nunca geraram variante e existem só como rotas de importação (parte 2).
- `PROMO_STAMPED` (33) e `STANDARDS_SNOWFLAKE` (27) são ambíguos (parte 3).
- Ficam fora da D2 e continuam como Finish: GOLD, RAINBOW, GALAXY, CRACKED_ICE, TINSEL,
  SNOWFLAKE, METAL, LENTICULAR e as reversas de padrão (Poké/Master/Love/Friend/Quick/Dusk
  Ball, Energy, Rocket).

## Parte 1 — `D2-01` (aprovada)

| Grupo | Origem | Destino | Linhas |
|---|---|---|---:|
| 1 | `SET_LOGO_STANDARDS` / `SET_LOGO_REVERSE` em EX11–EX16 | `REVERSE_HOLO`, sem contexto (= decisão H2 de EX7–EX10) | 555 |
| 2 | `SET_LOGO_STANDARDS` fora de EX11–EX16 | `STANDARD` + `ARTWORK_SET_LOGO` | 11 |
| 2 | `SET_LOGO_REVERSE` fora de EX11–EX16 | `HOLO` + `ARTWORK_SET_LOGO` | 99 |
| 2 | `SET_LOGO_COSMOS_HOLO` | `COSMOS_HOLO` + `ARTWORK_SET_LOGO` | 3 |
| 3 | `STAFF_HOLO` com logo | `HOLO` + `ARTWORK_SET_LOGO__ROLE_STAFF` (perfil novo) | 39 |
| 3 | `STAFF_HOLO` sem logo | `HOLO` + `ROLE_STAFF` | 1 |
| 4 | `SET_LOGO_STAFF_HOLO` | `HOLO` + `ARTWORK_SET_LOGO__ROLE_STAFF` | 1 |

Para os grupos 2 e 3, o destino segue a lineage. O grupo 2 (`SET_LOGO_REVERSE`) vai para
`HOLO`, e não para `REVERSE_HOLO`, porque a fonte diz `holo`. O grupo 3 ganha o logo porque
39 das 40 linhas têm o carimbo `set-logo`.

A atualização é feita no lugar (mesmo `id`), com gates fail-loud: tamanho do plano,
distribuição por grupo, colisão, referências e total de `card_variant`.

## Parte 1 — resultado

Executada por Fabrício em 2026-10-09. Leitura posterior: 0 variantes nos 5 tipos legados; perfil
`ARTWORK_SET_LOGO__ROLE_STAFF` selado; `card_variant` = 26.524; 0 duplicidade.

**Achado posterior:** 18 identidades CONFIRMED de Pricing (`pricing_source_card_identity`) apontam
para `STAFF_HOLO` (17) e `SET_LOGO_REVERSE` (1), tipos que agora não têm variante. Nenhum
`pricing_product` estava ligado às 709. Esses dois tipos ficam ativos e a reconciliação vai para o
Pricing 80 (`PRICING-CATALOG-VARIANT-RECONCILIATION-01`).

## Parte 2 — `D2-02` (aprovada; dry-run PASS)

Achado: o eixo Edition Context consome o carimbo antes da busca do acabamento, então 62 das 69 rotas
legadas já não casavam com nada. Só SET-LOGO (6) e PIKACHU-TAIL (1) estavam vivas.

| Passo | O quê |
|---|---|
| A | 23 rotas EC por coleção: stamp SET-LOGO → ARTWORK_SET_LOGO (fora de EX) |
| B | 12 rotas de Finish por coleção em ex11–ex16: NORMAL/HOLO + SET-LOGO → REVERSE_HOLO |
| C | 1 variante SV5 (holo galáxia + logo): COSMOS_HOLO → GALAXY_HOLO (decisão: seguir a fonte) |
| D | 1 rota EC em basep: PIKACHU-TAIL → CAMPAIGN_PIKACHU_WORLD_2000 |
| E | remove as 69 rotas de Finish legadas; desativa 63 tipos sem variante (STAFF_HOLO e SET_LOGO_REVERSE ficam ativos por causa do Pricing) |

**Dry-run (2026-10-09, transação desfeita):** universo de 5.000 linhas de staging com
carimbo/foil e variante persistida. Antes do D2-02, 638 delas não reproduziam a própria variante
numa reimportação. Depois, **0**, com 0 divergências novas e o total de `card_variant` inalterado.
5 linhas NEEDS_REVIEW passariam a resolver (as 4 set-logo SV e 1 pikachu-tail), mas o D2-02 não
reprocessa staging.

**Execução:** Fabrício rodou com `v_apply = true` em 2026-10-09. A primeira tentativa caiu por
falha de rede no SQL Editor e não gravou nada (leitura confirmou). Na segunda, a leitura posterior
mostrou 26 rotas EC SET-LOGO (3 já existentes + 23), 1 PIKACHU-TAIL, 12 rotas de Finish em EX11–EX16,
45 rotas de Finish restantes, 65 tipos inativos (2 + 63), a variante SV5 como GALAXY_HOLO + logo,
`card_variant` = 26.524 e 0 duplicidade.

## Parte 2 (plano original)

Para cada tipo legado sem variante, apontar o mapping para o acabamento base e desativar o
tipo, deixando o contexto para o Edition Context. Inclui os SET_LOGO_*, para que importações
futuras não recriem os tipos legados. EX11–EX16 precisa de mapping `SOURCE_SET`, como na H2.

## Parte 3 — `D2-03` (decisões de Fabrício; dry-run PASS)

**Snowflake → contexto neutro.** A fonte traz `normal + stamp snowflake`, um token diferente de
`countdown-calendar`. O D2-03 cria o traço e o perfil `ARTWORK_SNOWFLAKE_STAMP` ("Carimbo Floco de Neve"),
sem afirmar de qual campanha é o carimbo, e a rota EC global `stamp SNOWFLAKE`.

Ao preparar o script apareceu uma consequência: a rota global consome o carimbo antes da busca do
acabamento. Por isso os dois acabamentos que já embutiam o floco também precisam ser decompostos,
senão a reimportação divergiria (o dry-run acusou 22 casos):

| Tipo legado | Variantes | Destino |
|---|---:|---|
| `STANDARDS_SNOWFLAKE` | 27 | STANDARD + floco |
| `SHOWFLAKE_HOLO` | 17 | HOLO + floco |
| `SNOWFLAKE_COSMOS_HOLO` | 5 | COSMOS_HOLO + floco |

As 3 rotas de Finish com `{SNOWFLAKE}` são removidas e os 3 tipos desativados.

**PROMO_STAMPED → removido.** São 33 variantes (ME2.5 10, MEP 23) criadas à mão em julho, sem lineage
e sem evidência do carimbo: o checklist PDF da ME2.5 não cita carimbos, e a busca externa só confirmou
Prerelease/Staff para MEP 001–004. Nenhuma tinha cópia, preço, coleção ou staging ligado. As 33 são
apagadas e o tipo desativado. Consequência: a carta MEP 028 (Fanfarra de Celebração) só tinha essa
variante e entra na lista de cartas sem variante (6.726 → 6.727), tratada em
`CATALOG-VARIANT-COVERAGE-GAP-01`.

**Dry-run (transação desfeita):** 0 divergências de reimportação nas linhas com floco;
`card_variant` 26.524 → 26.491.

**Execução (2026-10-09):** leitura posterior: 0 variantes nos 4 tipos; 49 variantes com o perfil floco; rota SNOWFLAKE selada; 69 tipos inativos, 28 ativos; `card_variant` = 26.491; 0 duplicidade; 6.727 cartas sem variante.

## Resultado da D2

- 709 + 49 variantes decompostas nos três eixos, sempre no lugar (mesmos ids); 33 removidas.
- 69 tipos de Finish desativados; restam 28 ativos (acabamentos reais + `STAFF_HOLO`/`SET_LOGO_REVERSE`, mantidos pelo Pricing).
- Rotas de importação reproduzem 100% das variantes com carimbo/foil.
- Pendências que saem daqui: 18 identidades de Pricing → Pricing 80; MEP 028 sem variante → `CATALOG-VARIANT-COVERAGE-GAP-01`; 5 NEEDS_REVIEW agora resolvíveis (4 set-logo SV + 1 pikachu-tail) → próxima revalidação.
