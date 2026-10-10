# CATALOG-VARIANT-COVERAGE-GAP-01 — Cartas sem Card Variant

| Campo | Valor |
|---|---|
| **Status** | Fonte decidida (ADR-034 v0.2, snapshot congelado). **Snapshot obtido** e **F1 (correspondência) concluída**, ambos sem escrita no LIVE (2026-10-09). Próximo: F2 (SQL). |
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
| **F2** | SQL: (a) CHECK de `catalog_variant_import_job.source` aceita `POKEMON_TCG_API`; (b) `card_set_external_reference` das 48 coleções casadas; (c) 3 mappings de Finish do asset_source (NORMAL/HOLOFOIL/REVERSEHOLOFOIL); (d) guard de servidor "carta sem variante" no staging e no confirm; (e) revalidação (2239/2245) restrita a jobs `TCGDEX`, porque hoje ela fixa o asset_source no código. | Sim (scripts, com dry-run) | Próximo |
| **F3** | Carregador do snapshot (no lugar da Edge com rede): lê `sets/<id>.json`, correlaciona por Set + número e grava uma linha de staging por chave de preço com `raw_data = {type: <chave>, foil: null, subtype: null, stamp: [], size: "standard", ptcg_card_id, ptcg_rarity}`. Mesmos guards de cobertura do import do TCGdex. Testes offline. | Sim (staging) | Pendente |
| **F4** | Checagem cruzada com a regra era × raridade (comum/incomum = STANDARD + REVERSE; ultra/secreta = HOLO). Divergências vão para revisão antes do confirm. | Não | Pendente |
| **F5** | Piloto em XY1 (146 cartas): stage → revisão → confirm → leitura. | Sim | Pendente |
| **F6** | Campanha nas demais coleções, em lotes. | Sim | Pendente |

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

### Pontos que o desenho fecha

- **Precedência:** a fonte só grava em carta sem variante. O guard roda no servidor no staging e de
  novo no confirm, então uma corrida com o TCGdex não duplica nada.
- **Normalização de número:** maiúsculas e zeros à esquerda removidos por sequência de dígitos.
  Os formatos nossos (`001`, `XY01`, `SV1`, `SWSH001`, `CC001`, `RC9`) e os da fonte batem nessa forma
  canônica; a F1 prova isso por Set antes de qualquer escrita.
- **Fora do escopo:** Trainer Kits (sem fonte); ME5.5 tem frente própria, mas pode reaproveitar esta
  integração.
