# ME5.5 Celebração de 30 Anos + Coleção Clássica (2026-10-10)

| Campo | Valor |
|---|---|
| **Status** | Em andamento: importador corrigido e deployado; Card Set ME5.5CC criado; falta reimportar as cartas pela UI |
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

## Próximos passos (pela UI, Fabrício)

1. ME5.5 → Importar Cartas (TCGdex). Esperado: ~158 linhas; 001/002 em pt, demais em en. Conferir NEEDS_REVIEW.
2. ME5.5CC → Importar Cartas. A localização automática não acha pelo código; na busca manual, procurar
   "Classic Collection" e escolher o Set de **30** cartas (`30th-c`), não o de 25 (CEL25CC).
3. Importar Imagens dos dois Sets.
4. Depois da confirmação: raridade da ME5.5CC passa de NONE para CLASSIC_COLLECTION (mesmo tratamento da CEL25CC).
5. Variantes: a TCGdex marca as cartas com carimbo `30th-anniversary`; decisão de contexto de edição pendente.
