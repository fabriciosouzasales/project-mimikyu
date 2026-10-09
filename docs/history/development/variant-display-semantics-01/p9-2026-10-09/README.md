# Evidência P9 — `VARIANT-DISPLAY-SEMANTICS-01` / F2.1 (2026-10-09)

Evidência sanitizada do gate de payload da F2.1: só números, enums e hashes. Não contém cookie, token, `.env` nem corpo de resposta.

**Contrato e resultado:** [`docs/architecture/variant-display-semantics.md`](../../../../architecture/variant-display-semantics.md) §6–§7.

| Arquivo | Conteúdo |
|---|---|
| `samples.json` | 24 amostras (2 ambientes × 2 cenários × 6 rodadas; r0 = aquecimento) no formato do `p9-decide` |
| `capture-meta.json` | Ambientes, Set (ME2.5, S1), ordem das rodadas, headers RSC capturados do roteador real e SHA-256 do código injetado |
| `summary.json` / `summary.md` | Saída do `p9-decide.mjs`, executado sem alteração: `{"overall":"PASS","A":"PASS","B":"PASS"}` |
| `build-samples.py` | Transcrição das saídas do navegador para `samples.json`/`capture-meta.json` |
| `MANIFEST.sha256` | SHA-256 dos arquivos acima |

## Método

- **Ambientes.** Baseline `94b64ba` em `127.0.0.1:3101` e F2.1 (`94b64ba` + 3 arquivos) em `127.0.0.1:3102`.
  - Os dois rodaram como builds de produção (`next build` + `next start`, gzip), em cópias isoladas em `C:\mmkyu-p9\`, fora do repositório.
- **Login.** Feito por Fabrício no navegador embutido do app Claude.
- **Código injetado.** O Claude injetou o bundle `p9-inject.min.js` em cada página (SHA-256 `7df16e9471c562bdc6bb41583fc282f443bda7234d67a1d0d853d0226975512f`).
  - O bundle é uma versão de navegador da `p9-lib` com paridade verificada sobre 15 fixtures e 27/27 autotestes.
  - Ele não lê cookies nem storage.
  - O bundle e o ferramental P9 ficam fora do repositório (artefatos de sessão).
- **Cenários.**
  - **A:** documento HTML.
  - **B:** RSC, com os headers observados no `fetch` do roteador ao trocar o seletor ME2 → ME2.5, capturados independentemente em cada porta e idênticos.
- **Encerramento.** Os servidores foram encerrados pelo script do protocolo, que verificou o repositório principal: HEAD, working tree, hashes, `.next` e `node_modules` intactos.
