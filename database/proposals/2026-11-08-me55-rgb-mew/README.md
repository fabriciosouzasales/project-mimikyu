# ME5.5 — três cartas Mew "RGB" (R, G, B) (2026-11-08)

| Campo | Valor |
|---|---|
| **Status** | **EXECUTADO (2026-11-08).** Dry-run PASS; decisões e gravação autorizadas por Fabrício ("Autorizo gravar assim"). ME5.5 com 161 cartas, todas com uma variante padrão. Cópia executada em `database/migrations/2277_add_me55_rgb_mew_cards.sql`. |
| **Mandato** | Fabrício, 2026-11-08: "Quero incluí-las em nosso catálogo" (as 3 cartas que a TCGdex lista além das 158 do ME5.5). |
| **Card Set** | ME5.5 "Celebração de 30 Anos" `3aa3fcf6-5826-4a13-b6a2-8f652a2b485a` |
| **Arquivo** | `2277_add_me55_rgb_mew_cards.sql` (mesmo rito da 2275: `admin_create_card` + `admin_create_card_variant`, dry-run por padrão, idempotente) |

## Fatos

- TCGdex `30th` (pt e en): 161 cartas = 001–158 + `30th-R`, `30th-G`, `30th-B` ("Mew", "RGB Rare", holográfica). A importação de 2026-10-10 trouxe 158 (a TCGdex ainda não listava as três). Os arquivos de imagem das três não existem na TCGdex (pt nem en).
- Scrydex `me55`: 161 cartas, incluindo `me55-R`, `me55-G`, `me55-B`, imagens 654 × 914.
- Catálogo: raridade `RGB_RARE` ("Rara RGB") já existe, com mapeamento "RGB Rare"/"Rara RGB", sem cartas. As 158 cartas do ME5.5 usam total 128 e variante Holográfica/Padrão com o contexto `CAMPAIGN_30TH_ANNIVERSARY`.
- **O fluxo normal de importação de cartas não traz as três:** o plano de ordem do Set recusa identificador só com letras (`supabase/functions/_shared/catalog-normalization/collector-order.ts`, `UnsupportedCollectorNumberError`). Consequência: **qualquer nova importação de cartas do ME5.5 falha por inteiro** enquanto a TCGdex listar R/G/B — o mesmo vale antes e depois desta proposta. Correção possível (fora deste escopo): uma exceção nomeada para o ME5.5, no padrão HGSS/EXU.

## Proposta

| Nº | Nome | Raridade | Categoria | Total | Ordem | Variante padrão |
|---|---|---|---|---|---|---|
| R | Mew | Rara RGB | Pokémon | 128 | 159 | Holográfica · Celebração de 30 Anos |
| G | Mew | Rara RGB | Pokémon | 128 | 160 | Holográfica · Celebração de 30 Anos |
| B | Mew | Rara RGB | Pokémon | 128 | 161 | Holográfica · Celebração de 30 Anos |

Decisões a confirmar: (1) número = a letra (como TCGdex e Scrydex); (2) ordem R, G, B depois da 158 (ordem do nome "RGB" e da Scrydex; a TCGdex lista B, G, R); (3) total 128, Holográfica e contexto dos 30 anos, como as demais cartas do ME5.5.

## Dry-run no LIVE (2026-11-08)

`DRY_RUN_OK cartas=3/0 variantes=3/0 total=161`; resíduo conferido: ME5.5 segue com 158 cartas, nenhum log novo no action log.

## Depois de gravar

- Imagens en: Scrydex `me55-R`, `me55-G`, `me55-B` (3 imagens) — pelo canal manual do Catálogo ou por uma Edge pontual no padrão `import-scrydex-assets-*`.
- Imagens pt: sem fonte hoje.

## Execução (CONFIRMADO EXECUTADO, 2026-11-08)

Gravado com `v_dry_run = false`: R (159), G (160), B (161) — Mew, Rara RGB, total 128, Holográfica · Celebração de 30 Anos. Postcheck: ME5.5 **161 | 161** com exatamente uma variante padrão; action log com 3 `CARD_CREATED` e 3 `CARD_VARIANT_CREATED`.

## Imagens en (EXECUTADO, 2026-11-08)

Edge pontual `supabase/functions/import-scrydex-assets-5` (cópia da v4, portão `SCRYDEX_ASSETS_2026_11_08_ME55_RGB`, plano com R, G, B → `me55-R/G/B`). Grava em `card-front/me5.5/en/<R|G|B>.png`, mesmo padrão de pasta das demais cartas do ME5.5.

1. Deploy (Fabrício): `supabase functions deploy import-scrydex-assets-5 --project-ref qjfutqujxrbzgrtkpgkg`
2. Portão (agente, com autorização) → probe (esperado 3 `DISPONIVEL`) → importação (1 lote).

Execução: deploy por Fabrício; portão aberto com autorização; probe **3/3 `DISPONIVEL`**; importação **3 `IMPORTADA`**, 0 falha; portão fechado sozinho. Postcheck: ME5.5 en **161/161**, pt-BR 158/161 (R/G/B sem fonte pt), 0 primário duplicado; arquivos `me5.5/en/{R,G,B}.png` (~1,6 MB cada).
