# V1-13 · E1-B1 — Autorização do EDITOR e operações fundamentais do fichário (5371–5374)

| Campo | Valor |
|---|---|
| **Estado** | **PROPOSTA LOCAL VERSIONADA (commit `feat(v1-13): prepara autorizacao editor e operacoes basicas do fichario`) — NÃO EXECUTADA, NÃO APLICADA, NÃO HOMOLOGADA.** Sem execução dinâmica; nenhuma autorização para o LIVE; nenhum ambiente isolado. Preparada em `V1-13 / E1-B1 \| EDITOR AUTHORIZATION AND CORE BINDER OPERATIONS-01` (2026-11-15). Nenhum SQL executado, nenhum acesso ao LIVE, nenhum ambiente, nenhuma conta. Prova dinâmica (5889) **pendente**. |
| **Base** | HEAD `a40c707` (E1-A preparada; ela também não foi executada). A E1-B1 depende da E1-A aplicada (5366). |
| **Contrato** | `concept-decisions.md` C-234–C-244 (sobretudo C-235/DR-1, C-236, C-237, C-241, C-243); `05d` seção V1-13, entregas E1.3/E1.4. |
| **Validação** | Sem ambiente isolado (C-244): só sob protocolo controlado equivalente ao P1 da E1-A e com autorização específica. S8 concorrente, S10 e PR-04B continuam pendentes. |
| **Fora do escopo** | Reservas, travas e mesclagens (E1-B2); metadados e capa; Pokédex (E1-B3); coleção por item e leitura do histórico para membros (E1-B3/E1-D); operações em massa (E1-C); leituras 5323/5324 (E1-D); interface (E2/E3); prova dinâmica (E1-E). |

## Arquivos

| Arquivo | O que faz |
|---|---|
| `5371_create_binder_editor_authorization.sql` | Três funções **internas**: `assert_collection_binder_editor` (autorização e travas), `binder_slot_editor_scope` (classificação C-237) e `binder_slot_at` (bolso pela posição visível). |
| `5372_allow_editor_actor_in_binder_activity.sql` | `CREATE OR REPLACE` de `binder_activity_add_item` (5268): aceita ator EDITOR ativo da coleção do evento. **Dependência declarada** (ver abaixo). |
| `5373_create_get_shared_binder_placeable_cards.sql` | Leitura dos exemplares que o EDITOR pode colocar. |
| `5374_create_editor_binder_core_writes.sql` | `editor_place_card_in_binder`, `editor_move_binder_card` e `editor_remove_binder_card`. |
| `5889_validate_editor_core_binder_HARNESS.sql` | Prova dinâmica v1.2: 55 verificações + F.2 (GATE 56). **Não executada.** A v1.2 (E1-B3, `HISTORY INTEGRITY REVIEW-02`) só faz o 0.4 aceitar a gravação da 5372 ou da 5379, para a 5889 valer também como regressão depois da E1-B3. |
| `ROLLBACK_E1B1.sql` | Reversão R5374 → R5371; devolve a 5268 byte a byte. |
| `static_check_e1b1.py` | Verificação estática (sem banco), 61 verificações. |

Numeração conferida em 2026-11-15: último número usado `5370` (E1-A); último harness `5888`.

## Dependência declarada: histórico (5372)

As três operações são instrumentadas pelo histórico do fichário (P3-B S2). A gravação atual (5268) recusa qualquer ator que não seja o titular. Sem a 5372, toda escrita do EDITOR abortaria no primeiro item do histórico.

A mudança é a **menor possível**: só o teste do cabeçalho do evento. Ficam para a E1-B3/E1-D:

- a coleção por item;
- a leitura para membros;
- a lista de permissão de eventos;
- o nome do ator.

O caminho do titular não muda.

## Modelo de autorização

| Verificação, no servidor, a cada chamada | Onde |
|---|---|
| Identidade (`auth.uid()`) | 5371 e 5374 |
| Papel EDITOR **ACTIVE** na coleção X, relido sob trava | 5371, passos 1 e 6 |
| Coleção autorizada e titular (`owner_user_id`) | 5371, passo 1 |
| Fichário de que X participa (proprietária ou convidada) e mesmo titular | 5371, passos 2–5 |
| Proprietária e X ativas | 5371, passos 3 e 5 |
| Operação | Cada RPC da 5374 implementa uma única operação |
| Bolsos de origem e destino, pertencimento e disponibilidade | `binder_slot_at` + `binder_slot_editor_scope` sob trava do bolso |

A ordem de travas é a do titular, com a participação por último:

1. proprietária (FOR UPDATE);
2. layout (FOR UPDATE);
3. X convidada (FOR SHARE);
4. participação (FOR SHARE);
5. bolso(s), em ordem de id;
6. exemplar;
7. posições.

A participação vem depois da coleção, na mesma ordem de 5369/5370. Com isso, troca de papel, remoção e saída concorrentes ou esperam a escrita terminar, ou fazem a escrita ver o estado novo e ser recusada. Não há ciclo de travas.

A **5122 não foi ampliada**. Ela e as funções do titular 5272–5274 ficam byte a byte canônicas: md5 conferido no precheck e no postcheck da 5374. Esses md5 batem com os lidos no LIVE em LIVE_00 (P2, 2026-10-23) e LIVE_S2_90 (P3-B, 2026-10-27).

| Capacidade (E1-B1) | Titular | EDITOR de X | VIEWER / não membro / ex-membro / anon |
|---|---|---|---|
| Colocar carta | qualquer exemplar no local do fichário, em qualquer bolso (5272) | só exemplar **alocado a X e no local do fichário**, em bolso de X ou livre (5374) | ✘ (`COLLECTION_NOT_FOUND`; anon sem EXECUTE) |
| Mover / trocar | qualquer posição (5273) | só carta de X, de/para bolso de X ou livre | ✘ |
| Retirar | qualquer posição (5274, em lote) | só carta de X, um bolso por chamada | ✘ |
| Ver exemplares elegíveis | `get_my_collection_binder_unplaced` (5252) | `get_shared_binder_placeable_cards` (5373) | zero linhas |
| Alocar, desalocar, mudar local, condição, titularidade, excluir | ✔ (funções próprias) | ✘ (nenhuma escrita patrimonial existe na E1-B1) | ✘ |

## Classificação de bolsos (C-237) e proteção contra acesso cruzado

Para a coleção X, um bolso é classificado como:

- **OWN:** tudo o que existe nele é de X: carta alocada a X; reserva de X, sendo que reserva sem coleção pertence à proprietária (C-196); referência de espécie de X. Uma trava só conta como OWN se houver também carta ou reserva de X.
- **FREE:** sem carta, reserva, imagem, região mesclada, referência ou trava.
- **FOREIGN:** qualquer outro caso, inclusive bolso que **parece** vazio mas tem reserva de outra coleção, trava, imagem, região ou referência alheia, e bolso fora do fichário.

Recusas:

- **Bolso de terceiros e posição inexistente:** a **mesma** `SLOT_NOT_EDITABLE`. Ela não diz o que ocupa o bolso nem se ele existe.
- **Exemplar alheio, inexistente, sem coleção, de outra coleção ou em outro local:** a **mesma** `PHYSICAL_CARD_NOT_ELIGIBLE`. O EDITOR nunca descobre onde está um exemplar.

**Endereçamento por posição visível** (página, linha, coluna): as leituras compartilhadas (5315/5316) não expõem ids de bolso, e as escritas do EDITOR usam a mesma referência. Assim nenhum id interno de bolso chega ao EDITOR, e não há id de bolso para forjar.

## Leitura dos exemplares elegíveis (5373)

`get_shared_binder_placeable_cards(p_collection_id, p_limit default 96, p_offset default 0)`:

- **Quem recebe:** só o EDITOR ACTIVE de X, com X e a proprietária ativas. Os demais recebem zero linhas, sem exceção que permita enumerar.
- **O que lista:** só exemplares do titular que estão:
  - alocados a X;
  - em `storage_container_id` igual ao local do fichário;
  - fora de qualquer bolso.
- **Colunas:** `physical_card_id` (opaco, necessário para a escrita), mais os campos de exibição da 5315 (carta, número, Set, acabamento, idioma, imagem) e `total_count`.
- **Nunca:** local, condição, proveniência, valores, notas, Favoritos, Lista de desejos, ids do titular ou o resto do acervo.
- **Revalidação:** a escrita refaz todas as condições, sob trava.

## Operações (5374)

| RPC | Regras | Retorno |
|---|---|---|
| `editor_place_card_in_binder(coleção, página, linha, coluna, exemplar)` | Destino OWN ou FREE. Exemplar elegível relido sob trava (FOR UPDATE do exemplar, FOR SHARE da alocação). Mesmo bolso → UNCHANGED, sem evento. Outro bolso → `CARD_ALREADY_PLACED`. REPLACE só de carta de X | `ADD` \| `REPLACE` \| `UNCHANGED` |
| `editor_move_binder_card(coleção, origem, destino)` | Origem OWN com carta de X. Destino OWN ou FREE. Troca só com carta de X. Reservas e referências ficam no bolso | `MOVE` \| `SWAP` |
| `editor_remove_binder_card(coleção, posição)` | Bolso OWN com carta de X. Apaga só a posição: alocação, local físico, condição e acervo intactos (C-236) | `REMOVED` |

Para as três:

- bolso fixado de X → `SLOT_LOCKED`, como no titular;
- cada operação gera um evento com a coleção X registrada e o EDITOR como ator;
- **escrita direta (posicionamento):** só `collection_layout_slot_assignment`;
- **escrita de auditoria (decorrente):** um evento e seus itens em `binder_activity_event`/`binder_activity_item`, gravados pelas funções internas do histórico (5268 com a mudança da 5372). O cabeçalho da 5374 ("Só collection_layout_slot_assignment muda") refere-se às escritas diretas;
- **nenhuma escrita patrimonial:** alocação, local físico, condição, titularidade e acervo não mudam.

## Compatibilidade com o titular e dever de espelho

Optei por **funções dedicadas** em vez de um ramo nas funções do titular. O plano do `05d` deixava a forma para a proposta. Os motivos:

1. o titular fica byte a byte igual, sem regressão possível no caminho em produção;
2. o EDITOR precisa da coleção explícita (a 5273 não a recebe) e de endereçamento por posição;
3. a regra é outra: classificação por bolso, e não troca de "quem chama" por "titular".

A duplicação ficou limitada às instruções de escrita e aos itens do histórico. **Dever de espelho:** qualquer mudança futura nas escritas de 5272–5274 (tipos de evento, efeitos de item, erros) precisa ser repetida aqui. A verificação estática 12.1 confere os pontos comuns.

## Verificações

- **Estática** (executada, sem banco): `python3 -I -B static_check_e1b1.py` → **61/61 PASS** (2026-11-15).
- **Dinâmica** (pendente, sem execução autorizada): `5889` v1.1 → esperado **56/56**, sob protocolo controlado, depois da E1-A.

**Cenários cobertos pela 5889:**

- **Quem chama:** EDITOR autorizado; EDITOR de outra coleção no mesmo fichário; VIEWER; não membro; titular no caminho do EDITOR; membro removido; anon; troca de papel com efeito imediato.
- **Exemplares:** elegíveis; inelegíveis (outro local, sem coleção, de outra coleção, alheio, forjado).
- **Bolsos de terceiros:** carta, reserva, fixado vazio, posição inexistente.
- **Operações:** UNCHANGED; já posicionado; reserva própria; REPLACE; MOVE/SWAP; retirar.
- **Fichário com várias coleções:** nos dois sentidos.
- **Histórico:** ator e coleção registrados.
- **Titular e patrimônio:** titular intocado; alocações, locais, exemplares e participações intactos.

| S1–S10 | Situação depois da E1-B1 |
|---|---|
| S1, S2, S3 (carta, reserva, trava), S5, S6 (alocação e local), S7, S9 (leitura de elegíveis) | **Preparados na 5889, não executados** |
| S3: imagem, mesclagem, estado composto, convidada arquivada | Na 5889 v1.1 (seção 10), não executado |
| S3: referência de espécie | Só por inspeção: a fixture exige coleção Pokédex (E1-B3). É dependência de fixture, não vulnerabilidade |
| S4 (página e massa) | E1-C |
| S8 sequencial (rebaixamento, remoção) | Na 5889 (1.4, 1.7), não executado |
| S8 concorrente e S10 | **Pendentes**: exigem duas sessões com dados confirmados (estratégia E1-A §4) |

**Nenhum cenário foi comprovado dinamicamente.**

## Revisão de segurança (`CORE BINDER SECURITY REVIEW-02`, 2026-11-15)

Por inspeção. **Concorrência não aprovada por inspeção.**

- **Histórico (5372):**
  - o ator é sempre `auth.uid()`: não há parâmetro de autoria, e ninguém registra evento em nome de outro;
  - a coleção do evento é a que a RPC autorizou e travou (`p_collection_id`);
  - o teste exige EDITOR **ACTIVE** dessa coleção, do mesmo titular e participante do fichário. VIEWER, não membro e ex-membro são recusados;
  - `binder_activity_begin`/`add_item` não têm EXECUTE para a API, e o contexto é local à transação, sem caminho de cliente para alterá-lo;
  - o titular e os demais módulos mantêm o mesmo caminho (`v_owner = v_uid`), com o mesmo valor de `v_coll`.
- **Classificação:** os estados compostos são resolvidos por "qualquer elemento de terceiros = FOREIGN", em qualquer ordem. Imagem e mesclagem não coexistem com carta, reserva ou trava (gatilhos 5232/5238), por isso o bolso **parece** vazio na leitura mascarada e mesmo assim é recusado (5889 10.1–10.2).
- **Travas:** comparadas com 5272–5274, 5046, 5047, 5287–5289, 5305, 5306, 5369 e 5370. Nenhum ciclo encontrado:
  - a mudança de local (5287) e a saída do acervo (5289) travam exemplar e posição, sem travar proprietária, layout ou bolso, e só podem fazer a escrita do EDITOR encontrar a posição já apagada (→ `SLOT_EMPTY`/`FOREIGN`);
  - a troca de papel, a remoção e a saída esperam a trava da participação;
  - dois EDITORES de coleções do mesmo fichário serializam pela trava da proprietária.
- **Defeitos de código:** nenhum encontrado. Lacunas de cobertura e um risco documentado de forma imprecisa foram corrigidos (harness v1.1 e item 1 abaixo).

## Riscos e limitações

1. **Concorrência com mudanças de alocação do titular** *(corrigido na revisão REVIEW-02: a avaliação anterior superestimava o risco)*:
   - Alocar (5046) e desalocar (5047) travam a linha da coleção X com FOR UPDATE antes de tocar `collection_allocation`, e não existe UPDATE de alocação em nenhuma função.
   - A escrita do EDITOR segura X durante toda a operação: FOR UPDATE se X é a proprietária, FOR SHARE se é convidada.
   - Portanto, por inspeção, a alocação das cartas **de X** não muda entre a classificação e a escrita. Cartas de outras coleções só podem passar a "sem coleção", o que continua FOREIGN.
   - Não está provado dinamicamente; fica para S10.
2. **Serialização com o titular:** escritas do EDITOR travam a coleção proprietária como as do titular. Titular e EDITOR no mesmo fichário se alternam, sem paralelismo. É o comportamento esperado; o impacto real é medido em S10.
3. **md5 da 5268 (`binder_activity_add_item`):** derivado do arquivo canônico, sem leitura correspondente registrada no LIVE. A S0 de qualquer execução precisa confirmá-lo.
4. **Elementos não exercitados:** imagem, região e referência de espécie entram na classificação, mas não na fixture (L2). Coleção arquivada também não é exercitada (L4).
5. **Retirada:** é de um bolso por chamada. A retirada em lote do EDITOR, se for necessária, entra na E1-C.
6. **Interface:** E2 precisa chamar as RPCs por posição. As leituras compartilhadas já entregam posições.
7. **Dependência:** a E1-A precisa estar aplicada antes (5366), e a 5372 antes da 5374.
