# R2-F — B1: fundação do registro prospectivo da completude

| Campo | Valor |
|---|---|
| **Rodadas** | `R2-F B1 FOUNDATION IMPLEMENTATION PREPARATION-04` (2026-11-08) · `R2-F B1 SQL CORRECTION-05` (2026-11-08: 5358 v0.2, 5886 v0.2) |
| **Contrato** | D7 v1.63 §4n (`docs/domain-modeling/collections/reports-product-contract.md`), D1–D12, alternativa C mínima |
| **Status** | **APLICADO NO LIVE (2026-11-08) E CANÔNICO** — 5358 → `database/schema/5358_create_collection_completion_history.sql`, 5359 → `database/schema/5359_schedule_collection_completion_capture.sql` (só o bloco Status difere; ver §6). Os arquivos desta pasta são o texto aplicado; 5886 permanece aqui como evidência de validação. N1/N2 pendentes |
| **Arquivos** | `5358_create_collection_completion_history_PROPOSAL.sql` (estruturas, rotina interna, leitura) · `5359_schedule_collection_completion_capture_PROPOSAL.sql` (agendamento) · `5886_validate_collection_completion_history.sql` (P0, A1–A4, N1–N2) · este README |

## 1. O que a fundação faz

- **Fotografias** (`collection_completion_snapshot`): uma por mudança — dia de referência, instante da leitura, execução, modalidade, Card Set, acabamentos (Master Set), situação, `total_positions`, `satisfied_positions`, `progress_percentage` exatamente como a **5188** devolve.
- **Cobertura** (`collection_completion_coverage`): intervalos contínuos de dias comprovados **por coleção**; dia fora de todo intervalo = lacuna.
- **Execuções** (`collection_completion_capture_run`): registro operacional (400 dias); não prova cobertura.
- **Rotina** `internal.capture_collection_completion(p_dry_run)`: por coleção Set padrão/Master Set, numa subtransação — janela conferida antes de cada coleção, idempotência pelo dia coberto, identidade do titular só ali (gravada em `request.jwt.claim.sub` **e** em `request.jwt.claims`, conferida por `auth.uid()` antes da 5188), **5188**, conferência do resultado, cobertura (estende ou abre — retomada após lacuna sempre abre e grava), fotografia só na mudança. Janela até 03h00 de Brasília; trava contra execuções simultâneas; `p_dry_run` percorre tudo sem escrever.
- **Leitura** `get_my_collection_completion_history(p_collection_id)`: só o titular; início, último dia coberto, intervalos e fotografias.
- **Agendamento** (5359): 03h05 UTC = 00h05 de Brasília, todos os dias.

## 2. Segurança e integridade (evidência estática)

| Risco | Salvaguarda | Verificação |
|---|---|---|
| Cliente lê ou grava as tabelas | RLS sem política + `REVOKE ALL` de PUBLIC, anon, authenticated, service_role (precedente 5267) | A1, A3 (`42501`) |
| Cliente executa a rotina | schema `internal` sem USAGE para clientes (2000) + `REVOKE ALL` na função | A1, A3 (`42501`) |
| Identidade incompatível com `auth.uid()` | titular gravado nas duas configurações que `auth.uid()` pode ler; `auth.uid() = titular` conferido antes da 5188 (`R2F_IDENTITY_MISMATCH`) | P0 (definição vigente), A2 |
| Identidade do titular vaza para outra coleção ou para a sessão | `set_config(..., true)` dentro da subtransação de cada coleção; limpa logo após a 5188 e no fim; falha desfaz a subtransação (e a identidade) | A2 (`identity_clear`, sessão limpa) |
| Resultado da 5188 de outra coleção | conferência: uma linha, mesmo `collection_id`, mesma modalidade, números não nulos | estático + A2 (`failed` 0) |
| Leitura enumera coleções | fronteira antes de qualquer tabela; P0002 com a mesma mensagem | A3 |
| Fechamento fora do horário | janela até 03h00 conferida no início **e antes de cada coleção**; fora → `OUTSIDE_WINDOW` (nada gravado) ou parada com as restantes em `late_count` | A4, N1 (`dentro_da_janela`, `fora_da_janela`) |
| Contadores inconsistentes | contados só depois do desfecho da subtransação; `expected = processed + skipped + failed + late` (CHECK na tabela) | N1 (`balanco`) |
| Execução repetida | dia coberto é ignorado; PK (coleção, dia) nas fotografias; trava consultiva | estático + N2 |
| Execução parcial | cobertura e fotografia na mesma subtransação da coleção | N1 (contagens) |
| Lacuna presumida estável | retomada abre intervalo e grava fotografia mesmo sem mudança (`opens_coverage`) | estático; observável quando ocorrer |
| Arquivamento | coleção arquivada continua; situação faz parte da fotografia | estático |
| Impacto nas operações | nenhum gatilho; rotina só lê tabelas de coleção, uma vez por dia | A2 (`ms`) |
| Terceira regra de completude | nenhuma: só chamada à 5188; 5188/5310 intocadas | estático |

## 3. Plano de aplicação e verificação

1. **P0** (somente leitura): nomes livres, `pg_cron`, `internal` sem uso de clientes, assinatura da 5188, `auth.uid()`, fuso, número de coleções-alvo.
2. **5358** em uma migration (transação única do mecanismo de aplicação).
3. **A1** (somente leitura): RLS, ausência de políticas e de privilégios de clientes, rotina sem EXECUTE de clientes, ACL da leitura `authenticated` + `postgres`, nada gravado.
4. **A2** (somente leitura): `capture_collection_completion(true)` — COMPLETED, falhas 0, processadas = coleções-alvo, identidade limpa; custo em ms.
5. **A3** (somente leitura): anon `42501`, sem sub `28000`, nula `22023`, inexistente e de outro titular `P0002` (mesma mensagem), tabela e rotina `42501` para `authenticated`.
6. **A4** (escreve uma linha operacional): chamada diurna → `OUTSIDE_WINDOW`, nenhuma fotografia ou cobertura.
7. **5359**: agendamento.
8. **N1** (manhã seguinte, somente leitura): primeira execução COMPLETED dentro da janela, uma cobertura e uma fotografia inicial por coleção.
9. **N2** (manhã do segundo fechamento): coberturas estendidas, um fechamento por dia, fotografias novas só nas coleções que mudaram.
10. Promoção a `database/schema/` depois de N1/N2.

Reversão (só com autorização): `cron.unschedule('collection-completion-daily-capture')`; depois, `DROP` das duas funções e das três tabelas (sem CASCADE; nada fora delas depende delas).

## 4. Pendências conhecidas

- **[PENDENTE]** Conferir em `cron.job_run_details`, depois da primeira noite, que o comando do job (`set statement_timeout` + `select`) roda como esperado no `pg_cron` do Supabase.
- **[INFERIDO]** Custo: uma chamada da 5188 por coleção-alvo (hoje ~10 coleções); A2 mede.
- Numeração 5358/5359/5886: livres em `database/` e `docs/` na preparação.

## 5. Aplicação no LIVE (2026-11-08, `R2-F B1 — P0 PASS / EXECUÇÃO CONTROLADA`)

Projeto `mimikyu-core` (PostgreSQL 17.6.1.147). Arquivos aplicados sem alteração: 5358 v0.2 (md5 `06ac07b9…`, ledger `20261108160502`) e 5359 v0.1 (md5 `e4310865…`, ledger `20261108160640`). Blocos da 5886 v0.2 (`20af72fe…`) enviados sem alteração.

| Etapa | Resultado |
|---|---|
| P0 | PASS — `auth.uid()` = `coalesce(request.jwt.claim.sub, request.jwt.claims->>'sub')`; 8 coleções-alvo |
| 5358 | aplicada (transação única do `apply_migration`) |
| A1 | PASS — RLS sem política nas 3 tabelas, sem privilégio de anon/authenticated/service_role, rotina sem EXECUTE de clientes nem de PUBLIC, leitura DEFINER/STABLE/`search_path` vazio com ACL `postgres:EXECUTE, authenticated:EXECUTE`, nada gravado |
| A2 | PASS — ensaio: COMPLETED, 8/8 processadas, 0 falhas/puladas/fora da janela, 0 gravadas, identidade limpa, 277 ms |
| A3 | PASS — anon `42501`; sem identidade `28000`; nula `22023`; inexistente e de outro titular `P0002` com a mesma mensagem; tabelas e rotina `42501`; titular lê a própria coleção |
| A4 | PASS — `OUTSIDE_WINDOW` às 13h06 de Brasília; nenhuma fotografia nem cobertura (única escrita: a linha da execução) |
| 5359 | aplicada — job `collection-completion-daily-capture`, `5 3 * * *` (UTC), ativo, usuário `postgres`, um único job com o nome |

Pendentes: N1 na manhã de 2026-11-09 (primeiro fechamento, dia de referência 2026-11-08), conferência de `cron.job_run_details` e N2 no dia seguinte.

## 6. Promoção canônica (2026-11-08, `R2-F FINAL CLOSEOUT & PUBLICATION-01`)

Conferência somente leitura no LIVE antes da promoção: `md5(prosrc)` de `internal.capture_collection_completion` (`827139f6…`) e de `public.get_my_collection_completion_history` (`1cfb2bff…`) iguais aos corpos destes arquivos; `SECURITY DEFINER` e `search_path=""` nas duas; ACL `postgres` (rotina) e `postgres, authenticated` (leitura); comando do job `collection-completion-daily-capture` com md5 `6b82e8d0…`, igual ao da 5359, ativo, `5 3 * * *`, usuário `postgres`. Na mesma consulta (13h39 de Brasília de 2026-11-08): só a execução diurna do A4 (`OUTSIDE_WINDOW`), nenhuma fotografia nem cobertura, nenhuma execução do `pg_cron` ainda — **N1 não ocorreu**. A promoção não depende de N1/N2: preserva o texto já executado; N1/N2 seguem como acompanhamento operacional da rotina noturna.
