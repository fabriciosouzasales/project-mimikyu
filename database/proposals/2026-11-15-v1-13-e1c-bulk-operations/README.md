# V1-13 · E1-C — Operações em massa limitadas à coleção (5381–5383)

| Campo | Valor |
|---|---|
| **Estado** | **PROPOSTA LOCAL — NÃO EXECUTADA, NÃO APLICADA, NÃO HOMOLOGADA.** Preparada em `V1-13 / E1-C \| COLLECTION-SCOPED BULK OPERATIONS-01` e revisada em `E1-C1 \| BULK OPERATIONS SAFETY REVIEW-02` (2026-11-15). Divisão aprovada: esta proposta é a **E1-C1**; a **E1-C2** é o incremento seguinte, **não iniciado**. Nenhum SQL executado, nenhum acesso ao LIVE, nenhum ambiente, nenhuma conta. Prova dinâmica (5892) **pendente**. |
| **Base** | HEAD `3dc16fa` (E1-A `a40c707`, E1-B1 `b19ee93`, E1-B2 `b1fb4c1`, E1-B3 `3dc16fa`, todas sem execução). Depende das quatro aplicadas. |
| **Contrato** | C-234, C-237 (operações de página e em massa), C-238, C-241, C-242, C-243, C-244. |
| **Validação** | Sem ambiente isolado; só sob protocolo controlado e com autorização específica. S8 concorrente, S10 e PR-04B pendentes. |
| **Fora do escopo** | Mesclagem nova, campo de objetivo, limpeza de Storage, permissões patrimoniais, leituras da E1-D, interface (E2/E3), homologação (E1-E). |

## Arquivos

| Arquivo | O que faz |
|---|---|
| `5381_restrict_editor_binder_activity_event_types.sql` | Gatilho no histórico: evento com ator ≠ titular só com tipo de curadoria da lista fechada |
| `5382_create_editor_binder_page_operations.sql` (v1.1) | Autorização de fichário exclusivo; adicionar, remover (vazia) e reordenar páginas pelo EDITOR |
| `5383_create_editor_binder_species_reference_operations.sql` (v1.1) | Referências de espécie pelo EDITOR: prévia, aplicar, remover, mostrar e ocultar |
| `5892_validate_editor_bulk_operations_HARNESS.sql` (v1.1) | Prova dinâmica: 26 verificações + F.2 (GATE 27). **Não executada** |
| `ROLLBACK_E1C.sql` | Reversão R5383 → R5381; não apaga dado nenhum |
| `static_check_e1c.py` | Verificação estática, 34 verificações |

Numeração conferida: o último número usado era `5380` (E1-B3) e o último harness, `5891`.

## Inventário das operações em massa e classificação

**Regra da C-237:**

- Operações de página e em massa num fichário de **várias** coleções são do titular.
- Num fichário de **uma** coleção, o EDITOR pode executá-las, desde que nada de terceiros seja deslocado, retirado ou descartado.

A = permitida ao EDITOR dentro da coleção · B = exclusiva do titular · C = depende de decisão.

| Operação (titular) | Alcance real | Classe | Situação nesta rodada |
|---|---|---|---|
| Adicionar página (5280) | página nova vazia no fim | A, só no fichário exclusivo | **implementada** (5382) |
| Remover página (5286) | apaga página; exige página vazia, salvo referências | A, só no fichário exclusivo, só página totalmente vazia | **implementada** (5382) |
| Reordenar páginas (5282) | move páginas inteiras; não toca bolso | A, só no fichário exclusivo | **implementada** (5382) |
| Referências de espécie: aplicar, remover, mostrar/ocultar (5258) | camada e preferência do fichário inteiro | A, só no fichário exclusivo da Pokédex | **implementada** (5383) |
| Inserir e fechar espaço (5243/5283/5284) | desloca o conteúdo de todos os bolsos seguintes, entre páginas | A, só no fichário exclusivo, e só se a cadeia deslocada não tiver conteúdo de terceiros | **não implementada** (E1-C2) |
| Organização automática (5342/5344/5360) | só insere cartas de X em bolsos vazios com reserva de X | A, só no fichário exclusivo | **não implementada** (E1-C2) |
| Novidades do Catálogo (5264/5296) | insere reservas e páginas, pode deslocar conteúdo | A, só no fichário exclusivo, sem deslocar terceiros | **não implementada** (E1-C2) |
| Trava, liberação e retirada em vários bolsos (5278/5277/5274, `uuid[]`) | soma de operações por bolso | A como composição (cada bolso precisa ser de X) | **não necessária agora**: o EDITOR já as tem por bolso (E1-B1/E1-B2). Lote atômico fica para a E2, se a interface pedir |
| Mesclar e desfazer mesclagem (5238/5240) | região com imagem do titular | C (D9 pendente) | nada |
| Imagens do fichário, identidade, grade (5233, 5245, 5228) | aparência e estrutura | B (C-238) | nada |
| Montar, desmontar, excluir, transferir, associar, desassociar (5295, 5294, 5293, 5292, 5290, 5291) | estrutura de participação | B (C-238) | nada |
| Vincular exemplar à Pokédex (5210) e lote | aloca | B (C-242: alocação é do titular) | nada |
| Gerações da Pokédex (5203) | escopo | B (C-239) | nada |
| Organizar o acervo, mudar local (5287/5288) | patrimônio e local | B | nada |

**Por que E1-C2:**

- Espaços, organização automática e novidades têm planos e tokens próprios. Cada uma é espelho de 300 a 1.000 linhas, com dever de espelho.
- A regra de isolamento delas é diferente: o conteúdo deslocado precisa ser todo de X. Isso pede verificação por cadeia de bolsos.
- Tudo isso cabe melhor numa proposta própria do que junto com a fundação desta rodada.
- O contrato não precisa de decisão nova para elas.

## Autorização por conjunto afetado

`assert_collection_binder_editor_exclusive(X)`, interna:

1. **Autorização da 5371:** EDITOR ACTIVE de X, relida sob trava (proprietária FOR UPDATE → layout FOR UPDATE → participação FOR SHARE).
2. **Fichário exclusivo:** X é a coleção proprietária do fichário e não há nenhuma convidada. Associar e desassociar passam pela mesma trava da proprietária (5122), então o conjunto de coleções não muda até o fim da transação.
3. **Recusa neutra:** qualquer outro caso → `OPERATION_RESERVED_TO_OWNER` (42501), sem dizer o que há no fichário.

**Conjunto afetado de cada operação:**

| Operação | Conjunto | Validação antes de qualquer escrita |
|---|---|---|
| Adicionar página | nada existente | fichário exclusivo |
| Remover página | todos os bolsos da página | página travada; fichário com ≥ 2 páginas; cada bolso classificado: qualquer FOREIGN → reservada ao titular; conteúdo de X (carta, reserva, trava) → `PAGE_NOT_EMPTY`; referências de X confirmadas pela contagem |
| Reordenar | todas as páginas | todas travadas em ordem por id; permutação completa de 1..N |
| Referências | todos os bolsos | nenhuma referência de outra coleção no fichário; plano canônico recalculado sob a trava; token igual ao da prévia |

**Fichário exclusivo NÃO é fichário sem terceiros** (`SAFETY REVIEW-02`). Num fichário sem convidadas podem restar:

| Elemento | Origem | Para o EDITOR de X |
|---|---|---|
| Carta de outra coleção | convidada desassociada: as posições ficam (5253) | FOREIGN |
| Carta sem coleção | desalocada com posição | FOREIGN |
| Reserva de outra coleção | não sobra: a desassociação libera as reservas da convidada (5291) e a transferência torna explícitas as da proprietária (5254) | FOREIGN, se existir |
| Trava sem conteúdo de X | titular | FOREIGN |
| Imagem e mesclagem | titular | FOREIGN |
| Referência de espécie de outra coleção | proprietária anterior: a transferência (5254) não move as referências | FOREIGN |
| Coleção arquivada ou participação removida | uma convidada arquivada continua convidada, então o fichário não é exclusivo; uma participação removida só afeta o membro | — |

O efeito de cada operação sobre esses elementos:

| Operação | Efeito sobre terceiros | Tratamento |
|---|---|---|
| Adicionar página | nenhum | permitido |
| Remover página | apagaria o que está na página | **corrigido (5382 v1.1):** qualquer bolso FOREIGN → `OPERATION_RESERVED_TO_OWNER` |
| Reordenar | muda o número da página, nunca o bolso | permitido: a C-237 libera reordenar porque o conteúdo de cada bolso é preservado |
| Aplicar referências | rótulo em bolso com carta ou imagem de terceiros; o conteúdo fica e o bolso continua FOREIGN | permitido: alteração visual e de classificação, não patrimonial |
| Remover, mostrar ou ocultar referências, e a prévia | apagaria ou esconderia referências de outra coleção | **corrigido (5383 v1.1):** referência de outra coleção no fichário → `OPERATION_RESERVED_TO_OWNER`; remover só apaga e conta as de X |

- **Bolso livre não vira do EDITOR:** página nova e reordenação não mudam a classificação. As referências seguem a 5378: só a referência de X conta como bolso de X.
- **Conteúdo de terceiros:**
  - página com conteúdo de terceiros não é removida;
  - reordenar não toca bolso;
  - referência aplicada sobre carta sem coleção ou imagem do titular não toca o conteúdo, e o bolso continua FOREIGN para o EDITOR (5892 3.3).
- **Sem vazamento:**
  - as recusas não dizem o quê nem quanto: terceiros → "reservada ao titular", como a C-237 manda; conteúdo de X → "página não vazia";
  - a prévia de referências não devolve a contagem de bolsos ocupados (`slots_with_content` da 5258), porque ela revelaria conteúdo que o fichário mascarado esconde;
  - a única contagem devolvida é a das referências, que são de X.
- **Sem execução parcial:** toda recusa acontece antes da primeira escrita ou desfaz a chamada inteira.

## Referências de espécie (Pokédex)

| Pergunta | Resposta |
|---|---|
| A referência é limitada à coleção? | Sim, registrada para a Pokédex proprietária (5257: só ela pode tê-la) |
| O efeito visual é compartilhado? | Sim: a camada e a preferência de exibição valem para o fichário inteiro |
| É alteração global? | É do fichário inteiro: aplicar rotula todos os bolsos; remover apaga a camada |
| Afeta bolsos usados por outras coleções? | Num fichário com convidadas, sim: muda a classificação (5378) e a exibição para elas → **recusado ao EDITOR** |

- **Conclusão:** o EDITOR só aplica, remove, mostra ou oculta no fichário **exclusivo** da Pokédex autorizada, onde a camada só diz respeito a X. Não há permissão de escrita global.
- **Mostrar/ocultar:** o titular também pode fazê-lo pela convidada (5258). Para o EDITOR, exige a Pokédex proprietária, sem convidadas.

**Bolsos afetados:**

| Operação | Bolsos afetados | Natureza |
|---|---|---|
| Prévia | nenhum (só lê) | — |
| Aplicar | todos os pares do plano: bolso n ↔ posição n, em todas as páginas | rótulo de X; não muda carta, reserva, imagem, trava nem alocação |
| Remover | todas as referências de X do fichário | apaga só o rótulo de X |
| Mostrar / ocultar | nenhum bolso; a preferência do fichário | visual |

- **Bolso com exemplar de outra coleção:** recebe o rótulo ao aplicar, a carta não se move e o bolso continua FOREIGN para o EDITOR (a carta decide antes da referência, 5378). Nenhuma outra coleção participa do fichário exclusivo, então ninguém mais é afetado.
- **Patrimônio:** nenhuma das operações é patrimonial (5892 8.1).
- **Base e histórico:** regras de escrita iguais às da 5258, com o mesmo token e o mesmo plano canônico. A 5258 não grava evento, e o EDITOR também não.

## Tipos de evento do EDITOR (5381)

- **Gatilho BEFORE INSERT** em `binder_activity_event`. Vale para qualquer caminho de gravação, inclusive contexto forjado e funções futuras.
- **Gravação intocada:** o md5 da 5379 é preservado. A 5889 e a 5891 continuam válidas sem adaptação.
- **Regra:** evento novo cujo ator existe e é diferente do titular precisa de:
  - tipo na lista fechada: `CARD_PLACED`, `CARD_MOVED`, `CARDS_SWAPPED`, `CARDS_REMOVED`, `POCKET_RESERVED`, `RESERVATIONS_RELEASED`, `POCKETS_LOCKED`, `POCKETS_UNLOCKED`, `PAGES_ADDED`, `PAGE_REMOVED`, `PAGES_REORDERED`;
  - origem `FICHARIO`;
  - coleção registrada.
  - Senão: 42501 `BINDER_ACTIVITY_EVENT_TYPE`.
- **A lista é exatamente** a união dos tipos que as funções do EDITOR abrem (E1-B1, E1-B2, E1-C), conferida pela verificação estática 3.5. Nenhum tipo foi liberado "para o futuro". A E1-C2 terá de acrescentar os dela, explicitamente.
- **Já garantido antes:**
  - ator autenticado (5268);
  - EDITOR ativo da coleção do evento (5372);
  - itens só da coleção do evento e nenhum item estrutural (5379);
  - contexto da própria operação (5379).
- **Titular e legado:** sem mudança (5892 5.3).

**Como a E1-C2 acrescentará tipos:**

- Uma migration nova recria a função do gatilho com a lista estendida, só com o tipo que a função nova da E1-C2 abre (`GAP_OPENED`, `GAP_CLOSED`, `CARDS_AUTO_ARRANGED`, `CATALOG_NOVELTIES_INCORPORATED`, um por operação implementada).
- A verificação estática equivalente à 3.5 continua exigindo lista = tipos efetivamente abertos pelas funções do EDITOR. Um tipo sem função que o produza reprova.

**Revisão (`SAFETY REVIEW-02`):**

- A lista corresponde às operações existentes; nenhum tipo administrativo.
- O ator é `auth.uid()` (5268), e o evento é da coleção autorizada (5372).
- Os itens obedecem à 5379.
- Titular, legado (ator NULL) e rotinas sem evento (marcadores do Catálogo, histórico de completude) não são afetados.
- Nenhum caminho legítimo grava evento com ator diferente do titular fora do EDITOR: a gravação exige `auth.uid()`, e transferência e exclusão de conta não gravam com outro ator.

## Limite de páginas

- **Sem teto numérico,** como decidido. Os limites operacionais atuais:
  - grade fixa nos sete modelos (5228);
  - teto de itens por evento do histórico derivado da capacidade (5268, W1);
  - limites de 500 por confirmação na organização automática, nas novidades e nos espaços (E1-C2);
  - reordenar exige a lista completa de páginas numa chamada.
- **Nenhum desses limites** restringe a quantidade de páginas.
- **Para a E2/E3:** mensagens adequadas quando uma operação exceder a capacidade (limite por confirmação, tamanho de lista, erro de capacidade), sem planos comerciais.

## Atomicidade e concorrência (por inspeção; nada comprovado)

- **Ordem de travas:**
  - todas as operações novas: proprietária → layout → participação → páginas (por id) ou preferência;
  - titular: 5122 (proprietária → layout) → páginas;
  - E1-B1/E1-B2: a mesma raiz;
  - por inspeção, não há ciclo.
- **Coleções diferentes no mesmo fichário:** só existem no fichário de várias coleções, onde as operações são recusadas, depois de travar e sem escrever.
- **Mudança de participação:** a participação fica FOR SHARE até o fim; rebaixar ou remover espera e vale para a próxima chamada (5892 6.1).
- **Titular em paralelo:** passa pela mesma trava da proprietária, e as escritas ficam serializadas.
- **Validação × escrita:** tudo na mesma transação, depois das travas, e as referências recalculam o plano sob a trava. Ainda assim, escritas fora do caminho do fichário (por exemplo, mudança de local pelo acervo) não foram reinspecionadas nesta rodada.
- **Rollback:** recusa antes da escrita ou exceção; não há laço com captura que deixe parte gravada.
- **Pendente:** S8 concorrente e S10 com duas sessões (inclui página e referências do EDITOR × associação e escrita do titular).

## Compatibilidade

- **Intactas:** E1-A, E1-B1, E1-B2 e E1-B3 (verificação estática 9.2). Nenhuma migration anterior foi alterada.
- **Nenhuma função do titular redefinida:** 5258, 5280, 5282, 5286 e 5122 só são lidas.
- **Harnesses:**
  - 5888, 5861, 5889, 5890 e 5891 continuam válidos;
  - só abrem tipos de evento da lista, e os contextos forjados da 5891 são recusados antes de gravar evento;
  - a 5892 roda depois de todos, no estado final.
- **Ordem de aplicação:** E1-A → E1-B1 → E1-B2 → E1-B3 → E1-C. `ROLLBACK_E1C` vem antes de `ROLLBACK_E1B3`.

## Verificações

- **Estática** (executada, sem banco): `static_check_e1c.py` → **34/34 PASS**. Nove mutações aplicadas e desfeitas, todas detectadas: tipo extra na lista, convidada ignorada, trava ignorada na remoção, origem não conferida, privilégio para anon, escrita fora do escopo, classificação ignorada na remoção, referência de outra coleção ignorada e remoção de referências alheias.
- **Dinâmica** (pendente): `5892` → **27/27** esperado, sob protocolo controlado, depois de E1-A a E1-B3.

**Cenários cobertos pela 5892 (não executados):**

- **Páginas:** adicionar, reordenar (imagem do titular preservada), ordem inválida e ordem igual sem evento; página com imagem ou com bolso vazio fixado pelo titular → reservada ao titular; página com carta da coleção → `PAGE_NOT_EMPTY`.
- **Fichário exclusivo com terceiros:** o titular transfere a âncora (5254) e desassocia a antiga proprietária (5253). A carta e as referências dela ficam. Remover página, remover/esconder referências e a prévia são reservadas ao titular. Reordenar e adicionar página não tocam a carta, as referências, a imagem nem a exibição.
- **Várias coleções:** EDITOR da proprietária e da convidada recusados em páginas e referências, sem efeito.
- **Referências:**
  - prévia, token antigo, aplicar, aplicar de novo;
  - bolso com imagem do titular;
  - mostrar/ocultar;
  - remover página com referências;
  - remover a camada;
  - coleção livre.
- **Recusas:** VIEWER, estranho, ex-membro, titular pelo caminho do EDITOR e anon.
- **Tipos de evento:** só curadoria; tipo estrutural e origem de acervo forjados são recusados; eventos estruturais do titular continuam.
- **Revogação, titular, patrimônio e arquivada.**

## Decisões de produto

- **Nenhuma decisão nova** é indispensável para esta rodada.
- **D9, D10, D11, D12:** continuam pendentes; nada aqui as presume. A mesclagem continua C (D9).
- **Sequência:** divisão aprovada. A E1-C2 (espaços, organização automática, novidades do Catálogo) é o incremento seguinte da E1-C, **não iniciado**.

## Riscos

1. Concorrência não comprovada (S8/S10).
2. O EDITOR pode adicionar páginas sem limite, como o titular hoje; não há teto no contrato nem nos controles atuais (ver "Limite de páginas").
3. Prova dinâmica pendente; o número de páginas da fixture vem do plano do fichário (5892 L3).

## Ressalvas rastreadas e estado (2026-11-15, `E1-C1 | LOCAL COMMIT AND CLOSEOUT-03`)

| Item | Situação |
|---|---|
| Impacto visual das referências da Pokédex sobre bolsos com conteúdo de terceiros | analisado só por inspeção; a comprovar na E1-E |
| Teto numérico de páginas | não existe, e nenhum limite arbitrário foi introduzido |
| Limites operacionais e mensagens de capacidade | para a E2/E3 |
| E1-C1 | proposta local versionada, não executada nem homologada |
| E1-C2 | próximo incremento, não iniciado |
| E1-A, E1-B1, E1-B2, E1-B3 | preservadas |
| S1–S10 | não comprovados dinamicamente |
| S8 concorrente e S10 | pendentes |
| Testes reais da API do Storage | pendentes |
| PR-04B | aberta |
| D9–D12 | sem aprovação formal |
| Publicação da V1-13 | bloqueada |
| Ambiente isolado | nenhum |
