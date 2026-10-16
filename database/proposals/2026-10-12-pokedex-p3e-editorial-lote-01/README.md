# Pokédex P3e — Expansão Editorial pt-BR · Lote 01 (planejamento)

> **Nota de estado (2026-10-15, `DOC-GATE-01` Correction-01).** As menções a "aguarda homologação" abaixo (Status e "Próximo passo") estão **superadas**; o texto original foi preservado. Estado comprovado:
> 1. **Aprovação editorial:** 50/50 espécies APROVADO (JSON revisão 11; `docs/log.md`, 2026-10-13).
> 2. **Publicação:** Query 6137 CONFIRMADO EXECUTADO no LIVE, 6848 PASS, commit `54da0a2` (2026-10-13).
> 3. **Homologação:** registrada pelo ADR-011 v1.5 ("após a publicação e homologação da P3e — Lote 01 (commit `54da0a2`)"; "os lotes P3d e P3e não são reabertos").
> 4. **Pendências posteriores:** nenhuma específica do Lote 01. Os lotes seguintes pertencem à Frente B editorial (ADR-011 v1.5) e não fazem parte desta proposta.


| Campo | Valor |
|-------|-------|
| **Status** | Lote 01 **APROVADO e PUBLICADO** no LIVE (2026-10-13): Query 6137 **CONFIRMADO EXECUTADO** (publicação de dados, sem ledger) e promovida para `database/seeds/6137_publish_pokedex_editorial_ptbr_lote_01.sql`; 6848 = **PASS**. Aguarda homologação na aplicação para encerrar o Lote 01. |
| **Data** | 2026-10-12 |
| **Base** | P3d encerrada (piloto de 10 espécies publicado, 6847 PASS, commit `a888b2c`). Guia editorial v0.2 — `database/proposals/2026-10-12-pokedex-p3d-editorial-ptbr/README.md` §1. |
| **Escopo** | 50 espécies novas (100 textos: GENUS + FLAVOR), sem repetir o piloto (#1, 25, 150, 201, 493, 649, 721, 905, 906, 1025). |

## 1. Seleção proposta (50)

| Ger. | Nº | Espécie | Tipos | Status | Justificativa curta |
|---|---|---|---|---|---|
| 1 | 4 | Charmander | Fogo | — | Inicial clássico; chama da cauda é gancho forte |
| 1 | 6 | Charizard | Fogo/Voador | — | Ícone de colecionadores de TCG |
| 1 | 7 | Squirtle | Água | — | Inicial clássico, alta familiaridade no Brasil |
| 1 | 39 | Jigglypuff | Normal/Fada | — | Ícone da franquia; canto como traço central |
| 1 | 52 | Meowth | Normal | — | Personagem muito reconhecido; moeda na testa |
| 1 | 54 | Psyduck | Água | — | Reconhecimento alto; relato de pesquisa |
| 1 | 94 | Gengar | Fantasma/Veneno | — | Fantasma clássico; folclore de sombras |
| 1 | 133 | Eevee | Normal | — | Ponto de partida das evoluções múltiplas |
| 1 | 143 | Snorlax | Normal | — | Ícone; relato regional (Hisui) |
| 1 | 151 | Mew | Psíquico | Mítico | Par natural com Mewtwo (piloto) |
| 2 | 155 | Cyndaquil | Fogo | — | Inicial de Johto, também em Hisui |
| 2 | 175 | Togepi | Fada | Bebê | Única espécie bebê do lote |
| 2 | 197 | Umbreon | Sombrio | — | Muito valorizado no TCG; evolução de Eevee |
| 2 | 212 | Scizor | Inseto/Aço | — | Combinação de tipos marcante |
| 2 | 248 | Tyranitar | Pedra/Sombrio | — | Pseudolendário clássico |
| 2 | 249 | Lugia | Psíquico/Voador | Lendário | Lendário central de Johto |
| 3 | 257 | Blaziken | Fogo/Lutador | — | Inicial final popular |
| 3 | 282 | Gardevoir | Psíquico/Fada | — | Recorrente no TCG competitivo |
| 3 | 359 | Absol | Sombrio | — | Mal-entendido "arauto da desgraça" |
| 3 | 382 | Kyogre | Água | Lendário | Mitologia do mar (Hoenn) |
| 3 | 384 | Rayquaza | Dragão/Voador | Lendário | Lendário de Hoenn muito reconhecido |
| 3 | 385 | Jirachi | Aço/Psíquico | Mítico | Crença dos desejos |
| 4 | 393 | Piplup | Água | — | Inicial de Sinnoh; temperamento |
| 4 | 405 | Luxray | Elétrico | — | Único Elétrico do lote |
| 4 | 445 | Garchomp | Dragão/Terrestre | — | Pseudolendário de Sinnoh |
| 4 | 448 | Lucario | Lutador/Aço | — | Aura; muito popular |
| 4 | 483 | Dialga | Aço/Dragão | Lendário | Mitologia de Hisui, par com Arceus (piloto) |
| 4 | 491 | Darkrai | Sombrio | Mítico | Relato de pesadelos |
| 5 | 494 | Victini | Psíquico/Fogo | Mítico | Mítico de Unova |
| 5 | 495 | Snivy | Planta | — | Inicial de Unova; fotossíntese |
| 5 | 530 | Excadrill | Terrestre/Aço | — | Cobre Terrestre; "Rei da Broca" |
| 5 | 609 | Chandelure | Fantasma/Fogo | — | Folclore sombrio, bem enquadrável |
| 5 | 643 | Reshiram | Dragão/Fogo | Lendário | Mitologia de verdade × ganância |
| 6 | 658 | Greninja | Água/Sombrio | — | Muito popular no Brasil |
| 6 | 681 | Aegislash | Aço/Fantasma | — | Relato histórico de reino |
| 6 | 700 | Sylveon | Fada | — | Eeveelution de Kalos |
| 6 | 701 | Hawlucha | Lutador/Voador | — | Luta-livre; texto com personalidade |
| 6 | 716 | Xerneas | Fada | Lendário | Lendário de Kalos |
| 7 | 722 | Rowlet | Planta/Voador | — | Inicial de Alola |
| 7 | 745 | Lycanroc | Pedra | — | Cobre Pedra; caçador |
| 7 | 778 | Mimikyu | Fantasma/Fada | — | Espécie-símbolo do projeto MMKYU |
| 7 | 791 | Solgaleo | Psíquico/Aço | Lendário | Lendário de Alola |
| 8 | 823 | Corviknight | Voador/Aço | — | "Táxi aéreo" de Galar |
| 8 | 873 | Frosmoth | Gelo/Inseto | — | Cobre Gelo e Inseto |
| 8 | 887 | Dragapult | Dragão/Fantasma | — | Relação com Dreepy |
| 8 | 888 | Zacian | Fada | Lendário | Lendário de Galar |
| 9 | 908 | Meowscarada | Planta/Sombrio | — | Evolução final de Sprigatito (piloto) |
| 9 | 959 | Tinkaton | Fada/Aço | — | Martelo como traço central |
| 9 | 998 | Baxcalibur | Dragão/Gelo | — | Pseudolendário de Paldea; cobre Gelo |
| 9 | 1000 | Gholdengo | Aço/Fantasma | — | Corpo de moedas; ligado a colecionismo |

**Distribuição.** Gerações 10 · 6 · 6 · 6 · 5 · 5 · 4 · 4 · 4. Status: 37 convencionais, 8 lendários, 4 míticos, 1 bebê. Os 18 tipos aparecem ao menos uma vez. Pontos de concentração: Aço (10) e Fogo (7). Elétrico e Veneno aparecem só uma vez cada.

**Critério.** O reconhecimento entre colecionadores brasileiros é avaliação qualitativa: o projeto não tem dados de popularidade ou procura. A seleção também usa pares com o piloto (Mew–Mewtwo, Dialga–Arceus, Meowscarada–Sprigatito).

**Substituições durante o diagnóstico.**
- **Zoroark (#571):** substituído por Excadrill, porque a descrição armazenada (Legends: Arceus) descreve a forma de Hisui e não a forma padrão.
- **Scorbunny, Fuecoco, Talonflame:** substituídos por Frosmoth, Baxcalibur e Hawlucha, para reduzir o excesso de Fogo e cobrir Gelo e Lutador.

## 2. Diagnóstico factual (LIVE, só leitura, 2026-10-12)

- **Perfil:** as 50 espécies estão ativas, com perfil `IMPORTED`.
- **Textos oficiais:** cada uma tem exatamente 1 GENUS e 1 FLAVOR `SOURCE` em `en`, com `rights_status` THIRD_PARTY_UNLICENSED.
- **Editorial existente:** nenhuma tem editorial. O LIVE segue com 20 linhas `MMKYU_EDITORIAL`, todas do piloto.
- **Versões das descrições:** shield 21, legends-arceus 17, alpha-sapphire 7, violet 4, lets-go-eevee 1.
- **Limitação estrutural:** a chave `uq_pokemon_species_text` permite uma única descrição oficial por espécie e idioma. A base factual de cada texto é, portanto, uma descrição oficial de 88 a 193 caracteres, mais classificação, tipos e status.

**Pontos de atenção:**

| Categoria | Espécies | Tratamento proposto |
|---|---|---|
| Base factual curta | 151 Mew, 716 Xerneas (e, em menor grau, 7, 359) | Texto mais curto, aceito pelo guia |
| Voz de pesquisador em 1ª pessoa (Legends: Arceus) | 54, 133, 448 (445 com exclamação) | Converter em relato atribuído ("um pesquisador de Hisui…") |
| Contexto regional de Hisui | 94, 143, 155, 175, 393, 483, 491 | Enquadrar como relato ou mitologia de Hisui |
| Forma regional citada | 52 (Meowth de Galar) | Omitir ou citar como "a forma de Galar" |
| Unidades imperiais | 6 (pés), 257 (andares), 530 (mph), 959 (libras) | Converter para métrico, arredondado, com "cerca de" |
| Temas sombrios | 778, 609, 94, 491, 643 | Tom sóbrio, sempre como relato ou lenda |
| Mecânica de jogo | 384 (Mega Evolução), 212 ("item curioso"), 133 | Glossário; sem nomear item não citado na base |
| Afirmações absolutas na fonte | 197, 248, 282, 385, 405 | Atenuar ou enquadrar ("diz-se", "segundo as lendas") |
| Outra espécie citada | 887 (Dreepy), 888 (Zamazenta), 52 | Manter só como relação citada na base |
| Classificações difíceis | 791 "Sunne", 530 "Subterrene", 1000 "Coin Entity", 700 "Intertwining", 405 "Gleam Eyes", 701 "Wrestling", 52 "Scratch Cat" | Glossário com alternativas; terminologia oficial pendente, como no piloto |

## 3. Método de produção (reaproveita a P3d)

1. **Arquivo do lote:** `lote-01-pt-BR.json`, no mesmo esquema do piloto. Acréscimos:
   - `generation`;
   - `source_basis` (versão e md5 da descrição oficial usada, para detectar mudança da fonte);
   - `flags` (categorias da tabela acima).
2. **Redação em 5 blocos de 10.** Cada entrada sai como `PROPOSTO`, com `facts` e `editorial_interpretation` preenchidos. Fabrício aprova bloco a bloco; reprovação volta com nota.
3. **Validador offline** (`scripts/`, Deno, sem dependência nova). Verifica:
   - esquema e contagens;
   - nenhuma sobreposição com lotes já publicados;
   - md5 de cada texto;
   - limites de tamanho;
   - padrões proibidos: "você", exclamação, 1ª pessoa, "único", "o mais", unidades imperiais;
   - termos do glossário;
   - `source_basis` igual ao LIVE.
4. **Seed gerada a partir do JSON** (Query 6137 + validação 6848, numeração livre confirmada). Mesmo desenho da 6136: transação única, idempotente, `SOURCE` intocado, editoriais de outras espécies intocados. A validação é cumulativa: piloto preservado pelo hash `6c1653539c8abbb5ed06c1a4159e294b` e total esperado de 120 linhas.
5. **Ensaio com rollback** → publicação → validação → promoção para `database/seeds/` → homologação por amostra no navegador.

Sem tabela, função, interface administrativa ou dependência nova.

## 4. Decisões aprovadas (2026-10-12)

- Seleção exata das 50 espécies, com Excadrill no lugar de Zoroark.
- Base factual exclusiva: descrição e classificação oficiais armazenadas + dados estruturados; sem outras fontes nesta etapa.
- Guia editorial v0.2. Sistema métrico só quando a medida é relevante, arredondado com "cerca de".
- Mitologia e relatos com atribuição, sem transformar fatos em lendas; temas sombrios com sobriedade.
- Classificações naturais em pt-BR, com ambiguidades e alternativas registradas (`genus_alternative`, `genus_terminology_check`).
- Revisão em 5 blocos de 10; publicação única após aprovação integral do lote.

## 5. Arquivos do lote

| Arquivo | Papel |
|---|---|
| `lote-01-pt-BR.json` | Lote editorial: seleção, blocos, glossário do lote e entradas redigidas (estado, textos, fatos, interpretações, `source_basis`, md5). |
| `source-snapshot.sql` | Consulta **só de leitura** que congela versão e md5 das fontes oficiais e confirma 0 editorial. |
| `source-snapshot-2026-10-12.json` | Resultado da consulta acima no LIVE (50 espécies, 0 editorial). |
| `scripts/editorial/validate-editorial-lot.ts` (+ `.test.ts`) | Validador offline, sem dependências (Deno ou Node 22+). |

**Validar o lote** (a cada revisão; com `--require-approved` antes de gerar a 6137):

```
node --experimental-strip-types scripts/editorial/validate-editorial-lot.ts \
  --lot database/proposals/2026-10-12-pokedex-p3e-editorial-lote-01/lote-01-pt-BR.json \
  --published database/proposals/2026-10-12-pokedex-p3d-editorial-ptbr/pilot-pt-BR.json \
  --snapshot database/proposals/2026-10-12-pokedex-p3e-editorial-lote-01/source-snapshot-2026-10-12.json
```

O validador confere formato, quantidade, unicidade, estados, md5 e tamanhos declarados, conflito com espécies publicadas, padrões proibidos do guia (2ª e 1ª pessoa, exclamação, unidades imperiais, "oficial/tradução"), termos a evitar do glossário e mudança da fonte oficial. Superlativos, absolutos e tamanho fora da faixa viram avisos para revisão humana. Ele **não** avalia precisão factual, originalidade nem qualidade narrativa.

## 6. Bloco 1/5 — APROVADO (2026-10-12)

| Nº | Espécie | Classificação (aprovada) | Descrição | Caracteres |
|---|---|---|---|---|
| 4 | Charmander | Pokémon Lagarto | APROVADO | 235 |
| 6 | Charizard | Pokémon Chama | APROVADO | 160 |
| 7 | Squirtle | Pokémon Tartaruguinha | APROVADO | 167 |
| 39 | Jigglypuff | Pokémon Balão | APROVADO | 155 |
| 52 | Meowth | Pokémon Gato-Arranhador | APROVADO (rev. 2) | 161 |
| 54 | Psyduck | Pokémon Pato | APROVADO | 219 |
| 94 | Gengar | Pokémon Sombra | APROVADO (rev. 2) | 233 |
| 133 | Eevee | Pokémon Evolução | APROVADO (rev. 2) | 218 |
| 143 | Snorlax | Pokémon Dorminhoco | APROVADO (rev. 2) | 183 |
| 151 | Mew | Pokémon Nova Espécie | APROVADO | 119 |

Todas as classificações seguem com conferência terminológica brasileira pendente. Validador: OK, 1 aviso (Mew, curto por decisão aprovada); 13/13 testes PASS.

**Regras confirmadas na aprovação do Bloco 1** (registradas em `editorial_rules` no JSON):
- descrições curtas são aceitas quando a fonte é insuficiente;
- "um pesquisador de Hisui" só quando o relato original tiver fundamento explícito em primeira pessoa, nunca como fórmula;
- medidas só quando acrescentam valor; conversão de Charizard (cerca de 1.400 metros) aprovada;
- guia v0.2 e glossário do lote preservados.

## 7. Bloco 2/5 — APROVADO (2026-10-12)

| Nº | Espécie | Classificação | Descrição | Caracteres |
|---|---|---|---|---|
| 155 | Cyndaquil | Pokémon Rato de Fogo · escolhida | APROVADO | 130 |
| 175 | Togepi | Pokémon Bola de Espinhos · escolhida | APROVADO | 185 |
| 197 | Umbreon | Pokémon Luar · escolhida | APROVADO | 185 |
| 212 | Scizor | Pokémon Pinça · mantida | APROVADO (rev. 2) | 104 |
| 248 | Tyranitar | Pokémon Armadura · mantida | APROVADO (rev. 2) | 156 |
| 249 | Lugia | Pokémon Mergulhador · escolhida | APROVADO | 155 |
| 257 | Blaziken | Pokémon Labareda · mantida | APROVADO | 175 |
| 282 | Gardevoir | Pokémon Abraço · escolhida | APROVADO (rev. 2) | 145 |
| 359 | Absol | Pokémon Desastre · mantida | APROVADO | 141 |
| 382 | Kyogre | Pokémon Bacia Oceânica · escolhida | APROVADO | 173 |

Conferência com a terminologia oficial brasileira: pendência editorial registrada, **não bloqueante**. Glossário: "master" → "Treinador" confirmado **apenas** quando se refere à pessoa responsável pelo Pokémon (Master Ball e outros sentidos não são substituídos). Validador: OK, 2 avisos esperados (Mew e Scizor curtos por base factual limitada); 13/13 testes PASS.

Avisos de tamanho de Mew (#151) e Scizor (#212) aceitos por Fabrício e registrados em `accepted_warnings` no JSON. Tyranitar: "podem abalar" aprovado como atenuação editorial.

## 8. Bloco 3/5 — APROVADO (2026-10-12)

| Nº | Espécie | Classificação | Descrição | Caracteres |
|---|---|---|---|---|
| 384 | Rayquaza | Pokémon Alto Céu · escolhida | APROVADO (rev. 2) | 156 |
| 385 | Jirachi | Pokémon Desejo | APROVADO | 129 |
| 393 | Piplup | Pokémon Pinguim | APROVADO | 162 |
| 405 | Luxray | Pokémon Olhos Brilhantes · escolhida | APROVADO (rev. 2) | 168 |
| 445 | Garchomp | Pokémon Mach · escolhida | APROVADO | 125 |
| 448 | Lucario | Pokémon Aura | APROVADO | 197 |
| 483 | Dialga | Pokémon Temporal · escolhida | APROVADO | 156 |
| 491 | Darkrai | Pokémon Breu · escolhida | APROVADO | 156 |
| 494 | Victini | Pokémon Vitória | APROVADO | 129 |
| 495 | Snivy | Pokémon Cobra-Planta · escolhida | APROVADO | 175 |

Decisões registradas: Darkrai mantém "todos os moradores" (episódio delimitado, sustentado pela fonte); Lucario mantém "um pesquisador de Hisui" (primeira pessoa no original); "Mega Evolução" é termo provisório do glossário. Classificações sujeitas à conferência terminológica brasileira antes de exploração comercial. Validador: OK, 3 avisos esperados (Mew e Scizor de tamanho, aceitos; Darkrai "todos", aceito); 13/13 testes PASS.

## 9. Bloco 4/5 — APROVADO (2026-10-13)

| Nº | Espécie | Classificação | Descrição | Caracteres |
|---|---|---|---|---|
| 530 | Excadrill | Pokémon Subterrâneo | APROVADO | 103 |
| 609 | Chandelure | Pokémon Chamariz · escolhida | APROVADO (rev. 2) | 112 |
| 643 | Reshiram | Pokémon Branco Imenso · escolhida | APROVADO (rev. 2) | 160 |
| 658 | Greninja | Pokémon Ninja | APROVADO | 166 |
| 681 | Aegislash | Pokémon Espada Real | APROVADO | 180 |
| 700 | Sylveon | Pokémon Enlace · escolhida | APROVADO | 177 |
| 701 | Hawlucha | Pokémon Luta-Livre | APROVADO | 146 |
| 716 | Xerneas | Pokémon Vida | APROVADO | 118 |
| 722 | Rowlet | Pokémon Pena-Planta · escolhida | APROVADO | 127 |
| 745 | Lycanroc | Pokémon Lobo | APROVADO | 136 |

Decisões registradas: Excadrill "acima de 140 km/h" e "Rei da Broca" aprovados; "shuriken" aprovado no glossário; textos curtos de Excadrill e Xerneas aceitos. Avisos aceitos (`accepted_warnings`): Mew, Scizor, Darkrai, Excadrill, Xerneas, Chandelure. Conferência terminológica brasileira pendente. 13/13 testes PASS.

## 10. Bloco 5/5 — APROVADO (2026-10-13)

| Nº | Espécie | Classificação | Descrição | Caracteres |
|---|---|---|---|---|
| 778 | Mimikyu | Pokémon Disfarce | APROVADO (rev. 2) | 216 |
| 791 | Solgaleo | Pokémon Sol · escolhida | APROVADO | 132 |
| 823 | Corviknight | Pokémon Corvo | APROVADO | 138 |
| 873 | Frosmoth | Pokémon Mariposa de Gelo · escolhida | APROVADO (rev. 2) | 146 |
| 887 | Dragapult | Pokémon Furtivo · escolhida | APROVADO | 137 |
| 888 | Zacian | Pokémon Guerreiro | APROVADO | 154 |
| 908 | Meowscarada | Pokémon Ilusionista · escolhida | APROVADO | 184 |
| 959 | Tinkaton | Pokémon Martelo | APROVADO | 167 |
| 998 | Baxcalibur | Pokémon Dragão de Gelo · escolhida | APROVADO | 130 |
| 1000 | Gholdengo | Pokémon Ser de Moedas · escolhida | APROVADO | 181 |

Decisões registradas: Tinkaton "cerca de 100 kg" aprovado; epíteto "a Fera que Devora o Sol" aprovado provisoriamente; "velocidade supersônica" aprovado no glossário. Gholdengo e Frosmoth tiveram apenas a classificação trocada para a alternativa escolhida (md5 da classificação recalculado; descrição de Gholdengo inalterada). Avisos aceitos: Mew, Scizor, Darkrai, Excadrill, Chandelure, Xerneas. Conferência terminológica brasileira pendente. 13/13 testes PASS.

## 11. Publicação do Lote 01 (Query 6137 + validação 6848) — EXECUTADA

**Geração determinística.** Os dois SQL são gerados por `scripts/editorial/generate-editorial-lot-sql.ts` a partir do JSON aprovado — não são editados à mão:

```
node --experimental-strip-types scripts/editorial/generate-editorial-lot-sql.ts \
  --lot database/proposals/2026-10-12-pokedex-p3e-editorial-lote-01/lote-01-pt-BR.json \
  --published database/proposals/2026-10-12-pokedex-p3d-editorial-ptbr/pilot-pt-BR.json \
  --snapshot database/proposals/2026-10-12-pokedex-p3e-editorial-lote-01/source-snapshot-2026-10-12.json \
  --seed-query 6137 --validation-query 6848 \
  --out-dir database/proposals/2026-10-12-pokedex-p3e-editorial-lote-01 --tag p3e_lote_01
```

- O gerador só escreve se o lote passar no validador com `--require-approved`.
- Saída sem data/hora; o cabeçalho registra o sha256 dos JSON de entrada.
- Duas gerações consecutivas produziram bytes idênticos.

| Arquivo | sha256 |
|---|---|
| `lote-01-pt-BR.json` (revisão 11) | `73ab17d3fbb634b504e86854450cf0f89ccfa0fe32d67c6d7913d8f49fddf001` |
| `6137_publish_pokedex_editorial_ptbr_lote_01.sql` | `6032b2672d3e4f46d1df35c6a2acb7561cdc827267435106e5a286e0b3aac4b8` |
| `6848_validate_pokedex_editorial_ptbr_lote_01.sql` | `6c09e36ba14b8c66d18816a7c906fa8011835e18de1e6008f9c4f4b688e1c131` |
| `pilot-pt-BR.json` (P3d, preservado) | `4d2edea2f7848abb5193f6a27e8ba205eda4921dab9362049dfcac9fa5045115` |

**Integridade conferida offline.** 100 linhas de payload (50 espécies) com texto e md5 idênticos ao JSON; 6848 com os 100 md5 do lote e os 20 md5 do piloto iguais aos versionados.

**6137 (escrita, transação única, idempotente).**
- Payload: 100 textos; md5 de cada texto conferido no próprio SQL contra o aprovado; nenhuma espécie do piloto; 1–2000 caracteres.
- Pré-condições: 50 espécies ativas, perfil IMPORTED, GENUS + FLAVOR SOURCE en; SOURCE = 2.050 linhas com hash `ca8e9c87244160063971bd1a9f808b78`; editorial fora do lote = exatamente os 20 registros do piloto, com os md5 versionados.
- Escrita: `INSERT … ON CONFLICT ON CONSTRAINT uq_pokemon_species_text DO UPDATE` só para `MMKYU_EDITORIAL` pt-BR; só atualiza se o conteúdo mudou.
- Pós-condições na mesma transação: 100 linhas do lote com conteúdo exato e proveniência nula; total 120 linhas / 60 espécies; SOURCE inalterado; registros do piloto inalterados (id, conteúdo, `updated_at`).
- Qualquer violação aborta tudo. Sem DDL, funções, grants ou ledger.

**6848 (só leitura, BEGIN/ROLLBACK).** Total 120/60; nenhuma linha editorial fora dos dois lotes; forma (pt-BR, direitos, proveniência); GENUS + FLAVOR por espécie; md5 dos 100 textos do lote; md5 dos 20 registros do piloto; SOURCE 2.050 com o hash de base; ficha: #4 em pt-BR devolve o editorial ("Pokémon Lagarto"), #4 em `en` devolve o oficial com versão, #1 (piloto) segue editorial, #2 (fora dos lotes) segue com o oficial `en`.

**Pré-condições conferidas no LIVE (só leitura, 2026-10-13):** 20 linhas `MMKYU_EDITORIAL` / 10 espécies, todas do piloto, hash do conjunto `6c1653539c8abbb5ed06c1a4159e294b` (igual ao da P3d); 0 linhas editoriais nas 50 espécies do lote; 50/50 elegíveis; SOURCE 2.050 com hash `ca8e9c87…`; impressão digital das 50 descrições oficiais igual à do snapshot congelado (`2ede3e77f19a3a6579c145ed70024d06`); ledger 419; hash das funções `b2b77ca3…`; ACL de `pokemon_species_text` inalterada.

**Sequência de execução (cada etapa com autorização explícita):**
1. Reconferir pré-condições (consulta só de leitura acima) e o sha256 dos dois SQL.
2. **Ensaio**: 6137 + 6848 sem alteração de lógica numa única transação, encerrada por exceção (rollback integral), como no ensaio da P3d; conferência independente pós-rollback (0 linhas do lote, 20 do piloto, hashes de SOURCE, funções e ledger).
3. **Aplicação definitiva**: 6137 com o próprio `begin;`/`commit;`.
4. **Validação**: 6848 sobre os dados persistidos → `6848 PASS`; leitura independente de contagens e hashes.
5. Promoção da 6137 para `database/seeds/` (dado editorial, não migration) e homologação no navegador por amostra.

**Rollback (somente as 100 linhas do Lote 01):** o `DELETE` do rodapé da 6137 filtra `origin = 'MMKYU_EDITORIAL'`, `language_code = 'pt-BR'` e as 50 espécies do lote; os 20 registros do piloto e todo o SOURCE ficam fora do filtro. Após o rollback, a 6847 (validação da P3d) volta a ser aplicável e deve passar. As fichas do lote voltam ao inglês oficial sem mudança de código.

### Ensaio LIVE com rollback integral (2026-10-13) — PASS

- **Pré-checagem:**
  - 6137 e 6848 idênticas às preparadas (sha256 `6032b267…c4b8` e `6c09e36b…c131`; regeneração byte a byte idêntica);
  - JSON revisão 11 com 50/50 APROVADO (sha256 `73ab17d3…f001`); validador com `--require-approved` OK; 18/18 testes;
  - LIVE: 20 editoriais da P3d (hash `6c165353…294b`, metadados `98de7d5f…cc9d`), 0 no lote, SOURCE 2.050 / `ca8e9c87…`, snapshot sem deriva (`2ede3e77…`), ledger 419, funções `b2b77ca3…`, ACL e 1 trigger inalterados.
- **Execução:** uma única transação com 6137 + 6848 sem alteração de lógica. Só o invólucro mudou: `begin;`/`commit;` da 6137 e `begin;`/`rollback;` da 6848 removidos, alguns comentários omitidos, e um bloco final de conferência encerrado por exceção (rollback integral). Nenhum `commit`. Resultado: `ENSAIO_ROLLBACK 6137 OK + 6848 PASS (editorial: 120 linhas / 60 espécies; lote: 100 linhas; piloto: conteúdo e metadados intactos; funções/ACL/trigger/ledger inalterados)`.
- **Leitura independente pós-rollback:** 20 editoriais (todos da P3d), hash `6c1653539c8abbb5ed06c1a4159e294b` e metadados `98de7d5f…` iguais; 0 no lote; SOURCE 2.050 / `ca8e9c87…`; total da tabela 2.070; ledger 419; funções `b2b77ca3…`; ACL e trigger inalterados; nenhuma tabela temporária remanescente.


### Publicação definitiva no LIVE (2026-10-13) — 6137 CONFIRMADO EXECUTADO, 6848 PASS

- **Mandato:** autorização expressa de Fabrício para executar a 6137 exclusivamente para publicar o Lote 01 (50 espécies aprovadas).
- **Pré-condições confirmadas antes da gravação:** 6137/6848 idênticas às do ensaio (sha256 e regeneração byte a byte); JSON revisão 11 com 50/50 APROVADO e validador `--require-approved` OK; 18/18 testes; LIVE com 20 editoriais da P3d (conjunto `6c165353…`, metadados `98de7d5f…`), 0 no lote, SOURCE 2.050 / `ca8e9c87…`, snapshot sem deriva (`2ede3e77…`), ledger 419, funções `b2b77ca3…`, ACL e 1 trigger.
- **Execução:** 6137 com o `begin;`/`commit;` do próprio arquivo, via `execute_sql` (MCP Supabase), sem alteração de lógica (cabeçalho de comentários abreviado). Gravação em 2026-10-14 01:01:53 UTC, sem erro. Sem entrada de ledger (419).
- **Validação:** 6848 sobre os dados persistidos terminou sem exceção (= PASS; qualquer divergência lança `6848 FAIL`).
- **Leitura independente pós-publicação:**
  - 120 editoriais / 60 espécies; lote = 100 linhas / 50 espécies; 0 editoriais fora do lote e da P3d;
  - hash do conjunto do lote `4a4a08f4930965918f9b093d809ebca2`, idêntico ao recalculado a partir do JSON aprovado;
  - P3d intacta: conjunto `6c1653539c8abbb5ed06c1a4159e294b`, metadados (id, conteúdo, created_at, updated_at) `98de7d5ff26ebbba74937f1c84e7cc9d`;
  - SOURCE 2.050 / `ca8e9c87…`; total da tabela 2.170; ledger 419; funções `b2b77ca3…`; ACL e trigger inalterados; nenhuma tabela temporária.
- **Promoção:** `database/seeds/6137_publish_pokedex_editorial_ptbr_lote_01.sql` difere da proposta só no cabeçalho de status (sha256 do corpo `begin…commit` = `afd864b8…49cc` nos dois). A 6848 permanece inalterada nesta pasta. No JSON, só o bloco `publication` foi atualizado; textos e `content_md5` intactos.
- **Rollback (se necessário, com nova autorização):** o `DELETE` do rodapé da 6137 remove só as 100 linhas `MMKYU_EDITORIAL` pt-BR das 50 espécies do lote; a P3d e o SOURCE ficam fora do filtro, e a 6847 volta a ser aplicável. As fichas do lote voltam ao inglês oficial sem mudança de código.

**Próximo passo:** homologação de Fabrício na aplicação antes do encerramento do Lote 01.
