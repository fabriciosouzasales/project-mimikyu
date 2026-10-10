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

## Pendências

1. **Nomes em português.** A TCGdex só tem 001 e 002 traduzidas; as demais 156 + 30 ficaram em inglês.
   Quando a TCGdex publicar a tradução, uma nova importação traz os nomes como CONFLICT para aprovar.
2. **Imagens.** Importar Imagens dos dois Sets (ME5.5CC não tinha cartas, por isso falhou antes). Em pt-BR não
   haverá imagem; a continuação automática em `en` cobre.
3. **Mew RGB (3 cartas).** A API da TCGdex ainda não serve; entram numa importação futura.
4. **Pokédex.** A TCGdex ainda não publica `dexId` para `30th`/`30th-c`; Primary Species = 0. Reprocessar depois.
5. **Variantes.** Carimbo `30th-anniversary`; decisão de contexto de edição pendente.
