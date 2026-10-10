# ME5.5 Celebração de 30 Anos + Coleção Clássica (2026-10-10)

| Campo | Valor |
|---|---|
| **Status** | Cartas completas (ME5.5 158, ME5.5CC 30); pendentes imagens, nomes pt, Mew RGB, Pokédex e variantes |
| **Mandato** | Fabrício, 2026-10-10: "Vamos em frente com esse plano!" |
| **Card Sets** | ME5.5 `3aa3fcf6-5826-4a13-b6a2-8f652a2b485a` (TCGdex `30th`); ME5.5CC `21add268-7159-4b22-9b67-d9699a7a99f0` (TCGdex `30th-c`) |

## Diagnóstico

- A TCGdex tem só 2 cartas traduzidas para `pt` no Set `30th` (001 e 002); em `en` estão as 158 (mais os
  3 Mew RGB, commit #2370 do repositório `tcgdex/cards-database`, 20/09).
- O importador só trocava para `en` quando a lista `pt` vinha **vazia**. Com 2 cartas, aceitava a lista
  curta: 10 importações seguidas trouxeram as mesmas 2 cartas.
- A Coleção Clássica (30 cartas) é um Set separado na TCGdex, `30th-c`, raridade `None`, todas holo com o
  carimbo de 30 anos. Mesmo formato do precedente CEL25 / CEL25CC.

## Feito

| Passo | Resultado |
|---|---|
| Raridades | `RGB_RARE` ("Rara RGB", ordem 29, símbolo GOLD_STAR) + 7 mapeamentos `en` (Double Rare, Illustration Rare, Special Illustration Rare, Hyper Rare, Mega Hyper Rare, RGB Rare, Rara RGB). `None` já mapeia para NONE. |
| Importador | `import-catalog-cards` Versão 7, deployada (v24): se a lista `pt` tem menos cartas que a oficial, a lista `en` vira o conjunto e cada carta vem em `pt` quando existe lá, em `en` quando não. |
| Card Set | `ME5.5CC` "Celebração de 30 Anos Coleção Clássica", SPECIAL, ordem 10, 30 cartas, 16/09/2026, via `admin_create_card_set`. |

## Importação (Fabrício, 2026-10-10) e recuperação (2252)

| Job | Resultado da UI | Causa | Correção |
|---|---|---|---|
| ME5.5 `cfe7b926` | 124 inseridas, 2 inalteradas, 32 FAILED | Raridades `Pikachu Rare` (023–052) e `Futuristic Rare` (157–158) sem mapeamento | `PIKACHU_RARE` "Rara Pikachu" e `FUTURISTIC_RARE` "Rara Futurista" + mapeamentos; 32 cartas criadas |
| ME5.5CC `9c54c1d9` | 30 FAILED (`ck_card_collector_total_positive`) | TCGdex devolve `cardCount.official = 0` para `30th-c` | Importador Versão 7.1 (deploy v25); 30 cartas criadas com total 30 e raridade CLASSIC_COLLECTION |

Script: `database/migrations/2252_recover_me55_failed_rows.sql` (dry-run PASS, depois aplicado).
Resultado: ME5.5 **158** cartas (1..158), ME5.5CC **30** cartas (1..30), os 2 jobs COMPLETED.

## Imagens das Coleções Clássicas (ME5.5CC + CEL25CC, 2026-10-10)

A TCGdex não publica imagem para `30th-c` nem `cel25cc` (0 de 55, em qualquer idioma; testados 17 caminhos
alternativos no servidor de assets). O pokemontcg.io publica as duas em subconjuntos que mantêm o número da
carta ORIGINAL homenageada: `me55c-4` (Charizard), `me55c-106p` (Palkia LV.X), `cel25c-15_A4` (Claydol).
A correspondência com os nossos 001–030 / CC001–CC025 foi conferida carta a carta pelo nome.

Importação pontual aprovada por Fabrício ("Importação pontual das 30. Veja se isso se aplica também para a
classic collection de 25 anos"): Edge Function `import-classic-collection-assets` (sem entrada do chamador,
mapa fixo, portão `oneshot_operation_gate` consumido antes de agir, migration 2253).

| Set | Imagens | Fonte | Caminho | Tamanho |
|---|---|---|---|---|
| ME5.5CC | 30/30 | `images.scrydex.com/pokemon/me55c-<n>/large` | `card-front/me5.5cc/en/001.png` | 596 KB – 1,5 MB, 654×914 |
| CEL25CC | 25/25 | `images.pokemontcg.io/cel25c/<n>_hires.png` | `card-front/cel25cc/en/CC001.png` | 330 – 905 KB |

Cada carta ganhou `card_asset` (CARD_FRONT, en, `source_code` POKEMON_TCG_API, checksum SHA-256) e
`card_external_reference` (asset_source POKEMON_TCG_API, `image_source_url` = URL de origem). Conferência
visual: Charizard e Palkia (ME5.5CC) e Blastoise (CEL25CC) corretos, com carimbo comemorativo.

**Português:** nenhuma fonte publica estas cartas em pt (TCGdex `pt/cel25cc` tem 0 cartas; pokemontcg é só en).
Nada foi gravado como pt-BR para não rotular imagem inglesa como portuguesa.

## Pendências

1. **Nomes em português.** A TCGdex só tem 001 e 002 traduzidas; as demais 156 + 30 ficaram em inglês.
   Quando a TCGdex publicar a tradução, uma nova importação traz os nomes como CONFLICT para aprovar.
2. **Imagens.** Resolvido: ME5.5 158/158 (TCGdex), ME5.5CC 30/30 e CEL25CC 25/25 (pokemontcg, acima).
3. **Mew RGB (3 cartas).** A API da TCGdex ainda não serve; entram numa importação futura.
4. **Pokédex.** Resolvido por `database/migrations/2254_resolve_primary_species_me55_classic.sql` (dry-run
   PASS, 180 cartas): ME5.5 155/155 e ME5.5CC 25/28 com Primary Species, via `admin_resolve_card_primary_species`
   (basis EDITORIAL_RECONCILIATION, evidência pokemontcg.io + repositório TCGdex, gates de nome e cobertura).
   Ficam sem espécie, pela regra de dexId múltiplo: ME5.5CC 008 Pikachu & Zekrom GX [25, 644] e 019/020
   Darkrai & Cresselia LEGEND [491, 488] — mesmo estado das cartas originais em SM9/SMP/HGSS4.
5. **Variantes.** Carimbo `30th-anniversary`; decisão de contexto de edição pendente.
