# V1-13 · E3-6 / S4 — Auditoria colaborativa (D-E3-8): especificação contratual

| Campo | Valor |
|---|---|
| **Rodada** | `E3-6 / S2 + S4 — CONTRACT CONSOLIDATION, IMPLEMENTATION PREPARATION & GOVERNANCE OPTIMIZATION-01` (2026-11-27) |
| **Status** | **S4-a / 5394 EXECUTADA NO LIVE / CANÔNICA (2026-11-27 13:35:15Z)**: PRE, migration e POST com PASS (executor v1.4); nenhum evento; captura inerte com a barreira CLOSED; evidências em `S4A_5394_DEPLOY_EVIDENCE_2026-11-27.md`. Sequenciamento aprovado 5394 → 5392 → 5395; **a S4 não está concluída** (D-E3-8 obrigatória). |
| **Decisão** | D-E3-8 / P0-B: auditoria obrigatória de posição e representante da Pokédex e das referências de espécie, para titular e EDITOR. Ampliação aprovada em 2026-11-26. |
| **Conferido** | `database/schema/` 5267–5269 (histórico do fichário), 5341 (`binder_activity_category`), 5258, 5046, 5047, 6119, 6122–6126; `g1/protected/` 5380, 5383, 5388; `e1c2-remaining-bulk-operations/5384` (gatilho `trg_bae_editor_event_type`). |
| **Desbloqueia** | 5392 (S2), que depende da primitiva de registro desta especificação. |

## 1. Destino dos eventos — dois fluxos, um por natureza do dado

| Operações | Natureza | Destino | Motivo |
|---|---|---|---|
| Posição e representante da Pokédex (6122–6126 do titular, 5392 do EDITOR) | dado **da coleção**, sem fichário | **novo** `collection_activity_event` | `binder_activity_event` exige `layout_key NOT NULL`; uma coleção Pokédex pode não ter fichário |
| Referências de espécie (5258 do titular, 5383 do EDITOR) | dado **do fichário** (bolsos de um layout) | **existente** `binder_activity_event`, com 4 tipos novos | já tem autor, ator EDITOR (5372/5381/5384), leituras do titular (5269) e do participante (5388) |

Nenhum dos dois fluxos registra exemplar, alocação, identificador opaco, local, condição ou valores.

## 2. Catálogo de eventos

### 2.1 Pokédex (`collection_activity_event`, `source = 'POKEDEX'`)

| `event_type` | Operação efetiva | `summary` (somente dados autorizados) |
|---|---|---|
| `POKEDEX_POSITION_ASSIGNED` | `CREATED` | `to` {número, espécie}; `card` {nome, número, Set, variante}; `basis` (`SPECIES_MATCH`/`USER_OVERRIDE`) |
| `POKEDEX_POSITION_MOVED` | `MOVED` | `from`, `to`, `card`, `basis`, `representative_cleared` |
| `POKEDEX_POSITION_REMOVED` | `REMOVED` | `from`, `card`, `representative_cleared` |
| `POKEDEX_REPRESENTATIVE_SET` | `SET` | `position`, `card` |
| `POKEDEX_REPRESENTATIVE_REPLACED` | `REPLACED` | `position`, `card`, `previous_card` |
| `POKEDEX_REPRESENTATIVE_RESTORED` | `CLEARED` (volta à automática) | `position`, `previous_card` |
| `POKEDEX_POSITIONS_CHANGED` (origem `DERIVED`) | mudança sem registro explícito: alocar/desalocar e, até a 5395, as funções do titular (§4, §9) | `assigned`, `removed`, `representatives_set`, `representatives_cleared` (contagens) — um evento por coleção e transação |

### 2.2 Referências de espécie (`binder_activity_event`, categoria nova `SPECIES`)

| `event_type` | Operação efetiva | `summary` |
|---|---|---|
| `SPECIES_REFERENCES_APPLIED` | `APPLIED` (5258/5383) | `reference_count`, `first_number`, `last_number`, `visible` |
| `SPECIES_REFERENCES_CLEARED` | `REMOVED` com contagem > 0 | `removed_count` |
| `SPECIES_REFERENCES_SHOWN` | visibilidade `UPDATED` → ligada | — |
| `SPECIES_REFERENCES_HIDDEN` | visibilidade `UPDATED` → desligada | — |

Nunca a contagem de bolsos ocupados (C-243, mesma regra da 5383).

**Sem evento:** `UNCHANGED`, `ALREADY_APPLIED`, remoção de 0, recusas, `STATE_CHANGED`, `CONFIRMATION_REQUIRED`, `PLAN_CHANGED`, `COUNT_MISMATCH`.

## 3. Contrato de registro

| Regra | Como |
|---|---|
| Um evento por operação efetiva | a função de escrita chama a primitiva **uma vez**, depois da escrita, só quando o resultado é efetivo |
| Mesma transação | a primitiva roda dentro da transação da escrita; falha no registro → a escrita toda é desfeita |
| Autor confiável | a primitiva **deriva** o autor de `auth.uid()` e o papel do estado travado (titular = `collection.owner_user_id`; EDITOR = participação ACTIVE travada FOR SHARE pela 5376). Nunca aceita autor ou papel por parâmetro |
| Nome público | **não gravado**; resolvido na leitura a partir de `user_profile.display_name`, nas regras da C-241 (como `actor_display_name` da 5388) |
| Antes/depois | só número da posição, espécie, carta (nome, número, Set, variante), base, sinalizadores e contagens; lista fechada de chaves validada na primitiva; `summary` ≤ 2 048 bytes |
| Imutável | sem UPDATE; DELETE só em cascata da coleção ou do titular |

### 3.1 Primitiva mínima (nova, interna, sem EXECUTE para a API)

Duas chamadas internas, sem EXECUTE para a API, ambas `SECURITY DEFINER` com `search_path` vazio:

```
collection_activity_open(p_collection_id uuid) returns void        -- ANTES da escrita
  marca a transação (set_config local 'mmkyu.collection_activity_explicit' = id da coleção),
  para os gatilhos de instrução de §4 não registrarem a mesma mudança como efeito indireto
  (eles disparam ao fim de cada DELETE/INSERT, antes do registro explícito)

collection_activity_record(p_collection_id uuid, p_event_type text, p_summary jsonb) returns void   -- DEPOIS
  1. auth.uid() obrigatório; a marcação de open() presente para a mesma coleção (senão erro)
  2. papel: titular de p_collection_id → OWNER; senão participação ACTIVE EDITOR → EDITOR; senão erro (nunca grava)
  3. event_type ∈ catálogo §2.1; chaves de summary ∈ lista fechada do tipo; tamanho ≤ 2 048
  4. insert em collection_activity_event (owner_user_id da coleção, actor_user_id, actor_role, source 'POKEDEX')
```

Operação sem efeito (`UNCHANGED`) chama `open()` (sem custo) mas não `record()` — nenhum evento.

### 3.2 Estrutura

`collection_activity_event` (`id bigint identity`, `collection_id` FK `collection` ON DELETE CASCADE, `owner_user_id` FK `auth.users` ON DELETE CASCADE, `occurred_at`, `actor_user_id` sem FK — valor imutável, padrão B1 da 5267 —, `actor_role` ∈ {`OWNER`, `EDITOR`}, `event_type` (CHECK fechado), `source` ∈ {`POKEDEX`, `ACERVO`}, `summary jsonb` com CHECK de tipo e tamanho). Índice `(collection_id, occurred_at desc, id desc)`. RLS ligada sem políticas; sem privilégios para a API; leitura só por funções.

## 4. Efeitos indiretos de alocar e desalocar

Conferido:
- 6119 cria atribuições `SPECIES_MATCH` automaticamente ao alocar (gatilho `AFTER INSERT` em `collection_allocation`, dentro da 5046).
- 5047 desaloca, e as atribuições e representantes caem em cascata (FK 6120).

Isso **muda a organização da Pokédex** sem passar pelas RPCs de posição.

**Recomendação: gatilhos de instrução** (`AFTER INSERT` / `AFTER DELETE ... REFERENCING NEW/OLD TABLE`, `FOR EACH STATEMENT`) em `collection_pokedex_position_assignment`:
- **Quando registram:** só se a transação **não** estiver marcada por `collection_activity_open()` para a coleção (§3.1). Nesse caso gravam **um** `POKEDEX_POSITIONS_SYNCED` por coleção afetada, com contagens e `source = 'ACERVO'`; o autor é o titular da sessão.
- **Dupla função:**
  - cobrem 6119 e 5047 sem alterar 5046/5047;
  - servem de **rede de segurança** para qualquer escritor futuro que esqueça a primitiva (um evento agregado em vez de nenhum).
- **Duplicação evitada:** um "mover" explícito (DELETE + INSERT) marcou a transação antes de escrever, então não gera evento duplicado.

Alternativa (não recomendada): não registrar efeitos indiretos; fica uma lacuna documentada no histórico.

## 5. Integrações

| Contrato | O que muda na S4 | Tipo |
|---|---|---|
| 6122/6123, 6124, 6125, 6126 (titular) | **nova versão com o mesmo corpo + chamada à primitiva** quando o resultado é efetivo; assinatura e retorno iguais (frontend intocado); precheck do md5 antigo, postcheck do md5 novo | alteração controlada de contrato do titular (exigida pela D-E3-8) |
| 5380 (EDITOR por `physical_card_id`) | nenhuma: EXECUTE revogado pela 5392 | — |
| 5392 (EDITOR por identificador) | chama a primitiva; precheck exige a primitiva presente | dependência |
| 5258 (titular) e 5383 (EDITOR), referências | nova versão chamando `binder_activity_begin/end` com os 4 tipos novos; mesmas assinaturas | alteração controlada |
| 5267/5341/5384 (estrutura do histórico do fichário) | `chk_bae_event_type` + 4 tipos; `binder_activity_category` → `SPECIES`; lista do gatilho `trg_bae_editor_event_type` + 4 tipos (o EDITOR pode gerá-los) | extensão |
| 5269 (histórico do titular) | passa a exibir a categoria `SPECIES` (verificar o filtro de categoria) | leitura |
| 5388 (histórico do participante) | idem; regras C-241 inalteradas | leitura |
| Leitura nova `get_collection_activity` (titular e participantes de X) | histórico da Pokédex com `actor_display_name`; titular vê tudo, participante vê os eventos de X (C-241); fecha a **O2** para a Pokédex (autoria legível pelo titular) | RPC nova |

## 6. Pacotes e ordem

| Ordem | Pacote | Conteúdo | Depende de |
|---|---|---|---|
| 1 | **5391** (S2-a) | época, segredo, identificador, leitura do EDITOR | — (preparada) |
| 2 | **5394** (S4-a) | `collection_activity_event`, primitivas `open`/`record`, captura derivada (§9) | 5389 |
| 3 | **5392** (S2-b) | escritas do EDITOR + revogação da 5380 | 5391, 5394 |
| 4 | **5395** (S4-b) | novas versões instrumentadas de 6122–6126 (eventos explícitos do titular); eventos de referências de espécie (histórico do fichário, 5258/5383); leitura `get_collection_activity` (titular e participantes, O2) | 5394, 5384 |
| 5 | F3 | painel da posição para o EDITOR | 5392 |

A 5395 é independente da S2 e pode ser implantada antes ou junto da 5392. Numeração provisória: 5394 e 5395 estão livres no repositório.

## 7. Riscos

| # | Risco | Tratamento |
|---|---|---|
| A1 | novas versões de funções do titular (6122–6126, 5258) mudam contratos implantados | mesmo corpo + uma chamada; md5 antigo no precheck; static check com diff delimitado (só a chamada acrescentada) |
| A2 | o gatilho de instrução entra no caminho de alocar/desalocar em massa | uma inserção por coleção afetada por instrução; medir no gate de desempenho |
| A3 | registro falhando derruba a escrita | intencional (auditoria obrigatória); a primitiva só valida o que ela mesma controla |
| A4 | crescimento do histórico | índice por coleção; retenção/expurgo segue a política da 5270 (a decidir na S4-a) |
| A5 | nome exibido muda depois do evento | resolvido na leitura (decisão C-241, igual à 5388) |

## 8. Decisões pedidas

1. Dois fluxos (coleção para a Pokédex; fichário para as referências), como em §1.
2. Gatilhos de instrução para efeitos indiretos e como rede de segurança (§4).
3. Novas versões das funções do titular com o mesmo corpo + registro (§5).
4. Retenção do `collection_activity_event` igual à do histórico do fichário.

## 9. S4-a / 5394 — preparada (2026-11-27, `S2/5391 FINAL SAFETY REVIEW + S4-a/5394 PREPARATION-01`) — NÃO EXECUTADA

### 9.1 Escopo final e desvios da especificação (registrados para a auditoria)

- **A 5394 só cria infraestrutura e não altera nenhuma função existente.** As versões instrumentadas das funções do titular (6122–6126) e a leitura `get_collection_activity` passam para a **5395**, junto com as referências de espécie. Motivo: a 5392 só precisa da primitiva, e a 5394 fica sem mudança de contrato implantado.
- **Até a 5395 entrar, nenhuma mudança fica sem registro.** Toda mudança de posição ou representante feita fora das escritas explícitas (titular, alocar, desalocar e a 5380 enquanto existir) gera, pela **captura derivada**, um único `POKEDEX_POSITIONS_CHANGED` por coleção e transação, com contagens e autor derivado:
  - titular → `OWNER`;
  - EDITOR ACTIVE → `EDITOR`;
  - sem sessão → `SYSTEM`.
  
  Com a 5395, as operações do titular passam a eventos explícitos, e a captura derivada fica só para alocar e desalocar e como rede de segurança.
- **Marcação em duas chamadas.** `collection_activity_open()` vem **antes** da escrita e `collection_activity_record_pokedex()` **depois** (§3.1); o registro consome a marcação. Assim a captura derivada (que dispara no fim de cada DELETE/INSERT) não duplica a operação explícita.

### 9.2 Objetos

| Objeto | Função |
|---|---|
| `collection_activity_event` | histórico. `origin` EXPLICIT/DERIVED ⇔ tipo; autor ⇔ papel (SYSTEM sem autor, nunca em EXPLICIT); resumo ≤ 2 048 bytes; FK da coleção com CASCADE; índice `(collection_id, occurred_at desc, id desc)` para as leituras da 5395; RLS sem políticas; sem privilégios para a API |
| `collection_activity_event_guard` + `trg_900_…_event_guard` | imutável: só o evento derivado da própria transação acumula contagens |
| `collection_activity_open(uuid)` | marca a transação para a coleção; recusa coleção diferente já marcada |
| `collection_activity_record_pokedex(…)` | um evento EXPLICIT. Sem parâmetro de autor ou papel. Exige a marcação. Valida parâmetros por tipo, que exemplares e posições sejam da coleção e da sua Pokédex, e a base. Monta o resumo com chaves fechadas, só com catálogo e organização |
| `collection_activity_derived_add(…)` | acumula contagens num evento DERIVED por coleção e transação (mapa na GUC local) |
| 5 gatilhos de instrução (`REFERENCING … TABLE`) | atribuição INSERT/DELETE; representante INSERT/UPDATE/DELETE. Ignoram a coleção marcada |
| `trg_900_collection_activity_deallocation` (BEFORE DELETE, por linha) | conta a atribuição que cai em cascata na desalocação. A alocação apagada não é encontrada pelo gatilho de instrução da atribuição, então não há contagem dupla; a representante é contada pelo gatilho da própria tabela |

### 9.3 Artefatos

| Arquivo | Conteúdo |
|---|---|
| `5394_create_collection_activity_audit_infrastructure.sql` | transação única: precheck (barreira; md5 de 6123/6124/6126/6125; dependências; ausência; retrato dos escritores conhecidos, inclusive 5046, 5047, 6119 e 5380) → 3 travas NOWAIT (alocação → atribuição → representante) → objetos → REVOKE → postcheck (9 funções definer sem API, 7 gatilhos habilitados, 0 eventos, escritores intactos, barreira) |
| `ROLLBACK_5394.sql` | remove tudo. Recusa com a 5392 presente ou com **eventos gravados**: apagar auditoria é decisão do proprietário, não rollback |
| `S4A_5394_PRE_readonly.sql` / `S4A_5394_POST_readonly.sql` | gates do executor. `escritores_md5` precisa ser igual no PRE e no POST (o executor compara); `sem_eventos` |
| `S4A_5394_MANIFEST.txt` | PRE (gate) → 5394 (write) → POST (gate) |
| `static_check_5394.py` | **21/21 PASS**. Mutações detectadas: GRANT na primitiva → M5; autor por parâmetro → M8; captura que ignora a marcação → M7; identificador físico no resumo → M9; md5 do titular → C1; trava ausente → M2; `or replace` → M3/M6; marcação não consumida → M8; guarda removida → M11; parêntese faltando → S0 |

**PASS/STOP:**
- **PRE:** todos os booleanos verdadeiros (barreira, titular canônico, executor dono das tabelas, permissão de referenciar `auth.users`, ausência).
- **`gatilhos_existentes` e `escritores_*`:** relatório. Escritor fora do conjunto conhecido → STOP para reavaliar a captura.
- **POST:** todos os booleanos verdadeiros e `escritores_md5` igual ao do PRE.
- **STOP em:** 55P03 ou erro na transação; nada persiste e não há rollback.

### 9.4 Dependências para a 5392

1. A 5391 e a 5394 implantadas; o precheck da 5392 confere as duas, pelos md5 das primitivas.
2. Cada escrita da 5392 segue esta ordem:
   - `assert_collection_editor`;
   - `collection_activity_open(X)` **antes** de qualquer DELETE, INSERT ou UPDATE;
   - a escrita;
   - `collection_activity_record_pokedex(...)` **uma vez** por resultado efetivo;
   - nada em `UNCHANGED` nem em recusa.
3. O static check da 5392 deve provar que todo caminho que escreve chama `open` antes e `record` depois (risco A6).
4. Na mesma transação da 5392: revogar a 5380 de `authenticated`.

### 9.5 Riscos

| # | Risco | Tratamento |
|---|---|---|
| A2 | captura no caminho de alocar e desalocar em massa | uma consulta indexada por linha desalocada (só se houver atribuição) e uma inserção ou atualização por coleção e transação. Medir no TEST com volume real |
| A6 | escrita explícita que chama `open` e não chama `record` deixaria a mudança sem evento | regra 9.4/3 no static check da 5392 |
| A7 | a semântica do PG para transições em `INSERT … ON CONFLICT DO UPDATE` (representante do titular) gera contagens de *set* em INSERT ou UPDATE | as duas contam como `representatives_set`; aceitável para o evento agregado; o titular passa a evento explícito na 5395 |
| A8 | sintaxe e comportamento **não compilados nem executados** (sandbox sem PostgreSQL) | erro de sintaxe aborta a transação inteira na rodada B; o comportamento é provado no TEST |

### 9.6 Revisão dos efeitos imediatos (2026-11-27, `FINAL EXECUTOR GATE & TRIGGER SAFETY REVIEW-01`) — 5394 v1.1

**Defeito encontrado e corrigido.** Os caminhos do titular não consultam a barreira: alocar (5046 + 6119), desalocar (5047) e posição/representante (6122–6126). Por isso, na v1.0, os gatilhos começariam a registrar eventos **logo após a implantação**, ainda com a barreira CLOSED. Consequências:
- auditoria antes de qualquer colaboração;
- código novo no caminho de operações vivas;
- `ROLLBACK_5394` bloqueado assim que houvesse o primeiro evento.

**Correção (mínima):** as 5 capturas e o acúmulo derivado retornam na primeira instrução, a desalocação devolvendo `OLD`, quando `v1_13_capability_open()` é falso para a sessão. Com sessão: barreira CLOSED, ou TEST sem identidade registrada. Sem sessão: qualquer modo diferente de OPEN. O precheck passou a conferir também o md5 canônico de `v1_13_capability_open`.

| Pergunta | Resposta (v1.1) |
|---|---|
| Quais operações existentes acionam os gatilhos com a barreira CLOSED? | alocar, desalocar, 6122–6126 (titular) e 5380 (barreira recusa antes). Todas chegam ao gatilho, que **retorna na 1ª instrução** |
| Podem gravar eventos antes da abertura? | **Não** com CLOSED. Em TEST, só para sessões de identidades registradas (titular ou EDITOR de teste). O POST exige `sem_eventos` |
| Novos bloqueios ou falhas nas operações atuais? | custo por disparo: uma leitura da barreira (STABLE, linha única). Sem inserções, sem travas novas, sem caminho de erro novo com CLOSED. A migration toma SHARE ROW EXCLUSIVE NOWAIT nas 3 tabelas por instantes; com conflito → 55P03 e nada persiste |
| Eventos duplicados entre captura e registro explícito? | não: `open()` marca a coleção antes da escrita, as capturas ignoram a coleção marcada e `record()` consome a marcação (M7/M8). Não há registro explícito sem `open()` |
| Concorrência e operações em massa | com a capacidade aberta: uma atualização do mesmo evento derivado por instrução da transação (alocação em massa de n cartas → n atualizações de uma linha, n versões mortas até o vacuum); a desalocação faz uma consulta indexada por linha. Medir no TEST com volume real (A2) |
| Rollback com eventos? | enquanto CLOSED, não há eventos e o `ROLLBACK_5394` fica disponível. Depois da abertura (ou com eventos de TEST), ele **recusa**: apagar auditoria é decisão do proprietário, que exige um script próprio, fora do rollback |

**Compatibilidade com a 5391:**
- O gatilho de época **não** passa pela barreira, e isso é intencional. A época precisa avançar mesmo com a barreira fechada. Exemplo: uma troca de papel durante um fechamento de emergência, seguida de reabertura, reativaria identificadores antigos se a época não tivesse avançado (O1).
- O custo é uma inserção ou atualização numa tabela lateral, por inclusão e por mudança de `role`/`status`.
- Não há caminho de erro novo além de violar o valor único da sequência, o que não ocorre: a sequência não tem ciclo.
- Convites, respostas, trocas de papel, remoção e saída seguem iguais. O md5 das funções é conferido antes e depois.

**Suficiência para a 5392:** a primitiva cobre os 6 tipos de operação efetiva, com remoção da representante em cascata e representante anterior. O precheck da 5392 deve conferir os md5 de `collection_activity_open` e `collection_activity_record_pokedex`. A regra §9.4 continua: `open` antes, `record` uma vez por resultado efetivo, verificado no static check da 5392.

**Nenhuma alteração colaborativa sem registro:**
- toda escrita do EDITOR depende da barreira aberta para a sessão;
- com ela aberta, ou a 5392 registra explicitamente, ou a mudança (5380, enquanto existir) é capturada derivadamente com papel `EDITOR`.

A 5395 continua planejada (§6): titular explícito, referências de espécie e leituras.

Static check 5394: **22/22 PASS**. Mutações da inércia detectadas: retirada na desalocação → M13; `'TEST'` no lugar de `'OPEN'` → M13; md5 de `capability_open` alterado → C1.

### 9.7 Preparação da implantação (2026-11-27, `S4-a/5394 — AUDIT INFRASTRUCTURE DEPLOYMENT PREPARATION-01`)

**Decisão aprovada:** sequenciamento transitório 5394 → 5392 → 5395 (§9.1). A 5394 não encerra a S4.

**Expectativas do inventário** (`S4A_5394_EXPECTATIVAS.json`, sha256 `6351fb718a1e47c69da170507e04ee0a6e259426f466b4b82db2ce51185edd13`):
- conteúdo idêntico às expectativas da 5391 e ao inventário confirmado no PRE do LIVE em 2026-11-27 (13:00:24Z): 5 escritores de atribuição e 4 de representante;
- o executor v1.4 compara o inventário automaticamente e faz STOP em nome a mais, a menos, repetido, vazio ou ausente.

**Nomes bastam para a 5394, sem enfraquecer o controle.** Os gatilhos são **por tabela**, então capturam qualquer escritor, conhecido ou não. Além disso, o retrato `escritores_md5` (precheck e postcheck da migration, e PRE → POST pelo executor) cobre o corpo de **todas** as sobrecargas desses nomes; uma assinatura nova ou alterada muda o md5. Assinaturas completas (`regprocedure`) continuam recomendadas para a 5392.

**PRE ajustado** (só leitura, aceito pelo validador do executor):
- `dependencia_5391`: a 5391 implantada, com a RPC, a tabela de épocas e o gatilho habilitado (ordem D4);
- `sessoes_com_trava`: relatório das sessões com trava nas 3 tabelas. O `NOWAIT` recusa, sem esperar, se houver conflito.

**Revisão focalizada (sem defeito; SQL inalterado):**

| Item | Resultado |
|---|---|
| CLOSED | as 5 capturas e o acúmulo retornam na 1ª instrução; nenhum evento; operações atuais só pagam uma leitura STABLE da barreira por disparo |
| TEST | captura só nas sessões de identidades registradas (`v1_13_capability_open`) |
| OPEN | captura em todas as sessões. Sem sessão (`SYSTEM`) só em OPEN |
| Duplicidade | `open()` antes da escrita; a captura ignora a coleção marcada; `record()` consome a marcação |
| Autoria | `auth.uid()` e papel derivados no servidor; nenhum parâmetro de autor |
| Integridade | evento na mesma transação; imutável (guarda); FK da coleção |
| Privilégios | 9 funções definer com `search_path` vazio; nenhuma com EXECUTE para a API; tabela com RLS e sem privilégios |
| Reversibilidade | `ROLLBACK_5394` disponível enquanto não houver eventos (garantido com CLOSED). Recusa com eventos ou com a 5392 presente |
| 5392 | primitivas `open` e `record_pokedex` suficientes (§9.4) |
| Travas | PRE exige `executor_dono_tabelas` (prova de que pode criar gatilho e travar as tabelas `public`) e `pode_referenciar_usuarios`; a migration usa `lock_timeout` de 3 s e NOWAIT nas 3 tabelas |

**Critérios de desempenho** (a medir no TEST autorizado, com volume real; nada é comprovado antes):

| Medida | Critério |
|---|---|
| Custo dos gatilhos com CLOSED | sem evento; diferença de tempo em operação do titular (posição/representante) dentro do ruído (≤ 2 ms p95) |
| Captura agregada (TEST/OPEN) | exatamente 1 evento DERIVED por coleção e transação; ≤ 5 ms p95 adicionais por operação do titular |
| Alocação/desalocação em massa (500 exemplares de uma Pokédex) | ≤ 20 % acima da mesma operação sem a 5394; 1 evento por coleção afetada |
| Contenção | migration: nenhuma espera (NOWAIT), `sessoes_com_trava` = 0 na janela; operação: nenhuma trava nova além da linha da coleção já travada pelos caminhos atuais |
| Crescimento | ≤ 1 evento por operação explícita e ≤ 1 por transação derivada; tamanho medido ao fim do TEST; retenção decidida na 5395 |

**PASS/STOP da execução:**
- **PRE:**
  - todos os booleanos verdadeiros (inclusive `dependencia_5391`, `executor_dono_tabelas` e `pode_referenciar_usuarios`);
  - barreira CLOSED e 0 identidades TEST;
  - inventário igual às expectativas;
  - `escritores_md5` registrado.
- **Migration:** exit 0. Qualquer erro, inclusive 55P03 ou sintaxe, aborta tudo, sem rollback.
- **POST:** todos os booleanos verdadeiros, `sem_eventos`, e `escritores_md5` igual ao do PRE (o executor compara).
- **Fora do gate automático:** `sessoes_com_trava` > 0 não reprova o gate (o NOWAIT protege), mas recomenda adiar a janela.

**Artefatos:**

| Arquivo | sha256 |
|---|---|
| Manifesto `S4A_5394_MANIFEST.txt` | `24d7d8a628eb7d4fa40dbb1ccb48da2e8a0b42121157571d4fed923bf7bc17ad` |
| PRE | `8b63e713f0d682e39936005ef9cde45a56826086e9d421a9c50f3912936c5dcd` |
| Migration 5394 (inalterada) | `b43accc5e09dc8cf6572ad6baa3b37fdfef8fea07ae247d6bd52278842d73f5c` |
| POST | `ad50ef0f8ce84907d2b3582bc5c9da3a2eb59f667b6f44848146a2680771b0a9` |
| Rollback | `c613107358f670aa7d0a4a95f5c7dee078015cebbb239286bb35e9d4b32b71b5` |
| Expectativas | `6351fb718a1e47c69da170507e04ee0a6e259426f466b4b82db2ce51185edd13` |

Verificação estática: 24/24.

### 9.8 Implantação confirmada (2026-11-27 13:35:15Z)

PRE, migration e POST com PASS. Os `escritores_md5` são iguais no PRE e no POST. `dependencia_5391`, `executor_dono_tabelas` e `pode_referenciar_usuarios` deram verdadeiro, e `sessoes_com_trava` deu 0. Detalhe em `S4A_5394_DEPLOY_EVIDENCE_2026-11-27.md`.

**Riscos residuais:**
- captura em TEST/OPEN, duplicidade e desempenho não medidos (§9.7);
- operações do titular registradas só como evento agregado até a 5395;
- primitivas prontas para a 5392 (§9.4).

## 10. S4-b / 5395 — EXECUTADA NO LIVE / CANÔNICA (v1.1, 2026-11-27 14:32:43Z; preparada em `S2/5392 PASS-LIVE CLOSEOUT + S4-b/5395 PREPARATION-01`)

### 10.1 Escopo e desvios da especificação (para a auditoria)

- **Dentro:** eventos explícitos das 4 operações do titular na Pokédex (6123 atribuir/mover, 6124 retirar, 6126 escolher/substituir representante, 6125 voltar à automática) e a leitura `get_collection_activity` (O2 para a Pokédex).
- **Fora — decisão pedida (D-5395-1):** as referências de espécie (§2.2: 5258/5383, `binder_activity_event`, `chk_bae_event_type`, categoria `SPECIES`, gatilho 5384, leituras 5269/5388) passam para a **5396**. É outro fluxo (o do fichário), com outro conjunto de funções e de leituras. Juntá-lo à 5395 dobraria a superfície de um pacote que já reescreve 4 funções do titular. Até a 5396, essas operações seguem sem evento (como hoje) e não passam pela barreira. A S4 só fecha com a 5396.
- **Desvio de §5 (D-5395-2):** a instrumentação do titular só age quando `v1_13_capability_open()` é verdadeiro, a mesma condição da captura derivada da 5394.
  - Com a barreira CLOSED, o caminho é exatamente o de hoje: nenhuma marcação, nenhum evento.
  - Em TEST, um titular sem identidade registrada não gera evento, nem explícito nem derivado.
  - Sem sessão (`auth.uid()` nulo), as funções do titular já recusam a chamada.
- **6122:** a versão vigente de `set_pokedex_position_assignment` é a 6123. Só ela é reescrita.

### 10.2 Contrato

| Função (md5 canônico → instrumentado) | Marcação | Evento (um por operação efetiva) | Sem evento |
|---|---|---|---|
| `set_pokedex_position_assignment` 8c572182… → ce63a458… | antes do DELETE/INSERT; lê se havia representante | `POKEDEX_POSITION_ASSIGNED` ou `_MOVED` (`representative_cleared`) | no-op (mesma posição) e recusas: retornam ou abortam antes de qualquer bloco |
| `remove_pokedex_position_assignment` 26ef2d5d… → 2502eb25… | antes do DELETE; lê origem e representante | `POKEDEX_POSITION_REMOVED` | inexistente (aborta) |
| `set_pokedex_position_primary_representative` 6353dffe… → 1bbf1a6a… | antes do upsert, só com mudança; anterior `FOR UPDATE` | `POKEDEX_REPRESENTATIVE_SET` ou `_REPLACED` | mesma carta: sai antes de marcar e de escrever (v1.1, §10.5) |
| `clear_pokedex_position_primary_representative` eeede3a5… → 2bf25d3d… | antes do DELETE; anterior `FOR UPDATE` | `POKEDEX_REPRESENTATIVE_RESTORED` | inexistente (aborta) |

- **Sem duplicidade:** a marcação suprime a captura derivada da mesma coleção, inclusive a retirada da representante em cascata no mover. `record` consome a marcação.
- **Autor e papel:** derivados no servidor por `record` (5394): `auth.uid()`, OWNER/EDITOR.
- **Ordem:** a mesma trava de coleção (`FOR UPDATE`) que já serializa o titular. O instante vem do servidor (`occurred_at`).
- **Garantias de texto:**
  - assinatura, retorno, `SECURITY DEFINER`, `search_path=''`, ACL e corpo são idênticos aos implantados fora dos blocos `[5395+]…[5395-]` (prova textual C2);
  - a migration é gerada por `build_5395.py` a partir de `database/schema`.
- **`get_collection_activity(p_collection_id, p_before_id, p_limit)`:**
  - corpo: barreira (`v1_13_assert_capability`) → página 1–100 (`INVALID_PAGE`) → `collection_share_role` (titular, ou participante **ACTIVE**, com EDITOR lido como VIEWER). Removido, pendente ou recusado → zero linhas;
  - paginação: keyset `(occurred_at, id)` restrito à mesma coleção;
  - colunas: `event_id, occurred_at, event_type, origin, actor_role, actor_display_name, summary`. O nome vem de `user_profile` na leitura (C-241);
  - sem exemplar, alocação, local, condição, valores ou ids de usuário;
  - privilégios: `STABLE`, definer, só `authenticated` (revogada de PUBLIC, anon e service_role).
- **Compatível com a 5392:** não altera nenhum objeto dela. O inventário de escritores fica igual (7 + 6 assinaturas, confirmado no POST da 5392).

### 10.3 Artefatos (sha256)

| Arquivo | sha256 |
|---|---|
| `5395_instrument_owner_pokedex_audit_and_activity_read.sql` | `20f26b5af828710bed0fa69b3e36dcfd16281aedf904c06cd17faee5bc9771ef` |
| `ROLLBACK_5395.sql` | `742de4cda3eb324aa5404610c51c48e6e26f6a2b846c0f9981965adc443bdf91` |
| `S4B_5395_PRE_readonly.sql` (gate) | `77a3c81422f95ee996eaad399f4f848e10c31c3ae9376135138b1dcece1563c9` |
| `S4B_5395_POST_readonly.sql` (gate) | `4c78ba22c74846c8ffdfc02b4dd22b0e3f5e87351f39257da38cd4817b987a35` |
| `S4B_5395_EXPECTATIVAS.json` | `bb3a9fff596fa01b22cb03e71957e6883c27b60c8dc021ea938de6bed0391f21` |
| `S4B_5395_MANIFEST.txt` | `53ef47bedb9f498e4319ef6b6d5b390d31658824087e1d7adb55a94a18fe7b00` |
| `EMERGENCY_STOP_V1_13_ADD_S4.sql` (E2c) | `7d94715f9767c5c6882feb2529156a4b05e8adbfc43d61ffca23e39cb19ee862` |
| `build_5395.py` · `static_check_5395.py` | gerador · verificação estática (26/26, 37/37 mutações) |

- **Rollback:** exige o texto da 5395, restaura o canônico exato das 4 funções e remove a leitura. Não toca a ACL e não apaga eventos.
- **Emergência E2c:** revoga só a leitura. As funções do titular ficam inertes com o E1 (CLOSED), sem revogação.

### 10.4 Riscos residuais

- Comportamento não provado. Nada foi executado: compilação no LIVE, eventos em TEST/OPEN e desempenho ficam para o TEST autorizado e para a E4.
- ~~Marcação não consumida (representante sem mudança)~~: defeito confirmado e corrigido na v1.1 (§10.5).
- Em TEST, as operações de um titular sem identidade registrada não são auditadas (D-5395-2).
- Referências de espécie sem evento até a 5396 (D-5395-1).
- O md5 de `collection_share_role` vem do repositório e de gates anteriores executados. O PRE o confere antes da escrita.

### 10.5 Revisão da marcação transacional (2026-11-27, `S4-b/5395 TRANSACTIONAL AUDIT MARKER REVIEW-01`) — 5395 v1.1

**Ciclo de vida da marcação (5394).**
- **Criação:** `open(C)` grava `mmkyu.collection_activity_explicit = C` com `set_config(…, true)`, local à **transação**.
  - A cláusula `SET search_path` das funções restringe à função só a própria variável; a marcação sobrevive ao retorno de `open`.
- **Consumo:** só `record`, que grava `''` depois do INSERT do evento. Não há primitiva de fechamento.
- **Desfazimento:** erro na transação, ou na subtransação de um tratador EXCEPTION do chamador. As mudanças de GUC voltam junto (comportamento do PostgreSQL, não provado aqui por execução).
- **Efeitos de uma marcação residual C:**
  - os gatilhos derivados ignoram as escritas de C até o fim da transação;
  - `open(C')` para outra coleção recusa com `COLLECTION_ACTIVITY_NESTED`;
  - `open(C)` é aceito.

**Cenário.** A RPC não garante transação exclusiva: o pg_graphql presente no LIVE executa várias mutações de uma requisição numa mesma transação.

**Achado (defeito demonstrado no texto, v1.0).** No 6126 com a mesma carta, a v1.0 marcava sem registrar. Numa transação com mais operações, a marcação residual causava:
- **supressão** dos eventos derivados legítimos da mesma coleção (desalocação, atribuição automática);
- **recusa indevida** de uma operação auditada em outra coleção.

Não havia duplicidade, autoria errada nem alteração de ordem.

**Funções revisadas:**
- **6125** sem alteração: sem representante → `NOT_FOUND` aborta.
- **6124** sempre efetiva, ou `NOT_FOUND` aborta.
- **6123:** no-op e recusas saem antes do bloco; o INSERT sem `ON CONFLICT` é sempre efetivo.
- **5392:** `UNCHANGED` sai antes de `open` (static check 5392).

**Correção mínima (só 6126, sem tocar a 5394).** Sob auditoria, com a anterior já travada, a mesma carta faz a função **sair antes de marcar e de escrever**. Ela devolve a mesma linha do upsert canônico, como o `UNCHANGED` da 5392.

**Desvio do canônico (para a auditoria).** Só nesse caso, e só com a capacidade aberta, não há o UPDATE idempotente. Por isso não roda o gatilho `trg_020` (`updated_at` não muda) nem a revalidação `trg_010` de um estado já válido e travado.
- Nenhuma leitura do repositório usa o `updated_at` da representante.
- Com a barreira CLOSED, o caminho continua idêntico ao canônico.

**Provas estáticas novas:**
- **T1:** entre `open` e `record` não há RETURN, EXIT nem tratador EXCEPTION.
- **T2:** toda marcação precede uma escrita efetiva ou um erro.
- **T3:** a saída no-op devolve a linha canônica.
- **Mutações:** 8 novas, incluindo a reintrodução do defeito.
- **Pendente de execução (TEST/E4):** persistência e desfazimento da GUC, e o comportamento real em transações com várias chamadas.

**Arquivos regenerados:** migration, rollback (precheck com o md5 novo), POST (md5 do 6126), manifesto, static check. PRE e expectativas inalterados.

### 10.6 Implantação confirmada (2026-11-27 14:32:43Z)

- **Execução:** executor v1.4 com o manifesto `53ef47be…7b00` e as expectativas `bb3a9fff…1f21`. PRE, migration (exit 0) e POST com PASS.
- **Evidências:** `S4B_5395_DEPLOY_EVIDENCE_2026-11-27.md`.
- **Cópia canônica:** `database/schema/5395_instrument_owner_pokedex_audit_and_activity_read.sql`. O corpo é idêntico; só o bloco Status difere.
- **Não executados:** rollback e emergência E2c.
- **Provas funcionais pendentes:** TEST/E4.
