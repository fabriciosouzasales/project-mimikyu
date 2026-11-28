# V1-13 · E4 — Roteiro de execução da homologação final

| Campo | Valor |
|---|---|
| **Rodada** | `E4 — FINAL HOMOLOGATION EXECUTION READINESS` (2026-11-27) |
| **Status** | **EXECUTADA — PASS (2026-11-27).** TEST aberto (run-20261127T205010Z) e encerrado (run-20261128T002052Z) pelo executor; reteste da rodada de correção com o TEST reaberto pelo mesmo manifesto (run-20261128T005204Z) e encerrado (run-20261128T020010Z). Barreira CLOSED, 0 identidades, D1 desligada. Resultado por bloco e pendências em `docs/operations/v1-13-e4-homologation.md` §Resultado. |
| **Matriz** | `docs/operations/v1-13-e4-homologation.md` (31 casos: 28 obrigatórios). Este roteiro diz como executá-la. |
| **Normas** | C-244 (S1–S10, `05d` §"Critérios de autorização e segurança"); STD-005; gates G3–G5 de `BARRIER-FEASIBILITY-D-E1.md` §9 |

## 1. Sequência mínima

Cada fase só começa com a anterior em PASS. Qualquer STOP leva direto à §4.3.

| Fase | O que | Casos | Autorização |
|---|---|---|---|
| **F0** | Preparação local, sem LIVE: gerar os artefatos com o conjunto de contas (§2), verificação estática, sonda e `-Simular` dos dois manifestos | — | nenhuma |
| **F1** | Escolher as coleções existentes X, Y, Y2 e Z do titular e anotar os bolsos da sonda (§3); nada é criado | — | — |
| **F2** | **G3, negação com JWT real** (barreira CLOSED, registro vazio): sonda `E4_PROBE_G3_CLOSED`; não grava nada | F4, F1 (parcial), S7 (anon) | **A1** |
| **F3** | Abertura do TEST pelo executor (`E4_OPEN_MANIFEST.txt`; o PRE grava o **estado anterior** do titular na evidência) e D1 ligada só no `npm run dev` local | — | **A2** |
| **F4.1** | Papéis e convites: T convida E como VIEWER e promove a EDITOR; convida E2 como EDITOR (E2 aceita) e V como VIEWER; E e V abrem as quatro modalidades; recusa de convite e convite revogado entre contas do conjunto | A1, A2, B1, B2 | A2 |
| **F4.2** | Fichário pela interface (E em X): colocar, substituir, mover e trocar, retirar e desfazer, organização automática (com T alterando entre prévia e aplicação), reservas, fixação, páginas, espaços, novidades em Z (Master Set, como titular para comparação) | C1–C5, **S1** | A2 |
| **F4.3** | Pokédex pela interface (E em X): mover, desvincular, escolher e restaurar a representante; posição fora do escopo de gerações | D1, D2, **S1** | A2 |
| **F4.4** | **Sonda `E4_PROBE_TEST`** (chamadas diretas com JWT real, P4-B) | E1–E3, F1–F3, **S2–S9** | A2 |
| **F4.5** | Concorrência em duas janelas lado a lado (§5.3) | G1, G2, **S10**, **S8 concorrente**, PR-04B | A2 |
| **F4.6** | Histórico e autoria de tudo que F4.1–F4.5 gravou | H1, H2, **S1 (ator)**, **S9** | A2 |
| **F4.7** | Mobile e acessibilidade, visual (Light e Dark, desktop e celular) | I1, I2, I3 | A2 |
| **F4.8** | Regressões do titular T e desempenho | J1, K1, K2 | A2 |
| **F4.9** | Capa (5390): T envia, troca e remove; o EDITOR é recusado pela API do Storage (passos E4-32 e E4-33 da sonda) | S6, D-E3-6 | A2 |
| **F5** | Encerramento pelo executor (`E4_CLOSE_MANIFEST.txt`); D1 desligada; `dev` reiniciado | — | **A3** (dada junto com a A2) |
| **F6** | Depois de fechar: a sonda G3 de novo (deve repetir F2) e J2 (configuração desligada: só leitura V1-12) | F4, J2 | A3 |
| **F7** | Registro, parecer G5, decisões pendentes (§6) | L1 | — |

**S1–S10 (C-244) × fases:**

| Cenário | Onde é provado |
|---|---|
| S1 | F4.2 e F4.3 (aceito), com o ator EDITOR conferido em F4.6 |
| S2 | E4-23 a E4-25 |
| S3 | E4-34 a E4-36 |
| S4 | E4-37 a E4-39 |
| S5 | E4-04 a E4-08 |
| S6 | E4-26 a E4-33 |
| S7 | G3-01, G3-02, E4-16, E4-19 a E4-22 |
| S8 sequencial | E4-40 a E4-47 |
| S8 concorrente | F4.5 |
| S9 | `scan` de chaves proibidas em toda leitura da sonda, mais F4.6 |
| S10 | F4.5 |

PR-04B fica em F4.5. A prova P4-B é a própria sonda (JWT real pelo PostgREST).

**D-E3-2:** não é executável na E4. O histórico do **fichário** do titular (5269) não traz o autor. H1 confere a autoria onde o contrato a entrega: 5388 para participantes e `get_collection_activity` (5395) para titular e participantes. Para o fichário do titular, H1 registra "autor não exibido (D-E3-2)", sem FAIL. A pendência continua **bloqueando a publicação** até você decidir (§6).

## 2. Identidades, barreira e alcance da D1

- **Identidades TEST:** as **4 contas existentes** escolhidas por você (decisão `E4 — EXECUTION ADAPTATION`):

  | Rótulo | Conta | Papel na E4 |
  |---|---|---|
  | T | a conta que já tem coleções | titular das coleções X, Y, Y2 e Z |
  | E | uma das outras três | EDITOR de X e Y; VIEWER de Z |
  | E2 | outra | EDITOR de X (concorrência e outra participação) |
  | V | a última | VIEWER de X |

  **Configuração (uma vez, local):** `python build_e4.py --contas T=<username> E=<username> E2=<username> V=<username>` e depois `python build_e4.py`. O repositório guarda **só o md5** de cada username (`E4_CONTAS_MD5.json`); a resolução para UUID acontece no banco. O PRE da abertura exige que as 4 existam e que T tenha coleções ativas, e **registra na evidência** papel, UUID, username, se é administradora e quantas coleções tem. Administração e compartilhamentos V1-12 já existentes são **informativos** (contas reais têm vida própria) e não bloqueiam; continuam **bloqueantes**: nenhum EDITOR e nenhuma auditoria de coleção fora do conjunto.
- **Barreira:** modo `TEST` com o registro igual a essas quatro contas, nada além. A porta (5389) só abre quando `modo = TEST` **e** `auth.uid()` está no registro. Qualquer outra conta recebe exatamente o mesmo resultado do modo CLOSED, e isso inclui todas as contas reais, a sua e `anon`: leituras V1-13 vazias e escritas com `CAPABILITY_NOT_ENABLED`. O POST da abertura prova o registro (`registro_igual_contas`); os booleanos de isolamento provam que nenhum participante EDITOR, coleção de teste ou auditoria envolve conta real. O modo `OPEN` nunca é usado (a verificação estática barra).
- **D1 (`MMKYU_V113_EDITOR_CURATION`):** lida **só no servidor** do front.
  - Ligada apenas no `web/.env.local` da sua máquina, durante a E4, com `npm run dev` (http://localhost:3000).
  - No Vercel (Production e Preview) ela fica **ausente ou `off`**. Confirme no painel antes da A2: você confere, porque o agente não tem acesso.
  - Mesmo ligada por engano, ela só mostra controles. O servidor continua negando quem não está no registro.
- **Navegadores:** um perfil de navegador separado para cada conta do conjunto (T, E, E2 e V).

## 3. Coleções existentes e operações que modificam dados

**F1 — escolha (pela interface, sem criar nada):** entre as coleções do titular,

| Var | Requisito | Usada em |
|---|---|---|
| **X** | Pokédex com fichário **exclusivo**, exemplares elegíveis **fora de bolso**, alguns bolsos livres | C1–C5, D1–D2, E1–E3, F1–F3, G1–G2, K1 |
| **Y** + **Y2** | Y com fichário que **recebe Y2 como convidada** (fichário de várias coleções) | S3, S4, token de outra coleção |
| **Z** | qualquer outra coleção (de preferência Master Set) | S2 (E é VIEWER) |

- Se não existir um fichário com coleção convidada, S3/S4 exigem configurar um (pela interface, como titular): é a **única** mudança de estrutura necessária.
- K1 mede no volume real de X; com menos de 500 alocações, registre o volume ao lado do tempo.
- **Exemplares fora de bolso** (exigidos pela sonda e por G1): antes da sonda TEST, deixe pelo menos **3** cartas de X e **1** de Y fora de bolso. Pode ser pelo próprio teste de retirada (C3), feito pelo EDITOR, ou pelo titular, pela interface.
- Para a sonda TEST, anote um bolso livre em X (`LX_*`), um em Y (`LY_*`) e um bolso de Y com carta de Y2 (`Y2_*`). Os ids de coleção estão na URL.

**Estado anterior:** o PRE da abertura grava, na evidência do executor (fora do repositório), as contas, as coleções do titular (nome, descrição, capa, fichário, convidada, alocações), os membros, cada bolso ocupado, fixado ou reservado, as páginas por fichário, as atribuições e representantes da Pokédex, e as impressões digitais `*_fp`. O POST do encerramento grava as mesmas `*_fp`.

**O que a E4 muda nos dados reais do titular** (aceito na A2):

| Origem | Muda | Como preservar |
|---|---|---|
| F4.1 | participações e papéis entre as 4 contas | ficam inertes depois de F5; remova pela interface se quiser |
| F4.2–F4.5 | organização de X e Y: bolsos, reservas, fixação, páginas, espaços, organização automática, referências de espécie; Pokédex de X (atribuições, representantes); nome e descrição de X | `fichario_antes`, `paginas_antes`, `pokedex_antes`, `representantes_antes`, `colecoes_antes` do PRE da abertura, para restauração pela interface |
| F4.4 (E4-44) | uma colocação em `LX_*` | retirar pela interface |
| PR-04B (F4.5) | condição de **um** exemplar escolhido | restaurar a condição no fim; `condicao_fp` volta a ser igual |
| F4.9 | imagem de capa de X | reenviar a imagem original (`colecoes_antes.capa`) |
| Auditoria (5267, 5394–5396) | eventos no histórico de X, Y e Z | **imutáveis**: o histórico real passa a mostrar a homologação |

**Patrimônio intocado (critério de PASS):** alocações, exemplares, locais e acervo não mudam. `alocacoes_fp` e `exemplares_fp` precisam ser **iguais** no PRE da abertura e no POST do encerramento; `condicao_fp` também, depois da restauração da PR-04B. `eventos_editor_externos_n` precisa ser igual.

## 4. Ativação e encerramento

Rode tudo no PowerShell, a partir da raiz do repositório `project-mimikyu`, com `supabase\.temp\linked-project.json` apontando para `qjfutqujxrbzgrtkpgkg`.

### 4.1 F0 — simulação (offline, sem banco)

```powershell
python database\proposals\2026-11-27-v1-13-e4-homologation\static_check_e4.py
node --test scripts\v1-13\e4-probe.test.mjs
powershell -ExecutionPolicy Bypass -File scripts\v1-13\Invoke-ReviewedSql.ps1 -Repo . `
  -Manifesto database\proposals\2026-11-27-v1-13-e4-homologation\E4_OPEN_MANIFEST.txt -Projeto qjfutqujxrbzgrtkpgkg -Simular
powershell -ExecutionPolicy Bypass -File scripts\v1-13\Invoke-ReviewedSql.ps1 -Repo . `
  -Manifesto database\proposals\2026-11-27-v1-13-e4-homologation\E4_CLOSE_MANIFEST.txt -Projeto qjfutqujxrbzgrtkpgkg -Simular
```

Antes, uma vez: `python database\proposals\2026-11-27-v1-13-e4-homologation\build_e4.py --contas T=... E=... E2=... V=...` e `python ...\build_e4.py` (gera os SQL e manifestos; os hashes saem no terminal e passam a valer em §4.2, §4.3 e §6). Esperado: `STATIC CHECK E4: 29/29 PASS`, `# pass 6` e as duas simulações com código de saída 0.

### 4.2 F3 — abertura (só com a A2)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\v1-13\Invoke-ReviewedSql.ps1 -Repo . `
  -Manifesto database\proposals\2026-11-27-v1-13-e4-homologation\E4_OPEN_MANIFEST.txt -Projeto qjfutqujxrbzgrtkpgkg `
  -ShaManifestoEsperado <sha256 de E4_OPEN_MANIFEST.txt gerado em F0>
```

Confirmação digitada: `EXECUTAR qjfutqujxrbzgrtkpgkg <8 primeiros do sha>`. Os passos são PRE (gate) → abertura → POST (gate).
- **PASS:** os três passos com exit 0 e gates aprovados.
- **Guarde** a evidência do PRE: estado anterior, `*_fp` e `eventos_editor_externos_n`.

Depois, ligue a D1 **só na sua máquina**:

```powershell
Add-Content web\.env.local "MMKYU_V113_EDITOR_CURATION=on"
cd web; npm run dev
```

### 4.3 F5 — encerramento (A3; também é o STOP da E4)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\v1-13\Invoke-ReviewedSql.ps1 -Repo . `
  -Manifesto database\proposals\2026-11-27-v1-13-e4-homologation\E4_CLOSE_MANIFEST.txt -Projeto qjfutqujxrbzgrtkpgkg `
  -ShaManifestoEsperado <sha256 de E4_CLOSE_MANIFEST.txt gerado em F0>
```

Confirmação digitada: `EXECUTAR qjfutqujxrbzgrtkpgkg <8 primeiros do sha>`. Passos: PRE (gate que **só registra** `modo_atual`, `identidades_n`, `identidades_fora_do_conjunto_n` e `eventos_editor_externos_n`; o único critério é a linha de estado existir) → encerramento → POST. Nem o PRE nem a escrita têm condição que impeça fechar. Esperado no PRE: `TEST`, 4 e 0; se vier diferente, feche mesmo assim e registre como incidente.
- **PASS** exige:
  - `barreira = CLOSED`;
  - `identidades_teste = 0`;
  - todos os booleanos de isolamento verdadeiros;
  - `eventos_editor_externos_n`, `alocacoes_fp` e `exemplares_fp` iguais aos do PRE da abertura (`condicao_fp` igual depois da restauração da PR-04B).

Se a homologação parou por STOP, o encerramento roda do mesmo jeito: o PRE só registra e a escrita não tem pré-condição. A evidência do incidente fica nas execuções do executor e da sonda.

Depois, desligue a D1 e confira:

```powershell
(Get-Content web\.env.local) | Where-Object { $_ -notmatch '^MMKYU_V113_EDITOR_CURATION=' } | Set-Content web\.env.local
(Select-String -Path web\.env.local -Pattern 'MMKYU_V113_EDITOR_CURATION').Count   # esperado: 0
```

Por fim, pare o `npm run dev` (Ctrl+C) e suba de novo. Se o executor falhar no encerramento, a contingência é o `g1/EMERGENCY_STOP_V1_13.sql` com os complementos S2 e E37B, com autorização própria.

### 4.4 Sonda (F2, F4.4 e F6)

Copie os modelos para `Downloads\mmkyu-runs\e4\`, fora do repositório, e preencha os e-mails das contas do conjunto, os usernames pedidos e os ids. Para cada conta, a sonda pede a senha **oculta** e não grava a senha nem tokens.

```powershell
node scripts\v1-13\e4-probe.mjs --cases "$env:USERPROFILE\Downloads\mmkyu-runs\e4\E4_PROBE_G3_CLOSED.json" `
  --out "$env:USERPROFILE\Downloads\mmkyu-runs\e4\probe-g3-$(Get-Date -Format yyyyMMddTHHmmss).json"
node scripts\v1-13\e4-probe.mjs --cases "$env:USERPROFILE\Downloads\mmkyu-runs\e4\E4_PROBE_TEST.json" `
  --out "$env:USERPROFILE\Downloads\mmkyu-runs\e4\probe-test-$(Get-Date -Format yyyyMMddTHHmmss).json"
```

- **Para no primeiro desvio.** Código de saída 0 = PASS; 1 = STOP; 2 = erro de uso.
- **Pausas:** a sonda TEST para em três pontos para T trocar e remover papéis pela interface (S8/E3).
- **E4-44 escreve:** coloca uma carta de teste em `LX_*`.
- **Requisito:** Node 18 ou superior (`fetch`).

## 5. Critérios

### 5.1 PASS da E4 (todos)

1. F2 e F6 com a sonda G3 em PASS.
2. Abertura e encerramento com PASS no executor; `eventos_editor_externos_n`, `alocacoes_fp` e `exemplares_fp` iguais nos dois (e `condicao_fp` depois de restaurar a PR-04B).
3. Os **28 casos obrigatórios** da matriz em PASS, com evidência, incluindo os dez cenários S1–S10 e o S8 concorrente.
4. A sonda TEST em PASS completo: E4-01 a E4-47, sem chave proibida em nenhuma leitura.
5. **K1 (limite objetivo adotado na E4):**
   - **PASS:** E4-01 (lista elegível de X) e E4-44 (colocar) ≤ 1500 ms cada, medidos pela sonda, com o volume real de X registrado.
   - **Observação não bloqueante:** entre 1500 e 3000 ms.
   - **FAIL:** acima de 3000 ms.
6. D1 desligada no fim, conferida, e no Vercel ausente ou `off`.

### 5.2 STOP (encerre o TEST na hora, §4.3; não tente corrigir)

- **Na sonda:**
  - qualquer FAIL;
  - escrita aceita quando a recusa era esperada;
  - chave patrimonial ou pessoal numa resposta.
- **No executor:** gate reprovado ou exit ≠ 0 em qualquer passo.
- **Na interface:**
  - dado de outra conta, local, condição, valor, e-mail ou id interno aparece a um participante;
  - estado parcial ou inconsistente depois de uma recusa;
  - impasse que não se resolve.
- **Fora do conjunto:** qualquer conta fora das 4 envolvida em participação EDITOR ou evento da V1-13; ou mudança em `alocacoes_fp`/`exemplares_fp`.
- **Outras falhas:** erro 5xx repetido, ou barreira em estado diferente do esperado.

Depois de um STOP: registre, encerre (F5) e abra uma rodada de correção. Nunca repita até passar.

### 5.3 Concorrência (F4.5)

Use duas janelas, uma por conta, lado a lado. Dispare as duas ações ao mesmo tempo (contagem regressiva) e **depois** recarregue as duas.

| Caso | Como fazer | PASS |
|---|---|---|
| G1 | E e E2 colocam no mesmo bolso de X; depois, o mesmo exemplar em bolsos diferentes | uma conclui; a outra recebe recusa clara; sem duplicata |
| G2 / S10 | T e E movem cartas no mesmo fichário X; T e E alteram a mesma posição da Pokédex | serializado; sem impasse, sem estado parcial e sem bolso de terceiros alterado |
| S8 conc. | E aplica a organização automática em X enquanto T troca E para VIEWER | ou conclui antes da troca, ou é recusada; nunca grava depois da troca |
| PR-04B | duas janelas de T editam a condição dos mesmos exemplares; E edita a condição de cartas próprias ao mesmo tempo | sem perda de atualização em T; nada de E afeta T, e vice-versa |

### 5.4 NO-GO de publicação (mesmo com a E4 executada)

- Qualquer S1–S10 sem PASS registrado (C-244: nenhuma aceitação de risco substitui a prova).
- PR-04B não reavaliada.
- D-E3-2 sem decisão.
- Qualquer FAIL obrigatório sem correção homologada.
- Barreira fora de CLOSED com registro vazio ao fim da E4.

A abertura (`OPEN`) é decisão posterior (G5 e etapa 7), fora desta E4.

## 6. Autorizações necessárias e pontos de decisão

| Ponto | O que autoriza | Inclui |
|---|---|---|
| **A1** | F2 no LIVE com a barreira CLOSED | rodar a sonda G3 com as contas do conjunto (só chamadas recusadas; nada gravado) |
| **A2** | F3 e F4 | executor com `E4_OPEN_MANIFEST.txt` (sha gerado em F0); D1 ligada só no `.env.local`; sonda TEST; **as mudanças nos dados reais do titular listadas em §3** |
| **A3** | F5 e F6, **concedida junto com a A2** para que o encerramento nunca espere | executor com `E4_CLOSE_MANIFEST.txt` (sha gerado em F0); D1 desligada |
| Decisão | depois de F7 | D-E3-2 (aceitar como limitação documentada da V1.0 ou abrir rodada de SQL); manter ou remover as participações criadas entre as 4 contas |

## 7. Evidências

Fora do repositório, em `Downloads\mmkyu-runs\e4\`:
- as execuções do executor (automáticas);
- as saídas JSON da sonda;
- capturas de tela das contas do conjunto;
- `E4_REGISTRO.md`, com uma linha por caso no formato `| ID | PASS/FAIL/NÃO EXECUTADO | papel | UTC | evidência (arquivo ou captura) |`.

No fechamento (rodada própria), o resumo vai para `E4_EVIDENCE_<data>.md` neste pacote, para a matriz e para `docs/log.md`.

## 8. Artefatos

| Arquivo | Situação |
|---|---|
| `E4_CONTAS_MD5.json` | **a gerar** com o conjunto de contas (§2): só md5 dos usernames |
| `E4_OPEN_PRE_readonly.sql` · `E4_TEST_OPEN.sql` · `E4_OPEN_POST_readonly.sql` · `E4_OPEN_MANIFEST.txt` | **a gerar** por `build_e4.py` (hashes impressos no terminal) |
| `E4_CLOSE_PRE_readonly.sql` · `E4_TEST_CLOSE.sql` · `E4_CLOSE_POST_readonly.sql` · `E4_CLOSE_MANIFEST.txt` | **a gerar** por `build_e4.py` |
| `E4_PROBE_G3_CLOSED.template.json` · `E4_PROBE_TEST.template.json` | modelos da sonda (15 e 47 passos, mais pausas) |
| `build_e4.py` · `static_check_e4.py` | gerador · verificação estática (29/29, com 24/24 mutações, conferida com um conjunto fictício) |
| `scripts/v1-13/e4-probe.mjs` · `e4-probe.test.mjs` | sonda de JWT real · testes (6/6, sem rede) |

Os artefatos da versão `e4_*` (manifestos `e2dfd34b…` e `43500d5a…`) foram **retirados**: dependiam de contas que não serão usadas.

## 9. Defeitos impeditivos corrigidos nesta rodada

1. **Faltava meio de fazer chamadas diretas com JWT real.** A interface não produz token forjado, RPC antiga, coleção alheia nem `anon`, e sem isso E1–E3, F1–F4, S2–S9 e P4-B não eram executáveis. Criei a sonda `e4-probe.mjs`: só PostgREST e Storage, sem SQL, sem tocar na barreira e sem gravar credenciais.
2. **A ativação e o encerramento do TEST não existiam como artefatos revisados.** (Correção `E4-F0 — CLOSE MANIFEST CORRECTION-01`: o manifesto CLOSE não tinha gate antes da escrita, o que o executor v1.4 recusa; ganhou `E4_CLOSE_PRE_readonly.sql`, só de registro, e a verificação estática passou a emular essa regra, X3.) Criei as duas escritas de estado com gates e manifestos. Os gates foram adaptados à regra do executor, que reprova `barreira` ≠ CLOSED.
3. **A matriz exigia o que o contrato não entrega.** H1 pedia o autor também no fichário do titular (D-E3-2). Além disso, K1 não tinha um limite objetivo. A matriz foi ajustada na v1.1.
