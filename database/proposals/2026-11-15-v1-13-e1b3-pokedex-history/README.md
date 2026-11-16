# V1-13 · E1-B3 — Pokédex pelo EDITOR e fundação do histórico compartilhado (5378–5380)

| Campo | Valor |
|---|---|
| **Estado** | **PROPOSTA LOCAL — NÃO EXECUTADA, NÃO APLICADA, NÃO HOMOLOGADA.** Preparada em `V1-13 / E1-B3 \| POKÉDEX AND ACTIVITY HISTORY FOUNDATION-01` e revisada em `HISTORY INTEGRITY REVIEW-02` (2026-11-15). Nenhum SQL executado, nenhum acesso ao LIVE, nenhum ambiente, nenhuma conta. Prova dinâmica (5891) **pendente**. |
| **Base** | HEAD `b1fb4c1` (E1-A `a40c707`, E1-B1 `b19ee93`, E1-B2 `b1fb4c1`, todas sem execução). Depende de E1-A, E1-B1 e E1-B2 aplicadas. |
| **Contrato** | C-234, C-237 (classificação de bolsos), C-241 (histórico compartilhado), C-242 (Pokédex), C-243, C-244. |
| **Validação** | Sem ambiente isolado; só sob protocolo controlado e com autorização específica. S8 concorrente, S10 e PR-04B pendentes. |
| **Fora do escopo** | Referências de espécie em massa e demais operações de página/massa (E1-C), leitura do histórico e leituras 5323/5324 para membros (E1-D), interface (E2/E3), homologação (E1-E), mesclagem nova, campo de objetivo, limpeza de órfãos. |

## Arquivos

| Arquivo | O que faz |
|---|---|
| `5378_fix_binder_slot_editor_scope_species_reference.sql` | Corrige a classificação da 5371: bolso com referência de espécie de X passa a ser OWN (uma linha) |
| `5379_attribute_binder_activity_items_to_collection.sql` (v1.1) | Coleção de cada item do histórico, marca de atribuição por evento e recusa de contexto forjado (sobre a 5372); reaplicável sobre colunas preservadas |
| `5380_create_editor_pokedex_position_writes.sql` | Posição e representante Pokédex pelo EDITOR, entre exemplares já alocados |
| `5891_validate_editor_pokedex_history_HARNESS.sql` | Prova dinâmica: 32 verificações + F.2 (GATE 33). **Não executada** |
| `ROLLBACK_E1B3.sql` (v1.1) | Reversão R5380 → R5379 → R5378, com cópia literal dos corpos da 5372 e da 5371; preserva o histórico. R5379-D opcional, só antes de uso |
| `static_check_e1b3.py` | Verificação estática, 42 verificações |

Numeração conferida: o último número usado era `5377` (E1-B2) e o último harness, `5890`.

## Pokédex: operações do EDITOR (5380)

O contrato (C-242) dá ao EDITOR três capacidades na Pokédex. Duas entram aqui; a terceira é operação em massa.

| Capacidade (C-242) | Onde | Situação |
|---|---|---|
| Mudar a posição de um exemplar **já alocado** (6122/6124) | `editor_set_pokedex_position_assignment`, `editor_remove_pokedex_position_assignment` | **Preparada** |
| Escolher o representante entre exemplares já alocados (6125) | `editor_set_pokedex_position_primary_representative`, `editor_clear_pokedex_position_primary_representative` | **Preparada** |
| Aplicar, remover, mostrar ou ocultar referências de espécie (C-199) | 5258 (`apply/clear/set_..._visibility`) | **E1-C.** Toda operação da 5258 vale para o fichário inteiro; pela C-237 é operação em massa, só no fichário que atende só X |

- **Base:** espelho de 6122, 6124 e 6125/6126, com a coleção explícita. As funções do titular ficam byte a byte iguais (md5 no pre/postcheck).
- **Autorização:** `assert_collection_editor` (5376): EDITOR ACTIVE de X; trava coleção → participação; arquivada só depois de autorizado.
- **Modalidade:** X precisa ser Pokédex → senão `NOT_POKEDEX_COLLECTION`.
- **Exemplar:** precisa estar **alocado a X**; a alocação é travada depois da coleção (mesma ordem de 6124/6125). Sem alocação, de outra coleção, de outra conta ou inexistente → a mesma recusa `PHYSICAL_CARD_NOT_ELIGIBLE` da E1-B1.
- **Posição:** da Pokédex de X. Sem correspondência de espécie, exige confirmação (`USER_OVERRIDE`, com o EDITOR registrado em `assigned_by_user_id`, como o gatilho 6118 exige). Mesma posição → `UNCHANGED` antes de qualquer validação (regra v1.1 da 6122). Mover = DELETE + INSERT; o representante antigo sai em cascata (6120).
- **Representante:** só exemplar de X com posição; limpar só posição de X; repetições → `UNCHANGED`.
- **Identificação:** o EDITOR usa o `physical_card_id` que as leituras compartilhadas já devolvem. Nunca recebe `collection_allocation_id`.
- **Nunca:** alocar, desalocar, mudar local ou condição, ler o acervo, mexer em Set, escopo, política ou titularidade. A 5380 só escreve em posição e representante.
- **Posicionamento visual × alocação:** posição Pokédex e representante são **dados da coleção**, não do fichário, e não mudam patrimônio. A atribuição automática da alocação (6119) continua só com o titular, porque só ele aloca.
- **Histórico:** o titular também não registra evento para posição e representante (não são eventos do fichário, C-201–C-209). Mantido igual; registrar exigiria tipo de evento novo (contrato).

## Referência de espécie no bolso (5378)

- **Defeito concreto:** o cabeçalho da 5371 diz que o bolso com referência de espécie de X é OWN, como manda a C-237. O corpo, porém, só recusava a referência de outra coleção e deixava a de X como FREE.
- **Efeito:** o EDITOR da Pokédex proprietária não conseguia fixar nem soltar um bolso que só tem a referência de X (fixar/soltar exigem OWN na 5375).
- **Correção:** uma linha. Colocar, mover para, reservar e liberar não mudam (aceitam OWN e FREE).
- **Referência de outra coleção:** continua FOREIGN. O EDITOR de uma convidada nunca usa bolso rotulado pela Pokédex proprietária.
- **Arquivo da E1-B1 preservado:** a correção é uma migration nova (precheck pelo md5 da 5371). Antes da aplicação, o proprietário pode preferir incorporá-la à 5371.

## Histórico: modelo de eventos e itens (5379)

| Elemento | Antes (5268/5372) | Agora (5379) |
|---|---|---|
| Evento | titular, ator, coleção do evento, resumo | + `item_collection_recorded` (true para todo evento novo) |
| Item | carta, posições, detalhe | + `collection_id` (valor, sem FK, nunca reescrito) |
| Ator | `auth.uid()`; ≠ titular só como EDITOR ACTIVE da coleção do evento (5372) | igual |
| Contexto | `event_id` aceito como veio | precisa ser desta operação: mesmo fichário, mesmo ator, gravado nesta transação |

**Como a coleção de cada item é obtida** (no servidor, no instante da gravação, só do conteúdo real):

| Item | Coleção |
|---|---|
| CARD | alocação vigente do exemplar (`physical_card_id` do detalhe) |
| RESERVATION | coleção registrada na reserva (copiada pela 5275/5279); sem coleção registrada = proprietária do fichário (C-196) |
| POCKET (fixar/soltar) | conteúdo do bolso na ordem da classificação: carta (a alocação dela, ou nenhuma), senão reserva, senão referência de espécie |
| POCKET (imagem deslocada) | nenhuma (imagem é do titular) |
| PAGE, COLLECTION, BINDER | nenhuma (estrutura do fichário) |

- Coleção de outro titular → nenhuma.
- Nenhum valor vem de parâmetro do cliente nem do contexto.

**Isolamento e atribuição cruzada:**

- **EDITOR como ator:** todo item de carta, reserva ou bolso precisa ser da coleção do evento. Itens estruturais são recusados (`BINDER_ACTIVITY_CROSS_COLLECTION`). É defesa em profundidade: a 5374/5375 já só tocam bolsos de X, e uma futura operação da E1-C que tente deslocar conteúdo de terceiros aborta.
- **Contexto forjado:** quem conseguisse escrever no `mmkyu.binder_activity_ctx` (não é possível pela API) e apontasse o `event_id` de outro evento é recusado (`BINDER_ACTIVITY_FORGED_CONTEXT`). Coleção forjada de que o ator não é EDITOR já era recusada pela 5372.
- **Titular:** mesma gravação; ganha a coleção por item. A única recusa nova é a de contexto forjado, que nenhuma função instrumentada produz.
- **Privacidade:** nada novo é exposto. A leitura do titular (5269) não muda e não devolve as colunas novas.
- **Custo:** até 3 leituras por índice a mais por item. Eventos grandes (organização automática) ficam proporcionalmente mais lentos; não medido.

## Eventos com várias coleções

Um evento do titular pode ter itens de várias coleções (por exemplo, trocar a carta de CP com a de CX, ou um deslocamento de página). A partir da 5379, cada item carrega a própria coleção (5891 5.3).

**Regras para a leitura de membros (E1-D), registradas aqui como fundação, não implementadas:**

1. O membro de X vê só eventos com `collection_id = X` e tipo da lista de permissão da C-241.
2. Desses, só os itens CARD, RESERVATION e POCKET com `collection_id = X`, mais os itens PAGE (estrutura neutra de página) dos eventos de página permitidos.
3. **`summary`, contagens e `collection_name` de outras coleções nunca são devolvidos crus:** contagens e resumos são recalculados dos itens visíveis. O resumo gravado pode somar itens de terceiros.
4. Item sem coleção (bolso vazio fixado, imagem, exemplar sem coleção) nunca aparece para membro.

## Histórico anterior

- **Situação:** eventos gravados antes da 5379 (ou com ela revertida) têm `item_collection_recorded = false` e itens sem coleção.
- **Regra da gravação (implementada):** nenhuma atribuição retroativa. As tabelas são imutáveis e nada é inferido; a 5379 não faz UPDATE no histórico (5891 0.4).
- **Leitura de membros: decisão D12, PENDENTE** (abaixo). Nada aqui a presume aprovada; a E1-D só começa depois dela.

## Cobertura das quatro modalidades

| Modalidade | Gravação do histórico | Particularidades |
|---|---|---|
| Set padrão | carta por alocação; reserva por coleção registrada | reservas da montagem sem coleção = proprietária |
| Master Set | idem; acabamento fica no item, como antes | escopo e acabamentos continuam do titular (C-239) |
| Coleção livre | idem | sem posições de catálogo; nada específico |
| Pokédex | idem, e o bolso com referência de espécie de X é de X | posição e representante são da coleção e não geram evento (igual ao titular) |

As leituras de participante de Master Set (5323) e Pokédex (5324) continuam na E1-D.

## Compatibilidade

- **E1-A, E1-B1, E1-B2:** arquivos intactos. A 5378 exige o corpo da 5371, a 5379 o da 5372 e a 5380 a função da 5376.
- **Ordem de aplicação:** E1-A → E1-B1 → E1-B2 → E1-B3.
- **Harnesses:** ver a matriz em "Reversão e compatibilidade dos harnesses".
- **Funções do titular intocadas:** 6122, 6124, 6126, clear da 6125 (md5 derivados dos arquivos; confirmar na S0), 5272, 5273, 5276, 5278 e 5122.
- **Reversão:** `ROLLBACK_E1B3` vem antes de `ROLLBACK_E1B2`/`ROLLBACK_E1B1`. Devolve os corpos da 5372 e da 5371 byte a byte e preserva o histórico (ver abaixo).

## Reversão e compatibilidade dos harnesses

**Reversão da 5379 (`ROLLBACK_E1B3` v1.1):**

| Situação | O que fazer | Efeito |
|---|---|---|
| Antes de qualquer uso | R5379; opcionalmente R5379-D | gravação volta à 5372; R5379-D remove as colunas porque estão vazias |
| Depois de eventos reais | só R5379 | a escrita da atribuição para; colunas e histórico gravado ficam; R5379-D recusa |
| Desativar sem destruir | R5379 | mesmo efeito: a 5372 nunca escreve nas colunas novas |
| Reaplicar depois | 5379 de novo | o precheck aceita as colunas existentes só com a forma exata; `ADD COLUMN IF NOT EXISTS` |

- **Compatibilidade das funções antigas** com a estrutura ampliada: a 5372 e a 5268 não nomeiam as colunas novas.
  - O item fica NULL e o evento false ("não atribuído"), nunca com uma atribuição falsa.
  - A leitura do titular (5269) não as lê.
  - Nenhuma correção era necessária nas funções antigas.
- **Rótulo:** o evento gravado com a 5379 revertida tem a mesma marca do histórico anterior e cai na mesma regra de leitura (D12).

**Matriz de harnesses:**

| Harness | Depois da E1-B1 | Depois da E1-B2 | Depois da E1-B3 (estado final) |
|---|---|---|---|
| 5888 (E1-A) e 5861 (regressão) | válido | válido | válido (não fixa a gravação nem a classificação) |
| 5889 v1.2 (E1-B1) | válido (0.4 = 5372) | válido | **válido**: 0.4 aceita 5372 ou 5379; as demais verificações não dependem de referência de espécie nem da coluna nova |
| 5890 (E1-B2) | — | válido | válido: não fixa a gravação nem a classificação; o fixture não tem referência de espécie; os eventos do EDITOR só têm itens da coleção dele |
| 5891 (E1-B3) | — | — | válido: fixa 5378, 5379, as funções do titular e a cadeia nova |

- **Regressão no estado final:** rodar 5888, 5861, 5889, 5890 e 5891, nessa ordem, cada um sob o protocolo controlado (todos terminam em ROLLBACK por sentinela).
- **O que a regressão cobre:** os eventos do EDITOR de 5889/5890 passam pela guarda nova da 5379 (itens só da coleção do evento) e pela classificação da 5378. É a prova de que nenhuma operação da E1-B1/E1-B2 quebra com a E1-B3.
- **Única adaptação:** o 0.4 da 5889, porque o md5 mudou por desenho. O teste não foi dado como obsoleto; passou a aceitar a versão que o estende.

## Revisão de integridade do histórico (`HISTORY INTEGRITY REVIEW-02`)

| Cenário | Resultado da inspeção |
|---|---|
| Carta registrada depois da desalocação (acervo, E06/E07, exclusão de exemplar) | item sem coleção. Tipos ocultos aos membros de qualquer forma |
| Carta de Y em bolso do fichário de X (titular) | item atribuído a Y, nunca a X |
| Bolso com carta sem coleção e reserva de X | item sem coleção (a carta decide, como na classificação) |
| Reserva sem coleção registrada | proprietária do fichário (C-196), igual à classificação |
| Liberação (5277) | gravada antes da exclusão da reserva: coleção correta |
| Incorporação com atualização (5296, detalhe sem coleção) | coleção da reserva no bolso no momento, ou nenhuma; nunca outra |
| Itens de página | sem coleção (estrutura neutra) |
| **Evento estrutural com itens atribuídos** (E01 montagem, E19 desmontagem: cartas de X) | **risco de confusão identificado:** a coleção do item não concede visibilidade. A leitura de membros precisa filtrar antes pela lista de tipos da C-241 (E1-D). Registrado no cabeçalho e no comentário da coluna |
| EDITOR registrando item de outra coleção, sem coleção ou estrutural | recusado (`BINDER_ACTIVITY_CROSS_COLLECTION`) |
| Contexto forjado com evento de outro ator, fichário ou transação | recusado (`BINDER_ACTIVITY_FORGED_CONTEXT`) |
| Contexto forjado com evento do próprio ator, mesmo fichário e mesma transação | aceito, mas só acrescenta itens do mesmo ator e da mesma coleção. Exige escrever o GUC do contexto, impossível pela API. Residual aceito |
| Titular | mesma gravação, mais a coleção por item. Leitura 5269 inalterada |
| Histórico anterior | nenhuma atribuição retroativa (5891 0.4) |

**Recomendação para a E1-C (não implementada):** restringir, na gravação, os tipos de evento aceitos com ator EDITOR aos da C-241. Nenhuma função do EDITOR abre evento estrutural hoje, então não há defeito; fica como defesa em profundidade.

## Revisão das operações Pokédex

- **Exemplar já alocado:** a alocação de X é exigida e travada; nada aloca, desaloca ou atribui automaticamente (6119 continua só com o titular).
- **Espécie:** `SPECIES_MATCH` só com carta Pokémon, espécie resolvida e igual à da posição; caso contrário, confirmação explícita, com o EDITOR registrado.
- **Terceiros:**
  - exemplar de outra coleção ou conta → recusa única;
  - posição de outra Pokédex → `POKEDEX_POSITION_NOT_FOUND`;
  - representante só entre alocações de X (e o gatilho 6121 confere).
- **Escopo de gerações:** como no titular (6122), a posição não é conferida contra o filtro de gerações da coleção. Comportamento herdado, não ampliado.
- **Posições concorrentes** (por inspeção, sem prova):
  - todas as escritas do EDITOR travam a coleção antes;
  - a 6122 do titular trava só a alocação e espera, ou é esperada, na mesma linha;
  - o representante segue coleção → alocação → linha do representante, igual à 6125/6126;
  - a cascata da 6120 e o `FOR UPDATE` do representante não formam ciclo.
- **Local, condição, titularidade:** a 5380 só escreve em posição e representante (verificação estática 5.5 e 5891 9.1).
- **Titular:** 6122, 6124, 6126 e o clear da 6125 intocados (5891 8.1).
- **Histórico:** posição e representante **não geram eventos** no contrato atual, assim como no titular. Nenhum tipo novo criado.

## Verificações

- **Estática** (executada, sem banco): `static_check_e1b3.py` → **42/42 PASS**. Dez mutações aplicadas e desfeitas, todas detectadas: classificação, alocação de X, guarda do EDITOR, contexto forjado, privilégio para anon, escrita em alocação, DROP na reversão padrão, guarda do R5379-D, forma das colunas na reaplicação e mudança extra na 5889.
- **Dinâmica** (pendente): `5891` → **33/33** esperado, sob protocolo controlado, depois de E1-A, E1-B1 e E1-B2.

**Cenários cobertos pela 5891 (não executados):**

- **EDITOR autorizado:**
  - criar, mover e retirar posição;
  - confirmação sem espécie correspondente;
  - representante: definir, trocar, limpar e cascata.
- **Recusas:**
  - VIEWER, estranho, ex-membro, titular pelo caminho do EDITOR e anon;
  - exemplar sem alocação, de outra coleção, de outra conta ou inexistente;
  - EDITOR de coleção livre e EDITOR de outra coleção;
  - posição inexistente.
- **Referência de espécie:** OWN para a Pokédex proprietária, FOREIGN para a convidada; fixar e soltar pelo EDITOR de CP; convidada recusada.
- **Histórico:**
  - coleção por item nos eventos do EDITOR e do titular;
  - evento com duas coleções;
  - reserva sem coleção (C-196);
  - bolso vazio sem coleção;
  - contexto forjado (evento alheio e coleção alheia);
  - nenhuma atribuição ao histórico anterior.
- **Revogação:** EDITOR rebaixado perde tudo na hora e nenhum evento é gravado depois.
- **Titular e patrimônio:** titular intocado; nenhuma mudança de alocação, local ou condição.
- **Arquivada:** recusa.

| S1–S10 | Situação depois da E1-B3 |
|---|---|
| S1 (Pokédex), S2, S3 (referência de espécie), S6, S7, S9 (gravação) | **Preparados na 5891, não executados** |
| S3 | antes só por inspeção; agora com fixture Pokédex na 5891 |
| S9 (leitura de membros) | E1-D |
| S8 concorrente (inclusive titular × EDITOR na Pokédex) e S10 | **Pendentes** |

## Decisões de produto

- **D9, D10, D11:** seguem propostas, aguardando decisão do proprietário. Não tocadas aqui.
- **D12 — PENDENTE de decisão do proprietário** (necessária antes da E1-D; não bloqueia a E1-B3): histórico anterior à atribuição por item.
  - **Proposta:** eventos anteriores à 5379 não são exibidos aos membros, com aviso de histórico parcial. Exceção L01 somente quando a origem e a atribuição estiverem comprovadas e os dados puderem ser filtrados conforme a C-241.
  - **Evidência disponível para o L01** (para a decisão, não aplicada): cada L01 tem um único item e foi gravado pela 5270 com a coleção do registro de origem no evento.
  - **Alternativa:** mostrar cabeçalhos antigos de X sem itens, marcados como incompletos.
  - **Por que é decisão:** a C-241 lista quais eventos o membro vê, mas não trata eventos sem coleção por item. A proposta mostra menos do que a lista permite.
  - **Não é decisão aprovada.**

## Riscos

1. **Concorrência:**
   - ordem de travas por inspeção: coleção → participação → alocação, igual a 6124/6125;
   - a 6122 do titular trava só a alocação, sem ciclo com o EDITOR;
   - **não comprovada sem S8/S10.**
2. **md5 não confirmados no LIVE:** 6122, 6124, 6126 e o clear da 6125 foram derivados dos arquivos. A S0 precisa confirmá-los.
3. **Custo da gravação:** leituras extras por item, não medidas em eventos grandes.
4. **Rollback da 5379:** a reversão padrão não apaga nada. O R5379-D só remove colunas vazias (antes de qualquer uso) e recusa depois de uso real.

## Estado (2026-11-15, `LOCAL COMMIT AND CLOSEOUT-03`)

| Item | Situação |
|---|---|
| E1-A, E1-B1, E1-B2, E1-B3 | preparadas e versionadas localmente |
| Migrations | nenhuma aplicada |
| Harnesses | nenhum executado em banco |
| S1–S10 | sem comprovação dinâmica |
| S8 concorrente e S10 | pendentes |
| Testes da API do Storage | pendentes |
| PR-04B | aberta |
| D9, D10, D11, D12 | sem aprovação formal; D12 a resolver antes da E1-D |
| E1-C | restringir os tipos de evento que o EDITOR pode produzir (requisito registrado) |
| Publicação da V1-13 | bloqueada |
| Ambiente isolado | nenhum |

## Correção E2-D1 (2026-11-15, `V1-13 / E1-E2 | CANONICAL BASELINE RECONCILIATION AND G2 CORRECTION-02`)

O md5 conferido da função do titular `set_pokedex_position_assignment` era o da 6122 (`b2ba1c7de00420c15733a4d2f3e0bf43`), mas o corpo canônico vigente é o da 6123 (`8c572182a03025503e993e5ecc25e07a`, CONFIRMADO EXECUTADO). Corrigidos só esses pinos: 5380 v1.1 (pre e postcheck), 5891 v1.1 (0.3) e `static_check_e1b3.py` (`OWNER_DEX` → 6123). A função do EDITOR já trazia as quatro correções da 6123 (confirmação fail-closed, colunas sem ambiguidade, trava coleção → alocação, coleção REFERENCE_BASED explícita) e não mudou. Detalhe e comparação funcional: `../2026-11-15-v1-13-e1e-security-evidence/e1e2/README.md` §2.
