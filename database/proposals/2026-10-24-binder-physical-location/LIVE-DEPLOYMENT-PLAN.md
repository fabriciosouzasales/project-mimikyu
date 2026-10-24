# BINDER-PHYSICAL-LOCATION — plano de implantação controlada no LIVE

| | |
|---|---|
| Rodada | BINDER-PHYSICAL-LOCATION-LIVE-READINESS-01 |
| Status | **Passos 0–8 CONCLUÍDOS (2026-10-24).** Precheck PASS; Fase A + LIVE_50 (1ª) PASS (`LIVE-PHASE-A-2026-10-24.md`); frontend `0389498` publicado e homologado; LIVE_50 (2ª) q01–q08 PASS (q09 = baseline histórico); Fase B 5256 CONFIRMADO EXECUTADO e LIVE_90 7/7 PASS (`LIVE-PHASE-B-2026-10-24.md`). Promoção canônica concluída em `BINDER-PHYSICAL-LOCATION-FINAL-CLOSEOUT-01` (README §Encerramento). **PLANO ENCERRADO.** Commit/push pelo proprietário. |
| Decisão de direção | Validação em ambiente isolado **descartada** pelo proprietário. O pacote `pg17-validation/` permanece **NÃO EXECUTADO** e **não é requisito** desta implantação. |
| Projeto | Supabase `mimikyu-core` (`qjfutqujxrbzgrtkpgkg`) |
| Executor | Fabrício (ou o agente, com autorização explícita e separada de cada etapa) |

## 1. Estado dos contratos

| Fase | Migration | Contrato | Natureza |
|---|---|---|---|
| A | 5247 | `collection_layout.storage_container_id` (NOT NULL, UNIQUE, FK RESTRICT, imutável) + gatilhos de local | ADD COLUMN + backfill (sem tocar `updated_at`) |
| A | 5248 | posição pelo exemplar (`physical_card_id` NOT NULL UNIQUE, CASCADE); alocação vira legado (NULL, SET NULL); gatilho de integridade por local | ADD COLUMN + backfill + troca de FK + `create or replace` de 2 funções de gatilho |
| A | 5249 | escritores com confirmação (sobrecargas sem DEFAULT de 5024/5222) + prévias de impacto | funções novas |
| A | 5250 | `place_my_physical_card_in_slot` | função nova |
| A | 5251 | plano do fichário v2 (só exemplares guardados no fichário) | `create or replace` |
| A | 5252 | leituras: cabeçalho/páginas com colunas novas no fim; `get_my_collection_binder_unplaced(uuid,int,int,text,uuid)` nova, convivendo com a de 3 args | drop/create das leituras + função nova |
| A | 5253 | desassociar mantém posições | `create or replace` |
| A | 5254 | transferência da âncora antes de excluir a proprietária | função nova + `create or replace` do gatilho 5136 |
| A | 5255 | associação/candidatos pelo local do fichário | `create or replace` |
| B | 5256 | gatilho de proteção em `physical_card` (sem bypass) + DROP da leitura de 3 args | contração |

Revisão desta rodada:

- **Prechecks e postchecks somente leitura:** `LIVE_00`, `LIVE_01` (novo), `LIVE_50`, `LIVE_90` e `R0` contêm apenas SELECT em catálogo e tabelas. Nenhum INSERT/UPDATE/DELETE/DDL/GRANT/`set_config`/lock. Os prechecks *internos* de cada migration são `DO` de verificação que abortam a própria transação; eles fazem parte da migration, não do precheck.
- **Atomicidade:** todas as migrations são `begin … commit` próprias; falha = nada aplicado. 5247/5248/5249/5255/5256 fixam `lock_timeout 5s`; 5251–5254 só substituem funções (sem lock longo de tabela) e herdam o timeout da sessão.
- **Funções do frontend não tocadas pela proposta** (`move_slot_assignment`, `remove_slot_assignment`, `set_slot_lock`, inserção/fechamento de vão, remoção de página, imagens) não dependem de `collection_allocation`: movem/removem a linha da posição por `slot_id` e continuam corretas com posições sem alocação.
- **Achado menor (não bloqueante):** o token de desmontagem (`collection_binder_dismantle_snapshot`, 5226) serializa `slot:alocação`. Uma posição sem alocação sai da serialização (concatenação com NULL), então o token fica menos sensível a mudanças nessas posições. A desmontagem continua removendo todas as posições do fichário (ação explícita existente); só a detecção de "plano mudou" fica mais fraca para esse caso.

## 2. Sequência de implantação

| Passo | Ação | Escreve? | Autorização |
|---|---|---|---|
| 0 | **Precheck LIVE**: `LIVE_00` + `LIVE_01` (somente leitura, §6) | não | separada (esta é a única etapa pedida a seguir) |
| 1 | Janela combinada; nenhuma sessão de usuário ativa no Fichário (p11 do LIVE_00 repetido imediatamente antes) | não | — |
| 2 | **Fase A**: 5247 → 5248 → 5249 → 5250 → 5251 → 5252 → 5253 → 5254 → 5255, uma por vez, via `apply_migration` com o nome = nome do arquivo sem `.sql` (o LIVE_50 conta o ledger por esse nome) | sim | separada |
| 3 | **LIVE_50 (1ª)** | não | — |
| 4 | **Deploy do frontend novo** (`web/` local atual), após `next lint`/`next build` na máquina de Fabrício | — | separada |
| 5 | Homologação mínima pela interface (§3, saída do passo 4) | uso normal | — |
| 6 | **LIVE_50 (2ª)** — q05 garante que o frontend antigo não deixou posição fora do local na janela | não | — |
| 7 | **Fase B**: 5256 | sim | separada |
| 8 | **LIVE_90** + homologação final | não | — |

Promoção para `database/schema/` e documentação canônica só depois do passo 8 confirmado.

## 3. Critérios de entrada e saída (STOP objetivo)

| Fase | Entrada | Saída (todas verdadeiras) | STOP imediato se |
|---|---|---|---|
| Precheck | autorização; repositório no estado revisado | LIVE_00 p01–p11 = true; LIVE_01 `l01_all_canonical = true` (15/15); fatos anotados: layouts, guests, posições, reservas, `assignments_md5`, `layout_md5`, `allocations_md5`, exemplares em F001 | qualquer coluna false; contagens divergentes do esperado sem explicação (2 layouts — F001 "Celebração de 30 Anos" com 155 posições/158 reservas e F002 "Minha Pokédex" vazio, confirmado por Fabrício —, 25 páginas, 232 bolsos, 0 travados em 2026-10-24) |
| Fase A | precheck PASS no mesmo dia; p11 repetido = true | 9 migrations aplicadas; LIVE_50 q01–q09 = true; `assignments_md5`/`layout_md5`/`allocations_md5` = LIVE_00 | erro em qualquer migration (a própria transação desfaz — não reaplicar nem "corrigir" na hora); qualquer q false; md5 divergente |
| Deploy | fase A PASS; build/lint locais OK | interface: "Cartas disponíveis" lista os 27 (incl. Mudkip MEP 057) com filtros; posicionar + Desfazer funcionam; contracapa e Centro de Controle inalterados | erro de RPC no navegador; tela antiga/nova inconsistente → N1 (voltar o frontend) |
| Fase B | LIVE_50 (2ª) PASS, sobretudo q05 | 5256 aplicada; LIVE_90 q01–q07 = true; contagens = LIVE_50 | precheck da 5256 aborta (posição fora do local) → não forçar; R0 e decisão |
| Encerramento | LIVE_90 PASS | homologação final; promoção canônica; docs | — |

## 4. Recuperação aplicável (sem pressupor teste prévio isolado)

| Situação | Nível | Ação | Efeito em dados |
|---|---|---|---|
| Falha *durante* uma migration | — | nenhuma: a transação desfaz | nenhum |
| Problema após a fase A, antes do deploy | N2 | R2A (contratos); R2B só se R0 d03 = 0 e d04 = 0 | R2A não lê nem altera linhas; R2B preserva todas as posições |
| Problema após o deploy | N1 | voltar o frontend; se a fase B existir, R1 | nenhum |
| Problema de contrato após a fase B | N2 | R1 → R2A | nenhum |
| Precisa voltar o modelo e R0 mostra d03/d04 > 0 | correção posterior | migration nova, para frente; R2B é **inadmissível** e se recusa sozinho (P2/P3) | o modelo novo permanece |

Antes de qualquer R*: rodar **R0** (somente leitura) e registrar o resultado. Como não houve execução prévia, os scripts de recuperação também nunca rodaram: sua fidelidade se apoia em (a) corpos restaurados idênticos às canônicas (static check 44/44) e (b) **LIVE_01** provando que o LIVE executa essas mesmas canônicas.

## 5. Riscos residuais

| # | Risco | Mitigação disponível | Classe |
|---|---|---|---|
| 1 | Nenhuma das 10 migrations, nem R0/R1/R2A/R2B, rodou em PostgreSQL real: erros de sintaxe/execução só aparecerão no LIVE | transação por migration (falha = nada aplicado); ordem 1 por vez; STOP sem correção improvisada | **aceito por decisão do proprietário** — não é bloqueador técnico |
| 2 | Harness 5854 (53 casos) nunca executado; comportamento funcional sem prova automática | LIVE_50/90 + homologação pela interface; o harness é proibido no LIVE | aceito |
| 3 | Recuperação nunca exercitada | R0 diagnóstico; R2B recusa sozinho quando inadmissível; LIVE_01 confirma corpos canônicos | aceito |
| 4 | Concorrência verificada só por revisão da ordem de travas | janela sem uso ativo; 5256 só depois do deploy | baixo |
| 5 | Divergência LIVE × canônicas tornaria R1/R2A/R2B infiéis | **LIVE_01** (novo) — STOP se qualquer corpo divergir | coberto pelo precheck |
| 6 | 5251–5254 sem `lock_timeout` próprio | aplicar com o Fichário sem uso; se travar, cancelar a sessão (a transação desfaz) | baixo |
| 7 | Token de desmontagem pouco sensível a posições sem alocação | ação explícita; remove tudo de qualquer forma | baixo, registrado |
| 8 | Lint/build do frontend não rodaram no sandbox | rodar na máquina de Fabrício antes do deploy | pendência operacional |

Bloqueadores reais para **executar os prechecks**: nenhum.

## 6. Procedimento de precheck LIVE (para execução posterior, separadamente autorizada)

Somente leitura. Ordem:

1. `LIVE_00_precheck_readonly.sql` — estado anterior à fase A (11 checagens + fatos/md5 de referência).
2. `LIVE_01_precheck_canonical_fingerprint_readonly.sql` — 15 funções do LIVE com corpo idêntico às canônicas.

Execução recomendada (SQL Editor do Supabase ou MCP `execute_sql`), cada arquivo inteiro dentro de uma transação somente leitura:

```sql
begin transaction read only;
set local statement_timeout = '30s';
-- colar aqui o conteúdo de LIVE_00_precheck_readonly.sql
rollback;

begin transaction read only;
set local statement_timeout = '30s';
-- colar aqui o conteúdo de LIVE_01_precheck_canonical_fingerprint_readonly.sql
rollback;
```

Registrar: data/hora, saída completa das duas consultas de cada arquivo e o veredito (PASS = todas as colunas booleanas `true`, `l01_functions_checked = 15`). Qualquer `false`: STOP e reportar, sem executar nada além.
