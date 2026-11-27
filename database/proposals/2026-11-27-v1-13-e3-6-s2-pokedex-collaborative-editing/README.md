# V1-13 · E3-6 / S2 — Edição colaborativa da Pokédex: contratos 5391–5392 consolidados

| Campo | Valor |
|---|---|
| **Rodada** | `E3-6 / S2 — POKEDEX COLLABORATIVE EDITING CONTRACTS \| DESIGN REVIEW-01` (2026-11-27) |
| **Status** | **5391 e 5392 EXECUTADAS NO LIVE / CANÔNICAS (2026-11-27)**. 5391: 13:00:24Z; 5392 v1.1: 14:02:33Z. PRE, migration e POST com PASS pelo executor v1.4; barreira CLOSED. Evidências: `S2_5391_DEPLOY_EVIDENCE_2026-11-27.md` e `S2_5392_DEPLOY_EVIDENCE_2026-11-27.md`. Provas funcionais, de concorrência e de desempenho pendentes (TEST/E4). |
| **Base** | Proposta E3-6 (`2026-11-25-v1-13-e3-6-contract-evolution/README.md`, §0 P0-A/B/C, O1–O3, §3.2) — este documento a **substitui no detalhe** de 5391/5392 e não reabre a decisão de produto (edição colaborativa completa da Pokédex). |
| **Conferido no código implantado** | `e1e-security-evidence/g1/protected/` 5324, 5373, 5376 (`assert_collection_editor`), 5369, 5370, 5380, 5383, 5388; `g1/EMERGENCY_STOP_V1_13.sql`; `database/schema/` 5300, 5302–5306, 5046, 5047, 5165/5289, 5208, 5209, 5258, 5267–5269, 6118–6126; `000_enable_pgcrypto.sql`. |
| **Fora do escopo** | S1 (implantada), S3/5393 (implantada), F1, F2, S4 (só os pontos de integração), F3, E3-7. |

---

## 1. Ponto de partida

### 1.1 O que já existe e permanece

| Contrato | Papel na S2 | Mudança |
|---|---|---|
| 6122–6126 (titular: atribuir, mover, retirar, escolher e limpar representante) | regras de negócio e ordem de travas de referência (coleção → alocação → representante) | **nenhuma** (md5 conferido antes e depois) |
| 6118 (gatilhos da atribuição: imutável, mover = DELETE + INSERT, `USER_OVERRIDE` exige autor), 6120/6121 (representante: PK `(collection_id, pokedex_position_id)`, `UNIQUE (collection_allocation_id)`, FK para a atribuição com `ON DELETE CASCADE`) | integridade estrutural; a cascata remove a representante quando a carta sai da posição | nenhuma |
| 6119 (atribuição automática por espécie ao alocar), 5046/5047 (alocar/desalocar), 5165/5289 (remover exemplar só sem alocação) | outros escritores das mesmas tabelas; **todos travam `collection` FOR UPDATE antes** | nenhuma |
| 5324 (grade da Pokédex do participante, `collection_share_role`, EDITOR lê como VIEWER) | grade e representante **efetiva** (nome/número/Set/imagem); não diz se é escolhida | nenhuma |
| 5376 `assert_collection_editor` (EDITOR ACTIVE, não titular, `collection` FOR UPDATE, participação FOR SHARE, coleção ativa) | autorização das escritas | nenhuma |
| 5367 `collection_member_role` (papel real, STABLE) | autorização da leitura | nenhuma |
| 5389 barreira (`v1_13_assert_capability`) | porta de toda RPC nova | nenhuma |
| 5380 (4 escritas do EDITOR por `physical_card_id`, sem estado esperado nem auditoria) | regras reaproveitadas no corpo da 5392 | **EXECUTE revogado de `authenticated`** na 5392 (§3.6) |
| 5373 (exemplares colocáveis no fichário com `physical_card_id`) | — | nenhuma (endurecimento futuro registrado, §9 R8) |
| 5383/5393 (referências de espécie) | — | nenhuma |
| 5269/5388 (histórico do fichário, `binder_activity_event` com `layout_key NOT NULL`) | **não** é o destino dos eventos da Pokédex (§5) | nenhuma |

### 1.2 Menor conjunto de capacidades novas

| # | Objeto | Tipo | Pacote |
|---|---|---|---|
| N1 | época da participação (`role_epoch`) — tabela lateral + sequência + 2 gatilhos em `collection_membership` | estrutura interna | 5391 |
| N2 | segredo do servidor para os identificadores | tabela interna, sem grants | 5391 |
| N3 | ajudante interno de identificador (emitir/resolver) | função interna, sem EXECUTE para a API | 5391 |
| N4 | leitura `get_editor_pokedex_position_copies` | RPC (STABLE) | 5391 |
| N5 | 4 escritas por identificador | RPC (VOLATILE) | 5392 |
| N6 | revogação das 4 escritas da 5380 para `authenticated` | privilégio | 5392 |
| N7 | inclusão das 5 RPCs novas no `EMERGENCY_STOP_V1_13.sql` (nova versão do script) | operação | 5391/5392 |

Nada novo para Livre e Master Set. Nenhuma leitura nova da grade (a 5324 continua a fonte da grade).

---

## 2. Identificador opaco (P0-A) e época do papel

### 2.1 Construção

`copy_token = 'pc1.' || hex(HMAC-SHA256(segredo, allocation_id || '|' || membership_id || '|' || role_epoch))` — 68 caracteres; o prefixo `pc1` versiona o formato.

- **Segredo (N2):** `public.v1_13_copy_token_secret` (`id = 1`, `secret bytea` de 32 bytes por `gen_random_bytes`, `created_at`), RLS ligada sem políticas, `REVOKE ALL` de PUBLIC/anon/authenticated/service_role — padrão da 5389. **Rotação** (troca do segredo) invalida todos os identificadores de uma vez: alavanca de emergência documentada, nunca automática.
- **pgcrypto:** `hmac`/`gen_random_bytes` vêm da extensão (000); como as funções usam `search_path = ''`, o esquema da extensão precisa ser **confirmado no PRE** e qualificado no SQL (não presumir `extensions.`).
- **Propriedades:** determinístico dentro da mesma época (a interface pode usá-lo como chave estável entre leituras); diferente para outra coleção, outra alocação, outro participante ou outra época; nada derivável só de ids que o EDITOR possa conhecer (o segredo nunca sai do banco).
- **Não é autorização** (P0-A.3): toda escrita reconfere `assert_collection_editor`; o identificador só aponta o exemplar.
- **Aceito só** pelas RPCs da 5391/5392; o ajudante N3 não tem EXECUTE para nenhum papel da API.

### 2.2 Época do papel (N1) — desenho confirmado, com uma escolha de localização

Fatos conferidos:

| Transição | Função | Efeito na linha de participação |
|---|---|---|
| convite novo | 5303/5369 | INSERT (id novo) |
| aceitar / recusar | 5304 | UPDATE `status` PENDING → ACTIVE / DECLINED (mesma linha) |
| reconvite com o mesmo papel após recusa | 5369 | UPDATE `status` DECLINED → PENDING (**mesma linha**) |
| reconvite com outro papel após recusa | 5369 | DELETE + INSERT (id novo) |
| troca de papel (EDITOR ↔ VIEWER) | 5370 | UPDATE `role` (**mesma linha**, sem carimbo) |
| remover / sair | 5305 / 5306 | DELETE |

Desenho (P0-A.5, mantido): contador incrementado por gatilho sempre que `role` ou `status` mudam. **Refinamento proposto para a auditoria:** guardar a época numa **tabela lateral**, não numa coluna nova de `collection_membership`:

- `public.collection_membership_epoch (membership_id uuid PK → collection_membership(id) ON DELETE CASCADE, role_epoch bigint NOT NULL)`, sem grants; valores tirados de uma **sequência dedicada** (`nextval`), portanto **monotônicos e nunca reutilizados**, nem entre linhas.
- Gatilho `AFTER INSERT` em `collection_membership`: cria a época. Gatilho `AFTER UPDATE OF role, status` com `OLD.role IS DISTINCT FROM NEW.role OR OLD.status IS DISTINCT FROM NEW.status`: nova época. Backfill das linhas existentes na própria migration.
- **Por que lateral:** as funções 5303, 5304, 5369 e 5370 usam `collection_membership%ROWTYPE` com `SELECT *`/`RETURNING *`; não alterar a forma da tabela evita qualquer risco de incompatibilidade de tipo de linha em sessões abertas e cumpre "não alterar funções existentes" (nenhuma delas muda).
- **Fail closed:** participação sem linha de época → nenhum identificador é emitido nem aceito.
- **Coerência na transação:** a escrita trava a participação `FOR SHARE` (5376) antes de resolver o identificador; uma troca de papel/status concorrente (UPDATE da mesma linha) espera ou faz a escrita do EDITOR falhar — a época lida é a vigente durante toda a escrita.

Invalidação resultante (requisito O1): rebaixar, promover, rebaixar e promover de novo, recusar, reconvidar (mesma linha ou linha nova), remover, sair → época ou `membership_id` diferentes → identificadores antigos recusados com `COPY_NOT_FOUND`. Desalocar, realocar para outra coleção ou nova alocação na mesma coleção → `allocation_id` diferente ou inexistente → idem. **Arquivar e reativar a coleção não muda a época** (a escrita é recusada com `COLLECTION_ARCHIVED` enquanto arquivada); ver §9 R5.

### 2.3 Resolução sem varredura ampla

A resolução recalcula o HMAC sobre alocações candidatas de X, **limitadas pelo estado esperado** que a tela informou:

1. conjunto primário: atribuições da posição esperada (`idx_collection_pokedex_position_assignment_position_id`), ou, se a tela viu "sem posição", as alocações de X sem atribuição (`ix_collection_allocation_collection`);
2. sem acerto no conjunto primário → varredura das alocações de X (limitada à coleção): achou em outro lugar → `STATE_CHANGED`; não achou → `COPY_NOT_FOUND`.

Custo O(k) no caminho comum; O(n da coleção) só em conflito ou identificador inválido. A medição entra no gate de desempenho (G5 da S2).

---

## 3. Contratos consolidados

### 3.1 Convenções comuns

- `SECURITY DEFINER`, `search_path = ''`, objetos qualificados; primeira instrução `perform public.v1_13_assert_capability()` (barreira CLOSED → `42501 CAPABILITY_NOT_ENABLED`, como a 5393).
- EXECUTE só para `authenticated`; revogado de PUBLIC, anon e service_role.
- Recusas: só **código + nome** (a interface nunca lê hint/details); recusa de acesso **neutra** (`COLLECTION_NOT_FOUND`, P0002) para não membro, VIEWER, convite pendente/recusado, ex-membro, titular e coleção inexistente — indistinguíveis.
- Saída sem `physical_card_id`, `collection_allocation_id`, `membership_id`, `assigned_by_user_id`, local (`storage_name`), condição, certificação, proveniência, valores, datas de entrada no acervo ou de atribuição, nem nada de outras coleções.

### 3.2 5391 — leitura `get_editor_pokedex_position_copies`

```
get_editor_pokedex_position_copies(
  p_collection_id        uuid,
  p_pokedex_position_id  uuid,
  p_scope                text,          -- 'AT_POSITION' | 'ASSIGNABLE'
  p_query                text default null,  -- só ASSIGNABLE: nome da carta ou da espécie, ou número nacional (1–4 dígitos); 1–64 caracteres
  p_limit                integer default 30, -- 1–100
  p_offset               integer default 0   -- 0–10 000
) returns table (
  copy_token                  text,
  card_name                   text,
  collector_number            text,
  card_set_code               text,
  variant_label               text,
  language_code               text,
  image_path                  text,
  species_match               boolean,  -- a espécie principal da carta = espécie da posição
  current_position_id         uuid,     -- ASSIGNABLE: posição atual em X (NULL = sem posição); AT_POSITION = p_pokedex_position_id
  current_position_number     integer,
  assignment_basis            text,     -- 'SPECIES_MATCH' | 'USER_OVERRIDE' | NULL (sem posição)
  is_primary_representative   boolean,  -- escolhida explicitamente
  is_effective_representative boolean,  -- a que a grade (5324) mostra
  position_representative_mode text,    -- AT_POSITION: 'CHOSEN' | 'AUTOMATIC' (posição sem exemplares = zero linhas)
  total_count                 bigint
)
STABLE
```

- **Autorização:** `collection_member_role(X) = 'EDITOR'` (participação ACTIVE com papel EDITOR) e X Pokédex; senão **zero linhas** (sem travas, STABLE). VIEWER usa só a 5324. Titular usa as suas leituras (5208/5209).
- **Escopo:** posição tem de pertencer à Pokédex de X (senão zero linhas). `AT_POSITION` = exemplares de X com esta posição. `ASSIGNABLE` = exemplares **alocados a X** sem posição ou em outra posição — **nunca o acervo** (alocar continua do titular, C-243).
- **Ordem:** AT_POSITION — representante efetiva primeiro, depois a ordem de atribuição (sem devolver a data); ASSIGNABLE — `species_match` primeiro, depois nome, Set e número.
- **Exibição** (`current_position_id`/`number`) só de posições de X — informação já presente na grade 5324 do participante.
- **L2 resolvida aqui:** `position_representative_mode` e `is_primary_representative` dizem se a representante é escolhida ou automática; o `copy_token` da escolhida é o `p_expected_representative_token` das escritas.
- **Instantâneo:** uma chamada = um snapshot (STABLE). Consistência entre chamadas não é garantida — é o papel do estado esperado nas escritas.
- Arquivada: **zero linhas** (leitura própria do EDITOR exige coleção ACTIVE, como a 5373); escritas recusadas com `COLLECTION_ARCHIVED`.

### 3.3 5392 — escritas por identificador

Todas: `VOLATILE`, `lock_timeout` local curto, uma transação por chamada, `assert_collection_editor` (5376), Pokédex de X, mesmas regras da 5380/6122–6126. Retorno sem identificadores internos.

| Função | Parâmetros | Resultado |
|---|---|---|
| `editor_move_pokedex_copy` | `p_collection_id`, `p_copy_token`, `p_target_position_id`, `p_expected_position_id` (o que a tela viu; NULL = sem posição), `p_confirm_override boolean default false` | `operation` `CREATED`\|`MOVED`\|`UNCHANGED`, `pokedex_position_id`, `previous_position_id`, `assignment_basis`, `representative_cleared` |
| `editor_unassign_pokedex_copy` | `p_collection_id`, `p_copy_token`, `p_expected_position_id` (obrigatório, não nulo) | `operation` `REMOVED`\|`UNCHANGED`, `previous_position_id`, `representative_cleared` |
| `editor_choose_pokedex_representative` | `p_collection_id`, `p_copy_token`, `p_expected_position_id`, `p_expected_representative_token` (NULL = a tela viu automática) | `operation` `SET`\|`REPLACED`\|`UNCHANGED`, `pokedex_position_id` |
| `editor_restore_pokedex_automatic_representative` | `p_collection_id`, `p_pokedex_position_id`, `p_expected_representative_token` (obrigatório) | `operation` `CLEARED`\|`UNCHANGED` |

"Atribuir" = mover a partir de "sem posição" (`CREATED`). "Selecionar representante" = `SET`/`REPLACED`. "Restaurar automático" = `CLEARED`.

**Sequência obrigatória (O3):**

1. barreira → sessão → argumentos;
2. `assert_collection_editor` — trava `collection` FOR UPDATE e a participação FOR SHARE;
3. Pokédex de X; posição alvo na Pokédex de X;
4. resolver o identificador (§2.3) com a época vigente;
5. travar a alocação FOR UPDATE; ler a atribuição atual; travar a linha de representante da posição envolvida FOR UPDATE (as duas posições, na ordem crescente de id, quando houver mover entre posições com representante);
6. **comparar com o estado travado:**
   - estado final pedido já vigente → `UNCHANGED` (idempotência; vem antes da comparação do esperado e antes da espécie, regra 6122 v1.1);
   - estado travado ≠ esperado → `STATE_CHANGED` (22023), nada gravado;
   - espécie diferente sem confirmação → `CONFIRMATION_REQUIRED` (22023);
7. escrever (mover = DELETE + INSERT; cascata da representante pela FK 6120);
8. registrar o evento de auditoria (S4) **na mesma transação** (§5);
9. retornar.

### 3.4 Recusas

`CAPABILITY_NOT_ENABLED` (42501) · `not_authenticated` (28000) · `INVALID_ARGUMENT` (22023) · `COLLECTION_NOT_FOUND` (P0002, neutra) · `COLLECTION_ARCHIVED` (55000) · `NOT_POKEDEX_COLLECTION` (22023) · `POKEDEX_POSITION_NOT_FOUND` (22023) · `COPY_NOT_FOUND` (P0002 — identificador inválido, obsoleto ou de outro contexto: **mesma recusa para qualquer causa**) · `POKEDEX_ASSIGNMENT_NOT_FOUND` (22023) · `STATE_CHANGED` (22023) · `CONFIRMATION_REQUIRED` (22023) · `55P03` (trava ocupada: nada gravado, a interface oferece tentar de novo — nunca automaticamente).

### 3.5 Concorrência e resultado incerto

| Situação | Tratamento |
|---|---|
| Duas escritas na mesma coleção (EDITOR × EDITOR, EDITOR × titular, EDITOR × alocar/desalocar) | serializadas pela trava `collection` FOR UPDATE, que **todos os escritores conferidos** tomam primeiro (6122–6126, 5046/5047 com 6119, 5380, 5392). A comparação do esperado ocorre depois das travas — sem TOCTOU. O PRE inventaria os escritores das duas tabelas para manter essa premissa verdadeira |
| Ausência de linha de representante (nada para travar com FOR UPDATE) | coberta pela mesma trava da coleção |
| Estado diferente do visto | `STATE_CHANGED`; a interface relê 5391 e 5324 |
| Repetição da mesma operação | `UNCHANGED`, sem evento |
| Resultado incerto (rede, tempo esgotado) | a interface relê; nunca repete sozinha; a repetição manual dá `UNCHANGED` se a primeira tiver sido gravada |
| Perda de autorização durante a operação | a participação está travada FOR SHARE: uma troca de papel concorrente espera o fim da escrita; se vier antes, `assert_collection_editor` recusa com `COLLECTION_NOT_FOUND`. Nenhuma escrita depois de um rebaixamento confirmado |
| Coleção arquivada durante a operação | serializada pela trava da coleção; depois do arquivamento, `COLLECTION_ARCHIVED` |
| Mover a representante escolhida | a cascata remove a escolha da posição antiga; `representative_cleared = true` no retorno e no evento |

### 3.6 Revogação da 5380

Na mesma transação da 5392: `REVOKE EXECUTE` das quatro escritas da 5380 de `authenticated`. Necessidade: elas aceitam `physical_card_id`, não têm estado esperado (L3) nem auditoria (D-E3-8) — deixá-las abertas manteria um caminho de escrita sem auditoria. As funções **ficam** (o `EMERGENCY_STOP_V1_13.sql`, linhas 46–49, as revoga sem guarda; o mesmo motivo da I1 na S1).

---

## 4. Matriz de autorização

| Quem | 5324 (grade) | 5391 | 5392 | 6122–6126 (titular) |
|---|---|---|---|---|
| anon | ✘ | ✘ (sem EXECUTE) | ✘ (sem EXECUTE) | ✘ |
| autenticado sem vínculo | sem linhas | sem linhas | `COLLECTION_NOT_FOUND` | ✘ (dono) |
| convite PENDING / DECLINED | sem linhas | sem linhas | `COLLECTION_NOT_FOUND` | ✘ |
| VIEWER ACTIVE | ✔ | sem linhas | `COLLECTION_NOT_FOUND` | ✘ |
| EDITOR ACTIVE de X | ✔ (como VIEWER) | ✔ | ✔ (coleção ativa) | ✘ |
| EDITOR de outra coleção | sem linhas | sem linhas | `COLLECTION_NOT_FOUND` | ✘ |
| ex-membro / rebaixado | conforme papel atual | conforme papel atual | `COLLECTION_NOT_FOUND`; identificadores antigos `COPY_NOT_FOUND` | ✘ |
| titular de X | ✔ | sem linhas | `COLLECTION_NOT_FOUND` | ✔ (inalterado) |
| qualquer um, barreira CLOSED | contrato atual da 5324 | `CAPABILITY_NOT_ENABLED` | `CAPABILITY_NOT_ENABLED` | inalterado |
| modo TEST (futuro, autorizado à parte) | — | só identidades registradas | idem | — |

Livre e Master Set: sem mudança (5391 → zero linhas; 5392 → `NOT_POKEDEX_COLLECTION` depois da autorização).

## 5. Integração obrigatória com a S4 (D-E3-8)

**Regra de liberação:** as escritas da 5392 **não são implantadas sem o registro de auditoria disponível**; cada operação efetiva grava seu evento **na mesma transação** (falha no registro → a escrita toda é desfeita).

| Operação efetiva | Evento | Conteúdo autorizado |
|---|---|---|
| `CREATED` | posição atribuída | autor (nome público, papel no momento), coleção, posição (número + espécie), carta (nome, número, Set, variante), base (`SPECIES_MATCH`/`USER_OVERRIDE`) |
| `MOVED` | posição movida | posição anterior e nova, carta, base, `representative_cleared` |
| `REMOVED` | posição retirada | posição anterior, carta, `representative_cleared` |
| `SET` / `REPLACED` | representante escolhida / substituída | posição, carta nova (e anterior em `REPLACED`) |
| `CLEARED` | representante restaurada para a automática | posição, carta que deixou de ser escolhida |

Nenhum evento para `UNCHANGED`, recusa, `STATE_CHANGED` ou `CONFIRMATION_REQUIRED`. Nunca exemplar, alocação, identificador, local, condição ou valores.

**Pontos de integração (contrato que a S4 precisa oferecer; a S2 não cria tabela própria de eventos):**

1. **Destino:** a S4 define um fluxo de eventos **por coleção**. `binder_activity_event` (5267) é por fichário (`layout_key NOT NULL`, `source`/`event_type` com CHECK fechado) e **não** serve como está; a extensão ou a tabela nova é decisão da S4.
2. **Primitiva de registro** interna (sem EXECUTE para a API), chamada pela 5392 dentro da transação, com o vocabulário acima — a 5392 depende dela no precheck.
3. **Titular:** a D-E3-8 inclui as operações equivalentes de 6122–6126 (e da 5258/5383 para referências). A S4 decide como cobri-las (nova versão das funções do titular ou outro mecanismo) — a S2 não altera funções do titular.
4. **Efeitos indiretos a decidir na S4:** atribuição automática ao alocar (6119), remoção de atribuições ao desalocar (5047) e a cascata da representante — mudam posições sem chamada às RPCs de posição.
5. **Leitura** (titular vê tudo; participantes veem X conforme C-241) e **autoria para o titular** (O2) — entregas da S4, separadas.

**Ordem de implantação decorrente:** 5391 (leitura + época + segredo) pode ser implantada antes, inerte com a barreira CLOSED; **5392 só junto ou depois da primitiva de registro da S4**.

## 6. Compatibilidade

| Item | Garantia |
|---|---|
| Titular (6122–6126, 5208, 5209, 5046, 5047, 6119) | intocados; md5 no precheck e no postcheck |
| Funções de participação (5303–5306, 5369, 5370) | intocadas; só ganham os gatilhos de época (efeito: uma linha na tabela lateral) — verificar no PRE que nenhum gatilho existente conflita |
| 5324, 5323 (galerias F1) | intocadas |
| 5383, 5393 (referências F2, S3) | intocadas |
| 5390 (S1) | sem relação; preservada |
| EDITOR/VIEWER em Livre e Master Set | sem mudança |
| C-234–C-244, P0-A/B/C, D-E3-8, D-E3-9 | atendidos; C-243 (patrimônio só do titular) preservado: nada aloca, desaloca ou altera exemplar |
| `EMERGENCY_STOP_V1_13.sql` | ganha as 5 RPCs novas em versão nova do script (mesma implantação); as linhas 46–49 continuam válidas |

## 7. Estratégia de validação (diretriz vigente)

1. **Estática:** static check do texto (forma, `search_path`, porta, grants, nenhum DDL sobre titular/participação além dos gatilhos, nenhuma coluna proibida no retorno, ordem de travas, comparação depois das travas, evento na mesma transação).
2. **PRE somente leitura:** barreira e identidades; md5 do titular, das funções de participação e da 5380; esquema da pgcrypto e funções `hmac`/`gen_random_bytes`; inventário dos escritores de `collection_pokedex_position_assignment` e `collection_pokedex_position_primary_representative` (premissa da trava da coleção); gatilhos existentes em `collection_membership`; índices de §2.3; ausência dos objetos novos; presença da primitiva S4 (só para 5392).
3. **Migration transacional** com precheck/postcheck internos, apenas com autorização específica.
4. **POST somente leitura.**
5. **Provas funcionais e de segurança** (matriz §4, O1 completo, concorrência em duas sessões, privacidade das colunas, `STATE_CHANGED`, idempotência, cascata, desempenho da resolução) **só na homologação autorizada**. Nenhum teste sintético no LIVE sem autorização; nada declarado validado antes de executado.

## 8. Plano

| Passo | Conteúdo | Dependência |
|---|---|---|
| S2-a | SQL 5391 (N1–N4) + rollback + static check + PRE/POST | aprovação deste contrato |
| S4 | contrato e SQL da auditoria colaborativa (destino, primitiva, titular, efeitos indiretos, leitura) | D-E3-8 |
| S2-b | SQL 5392 (N5, N6) chamando a primitiva da S4 | S2-a, S4 (primitiva) |
| N7 | nova versão do `EMERGENCY_STOP_V1_13.sql` | S2-a/S2-b |
| F3 | painel da posição para o EDITOR | S2-b |
| E4 | homologação | todos |

## 9. Riscos residuais

| # | Risco | Tratamento |
|---|---|---|
| R1 | resolução O(n) em conflito ou identificador inválido em coleções grandes | caminho comum O(k) (§2.3); medir no gate G5 da S2 |
| R2 | gatilhos novos em `collection_membership` entram no caminho de convites e troca de papel | função mínima, sem leitura externa; falha bloquearia convites — postcheck e homologação cobrem |
| R3 | segredo único: vazamento permitiria forjar identificadores | segredo inacessível à API; mesmo forjado, o identificador só aponta exemplar de X para um EDITOR já autorizado (não concede acesso); rotação disponível |
| R4 | premissa "todos os escritores travam a coleção" pode deixar de valer com funções futuras | inventário no PRE; regra registrada para novas funções |
| R5 | arquivar e reativar não invalida identificadores | escrita recusada enquanto arquivada; autorização reconferida depois; aceitável — registrar como decisão |
| R6 | cascata da representante ao mover surpreende | retorno e evento trazem `representative_cleared`; interface explica (F3) |
| R7 | S4 ainda sem contrato: 5392 bloqueada até a primitiva existir | ordem de implantação §5 |
| R8 | 5373/5374 continuam expondo `physical_card_id` no fichário | fora do escopo; endurecimento futuro registrado |
| R9 | concorrência e desempenho não medidos | gates da S2 na homologação |

## 10. Decisões pedidas à auditoria

1. Época em **tabela lateral com sequência** (recomendado) × coluna em `collection_membership`.
2. `p_query` na leitura ASSIGNABLE (recomendado para coleções grandes).
3. R5 (arquivar/reativar não invalida identificadores) aceito.
4. Ordem de implantação: 5391 antes; 5392 só com a primitiva da S4.

---

## 11. Decisões aprovadas (2026-11-27, `S2 + S4 … GOVERNANCE OPTIMIZATION-01`)

| # | Decisão | Aplicação na 5391 |
|---|---|---|
| D1 | Época em tabela lateral `collection_membership_epoch` com sequência própria; valores nunca reutilizados; `collection_membership` sem mudança de forma | sequência `no cycle` + `UNIQUE (role_epoch)`; gatilho `AFTER INSERT OR UPDATE OF role, status`; FK `ON DELETE CASCADE` (remover/sair apaga a época; reconvite com outro papel cria linha e época novas; reconvite com o mesmo papel muda `status` → época nova); md5 de 5369/5370/5304/5305/5306/5367 conferidos antes e depois |
| D2 | `AT_POSITION` e `ASSIGNABLE`; filtro opcional por nome ou número nacional | limite 1–100, deslocamento ≤ 10 000, filtro ≤ 64 caracteres (só ASSIGNABLE); 1–4 dígitos = número nacional da espécie da carta; texto = nome da carta ou da espécie (LIKE escapado); ordem determinística com desempate interno pela alocação (nunca devolvida); `total_count` |
| D3 | Arquivar/reativar não invalida o identificador; cada escrita revalida coleção ACTIVE, participação EDITOR ACTIVE, vínculo atual do exemplar, estado esperado, barreira e autorização | contrato da 5392 (§3.3); na 5391 a leitura já exige coleção ACTIVE |
| D4 | 5391 → S4 → 5392 → F3; 5392 não é liberada sem a primitiva da S4 | S4 especificada; 5392 terá precheck da primitiva |

## 12. Diagnóstico focalizado 5373/5374

| Pergunta | Resposta (conferida nas versões protegidas implantadas) |
|---|---|
| Quem recebe identificador físico? | **Só o EDITOR ACTIVE**, pela 5373 `get_shared_binder_placeable_cards` (VIEWER: zero linhas; coleção ACTIVE; barreira por `v1_13_capability_open`). Nenhuma outra leitura compartilhada devolve `physical_card_id` (5315/5316/5318, 5323, 5324, 5386, 5388 conferidas). A 5374 **recebe** `physical_card_id` (colocar) e devolve só `operation` |
| Global ou da coleção? | **Global e permanente** (id do exemplar); `collection_allocation.physical_card_id` é UNIQUE (um exemplar em no máximo uma coleção por vez) |
| Correlacionável entre coleções? | **Só no tempo:** se o titular mover o exemplar de X para Y e o mesmo EDITOR participar de ambas, verá o mesmo id. Não concede acesso: toda função que aceita o id autoriza pela coleção (titular ou EDITOR de X) |
| Vulnerabilidade relevante para a S2? | **Sim, uma, já tratada:** com o `physical_card_id` da 5373, o EDITOR poderia chamar as escritas da 5380 (sem estado esperado e sem auditoria), contornando o identificador opaco. **A 5392 revoga a 5380 de `authenticated`** — sem isso, a 5392 não pode ser liberada. A exposição da 5373 em si é de privacidade (correlação), sem ganho de autoridade |
| Menor ajuste | 5373 v2 devolvendo o identificador opaco da 5391 no lugar do `physical_card_id`, e 5374 aceitando o identificador (mesma resolução da 5392). **Prioridade média**, não bloqueia S2/S4; depende da 5391 implantada; registrar para antes da abertura pública (E4). Nada alterado nesta rodada |

## 13. 5391 — artefatos preparados (NÃO EXECUTADOS)

| Arquivo | Conteúdo |
|---|---|
| `5391_create_editor_pokedex_copy_identity_and_read.sql` | transação única: precheck (V02 barreira, pgcrypto em `extensions`, V03 md5 das 6 funções de participação, V07 nenhum gatilho em `collection_membership`, dependências, V04 ausência) → `LOCK … SHARE ROW EXCLUSIVE NOWAIT` em `collection_membership` → sequência, tabela de época, gatilho, backfill → segredo (32 bytes) → 3 ajudantes internos → RPC → `REVOKE`/`GRANT` → postcheck V09 |
| `ROLLBACK_5391.sql` | remove os 8 objetos; recusa se a 5392 existir; não toca dados nem funções de participação |
| `S2_5391_PRE_readonly.sql` / `S2_5391_POST_readonly.sql` | um SELECT cada (arquivos separados para o executor por arquivo) |
| `S2_5391_MANIFEST.txt` | PRE (read) → 5391 (write) → POST (read), com sha256 |
| `static_check_5391.py` | **23/23 PASS**, com testes de mutação: coluna física no retorno → M6; GRANT em ajudante → M5; md5 alterado → C1; escopo aberto → M9; trava ausente → M2; parêntese desbalanceado → S0 |

**PASS do PRE:** todos os booleanos de primeiro nível verdadeiros. `escritores_*` é relatório; o esperado é apenas as funções já conhecidas (6119/6122–6126, 5380). Qualquer outro escritor é **STOP** para reavaliar a premissa de serialização.

**PASS do POST:** todos os booleanos verdadeiros; `participacoes` = `epocas`; barreira CLOSED; 0 identidades.

**STOP:** qualquer booleano falso, pgcrypto fora de `extensions`, gatilho preexistente em `collection_membership`, 55P03 ou erro na transação. Nada persiste e não há rollback.

**Desempenho:**
- AT_POSITION: O(alocações de X com aquela posição), pela junção a partir das alocações de X (`ix_collection_allocation_collection` e a chave única da atribuição). Não depende do volume das outras coleções.
- ASSIGNABLE: O(alocações de X), com o catálogo unido para filtro e ordem. O identificador e a imagem são calculados só para a página.
- Nenhum índice novo: não há evidência que o justifique.
- Critério a medir no TEST com volume real: p95 ≤ 300 ms por chamada para coleções de até 5 000 exemplares alocados. Acima disso → STOP de desempenho e avaliação de índice.

**Limitações:**
- A sintaxe **não foi compilada**: o sandbox não tem PostgreSQL nem acesso ao PyPI para o parser. Um erro de sintaxe aborta a transação inteira na rodada B, sem efeito.
- O executor PowerShell não foi executado: o sandbox não tem PowerShell. O `-Simular` deve ser rodado no Windows antes da rodada B.

## 14. Auditoria estática final da 5391 (2026-11-27, `S2/5391 FINAL SAFETY REVIEW + S4-a/5394 PREPARATION-01`)

| Foco | Resultado |
|---|---|
| Sintaxe e dependências | colunas e assinaturas conferidas no repositório (`collector_order`, `category_id`, `language_order`, `scope_kind`, `lifecycle_status`, perfis de variante; assinaturas de 5369, 5370, 5304, 5305 e 5306). Tipos do `RETURN QUERY` conferidos coluna a coluna. Estrutura balanceada (S0). **Não compilada** (sem PostgreSQL no sandbox) |
| Época | sequência `no cycle` e valor `UNIQUE` (nunca reutilizado); o gatilho só lê `OLD` no ramo UPDATE; backfill feito sob a trava que impede inclusões concorrentes; FK com CASCADE |
| Segredo | 32 bytes de `gen_random_bytes`; RLS sem políticas; sem privilégios para a API; só o ajudante o lê; a migration não o devolve |
| Privilégios e `search_path` | 4 funções definer com `search_path` vazio. O Supabase concede privilégios padrão a objetos novos, por isso há REVOKE explícito em tabelas, sequência e ajudantes; o postcheck confere |
| Isolamento | os dois modos filtram `ca.collection_id = X`; a representante é filtrada pela coleção; a posição precisa ser da Pokédex e do escopo de X |
| Identificadores inválidos | a 5391 só **emite** identificadores; recusar inválidos é da 5392 (`COPY_NOT_FOUND`) |
| Busca e ordem | limites validados antes da autorização (não revelam nada); LIKE escapado; número = 1–4 dígitos; desempate final pela alocação, que nunca é devolvida |
| EDITOR e barreira | `v1_13_editor_membership`: ACTIVE, EDITOR, não titular, coleção ACTIVE, com época. A barreira é a primeira instrução |
| **Defeito encontrado** | nenhum no SQL da migration. **Gate:** o POST não tinha um booleano para "toda participação tem época" (era uma comparação de números que o executor não avalia). Corrigido com `epocas_completas` |

**Executor v1.1** (`scripts/v1-13/Invoke-ReviewedSql.ps1`, revisão estática):
- **Defeito corrigido:** a v1.0 seguia para a migration mesmo com um PRE reprovado, porque o SELECT sai com código 0. Agora o modo `gate` avalia o resultado: booleanos de primeiro nível, `barreira`, `identidades_teste`, `executor` = `-Papel` e chaves `*_md5` iguais às do gate anterior. Um manifesto com escrita sem gate antes é recusado.
- Fora da simulação, exige `-ShaManifestoEsperado`, o sha256 auditado.
- Confere a versão da CLI.
- `scripts/v1-13/static_check_executor.py`: **9/9 PASS**.
- **O `-Simular` precisa ser rodado de novo no Windows com a v1.1.**

Manifesto atualizado para `gate → write → gate` (o sha256 muda; ver `S2_5391_MANIFEST.txt`). O `static_check_5391.py` continua **23/23 PASS**.

**Dependências da 5392:** ver S4 §9.4.

## 15. Tentativa de implantação da 5391 — STOP no PRE (2026-11-27 12:20Z) e correção

**Resultado.**
- O executor v1.2 parou no passo 1, o PRE em modo `gate`, com a CLI tendo saído com código 0.
- Motivos registrados: `executor = supabase_read_only_user (esperado postgres)`, `executor_dono_membership = false` e `pode_travar_membership = false`.
- O passo 2 (migration) **não foi chamado**; nada foi escrito.
- O PRE confirmou barreira CLOSED, 0 identidades, barreira canônica, participação canônica, `membership_sem_gatilho`, `pgcrypto_extensions` e `ausente_5391`.
- Registro: `Downloads\mmkyu-runs\run-20261127T122008Z`.

**Causa raiz (canal).**
- O executor enviava os `gate` com `--read-only`. Na CLI 3.2.0, `db query --remote --read-only` roda a consulta como `supabase_read_only_user`; a E1 já tinha registrado isso na S0.
- O PRE foi escrito para rodar com o papel da migration: prova que o executor é dono de `collection_membership` e pode travá-la. Os dois desenhos eram incompatíveis.
- Os canais que funcionaram antes são de escrita, sem `--read-only`, e rodaram como `postgres`:
  - as escritas da E1 (CLI `db query --remote --yes`);
  - a S3/5393 e a S1/5390 (`database/query` pelo conector).
- **Correção (executor v1.3):**
  - os `gate` rodam no papel da escrita, sem `--read-only`; só o modo `read` usa o papel de leitura;
  - a garantia de que um gate não escreve passa a ser do conteúdo: o executor recusa, antes de qualquer conexão, arquivo `gate`/`read` que não seja um único SELECT sem palavra de escrita fora de comentários e literais;
  - essa garantia se soma à do sha256 auditado e à do static check K1.
- A verificação do papel continua exigindo `postgres`. Nenhum privilégio foi alterado e o SQL da 5391 não mudou.

**Erro oculto encontrado na mesma evidência.**
- `escritores_atribuicao` e `escritores_representante` vieram vazios.
- Causa: em expressão regular do PostgreSQL, `\b` é backspace, não limite de palavra (que é `\y`).
- Corrigido no PRE da 5391 e no da 5394. Os manifestos foram regenerados.
- Verificação estática V15, com teste de mutação.

## 16. Implantação confirmada (2026-11-27 13:00:24Z)

Terceira tentativa autorizada: PASS. As duas anteriores pararam no PRE sem escrever (§15 e evidências). Detalhe, hashes e saídas de PRE/POST em `S2_5391_DEPLOY_EVIDENCE_2026-11-27.md`.

**Pendências:**
- provas funcionais, de segurança e de desempenho (TEST/E4);
- 5392 depende da 5394 (S4-a) implantada;
- 5395 (instrumentação do titular, referências de espécie, leituras) depois da 5394;
- extensão `regprocedure` no inventário dos próximos PRE (§ correção WRITER INVENTORY GATE);
- ajuste da 5373 para o identificador opaco (§12) antes da E4.

## 17. 5392 — escritas do EDITOR preparadas (2026-11-27, `S4-a/5394 PASS-LIVE CLOSEOUT + S2/5392 IMPLEMENTATION PREPARATION-01`) — NÃO EXECUTADA

**Funções (contrato §3.3–§3.6):**
- `editor_move_pokedex_copy`: atribuir (CREATED) e mover (MOVED);
- `editor_unassign_pokedex_copy`: REMOVED;
- `editor_choose_pokedex_representative`: SET e REPLACED;
- `editor_restore_pokedex_automatic_representative`: CLEARED;
- ajudante interno `v1_13_resolve_pokedex_copy`.

**Revogação:** na mesma transação, a 5392 revoga as 4 escritas da 5380 de todos os papéis de cliente. As funções ficam no catálogo.

**Ordem em cada RPC** (static check M5–M9 e M13):
1. barreira;
2. `assert_collection_editor`, que trava a coleção (FOR UPDATE) e a participação (FOR SHARE);
3. época vigente;
4. resolução do identificador: primeiro no escopo esperado, depois na coleção;
5. trava da alocação;
6. trava da representante;
7. `UNCHANGED`, que termina sem evento;
8. estado esperado (`STATE_CHANGED`);
9. espécie (`CONFIRMATION_REQUIRED`);
10. `collection_activity_open`;
11. escrita;
12. **um** `collection_activity_record_pokedex` por resultado efetivo.

Recusas e `UNCHANGED` acontecem antes de `open`, sem evento. A autoria é derivada no servidor, pela 5394.

**Inventário por assinatura completa** (`esquema.nome(tipos)`, ordem C):
- **PRE:** comparado pelo executor v1.4 com `S2_5392_EXPECTATIVAS.json` (os 5 + 4 escritores confirmados no LIVE, agora com assinatura).
- **POST:** exige, como booleano, o inventário anterior **mais** as 4 RPCs novas.

**Artefatos:**

| Arquivo | sha256 |
|---|---|
| `S2_5392_MANIFEST.txt` | `db2e608b3b4e35fbe24a6bbfed17a0756976246108d3dcf48a9da480ffcdba30` |
| PRE | `0dc02f1705abb4ef62523aaa58822631f2de991c3303ce936133337f0d3447e4` |
| Migration | `2376c4b33a1afe72b29681a41b21166c6117781681dfbd91f029f924d20fb598` |
| POST | `734bf6fbec1610f6b3900dfac3aa273e31d954340975c5c092a795452dbc1436` |
| Rollback | `2329a57bee4f05fa042228d68be70e1e8888448c1607169c460081854bd923c4` |
| Expectativas | `10d2f706929641c64564bd8e3ef5a4879795f63a027fe9c24124402732e37c68` |

**Verificação estática: 23/23.** Mutações detectadas:

| Mutação | Verificação que reprova |
|---|---|
| `open` depois da escrita | M6 |
| `record` removido | M6 |
| estado esperado não comparado | M8/M13 |
| representante esperada não comparada | M9/M13 |
| GRANT no resolvedor | M4 |
| 5380 não revogada | M4 |
| barreira fora da 1ª instrução | M5 |
| `physical_card_id` na interface | M10 |
| `UNCHANGED` depois de `open` | M7 |
| resolvedor sem filtro da coleção | M11 |
| `open` removido | M6/M7/M13 |

**Pendentes (não medidos, nada declarado PASS):**
- sintaxe e comportamento (sem PostgreSQL no sandbox);
- matriz de papéis, invalidação O1, concorrência em duas sessões, desempenho da resolução (O(k) no caminho comum, O(n) em conflito), tudo no TEST;
- inclusão das 4 RPCs novas no `EMERGENCY_STOP_V1_13.sql` antes de qualquer abertura;
- escrita sem filtro de escopo de gerações, como o titular (6122) e a 5380 (a leitura 5391 já filtra).

**Rollback:** remove as 5 funções e devolve a 5380 a `authenticated`, o que **reintroduz** o caminho sem auditoria explícita. Confira `acl_5380` no PRE para saber se `service_role` também constava.

## 18. 5392 v1.1 — correções contratuais finais (2026-11-27, `FINAL CONTRACT CORRECTIONS & DEPLOYMENT READINESS-01`) — NÃO EXECUTADA

**Rollback seguro.** `ROLLBACK_5392` v1.1 remove as 6 funções e **não concede nada**. O postcheck exige as 4 escritas da 5380 ainda revogadas para todo papel de cliente, e o EDITOR fica sem escrita de Pokédex.
- Restaurar a 5380 passa a ser uma **exceção separada** (`RESTORE_5380_EXCECAO_5392.sql`), com autorização específica, 5392 ausente e barreira CLOSED.
- Para só **suspender**, sem remover nada, usar o complemento de emergência abaixo.

**Escopo de gerações.**
- **Divergência confirmada:** a leitura 5391 e as grades 5204/5324 só aceitam posições do escopo da coleção. A 5392 v1.0 aceitava qualquer posição da Pokédex, o que permitiria, por RPC direta, atribuições invisíveis na grade.
- **Correção:** o ajudante interno `v1_13_pokedex_position_in_scope` aplica o mesmo critério da 5391 (`FULL_REFERENCE` ou geração listada). Ele é aplicado:
  - ao alvo de **mover**;
  - à posição atual em **escolher**;
  - à posição em **restaurar**.

  Fora do escopo, a recusa é neutra (`POKEDEX_POSITION_NOT_FOUND`), antes das travas da representante e de `open`.
- **Retirar** continua aceitando qualquer posição atual: é limpeza e não cria estado invisível.
- **Titular:** as funções 6122–6126 não filtram escopo. É preexistente, não foi alterado e fica registrado para a 5395. Ambas as interfaces já mostram só o escopo, então não há diferença visível entre titular e EDITOR.

**Emergência.** `EMERGENCY_STOP_V1_13_ADD_S2.sql` é um bloco E2b no mesmo formato do `g1/EMERGENCY_STOP_V1_13.sql`. Esse script é gerado e protegido e **não foi alterado**.
- **Revoga:** as 4 RPCs da 5392 e a leitura do EDITOR da 5391, de PUBLIC, anon e authenticated.
- **Não faz:** não concede nada (a 5380 continua revogada pelo E2 principal); não toca a 5393, porque revogá-la trocaria `CAPABILITY_NOT_ENABLED` por 42501 e quebraria o fallback C2. O E1 já a desliga.

**Integridade da auditoria.** O static check M15 garante, em cada RPC:
- um único `collection_activity_open`;
- nenhum `return` nem `raise` entre `open` e o primeiro `record`.

Qualquer erro posterior, inclusive do próprio `record`, aborta a transação inteira. A marcação é GUC local, então não sobra marcação sem registro. `UNCHANGED`, `STATE_CHANGED` e as demais recusas acontecem antes de `open`.

**Artefatos v1.1:**

| Arquivo | sha256 |
|---|---|
| Manifesto | `88bc25623308ea2028ab80b53aa53a5b737ce01124a9d89a8d5e9dcedbad5a07` |
| Migration | `fa92d9d5c770fcc51896ff1ed7e29dbda2777015e97773a2c3964adbac678ff3` |
| PRE | `db79d31a615ef4e8be7945a004755c9ce75af110d08b9c5150cf838c54b62ef3` |
| POST | `44cc42292a456405e1427dad1b940975f08851eaa2787287ef1abb9dcdf3c1f1` |
| Rollback | `f173ddda3ec5605c1ba2a7e1e7d3fe8657e84872e6f92e4399c89cf90511c7d7` |
| Exceção 5380 | `4db1a4e64e4d206ede4e1355290a57c511b1363a5231046458d876eea3a41246` |
| Emergência E2b | `70a9a130d6986a5c03e6deadddae3288cfe6c71c9ed060fee099b7d1a7d1f629` |
| Expectativas (inalteradas; o ajudante novo não escreve) | `10d2f706929641c64564bd8e3ef5a4879795f63a027fe9c24124402732e37c68` |

**Verificação estática: 27/27.** Mutações novas detectadas:

| Mutação | Verificação que reprova |
|---|---|
| rollback concedendo a 5380 | R1 |
| exceção sem exigir 5392 ausente | R2 |
| emergência concedendo algo | E1 |
| emergência sem uma RPC | E1 |
| mover sem escopo | M14 |
| restaurar só com a Pokédex | M14 |
| escopo sem o filtro de gerações | M14 |
| `return` entre `open` e `record` | M15 |
| GRANT no ajudante de escopo | M4 |

## 19. 5392 implantada (2026-11-27 14:02:33Z)

PRE, migration e POST com PASS. As 4 RPCs e os 2 ajudantes estão presentes, a 5380 está revogada, o inventário pós-migration é exato e não há eventos. Detalhe em `S2_5392_DEPLOY_EVIDENCE_2026-11-27.md`.

**Pendências:**
- provas funcionais (TEST/E4);
- disponibilizar `EMERGENCY_STOP_V1_13_ADD_S2.sql` antes de qualquer abertura;
- 5395 (titular explícito, referências de espécie, leituras do histórico);
- 5373 com identificador opaco antes da E4.
