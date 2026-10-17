# MEP — cartas só na Scrydex (2026-10-17, `CATALOG-MEP-REFRESH-01` Etapa 2)

| Campo | Valor |
|---|---|
| **Status** | **EXECUTADO (2026-10-17).** Dry-run PASS, depois aplicado com autorização de Fabrício ("As 7 suposições estão certas e autorizo a execução"). MEP com 111 cartas, todas com uma variante padrão. Cópia executada em `database/migrations/2275_add_mep_scrydex_only_cards.sql`. |
| **Mandato** | Fabrício, 2026-10-17: "Siga para etapa 2" (plano: proposta, sem aplicar; "Pikachu at the Museum" fora). |
| **Card Set** | MEP "MEP Black Star Promos" `5c106d7c-c001-4f09-85c6-087c6ed0a925` |
| **Arquivo** | `2275_add_mep_scrydex_only_cards.sql` |

## Contexto

Depois da Etapa 1 o MEP tem 88 cartas (tudo o que a TCGdex publica). A Scrydex lista 112: 001–110, 120 e
"Pikachu at the Museum" (jumbo, sem número). As 23 cartas abaixo existem só na Scrydex. Os nomes e números de
001–088 batem com a Scrydex, o que dá confiança na fonte para o restante.

## Cartas e variantes propostas

| Nº | Nome no catálogo | Categoria | Variante padrão | Variantes extras | Fonte (Scrydex) |
|---|---|---|---|---|---|
| 089 | Mega Zeraora ex | Pokémon | Holográfica | — | holofoil |
| 090 | Mega Darkrai ex | Pokémon | Holográfica | — | holofoil |
| 091 | Mega Dragonite ex | Pokémon | Holográfica | — | holofoil |
| 092 | Resort Paraíso | Treinador | Holográfica · Mundial 2025 · Equipe | Holográfica · Mundial 2025 | worldChampionshipsStaffStamp, worldChampionshipsStamp |
| 093 | Pikachu | Pokémon | Holográfica · Campeão | Holográfica · Mundial 2025 | winnerStamp, worldChampionshipsStamp |
| 094–110 | Exeggutor de Alola, Lucario, Moltres, Articuno, Zapdos, Greninja ex, Sylveon ex, Nidorina, Victini, Zeraora, Mewtwo, Mew, Ditto, Pikachu ex, Espeon ex, Pikachu ex, Umbreon ex | Pokémon | Holográfica · Celebração de 30 Anos | 101: Holográfica · Pokémon Center | anniversaryStamp (101 também pokemonCenterStamp) |
| 120 | Fanfarra de Celebração | Treinador | Padrão (sem contexto) | — | aceTrainerStamp |

Todas com raridade Promo, total 88 (igual às 88 existentes) e ordem = número. **Atualização (2026-10-17):** o total de todas as 111 cartas e do Set passou a 111 pela migration `2276` (pedido de Fabrício).

## Decisões de mapeamento (confirmadas por Fabrício em 2026-10-17)

1. **Acabamento.** A Scrydex não diz o acabamento dos carimbos. Usei Holográfica, como as outras 80 cartas
   do MEP. Exceção: 120 em Padrão, igual à 028 (mesma carta, Fanfarra de Celebração).
2. **"Anniversary Stamp" → Celebração de 30 Anos** (`CAMPAIGN_30TH_ANNIVERSARY`). Alternativa existente:
   `CAMPAIGN_POKEMON_DAY_30TH` (30º Dia Pokémon).
3. **092/093 → Mundial 2025.** A Scrydex diz só "World Championships"; o ano 2025 é inferência pela data
   do MEP. O selo "Winner" do 093 virou `PLACEMENT_WINNER` sozinho (não existe "Mundial 2025 · Campeão").
4. **120 "Ace Trainer Stamp"** não tem contexto no catálogo. Criar um contexto novo é decisão separada;
   aqui a carta entra sem contexto.
5. **Total 88.** Total nulo aparece como "???" na interface; os Sets promo usam um total único.
6. **Nomes.** Em português quando o catálogo já usa o nome (Exeggutor de Alola, Resort Paraíso, Fanfarra de
   Celebração); os demais são iguais nas duas línguas.
7. **Fora:** "Pikachu at the Museum" (decisão de Fabrício) e a versão jumbo do 100 (jumbo é fora de escopo).

## Execução

Rodar o arquivo com `v_dry_run := false`, como administrador no SQL editor. Ele usa só
`admin_create_card` e `admin_create_card_variant` (validações e auditoria das próprias funções) e é
idempotente: reexecutar não duplica. Validação no próprio cabeçalho do arquivo (esperado 111 | 111).

Quando a TCGdex publicar estas cartas, a importação normal vai encontrá-las por número (CONFLICT/MATCHED),
sem duplicar.

## Imagens

Fora deste arquivo (Etapa 3): imagens EN da Scrydex (`images.scrydex.com/pokemon/mep-<n>/large`;
092 e 093 usam `mep-92wcs` e `mep-93ws`). Não há fonte pt.
