# Bulk B1 — recusa explícita de Card Variant inativa (`5152`)

| Campo | Valor |
|---|---|
| **Rodada** | `COLLECTION-BULK-ACTIVE-VARIANT-HARDENING-01` (2026-10-16) |
| **Status** | **EXECUTED / VALIDATED / PROMOTED (LIVE, 2026-10-16).** `5152` aplicada no LIVE (`mimikyu-core`, ledger `20261016234129`) por autorização expressa de Fabrício e promovida para `database/schema/`. Pós-verificação LIVE (§7.6): `5824` 30/29/0/1, `5822` 64/64/0/0, `5823` v2.2 60/60/0/0, resíduo zero, Security Advisor sem alerta novo. Antes, validada offline em PostgreSQL 17 isolado (manifesto `OFFLINE-MANIFEST-01`, fixture `5825`; evidência em `C:\mmkyu-bulk-offline\out`, fora do repositório). `K01` = **NOT PROVEN / ACCEPTED RISK** (§5). |
| **Baseline** | **HEAD histórico da proposta** (base sobre a qual `5152`, `5824` e `5825` foram redigidos): `2e3747062eedb89756647cd0a17521a25421a5cf`. **HEAD efetivo do repositório** em 2026-10-16 (`BULK04-READINESS-01-CORRECTION-01`): o mesmo `2e37470`, com alterações locais não commitadas (`database/schema/5034`, documentação e esta pasta, ainda não versionada). O HEAD efetivo no momento da implantação deve ser reconfirmado (§7.1). |
| **Diagnóstico de origem** | `COLLECTION-BULK-ACTIVE-VARIANT-CHECK-01` — `CONFIRMED-GAP` |
| **Aprovação** | Mudança do fingerprint (`5149`) aprovada por Fabrício e aplicada em 2026-10-16. |
| **Arquivos** | `5152_harden_bulk_b1_inactive_card_variant.sql` (migration; cópia canônica idêntica em `database/schema/`) · `5824_validate_bulk_b1_inactive_card_variant.sql` (harness) · `5825_fixture_offline_synthetic_catalog.sql` e `OFFLINE-MANIFEST-01.txt` (só validação offline; nunca no LIVE) · este README |

## 1. Problema

| Etapa | Antes de `5152` |
|---|---|
| Preview (`5151`) | Só verificava existência da variante. Variante inativa saía com `ok = true` e fingerprint. |
| Fingerprint (`5149`) | Não incluía `is_active`. Desativar a variante depois do preview não tornava o preview desatualizado. |
| Confirmação (`5150`) | Sem checagem própria. Barrada apenas pelo trigger `trg_guard_card_variant_active` (`2268`) no `INSERT` — `MV001`, um único id, no meio da escrita, fora do formato de erro do contrato B1. |

## 2. Correção

Uma migration, três `CREATE OR REPLACE FUNCTION`. Os corpos são cópias de `database/schema/5149`, `5150` e `5151`, alteradas **só** nos trechos marcados "5152". O diff função a função tem 4 linhas removidas: 1 linha do catálogo do fingerprint e as 3 strings de `COMMENT`.

| Função | Mudança |
|---|---|
| `5149` | Cada item do catálogo resolvido ganha `'is_active', cv.is_active`. |
| `5150` | Passo **6.2b**, antes de qualquer escrita: `RAISE 'CARD_VARIANT_INACTIVE: <n> card_variant_id inativa(s), sem novos vinculos: <10 primeiros>'`, `22023`, `DETAIL` com a lista completa. |
| `5151` | Passo **3.5b**: issue `CARD_VARIANT_INACTIVE`, `BLOCKING`, `offenders` com a lista completa. Com ele, `ok = false` e nenhum fingerprint. |

**Preservado:**
- assinaturas, envelope, teto 1000, `SECURITY DEFINER`/`INVOKER`, volatilidade, `search_path` e ACL (os `REVOKE`/`GRANT` são reafirmados iguais);
- `request_hash` (`5147`);
- trigger `2268`.

**Sem lock novo em `5150`.** A ordem de locks continua exclusivamente em `5148` (I9; `5822` `L02`). A corrida entre a validação 6.2b e o `INSERT` continua coberta pelo trigger `2268`, que lê com `FOR SHARE` e derruba a transação inteira, claim incluído.

## 3. Idempotência e compatibilidade

- **Replay (D9):** `5150` devolve `REPLAY` no passo 3 (claim), antes do fingerprint e da validação. Uma operação concluída continua sendo `REPLAY` mesmo que a variante seja desativada depois (`5824` `I02`).
- **Fingerprints anteriores à aplicação ficam inválidos:** o material hasheado ganha a chave `is_active`. A confirmação recebe `PREVIEW_STALE` e basta refazer o preview. Nenhum consumidor dessas RPCs foi encontrado em `web/` nem em `supabase/functions` (busca de 2026-10-16).
- **`bulk_operation.preview_fingerprint` já gravado:** não é revalidado por nada; nenhum dado persistido muda.

## 4. Validação proposta — ordem de execução (após autorização)

1. Aplicar `5152`.
2. Executar `5824`. Gate: `TOTAL 30 / PASS 29 / FAIL 0 / NOT PROVEN 1` (`K01`).
3. Reexecutar `5822` (B1) e `5823` (Preview), que precisam continuar `64/64` e `60/60`.
4. Postcheck externo de resíduo (após o `ROLLBACK` forçado de `5824`):

```sql
select (select count(*) from public.card_variant where not is_active) as inativas,  -- igual ao baseline
       (select count(*) from public.physical_card)                    as physical_cards,
       (select count(*) from public.bulk_operation)                   as bulk_operations;
```

## 5. `K01` — roteiro de concorrência (duas sessões persistentes)

O mesmo método dos casos `K01`–`K03` de `5821`, com duas sessões `psql` e uma role temporária:

1. **A:** `BEGIN;` e definir `request.jwt.claims` de u1. Chamar `register_physical_cards_bulk` com uma variante ativa `X`.
2. **B:** desativar `X` e `COMMIT` depois da validação 6.2b de A e antes do `INSERT` dela.
3. **A:** no `INSERT`, o resultado esperado é `MV001 CARD_VARIANT_INACTIVE` vindo do trigger, `ROLLBACK` total e contagem da chave igual a 0.

**Situação: NOT PROVEN / ACCEPTED RISK** (decisão de Fabrício, 2026-10-16). Fundamento: o caso prova o trigger `2268` (já no LIVE e validado na sua própria rodada), não o `5152`; no pior caso a corrida produz o `MV001` do trigger em vez do `22023` do passo 6.2b, sempre com a transação inteira desfeita — sem gravação parcial nem perda de dados. Um roteiro executável sem versão instrumentada (B segura a desativação; A bloqueia no `FOR SHARE` do trigger) foi preparado na rodada `BULK-03 — K01 CONCURRENCY VALIDATION`, mas não é requisito de implantação.

## 6. Reversão

Reaplicar como `CREATE OR REPLACE` os corpos de `database/schema/5149`, `5150` e `5151`. Nenhum dado é alterado pela migration.

## 7. Implantação LIVE — EXECUTADA (2026-10-16)

Pacote preparado em `BULK04-READINESS-01` e executado em 2026-10-16 com autorização expressa de Fabrício (só `5152`). Resultado em §7.6. Os itens 7.1–7.4 ficam como registro do pacote aprovado.

### 7.1 Integridade do artefato

| Item | Valor |
|---|---|
| Arquivo | `5152_harden_bulk_b1_inactive_card_variant.sql` (1243 linhas, transação própria: `BEGIN;` linha 56, `COMMIT;` linha 1243) |
| SHA-256 aprovado | `9b7949dabf53b0bbc465f6307a246c8218f94ed37389ca8fa5a81198bb79c765` |
| HEAD histórico da proposta | `2e3747062eedb89756647cd0a17521a25421a5cf` — referência de redação; não muda com commits posteriores |
| HEAD efetivo | Confirmar com `git rev-parse HEAD` no momento da implantação e registrar na evidência. Pode diferir do histórico (por exemplo, depois do commit desta pasta e do `5034`); a autoridade do artefato é o SHA-256 acima, não o HEAD |

Conferir o SHA-256 imediatamente antes da execução. Aplicar o arquivo **uma única vez, sem retry automático**; qualquer divergência de hash ou de texto = STOP.

### 7.2 Pré-condições LIVE (somente leitura, no mesmo dia da aplicação)

1. `5149`, `5150` e `5151` existem com as assinaturas `(jsonb, uuid, uuid)`, `(jsonb)` e `(jsonb)`; o `prosrc` de cada uma é igual ao corpo de `database/schema/5149`/`5150`/`5151` (sem deriva desde a promoção).
2. Dono `postgres`, `SECURITY DEFINER`/`INVOKER`, volatilidade, `search_path` vazio e ACL conforme `05d` — snapshot guardado para comparação em 7.3.
3. `2268` presente: `card_variant.is_active NOT NULL`, `ck_card_variant_default_active` e `trg_guard_card_variant_active` habilitado nas quatro tabelas.
4. Baseline de contagens: `bulk_operation`, `physical_card`, `card_variant` inativas.
5. Nenhum consumidor das três RPCs em `web/` ou `supabase/functions` (fingerprints anteriores ficam inválidos — §3).

### 7.3 Verificações posteriores

1. `5149` contém `is_active`; `5150` e `5151` contêm `CARD_VARIANT_INACTIVE`.
2. Assinaturas, dono, segurança, volatilidade, `search_path` e ACL idênticos ao snapshot de 7.2.
3. `5824` → `30/29/0/1` (`K01` aceito, §5); `5822` → `64/64`; `5823` → `60/60`. Os três terminam em `ROLLBACK`.
4. Contagens de 7.2 item 4 idênticas depois dos harnesses.

### 7.4 Tratamento de falhas

| Momento | Ação |
|---|---|
| Pré-condição falha | Não aplicar. STOP e diagnóstico. |
| Erro durante o `5152` | A transação é desfeita por inteiro; nada muda no LIVE. STOP. |
| Verificação posterior ou harness FAIL | **STOP.** Não reverter automaticamente. Preservar as evidências (saídas de 7.2 e 7.3, logs dos harnesses, estado das três funções) e diagnosticar. Qualquer rollback (§6) só com autorização específica de Fabrício para aquele rollback. |

Depois do PASS: promover o `5152` para `database/schema/` e atualizar `05d`, `README`, `ROADMAP` e `log.md` no mesmo ciclo.

### 7.5 Correção documental do `5034` (tratamento separado)

`database/schema/5034_create_create_collection_function.sql` v1.2 altera **só o cabeçalho** (sequência que fechava o comentário antes da hora); o corpo SQL é byte-idêntico. **Nenhuma ação no LIVE:** a função está em produção desde 2026-09-01 e foi depois substituída por `5068`. Deve ir em **commit próprio**, separado do `5152`.

### 7.6 Resultado da implantação

| Item | Resultado |
|---|---|
| Pré-condições (7.2) | Todas atendidas: `prosrc` de `5149`/`5150`/`5151` = `database/schema` (md5), `2268` íntegro, contagens `bulk_operation` 0 / `physical_card` 0 / inativas 0, nenhum consumidor. |
| Aplicação | Uma vez, sem erro, via `apply_migration` do Supabase (transação da própria ferramenta; `BEGIN`/`COMMIT` do arquivo omitidos no envio). Ledger `20261016234129`. Os três corpos no LIVE = arquivo, byte a byte (md5 de `prosrc`). |
| 7.3 itens 1–2 | PASS — código contém `is_active`/`CARD_VARIANT_INACTIVE`; assinaturas, dono, segurança, volatilidade, `search_path` e ACL inalterados. |
| 7.3 item 3 | `5824` v1.0 **30/29/0/1 GATE OK**; `5822` **64/64/0/0**; `5823` v2.2 **60/60/0/0** (Preview com 1000 variantes reais: 1212 ms, observacional). |
| 7.3 item 4 | Resíduo zero (10 tabelas, incluindo inativas e Game sintético). |
| Security Advisor | Nenhum alerta novo (lista completa comparada antes × depois). |
| Promoção | Cópia canônica idêntica em `database/schema/5152_…sql`; só o cabeçalho `Status` mudou após a aplicação. SHA-256 do arquivo com o cabeçalho final: `5088955ba34cd0e7d3b0dba46b8491e54907a776d79afe7a772e091cffa3b370` (o SHA-256 aprovado em 7.1 refere-se ao texto aplicado, antes da troca do cabeçalho). |
| Corpo vigente depois de BULK-04 | `5150` e `5151` foram depois substituídas por `5155` e `5158` (pasta `2026-10-16-bulk-04-register-card-set`); `5149` continua com o corpo desta migration. |
