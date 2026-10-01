# 2830H — Registro da execução LIVE final do E15 (lote L13, Seção 5)

| | |
|---|---|
| Mandato de execução | `BATCH12-E15-FINAL-LIVE-EXECUTION-02` (2026-10-01). A tentativa `-01` foi recusada no canal antes de chegar ao banco: nenhum SQL executado |
| Closeout | `BATCH12-E15-FINAL-LIVE-EVIDENCE-CLOSEOUT-01`. **Auditoria independente: PASS** |
| Baseline | HEAD `669b8d39f14a450dc7c386636dce0e8eba3c0579` · E15 `2830H_E15_section5_legacy_hold.sql` md5 `83e4d5d9a83958282cbc731725c8a298` (artefato do B3H PASS-LOCAL, `B3H-PASS-LOCAL-RECORD.md`) |
| Canal | Supabase MCP `execute_sql`, projeto `qjfutqujxrbzgrtkpgkg` (PostgreSQL 170006). Autorização explícita de Fabrício, limitada às 6 submissões abaixo |
| Evidência | `E15-LIVE-EVIDENCE-02-20261001T002021Z.zip`, md5 `cfdf7e14a1583299855a4ef95d5de10d` (fora do repositório; `MANIFEST.md5` interno) |
| Resultado | **E15 FINAL LIVE = PASS**, executado uma única vez. Casos `5.1`, `5.2`, `5.3`, `5.6`, `5.7` homologados |
| Cobertura | **135/135** automáticos da `2830` v7.0 (homologação da auditoria independente) |
| Estado | Nenhuma escrita persistente. FREEZE ATIVO; UNFREEZE exige mandato próprio. **Este closeout fecha o harness automático, não o Batch 12 global** (que permanece OPEN até o gate completo HARNESS + UNFREEZE) |

## 1. Sequência executada

S0 local; S4 (E15P) não se aplica ao L13 (aceito pela auditoria: o E15P é instrumento histórico de medição com `gate_pass` falso por contrato). E98 não se aplica.

| Passo | Texto submetido | Resultado | `checked_at` do banco (UTC) |
|---|---|---|---|
| S0 | — (preflight local) | HEAD, árvore e md5 de E15/E00/E99 conformes | — |
| S1 | L1 (runbook §3.1, md5 `0836c36a…`) | conforme §4.1 | 2026-10-01T00:19:00.740041Z |
| S2 | L3 (runbook §3.2, md5 `b7bc3700…`) | conforme §4.2: `locks_on_scope=[]`, sessões `client backend` só `idle` | 2026-10-01T00:19:25.820729Z |
| S3 | E00 integral (md5 `45b6c35c…`) | `gate_pass=true`, 24/24, `d_canon_diff=[]`, `d_baseline_md5=5c329d5e38a7e369cc100ab08953e1a7`, `db_role_setting_rows=10` | 2026-10-01T00:22:57.270771Z |
| S5 | E15 integral (md5 `83e4d5d9…`), **submissão única** | `H283P` (§2) | sem timestamp do banco (ver §3) |
| S6 | E99 com os 3 marcadores do S3 desta rodada (`S6_E99_submitted.sql`, md5 `7bbb69f2…`) | `gate_pass=true`, 9/9, `d_diff=[]`, `d_canon_diff=[]`, `d_baseline_now_md5=5c329d5e…` | 2026-10-01T00:29:50.144464Z |
| S7 | L3 final | conforme §4.2: `locks_on_scope=[]`, sessões `client backend` só `idle` | 2026-10-01T00:30:20.334917Z |

## 2. Resposta terminal do E15

```
ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E15_SECAO_5_LEGADO_HOLD pass=5/5 casos=5.1,5.2,5.3,5.6,5.7 marker=H2830_F8629FEFD6D54373B7A84B439E502456 elapsed_ms=6027 hold=107 structural=365 unconditioned=285 conditioned=80 by_pscid=80 by_psvm=40
CONTEXT:  PL/pgSQL function inline_code_block line 1080 at RAISE
```

`H283P` é o terminal de sucesso (o envelope termina em exceção e desfaz tudo). Valores homologados: `hold=107`, `structural=365`, `unconditioned=285`, `conditioned=80`, `by_pscid=80`, `by_psvm=40`. O contexto (`line 1080`) coincide com o `context_line` do manifesto.

## 3. Ordem E00 → E15 → E99

- E00 (S3) e E99 (S6) têm `checked_at` do banco, e S3 < S6.
- O E15 **não** devolve timestamp do banco no terminal (só `elapsed_ms`).
- A ordem E00 → E15 → E99 é sustentada pelo **registro sequencial da execução** (uma chamada por passo, na ordem S3 → S5 → S6, cada uma iniciada depois da resposta da anterior) e pelas evidências da rodada: o E99 compara com o `d_baseline` do E00 desta rodada (`g_captured_integrity`, `g_baseline_equal`) e nenhum outro envelope foi submetido entre S3 e S6.

## 4. Limites registrados

- O texto é transportado pelo agente dentro da chamada MCP; o banco não devolve hash do texto recebido. A identidade byte a byte do texto recebido com o arquivo do repositório não é provada pelo canal; é coerente com E00 24/24 (`d_baseline_md5` igual ao histórico), com o terminal do E15 na linha 1080 e com `g_captured_integrity=true` no E99.
- Os horários locais do ambiente do agente estão cerca de 1 minuto à frente do banco; não são usados para provar ordem.

## 5. O que esta rodada não fez

Nenhum SQL além das 6 submissões; E15 não repetido; E15P, E98, B3H e A4 não executados; nenhum gerador, SQL ou digest alterado; FREEZE mantido.
