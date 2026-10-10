# CATALOG-VARIANT-COVERAGE-GAP-01 — Cartas sem Card Variant

| Campo | Valor |
|---|---|
| **Status** | Fonte decidida (ADR-034 v0.2, snapshot congelado). **Snapshot obtido** e **F1 (correspondência) concluída**, sem escrita no LIVE. **F2-01 EXECUTADO** por Fabrício (2026-10-09). **F3-01 aplicado e XY1 em staging** (job `686f4ed4…`, 269 linhas, 2026-10-10). **Piloto XY1 CONCLUÍDO** (F5-01 executado: 269 variantes, `card_variant` 26.760). **F6 (campanha) CONCLUÍDA** (2026-10-10): 49 jobs COMPLETED, 10.812 variantes, `card_variant` **37.303**, cartas sem variante **330**. **Frente FECHADA** (2026-10-10): F2-01/F3-01 promovidos (2246/2247), UI traduz a 2ª fonte, achados restantes registrados. |
| **Sequência** | Item 5c do `docs/ROADMAP.md` |
| **Por que importa** | `physical_card.card_variant_id` é `NOT NULL`: sem variante, a carta não entra em Collections. |

## Universo (LIVE, 2026-10-09)

**6.727 cartas sem nenhuma variante** — soma fechada:

| Grupo | Cartas | Sets |
|---|---:|---|
| 1. Fonte em formato booleano | 296 | SWSH1, SWSH3.5 |
| 2. Coleções principais BW/XY/SM | 5.081 | 36 (BW1–BW11, XY0–XY12, SM1–SM12, SM115) |
| 3. Especiais | 465 | CEL25CC, DC1, DET1, DV1, G1, SM3.5, SM7.5, SMA |
| 4. Promos | 613 | BWP, XYP, SWSHP (287 de 300), SVP (8), MEP (1) |
| 5. Trainer Kits | 270 | 9 kits HS/XY |
| 6. ME5.5 | 2 | já tem frente própria (`CATALOG-ME5.5-IMPORT-01`) |

## O que a fonte atual (TCGdex) oferece

Retomado de `2026-09-18-bulk-staging-01/source-variant-coverage-169.md` e reconfirmado no
`raw_data` da importação de cartas:

- **Grupos 2, 3, 5 (e parte do 4):** o arquivo-fonte não declara variante. O objeto `variants`
  que aparece no `raw_data` (`normal: true`, resto `false`) é o **default do compilador**, igual
  até para Ultra Raras. Não é dado.
- **Grupo 1 (SWSH1, SWSH3.5):** o objeto booleano é real (comuns `normal + reverse`, Holo V
  `holo`, Rara Holo `holo + reverse`). Ele dá o acabamento, mas não traz foil/subtype/size.
  Nesses dois Sets nenhum desses campos é necessário.

## A regra era × raridade resolve quanto?

Nas coleções principais BW/XY/SM a estrutura de impressão é conhecida (comum/incomum = Normal +
Reverse; Ultra/Secreta = só Holo). O bloqueio é a **Rara**: a raridade importada em pt-BR é "Rara"
tanto para a rara comum quanto para a rara holo. O dado atual não distingue as duas.

| Raridade (grupo 2) | Cartas | Regra aplicável? |
|---|---:|---|
| COMMON | 1.351 | Sim: STANDARD + REVERSE_HOLO |
| UNCOMMON | 1.407 | Sim: STANDARD + REVERSE_HOLO |
| ULTRA_RARE | 653 | Sim: HOLO |
| RARE_SECRET | 275 | Sim: HOLO |
| RARE | 1.356 | **Não**: holo ou não-holo indistinguível (sempre + REVERSE_HOLO) |
| NONE | 39 | Não (XY0, kit inicial) |

A regra cobre **3.686 de 5.081** cartas do grupo 2 (73%). As 1.356 Raras exigem outra fonte.

## Fontes possíveis para o restante

- **pokemontcg.io (API pública):** traz a raridade em inglês ("Rare" × "Rare Holo") e, por carta,
  as chaves de preço TCGplayer (`normal`, `holofoil`, `reverseHolofoil`, `1stEditionHolofoil`),
  que na prática listam as variantes existentes. Exige integração nova (staging, mapping, validação),
  nos mesmos moldes do TCGdex.
- **TCGdex em inglês:** a raridade "Rare Holo" pode existir em `en`, mas as variantes continuam
  ausentes. Só ajudaria a separar a Rara.
- **Curadoria manual:** inviável em volume (5.000+ cartas).

## Decisão (Fabrício, 2026-10-09)

**pokemontcg.io como segunda fonte de variantes**, em staging como o TCGdex. A regra era × raridade
fica só como checagem cruzada.

## Sonda da fonte (2026-10-09, leitura pública, sem chave)

Pelo navegador, `GET /v2/cards?q=set.id:<id>&select=id,number,rarity,tcgplayer`:

- **Formato:** a raridade vem em inglês e separa "Rare" de "Rare Holo". As chaves de
  `tcgplayer.prices` listam as variantes da carta (`normal`, `holofoil`, `reverseHolofoil`,
  `1stEditionHolofoil`, …). Exemplo XY1 (146 cartas): Common `normal+reverseHolofoil` 39 e `normal` 9
  (energias), Rare `normal+reverseHolofoil` 26, Rare Holo `holofoil+reverseHolofoil` 16, Rare Holo EX
  `holofoil` 8, Rare Ultra `holofoil` 6.
- **Cobertura medida:** 34 Sets responderam, com 4.424 cartas, das quais 4.361 (98,6%) trazem
  variantes. Ex.: BW1–BW11 100%; XY1 100%; SM1 163/173; XYP 209/216; SWSH1 216/216; SWSH3.5 80/80;
  DC1, DV1, SM115 e XY0 100%.
- **Catálogo de Sets:** cobre todos os grupos 1–4 (BW, XY, SM, especiais, BWP/XYP/SWSHP/SVP).
  **Não cobre os Trainer Kits (270 cartas)**, que continuam sem fonte. Cobre também `me55`
  (161 cartas), útil para `CATALOG-ME5.5-IMPORT-01`.
- **Estabilidade:** sem chave de API, a fonte respondeu HTTP 500/502 com frequência; 16 Sets não
  completaram na janela da sonda. (Superado: com a API descontinuada, a fonte virou o snapshot versionado;
  as 50 coleções foram baixadas completas, com novas tentativas, e não há chamada de rede na integração.)

## Riscos a tratar no desenho

1. **Chaves de preço como sinal de variante:** é um proxy. Cerca de 1,4% das cartas vêm sem preço
   e ficam sem variante; essas linhas vão para revisão, nunca recebem default.
2. **Correspondência carta ↔ carta:** pelo par Set + número. Nomes não servem (pt-BR × en). Sets
   com numeração especial (SMA `SV1`, XYP `XY01`) precisam de normalização explícita.
3. **Vocabulário:** `normal`→STANDARD, `holofoil`→HOLO, `reverseHolofoil`→REVERSE_HOLO. Qualquer outra
   chave cai em revisão (deny by default, ADR-034). No snapshot não apareceu nenhuma outra chave.
4. **Governança:** nova `asset_source`, staging próprio e um ADR (segunda fonte de variantes,
   precedência sobre o TCGdex por Set).

## Desenho da integração (2026-10-09)

Decisão arquitetural: `docs/adr/ADR-034-second-variant-source-pokemontcg.md` (Aprovado, v0.2). A API foi
descontinuada (chaves só até 01/03/2027); por decisão de Fabrício a fonte virou **snapshot único**,
versionado em `database/seeds/sources/pokemontcg-snapshot-2026-10-09/`. Com isso saem a chave de API, o
segredo e o retry em tempo de execução: a tabela de fatias abaixo foi revisada.

### O que já existe e é reaproveitado

- `asset_source` `POKEMON_TCG_API` já existe, sem nenhum uso (0 refs, 0 mappings).
- Staging `catalog_variant_import_job/row`, o resolver de três eixos, o decide (2144) e o confirm
  (2145). A RPC de mapping (2150) já traduz `job.source` → `asset_source.code`.

### O que muda

| Fatia | Conteúdo | Escrita no LIVE? | Estado |
|---|---|---|---|
| ~~F0~~ | ~~Chave de API como segredo da Edge.~~ Substituída pelo snapshot. | — | Superada |
| **S** | Snapshot da fonte no repositório (50 coleções, 6.733 cartas, manifest com contagem e hash). | Não | **Feito** |
| **F1** | Prova de correspondência Set + número normalizado contra as cartas sem variante (`F1/match.py`). | Não | **Feito** (abaixo) |
| **F2** | `F2-01_second_source_foundation_ready.sql` (detalhe abaixo). | Sim (script com dry-run) | **Executado** |
| **F3** | `F3-01_stage_function_ready.sql` (função) + `F3/stage_<set>.sql` (49 chamadas, uma por coleção, com o arquivo do snapshot embutido). Detalhe abaixo. | Sim (staging) | **Pronto, prova PASS** |
| **F4** | Checagem cruzada com a regra era × raridade (comum/incomum = STANDARD + REVERSE; ultra/secreta = HOLO). Divergências vão para revisão antes do confirm. | Não | **Feito** (pós-campanha, abaixo) |
| **F5** | Piloto em XY1 (146 cartas): `F3/stage_xy1.sql` (executado: job `686f4ed4-28df-4ca1-81d9-fd2f0639249f`, STAGED, 269 linhas) → `F5-01_confirm_xy1_ready.sql` (decide + confirm, dry-run PASS: 269 inseridas, `card_variant` 26.491 → 26.760, XY1 sem variante 0). | Sim | **Concluído** (2026-10-10) |
| **F6** | Campanha nas 48 coleções restantes em 4 lotes: `F6/stage_{A_bw,B_xy,C_sm,D_outros}_{dryrun,apply}.sql` (uma consulta por lote; falha em qualquer coleção desfaz o lote) + `F6/confirm_staged_ready.sql` (decide + confirm de todo job STAGED da 2ª fonte, mesmos gates do F5-01). | Sim | **Concluída** (2026-10-10, execução direta, abaixo) |

### Resultado da F1 (2026-10-09, só leitura)

Universo: as 6.727 cartas sem variante, menos as que a fonte não tem (Trainer Kits 270, ME5.5 2,
MEP 028) = **6.454 cartas em 50 coleções**.

| Resultado | Cartas | Observação |
|---|---:|---|
| Casadas, 1 para 1 | 6.422 (99,5%) | 0 ambíguas |
| — com chaves de preço | 6.397 | viram 10.812 linhas de staging |
| — sem chave de preço | 25 | sem variante padrão; vão para revisão |
| Sem correspondência | 32 | CEL25CC 25 e SVP 7 |

Combinações de chaves nas 6.397: `normal + reverseHolofoil` 3.866; `holofoil` 1.885;
`holofoil + reverseHolofoil` 540; `normal` 94; `holofoil + normal` 9 (XY0); `reverseHolofoil` 3.

**Achados que pedem decisão antes da F2:**

1. **CEL25CC (25):** nós numeramos `CC001`–`CC025`; a fonte usa o número original de cada carta
   (`2`, `4`, `15` ×4, …). Número não casa. As 25 têm só `holofoil` na fonte. Saídas possíveis: tabela
   de correspondência curada, ou ficar sem variante.
2. **SVP (7):** os números 191, 192, 213, 214, 215, 225 e 226 não existem na fonte (ela para no 207).
   Ficam sem fonte.
3. **Numeração suspeita no nosso catálogo (10 cartas, XY):** em XY2, XY4, XY6, XY7, XY9 e XY10 temos uma
   carta com sufixo (`88a`, `24a`, `65a`, `77a`, `92a`, `75a`, `98b`, `107a`, `43a`, `105a`) e **não**
   temos a carta base, cuja posição ela ocupa (ex.: XY10 `105a` aparece no lugar da 108). Na fonte, as
   versões com sufixo são cartas diferentes e sem preço. Parece defeito de importação do catálogo, não
   da fonte. Essas 10 casam com a versão "a" e entram nas 25 sem chave. Fica fora desta frente, como
   achado à parte.

### F2 — `F2-01` (decisão de Fabrício, 2026-10-09: CEL25CC fica sem variante)

**Correção da contagem:** são **49** coleções, não 48. A SVP entra porque 1 das 8 cartas dela casa
(SVP 102); as outras 7 seguem sem fonte. Fica de fora só a CEL25CC.

| Passo | O quê |
|---|---|
| S1 | CHECK de `catalog_variant_import_job.source` passa a aceitar `POKEMON_TCG_API` |
| S2 | 49 `card_set_external_reference` da fonte, cada uma com o SHA-256 do arquivo do snapshot em `metadata` |
| S3 | 3 rotas de Finish GLOBAIS: NORMAL → STANDARD, HOLOFOIL → HOLO, REVERSEHOLOFOIL → REVERSE_HOLO |
| S4 | Guard `trg_cvir_second_source` (só para jobs da 2ª fonte). No staging: carta do Card Set do job, carta sem nenhuma variante, só `VALID`, `type` dentro das 3 chaves. No confirm: se a carta ganhou variante de outra origem depois do staging, a linha falha e nada é gravado. `card_id`/`job_id` imutáveis. Guard `trg_cvij_source_immutable`: a fonte do job não muda. |
| S5 | Cancela o job TCGDEX vazio da SM12 (0 linhas, STAGED desde 2026-09-18), que ocupava o índice de job ativo da coleção |

**Revalidação (2239/2245) não muda.** Ela só toca linhas `NEEDS_REVIEW`, e o guard impede que uma linha
da 2ª fonte seja outra coisa além de `VALID`. Uma chave fora das 3 é recusada no staging em vez de ir para
revisão; como o snapshot é imutável e só tem as 3 chaves, nenhum caso real cai nisso (ADR-034 v0.3).

**Dry-run (2026-10-09, transação desfeita):** todos os gates passaram; provas T1–T10 (aceite em carta sem
variante; recusa de NEEDS_REVIEW, de carta de outra coleção, de carta com variante, de chave fora do
vocabulário; duas variantes da mesma carta no mesmo job; corrida com outra origem no confirm; job TCGDEX não
afetado; fonte e identidade imutáveis) e as 3 rotas resolvem para STANDARD/HOLO/REVERSE_HOLO.
`card_variant` 26.491 inalterado; leitura posterior confirmou que nada ficou gravado.

**Execução (2026-10-09):** Fabrício rodou com `v_apply = true`. Leitura posterior: CHECK aceita as duas fontes; 49 referências; 3 rotas (normal→STANDARD, holofoil→HOLO, reverseHolofoil→REVERSE_HOLO); os 2 triggers ativos; job da SM12 CANCELLED; 0 jobs da 2ª fonte; `card_variant` 26.491; 6.727 cartas sem variante; `anon` sem EXECUTE no guard.

**Observação para a UI:** a consulta de job ativo por carta (`web/lib/catalogo/queries.ts`) filtra
`source = 'TCGDEX'`, e o rótulo da fonte só traduz `TCGDEX`. Jobs da 2ª fonte aparecem com o código cru.
Ajuste de exibição fica para a fatia do carregador.

### F3 — carregador (2026-10-10)

`internal.stage_pokemontcg_snapshot_set(p_snapshot_text, p_apply)`, executada no SQL Editor:

- **Integridade:** o SHA-256 do texto recebido (sem CR) precisa bater com o `snapshot_sha256` gravado na
  referência da coleção na F2-01, e a contagem com `total_count`. Texto adulterado é recusado.
- **Correspondência:** cartas da coleção sem nenhuma variante × cartas do snapshot, pelo número normalizado.
  Só pares 1 para 1; número repetido em qualquer lado fica de fora como ambíguo.
- **Staging:** uma linha por chave de preço (VALID / NEW / PENDING), já resolvida pelos 3 eixos. Carta
  casada sem chave não gera linha. `raw_data` guarda `ptcg_card_id`, `ptcg_number`, `ptcg_rarity` e o
  nome do snapshot. Sem rede, sem chave de API.
- **Recusa:** job ativo na coleção (também impede rodar duas vezes), rota que não resolve, plano vazio
  (nenhum job é criado).
- **Saída:** contagens, linhas por tipo e a checagem cruzada F4 (combinação de chaves por raridade nossa).
- `F3/stage_<set>.sql`: 49 scripts gerados a partir do snapshot, um por coleção, em DRY_RUN por padrão.
  A decisão e o confirm seguem pelo mesmo runner do NRR-CONFIRM (admin real como ator).

**Prova (2026-10-10, transação desfeita):** função criada e chamada com o arquivo `xy1.json`. DRY_RUN não
gravou nada; texto adulterado recusado (`F3_SNAPSHOT_HASH`); texto com CRLF aceito; APPLY criou o job STAGED
com 269 linhas, todas VALID/PENDING; segunda chamada recusada (`F3_ACTIVE_JOB`). Nada ficou no LIVE.

Plano do piloto **XY1**: 146 de 146 cartas casadas, 0 ambíguas, 0 órfãs, 0 sem chave → **269 linhas**
(STANDARD 116, REVERSE_HOLO 123, HOLO 30). Checagem cruzada: COMMON `normal+reverse` 39 e `normal` 9
(energias); UNCOMMON `normal+reverse` 42; RARE `normal+reverse` 26 e `holo+reverse` 16 (a distinção que
faltava em pt-BR); ULTRA_RARE `holofoil` 14. Nenhuma divergência da regra era × raridade.

### F5 — piloto XY1 (2026-10-10)

Executado por Fabrício. Leitura posterior: job `686f4ed4…` COMPLETED, 269 INSERTED, 0 FAILED;
`card_variant` 26.491 → **26.760**; 0 cartas da XY1 sem variante; 0 duplicidade de identidade;
cartas sem variante no catálogo 6.727 → **6.581**.

### F6 — campanha (2026-10-10)

**Execução direta pelo agente, a pedido de Fabrício** ("isso reduz bastante a possibilidade de eu rodar algo
errado"), via `execute_sql` no projeto `qjfutqujxrbzgrtkpgkg`. Os arquivos `F6/stage_*` continuam válidos
para reexecução manual, mas não foram usados.

- **Staging sem redigitar o snapshot.** Cada chamada leva as cartas num formato compacto
  (`número|raridade|chaves`) e um bloco DO reconstrói o texto JSON exato do arquivo do snapshot antes de
  chamar `internal.stage_pokemontcg_snapshot_set`. A função recusa qualquer texto cujo SHA-256 não bata com a
  referência gravada na F2-01, então a fidelidade da reconstrução fica provada pelo próprio servidor. O bloco
  também aborta (desfazendo a chamada inteira) se `rows_planned` ou `matched` divergirem do plano da F1.
- **Confirm:** o corpo de `F6/confirm_staged_ready.sql` com `v_apply = true`, uma vez por lote.
- **Ordem:** D (DC1, DET1, DV1, G1, SWSH1, SWSH3.5, SWSHP, SVP) → A (12 BW) → B (13 XY) → C (15 SM).

| Lote | Jobs | Linhas | `card_variant` depois |
|---|---:|---:|---:|
| Piloto XY1 | 1 | 269 | 26.760 |
| D | 8 | 1.088 | 27.848 |
| A | 12 | 2.539 | 30.387 |
| B | 13 | 2.687 | 33.074 |
| C | 15 | 4.229 | **37.303** |
| **Total** | **49** | **10.812** | |

**Leitura final (LIVE):** 49 jobs da 2ª fonte, todos COMPLETED; 10.812 linhas INSERTED, 0 em outro estado;
0 linhas FAILED no staging inteiro; 10.812 variantes distintas, 0 duplicidade carta × tipo; por tipo
STANDARD 3.969, REVERSE_HOLO 4.409, HOLO 2.434. Cartas sem variante: 6.727 → **330** (Trainer Kits 270,
CEL25CC 25, as 25 casadas sem chave de preço, SVP 7, ME5.5/MEP 3).

### F4 — checagem cruzada era × raridade (pós-campanha, só leitura)

Combinação de tipos por raridade nossa, nas 6.397 cartas que ganharam variante. Padrão esperado em quase
tudo: COMMON/UNCOMMON `STANDARD+REVERSE_HOLO` 3.049; RARE `STANDARD+REVERSE_HOLO` 817 e `HOLO+REVERSE_HOLO`
513; ULTRA/SECRET/SHINY/V/VMAX `HOLO` 1.157; PROMO `HOLO` 478. Fora do padrão, 102 cartas, todas explicadas:

| Caso | Cartas | Leitura |
|---|---:|---|
| BWP com raridade nossa COMMON/UNCOMMON/RARE | 58 | A fonte diz `Promo`; a raridade nossa é que está fora. Achado de catálogo (raridade), não de variante. |
| BW11 e G1 (Radiant Collection), DET1, DV1: comum/incomum só HOLO | 40 | Correto: essas cartas só existem holo. |
| XY12 109–113 `Rare Secret` só STANDARD | 5 | A fonte só tem preço `normal`. Fica registrado para revisão editorial. |

Nenhuma divergência pede desfazer variante.

### Fechamento (2026-10-10)

**Promoção canônica** (corpos das funções conferidos contra o LIVE: md5 do `prosrc` sem CR idêntico aos arquivos):

| Arquivo canônico | Origem | Conteúdo |
|---|---|---|
| `database/migrations/2246_second_variant_source_foundation.sql` | `F2-01` (com `v_apply = true`, forma executada) | CHECK de source, 49 refs, 3 rotas, guards `trg_cvir_second_source`/`trg_cvij_source_immutable`, cancelamento do job vazio da SM12. One-shot. |
| `database/schema/2247_create_stage_pokemontcg_snapshot_set_function.sql` | `F3-01` | `internal.stage_pokemontcg_snapshot_set` |

`F3/stage_<set>.sql`, `F5-01` e `F6/*` ficam aqui como registro de execução (operações de dado).

**UI:** `web/lib/catalogo/queries.ts` passou a traduzir a fonte `POKEMON_TCG_API` ("Pokémon TCG API", contexto
`SYSTEM`). A leitura de job ativo do seletor de Importar Variantes continua só TCGDEX, de propósito: os jobs
da 2ª fonte nascem e são confirmados no banco, nenhum fica ativo para retomar na tela. `tsc --noEmit` limpo.

**SVE:** o job TCGDEX `dcef3bd2` (reimportação de 04/10, preparada antes do Batch 13) foi confirmado por
Fabrício pela UI: 112 `UNCHANGED`, 0 inseridas. As 48 linhas que pareciam novas já existiam desde 12–15/09.

**Fica fora desta frente (achados registrados, sem dono ainda):**

| Achado | Cartas | Natureza |
|---|---:|---|
| Trainer Kits sem fonte | 270 | Sem variante; nenhuma das duas fontes cobre |
| CEL25CC | 25 | Sem variante por decisão (numeração `CC001`–`CC025` × número original) |
| Casadas sem chave de preço | 25 | XYP 7, SWSHP 4, as 10 XY abaixo, BWP 2, G1 2 |
| Numeração suspeita (XY2/4/6/7/9/10) | 10 | Carta com sufixo no lugar da base; defeito provável de importação do catálogo |
| SVP 191–226 | 7 | Números que a fonte não tem |
| ME5.5 / MEP | 3 | Frente própria (`CATALOG-ME5.5-IMPORT-01`) |
| BWP com raridade COMMON/UNCOMMON/RARE | 58 | Raridade do catálogo, não variante |
| XY12 109–113 secreta só STANDARD | 5 | Revisão editorial |

**Estado da frente:** carga concluída e fechada. `card_variant` 37.303; 330 cartas sem variante, todas listadas acima.

### Pontos que o desenho fecha

- **Precedência:** a fonte só grava em carta sem variante. O guard roda no servidor no staging e de
  novo no confirm, então uma corrida com o TCGdex não duplica nada.
- **Normalização de número:** maiúsculas e zeros à esquerda removidos por sequência de dígitos.
  Os formatos nossos (`001`, `XY01`, `SV1`, `SWSH001`, `CC001`, `RC9`) e os da fonte batem nessa forma
  canônica; a F1 prova isso por Set antes de qualquer escrita.
- **Fora do escopo:** Trainer Kits (sem fonte); ME5.5 tem frente própria, mas pode reaproveitar esta
  integração.
