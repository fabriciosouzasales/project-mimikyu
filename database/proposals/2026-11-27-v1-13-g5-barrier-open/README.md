# V1-13 · Etapa 7 — Abertura funcional da barreira (OPEN) e reversão

| Campo | Valor |
|---|---|
| **Rodada** | A (contrato e artefatos), STD-005 |
| **Status** | **EXECUTADA NO LIVE (2026-11-27; 02:40:26Z de 2026-11-28).** Executor v1.4, run-20261128T024029Z, manifesto `7f8e5483…`: PRE PASS, escrita exit 0, POST PASS; conferência só leitura: OPEN, 0 identidades. `MMKYU_V113_EDITOR_CURATION=on` em Production no Vercel com redeploy; conferência em produção PASS (proprietário). Fechamento pronto e não usado. |
| **Depende de** | Parecer G5 = **GO** (decidido pelo proprietário em 2026-11-27, `G5_PARECER.md`) e autorização expressa da rodada B |
| **Normas** | D-E1 e gates G0–G5 (`../2026-11-15-v1-13-e1e-security-evidence/BARRIER-FEASIBILITY-D-E1.md` §9); C-244; STD-005 §3 |

## O que faz

A barreira 5389 tem três modos: CLOSED (ninguém), TEST (só identidades do registro) e OPEN (todos os autenticados). A abertura muda **só** o modo para OPEN. Nada mais é alterado: funções, permissões e dados ficam como estão. Cada operação nova da V1-13 continua decidida no servidor por papel, participação e posse.

## Artefatos

| Arquivo | Papel |
|---|---|
| `G5_OPEN_PRE_readonly.sql` | gate: barreira CLOSED, 0 identidades, funções da porta canônicas, 5397 e 5398 presentes |
| `G5_BARRIER_OPEN.sql` | escrita, transação única: confere CLOSED e o registro vazio, muda para OPEN e confere OPEN com o registro vazio |
| `G5_OPEN_POST_readonly.sql` | gate: `modo_aberto`, 0 identidades, funções canônicas (sem a chave `barreira`, que o executor exige CLOSED) |
| `G5_OPEN_MANIFEST.txt` | PRE → abertura → POST |
| `G5_CLOSE_PRE_readonly.sql` · `G5_BARRIER_CLOSE.sql` · `G5_CLOSE_POST_readonly.sql` · `G5_CLOSE_MANIFEST.txt` | reversão e STOP de emergência: CLOSED e registro vazio, sem pré-condição que impeça fechar |
| `build_g5.py` · `static_check_g5.py` | manifestos com sha256; verificação estática 17/17 com 16/16 mutações detectadas |
| `G5_PARECER.md` | parecer GO/NO-GO e lacunas para decisão |

Os sha256 saem do `build_g5.py`:

- abertura: `7f8e5483beea46521f549b92e39cdd4363d1afbf31c100973dc35364613f750f`;
- fechamento: `dfd15f73067ee5dd66a0b8961c180fa1e5c30259b97d7d2c71bc0ce51d78ea0f`.

O PRE da abertura foi rodado no LIVE só como leitura em 2026-11-27 e passou: CLOSED, 0 identidades, funções canônicas, 5397 e 5398 presentes.

## Sequência (rodada B, com autorização)

1. **Antes:** decidir o G5 (parecer §3). Revisar os dados da homologação (papéis e convites da E4 que passam a valer).
2. `-Simular` dos dois manifestos.
3. Abertura pelo executor (`G5_OPEN_MANIFEST.txt`, `-ShaManifestoEsperado 7f8e5483…`).
4. Vercel → Project → Settings → Environment Variables: `MMKYU_V113_EDITOR_CURATION` = `on` em **Production**, depois um redeploy.
5. Conferência em produção com uma conta EDITOR: abrir o fichário compartilhado, colocar e retirar uma carta, ver o autor no histórico do titular e o palco da Pokédex compartilhada.
6. Registro: `docs/log.md`, `05d`, `ROADMAP` e matriz.

**STOP ou rollback:** `G5_CLOSE_MANIFEST.txt` pelo executor (`-ShaManifestoEsperado dfd15f73…`). Isso desliga tudo no servidor na hora, sem deploy. Depois, remover `MMKYU_V113_EDITOR_CURATION` (ou pôr `off`) em Production no Vercel e fazer um redeploy. Se o POST do fechamento reprovar por md5 das funções da porta, a barreira já está fechada (STOP pós-escrita): registrar como incidente.
