# V1-13 · E1-C2 — Operações em massa complementares (5384–5387)

| Campo | Valor |
|---|---|
| **Estado** | **PROPOSTA LOCAL — NÃO EXECUTADA, NÃO APLICADA, NÃO HOMOLOGADA.** Preparada em `V1-13 / E1-C2 \| REMAINING BULK OPERATIONS-01` e revisada em `BULK OPERATIONS INTEGRITY REVIEW-02` (2026-11-15). Nenhum SQL executado, nenhum acesso ao LIVE, nenhum ambiente, nenhuma conta. Prova dinâmica (5893) **pendente**. |
| **Base** | HEAD `a3e3ed6` (E1-A `a40c707`, E1-B1 `b19ee93`, E1-B2 `b1fb4c1`, E1-B3 `3dc16fa`, E1-C1 `a3e3ed6`, todas sem execução). |
| **Contrato** | C-200, C-220–C-226, C-234, C-235, C-237, C-238, C-239, C-241, C-242, C-243, C-244. |
| **Validação** | Sem ambiente isolado; só sob protocolo controlado e com autorização específica. S8 concorrente, S10 e PR-04B pendentes. |
| **Fora do escopo** | Mesclagem nova, campo de objetivo, limpeza de Storage, leituras da E1-D, interface (E2/E3), homologação (E1-E). |

## Arquivos

| Arquivo | O que faz |
|---|---|
| `5384_extend_editor_binder_activity_event_types.sql` | Lista de tipos do EDITOR: mais 4 pares (tipo, origem), cada um com a função que o produz |
| `5385_create_editor_binder_gap_operations.sql` | Ajudantes comuns (leitura sem trava, conjunto com terceiros, página nova) e inserir/fechar espaço |
| `5386_create_editor_binder_auto_arrange.sql` | Organização automática pelo EDITOR |
| `5387_create_editor_binder_catalog_reconciliation.sql` | Novidades do Catálogo pelo EDITOR (Master Set) |
| `5893_validate_editor_remaining_bulk_operations_HARNESS.sql` (v1.1) | Prova dinâmica: 23 verificações + F.2 (GATE 24). **Não executada** |
| `ROLLBACK_E1C2.sql` | Reversão R5387 → R5384; devolve a lista da 5381 byte a byte; não apaga nada |
| `static_check_e1c2.py` | Verificação estática, 35 verificações |

Numeração conferida: o último número usado era `5383` (E1-C1) e o último harness, `5892`.

## Inventário das quatro famílias

| | Inserir espaço | Fechar espaço | Organização automática | Novidades do Catálogo |
|---|---|---|---|---|
| **Titular** | `preview_my_binder_insert_gap`, `insert_my_binder_gap` (5243/5283) | `close_my_binder_gap` (5243/5284) | `preview/apply_my_binder_auto_arrange` (5342–5344, 5360) | `get_my_binder_catalog_novelties`, `preview/apply_my_binder_catalog_reconciliation` (5263–5266, 5296) |
| **Parâmetros** | coleção, bolso, token `g1`, confirmações de página | coleção, bolso do espaço, bolso final, token `u1`, página criada | coleção, token `aa1` | coleção, chaves (null = todas), token `rc1`, confirmações |
| **Plano** | `binder_gap_chain`/`binder_gap_evaluate` | `binder_gap_undo_token` | `binder_auto_arrange_plan` | `binder_catalog_context/novelties/plan` |
| **Escreve** | posições, reservas e imagens andam uma casa (`binder_gap_move_pocket`); página nova | o inverso; remove a página criada se ficou vazia | só INSERT de posições | reservas novas, acabamento em reserva genérica, deslocamentos, páginas novas, registro de incorporação |
| **Barreiras** | bolso fixado ou mesclado não anda e bloqueia | trecho com fixado/mesclado expira | fixado, imagem, mesclagem e ocupado não são destino | as mesmas do espaço; carta fora de ordem e reserva genérica ambígua pedem revisão |
| **Referências de espécie** | não andam (ficam no bolso) | idem | Pokédex: destino é o bolso da espécie de X | fichário com qualquer referência é inelegível |
| **Histórico** | `GAP_OPENED` (FICHARIO), itens SHIFTED, PAGE_ADDED | `GAP_CLOSED` (FICHARIO), SHIFTED, PAGE_REMOVED | `CARDS_AUTO_ARRANGED` (FICHARIO), PLACED | `CATALOG_NOVELTIES_INCORPORATED` (**CATALOGO**), RESERVED/INCORPORATED/SHIFTED/PAGE_ADDED |
| **Alcance** | trecho até o 1º bolso livre, podendo cruzar páginas e criar uma | trecho do espaço | todos os bolsos vazios reservados (ou de espécie) | cada passo desloca um trecho; páginas no fim |
| **Limites** | 500 linhas; confirmação para cruzar página e criar página | 500 | 500 inserções | 100 novidades, 500 linhas |
| **Autorização** | proprietária ou convidada (5240) | idem | só proprietária | proprietária ou convidada; só Master Set |

## O que foi implementado

**Todas as quatro**, como RPCs próprias do EDITOR. Nenhuma ficou exclusiva do titular, porque cada uma pôde ser isolada pela regra abaixo.

| RPC | Espelho de |
|---|---|
| `editor_preview_binder_insert_gap`, `editor_insert_binder_gap` | 5243/5283 |
| `editor_close_binder_gap` | 5284 |
| `editor_preview_binder_auto_arrange`, `editor_apply_binder_auto_arrange` | 5360 |
| `editor_preview_binder_catalog_reconciliation`, `editor_apply_binder_catalog_reconciliation` | 5265/5296 |

**Reuso em vez de cópia.**

- **Reusados sem mudança:** os planos, tokens e deslocamentos canônicos (`binder_gap_chain`, `binder_gap_evaluate`, `binder_gap_move_pocket`, `binder_gap_undo_token`, `binder_auto_arrange_plan`, `binder_catalog_assert_eligible`, `binder_catalog_novelties`, `binder_catalog_plan`, `binder_activity_add_pocket_shift_items`). A prévia e a confirmação do EDITOR produzem **o mesmo plano e o mesmo token** do titular, e nenhuma regra de prioridade é nova.
- **Duplicado:** só a orquestração de cada RPC do titular, que não pode ser chamada porque exige o titular (`binder_layout_lock_for_collection`, `assert_collection_layout_mutable`). Ficam com DEVER DE ESPELHO:
  - corpo de `insert/close_my_binder_gap` (~90 linhas cada);
  - `apply_my_binder_auto_arrange` (~100);
  - `apply_my_binder_catalog_reconciliation` (~170).
- **Custo:** qualquer mudança nessas quatro funções do titular precisa ser repetida aqui. A alternativa, um parâmetro de ator nas funções do titular, mudaria quatro funções canônicas homologadas e o md5 delas, e mexeria no caminho do titular. Foi descartada.

## Regra central e matriz

O EDITOR só executa quando **todas** as condições valem, sob as travas, antes de qualquer escrita:

1. **Participação ativa e fichário exclusivo** (5382 para escrita, `editor_binder_exclusive_read` para prévia): EDITOR ACTIVE de X, X proprietária do fichário, nenhuma convidada, X ativa.
2. **Conjunto afetado inteiro de X ou livre:** nenhum bolso FOREIGN (5371/5378). Senão → `OPERATION_RESERVED_TO_OWNER`, sem dizer o quê.
3. **Plano recalculado e token igual ao da prévia.**
4. **Nada patrimonial ou administrativo:** nenhuma alocação, exemplar, local, condição, Set, escopo, acabamento, política, identidade, imagem, mesclagem ou participação é escrito.

| Operação | Fichário com convidadas | Fichário exclusivo, conjunto só de X/livre | Fichário exclusivo, conjunto com terceiros |
|---|---|---|---|
| Inserir espaço | titular | **EDITOR** | titular |
| Fechar espaço | titular | **EDITOR** | titular |
| Organização automática | titular | **EDITOR** | titular (defesa em profundidade; o plano já só escolhe X) |
| Novidades do Catálogo | titular | **EDITOR** | titular |

Conjunto afetado por operação:

| Operação | Conjunto conferido |
|---|---|
| Inserir espaço | todos os bolsos que andam + o bolso de destino (página nova nasce vazia) |
| Fechar espaço | todo o trecho do espaço ao fim |
| Organização automática | todos os bolsos de destino do plano |
| Novidades | destinos de todos os passos + trechos inteiros de cada deslocamento (posições existentes) |

- **Por que o estado atual basta nas novidades:** um conteúdo só se desloca a partir de uma posição que está no trecho do passo em que anda, e páginas novas nascem vazias.

## Conteúdo residual de terceiros

| Resíduo | De onde vem | Proteção |
|---|---|---|
| Carta de convidada desassociada | 5253: as posições ficam | FOREIGN no conjunto → recusa (5893 1.2) |
| Carta sem coleção | desalocada com posição | FOREIGN → recusa |
| Imagem, mesclagem, trava do titular | titular | imagem/mesclagem FOREIGN → recusa (5893 1.5, 3.2); trava é barreira canônica |
| Reserva de outra coleção | antiga proprietária: a 5254 torna explícitas as reservas implícitas | FOREIGN → recusa; a organização só usa reservas de X |
| Referência de espécie de outra coleção | antiga proprietária: a 5254 não as move | FOREIGN; novidades → recusa antes da elegibilidade (sem revelar o motivo) |

**Prévias sem dados de terceiros:**

- Espaço: sem posição de barreira, sem contagem de imagens, sem ids de bolso.
- Organização: sem `slot_id`; só conteúdo de X, porque o plano só considera X.
- Novidades: sem `layout_id`, capacidade e bolsos livres, que revelariam ocupação de terceiros. A posição de barreira só aparece se o bolso da barreira for de X.

## Atomicidade, planos e tokens

| | Ordem de travas do EDITOR | Ordem do titular |
|---|---|---|
| Espaço | proprietária → layout → participação → bolsos da cadeia (por id) | 5122 (proprietária → layout) → bolsos por id |
| Organização | proprietária → layout → participação → bolsos → exemplares (por id) | 5122 → bolsos → exemplares |
| Novidades | proprietária → layout → participação → bolsos de cada passo (por id) | 5240/5122 → bolsos de cada passo |

- **Travas:** mesma raiz e mesma sequência do titular e da E1-C1. Por inspeção, não há ciclo.
- **Plano e token:** o token da prévia é recomputado sob as travas e comparado antes de escrever (`GAP_PLAN_CHANGED`, `AUTO_ARRANGE_PLAN_CHANGED`, `RECONCILE_PLAN_CHANGED`, `GAP_UNDO_EXPIRED`). A organização ainda replaneja depois de travar bolsos e exemplares.
- **Rollback integral:** toda recusa acontece antes da primeira escrita, ou é exceção que desfaz a chamada inteira (verificações finais de consistência como no titular).
- **Concorrência:** **não comprovada** (S8 concorrente, S10).

## Eventos (5384)

| Tipo novo | Função que o produz | Origem |
|---|---|---|
| `GAP_OPENED` | `editor_insert_binder_gap` | FICHARIO |
| `GAP_CLOSED` | `editor_close_binder_gap` | FICHARIO |
| `CARDS_AUTO_ARRANGED` | `editor_apply_binder_auto_arrange` | FICHARIO |
| `CATALOG_NOVELTIES_INCORPORATED` | `editor_apply_binder_catalog_reconciliation` | CATALOGO |

- **Regra por par (tipo, origem):** os 14 tipos de fichário só com FICHARIO; as novidades só com CATALOGO, igual ao titular. Coleção obrigatória; ator = `auth.uid()` (5268) e EDITOR ativo da coleção do evento (5372).
- **Itens:** só de X ou de página (5379); a guarda da 5379 continua valendo.
- **Continuam fora:** montagem, associação, desassociação, desmontagem, exclusão, transferência e saídas pelo acervo.
- **Lista fechada:** a verificação estática 3.2 confere que a lista é exatamente o conjunto de pares que as funções do EDITOR abrem.
- **Compatibilidade:**
  - a gravação (5379) não muda;
  - a 5381 (arquivo) não muda;
  - a 5892 continua válida, porque o fixture dela só gera tipos que já estavam na lista;
  - a reversão devolve a lista da 5381 byte a byte.
- **Leitura de membros (E1-D):** a C-241 lista E11–E16 como visíveis aos membros. O E21 (`CARDS_AUTO_ARRANGED`, criado depois da C-241 pela 5341) não está na lista. Decidir na E1-D se ele entra (D13, abaixo).

## Revisão de integridade (`BULK OPERATIONS INTEGRITY REVIEW-02`)

Nenhum defeito material foi encontrado nas migrations 5384–5387; elas não mudaram. A 5893 ganhou os casos indispensáveis (v1.1).

### Token `u1` (fechar espaço)

| Pergunta | Resposta (5243 `binder_gap_undo_token`, inalterada) |
|---|---|
| Quem produz | só a inserção (do titular ou do EDITOR), na resposta da chamada. É hash de ids internos (posição, reserva, imagem, trava); nem o EDITOR nem o cliente conseguem calculá-lo |
| A quem se liga | a **nenhum usuário e nenhuma operação**: é uma foto do trecho espaço..fim e da página criada |
| Estado anterior | o trecho precisa estar exatamente como ficou depois da inserção; qualquer mudança no trecho (carta, reserva, imagem, trava) ou na página criada o invalida → `GAP_UNDO_EXPIRED` |
| Reuso | depois de fechar, o estado muda e o token expira (5893 1.4); só volta a valer se o mesmo estado se repetir, e aí fechar é de novo legítimo |
| EDITOR desfaz o titular | só com o token em mãos **e** com o trecho inteiro de X ou livre (5893 1.5). O efeito é o mesmo que mover cartas de X, o que ele já pode fazer. Se o espaço do titular deslocou conteúdo de terceiros (imagem, carta de outra coleção), o EDITOR é recusado mesmo com o token (5893 1.7) |
| EDITOR desfaz outro EDITOR | o mesmo critério |
| Alterações posteriores legítimas | não são desfeitas: qualquer mudança no trecho invalida o token; mudanças fora do trecho não são tocadas; a página criada só sai se for a última e estiver vazia de tudo |

- **Conclusão:** o token não é credencial. A autorização do desfazer é a mesma de qualquer deslocamento do EDITOR (C-237: fichário exclusivo, conteúdo só de X).
- **Sem ampliação:** a capacidade do EDITOR não cresce por consequência indireta, e o contrato vigente resolve o caso. **Nenhuma decisão funcional nova.**

### Organização automática (5342/5360 → 5386)

| Ponto | Comprovado por inspeção |
|---|---|
| Elegibilidade | `cands`: exemplar com alocação a X (`ca.collection_id = X`), no local do fichário (`storage_container_id = container`), do inventário do titular, fora de qualquer bolso |
| Duplicatas | 1:1 estrito (grau 1 no bolso e no exemplar), sem desempate; Pokédex: só a representante (escolhida → vínculo mais antigo); as demais ficam de fora (`NOT_REPRESENTATIVE`) |
| Reservas / travas | destino Set/Master: bolso VAZIO com reserva da proprietária (NULL ou X), não fixado, sem imagem, fora de mesclagem; Pokédex: bolso VAZIO com referência de X, sem reserva/imagem/trava/mesclagem |
| Patrimônio | só `insert into collection_layout_slot_assignment` (5386: verificação estática 5.3); alocação, exemplar, local e condição intactos (5893 6.1) |
| Plano = escrita | os pares gravados são os INSERT do plano recalculado depois das travas (bolsos e exemplares FOR UPDATE), com o mesmo token |
| Posições existentes | bolso ocupado nunca é destino; exemplar já posicionado nunca é candidato; corrida → `unique_violation` → `AUTO_ARRANGE_PLAN_CHANGED` |
| Elegibilidade alterada | exemplar posicionado entre prévia e confirmação → `AUTO_ARRANGE_PLAN_CHANGED`, nada gravado (5893 2.3) |

### Novidades do Catálogo (5264/5296 → 5387)

| Efeito persistente | Coberto |
|---|---|
| Reserva nova (IN_PLACE, RESERVE_PLACED, fim de deslocamento) | só em bolso conferido no conjunto afetado; registrada para a proprietária (X) |
| Acabamento em reserva genérica (UPGRADE) | só reserva genérica cuja coleção resolvida é X; bolso conferido |
| Deslocamentos | trecho inteiro conferido; `binder_gap_move_pocket` da 5243 |
| Páginas novas | no fim, vazias, dentro do evento |
| Registro de incorporação | `(fichário, X, chave)`: estado de X, faz a novidade não voltar a ser oferecida a X (nem ao titular para X) |
| Histórico | `CATALOG_NOVELTIES_INCORPORATED` (CATALOGO, X) |
| Qualquer outro | nenhum: Catálogo, Set, escopo, acabamentos, marcos e outras coleções só são lidos (5893 3.3) |

- **Organizar a coleção × administrar o Catálogo:** o EDITOR lê o Catálogo (posições nascidas depois do marco de X) e escreve só no fichário e no registro de X. Não cria, edita nem reclassifica carta, variante, Set ou acabamento.

### Matriz plano → autorização → escrita

| Família | Previsto pelo plano | Classificado (OWN/FREE/FOREIGN) | Modificado | Secundário | Travas | Invalida o token |
|---|---|---|---|---|---|---|
| Inserir espaço | cadeia (bolsos que andam) + destino | cadeia + destino; qualquer FOREIGN → recusa | cartas, reservas (e imagens, impossíveis após a guarda) da cadeia; página nova | itens SHIFTED, PAGE_ADDED | proprietária → layout → participação → bolsos (id) | qualquer mudança na cadeia ou no destino (`g1`) |
| Fechar espaço | trecho espaço..fim | trecho inteiro | conteúdo do trecho; página criada vazia | SHIFTED, PAGE_REMOVED | idem | qualquer mudança no trecho ou na página (`u1`) |
| Organização | pares bolso ↔ exemplar | todos os destinos | posições novas | PLACED | + exemplares (id); replano | pares, época de organização, marco de cobertura (`aa1`) |
| Novidades | passos (destinos e trechos) | destinos + trechos existentes | reservas, acabamento, deslocamentos, páginas, registro | RESERVED/INCORPORATED/SHIFTED/PAGE_ADDED | proprietária → layout → participação → bolsos de cada passo | todos os bolsos, objetivo, marco, seleção e passos (`rc1`) |

- **TOCTOU:**
  - classificação e escrita acontecem sob a trava da proprietária, que todos os escritores de bolso tomam (titular 5122; EDITOR 5371/5382);
  - a mudança de local pelo acervo (5287/5288/5289) não toma essa trava, mas só **retira** posições (trava exemplares e posições). Retirar nunca cria conteúdo de terceiros;
  - na inserção, a soma de linhas movidas é conferida (`GAP_INCONSISTENT`); nas novidades, a consistência final;
  - no fechamento, igual ao titular: menos conteúdo a devolver, nunca conteúdo de terceiros;
  - a alocação de um exemplar a outra coleção por cima da trava de X não muda a classificação para X: sem coleção e de outra coleção são ambos FOREIGN.
- **Prévia vencida:** o titular reserva o destino depois da prévia → `GAP_PLAN_CHANGED` (5893 1.3).
- **Lacuna:** nenhuma encontrada. Concorrência real **não comprovada** (S8/S10).

### Eventos

- **Pares (tipo, origem):** os 4 tipos novos vêm cada um da sua função e com a origem do titular. Os 11 anteriores continuam (3.2 confere a lista inteira).
- **Ator e coleção:** o ator é `auth.uid()`, e o EDITOR é ativo da coleção do evento (5372).
- **Itens:** todos de X ou de página (5379; 5893 1.3, 2.2).
- **Fora da lista:** nenhum tipo administrativo ou estrutural.
- **Pendências:** D13 continua proposta; a C-241 não foi alterada e a leitura de membros não foi implementada.

## Compatibilidade com E1-A até E1-C1

- **Intactas:** E1-A … E1-C1, `web/` e `database/schema/` (verificação estática 10.1). Nenhuma migration anterior foi alterada.
- **Nenhuma função do titular ou de entrega anterior redefinida** (7.3). A 5384 substitui só o corpo da função do gatilho da 5381, por nova migration.
- **Harnesses 5888, 5861, 5889, 5890, 5891 e 5892:**
  - não fixam a função do gatilho;
  - as operações deles só abrem tipos que continuam permitidos;
  - a 5893 fixa o md5 novo.
- **Ordem de aplicação:** … → E1-C1 → 5384 → 5385 → 5386 → 5387. `ROLLBACK_E1C2` vem antes de `ROLLBACK_E1C`.

## Verificações

- **Estática** (executada, sem banco): `static_check_e1c2.py` → **35/35 PASS**. Onze mutações aplicadas e desfeitas, todas detectadas:
  - guarda de terceiros desligada na inserção, na prévia de espaço, no fechamento, na organização e nas novidades;
  - tipo estrutural na lista;
  - origem não conferida nas novidades;
  - exposição de capacidade na prévia;
  - EXECUTE para anon;
  - página removida com referência;
  - reserva com coleção explícita.
- **Dinâmica** (pendente): `5893` v1.1 → **24/24** esperado, sob protocolo controlado, depois de E1-A … E1-C1. Casos da revisão: token `u1` de outro usuário (1.5, 1.7), prévia vencida (1.3), elegibilidade alterada (2.3), efeitos da incorporação (3.3).

## Riscos, dependências e provas pendentes

1. Concorrência não comprovada (S8/S10), inclusive EDITOR × titular nas quatro operações.
2. **Dever de espelho** sobre quatro funções do titular (ver "Reuso em vez de cópia").
3. Os planos canônicos não foram reinspecionados linha a linha nesta rodada. A proteção do EDITOR não depende deles, porque o conjunto afetado é conferido à parte, mas uma mudança futura no plano exige revisar a regra do conjunto (README da 5387).
4. **D13 (para a E1-D, não bloqueia):** o membro deve ver `CARDS_AUTO_ARRANGED`? A C-241 não o lista. Decisão do proprietário.
5. Pendentes:
   - S1–S10 sem prova dinâmica;
   - S8 concorrente e S10;
   - API do Storage, inclusive envios paralelos;
   - PR-04B aberta;
   - nenhuma migration da V1-13 aplicada;
   - publicação da V1-13 bloqueada;
   - D9–D12 sem aprovação formal.

## Dever de espelho (registro, `E1-C2 | LOCAL COMMIT AND CLOSEOUT-03`)

| Função canônica do titular | Operação do EDITOR que a espelha | Internas reusadas (mudança nelas também exige revisão) |
|---|---|---|
| `insert_my_binder_gap` (5283) | `editor_preview_binder_insert_gap`, `editor_insert_binder_gap` (5385) | `binder_gap_chain`, `binder_gap_evaluate`, `binder_gap_move_pocket`, `binder_gap_undo_token` (5243) |
| `close_my_binder_gap` (5284) | `editor_close_binder_gap` (5385) | `binder_gap_undo_token`, `binder_gap_move_pocket` (5243) |
| `apply_my_binder_auto_arrange` (5360) | `editor_preview/apply_binder_auto_arrange` (5386) | `binder_auto_arrange_plan` (5360) |
| `apply_my_binder_catalog_reconciliation` (5296) | `editor_preview/apply_binder_catalog_reconciliation` (5387) | `binder_catalog_context/assert_eligible/novelties/plan` (5264) |

- **Quando revisar:** qualquer alteração nessas funções obriga a revisar a operação do EDITOR correspondente na mesma proposta, com nova rodada de verificação estática e do harness 5893.
- **O que revisar:** regra, limite, token, efeitos e conjunto afetado.
- **Refatoração:** nenhuma nesta rodada.

## Estado (2026-11-15, `E1-C2 | LOCAL COMMIT AND CLOSEOUT-03`)

| Item | Situação |
|---|---|
| E1-A, E1-B1, E1-B2, E1-B3, E1-C1, E1-C2 | preparação local concluída e versionada |
| E1-C (C1 + C2) | encerrada **apenas como preparação local** |
| Migrations | nenhuma aplicada |
| Harnesses | nenhum executado em banco |
| D9–D13 | aguardando aprovação formal; D12 obrigatoriamente antes da E1-D |
| E1-D | não iniciada |
| S1–S10 | sem comprovação dinâmica |
| S8 concorrente e S10 | pendentes |
| Testes reais da API do Storage | pendentes |
| PR-04B | aberta |
| Publicação da V1-13 | bloqueada |
| Ambiente isolado | nenhum |
