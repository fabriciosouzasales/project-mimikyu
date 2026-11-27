# V1-13 · E3-6 / S4 — Auditoria colaborativa (D-E3-8): especificação contratual

| Campo | Valor |
|---|---|
| **Rodada** | `E3-6 / S2 + S4 — CONTRACT CONSOLIDATION, IMPLEMENTATION PREPARATION & GOVERNANCE OPTIMIZATION-01` (2026-11-27) |
| **Status** | **S4-a / 5394 PREPARADA — NÃO EXECUTADA** (2026-11-27): migration v1.1 (captura derivada inerte com a capacidade fechada), rollback, PRE/POST, manifesto, static check 22/22 com mutação (§9, §9.6). S4-b / 5395 apenas especificada. |
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
