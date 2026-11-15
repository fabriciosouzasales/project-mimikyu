# V1-13 · E1-D — Leituras compartilhadas seguras

| Campo | Valor |
|-------|-------|
| **Rodada** | `V1-13 / E1-D \| SECURE SHARED READS-01` (2026-11-15) |
| **Status** | **PROPOSTA LOCAL — NÃO EXECUTADA, NÃO APLICADA, NÃO HOMOLOGADA.** Nenhum SQL executado, nenhum harness rodado em banco, nenhum acesso ao LIVE, sem commit. Revisada em `SHARED READS PRIVACY AND CONTRACT REVIEW-02` (seção 13) e corrigida em `D14 CONTRACT REFINEMENT AND MINIMAL CORRECTION-03` (seção 14). **D14 APROVADA (opção B)** e implementada na `5388` v1.2. |
| **Base** | `main` em `17efd41` (E1-A … E1-C2 versionadas; D9–D13 aprovadas e formalizadas em `concept-decisions.md` 1.39). |
| **Contrato** | C-241 com **D12, D13 e D14 (APROVADAS)**, C-242, C-243, C-204, C-208, C-173, C-174, C-179; padrão das leituras compartilhadas da V1-12 (`5310`–`5321`). |
| **Arquivos** | `5323`, `5324`, `5388` v1.2 (migrations), `5894` v1.3 (harness, 29), `ROLLBACK_E1D.sql`, `static_check_e1d.py` (52). |

## 1. Inventário das leituras e lacunas

Toda leitura compartilhada decide o acesso por `collection_share_role` (`5302`): `OWNER` para o titular, `VIEWER` para **qualquer** participação `ACTIVE` (VIEWER ou EDITOR, E1-A), `PUBLIC` pela visibilidade, senão nada. As leituras da E1-D aceitam só `OWNER`/`VIEWER` — PUBLIC continua com as leituras públicas próprias (`5317`/`5318`/`5327`). A `5302` não muda (sem defeito material: ela já dá ao EDITOR exatamente o nível de leitura do VIEWER, e só isso).

| Superfície | Leitura | EDITOR hoje | Lacuna |
|---|---|---|---|
| Coleção, progresso, cartas | `5312`, `5310`, `5313` | ✔ (nível VIEWER; `5312` devolve `role`) | — |
| Fichário, páginas, imagens, capa | `5314`/`5321`, `5316`, `5326`, `5328`, `5329` | ✔ | — |
| Set padrão (posições) | `5320` | ✔ | — |
| Coleção livre | `5313`, fichário | ✔ | sem posições (por definição) |
| **Master Set (posições por acabamento)** | — | ✘ | **`5323` (esta etapa)** |
| **Pokédex (posições por espécie)** | — | ✘ | **`5324` (esta etapa)**; progresso já vem da `5310` (ramo REFERENCE_POSITION) |
| **Histórico do fichário** | só `5269` (titular) | ✘ | **`5388` (esta etapa)** |
| Leituras de apoio à edição | `5373` (E1-B1) etc. | ✔ (só EDITOR) | — |

Lacunas conhecidas fora do escopo (não bloqueiam a E1-D): lista de gerações do escopo da Pokédex para o filtro do participante (a grade já devolve `generation_code` por linha; a E2 decide se basta); dados de Wishlist, favoritos e valores continuam fora (C-243).

## 2. Contrato da leitura compartilhada do histórico (`5388`)

`get_shared_binder_activity(p_collection_id, p_categories, p_before_occurred_at, p_before_id, p_limit)` e `get_shared_binder_activity_status(p_collection_id)`.

- **Autorização no servidor**: `5302` ∈ {OWNER, VIEWER}; não membro, convite pendente/recusado, removido, PUBLIC e anônimo → zero linhas (sem EXECUTE para `anon`), indistinguível de "sem histórico". O titular recebe a **mesma** visão filtrada; o histórico integral dele continua na `5269`.
- **Fichário atual de X**, derivado no servidor (âncora em `collection_layout`, senão convidada em `collection_layout_guest`, regra da `5321`). Nenhuma chave de fichário vem do cliente. Sem fichário → nada (C-208: fichário desmontado, removido ou do qual X saiu fica só com o titular).
- **Pertencimento**: titular do evento = titular de X; `layout_key` = fichário atual; e **categoria A** (`collection_id` do evento = X) **ou categoria B, D14** (evento sem coleção registrada cujo autor gravado é o titular gravado). Evento registrado para outra coleção nunca entra. Detalhe na seção 14.
- **Lista positiva** por par tipo/origem — exatamente a lista de gravação do EDITOR (`5384`) = C-241 + D13: FICHARIO com E02–E05, E08–E10, E11–E15 e E21; CATALOGO com E16. L01 só pela regra da D12 (abaixo). Tudo o mais — E01, E06a/E06b/E07, E17–E20, sem coleção, de outra coleção, tipos futuros — fica oculto.
- **Atribuição por item, não só pelo cabeçalho** (`binder_activity_item.collection_id`, gravada pela `5379`):

  | Item | Visível ao participante de X quando |
  |---|---|
  | `CARD`, `RESERVATION`, `POCKET` | `collection_id` do item = X |
  | `PAGE` | o evento é de páginas/espaços (E11–E15) |
  | `COLLECTION`, `BINDER`, outros | nunca |
  | item do L01 | sempre o `CARD/INCORPORATED` (cópia do catálogo, sem exemplar) |

  A mesma regra (texto idêntico, conferido pela verificação estática 8.4) decide a existência do evento e a lista de itens.
- **Resumos e contagens** só dos itens autorizados: `item_count` = itens visíveis; `items` = até 50 visíveis com `ordinal` **renumerado** 1..n (sem lacunas que denunciem itens ocultos); `items_truncated` = visíveis > 50. O `summary` gravado (contagens do evento inteiro, chaves, ids) **não sai**.
- **Campos secundários**: não saem `detail` (pode conter `physical_card_id`, `collection_id`, `storage_container_id`, `condition_code`, tokens de plano), `collection_name`/`binder_name` gravados (identidade do fichário segue a `5321`), `owner_user_id`, `actor_user_id`, `layout_key`, `created_xact`. Mensagens de erro: só as de entrada (cursor e categoria, iguais à `5269`); falta de acesso nunca gera erro distinto.
- **Ator**: `actor_role` (`OWNER` → "Titular"; `PARTICIPANT` → "Participante"; nulo no L01) e `actor_display_name` = `user_profile.display_name` (nome de exibição público, inclusive de quem saiu — C-173). Nunca e-mail, nome de usuário ou id. Pela gravação (`5372`/`5379`), ator diferente do titular num evento de X só pode ser EDITOR ativo de X na época; logo nunca aparece identidade de participante de outra coleção.
- **Ordem e paginação**: `occurred_at desc, id desc`; cursor `(occurred_at, id)`; limite 1..50; categorias da `5269`/`5341`. `event_id` sai só como cursor (sequência global, sem significado por coleção).

## 3. Eventos que envolvem várias coleções

Um evento de X pode conter itens de outras coleções do mesmo titular (organização automática, espaços e páginas num fichário com convidadas, deslocamentos). Para o participante de X:

- itens de outras coleções **não aparecem** e **não contam** (contagem e ordinal recalculados);
- se **nenhum** item de X sobra, o evento inteiro some (sem "evento vazio" que revele atividade alheia);
- um evento cuja coleção registrada é outra (ex.: organização feita a partir da proprietária, vista por um membro da convidada) fica oculto, mesmo que tenha itens de X — a regra da C-241 é "coleção registrada = X";
- nenhum nome de coleção, nome de fichário, resumo ou detalhe do evento é devolvido.

## 4. D12 e D13 (APROVADAS)

- **D12 — atribuição confiável**: só eventos com `item_collection_recorded = true` (gravados pela `5379`). Eventos anteriores à `5379`, ou gravados com ela revertida (`ROLLBACK_E1B3`, R5379), ficam ocultos aos membros; nada é inferido nem reescrito (C-179). Titular íntegro (`5269`).
- **D12 — L01**: visível só quando a **origem** comprova a vinculação: `LEGACY_CATALOG_INCORPORATION`, origem `LEGADO`, sem ator, coleção do evento = X **e** linha de origem presente em `collection_layout_catalog_incorporation` (mesmo fichário, X e mesma chave — a linha permanece mesmo com a reserva liberada). Dado exposto: só a cópia de catálogo (nome, número, Set, acabamento). Sem a linha → oculto.
- **D12 — aviso de histórico parcial**: `get_shared_binder_activity_status` devolve `has_binder` e `history_may_be_partial`. Significado exato (v1.1): existe evento registrado para X neste fichário, **de um tipo da lista de permissão**, que a leitura omite **só** por falta de atribuição (não atribuído, ou L01 sem origem comprovada). Estrutura, acervo, eventos sem coleção e eventos de outras coleções nunca acendem o sinal. É **conservador**: diz que pode haver registro anterior não exibido; não conta, não prova e não identifica eventos ocultos (sem tipo, data ou quantidade). A interface (E2) pode também mostrar o aviso sempre; o booleano só evita mostrá-lo à toa.
- **D13 — `CARDS_AUTO_ARRANGED`**: na lista de permissão, filtrado pelos itens de X; oculto quando não atribuído ou quando nenhum item de X sobra. `PAGE` desse evento não é exibida (só nos eventos de páginas).

## 5. Master Set (`5323` · `get_shared_master_set_positions`)

Espelho da `5198` sem a parte que lê o acervo. Devolve posições (carta + acabamento, carta secreta), arte, satisfação, exemplares **desta** coleção e `total_count`; mesmo filtro (ALL/OWNED/MISSING), paginação (≤ 500, deslocamento ≤ 100.000) e ordem. Escopo e acabamentos do titular (`collection_master_set_finish`, C-239) e regra de satisfação inalterados (CTEs `positions`, `in_collection`, `in_by_card`, `filtered` e imagem idênticas à `5198`, verificação 7.1). **Removido**: `copies_available` e a CTE `available` (inventário do titular). Não lê inventário, local, condição (C-233), certificação, valores, outras coleções. Coleção que não é Master Set → zero linhas.

## 6. Pokédex (`5324` · `get_shared_pokedex_positions`)

Espelho da `5204` sem o acervo. Devolve espécies do escopo (Pokédex inteira ou gerações do titular), número nacional, geração, arte da espécie, satisfação, exemplares atribuídos **desta** coleção e a representante (principal, senão a atribuição mais antiga — só entre exemplares desta coleção, só dados de catálogo). Mesmo filtro, filtro por geração, paginação e ordem (CTEs `scope`, `links`, `assigned`, `page`, `rep`, arte e representante idênticas à `5204`, verificação 7.2). **Removidos**: `copies_available`, `copies_elsewhere`, `acervo_state` e a CTE `inv`. Nada permite inferir se o titular tem a espécie fora da coleção (coberto pelo harness 3.2, não executado: mudar o acervo muda a grade do titular e não a do participante). Progresso do participante: `5310` (inalterada).

## 7. Quatro modalidades

| Modalidade | Leitura do participante | Edição (já entregue) |
|---|---|---|
| Set padrão | `5320` (V1-12) | E1-B1/B2/C1/C2 |
| Master Set | **`5323`** + `5310` | E1-B1/B2/C1/C2 (novidades `5387`) |
| Coleção livre | `5313` + fichário (V1-12) | E1-B1/B2/C1/C2 |
| Pokédex | **`5324`** + `5310` | E1-B3 (`5380`), E1-C1 (`5383`) |
| Histórico (todas) | **`5388`** | gravação `5372`/`5379`/`5384` |

Leitura e edição seguem separadas: as leituras novas não usam `collection_member_role` (papel EDITOR) e não liberam nenhuma escrita; o EDITOR lê exatamente o que o VIEWER lê.

## 8. Matriz OWNER / EDITOR / VIEWER

| Leitura | OWNER | EDITOR ativo | VIEWER ativo | Pendente, recusado, removido, estranho, anônimo |
|---|---|---|---|---|
| Master Set `5323` | grade (sem disponíveis; os dele seguem na `5198`) | grade | grade | zero linhas / sem EXECUTE |
| Pokédex `5324` | grade (sem acervo; completo na `5204`) | grade | grade | idem |
| Histórico `5388` | visão filtrada (integral na `5269`) | filtrado por X | filtrado por X | idem |
| Estado `5388` | booleanos | booleanos | booleanos | idem |
| Coleção arquivada | mesma regra da `5312` (coberto pelo harness 6.2, não executado) | idem | idem | — |

## 9. Prova estática de não exposição

`static_check_e1d.py` (52 verificações) confere no texto: autorização pela `5302` antes de qualquer tabela (4.x); retorno sem coluna de acervo, local, condição, valor, e-mail, resumo, detalhe, nome gravado ou id interno (5.x); nenhuma leitura de inventário, local ou condição em `5323`/`5324` (6.x) e espelho fiel da parte segura (7.x); lista de permissão = C-241 + D13 = `5384` (8.1); pertencimento ao fichário atual e atribuição (8.2); L01 com origem (8.3); regra de item idêntica nos dois pontos (8.4); saída de itens restrita e ordinal renumerado (8.5); ator (8.6); ordem e cursor (8.7); estado (8.8). Prova por mutação (24 defeitos plantados, todos detectados, arquivos restaurados por md5): remover a atribuição, incluir E01 na lista, afrouxar a regra do segundo ponto, devolver `detail`, devolver `copies_available`, ler `inventory`, autorizar depois de ler, L01 sem origem, reversão incompleta, EXECUTE para `anon`, ignorar o fichário, usar `username`, mostrar PAGE na organização automática, fronteira por titular, contagem do harness, sinal parcial sem lista de permissão (dois modos). Omitir colunas não basta: o harness confere filtros, totais, agregados, mensagens e a ausência de textos privados na saída inteira (4.3).

## 10. Compatibilidade

Nenhuma função existente redefinida (verificação 9.1): `5302`, leituras do titular `5198`/`5204`/`5269`, gravação `5379`, gatilho `5384`, leituras da V1-12. Nenhuma tabela, índice, gatilho ou política. E1-A … E1-C2 intactas (12.1); tipos e origens de evento, C-234–C-244 e D9–D13 inalterados; nada de E2/E3. O harness `5894` 0.2 exige os md5 canônicos de `5302`, `5198`, `5204`, `5269` e `5379`.

| Função nova | md5 do corpo |
|---|---|
| `get_shared_master_set_positions` | `5754080699dba44e6ac362c5270e4051` |
| `get_shared_pokedex_positions` | `9e87eb412b72733e319aafb31240a3bd` |
| `get_shared_binder_activity` | `00ae54a9553a76fa564e2a335d966622` (v1.2) |
| `get_shared_binder_activity_status` | `31a016b254e10bedb841c7820d10dca2` (v1.2) |

## 11. Ordem de aplicação, reversão e harness

Aplicação (só com autorização específica, depois de E1-A … E1-C2): `5323` → `5324` → `5388`. Reversão: `ROLLBACK_E1D.sql` (R5388 → R5324 → R5323), só `DROP FUNCTION`; nenhum dado tocado; antes de `ROLLBACK_E1C2`.

Harness `5894` v1.3 (29 = 28 + F.2), sob protocolo controlado equivalente ao P1 (C-244), transação terminada em ROLLBACK: estrutura (0.1), inalterados (0.2), EDITOR nas leituras V1-12 (1.1), negados — estranho, pendente, removido, outro titular (1.2), anônimo (1.3), Master Set paridade/filtros/sem inferência (2.1–2.3), Pokédex idem (3.1–3.3), agregados 5310 × grades (3.4), lista exata de eventos, inclusive evento do titular sem coleção (4.1), D13 filtrado (4.2), não exposição na saída inteira (4.3), ator (4.4), VIEWER = EDITOR e titular íntegro (4.5), convidada (4.6), categorias e cursor (4.7), L01 com, sem, de outra coleção e de outro fichário (4.8), histórico parcial sem efeito de terceiros nem de estrutura (5.1), convidada desassociada (5.2), transferência de âncora (5.3), troca de papel e remoção (6.1), arquivada (6.2), sem escrita (7.1), resíduo zero (99.1). O histórico da fixture é gravado direto, na forma da `5379` (L3), para cobrir ramos que o uso normal só produz com dados antigos (D12) ou fichários de várias coleções (D13).

## 12. Riscos, desempenho e provas pendentes

- **Desempenho (não medido; nenhuma alegação)**: o histórico percorre `ix_bae_owner_layout_time` em ordem e filtra coleção, tipo e atribuição na linha; num fichário com muitas coleções e poucos eventos de X, encher uma página pode exigir percorrer muitos eventos. Itens pela PK `(event_id, ordinal)`, sem N+1 (uma consulta por página; agregação única). Índice candidato, **não criado**, só se a medição pedir: `binder_activity_event (owner_user_id, layout_key, collection_id, occurred_at desc, id desc)`. `5323`/`5324` custam o mesmo ou menos que `5198`/`5204` (sem varredura do acervo).
- **Medições para a E1-E**: histórico com evento de centenas de itens (organização automática) e 50 eventos por página; fichário com várias coleções e eventos de X esparsos; estado (`history_may_be_partial`) sem eventos não atribuídos (pior caso do EXISTS); Master Set no maior Set (referência da 5198: 336 posições, 300 ms); Pokédex nacional completa (3 páginas de 500).
- **Concorrência**: funções STABLE, autorização e leitura no mesmo instantâneo por chamada; revogação vale na chamada seguinte. Sem prova concorrente (S8 concorrente, S10).
- **Transferência de âncora** (revisão 02): a `5254`/`5292` preserva a chave do fichário e torna a antiga proprietária convidada. Os eventos de X anteriores continuam visíveis aos membros de X (X segue participando do mesmo fichário) e nunca aos da nova proprietária. A C-208 trata de fichário "transferido para fora" (outro dono) e não se aplica; nenhum corte temporal é necessário nem foi criado (harness 5.3).
- **Ressalva de produto para a E2**: sem `detail` e `summary`, a interface descreve cada evento pelo tipo e pelos itens visíveis; textos que dependiam do resumo do titular não se aplicam ao participante.

- **Medições adicionais para a E1-E** (revisão 02): coleção com eventos raros num fichário de muitas coleções (varredura até encher a página); evento com centenas de itens e poucos de X (agregação por evento); `history_may_be_partial` sem nenhum evento não atribuído (EXISTS até o fim do fichário).

**Pendências obrigatórias (inalteradas por esta etapa):** nenhuma migration da V1-13 aplicada; nenhum harness executado em banco; S1–S10 sem comprovação dinâmica; S8 concorrente e S10 pendentes; testes reais da API do Storage pendentes, inclusive envios simultâneos; PR-04B aberta; E1-E não iniciada; publicação da V1-13 bloqueada; nenhum ambiente isolado; nenhuma autorização para o LIVE. D12, D13 e D14 estão APROVADAS, não pendentes.

## 13. Revisão de privacidade e contrato (`SHARED READS PRIVACY AND CONTRACT REVIEW-02`)

Números entre parênteses nesta seção são verificações do harness `5894` (não executado) — cobertura prevista, não prova.

**C-241 × 5384 × 5388.** Tipos: C-241 + D13 (E02–E05, E08–E10, E11–E15, E16, E21; L01 por D12) = lista de gravação do EDITOR (`5384`: 14 FICHARIO + E16 CATALOGO) = lista de leitura (`5388`). Origens: todas as gravações reais do titular desses tipos usam as mesmas origens (FICHARIO; E16 CATALOGO — 5272–5296, 5344, 5360), então o pareamento tipo/origem não oculta evento legítimo. Leitura e escrita continuam separadas: a lista de leitura não depende de quem gravou (titular ou EDITOR) e não amplia o que o EDITOR grava.

**Divergência de efeito encontrada (não é defeito de código; é decisão de produto).** O titular grava **sem coleção** os eventos de mover/trocar (5273), retirar (5274), liberar reservas (5277), fixar/soltar (5278), páginas (5280–5286) e espaços (5283/5284); só colocar (5272), reservar (5276), novidades (5296) e organização automática (5344/5360) levam a coleção. Pela letra da C-241 ("coleção registrada = X"; "eventos sem coleção" ocultos), esses eventos do titular **nunca** aparecem aos membros, mesmo com todos os itens atribuídos a X pela `5379`. Os mesmos tipos feitos pelo EDITOR levam coleção e aparecem. A `5388` segue a letra (conservador) e o harness 4.1 (h14) fixa esse comportamento.

**D14 — proposta nesta rodada; APROVADA (opção B) na rodada seguinte — ver seção 14.** Opções apresentadas:
- **Opção A (atual, letra da C-241):** evento sem coleção registrada fica oculto. Membro vê dos atos do titular só colocar, reservar, novidades e organização automática.
- **Opção B:** evento do titular sem coleção registrada, gravado com atribuição por item (`item_collection_recorded`), aparece ao membro de X quando tem pelo menos um item de conteúdo (`CARD`/`RESERVATION`/`POCKET`) de X, com os mesmos filtros de item; eventos só de páginas sem coleção continuam ocultos (a página é estrutura compartilhada do fichário). Exige refinamento da C-241 ("coleção registrada = X **ou**, sem coleção registrada, item de conteúdo de X") e um ajuste pequeno na `5388` e no harness.
- Alternativa fora da E1-D: passar a gravar a coleção nos eventos do titular (mexe em 5273–5286, já canônicas; não recomendado nesta etapa).

**Correção aplicada (v1.1 da `5388`).** O sinal `history_may_be_partial` acendia para qualquer evento não atribuído de X, inclusive estruturais (E01, E17–E20) e de acervo (E06/E07), que ficariam ocultos de qualquer forma — aviso indevido. Agora só conta eventos dos tipos da lista de permissão (mesma lista, conferida na verificação 8.8). Leitura dos eventos inalterada (md5 de `get_shared_binder_activity` igual).

**Histórico × fichário.** Fichário atual derivado no servidor; transferência de âncora preserva a chave e os eventos de X (5.3); desassociação encerra a leitura (5.2); reassociação ao mesmo fichário volta a mostrar os eventos de X desse fichário (são de X, só com itens de X); fichário anterior de X (outra chave) não é exibido (C-241 "fichário atual"; C-208). Outra coleção: exige participação ativa na coleção pedida (5302) e coleção do evento = a pedida. Revogação: vale na chamada seguinte (6.1); sem prova concorrente.

**D12 e L01.** Não atribuídos ocultos (4.1 h7); L01 exige linha de origem com a mesma coleção, o mesmo fichário e a mesma chave — a chave primária `(layout_id, collection_id, item_key)` da `5263` comprova a coleção (4.8 l1–l4); dado do L01 é só catálogo; histórico do titular íntegro (4.5).

**Master Set e Pokédex.** Satisfação, progresso e contagens derivam só de `collection_allocation` desta coleção e (Pokédex) das atribuições dessas alocações; escopo, acabamentos e gerações são configuração da coleção; representante e idioma da imagem vêm de exemplar desta coleção; filtros e totais operam sobre essas mesmas linhas; ordem determinística (Master Set: `display_order` é NOT NULL e único por jogo, uma única posição secreta por carta; Pokédex: número e id da posição). Mudar o acervo fora da coleção não muda a resposta (2.3, 3.2); progresso compartilhado (5310) bate com as grades (3.4). Arquivada e revogação seguem a 5312/5302 (6.1, 6.2).

**Autor.** `user_profile.display_name` é o nome de exibição público que a V1-12 já expõe (`owner_display_name` na 5312) e que a C-241 autoriza; sem e-mail, nome de usuário ou id. A identificação vem do ator gravado como valor, não da participação atual: quem saiu continua identificado (C-173); conta excluída → nome nulo e a interface usa o papel.

## 14. D14 — formalização e correção mínima (`D14 CONTRACT REFINEMENT AND MINIMAL CORRECTION-03`)

**Decisão:** D14 opção B, APROVADA pelo proprietário (definitiva), formalizada como refinamento de C-241 (`concept-decisions.md` 1.40; matriz de C-234 só cita a D14 na linha do histórico).

**Regra na `5388` v1.2** (`get_shared_binder_activity`):

| Condição | Categoria A | Categoria B (D14) |
|---|---|---|
| Acesso | 5302 OWNER/VIEWER, fichário atual de X | idem |
| Cabeçalho | `collection_id = X` | `collection_id IS NULL` **e** `actor_user_id = owner_user_id` |
| Tipo/origem | lista de permissão (C-241 + D13) | a mesma lista |
| Atribuição | `item_collection_recorded` (ou L01 com origem, D12) | `item_collection_recorded`; L01 nunca |
| Item que torna o evento visível | conteúdo de X; PAGE nos eventos de páginas | só conteúdo de X (carta, reserva, bolso); PAGE nunca |
| Itens devolvidos, contagem, ordinal | só os visíveis | só os visíveis |
| Outra coleção no cabeçalho | oculto | — (não se aplica) |

Não há condição genérica "qualquer evento com item de X": um evento registrado para Y nunca entra, mesmo com item de X (D13/C-241 inalteradas). A regra de item visível continua uma só, nos dois pontos (verificações 8.4/8.9).

**Autoria histórica** (reconciliada em `D14 HISTORICAL AUTHORSHIP RECONCILIATION-04`, seção 15). A categoria B exige ator gravado = titular gravado, valores do instante do evento e imutáveis (C-179, C-204). A condição `owner_user_id = titular de X` vale para **todo** evento (A e B), não é específica da D14 e não usa um "titular atual" diferente do histórico. Ator nulo fora do L01 → oculto (h20). Ator ≠ titular sem coleção não pode ser gravado: a `5372`/`5379` exige coleção para ator diferente do titular e o gatilho `5384` recusa. Limitação: linha gravada por caminho privilegiado, fora das funções, não é distinguível — mesmo modelo de confiança da `5269`.

**Sinal de histórico parcial (`get_shared_binder_activity_status` v1.2).** Mesmas categorias da leitura. Acende quando há evento A ou B de tipo da lista de permissão omitido só por falta de atribuição, ou L01 de X sem origem. Eventos B **atribuídos** não acendem (ou aparecem, ou é certo que não têm item de X). Eventos B **não atribuídos** (anteriores à 5379) acendem por cautela: não se sabe se tinham item de X — o sinal continua um "pode haver", sem contagem, tipo ou data. Registrados para outra coleção, estruturais e de acervo nunca acendem.

**Harness `5894` v1.2 (29).** Fixture: h14 (titular, sem coleção, item de CF → visível), h17 (sem coleção, só CG → oculto a CF, visível a CG), h18 (sem coleção, itens de CG e CF → cada coleção vê só o seu), h19 (sem coleção, só PAGE → oculto), h20 (sem coleção, ator nulo → oculto), h16 (sem coleção, não atribuído → oculto; acende o sinal de CM). Verificações afetadas: 4.1, 4.6, 4.7, 4.8, 5.1, 5.3, 6.1; nova 4.9 (filtragem e contagem por coleção no evento misto, autoria Titular). Preservados: EDITOR (h9), registrado para outra coleção (h4), não atribuído (h7), L01 (l1–l4), histórico integral do titular (4.5). Não executado.

**Master Set e Pokédex:** `5323`/`5324` inalteradas (md5 iguais).

## 15. Titularidade histórica × atual (`D14 HISTORICAL AUTHORSHIP RECONCILIATION-04`)

**Semântica real:**

| Conceito | Onde está | Pode mudar? |
|---|---|---|
| Titular do evento | `binder_activity_event.owner_user_id`, gravado pela 5268/5379 a partir do dono da coleção-âncora no instante (C-204) | não (imutável, C-179) |
| Autor do evento | `actor_user_id`, `auth.uid()` no instante | não |
| Titular da coleção | `collection.owner_user_id` | **não**: gatilho de identidade estrutural `5032` ("owner_user_id é imutável"); transferência de titularidade de coleção é fluxo futuro não modelado (C-141, C-156) |
| Titular do fichário | dono da coleção-âncora (`collection_layout.collection_id`) | a âncora muda (5254), o dono não: âncora e convidadas são sempre do mesmo dono (5229, gatilho "convidada e proprietária precisam ser do mesmo dono"; 5254 "outra coleção do mesmo usuário") |
| Transferência de âncora | `transfer_my_binder_ownership` (5254/5292) | troca a coleção-âncora; **não** é transferência de titularidade |

**Parecer:** a condição `e.owner_user_id = titular de X` está **correta e é mantida sem alteração de código**.
- **Não exclui evento legítimo:** todo evento de um fichário em que X participa foi gravado com o dono da âncora daquele instante. Pelo modelo vigente, esse dono é sempre o dono de X (titular imutável e fichário de um só dono), inclusive depois de transferências de âncora (harness 5.3). Não existe, no domínio atual, titular histórico diferente do titular atual.
- **Fundamento contratual:** C-204 (o histórico pertence ao titular do evento, nunca recalculado) e C-208 (fichário transferido para fora: histórico só com o titular dos eventos, **nunca pelo novo dono nem por terceiros**). Se um dia houver transferência de titularidade (C-156), a mesma condição já entrega o que a C-208 exige: membros do novo dono não veem eventos do antigo.
- **Proteção real:** é a barreira que impede uma linha com outro titular, gravada no mesmo `layout_key`, de aparecer a membros de X só porque o autor é o titular *dela* (harness h13 na categoria A, **h21** na categoria B). Sem ela, a regra B ("ator = titular gravado") aceitaria qualquer titular. Também é a primeira coluna do índice `ix_bae_owner_layout_time`.
- **Não autoriza nada sozinha:** acesso pela 5302 e atribuição por item continuam obrigatórios; a identidade do autor nunca dá acesso a evento de outra coleção (registrado para Y → oculto).

**Dependência futura (registrada, não implementada):** hoje a titularidade da coleção é imutável (5032) e a transferência de âncora (5254) não é transferência de titularidade. Se a transferência de titularidade de coleção (C-156) for implementada, a autorização do histórico compartilhado (`5388`, categorias A e B e o sinal de histórico parcial) **precisa ser revista** no mesmo ciclo, junto com a C-208.

**Harness:** h21 acrescentado (linha forjada, impossível no domínio — por isso só como defesa: titular e autor C, sem coleção, item de CF, no fichário de CF → oculto). Titularidade atual distinta da histórica **não** foi simulada, porque o domínio não permite (5032). Total inalterado: 29.

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Proposta local (2026-11-15, `V1-13 / E1-D \| SECURE SHARED READS-01`).** `5323`, `5324`, `5388`, `ROLLBACK_E1D`, harness `5894` (26), `static_check_e1d.py` 47/47 com prova por mutação. Nada executado. |
| 1.1 | **Revisão de privacidade e contrato (2026-11-15, `SHARED READS PRIVACY AND CONTRACT REVIEW-02`).** `5388` v1.1: sinal de histórico parcial restrito à lista de permissão. D14 (eventos do titular sem coleção) proposta, aguardando decisão. Transferência de âncora, L01 com origem insuficiente, sinal parcial e agregados cobertos pelo harness `5894` v1.1 (28), não executado. `static_check_e1d.py` 50/50, 17 mutações detectadas. Nada executado. |
| 1.2 | **D14 aprovada e implementada (2026-11-15, `D14 CONTRACT REFINEMENT AND MINIMAL CORRECTION-03`).** `5388` v1.2 (categoria B: evento do titular sem coleção, atribuído, com item de conteúdo de X; estado com as mesmas categorias), harness `5894` v1.2 (29), `static_check_e1d.py` 51/51, 22 mutações detectadas. Nada executado. |
| 1.3 | **Titularidade histórica reconciliada (2026-11-15, `D14 HISTORICAL AUTHORSHIP RECONCILIATION-04`).** Condição de titular mantida (titular de coleção imutável, fichário de um só dono; C-204/C-208); sem mudança de código na `5388`; harness `5894` v1.3 (h21, total 29); `static_check_e1d.py` 52/52, 24 mutações. Nada executado. |
