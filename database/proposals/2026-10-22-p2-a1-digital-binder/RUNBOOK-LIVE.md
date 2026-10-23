# RUNBOOK LIVE — Fichário Digital (P2-A1)

| Campo | Valor |
|---|---|
| Versão | 1.0 (2026-10-23, `P2-A1-LIVE-READINESS-01`) |
| Status | **PREPARADO — NADA EXECUTADO.** |
| Governança | O projeto **não usa ambiente isolado, staging ou banco de testes**. A validação acontece no LIVE, só com o que é seguro lá. |
| Quem executa | Fabrício, ou o agente com autorização expressa **por etapa** |

## 1. Classes de execução

| Classe | O quê | Arquivo | Autorização |
|---|---|---|---|
| **R1** | Leitura de catálogo e contagens, em `begin transaction read only` | `LIVE_00_precheck_readonly.sql`, `LIVE_90_postcheck_readonly.sql` | uma para o R1 pré, outra para o R1 pós |
| **W1** | DDL autorizado: os seis contratos | `5225` → `5223` → `5224` → `5226` → `5227` → `5228` | **expressa, separada**; aprovar R1 não aprova W1 |
| **R2** | Sondas de RPC em `begin transaction read only` (§8) | só neste runbook | opcional, separada |
| **PROIBIDO no LIVE** | `5850` em qualquer modo; Seção P; K1–K6; fixtures sintéticas; injeção de falha; carga | — | não se aplica |

**Por que o `5850(false)` também fica fora:** o wrapper cria função em `pg_temp` e, da Seção F em diante, insere em `auth.users`, `expansion`, `card_set`, `card`, `card_variant`, `game`, `card_variant_type`, `physical_card`, `collection`, `collection_allocation`, `collection_layout`… e, na Seção 11, cria função e trigger em `public`. O rollback final não muda a classe: escreve no LIVE, dispara triggers e toma travas em tabelas de produção. Só as checagens estruturais 0.1–0.10 são leitura; elas foram extraídas como SELECT puro no `POST-1` do `LIVE_90`.

## 2. Pré-requisitos

1. `HEAD` = `54323de` + pasta da proposta e docs não commitados; hashes SHA-256 dos seis SQL iguais aos do relatório da rodada.
2. `python static_check_p2_a1.py` → `75/75 PASS`.
3. Janela sem uso do app; ninguém editando catálogo (classe C da concorrência).
4. Ferramenta: Supabase MCP no projeto canônico (`execute_sql` para R1/R2, `apply_migration` para W1), ou SQL Editor com o mesmo texto.

## 3. Ordem

| # | Etapa | Classe | Comando |
|---|---|---|---|
| 0 | Pré-checagens `PRE-1`…`PRE-7` | R1 | `LIVE_00`, bloco a bloco, em `begin transaction read only; … rollback;` |
| — | **GATE DE AUTORIZAÇÃO** (§4) | — | — |
| 1 | `5225` reserva por acabamento | W1 | `apply_migration` com o conteúdo integral do arquivo; nome `p2a1_5225_extend_slot_expected_content_variant_type` |
| 2 | `5223` leitura | W1 | idem; `p2a1_5223_create_get_my_collection_binder_functions` |
| 3 | `5224` prévia e montagem | W1 | idem; `p2a1_5224_create_collection_binder_plan_preview_create` |
| 4 | `5226` desmontagem + `delete_collection` v1.4 | W1 | idem; `p2a1_5226_create_collection_binder_dismantle_and_update_delete_collection` |
| 5 | `5227` fecha `create_collection_layout` | W1 | idem; `p2a1_5227_restrict_create_collection_layout_to_binder_assembly` |
| 6 | `5228` grade nos sete modelos | W1 | idem; `p2a1_5228_restrict_set_collection_layout_grid_to_seven_models` |
| 7 | Pós-checagens `POST-1`…`POST-4` | R1 | `LIVE_90` + `get_advisors(security)` |
| 8 | Fechamento documental | — | promoção para `database/schema/`, 05d, ROADMAP, HANDOFF, log |
| 9 | P2-B (visual) | — | só com autorização de avanço |

Cada arquivo é uma transação (`begin; … commit;`) com pré-checagem fail-loud no início e, na 5227/5228, pós-checagem da matriz efetiva antes do `commit`. Um erro em qualquer ponto desfaz **aquele arquivo inteiro**. Entre arquivos: ler a resposta, conferir o ledger e só então seguir.

## 4. Gate de autorização (antes do primeiro SQL de escrita)

Só avança para W1 com **todos** estes itens registrados:

- `PRE-2`, `PRE-3` e `PRE-4`: todas as linhas `ok = true`.
- `PRE-5`: `anon_exec = false`, `public_grant = false`, `acl_is_default = false` nas quatro funções-base; `anon`/`authenticated` sem `rolsuper`/`rolbypassrls`.
- `PRE-6` registrado como baseline. Se `layouts > 0`, Fabrício decide antes (ver §5).
- `PRE-7`: nenhuma transação aberta há mais de 1 min e nenhuma trava concedida a outra sessão nas tabelas listadas.
- Mensagem expressa de Fabrício autorizando a etapa W1.

## 5. Critérios PASS / STOP

| Ponto | PASS | STOP |
|---|---|---|
| `PRE-2`/`PRE-3`/`PRE-4` | todas `ok` | qualquer `false`: o LIVE difere do que as propostas pressupõem. Auditar, sem tentar ajustar no LIVE |
| `PRE-3` md5 | igual ao esperado | diferente com marcadores `ok`: **não** é STOP; registrar e seguir (diferença de espaço) |
| `PRE-5` | conforme §4 | `anon` executa, ou ACL nula (PUBLIC implícito) |
| `PRE-6` `layouts` | `0` | `> 0`: **decisão, não falha**. Um layout já existente faz a 5224 responder `LAYOUT_ALREADY_EXISTS` para aquela coleção; a 5228 recusa grade fora dos sete modelos para ele. Nada é alterado pelo pacote |
| `PRE-7` | sem bloqueio | transação longa ou trava nas tabelas-alvo: esperar; a 5225 faz `ALTER TABLE` e entraria na fila |
| Cada W1 | resposta sem erro e entrada nova no ledger | qualquer erro: parar (§6) |
| `POST-1` | 10/10 `ok` | qualquer `false` |
| `POST-2` | contagens idênticas ao `PRE-6`; `expected_with_type = 0` | qualquer diferença |
| `POST-3` | seis entradas, na ordem | faltando, duplicada ou fora de ordem |
| `POST-4` | só a variação esperada do lint 0029 | achado novo de outra classe |

## 6. Conduta em erro

1. **Parar.** Não reaplicar, não editar o arquivo, não "consertar" no LIVE. Guardar a mensagem integral (SQLSTATE e texto).
2. Rodar `POST-1`/`POST-2`/`POST-3` (R1) para fotografar o estado: os arquivos anteriores ficaram aplicados; o que falhou não deixou nada.
3. Reportar a Fabrício. Correção só como nova proposta, com nova autorização.

O estado depois de qualquer prefixo da ordem é coerente: cada arquivo só **acrescenta** função, coluna ou regra, ou restringe privilégio. A ordem não abre caminho novo a quem não o tinha (a 5123 já é executável hoje; a 5227 só fecha).

**Reversão por contrato** (cada uma só com autorização, em ordem inversa, como nova proposta):

| Contrato | Reversão | Segura enquanto |
|---|---|---|
| 5228 | reaplicar `database/schema/5137` v1.1 | sempre (só regra; nenhum dado) |
| 5227 | `grant execute on function public.create_collection_layout(uuid, integer, integer) to authenticated;` | sempre |
| 5226 | `drop` das 3 funções novas; reaplicar `database/schema/5039` v1.3 | sempre (sem dado próprio) |
| 5224 | `drop` das 3 funções | antes do primeiro fichário criado; depois, a reversão não apaga fichários, só remove o caminho de criação |
| 5223 | `drop` das 2 funções | sempre (leitura) |
| 5225 | `drop` da função de 4 args, trigger e função de trigger; `alter table … drop column expected_variant_type_id`; reaplicar `database/schema/5128` | **só com `expected_with_type = 0`** e com 5223/5224/5226 já revertidas (elas leem a coluna) |

**Sem reversão segura** quando já houver fichários com reserva por acabamento (`expected_with_type > 0`): desfazer a 5225 apagaria a informação. Nesse caso, só correção para frente.

## 7. Evidência mínima a registrar

- Saída integral de `PRE-1`…`PRE-7` e `POST-1`…`POST-4`, com data e hora UTC.
- Para cada W1: nome e versão do ledger, resposta (`success` ou erro integral) e SHA-256 do arquivo aplicado.
- Comparação `PRE-6` × `POST-2`, campo a campo.
- Lint 0029 antes × depois.
- Autorizações de Fabrício (R1 pré, W1, R1 pós, R2 se houver), citadas literalmente.

Destino: seção "Execução no LIVE" do `README.md` desta pasta, linha em `docs/log.md` e revisão do 05d, no mesmo ciclo.

## 8. R2 — sondas sem gravação (opcional, autorização própria)

Provam comportamento sem escrita: a transação é `read only`, então o Postgres recusa qualquer gravação (25006) mesmo dentro de SECURITY DEFINER. Usam o usuário e **uma coleção reais de Fabrício** (`<UID>`, `<C>`), só para leitura. Uma sonda por transação:

```sql
begin transaction read only;
select set_config('request.jwt.claims', json_build_object('sub','<UID>','role','authenticated')::text, true);
set local role authenticated;
select * from public.create_collection_layout('<C>'::uuid, 3, 3);   -- S1: esperado 42501 (5227)
rollback;
```

| Sonda | Chamada (depois do `set local role authenticated`) | Esperado |
|---|---|---|
| S1 | `create_collection_layout('<C>', 3, 3)` | 42501, permissão negada |
| S2 | `get_my_collection_binder('<C>')` | 1 linha, coerente com a coleção |
| S3 | `preview_my_collection_binder('<C>', 3, 3, 'PRINCIPAL_ONLY')` | prévia com `plan_token`, ou 55000 `NOT_ELIGIBLE` se o local padrão não for `BINDER` |
| S4 | `get_my_collection_binder(gen_random_uuid())` | P0002 `COLLECTION_NOT_FOUND` |
| S5 | igual a S2, mas com `set local role anon` | 42501 |

**Não podem ser sondadas sem gravar:** `create_my_collection_binder`, `dismantle_my_collection_binder`, `set_collection_layout_grid` (a 5122 toma `FOR UPDATE`, recusado em `read only` antes da regra dos sete modelos), `set_slot_expected_content`, `delete_collection` v1.4 e toda concorrência (K1–K6).

## 9. O que continua sem prova comportamental

- Montagem, desmontagem e as recusas que dependem de gravação (D2 na grade, `PLAN_CHANGED`, `DISMANTLE_PLAN_CHANGED`, `BINDER_EXISTS`, `EXPECTED_VARIANT_TYPE_GAME_MISMATCH`).
- Concorrência entre sessões (K1–K6) e `lock_timeout`.
- Teto de volume (10 000 alocações / 20 000 bolsos): **provisório**; nenhuma carga no LIVE.
- Desempenho real da prévia e da criação.

Nada disso é declarado provado pela inspeção estática nem pelas pós-checagens estruturais. A primeira evidência comportamental real será o uso pelo próprio Fabrício na P2-B. Cada montagem real grava dados dele, então é classe W, com autorização própria.
