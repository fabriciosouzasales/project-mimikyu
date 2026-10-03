# Evidência CN-1 — P14(a) lado CN1, P14(b1)/(b2)/(c)/(d), K1, K2 e K8b (2026-10-02/03)

| Campo | Valor |
|---|---|
| Objetivo | Preservar no repositório a evidência primária do ambiente isolado CN-1 (Supabase local via CLI + Docker), para que P14/K1/K2/K8b não dependam do archive local, de handoff ou de chat. |
| Mandato | `BATCH12-PHASE6-CN1-EVIDENCE-PRESERVATION-AND-RECONCILIATION-02` (inventário e gate fail-closed em `…-01`). Baseline `4f9753d51b2e018b1d2590ebe17a98918fc36218`. |
| Escopo | Só preservação: bytes copiados sem alteração. Nenhum SQL, nenhum acesso ao LIVE, nenhum Docker, nenhuma nova execução CN-1. |
| Origem | `C:\b12-archive\CN1-P14D\`, criado pelo runner de descarte P14(d) `CN1-P14D-DISPOSAL-RUNNER-CORRECTION-02` (md5 `8f41e742122cce050a429ee60f7c8803`), em 2026-10-03T02:32Z. |
| Conteúdo | `.gitattributes` (`raw/** -text`), `MANIFEST.md5` (formato `md5sum`: hash, dois espaços, caminho), `MANIFEST.tsv` (md5, bytes, arquivo, origem, mtime) e `raw/`: **255 arquivos, 362.029 bytes**. |

## 1. Seleção de custódia, não reprodução integral

O `MANIFEST.md5.txt` original do archive (md5 `5d4897b27c440836af3f90a421656e52`) cobre **605 arquivos, 5.114.977 bytes**:

- 18 pastas de `evidence-snapshot\` (580 arquivos);
- `failed-attempt-snapshot\` (25 arquivos).

O archive tem ainda `P14D-RUN\` (28 arquivos), fora desse manifesto porque é a evidência do próprio descarte.

Esta pasta versiona **apenas uma seleção de custódia**:

| Conjunto preservado (`raw/…`) | Arquivos | Bytes | Fingerprint de origem (`MANIFEST.meta.txt`) |
|---|---|---|---|
| `evidence-snapshot/CN1-4-P14A-LOCAL` | 20 | 21.215 | `files=20 md5=1280b0a6…` |
| `evidence-snapshot/CN1-5-P14BC-CORRECTION-02` | 36 | 15.673 | `files=36 md5=e4a3c553…` |
| `evidence-snapshot/CN1-6-K1` | 50 | 76.303 | `files=50 md5=02a1d1eb…` |
| `evidence-snapshot/CN1-6-K2-CORRECTION-02` | 65 | 98.220 | `files=65 md5=312d8158…` |
| `evidence-snapshot/CN1-6-K8B-CORRECTION-04` | 54 | 64.203 | `files=54 md5=bc527a3a…` |
| `P14D-RUN` | 28 | 25.595 | — (não coberto pelo manifesto do archive) |
| `archive-manifest/MANIFEST.md5.txt` e `MANIFEST.meta.txt` | 2 | 60.820 | `5d4897b2…`, `66d38851…` |

**Não versionados** (permanecem só no archive): as outras 13 pastas de `evidence-snapshot` e o `failed-attempt-snapshot`. São as tentativas STOP e as etapas CN1-1/2/3, ou seja, proveniência e contexto, não prova dos itens desta pasta. O manifesto original é preservado para manter a cadeia com o conjunto maior.

## 2. Verificação

- **Byte a byte:** os 255 arquivos são idênticos à origem (`cmp`): 255/255, 0 divergentes.
- **Contra o manifesto do archive:** os 225 arquivos das 5 pastas de `evidence-snapshot` conferem com as 225 linhas correspondentes do `MANIFEST.md5.txt` original (md5 e bytes): 225 ok, 0 divergentes. O manifesto completo do archive foi recalculado no inventário (`…-01`): 605 ok, 0 ruins, 0 ausentes.
- **`MANIFEST.md5` desta pasta:** formato canônico do `md5sum` (`<md5>  raw/<caminho>`), 255 linhas, sem comentários. Validação, a partir desta pasta: `md5sum -c MANIFEST.md5` → 255 `OK`, 0 falhas.
- **`MANIFEST.tsv`:** as mesmas 255 entradas com bytes, origem no archive e mtime de origem. Os bytes declarados conferem com os arquivos preservados (0 divergentes).
- **Runners:** os scripts executados **não** fazem parte desta seleção. Cada `RESULT.txt` pina o md5 do runner. Cópias fora do repositório com md5 idêntico existem para K1 (`ea6230b0…`), K2 (`7aaefe32…`), K8b (`29ce3c0a…`) e P14(d) (`8f41e742…`), mas não foram versionadas (fora do mandato).

## 3. Segurança

Varredura dos 255 arquivos preservados:

- JWT (`eyJ….…`), `sb_secret_`/`sb_publishable_`/`sbp_`, `PGPASSWORD=`, URI com senha, chave privada, `SCRAM-SHA-256$`, `Authorization: Bearer`, `apikey:`, pares `password|secret|token=valor` e e-mails: **0 ocorrências**.
- Nenhum arquivo proibido: `.dpapi`, `local_pw*`, `*.verifier`, `container_inspect*`, `data.sql`, `schema.sql`, `auth_stub_ids*`, `.env*`, `config.toml`.
- Acertos textuais sem valor secreto:
  - nomes de caminho (`secrets\cn1-3-admin.dpapi existe=True`, `acao=removida`);
  - `grant_type=password (credencial do CN1-3 em memoria)`, sem valor;
  - `anon_key_present=True`, sem valor.
- Gates dos próprios runners: V6 `segredos=0 jwt_like=0` em CN1-4 e CN1-5; V5 `segredos=0` em K1 e K2; P14(d) A10 e B3 `segredos=0` com 7 valores secretos carregados.
- A palavra `postgres` aparece só como referência operacional (`supabase/postgres:17.6.1.147`, `psql (PostgreSQL) 17.6`). Ver §5.

Os registros também contêm, sem valor secreto: caminhos locais, PIDs, xids, UUIDs de fixture sintética e o UUID do admin local do CN-1.

## 4. Matriz requisito → artefato → tipo de prova → resultado → limitação

| Requisito (2830 v7.0 P14 / D) | Artefato | Tipo de prova | Resultado | Limitação |
|---|---|---|---|---|
| **P14(a)** paridade LIVE × ambiente por impressão digital | `CN1-4-P14A-LOCAL/` (`RESULT.txt`, `P14A_CN1_OUTPUT.csv` md5 `07cbe136…`, `10_capture_summary.txt`) | DIRECT PRIMARY, **só o lado CN1** | Captura CN1: P6 SQL pinado `2738566c…` (14.610 B), C2 31/31 itens, `agg_raw=6e2ef02e…`, `agg_lf=e926f44d…`. VERDICT: "CN1-4 CAPTURE = PASS (… paridade NAO decidida: requer captura LIVE e comparacao)" | **Captura LIVE e comparação LIVE×CN1: EVIDENCE-NOT-RECOVERABLE.** Não existem em repositório, archive, b12-pg17, outputs, uploads nem registros de ferramenta; só em texto de mandato, que não é prova. **P14(a) = PARTIAL / OPEN** |
| **P14(b1)** HTTP com admin real | `CN1-5-P14BC-CORRECTION-02/` | DIRECT PRIMARY | B1_1…B1_7 PASS: JWT real 200, claims, `is_admin()` jwt=true / anon=false, token adulterado 401, isolamento por requisição 3×. VERDICT PASS | Uma execução |
| **P14(b2)** conexões Postgres persistentes | idem | DIRECT PRIMARY | B2_1…B2_5 PASS: 3 pids distintos, mesmo pid e mesmo txid entre statements, `auth.uid()` = admin, `is_admin()=t` | idem |
| **P14(c)** prova de canal | idem | DIRECT PRIMARY | C1/C2 PASS: observadora vê `idle in transaction` com `backend_xid`; R1/R2 PASS | idem |
| **P14(d)** fixture sintética, descarte registrado | `P14D-RUN/` | DIRECT PRIMARY | 35 PASS / 0 STOP: A1–A10, B1–B5, C, D9. VERDICT "CN1 P14(d) = PASS": evidência preservada e manifestada; DPAPI removida; containers, volumes, rede, config e dados descartados | O upload `CN1-P14D-…RESULT.txt` (`0bf131b7…`) é derivado (RESULT + concatenação dos arquivos) e não foi versionado |
| **P14(e)** evidência registrada (impressão digital LIVE × ambiente, prova de canal, script, saídas, observações de lock) | todos os conjuntos acima | DIRECT PRIMARY, só lado CN1 | prova de canal, saídas e `pg_locks`/`pg_stat_activity`/`pg_blocking_pids` preservados | impressão digital LIVE × ambiente não recuperável, mesma lacuna de P14(a) → **PARTIAL / OPEN** |
| **K1 / D1** | `CN1-6-K1/` | DIRECT PRIMARY | 34 PASS / 0 STOP. VERDICT "CN1-6 K1 = PASS" (corrida benigna; A e B commitados; 1 variant; `action_log=2`) | **EXECUTION PASS · CONTRACTUAL ACCEPTANCE OPEN (D4)** → D1 PARTIAL / OPEN |
| **K2 / D2** | `CN1-6-K2-CORRECTION-02/` | DIRECT PRIMARY | 42 PASS / 0 STOP. VERDICT "CN1-6 K2 = PASS" (K2.a–K2.e via HTTP/JWT real; `action_log=5`; nenhum 23505 cru ao HTTP; K1 intacto) | **EXECUTION PASS · CONTRACTUAL ACCEPTANCE OPEN (D4)** → D2 PARTIAL / OPEN; E2 PARTIAL / OPEN |
| **K8b / D3** | `CN1-6-K8B-CORRECTION-04/` + `CN1-6-K1/07d_k8b_adjudication.txt` + gate `P7d_k8b_pass_adjudicated` de `CN1-6-K1/RESULT.txt` | DIRECT PRIMARY + adjudicação mecânica primária posterior | RESULT bruto: 37 PASS / 1 STOP (só V5), VERDICT "K8b = STOP (V5 … segredos=3)", preservado sem correção. Adjudicação: V5 = falso positivo provado (§5). Execução comportamental (K8B-1…K8B-12) = PASS | **EXECUTION PASS · CONTRACTUAL ACCEPTANCE OPEN (D4)** → D3 PARTIAL / OPEN |
| **D4** P14(a) + P14(c) | — | — | P14(c) CLOSED; P14(a) OPEN | **D4 = PARTIAL / OPEN** |

## 5. Adjudicação K8b / V5

**Causa.** O runner K8b-04 (`29ce3c0a…`) busca o valor de `POSTGRES_PASSWORD` do container em todos os arquivos de evidência, com `Select-String -SimpleMatch`. Esse comando não diferencia maiúsculas de minúsculas. No CN-1 o valor é o literal local `postgres`, então qualquer menção a `postgres` vira "segredo".

**Prova mecânica, sem inferência:**

1. O runner K1 `ea6230b0…`, executado depois, contém o gate `P7d_k8b_pass_adjudicated`, que verifica:
   - (i) md5 do runner K8b = `29ce3c0a…`;
   - (ii) 38 gates lidos, todos PASS exceto `V5_no_secrets_in_evidence`;
   - (iii) K8B-1…K8B-12, V1–V4 e V6 PASS, mais IMG3=IMG0 e `delta_deadlocks=0`;
   - (iv) **rechecagem no container: `POSTGRES_PASSWORD == 'postgres'` = True** (valor não impresso);
   - (v) arquivos com hit anon = 0 e JWT = 0;
   - (vi) os arquivos com `postgres` são exatamente `04_b12pg17_before.txt`, `09_tooling.txt`, `42_b12pg17_after.txt` e `RESULT.txt`, e as linhas são só referências operacionais.

   Resultado registrado: `P7d … PASS | md5_ok=True k8b_gates_ok=True unico_stop_V5=True final_ok=True pw_literal_postgres=True anon_hits=0 jwt_hits=0 pg_hits_ok=True`. A saída detalhada está em `CN1-6-K1/07d_k8b_adjudication.txt`.
2. **Reconferência nos bytes preservados (sem execução):** no diretório K8B-04, os arquivos que contêm `postgres` (sem distinguir caixa) são exatamente os 4 acima. Excluindo o `RESULT.txt`, escrito depois do V5, restam **3**, o mesmo número do `segredos=3`. Todas as ocorrências são `image=supabase/postgres:17.6.1.147` ou `psql (PostgreSQL) 17.6`.
3. Os runners seguintes (K1, K2) corrigem o método: `postgres_password_pesquisado=False (literal local 'postgres' nao e segredo pesquisavel)`, com anon e JWT ainda proibidos. Ambos fecham com V5 `segredos=0`.

**Conclusão.** O único STOP do K8b é um falso positivo provado mecanicamente por evidência primária, e todos os gates de cenário passaram. A **execução comportamental do K8b = PASS**. O RESULT bruto (`VERDICT … = STOP`) continua preservado sem alteração. A aceitação contratual (D3) segue **OPEN** por D4.

## 6. Limites

- Uma execução por cenário, no CN-1 local. Não é prova no LIVE.
- **P14(a) e P14(e) abertos.** A paridade LIVE×CN1 não está provada no repositório. A 2830 v7.0 diz: "Divergência = K1/K2/K8b não aceitos". A D4 faz de P14(a)+P14(c) condição de validade de D1–D3. Por isso, K1/K2/K8b ficam em **EXECUTION PASS · CONTRACTUAL ACCEPTANCE OPEN**: D1/D2/D3 PARTIAL/OPEN, D4 PARTIAL/OPEN, E2 PARTIAL/OPEN.
- Se a evidência LIVE original da P14(a) for encontrada, a reavaliação exige mandato próprio.
