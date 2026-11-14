# PR-04A · G-D — captura T0 (somente leitura)

| Campo | Valor |
|---|---|
| Rodada | `PR-04A \| G-D T0 READONLY CAPTURE-01` |
| Projeto | Supabase LIVE `qjfutqujxrbzgrtkpgkg` (`mimikyu-core`) |
| Canal | MCP `execute_sql`, uma chamada por consulta, executor `postgres` |
| Fonte | `5365_STATE_readonly.sql` v1.2 (MANIFEST 3/3), consultas 1 e 2 enviadas sem modificação (sha256 dos trechos: c1 `d2af22c24ef1b1cf…`, c2 `3fdfb05af9f3d31c…`) |
| Horário (UTC, relógio do ambiente do agente) | antes da consulta 1: 2026-11-14T02:31:25Z · entre as consultas: 2026-11-14T02:31:48Z · depois da consulta 2: 2026-11-14T02:31:50Z |
| Horário (America/Sao_Paulo, UTC−3) | 2026-11-13 23:31:25 – 23:31:50 |
| **T0 (referência da janela)** | **2026-11-14T02:31:50Z** (fim da consulta 2) |
| T1 mínimo | **2026-11-15T02:31:50Z** (≥ 24 h), mesmo executor, mesmas consultas |

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `T0_consulta1.tool-payload.txt` | Resposta integral da ferramenta à consulta 1, como recebida (JSON com escape de string). |
| `T0_consulta1.json` | O mesmo conteúdo decodificado (`json.loads`), sem nenhuma outra alteração. |
| `T0_consulta2.tool-payload.txt` | Resposta integral da ferramenta à consulta 2, como recebida. |
| `T0_consulta2.json` | O mesmo conteúdo decodificado. |
| `SHA256SUMS` | Hashes de todos os arquivos acima e deste `CAPTURE.md`. |

Transcrição: a resposta da ferramenta foi gravada a partir do texto recebido e aceita só depois de decodificar como JSON válido e conferir: consulta 1 com as 8 assinaturas, md5 e ACL esperados; consulta 2 com 1 META + 26 DADO e chaves únicas. Não há prova criptográfica de ponta a ponta entre o banco e o arquivo.

## Verificação imediata

- Consulta 1: 8/8 assinaturas iguais ao README (md5, dono `postgres`, SECURITY DEFINER, ACL `{postgres=X/postgres,authenticated=X/postgres}`, `authenticated` sim, `anon`/`service_role` não, `postgres` sim).
- META: `executor postgres`, `visibilidade_total true`, `linhas_ocultas 0`, `linhas_total 4937`, `stats_reset 2026-07-17 14:44:59.561669+00`, `dealloc 52`.
- DADO: 26 linhas, `chave_repetida` = 1 em todas, chaves únicas.
- Linhas que decidem o gate (`NAO_ADMIN`): LEGACY_STORAGE 15 · LEGACY_ORGANIZE 3 · LEGACY_ADD 13/13/3/3/3 · AMBIGUOUS 2/3 (`queryid 4472039671804551423`, `6264847537264826768`).
- Contexto (`ADMIN`, não decide): 14 AMBIGUOUS e 1 LEGACY_ADD — esta última (`queryid 1985204789366858170`) é a **própria consulta 2** do preflight: o comentário inicial do arquivo cita `add_physical_cards(` e é guardado no texto. Cresce a cada execução da consulta 2 como `postgres`; não decide o gate. A observação do STATE de que a consulta "não aparece" é imprecisa (só documental).

**Uma fotografia isolada não é PASS do G-D.**
