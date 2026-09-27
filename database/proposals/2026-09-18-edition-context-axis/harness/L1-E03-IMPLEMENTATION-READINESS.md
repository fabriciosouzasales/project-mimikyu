# 2830H — L1 (Seção 2, 13 casos): readiness de implementação do E03

| Campo | Valor |
|---|---|
| **Natureza** | Preparação técnica e prova estática. **Sem implementação e sem execução**: o E03 e o E03P **não** foram escritos nesta preparação (foram implementados depois, localmente e sem execução, em `BATCH12-2830-P5-L1-E03-IMPLEMENTATION-01`; ver `harness/README.md`); nenhum SQL executado; nenhum acesso ao LIVE; nenhuma alteração em envelopes, schema, migrations, funções ou validações. |
| **Mandato** | `BATCH12-2830-P5-L1-IMPLEMENTATION-READINESS-01` (v1.0) e `BATCH12-2830-P5-L1-IMPLEMENTATION-READINESS-CORRECTION-01` (v1.1, blocker B-1), baseline HEAD `10eef142d46f8bd14e8008cae4e556444e3862cf`; `BATCH12-2830-P5-L1-E03-IMPLEMENTATION-CORRECTION-01` (v1.2, achado D-1, só documental), baseline HEAD `1467583206f221308bbb9a237fe0c08a2f4ea5e4`. |
| **Autoridades** | 2830 v7.0 (blob `b4647dcb…`, imutável) · `PHASE5-AUTOMATED-COVERAGE-READINESS.md` (blob `1aa8d71d…`) · `LIVE-VALIDATION-PROTOCOL.md` (blob `abe806d6…`) · E00 `a4dd8438…`, E01 `c4118b8c…`, E02 `3357ed46…`, E99 `49a71ecb…`. |
| **Escopo** | **Exclusivamente** 2.1, 2.2, 2.3, 2.4, 2.5, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13, 2.14 (13). **2.6 permanece reservado ao L5.** |
| **Estado** | **v1.3 — rastreamento da DP-4 = A (regra E03-20), para auditoria independente.** v1.2: correção documental do achado D-1. A v1.1 (blob `220fbd8b…`) foi aprovada e é a versão contra a qual E03, E03P e E03T foram implementados; a v1.2 não altera critério de caso, desenho da sonda nem regra de PASS/FAIL. Blocker B-1 (sonda de modo contaminando o IMMEDIATE seguinte) corrigido por sonda autocontida em subtransação própria (§2.6). N-1 fundamentado estaticamente, **não comprovado em runtime**. N-2 resolvido por correspondência demonstrada. Nenhum PASS novo. Estado das decisões na v1.3: DP-7 = A (E03T, executado e auditado); para o E03, DP-1 = A, DP-4 = A (implementada) e DP-5 = A, com autorização de escrita condicionada à auditoria e publicação do novo blob e a mandato próprio. **FREEZE ATIVO.** |

---

## 0. Resultado e STOP

| Gate | Resultado |
|---|---|
| **A** — contrato literal e dependências | Conforme. Os 13 casos correspondem à 2830 v7.0 (l. 453–477) e aos objetos efetivos da 2206 v2.0 (blob `2fcd4d74…`). A identidade repositório = LIVE está provada por cadeia de md5 (§1.3). Nenhuma dependência não documentada nas 3 tabelas escritas (§1.4). |
| **B** — `SET CONSTRAINTS` e subtransações | Viável pela documentação do PostgreSQL 17 e pelo código de `trigger.c` (§2). **Limitação declarada:** nunca executado neste harness. O E03 carrega sondas de modo **autocontidas** (§2.6, corrigidas na v1.1), e há um teste controlado opcional para mandato posterior (§2.8). |
| **C** — isolamento das fixtures | Conforme. Cada caso usa IDs próprios, criados e desfeitos na sua subtransação. Cada sonda cria e desfaz a própria linha e o próprio evento na sua subtransação, sem tocar as fixtures do caso. UPDATE/DELETE só em linha do próprio caso. Nenhum erro incidental aceito como PASS (§2.6, §3). |
| **D** — E03P e static_check | Contrato fechado sem alterar o E00: E03P com 12 gates (§5) e perfil E03 com 19 regras (§6). |
| **E** — protocolo futuro | Sequência S0 → L1 (canal) → L3 → E00 → E03P → E03 → E99 → L3 especificada, com STOP e prova tripla (§7). |

**STOP: não houve.** A análise não encontrou risco material de segurança, integridade, semântica, concorrência, performance ou perda de dados. As escritas previstas são transitórias, só em linhas de fixture de 3 tabelas EC, sempre desfeitas por subtransação e pelo término em exceção. Qualquer execução continua dependendo de DP-5.

**Blocker B-1 (auditoria da v1.0): corrigido na v1.1.** A sonda de modo da v1.0 deixava um evento diferido pendente na subtransação do caso, e em 2.7 esse evento seria processado pelo IMMEDIATE de Pb. A sonda passa a rodar em subtransação própria, encerrada sempre por uma sentinela exclusiva (`H283S`), e a matriz de eventos do §2.6.4–§2.6.5 mostra que cada IMMEDIATE processa exatamente os eventos previstos. Nenhum blocker novo; as limitações remanescentes estão no §2.6.6.

**Achado D-1 (auditoria da implementação): corrigido na v1.2, só no texto.** A função de selo da 2206 (l. 70–74) retorna sem efeito quando o profile do evento não existe mais. Um evento hipotético de sonda que sobrevivesse ao rollback da sonda não levantaria `EMPTY_COMPOSITION`: seria um no-op. O §2.6.4, o §2.6.6, o §2.8, o §3.3 e o §8 foram ajustados, e o §2.6.7 separa o que é esperado, o que é observável pelo E03T e o que continua não comprovado. A conclusão de isolamento não muda.

> Nota de nomenclatura: neste documento, **"L1 (canal)"** é a consulta de canal do protocolo (md5 `0836c36a…`). **"Lote L1"** é este conjunto de 13 casos.

## 1. Gate A — contrato literal e dependências

### 1.1 Contrato 2830 v7.0 (l. 453–477) × objeto efetivo da 2206 v2.0

| Caso | Texto da 2830 | Objeto que decide | Contrato de erro/efeito efetivo (2206 blob `2fcd4d74…`) |
|---|---|---|---|
| 2.1 | selo = ARRAY(N:N ORDER BY trait_id) após IMMEDIATE | `trg_cecp_seal` → `internal.seal_edition_context_composition()` | UPDATE do próprio profile com `ARRAY(SELECT trait_id … ORDER BY trait_id)` (l. 80–99) |
| 2.2 | profile sem N:N ⇒ `EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION` | idem | `RAISE EXCEPTION 'EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION: …'` (l. 88) |
| 2.3 | 2º INSERT na N:N de profile selado ⇒ COMPOSITION_IMMUTABLE | `trg_cecpt_immutable` → `internal.guard_edition_context_composition_immutable()` | `'EDITION_CONTEXT_COMPOSITION_IMMUTABLE: …'` (l. 165); reinserção **idêntica** passa (l. 149–163) |
| 2.4 | DELETE na N:N de profile selado ⇒ COMPOSITION_IMMUTABLE | idem (evento DELETE) | idem (l. 165) |
| 2.5 | trait inativo ⇒ TRAIT_INACTIVE | `trg_cecpt_trait_active` → `internal.guard_edition_context_trait_active()` | `'EDITION_CONTEXT_TRAIT_INACTIVE: …'` (l. 244) |
| 2.7 | mesma assinatura ⇒ `uq_cecp_game_signature` (23505) | índice único parcial (2204 l. 111–113) | 23505 no UPDATE do selo, dentro da função A |
| 2.8 | assinatura NULL não colide | predicado `WHERE traits_signature IS NOT NULL` (2204 l. 113) | ausência de erro |
| 2.9 | N:N decrescente ⇒ selo ascendente | `ORDER BY t.trait_id` (2206 l. 83) | efeito |
| 2.10 | repetição na N:N ⇒ PK 23505; cardinality(selo) = COUNT(N:N) | `pk_cecpt` (2205 l. 25) | 23505 |
| 2.11 | UPDATE falsificando selo em montagem ⇒ `EDITION_CONTEXT_SIGNATURE_MISMATCH` | `trg_cecp_signature_write` → `internal.enforce_edition_context_signature_write()` | `'EDITION_CONTEXT_SIGNATURE_MISMATCH: …'` (l. 217) |
| 2.12 | UPDATE alterando selo gravado ⇒ `EDITION_CONTEXT_SIGNATURE_IMMUTABLE` | idem | `'EDITION_CONTEXT_SIGNATURE_IMMUTABLE: …'` (l. 201) |
| 2.13 | UPDATE voltando selo a NULL ⇒ idem | idem (`NEW IS DISTINCT FROM OLD`, OLD não nulo) | idem (l. 201) |
| 2.14 | UPDATE sem tocar o selo (ex.: `name`) é permitido; só fixture | `trg_cecp_signature_write` é `BEFORE UPDATE OF traits_signature` (l. 227–230) e **não dispara** | ausência de erro; `name` alterado |

### 1.2 SQLSTATE e MESSAGE_TEXT — N-2 resolvido

- As 5 funções levantam com `RAISE EXCEPTION '<TOKEN>: …'` **sem** cláusula `ERRCODE`. Pela documentação do PL/pgSQL, o SQLSTATE resultante é `P0001` (`raise_exception`).
- Nas 5 migrations do núcleo EC (2203–2207) há 15 tokens distintos. A tabela abaixo mostra que cada nome usado pela 2830 aparece em **exatamente um** deles:

| Nome na 2830 | Tokens que o contêm | Prefixo exigido no E03 |
|---|---|---|
| `EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION` (2.2) | 1 — ele mesmo | `EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION:` |
| `COMPOSITION_IMMUTABLE` (2.3, 2.4) | 1 — `EDITION_CONTEXT_COMPOSITION_IMMUTABLE` | `EDITION_CONTEXT_COMPOSITION_IMMUTABLE:` |
| `TRAIT_INACTIVE` (2.5) | 1 — `EDITION_CONTEXT_TRAIT_INACTIVE` | `EDITION_CONTEXT_TRAIT_INACTIVE:` |
| `EDITION_CONTEXT_SIGNATURE_MISMATCH` (2.11) | 1 — ele mesmo | `EDITION_CONTEXT_SIGNATURE_MISMATCH:` |
| `EDITION_CONTEXT_SIGNATURE_IMMUTABLE` (2.12, 2.13) | 1 — ele mesmo | `EDITION_CONTEXT_SIGNATURE_IMMUTABLE:` |

**Conclusão N-2:**
- Nenhum código novo é criado. O E03 compara com o **token implementado completo, seguido de `:`**, que é o único token do corpus que contém o nome do contrato.
- Os dois pontos impedem colisão com tokens vizinhos (ex.: `EDITION_CONTEXT_MAPPING_COMPOSITION_SEALED` não contém `EDITION_CONTEXT_COMPOSITION_IMMUTABLE`).
- **Regra de comparação:** `starts_with(v_msg, '<TOKEN>:')`, **nunca** `LIKE`, porque `_` em `LIKE` é curinga.

### 1.3 Identidade repositório = LIVE (cadeia de md5, sem SQL nesta rodada)

| Função | md5 do corpo em 2206 (calculado agora) | Pino no E00 (l. 173–176) | `body_md5_lf` no LIVE (E00 da Etapa 3, registro `974674f9…` l. 365) |
|---|---|---|---|
| `internal.seal_edition_context_composition` | `6077409a…` | `6077409a…` | `6077409a…` |
| `internal.guard_edition_context_composition_immutable` | `cfdcb500…` | `cfdcb500…` | `cfdcb500…` |
| `internal.enforce_edition_context_signature_write` | `caa2e4d4…` | `caa2e4d4…` | `caa2e4d4…` |
| `internal.guard_edition_context_trait_active` | `68fb05f1…` | `68fb05f1…` | `68fb05f1…` |

- Na Etapa 3 (2026-09-27 03:41Z), o gate `g_p7_identity_pinned = true` provou essa igualdade no LIVE.
- O E00 de cada rodada futura volta a provar a identidade antes do E03. Se o pino divergir, o resultado é STOP.

### 1.4 Ausência de dependências não documentadas

Fonte: inventário P7 do E00 executado na Etapa 3 (`d_p7_functions`, registro `974674f9…` l. 365):

| Tabela escrita pelo lote L1 | Funções alcançadas (trigger/CHECK/DEFAULT/índice) no LIVE |
|---|---|
| `card_edition_context_trait` | **nenhuma** |
| `card_edition_context_profile` | `trg_cecp_seal` (SEAL), `trg_cecp_signature_write` (GUARD) |
| `card_edition_context_profile_trait` | `trg_cecpt_immutable` (GUARD), `trg_cecpt_trait_active` (GUARD) |

Também confirmado no mesmo registro:
- **Escritas** (`d_p7_writes`): a única escrita alcançada nessas tabelas é `seal_edition_context_composition` → `public.card_edition_context_profile`.
- **Sequences** (`d_sequences`): `[]` nas 10 tabelas inventariadas.
- **RLS** (`d_ownership_rls`): as 3 tabelas com dono `postgres`, `force_rls = false`.
- **Updated_at:** não há trigger de `updated_at` nessas tabelas; o selo grava `updated_at = now()` explicitamente (2206 l. 97).

Tudo isso é evidência **histórica** (03:41Z). O E00 e o E03P de cada rodada futura revalidam (§5).

### 1.5 Semântica DEFERRED e ordem de disparo

| Fato | Fonte |
|---|---|
| `trg_cecp_seal` é `CONSTRAINT TRIGGER … AFTER INSERT ON card_edition_context_profile DEFERRABLE INITIALLY DEFERRED FOR EACH ROW` | 2206 l. 109–113 |
| `trg_cecem_seal` é idêntico, em `card_edition_context_external_mapping` | 2207 l. 483–487 |
| Constraint triggers disparam quando o constraint associado seria verificado; o modo é controlado por `SET CONSTRAINTS` | docs PG 17, *SET CONSTRAINTS* |
| Num teste que termina em rollback, os DEFERRED nunca disparam sozinhos | 2830 P4 (l. 226–235) |
| Vários triggers do mesmo evento e relação disparam em **ordem alfabética** de nome | docs PG 17, §37.1 |
| INSERT na N:N: `trg_cecpt_immutable` (i) antes de `trg_cecpt_trait_active` (t) | nomes na 2206 l. 172 e 253 |
| `UPDATE OF col` só dispara se `col` estiver no `SET` do UPDATE | docs PG 17, §37.1 |

Consequências para os casos:
- **2.3:** profile selado, trait ativo diferente. `immutable` levanta antes de `trait_active` rodar.
- **2.5:** profile em montagem. `immutable` retorna `NEW` e `trait_active` levanta.
- **2.14:** o UPDATE de `name` não dispara `trg_cecp_signature_write`.

### 1.6 Condições de rollback

- Cada caso roda em sub-bloco `BEGIN … EXCEPTION` e termina **sempre** em `RAISE … ERRCODE 'H283C'`. Isso desfaz a subtransação do caso: fixtures, eventos DEFERRED enfileirados e estado de `SET CONSTRAINTS` (§2.4).
- Cada sonda de modo roda em sub-bloco próprio, aninhado no caso, e termina **sempre** em `RAISE … ERRCODE 'H283S'` (caminho normal) ou em `H283F` (falha). Isso desfaz só a linha e o evento da sonda; as fixtures do caso ficam intactas (§2.6).
- O envelope termina **sempre** em `H283P` (sucesso) ou `H283F` (falha). Os dois abortam a transação inteira. Não existe caminho de COMMIT (2830 P2).
- Resíduo não-transacional aceito (protocolo §5.3): estatísticas, tuplas mortas, WAL e logs.

## 2. Gate B — N-1: `SET CONSTRAINTS` dentro do DO

### 2.1 Sintaxe aplicável

```sql
SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;
-- medir
SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;
```

| Ponto | Fundamento |
|---|---|
| Comando direto no PL/pgSQL, **sem** `EXECUTE` | docs PG 17 §41.5.2: qualquer comando SQL que não retorna linhas pode ser escrito diretamente. Os nomes são constantes: não há variável a substituir, logo não é preciso SQL dinâmico. |
| Nomes qualificados | docs *SET CONSTRAINTS*: cada nome pode ser qualificado por schema. O constraint de um constraint trigger tem o nome do trigger e fica no schema da tabela (`public`). |
| Ambiguidade de nome | docs *SET CONSTRAINTS*, Notes: nomes não são únicos por schema, e o comando age sobre **todas** as correspondências. **Mitigação:** o gate `g_seal_constraint_names_unique` do E03P exige exatamente 1 constraint com cada nome em `public`. |
| Exigência de deferrable | docs: os nomes listados precisam ser deferrable. O E03P verifica `condeferrable` e `condeferred`. |
| Escopo transacional | docs: o comando altera só a transação corrente. Dentro do DO, a transação é a do envelope, que termina sempre em exceção. **Não** é alteração de sessão, `SET LOCAL` nem `set_config`. |

### 2.2 IMMEDIATE que dispara exceção

- **docs *SET CONSTRAINTS*:** ao passar de DEFERRED a IMMEDIATE, os eventos pendentes são verificados durante o próprio comando. Se algum falha, o comando falha **e não muda o modo**.
- Logo, nos negativos 2.2 e 2.7 a exceção é levantada **no** `SET CONSTRAINTS … IMMEDIATE`, e o modo continua DEFERRED.

### 2.3 Subtransação do negativo

- **Desenho obrigatório:** em todo negativo FXd (2.2 e o segundo profile de 2.7), as fixtures que geram o evento **e** o `SET … IMMEDIATE` ficam no **mesmo** sub-bloco interno.
- Quando o sub-bloco aborta, somem juntos a linha e o evento. Nada fica pendente para um IMMEDIATE posterior.
- O handler do sub-bloco captura `RETURNED_SQLSTATE`, `MESSAGE_TEXT`, `CONSTRAINT_NAME` e `TABLE_NAME`, e depois executa `SET … DEFERRED` (P4, item 3). O corpo do sub-bloco também termina em `SET … DEFERRED`, alcançado só se o IMMEDIATE não falhar (caminho que já é FAIL); assim o P4 vale nos dois caminhos.
- **Atribuição do erro ao IMMEDIATE (v1.1):** imediatamente antes do `SET … IMMEDIATE`, o sub-bloco faz `v_step := 'IMMEDIATE'`; cada statement anterior do sub-bloco é precedido do seu próprio `v_step`. Como as variáveis locais conservam o valor do momento do erro (docs PG 17 §41.6.8), o aceite exige `v_step = 'IMMEDIATE'`: um erro levantado por um INSERT de fixture, mesmo com o SQLSTATE esperado, vira FAIL.
- **A sonda nunca fica dentro do sub-bloco negativo nem do handler:** o `WHEN OTHERS` do negativo engoliria o `H283F` da sonda. Ela roda depois do `END` do sub-bloco (§2.6).

### 2.4 Restauração do estado antes do próximo caso

Comentários de `trigger.c` sobre `AfterTriggersTransData`:
- **`state`:** cada nível de subtransação que muda o estado de `SET CONSTRAINTS` guarda uma cópia antes e a restaura se abortar.
- **`events`:** os ponteiros da fila de eventos são restaurados no abort da subtransação.
- **`firing_counter`:** identifica os eventos deferidos disparados (ou marcados) dentro de uma subtransação abortada.

Três camadas garantem DEFERRED ao entrar em cada caso:
1. o `SET … DEFERRED` explícito (P4, item 3);
2. a regra "falhou, não muda o modo" (§2.2);
3. o abort da subtransação do caso (`H283C`), que restaura estado e fila.

### 2.5 Eventos pendentes entre casos e dentro do caso

**Entre casos — disparo cruzado impossível pelo desenho:**
- cada caso cria e desfaz suas próprias linhas e eventos na própria subtransação;
- ao sair do caso não resta evento pendente;
- `trg_cecem_seal` é nomeado só para cumprir o P4 literalmente ("nos dois triggers"); o lote L1 não cria mapping, então não há evento dele;
- o envelope é uma transação nova, sem eventos anteriores.

**Dentro do caso:**
- Os únicos eventos diferidos possíveis no lote L1 são de `trg_cecp_seal`. É a única constraint `DEFERRABLE` nas 3 tabelas escritas (2206 l. 111). As FKs da N:N (2205 l. 28–34) e a FK para `game` (2203 l. 47, 2204 l. 68) não declaram `DEFERRABLE`, logo são verificadas no fim de cada statement e nunca ficam pendentes. O E03P revalida isso no LIVE (`g_deferrable_only_seal`, §5).
- Os guards da N:N e o `trg_cecp_signature_write` são `BEFORE`: não enfileiram evento. O selo é `AFTER INSERT`: UPDATE e DELETE não o enfileiram.
- Logo, cada INSERT de profile enfileira exatamente um evento, e nada mais enfileira. O §2.6.4–§2.6.5 mostra, para cada IMMEDIATE, o conjunto exato de eventos processados.

### 2.6 Sonda de modo autocontida (corrigida na v1.1)

#### 2.6.1 Diagnóstico do blocker B-1 (v1.0)

- Na v1.0, a sonda inseria um profile sem N:N **diretamente na subtransação do caso**. Em modo DEFERRED esse INSERT enfileira um evento de `trg_cecp_seal`, que só seria descartado pelo `H283C` no fim do caso.
- Em 2.7, esse evento ainda estaria pendente quando o sub-bloco negativo executasse `SET … IMMEDIATE` para Pb. Ao passar a IMMEDIATE, o comando verifica **todos** os eventos pendentes dos constraints nomeados (docs *SET CONSTRAINTS*), não só os de Pb.
- Na v1.0 a linha da sonda **continuava existindo** (só seria desfeita pelo `H283C`), então o selo passava pelo teste de existência (2206 l. 70–74) e levantava `EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION` (2206 l. 88). O resultado de 2.7 passaria a depender da ordem de processamento da fila, que não é contrato documentado. Na ordem de enfileiramento, o evento da sonda vem antes do de Pb e o caso receberia `P0001` em vez de `23505`/`uq_cecp_game_signature`.
- **Efeito:** a sonda alterava a pré-condição que devia proteger. Nos demais casos FXd a sonda da v1.0 não era seguida de outro IMMEDIATE, mas o padrão era inseguro por construção.

#### 2.6.2 Estrutura corrigida

Gabarito estrutural (**não é o E03**; nomes de variáveis ilustrativos). A sonda roda imediatamente após o `SET … DEFERRED` do caminho normal, ou após o `END` do sub-bloco negativo e das suas asserções:

```sql
v_qn   := v_qn + 1;                          -- contador do envelope; 11 sondas no lote L1
v_qtag := format('H2830_PROBE: envelope=%s caso=%s n=%s marker=%s', c_env, v_case, v_qn, v_marker);
v_q    := NULL;
v_qok  := NULL;
BEGIN                                        -- subtransação Q, exclusiva da sonda
    INSERT INTO public.card_edition_context_profile (game_id, code, name, display_order)
    VALUES (v_game, v_marker || '_Q' || v_qn, 'H2830 sonda ' || v_marker, v_order_q)
    RETURNING id INTO v_q;                   -- em IMMEDIATE, o selo dispararia no fim deste INSERT
    SELECT (traits_signature IS NULL) INTO v_qok
      FROM public.card_edition_context_profile WHERE id = v_q;
    IF v_q IS NULL OR v_qok IS DISTINCT FROM true THEN
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=%s sonda n=%s sem efeito observável', c_env, v_case, v_qn);
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'H283S', MESSAGE = v_qtag;   -- sentinela: desfaz Q
EXCEPTION
    WHEN SQLSTATE 'H283S' THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg IS DISTINCT FROM v_qtag THEN
            RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
                'H2830_FAIL: envelope=%s caso=%s sentinela de sonda trocada (%s)', c_env, v_case, v_msg);
        END IF;
    WHEN SQLSTATE 'H283F' THEN RAISE;
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
            'H2830_FAIL: envelope=%s caso=%s sonda n=%s modo não DEFERRED ou erro inesperado sqlstate=%s msg=%s',
            c_env, v_case, v_qn, v_state, v_msg);
END;
SELECT count(*) INTO v_n FROM public.card_edition_context_profile WHERE id = v_q;
IF v_n <> 0 THEN
    RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(
        'H2830_FAIL: envelope=%s caso=%s sonda n=%s não descartada', c_env, v_case, v_qn);
END IF;
v_q := NULL;
```

- `v_order_q` = base do caso + 1090 (fora da faixa `+1000+k`, k ≤ 9, das fixtures do caso; F-3). Linhas de sondas diferentes nunca coexistem, porque cada uma é desfeita antes da seguinte.
- A sonda não executa `SET`, UPDATE, DELETE nem INSERT na N:N.
- Depois da sonda, o caso refaz as asserções que dependem das fixtures anteriores (por exemplo, Pa selado em 2.7) antes de escrever de novo.

#### 2.6.3 Os 7 requisitos do mandato × estrutura

| # | Requisito | Como a estrutura garante | Fundamento | Detecção em runtime |
|---|---|---|---|---|
| 1 | Confirmar DEFERRED | O INSERT da sonda termina sem erro e o selo continua `NULL`. Em IMMEDIATE, o constraint trigger `AFTER ROW` dispararia no fim do INSERT e levantaria `EMPTY_COMPOSITION` (2206 l. 88), capturado pelo `WHEN OTHERS` da sonda e convertido em `H283F`. | docs *CREATE TRIGGER* (constraint trigger: fim do statement ou fim da transação, conforme o modo) e *SET CONSTRAINTS*; `tgenabled = 'O'` exigido pelo E03P (`g_s2_triggers`) | sim: o próprio INSERT |
| 2 | Descartar a fixture da sonda | O corpo de Q não tem saída normal: termina em `H283S` ou em erro. Toda saída de Q por exceção desfaz as alterações feitas dentro do bloco. | docs PG 17 §41.6.8 ("all changes to persistent database state within the block are rolled back") | sim: `count(*) … WHERE id = v_q` = 0 após o `END` (a variável conserva o id, §41.6.8) |
| 3 | Nenhum evento da sonda sobrevive | O evento é enfileirado dentro de Q. No abort de uma subtransação, a fila de eventos volta ao estado do início dela. | comentários de `trigger.c` (`AfterTriggersTransData.events`) | **não observável diretamente** (v1.2): um evento remanescente encontraria a linha já desfeita e seria no-op (2206 l. 70–74). O E03T T3 observa só a ausência de contaminação do IMMEDIATE posterior (§2.6.7) |
| 4 | Não desfazer as fixtures do caso | O rollback de Q volta ao ponto de entrada de Q. O que o caso escreveu antes (T1, T2, Pa e o selo de Pa) fica fora do bloco. O evento de Pa, disparado em C antes de Q, mantém a marca de processado: só eventos disparados dentro da subtransação abortada são desmarcados. | docs §41.6.8 (exemplo: o INSERT anterior ao bloco não é desfeito); `trigger.c` (`firing_counter`) | sim: asserções pós-sonda (Pa selado e igual; contagem das fixtures) |
| 5 | Sentinela capturada por identidade exata, sem mascarar erro | O handler aceita só `SQLSTATE 'H283S'` **e** `MESSAGE_TEXT` igual a `v_qtag` (envelope, caso, número da sonda, marcador da execução). `H283F` é repassado. Todo o resto cai no `WHEN OTHERS` e vira `H283F`. `H283S` só é levantado pelo último statement de Q: as funções da 2206 levantam sem `ERRCODE` (`P0001`, §1.2) e o PostgreSQL não usa a classe `H2`. `57014` e `P0004` não são capturados por `OTHERS` (docs §41.6.8) e abortam o envelope. | docs §41.6.8; §1.2 | sim: sentinela com mensagem diferente vira `H283F` |
| 6 | `H283C`, `H283F` e `H283P` exclusivos | `H283S` é um sinal novo do harness, na mesma classe `H283x` declarada no cabeçalho do E01 (l. 20–23), usado só na sonda. `H283C` continua só no fim de caso, `H283F` só em falha e `H283P` só no fim do envelope. `H283S` nunca sai da sonda; se saísse (defeito), o `WHEN OTHERS` do caso o converteria em `H283F`. | E01 l. 20–25; regras E03-12 e E03-17 (§6) | estática (static_check) |
| 7 | Modo restaurado antes de prosseguir | A sonda vem depois do `SET … DEFERRED` e não executa `SET`. O abort de Q não mexe no estado de `SET CONSTRAINTS` de C, porque Q não o alterou. Se o modo não for DEFERRED, a sonda gera `H283F` e o envelope aborta: não há "prosseguir" com o modo errado. | docs *SET CONSTRAINTS*; `trigger.c` (`state`: só o nível que altera o estado guarda cópia) | sim: requisito 1 |

#### 2.6.4 Caso 2.7 — sequência completa e eventos pendentes

Notação: **E** = transação do envelope; **C** = subtransação do caso (fim em `H283C`); **Q1/Q2** = sondas (fim em `H283S`); **N** = sub-bloco negativo (fim no erro esperado); ev(X) = evento de `trg_cecp_seal` do profile X. Em todas as etapas `trg_cecem_seal` não tem evento (§2.5).

| # | Etapa | Pilha | Fixtures visíveis | Eventos pendentes | Modo `trg_cecp_seal` | IMMEDIATE processa | Resultado esperado | Erro inesperado |
|---|---|---|---|---|---|---|---|---|
| 0 | Entrada no caso; variáveis de fixture a `NULL` | E›C | nenhuma | ∅ (casos anteriores abortados, §2.5) | DEFERRED | — | — | — |
| 1 | INSERT T1, T2 (trait) | E›C | T1, T2 | ∅ (trait sem trigger, §1.4) | DEFERRED | — | 2 ids | `WHEN OTHERS` do caso → `H283F` |
| 2 | INSERT Pa; INSERT N:N (Pa,T1), (Pa,T2) | E›C | + Pa (selo `NULL`), 2 N:N | {ev(Pa)} | DEFERRED | — | guards passam (Pa em montagem, T ativos) | idem |
| 3 | `SET … IMMEDIATE` | E›C | Pa selado | ∅ (ev(Pa) processado em C) | IMMEDIATE | **{ev(Pa)}** | selo de Pa = ARRAY(T1,T2) ordenado; `signature_write` aceita (OLD `NULL`, NEW = composição real) | idem |
| 4 | Asserção: Pa selado e igual ao esperado; `SET … DEFERRED` | E›C | T1, T2, Pa selado | ∅ | DEFERRED | — | asserção verdadeira | `H283F` |
| 5 | Q1: INSERT q1; asserção selo `NULL` | E›C›Q1 | + q1 (selo `NULL`) | {ev(q1)} | DEFERRED | — | INSERT sem erro (prova de DEFERRED) | modo IMMEDIATE → `EMPTY_COMPOSITION` no INSERT → `WHEN OTHERS` de Q1 → `H283F` |
| 6 | Q1: `RAISE H283S` → handler | E›C | q1 desfeita; T1, T2, Pa intactos | **∅** (fila de volta ao início de Q1) | DEFERRED (Q1 não alterou o estado) | — | `MESSAGE_TEXT = v_qtag` | mensagem diferente → `H283F` |
| 7 | Pós-Q1: `count(q1) = 0`; Pa ainda selado e igual | E›C | T1, T2, Pa selado | ∅ | DEFERRED | — | verdadeiro | `H283F` |
| 8 | N: INSERT Pb; INSERT N:N (Pb,T1), (Pb,T2) (cada um com seu `v_step`) | E›C›N | + Pb (selo `NULL`), 2 N:N | {ev(Pb)} | DEFERRED | — | sem erro | capturado por N; falha na checagem (step ≠ IMMEDIATE) → `H283F` |
| 9 | N: `v_step := 'IMMEDIATE'`; `SET … IMMEDIATE` | E›C›N | idem | {ev(Pb)} | tentativa de IMMEDIATE | **exatamente {ev(Pb)}** | selo de Pb calcula ARRAY(T1,T2) = assinatura de Pa; `signature_write` aceita; o índice rejeita: `23505`; o SET falha | outro SQLSTATE, constraint, tabela ou step → `H283F` na checagem |
| 10 | Handler de N (N abortada): captura diagnósticos; `SET … DEFERRED` | E›C | Pb e N:N de Pb desfeitos; T1, T2, Pa intactos | ∅ | DEFERRED (falha não muda o modo; estado restaurado) | — | — | — |
| 11 | Asserções: `v_got`; `23505`; `CONSTRAINT_NAME = 'uq_cecp_game_signature'`; `TABLE_NAME = 'card_edition_context_profile'`; `v_step = 'IMMEDIATE'`; `count(Pb) = 0`; Pa selado e igual | E›C | T1, T2, Pa selado | ∅ | DEFERRED | — | todas verdadeiras | `H283F` |
| 12 | Q2 (como 5–7) | E›C›Q2 → E›C | idem | ∅ ao fim | DEFERRED | — | como Q1 | como Q1 |
| 13 | `RAISE H283C` → handler do caso | E | nenhuma | ∅ (C abortada) | DEFERRED (estado da entrada de C) | — | `v_done` recebe 2.7 | sinal trocado → `H283F` |

**Por que a sonda não pode interferir no resultado de 2.7:**
- **Pela estrutura:** na etapa 9 a fila contém exatamente ev(Pb). ev(Pa) já foi processado na etapa 3, ev(q1) saiu com Q1 na etapa 6, e nada mais enfileira evento (§2.5).
- **Pelo aceite, mesmo num vazamento hipotético (corrigido na v1.2):** o resultado aceito (`23505` em `uq_cecp_game_signature`, com `v_step = 'IMMEDIATE'`) só pode vir do selo de um profile cuja composição seja igual à de Pa. Só Pb tem essa composição. Um evento de sonda que sobrevivesse ao rollback da sonda encontraria a linha q1 já desfeita e o selo retornaria sem efeito (2206 l. 70–74): **não** levantaria `EMPTY_COMPOSITION`, não selaria nada e não alteraria o erro de Pb. Um vazamento não gera PASS falso nem FAIL, em qualquer ordem de fila.
- **Estado esperado × observável:** a coluna "Eventos pendentes" registra o estado **esperado** pela semântica transacional do PostgreSQL (§2.4, `trigger.c`). O E03 **não observa** a fila; observa só os efeitos (selo, contagens, SQLSTATE, `v_step`). Ver §2.6.7.
- **Após o negativo:** Q2 fica pendente só dentro de Q2 e sai com ela. Não há IMMEDIATE depois de Q2.

#### 2.6.5 Demais casos: eventos processados por IMMEDIATE

| Caso | IMMEDIATE (subtransação) | Eventos processados | Sondas | Escrita depois da sonda | IMMEDIATE depois de sonda? |
|---|---|---|---|---|---|
| 2.1 | 1 (C) | {ev(P)} | Q1 após o DEFERRED | nenhuma | não |
| 2.2 | 1 (N) | {ev(P)} → `EMPTY_COMPOSITION` esperado | Q1 após o `END` de N e as asserções | nenhuma | não |
| 2.3 | 1 (C) | {ev(P)} | Q1 | sub-bloco com INSERT N:N (P,T2): guard `BEFORE`, sem evento | não |
| 2.4 | 1 (C) | {ev(P)} | Q1 | sub-bloco com DELETE N:N: guard `BEFORE`, sem evento | não |
| 2.7 | 2 (C; N) | {ev(Pa)}; {ev(Pb)} | Q1 entre os dois; Q2 após N | N (Pb e N:N de Pb) | sim, só aqui — isolado por Q1 (§2.6.4) |
| 2.9 | 1 (C) | {ev(P)} | Q1 | nenhuma | não |
| 2.10 | 1 (C) | {ev(P)} (o INSERT duplicado roda antes, em sub-bloco próprio, e não enfileira selo) | Q1 | nenhuma | não |
| 2.12 | 1 (C) | {ev(P)} | Q1 | sub-bloco com UPDATE do selo: o selo é `AFTER INSERT`, sem evento | não |
| 2.13 | 1 (C) | {ev(P)} | Q1 | idem | não |
| 2.14 | 1 (C) | {ev(P)} | Q1 | UPDATE de `name`: sem evento | não |
| 2.5, 2.8, 2.11 (FX) | nenhum | — (ev dos profiles fica pendente até o `H283C`) | nenhuma (sem `SET CONSTRAINTS`) | — | não |

Total: 11 IMMEDIATE, 13 `SET … DEFERRED` (9 de caminho normal e 4 nos 2 negativos, corpo e handler) e 11 sondas — uma por IMMEDIATE.

#### 2.6.6 Limites da correção

- **Estático, não runtime:** a remoção do evento no abort de Q vem da semântica de subtransação do PostgreSQL e dos comentários de `trigger.c`, não de execução. **Não há detecção direta** (v1.2): nem o E03 nem o E03T T3 distinguem "evento removido" de "evento remanescente executado como no-op", porque o selo da 2206 não faz nada quando o profile não existe (l. 70–74). O que pode ser observado é a ausência de contaminação (§2.6.7).
- **Só `trg_cecp_seal` é sondado.** O modo de `trg_cecem_seal` muda no mesmo comando, mas não é observável no lote L1, que não cria mapping (e por isso também não o afeta).
- **`H283S` é sinal novo do harness.** Não é código da 2830 nem do protocolo, e nunca chega ao canal: o protocolo continua vendo só `H283P` ou `H283F`. A aceitação do sinal fica com a auditoria.
- **Custo:** 11 subtransações, 11 INSERTs e 22 leituras a mais no envelope, todas desfeitas. O limite de tempo continua o do §7 (`elapsed_ms ≤ 60000`).

#### 2.6.7 Esperado, observável e não comprovado (v1.2)

| Afirmação | Esperado pela semântica do PostgreSQL | Observável pelo E03T (T1–T3) | Ainda não comprovado em runtime |
|---|---|---|---|
| A sonda confirma DEFERRED | Em DEFERRED o constraint trigger não dispara no fim do INSERT; em IMMEDIATE dispararia e levantaria `EMPTY_COMPOSITION` | Sim: o INSERT da sonda termina sem erro e o selo continua `NULL` (T1, T2, T3) | Todo o padrão, até a primeira execução autorizada |
| A linha da sonda é desfeita | O rollback do bloco desfaz o que foi escrito nele (docs §41.6.8) | Sim: `count(*) … WHERE id = v_q` = 0 depois do `END` | Idem |
| O evento da sonda é removido da fila | O abort da subtransação devolve a fila ao estado do início dela (`trigger.c`) | **Não.** Removido e remanescente-no-op produzem o mesmo resultado observável | **Sim — NÃO DEMONSTRADO e não demonstrável por SQL** neste harness |
| O IMMEDIATE posterior à sonda não é contaminado | Nenhum evento pendente; se houvesse um evento da sonda, ele seria no-op (2206 l. 70–74) | Sim, em T3: o segundo IMMEDIATE termina sem erro, o selo continua igual e nenhuma linha de sonda é visível | Idem |
| As fixtures do caso ficam intactas depois da sonda | O rollback de Q volta ao ponto de entrada de Q | Sim: asserções pós-sonda do selo e das contagens | Idem |
| No 2.7, o IMMEDIATE de Pb processa só ev(Pb) | Pela matriz do §2.6.4 | Só indiretamente (no E03): `23505` + `uq_cecp_game_signature` + `v_step`; o E03T não cobre o 2.7 | Idem |

- A garantia de que a sonda não altera o resultado de nenhum caso **não depende** de observar a remoção do evento: pela estrutura, o evento sai com a sonda; e, mesmo que ficasse, seria no-op (§2.6.4).
- Nada nesta tabela é PASS. A cobertura continua **17/135**.

### 2.7 Conclusão N-1 e limitação

- **Fundamentado estaticamente:**
  - sintaxe direta no PL/pgSQL, nomes qualificados e escopo transacional (docs PG 17);
  - efeito retroativo e "falha não muda o modo" (docs);
  - restauração de estado e fila no abort da subtransação (`trigger.c`);
  - isolamento das sondas: cada IMMEDIATE processa exatamente os eventos previstos (§2.6.4–§2.6.5).
- **Não comprovado em runtime:** nenhuma execução deste padrão no harness. Não se afirma comprovação LIVE.
- **Tratamento:**
  - erro de sintaxe ou comportamento divergente vira `H2830_FAIL` (FAIL de harness), nunca PASS (2830 P4, l. 236–238);
  - as sondas autocontidas do §2.6 detectam falha de restauração do modo sem deixar evento para o IMMEDIATE seguinte;
  - para reduzir risco antes do E03 completo, há o teste controlado opcional **E03T** (§2.8), sujeito a DP-7.
- **Nota de contexto:** um commit do PostgreSQL de 2026-08-19 corrigiu o contexto de disparo em subtransação após erro capturado em `AfterTriggerSetState`. A mensagem declara backpatch só até a versão 19, porque a correção envolve campos do fast path de RI em lote. O LIVE é 17.6 (`server_version_num = 170006`, P9A-00). O código-fonte da 17 **não** foi inspecionado nesse ponto; o risco é declarado e as sondas do §2.6 cobrem o sintoma observável.

### 2.8 Teste controlado E03T (implementado localmente em `…-P5-L1-E03-IMPLEMENTATION-01`; não executado)

- **Forma:** um DO, mesma estrutura de sinais do E01.
- **Casos** (todas as sondas no formato do §2.6.2):
  - T1: 2.1 reduzido (selo via IMMEDIATE + sonda);
  - T2: 2.2 reduzido (IMMEDIATE que falha capturado + sonda);
  - T3: reprodução mínima de B-1 — profile selado por IMMEDIATE, `SET … DEFERRED`, sonda Q, depois novo `SET … IMMEDIATE` e `SET … DEFERRED` sem outro evento pendente. O segundo IMMEDIATE deve terminar sem erro, com o selo intacto e nenhuma linha de sonda visível. **Corrigido na v1.2:** isso prova que o IMMEDIATE posterior não é contaminado, mas **não** detecta diretamente a remoção do evento de Q: se ele sobrevivesse, encontraria a linha desfeita e seria no-op (2206 l. 70–74), com o mesmo resultado observável (limite L-1, §2.6.7). Termina com uma segunda sonda.
- **Aceite:** `H283P pass=3/3` e E99 limpo.
- **Função:** isolar N-1 com o mínimo de escrita: provar em runtime que `SET CONSTRAINTS` funciona dentro do DO, que a sonda confirma DEFERRED e que não há contaminação observável. Não conta como caso da 2830.
- **Decisão:** DP-7. A alternativa é aceitar que o próprio E03 carrega as sondas.

## 3. Gate C — isolamento das fixtures

### 3.1 Regras comuns

| # | Regra |
|---|---|
| F-1 | Game `POKEMON` por `code`, preflight exatamente 1 (padrão E01 l. 80–85). Nenhum Game escrito. |
| F-2 | Marcador por execução: `H2830_` + uuid sem hífens em maiúsculas (AD-6), em **`code` e `name`** de todo trait e profile de fixture. Trait `code`: 41 caracteres ≤ 80; profile `code` ≤ 140. |
| F-3 | Trait: família `EVENT`, `display_order = max(display_order da família EVENT no Game) + 1000 + k`, porque `uq_cect_game_family_order` é por família. Profile: `display_order = max(display_order do Game) + 1000 + k`, porque `uq_cecp_game_order` é por Game. `code` com marcador evita `uq_cect_game_code`/`uq_cecp_game_code`. Fixtures do caso usam k ≤ 9. Sonda: `code = v_marker ‖ '_Q' ‖ n` e `display_order = base + 1090` (§2.6.2). |
| F-4 | Todo id de fixture é capturado por `INSERT … RETURNING id INTO v_*`. No início de cada caso, todas as variáveis de fixture, `v_q` e `v_step` voltam a `NULL`. Um id de caso anterior nunca é reutilizado. `v_q` só é lido na asserção pós-sonda e volta a `NULL` logo depois. |
| F-5 | UPDATE só em `card_edition_context_profile`, com `WHERE id = v_p AND code = v_code_p`. Nenhum profile ou trait preexistente é tocado. |
| F-6 | DELETE só em `card_edition_context_profile_trait`, com `WHERE profile_id = v_p AND trait_id = v_t…`, e só com `v_p` de fixture. |
| F-7 | Positivo com UPDATE (2.14): `GET DIAGNOSTICS v_n = ROW_COUNT` e exigir `v_n = 1`. |
| F-8 | Negativos: SQLSTATE exato **e** prefixo exato (P0001) ou `CONSTRAINT_NAME` + `TABLE_NAME` exatos (23505). Qualquer outro erro, ou a ausência de erro, é `H2830_FAIL`. |
| F-9 | Antes da ação negativa, conferir a pré-condição: profile selado (`traits_signature` NOT NULL) ou em montagem (NULL), conforme o caso. Assim um erro vizinho não passa pelo erro esperado. |
| F-10 | Sonda de modo: exatamente uma por IMMEDIATE, sempre no formato do §2.6.2, em nível de caso (nunca dentro de sub-bloco negativo nem de handler). Depois dela, a pré-condição das fixtures do caso é conferida de novo antes de qualquer escrita. |

### 3.2 Matriz caso → IDs → operações → aceite → rollback

| Caso | IDs próprios | Operações (em ordem) | Aceite | Rollback |
|---|---|---|---|---|
Notação: **Q1/Q2** = sonda autocontida do §2.6.2 (linha e evento próprios, desfeitos por `H283S`); **N** = sub-bloco negativo; "IMMEDIATE/DEFERRED" = P4 itens 1 e 3.

| Caso | IDs próprios | Operações (em ordem) | Aceite | Rollback |
|---|---|---|---|---|
| **2.1** | T1, T2, P; q1 (sonda) | INSERT T1, T2; INSERT P; INSERT N:N (P,T2), (P,T1); IMMEDIATE; medir; DEFERRED; Q1 | selo NOT NULL, = ARRAY ordenado, cardinality 2; Q1 conforme e descartada | Q1 (`H283S`) + H283C |
| **2.2** | P; q1 | N {INSERT P; `v_step`; IMMEDIATE; DEFERRED}; handler {captura; DEFERRED}; asserções; Q1 | `P0001` + `EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION:` + `v_step = 'IMMEDIATE'`; P ausente; Q1 conforme | N + Q1 + H283C |
| **2.3** | T1, T2, P; q1 | INSERT T1, T2, P, N:N (P,T1); IMMEDIATE; DEFERRED; Q1; assert selado = {T1}; N {INSERT N:N (P,**T2**)} | `P0001` + `EDITION_CONTEXT_COMPOSITION_IMMUTABLE:`; composição continua {T1} | Q1 + N + H283C |
| **2.4** | T1, T2, P; q1 | INSERT T1, T2, P, N:N (P,T1), (P,T2); IMMEDIATE; DEFERRED; Q1; assert selado; N {DELETE N:N (P,T1)} | `P0001` + `EDITION_CONTEXT_COMPOSITION_IMMUTABLE:`; composição continua {T1,T2} | Q1 + N + H283C |
| **2.5** | Ti (inativo), P | INSERT Ti com `is_active = false`; INSERT P (em montagem); N {INSERT N:N (P,Ti)} | `P0001` + `EDITION_CONTEXT_TRAIT_INACTIVE:` | N + H283C |
| **2.7** | T1, T2, Pa, Pb; q1, q2 | INSERT T1, T2, Pa, N:N (Pa,T1), (Pa,T2); IMMEDIATE; assert Pa selado; DEFERRED; Q1; assert Pa selado; N {INSERT Pb, N:N (Pb,T1), (Pb,T2); `v_step`; IMMEDIATE; DEFERRED}; handler {captura; DEFERRED}; asserções; Q2 (sequência completa no §2.6.4) | `23505`, `CONSTRAINT_NAME = 'uq_cecp_game_signature'`, `TABLE_NAME = 'card_edition_context_profile'`, `v_step = 'IMMEDIATE'`; Pb ausente; Pa selado e igual; Q1 e Q2 conformes | Q1 + N + Q2 + H283C |
| **2.8** | Pa, Pb | INSERT Pa, Pb, sem N:N e **sem** IMMEDIATE | as 2 linhas existem com `traits_signature IS NULL`; zero exceção | H283C descarta linhas **e** eventos pendentes |
| **2.9** | T1, T2, T3, P; q1 | INSERT T1..T3; INSERT P; INSERT N:N em ordem **decrescente** de `trait_id`; IMMEDIATE; DEFERRED; Q1 | selo = array ascendente = `ORDER BY trait_id`; cardinality 3 | Q1 + H283C |
| **2.10** | T1, P; q1 | INSERT T1, P, N:N (P,T1); N {INSERT N:N (P,T1)}; depois IMMEDIATE; DEFERRED; Q1 | `23505`, `pk_cecpt`, `card_edition_context_profile_trait`; depois `cardinality(selo) = COUNT(N:N de P) = 1` | N + Q1 + H283C |
| **2.11** | T1, T2, P | INSERT T1, T2, P, N:N (P,T1); assert em montagem (NULL); N {UPDATE P SET `traits_signature = ARRAY[T2]`} | `P0001` + `EDITION_CONTEXT_SIGNATURE_MISMATCH:` | N + H283C |
| **2.12** | T1, T2, P; q1 | INSERT T1, T2, P, N:N (P,T1); IMMEDIATE; DEFERRED; Q1; assert selado = {T1}; N {UPDATE `traits_signature = ARRAY[T2]`} | `P0001` + `EDITION_CONTEXT_SIGNATURE_IMMUTABLE:` | Q1 + N + H283C |
| **2.13** | T1, P; q1 | como 2.12 até Q1 e o assert; N {UPDATE `traits_signature = NULL`} | `P0001` + `EDITION_CONTEXT_SIGNATURE_IMMUTABLE:` | Q1 + N + H283C |
| **2.14** | T1, P; q1 | como 2.13 até Q1 e o assert; UPDATE `name = 'H2830 fixture 2.14 ' ‖ v_marker` | `ROW_COUNT = 1`; `name` novo; `traits_signature` igual ao selado | Q1 + H283C |

### 3.3 Exame dos casos pedidos

- **2.3.**
  - A 2206 (l. 149–163) deixa passar a reinserção **idêntica** para manter o seed 2231 idempotente. Por isso o caso usa **outro** trait (T2).
  - T2 é ativo, do mesmo Game e não duplica a PK. O único erro possível é o do guard de imutabilidade, que dispara primeiro (§1.5).
- **2.7.**
  - Pa é selado **antes**, fora do sub-bloco. A sonda Q1, entre o selo de Pa e o sub-bloco de Pb, roda e é desfeita na própria subtransação. No IMMEDIATE de Pb a fila contém **exatamente** o evento de Pb, e o desfecho é determinístico (§2.6.4).
  - Mesmo num vazamento hipotético do evento de Q1, o resultado aceito só pode vir do selo de Pb: o evento de sonda encontraria a linha desfeita e seria no-op (2206 l. 70–74; corrigido na v1.2, §2.6.4).
  - `code` e `display_order` distintos afastam `uq_cecp_game_code` e `uq_cecp_game_order`. Os traits de fixture são UUIDs novos, então nenhum profile do LIVE tem a mesma assinatura.
  - A constraint exigida é só `uq_cecp_game_signature`. Numa violação de índice único, `CONSTRAINT_NAME` é o nome do índice; isso é esperado, mas **não** foi observado neste harness. Divergência vira FAIL, nunca PASS.
- **2.10.**
  - Em montagem, `immutable` retorna `NEW` e `trait_active` passa, porque T1 é ativo. O erro vem da PK `pk_cecpt`.
  - O INSERT duplicado roda em sub-bloco. O profile e a primeira linha sobrevivem para o selo.
- **2.11.**
  - Profile em montagem (OLD NULL) e selo informado {T2} ≠ real {T1}: `EDITION_CONTEXT_SIGNATURE_MISMATCH`.
  - Não há IMMEDIATE neste caso. O evento pendente de P é descartado pelo H283C.
- **2.12 e 2.13.** Selo gravado (OLD não nulo) e NEW diferente, inclusive NULL: `EDITION_CONTEXT_SIGNATURE_IMMUTABLE`. Os CHECKs `ck_cecp_signature_not_empty`/`_shape` aceitam os dois valores e não interferem.
- **2.14.** `UPDATE OF traits_signature` não dispara porque só `name` está no `SET`. Não há outro trigger de UPDATE em `card_edition_context_profile` (§1.4).

## 4. Matriz de contrato (resumo auditável)

| Caso | Tipo | Contrato (2830) | Fixture | Ação | Aceite | Rollback |
|---|---|---|---|---|---|---|
| 2.1 | FXd + | selo ordenado após IMMEDIATE | 2 T + 1 P | IMMEDIATE | selo = esperado | H283C |
| 2.2 | FXd − | EMPTY_COMPOSITION | 1 P | IMMEDIATE | P0001 + prefixo | sub-bloco + H283C |
| 2.3 | FXd − | COMPOSITION_IMMUTABLE (INSERT) | 2 T + 1 P | INSERT N:N | P0001 + prefixo | idem |
| 2.4 | FXd − | COMPOSITION_IMMUTABLE (DELETE) | 2 T + 1 P | DELETE N:N | P0001 + prefixo | idem |
| 2.5 | FX − | TRAIT_INACTIVE | 1 T inativo + 1 P | INSERT N:N | P0001 + prefixo | idem |
| 2.7 | FXd − | `uq_cecp_game_signature` | 2 T + 2 P | IMMEDIATE (Pb) | 23505 + índice + tabela | idem |
| 2.8 | FX + | NULL não colide | 2 P | nenhuma | 2 NULL coexistem | H283C |
| 2.9 | FXd + | selo ascendente | 3 T + 1 P | IMMEDIATE | ordem ascendente | H283C |
| 2.10 | FXd −/+ | PK + cardinality | 1 T + 1 P | INSERT duplicado; IMMEDIATE | 23505 `pk_cecpt`; 1 = 1 | sub-bloco + H283C |
| 2.11 | FX − | SIGNATURE_MISMATCH | 2 T + 1 P | UPDATE selo | P0001 + prefixo | idem |
| 2.12 | FXd − | SIGNATURE_IMMUTABLE | 2 T + 1 P | UPDATE selo | P0001 + prefixo | idem |
| 2.13 | FXd − | SIGNATURE_IMMUTABLE (NULL) | 1 T + 1 P | UPDATE selo = NULL | P0001 + prefixo | idem |
| 2.14 | FXd + | UPDATE sem selo permitido | 1 T + 1 P | UPDATE name | ROW_COUNT 1; selo intacto | H283C |

## 5. Gate D — contrato do E03P (1 SELECT; E00 intacto)

| Gate | Condição exata |
|---|---|
| `g_game_pokemon_one` | `count(*) = 1` em `public.game WHERE code = 'POKEMON'` |
| `g_s2_triggers` | exatamente estas linhas não internas em `pg_trigger`: `trg_cecp_seal` (profile; `tgtype = 5`, AFTER INSERT ROW; `tgconstraint <> 0`; `tgdeferrable`; `tginitdeferred`; função `internal.seal_edition_context_composition`); `trg_cecp_signature_write` (profile; `tgtype = 19`, BEFORE UPDATE ROW; `tgattr` = só `traits_signature`; função `…enforce_edition_context_signature_write`); `trg_cecpt_immutable` (profile_trait; `tgtype = 31`, BEFORE INSERT/DELETE/UPDATE ROW; `…guard_edition_context_composition_immutable`); `trg_cecpt_trait_active` (profile_trait; `tgtype = 7`, BEFORE INSERT ROW; `…guard_edition_context_trait_active`); todas com `tgenabled = 'O'` |
| `g_no_other_triggers_l1` | nenhum outro trigger não interno em trait, profile e profile_trait |
| `g_seal_constraint_names_unique` | em `pg_constraint`, exatamente 1 linha `connamespace = public` com `conname = 'trg_cecp_seal'` e 1 com `'trg_cecem_seal'`, ambas `contype = 't'`, `condeferrable` e `condeferred` |
| `g_deferrable_only_seal` | (v1.1) entre as constraints com `conrelid` em trait, profile e profile_trait, a **única** com `condeferrable = true` é `trg_cecp_seal` (em profile). Sustenta a matriz de eventos do §2.5–§2.6.5: nenhum outro evento diferido pode existir no lote L1 |
| `g_s2_constraints` | presentes e válidos: `pk_cecpt` (p), `fk_cecpt_profile` (f), `fk_cecpt_trait` (f), `uq_cecp_game_code`, `uq_cecp_game_order`, `uq_cect_game_code`, `uq_cect_game_family_order`, `ck_cecp_signature_not_empty`, `ck_cecp_signature_shape`, `ck_cect_code_format`, `ck_cecp_code_format`; índice `uq_cecp_game_signature` único, válido, em `(game_id, traits_signature)` e com predicado `traits_signature IS NOT NULL` |
| `g_s2_error_tokens` | o `prosrc` das 4 funções contém exatamente os 5 tokens do §1.2 (redundante com o pino md5; literal ao P11) |
| `g_s2_function_pins` | `md5(replace(prosrc, E'\r\n', E'\n'))` das 4 funções = pinos do §1.3 |
| `g_nn_no_sequence` | nenhuma sequence com default `nextval` ou `OWNED BY` em `card_edition_context_profile_trait` (P6; `touched_now = false` no E00) |
| `g_nn_rls_bypass` | `card_edition_context_profile_trait`: `relforcerowsecurity = false` e dono = `current_user` |
| `g_marker_absent_now` | nenhum trait/profile com `code LIKE '%H2830%'` (confirma o `g_no_residue` do E00 no instante do E03P) |
| `gate_pass` | conjunção de todos; qualquer `false` ou `NULL` ⇒ STOP antes do E03 |

**Saída:** um `jsonb` com cada gate e o detalhe (`d_*`) usado para decidir. É registrado integralmente.

**Perfil estático do E03P:** o mesmo do E00/E99 (`tools/static_check.py`, l. 60–67): 1 statement; sem INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, `SET`, `DO`, `TEMP`, `INTO`, GRANT, REVOKE, COMMENT, COPY, CALL, LOCK, LISTEN ou NOTIFY; parênteses balanceados.

## 6. Gate D — perfil E03 no `tools/static_check.py` (implementado localmente em `…-P5-L1-E03-IMPLEMENTATION-01`)

| # | Regra (falha = FAIL do static_check) |
|---|---|
| E03-1 | 1 `DO $h2830_e03$ … $h2830_e03$;` e nada executável fora dele |
| E03-2 | tokens proibidos: toda a lista do perfil E01 (l. 25–27), **exceto** `UPDATE` e `DELETE`, que passam para E03-3/E03-4. Continuam proibidos `SET LOCAL`, `SET ROLE`, `SET SESSION`, `SET_CONFIG`, `EXECUTE`, `PERFORM`, `TEMP`, `LOCK`, `COMMIT`, `ROLLBACK`, DDL, `COPY`, `CALL`, `NOTIFY`, `RAISE NOTICE/WARNING/INFO` |
| E03-3 | todo UPDATE casa com `^UPDATE public\.card_edition_context_profile SET (traits_signature = (ARRAY\[v_t\w+\]\|NULL)\|name = [^;]+) WHERE id = v_p\w* AND code = v_code_p\w*$` |
| E03-4 | todo DELETE casa com `^DELETE FROM public\.card_edition_context_profile_trait WHERE profile_id = v_p\w* AND trait_id = v_t\w*$` |
| E03-5 | todo statement iniciado por `SET` é exatamente `SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE` ou `… DEFERRED` |
| E03-6 | em cada caso, `#DEFERRED ≥ #IMMEDIATE`, e todo IMMEDIATE tem um DEFERRED depois dele no mesmo caso (caminho normal) ou, se estiver num sub-bloco negativo, um no fim do corpo e outro no handler. Totais do lote: 11 IMMEDIATE e 13 DEFERRED (§2.6.5) |
| E03-7 | alvos de INSERT/UPDATE/DELETE ⊂ {`card_edition_context_trait`, `card_edition_context_profile`, `card_edition_context_profile_trait`}; todo INSERT em trait/profile contém `v_marker` em `code` e `name` |
| E03-8 | negativos: cada `EXCEPTION WHEN OTHERS THEN v_got := true;` seguido de **uma** destas checagens: `v_state <> 'P0001' OR NOT starts_with(v_msg, '<TOKEN>:')`, com TOKEN ∈ os 5 do §1.2; ou `v_state <> '23505' OR v_con IS DISTINCT FROM '<c>' OR v_tab IS DISTINCT FROM '<t>'`, com (c, t) ∈ {(`uq_cecp_game_signature`, `card_edition_context_profile`), (`pk_cecpt`, `card_edition_context_profile_trait`)}; e `IF NOT v_got` presente |
| E03-9 | os tokens usados no E03 são exatamente os 5 do §1.2, e cada um existe literalmente no blob da 2206 (checagem cruzada entre arquivos) |
| E03-10 | proibido `LIKE` sobre `v_msg` |
| E03-11 | casos, na ordem: `2.1, 2.2, 2.3, 2.4, 2.5, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13, 2.14`; `c_expected` igual; **`2.6` ausente** |
| E03-12 | ERRCODEs só `H283C/F/P/S`; `H283P` exatamente 1 e último; estrutura por caso igual à do E01 (1 H283C, handlers H283C/H283F/OTHERS). `H283S` só dentro de bloco de sonda (E03-17), nunca `H283C` dentro de sonda; `WHEN SQLSTATE 'H283S'` só no handler da sonda |
| E03-13 | reset das variáveis de fixture, de `v_q` e de `v_step` a `NULL` no início de cada caso |
| E03-14 | 2.14: `GET DIAGNOSTICS v_n = ROW_COUNT` seguido de `IF v_n <> 1` |
| E03-15 | (v1.1) sondas: por caso, `#sondas = #IMMEDIATE` (11 no lote). Cada sonda aparece em nível de caso, depois do `DEFERRED` do caminho normal ou depois do `END` do sub-bloco negativo e das suas asserções. Proibido: sonda dentro de sub-bloco negativo ou de handler; INSERT, UPDATE, DELETE ou `SET` entre o `DEFERRED` (ou o `END` do negativo) e a sonda |
| E03-16 | BEGIN/END, IF/END IF, parênteses e aspas balanceados |
| E03-17 | (v1.1) forma exata do bloco de sonda (§2.6.2): corpo = 1 INSERT em `card_edition_context_profile` com `RETURNING id INTO v_q`, 1 `SELECT … INTO v_qok`, 1 `IF … H283F` e, como **último** statement, 1 `RAISE … ERRCODE = 'H283S', MESSAGE = v_qtag`; handlers exatamente, nesta ordem: `WHEN SQLSTATE 'H283S'` (compara `MESSAGE_TEXT` com `v_qtag` por `IS DISTINCT FROM` e levanta `H283F` se diferir), `WHEN SQLSTATE 'H283F' THEN RAISE;`, `WHEN OTHERS` convertendo em `H283F`. Sem `SET`, UPDATE, DELETE, INSERT na N:N, `EXIT` ou `RETURN` no bloco; `v_qtag` contém `c_env`, `v_case`, `v_qn` e `v_marker` |
| E03-18 | (v1.1) depois de cada sonda: `SELECT count(*) … WHERE id = v_q`, `IF v_n <> 0` → `H283F`, e `v_q := NULL`; fora do bloco de sonda, dessa asserção e do reset do início do caso, `v_q` não aparece em nenhum statement |
| E03-19 | (v1.1) nos negativos cujo erro nasce no IMMEDIATE (2.2 e 2.7): `v_step := 'IMMEDIATE'` imediatamente antes do `SET … IMMEDIATE` e `v_step IS DISTINCT FROM 'IMMEDIATE'` na checagem de aceite |
| E03-20 | (v1.3, DP-4 = A, só E03) primeira instrução executável do bloco principal = `SET LOCAL lock_timeout = '5s';` seguida **imediatamente** da asserção `IF current_setting('lock_timeout') IS DISTINCT FROM '5s' THEN RAISE … ERRCODE = 'H283F' … caso=PREFLIGHT …; END IF;`, texto e ordem exatos; exatamente 1 `SET LOCAL` e nenhum outro uso de `lock_timeout`. Só este preâmbulo é retirado do E03-2 (`SET LOCAL` continua proibido em qualquer outro lugar) e do E03-5 (todo outro `SET` continua tendo de ser um dos dois `SET CONSTRAINTS`). No E03T (DP-4 = B) a regra exige **ausência** de `SET LOCAL` e de `lock_timeout` |

**Evidências verificáveis pelo auditor sem executar SQL:**
- a saída do `static_check` com as regras E03-1 a E03-20;
- blob e md5 de E03/E03P;
- a lista dos UPDATE/DELETE/`SET CONSTRAINTS` extraída por grep;
- a lista de blocos de sonda extraída por grep (`H283S`), com o caso e a posição de cada um, comparada com o §2.6.5;
- a checagem cruzada dos tokens contra a 2206;
- os pinos md5 do E03P recalculados a partir do blob `2fcd4d74…` (§1.3).

## 7. Gate E — protocolo de execução futura (não executar)

| Passo | Chamada | Identidade exigida | Gate |
|---|---|---|---|
| S0 | verificação local | HEAD = baseline do mandato de execução; árvore limpa; E00 `a4dd8438…` (md5 `45b6c35c…`); E99 `49a71ecb…` (md5 `f0b91183…`); E03 e E03P = blobs auditados no mandato de implementação; `static_check` PASS | STOP se divergir |
| S1 | L1 (canal) | md5 `0836c36a8d3749b1e7718223e064caf9` | `transaction_read_only = off`; `lock_timeout` conforme DP-4 |
| S2 | L3 | md5 `b7bc3700aeef278f6a79bd30e6a8d229` | limpo |
| S3 | E00 verbatim | `a4dd8438…` | `gate_pass = true` |
| S4 | E03P verbatim | blob auditado | `gate_pass = true` |
| S5 | E03 verbatim, uma chamada, imediatamente após S4 | blob auditado | `H283P` com `H2830_ROLLBACK_PASS: envelope=E03_SECAO2_COMPOSICAO_PROFILE pass=13/13 casos=2.1,2.2,2.3,2.4,2.5,2.7,2.8,2.9,2.10,2.11,2.12,2.13,2.14 marker=H2830_… elapsed_ms=N`, com `elapsed_ms ≤ 60000` |
| S6 | E99 com os 3 marcadores do S3 | `49a71ecb…` | `gate_pass = true`, `d_diff = []`, `d_canon_diff = []`, `g_marker_absent = true` |
| S7 | L3 | `b7bc3700…` | nenhum backend/lock residual |

**Prova independente de rollback (tripla):**
1. mensagem terminal com o marcador;
2. E99 com contagens de trait/profile/profile_trait iguais ao `d_baseline` do S3 e marcador ausente em `trait.code`/`profile.code`;
3. L3 limpa.

**STOP e tratamento (sem retry, sem limpeza automática):**

| Evento | Ação |
|---|---|
| gate falso em S0–S4 | não submeter o E03 |
| `H283F` | FAIL do caso; E99 imediato; STOP |
| `H283F` com "sonda" na mensagem | FAIL de harness (P4/N-1: modo não restaurado, sentinela trocada ou sonda não descartada); E99 imediato; STOP; nunca PASS |
| SQLSTATE inesperado, `57014`, `55P03` ou `25006` | FAIL; E99 imediato; STOP |
| retorno `[]` | defeito grave (o DO não pode terminar sem exceção); E99 imediato; STOP |
| mensagem truncada ou `pass ≠ 13/13` | inconclusivo, nunca PASS; E99 imediato; STOP |
| `elapsed_ms > 60000` | não aceito, mesmo com `H283P`; investigar |
| E99 com diferença ou marcador presente | **incidente**: não apagar, não repetir; registrar marcador, linhas e `d_diff`; a limpeza exige mandato explícito com SQL pareado |
| queda de conexão | L3 só leitura, **sem** `pg_terminate_backend`; E99; STOP |

## 8. Decisões pendentes (não decididas aqui)

| # | Decisão | Efeito no lote L1 |
|---|---|---|
| DP-1 | Estender a adaptação AD-2 (tempo medido no LIVE, limite de 120 s, aceite ≤ 60 s) ao lote L1, ou exigir P9b | sem ela, a letra do P9(b) exige medição em ambiente isolado antes do LIVE |
| DP-4 | `SET LOCAL lock_timeout` no E03. A decisão D-3 cobriu só o E01. A opção (a) exige incluir `SET LOCAL` no allowlist E03-5 e uma asserção inicial | define o E03 e o perfil E03 |
| — | **Atualização v1.3:** DP-4 = A decidida para o E03 e implementada (`BATCH12-2830-P5-L1-E03-DECISION-AND-IMPLEMENTATION-01`): preâmbulo P8 no E03 (novo blob) e regra E03-20. DP-1 = A e DP-5 = A também decididas para o E03 (`L1-E03-LIVE-EXECUTION-READINESS.md` v1.1). As linhas acima ficam como registro histórico | — |
| DP-5 | Autorização expressa de escrita transitória com rollback integral: INSERT em trait, profile e profile_trait; UPDATE só em profile de fixture; DELETE só em profile_trait de fixture | sem ela, nada vai ao LIVE |
| DP-7 | Rodar o teste controlado E03T (§2.8) antes do E03, ou aceitar as sondas embutidas no E03. O E03T prova em runtime o padrão N-1 e a ausência de contaminação observável; **não** detecta diretamente a remoção do evento da sonda (corrigido na v1.2, §2.6.7) | ordem da execução futura |
| DP-3 | Para este lote, o próprio mandato fixa o E03P como companheiro do E00, sem alterá-lo. A decisão continua aberta para os lotes seguintes | nenhum no lote L1 |

## 9. Limites desta rodada

- Nenhum SQL, nenhum acesso ao LIVE; nada implementado nas rodadas desta readiness; nenhum arquivo além deste documento, do README e do log. A v1.2 também é só documental: E03, E03P, E03T e `tools/static_check.py` não foram alterados.
- Fatos de PostgreSQL vêm da documentação oficial da versão 17 e de comentários do código-fonte. As evidências do LIVE são históricas (Etapa 3). **Nada** aqui foi observado em runtime para o padrão `SET CONSTRAINTS`.
- Nenhum caso declarado PASS.

**Fontes externas consultadas:**
- [PostgreSQL 17 — SET CONSTRAINTS](https://www.postgresql.org/docs/17/sql-set-constraints.html)
- [PostgreSQL 17 — PL/pgSQL Basic Statements](https://www.postgresql.org/docs/17/plpgsql-statements.html)
- [PostgreSQL 17 — Overview of Trigger Behavior](https://www.postgresql.org/docs/17/trigger-definition.html)
- [PostgreSQL 17 — PL/pgSQL Control Structures, §41.6.8 Trapping Errors](https://www.postgresql.org/docs/17/plpgsql-control-structures.html#PLPGSQL-ERROR-TRAPPING)
- [PostgreSQL 17 — CREATE TRIGGER (constraint triggers)](https://www.postgresql.org/docs/17/sql-createtrigger.html)
- [Comentários de `trigger.c` sobre `AfterTriggersTransData`](https://www.postgresql.org/message-id/attachment/175104/improve_comments_on_trigger_structure.patch)
- [Commit "Restore after-trigger firing context at subtransaction end"](http://www.mail-archive.com/pgsql-committers@lists.postgresql.org/msg48425.html)

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-P5-L1-IMPLEMENTATION-READINESS-01`, baseline `10eef142`), preparação técnica e prova estática, sem SQL e sem LIVE.**<br>• Gate A: 13 casos × 2206, com identidade md5 repositório = E00 = LIVE (Etapa 3) e dependências só dos 4 triggers conhecidos;<br>• Gate B: N-1 fundamentado estaticamente (docs PG 17 + `trigger.c`), não comprovado em runtime; sondas de modo e teste controlado E03T opcional;<br>• N-2: cada nome abreviado corresponde a exatamente um token implementado, comparado por `starts_with` com `:`;<br>• Gate C: matriz caso → IDs → operações → aceite → rollback;<br>• Gate D: E03P (11 gates) e perfil E03 (16 regras);<br>• Gate E: protocolo S0–S7 com STOP;<br>• decisões DP-1, DP-4, DP-5, DP-7 e DP-3.<br>Sem STOP. FREEZE ATIVO. |
| 1.1 | **Correção do blocker B-1 (2026-09-27, `BATCH12-2830-P5-L1-IMPLEMENTATION-READINESS-CORRECTION-01`, baseline `10eef142`), sem SQL e sem LIVE.** A sonda de modo da v1.0 deixava um evento de `trg_cecp_seal` pendente na subtransação do caso, que em 2.7 seria processado pelo IMMEDIATE de Pb (`EMPTY_COMPOSITION` em vez de `23505`).<br>• §2.6 reescrito: sonda autocontida em subtransação própria, encerrada pela sentinela exclusiva `H283S` com mensagem exata; gabarito estrutural; os 7 requisitos do mandato × estrutura; matriz de eventos pendentes do 2.7 (14 etapas) e dos demais casos; limites;<br>• §2.3: atribuição do erro ao IMMEDIATE por `v_step`; sonda proibida dentro de sub-bloco negativo;<br>• §2.5: única constraint `DEFERRABLE` no lote é `trg_cecp_seal`;<br>• §2.8: E03T T3 passa a ser a reprodução mínima de B-1;<br>• §3: regras F-3, F-4 e F-10 e matriz caso → IDs com Q1/Q2;<br>• §5: gate `g_deferrable_only_seal` (12 gates);<br>• §6: E03-6, E03-12, E03-13 e E03-15 revistas; E03-17 a E03-19 novas (19 regras);<br>• §7: tratamento de `H283F` de sonda; §8: DP-7 atualizada.<br>13 casos preservados; 2.6 continua no L5. N-1 continua não comprovado em runtime. Sem STOP. FREEZE ATIVO. |
| 1.2 | **Correção documental do achado D-1 (2026-09-27, `BATCH12-2830-P5-L1-E03-IMPLEMENTATION-CORRECTION-01`, baseline `14675832`), sem SQL e sem LIVE.** A função de selo da 2206 (l. 70–74) retorna sem efeito quando o profile do evento não existe mais; um evento remanescente de sonda seria no-op, não `EMPTY_COMPOSITION`.<br>• §2.6.4 e §3.3: vazamento hipotético corrigido (no-op, nem PASS falso nem FAIL); "Eventos pendentes" declarado como estado esperado, não observado;<br>• §2.6.1: esclarecido que na v1.0 a linha da sonda existia, por isso o B-1 produzia `EMPTY_COMPOSITION`;<br>• §2.6.3 (requisito 3), §2.6.6, §2.8 e §8 (DP-7): o E03T T3 prova ausência de contaminação, não a remoção do evento (limite L-1);<br>• §2.6.7 novo: esperado × observável pelo E03T × não comprovado;<br>• cabeçalho, §0, §2.8, §6 e §9: estado dos artefatos reconciliado.<br>Sem alteração dos 13 casos, dos critérios de PASS/FAIL, do desenho da sonda `H283S`, das matrizes §2.6.4/§2.6.5/§3.2/§4 nem das regras §5/§6. N-1 continua não comprovado em runtime. Sem STOP. FREEZE ATIVO. |
| 1.3 | **Rastreamento da DP-4 = A (2026-09-27, `BATCH12-2830-P5-L1-E03-DECISION-AND-IMPLEMENTATION-01`, baseline `aeeed59a`), sem SQL e sem LIVE.**<br>• §6: nova regra E03-20 (preâmbulo `SET LOCAL lock_timeout = '5s'` + asserção fail-closed como primeira instrução executável do E03; ausência no E03T); E03-2 e E03-5 passam a excluir **só** esse preâmbulo;<br>• §8: nota de que DP-1, DP-4 e DP-5 do E03 foram decididas.<br>13 casos, fixtures, sondas, contratos de erro e matrizes inalterados. FREEZE ATIVO. |
