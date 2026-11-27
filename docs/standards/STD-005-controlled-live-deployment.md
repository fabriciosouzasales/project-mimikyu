# STD-005 — Controlled LIVE Deployment (V1-13)

| Campo | Valor |
|--------|-------|
| **Documento** | STD-005 |
| **Título** | Implantação controlada no LIVE — verificações padrão, executor por arquivo, fluxo de rodadas, documentação e homologação progressiva |
| **Versão** | 1.1 (2026-11-27) |
| **Status** | Proposto — aguarda auditoria independente |
| **Objetivo** | Reduzir rodadas e documentação redundantes sem flexibilizar critérios: reutilizar verificações já provadas, eliminar transcrição manual de SQL e antecipar provas. |
| **Escopo** | Toda mudança de banco da V1-13 (e seguintes, se adotado). Não substitui o STD-001 §10 (formato das Queries): o complementa. |
| **Dependências** | `STD-001-database-standards.md`, `CLAUDE.md` |

---

## 1. Princípios

1. **Critério antes da execução.** PASS/STOP definidos no artefato antes de qualquer chamada ao LIVE.
2. **STOP obrigatório** em qualquer divergência material; nada é ajustado no LIVE para contornar.
3. **Transação única** quando aplicável; falha = nada persiste = sem rollback redundante.
4. **Evidência reprodutível:** hashes dos arquivos, texto exatamente o do arquivo, resultado bruto.
5. **Não declarar PASS** do que não foi executado. Separar: validado automaticamente · por inspeção · pendente.

## 2. Verificações padrão (reutilizar; não reinventar por pacote)

Cada pacote escolhe as que se aplicam e as cita pelo código. Um controle só entra se tiver critério de decisão.

| Código | Verificação | Onde | Critério / lição |
|---|---|---|---|
| **V01** | Identidade do destino: projeto LIVE e executor (`current_user`) | executor + PRE | ref do projeto conferida pelo executor; papel = o previsto (hoje `postgres`) |
| **V02** | Barreira 5389: md5 de `v1_13_assert_capability`/`v1_13_capability_open`, modo `CLOSED`, 0 identidades TEST | PRE + precheck + postcheck | qualquer outro estado → STOP |
| **V03** | Hashes canônicos: md5 do `prosrc` de toda função **tocada ou da qual se depende**, calculados do arquivo canônico pelo static check | precheck + postcheck + static | constantes nunca editadas para "passar"; o extrator do static check reproduz md5 já fixados (autoteste) |
| **V04** | Ausência/presença dos objetos novos | precheck | "já aplicada" ou divergente → STOP |
| **V05** | Privilégios efetivos: ACL completo, `has_*_privilege` para `anon`, `authenticated`, `service_role`, `authenticator`, PUBLIC (grantee 0), herança; tabelas/sequências novas com `REVOKE` explícito (o Supabase concede privilégios padrão a objetos novos) | postcheck + POST | privilégio inesperado → STOP. Lição S1: ACL real sem `service_role` — o rollback não pode presumir |
| **V06** | Capacidade **DDL × DML**: o que o booleano prova | PRE | **Lição 5237/5390:** pertencer ao dono de `storage.objects` é falso no Supabase, embora `postgres` crie/altere políticas ali (5176, 5377, 5237). Não usar pertencimento como critério em esquemas da plataforma; usar o privilégio que a instrução exige (ex.: `LOCK … ACCESS EXCLUSIVE` ⇐ UPDATE/DELETE/TRUNCATE/MAINTAIN) e registrar o precedente como **evidência, não garantia**. Em tabelas `public` do projeto (dono `postgres`), pertencimento ao dono **é** a prova correta |
| **V07** | Dependências: `pg_depend`, `prosrc`/políticas que citam o objeto, gatilhos existentes na tabela | PRE + precheck | dependente inesperado → STOP. Lição S1: o `EMERGENCY_STOP` revoga sem guarda → REVOKE em vez de DROP |
| **V08** | Travas: `lock_timeout` curto + `LOCK … NOWAIT` antes do DDL na tabela quente | migration | 55P03 → nada persiste; nova janela por decisão do operador, sem repetição automática |
| **V09** | Postcheck interno na mesma transação: objetos, segurança (`prosecdef`, `search_path=''`, volatilidade), privilégios, retratos (hash de políticas/ACLs que ficam) comparados ao do precheck | migration | divergência aborta a transação |
| **V10** | Rollback proporcional ao estado real: só para migration **confirmada**; recusa se dependentes posteriores existirem; documenta se reintroduz risco | `ROLLBACK_*.sql` | nunca automático. Lição S1: o rollback reintroduzia capacidades indevidas — dizer isso no arquivo |
| **V11** | Forma do arquivo: um único comentário de bloco no cabeçalho, sem `*/` interno; `begin;` … `commit;`; aspas/parênteses/`$tag$` balanceados | static | **Lição 5388:** `*/` no comentário derrubou a implantação (o arquivo inteiro é enviado) |
| **V12** | Checks de leitura: um SELECT por fase, palavras-chave de escrita só fora de literais, só contagens e nomes de papéis (nunca dados de usuário, segredos ou caminhos) | static | — |
| **V13** | Sem referência a projeto, URL, chave ou token em artefato versionado | static | — |
| **V14** | Testes de mutação do static check para os controles críticos (coluna proibida, grant indevido, md5 alterado, escopo aberto, trava ausente) | static (rodada A) | um controle que não falha com a mutação não conta |

**Lição 5393 (S3):** o canal do conector foi aceito excepcionalmente porque o texto foi enviado do `begin;` ao `commit;` sem alteração, mas a igualdade byte a byte **não foi provável** pelo próprio canal. Daqui em diante, usar o executor por arquivo (§3).

## 3. Executor por arquivo

Artefato: `scripts/v1-13/Invoke-ReviewedSql.ps1` (v1.4), executado por Fabrício no Windows. Verificação estática: `scripts/v1-13/static_check_executor.py`.

1. Lê um **manifesto** (`passo|arquivo|sha256|modo`), com `modo ∈ {gate, read, write}`.
   - `gate`: leitura somente leitura **avaliada**; PRE e POST são sempre `gate`.
   - `read`: só registrada.
   - Uma escrita sem gate antes é recusada.
2. Fora da simulação, exige `-ShaManifestoEsperado`, o sha256 do manifesto auditado e citado na autorização.
3. Calcula o SHA-256 de cada arquivo e compara com o manifesto antes de conectar, e de novo imediatamente antes de cada passo.
4. Confere o destino (`supabase/.temp/linked-project.json` = ref) e a versão fixada da CLI.
5. Exige a confirmação digitada `EXECUTAR <ref> <8 primeiros do sha256 do manifesto>` e cria uma trava por manifesto.
6. Executa `supabase db query --file <arquivo> --remote=<ref>`, com `--read-only` fora de `write`, enviando o **arquivo inteiro**, sem transcrição.
7. **Gate reprovado** em qualquer um destes casos:
   - um booleano de primeiro nível falso;
   - `barreira` ≠ CLOSED;
   - `identidades_teste` ≠ 0;
   - `executor` ≠ `-Papel`;
   - uma chave `*_md5` diferente da do gate anterior.
8. Para no primeiro erro ou gate reprovado (código de saída 2) e não repete.
9. Grava o registro **fora do repositório**: hashes, UTC, código de saída, avaliação dos gates, stdout/stderr brutos.

**Não faz:** guardar credenciais (a CLI usa o próprio login), usar `--debug`, abrir a barreira, ativar TEST, repetir passos ou escolher o rollback. O `-Simular` confere manifesto, hashes, destino e CLI (consulta só o registro npm) **sem conectar ao banco**.

## 4. Fluxo de rodadas

| Rodada | Conteúdo | Sai com |
|---|---|---|
| **A — Contrato + artefatos** | contrato, migration, rollback, PRE/POST, static check com testes de mutação, manifesto do executor, riscos, README do pacote | STOP para auditoria independente |
| **B — Execução autorizada** | após autorização explícita: executor por arquivo, PRE → migration → POST, STOP em divergência; com PASS, na mesma rodada: cópia canônica em `database/schema/`, evidências no README do pacote e linha no `log.md` | PASS (pronto para commit) ou STOP |
| **C — Fechamento** | auditoria das evidências, commit único, push (ou comando para o Windows) | publicado |

Rodadas extras **só** com defeito, risco material ou decisão pendente. Um STOP afeta só a parte bloqueada; o trabalho independente segue.

## 5. Documentação enxuta

| Documento | Atualizar quando |
|---|---|
| README do pacote | sempre: detalhe, riscos, evidências, decisões do pacote |
| `docs/log.md` | sempre: uma linha por rodada |
| `docs/05d`, `ROADMAP`, `INDEX` | só em **decisão aprovada, implantação confirmada ou marco**; `INDEX` também quando surge ou some um documento (CLAUDE.md) |
| Revision History dos documentos numerados | junto com a atualização acima, não por verificação estática |

Uma mudança de static check ou de critério de PRE fica no README do pacote e no `log.md`.

## 6. Homologação progressiva (sem ambiente isolado)

| Classe | Pode antecipar? | Como | Autorização |
|---|---|---|---|
| Estática | sim, sempre | static check + mutação (rodada A) | — |
| Implantação | sim, por pacote | PRE/POST (rodada B) | específica por pacote |
| Leitura com barreira CLOSED | sim | leitura somente leitura como `authenticated` com sub fictício, em transação revertida (precedente S3): só a recusa `CAPABILITY_NOT_ENABLED`/sem linhas | junto da rodada B |
| Funcional com identidades reais | **sim, por pacote**, logo após a implantação | modo **TEST** da barreira com identidades registradas (titular + EDITOR + VIEWER de teste), roteiro curto por pacote, dados de teste do próprio titular de teste, limpeza verificada | **específica para TEST** (identidades, janela, roteiro) |
| Segurança e privacidade | sim, no mesmo roteiro TEST | matriz de papéis do pacote, colunas proibidas, recusas neutras | idem |
| Concorrência | sim, no TEST | duas sessões reais nos cenários do pacote | idem |
| Desempenho | parcial | tempos das RPCs do pacote no TEST, com volume real do titular de teste; limite por pacote | idem |
| Aceite final | **não** | **E4**: homologação integrada de toda a V1-13 | marco obrigatório |

Regra: uma prova executada no TEST de um pacote **não** dispensa a E4; ela reduz o que a E4 precisa descobrir. Nada vira PASS sem execução registrada.

**Fila atual de provas que podem ser antecipadas com TEST**, decisão do proprietário:
- 5393: G3, G4 e G5;
- 5390: titular envia, troca e remove; o EDITOR é recusado pela API do Storage;
- E1: S8 concorrente, S10 e PR-04B;
- 5391: matriz de papéis e invalidação O1, após a implantação.

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-11-27).** Verificações V01–V14 com as lições da 5237, 5377, 5388, 5390 e 5393; executor por arquivo; rodadas A/B/C; documentação enxuta; homologação progressiva. |
| 1.1 | **Executor v1.1 (2026-11-27).** Modo `gate` com avaliação do resultado (corrige: PRE reprovado não impedia a migration na v1.0), sha256 auditado do manifesto obrigatório, versão da CLI, comparação de `*_md5` entre gates; verificação estática do executor. |
| 1.2 | **Executor v1.3 e V15 (2026-11-27).** `--read-only` da CLI roda como `supabase_read_only_user`: `gate` passa a rodar no papel da escrita, com conteúdo SELECT único conferido pelo executor antes de conectar; `\b` é backspace em regex do PostgreSQL (usar `\y`). |
| 1.3 | **Executor v1.4 (2026-11-27).** `gate` e `write` com `--yes` (a CLI com `-o json` recusa sem confirmação); inventário `escritores_*` como gate obrigatório contra expectativas auditadas (`-Expectativas` + `-ShaExpectativas`); `.Count` só sobre coleções (StrictMode); primeira implantação pelo executor: 5391, PASS. |
