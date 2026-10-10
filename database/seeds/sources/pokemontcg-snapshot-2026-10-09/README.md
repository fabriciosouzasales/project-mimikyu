# Snapshot Pokémon TCG API — 2026-10-09

| Campo | Valor |
|---|---|
| **Fonte** | Pokémon TCG API v2 (`api.pokemontcg.io`), endpoint público, sem chave |
| **Data** | 2026-10-09 |
| **Decisão** | ADR-034 v0.2 (fonte congelada) |
| **Uso** | Segunda fonte de Card Variants para cartas sem nenhuma variante (`CATALOG-VARIANT-COVERAGE-GAP-01`) |
| **Conteúdo** | 50 coleções, 6.733 cartas (`manifest.json`) |

## Regras

- **Imutável.** Nada aqui é editado depois do commit. Uma correção gera outro snapshot, com outra data.
- **Completo por coleção.** Uma coleção só entrou se o número de cartas baixadas é igual ao `totalCount`
  informado pela fonte.
- **Campos guardados:** `id`, `number`, `rarity` (texto original em inglês; `null` quando a fonte não
  informa) e as chaves de `tcgplayer.prices` em ordem alfabética (`tcgplayer_price_keys`). Os valores de
  preço foram descartados: o sinal usado é a existência da chave, não o preço.
- `tcgplayer_price_keys` vazio quer dizer que a fonte não tem preço para a carta. Pelo ADR-034, essas
  cartas não ganham variante padrão.

## Como foi obtido

`GET /v2/cards?q=set.id:<set_id>&orderBy=number&select=id,number,rarity,tcgplayer`, paginado, com novas
tentativas por coleção (a API respondeu 500/502 com frequência). A transferência para o repositório foi
conferida por coleção: o SHA-256 de uma forma canônica em texto, calculado no navegador sobre a resposta,
bate com o mesmo cálculo feito sobre o arquivo gravado (`transfer_check_sha256` no manifest). O
`sha256` do manifest é o do arquivo `sets/<set_id>.json`.

## Coleções

bw1–bw11, bwp, xy0–xy12, xyp, sm1, sm2, sm4–sm12, sm115, sm35, sm75, sma, det1, dc1, dv1, g1, cel25c,
swsh1, swsh35, swshp, svp. Os Trainer Kits não existem na fonte.
