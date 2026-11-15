# V1-13 · E1-A — Papéis e permissões do EDITOR · proposta SQL (5366–5370)

| Campo | Valor |
|---|---|
| **Estado** | **E1-A: IMPLEMENTAÇÃO LOCAL PREPARADA / AUDITORIA ESTÁTICA PASS COM RESSALVAS / NÃO EXECUTADA. P1: NÃO AUTORIZADO PARA EXECUÇÃO.** Não aplicada nem homologada. Implementação local em `V1-13 / E1-A \| EDITOR ROLE FOUNDATION IMPLEMENTATION-01` (2026-11-14); migrations 5367–5370 em v1.1 (`VALIDATION STRATEGY CORRECTION-01`, 2026-11-15: paridade de ACL). Nada aplicado no LIVE, nenhum SQL executado, nenhum ambiente criado. Prova dinâmica (5888) **pendente**. |
| **Validação** | **Sem ambiente isolado** (C-244 revisada em 2026-11-15, `concept-decisions.md` revisões 1.37 e 1.38). Qualquer operação no banco existente só sob protocolo controlado e com autorização específica; a revisão não autoriza execução. Protocolo, mecanismo transacional, garantias demonstráveis × operacionais, locks, efeitos remanescentes e casos de recusa: `VALIDATION-STRATEGY-E1A.md` v1.3 (documentação 1.3.1). Auditoria independente estática: **PASS COM RESSALVAS** (R1 bloqueio de usuários durante o ensaio; R2 efeitos externos indiretos; R3 divergências documentais, corrigidas; R4 provas dinâmicas não executadas). **P1 não autorizado para execução**: exige S0 e autorização específica. S8 concorrente e S10 pendentes; PR-04B aberta. |
| **Contrato** | `docs/domain-modeling/collections/concept-decisions.md` C-234 a C-244, sobretudo C-234 e C-240; `docs/05d-colecoes-e-usuarios.md`, seção "Compartilhamento com EDITOR (V1-13)", entrega E1.1. |
| **Plano** | `V1-13 / E1 \| IMPLEMENTATION READINESS-01` (aprovado): incremento E1-A. |
| **Fora do escopo** | Qualquer escrita do EDITOR (E1-B), operações em massa (E1-C), histórico e leituras 5323/5324 (E1-D), interface. |

## Arquivos

| Arquivo | O que faz |
|---|---|
| `5366_widen_collection_membership_role_editor.sql` | `chk_collection_membership_role` passa de `('VIEWER')` para `('VIEWER','EDITOR')`. Padrão continua VIEWER; RLS sem política e sem privilégio de tabela. |
| `5367_create_collection_member_role_function.sql` | Nova `collection_member_role(uuid)` **interna** (sem EXECUTE para a API): papel real `OWNER`/`EDITOR`/`VIEWER`/NULL do usuário da sessão. |
| `5368_expose_member_role_in_sharing_reads.sql` | `CREATE OR REPLACE` de 5309, 5311 e 5312 com **uma linha a mais cada**: chave `role` (papel do próprio usuário). |
| `5369_replace_invite_collection_member_with_role.sql` | `DROP` de `invite_collection_member(uuid, text)` + `CREATE` de `invite_collection_member(uuid, text, text DEFAULT 'VIEWER')` na mesma transação. |
| `5370_create_set_collection_member_role_function.sql` | Nova `set_collection_member_role(uuid, uuid, text)`: troca direta VIEWER ↔ EDITOR, só titular, só participação ACTIVE, idempotente. |
| `5888_validate_editor_role_foundation_HARNESS.sql` | Prova dinâmica (54 verificações + GATE), executável **só** sob o protocolo controlado de `VALIDATION-STRATEGY-E1A.md` e com autorização específica; sem BEGIN/COMMIT próprios, não é comando pronto para produção. |
| `ROLLBACK_E1A.sql` | Reversão R5370 → R5366, com os corpos V1-12 restaurados byte a byte; bloqueada enquanto houver EDITOR. |
| `static_check_e1a.py` | Verificação estática (sem banco): 68 verificações sobre os arquivos, os canônicos, o frontend, a paridade de ACL e a 5861 v1.4. |
| `5861_validate_collection_sharing_v1.4.sql` | Correção mínima do harness da V1-12 para continuar válido depois da 5369 (assinatura nova do convite e chave `role`); mesmas 51 verificações. |
| `VALIDATION-STRATEGY-E1A.md` | Estratégia de validação sem ambiente isolado, v1.3 (documentação 1.3.1; protocolo P1 e artefato em `p1/`). |
| `p1/` | Ensaio P1 gerado (`P1_DRYRUN_E1A_rollback.sql`), S0/pós-estado só leitura, gerador, verificador independente e MANIFEST. **Nada executado; execução bloqueada** até a S0, a revisão independente e a autorização específica. |

Numeração conferida em 2026-11-14 contra `database/schema/` e `database/proposals/`: último número usado era `5365`; último harness, `5887`. `5323`/`5324` continuam reservados às leituras de Master Set e Pokédex (E1-D).

## Decisão de implementação: nível de leitura × papel real

O plano do `05d` previa que `collection_share_role` (5302) passasse a devolver EDITOR. A inspeção do planejamento mostrou que isso derrubaria o acesso do EDITOR: nove leituras (5312, 5313, 5314, 5316, 5320, 5321, 5326, 5328 e a política 5329) e as rotas `compartilhada/[id]` aceitam só OWNER/VIEWER. Por isso:

- **5302 não muda** e passa a ser lida como **nível de leitura**: todo membro ACTIVE, de qualquer papel, recebe `VIEWER`.
- **5367** é a fonte do **papel real**, usada para exibição (5368) e, na E1-B, para autorizar escrita.
- **5312**: `access` continua `OWNER`/`VIEWER`; `role` é a chave nova.

Resultado: as leituras e as rotas da V1-12 funcionam para o EDITOR sem alteração (verificação estática 9.2/9.3/10.3; prova dinâmica 3.2).

## Comportamento anterior × proposto

| Situação | V1-12 (hoje) | E1-A (proposto) |
|---|---|---|
| Convite sem papel (tela atual) | VIEWER | VIEWER (mesma chamada de 2 argumentos) |
| Convite com papel | — | `p_role` VIEWER ou EDITOR; outro valor → `INVALID_ROLE` |
| Convite pendente, mesmo papel | `ALREADY_PENDING` | `ALREADY_PENDING` |
| Convite pendente, outro papel | — | `INVITE_PENDING_ROLE_IMMUTABLE`, nada muda (cancelar e convidar de novo) |
| Recusado, novo convite com o mesmo papel | volta a PENDING, mesmo id | igual |
| Recusado, novo convite com outro papel | — | linha recusada apagada, convite **novo com id novo** (aba antiga não aceita papel que não viu) |
| Membro ativo convidado de novo | `ALREADY_MEMBER` | `ALREADY_MEMBER` (papel não muda por convite) |
| Troca de papel | — | `set_collection_member_role`: só titular, só ACTIVE; mesmo papel → `UNCHANGED` |
| Leitura de membro EDITOR | — | idêntica à do VIEWER |
| Retornos | sem papel (exceto painel do titular) | `role` em convite, caixa de convites, "Compartilhadas com você" e cabeçalho |
| Escrita do EDITOR | — | **nenhuma** (E1-B) |

Mudança interna sem efeito funcional: o convite passa a travar a linha de participação existente (`FOR UPDATE`) depois da trava da coleção — mesma ordem da troca de papel.

## Ordem de aplicação (quando autorizada)

`5366 → 5367 → 5368 → 5369 → 5370`, uma por vez, por **psql** (várias instruções entre `begin`/`commit`; o SQL Editor não garantiu transação única — protocolo da V1-16, §2 e §11). A 5368 vem antes do convite com papel para que o papel já apareça nas leituras quando o primeiro EDITOR puder existir. Cada etapa tem precheck (estado canônico ou `JÁ APLICADA`) e postcheck (corpo gravado = arquivo, ACL, `SECURITY DEFINER`, `search_path`).

**S0 obrigatória antes de qualquer etapa:** os md5 dos corpos vigentes de 5302, 5303, 5308, 5309, 5311 e 5312 foram **derivados dos arquivos canônicos**, não lidos no LIVE. Conferir no banco-alvo; qualquer divergência → STOP.

## Evidências

- **Estática (executada, sem banco):** `python3 -I static_check_e1a.py` → **68/68 PASS** em 2026-11-15 (61/61 na v1.0).
- **Dinâmica (pendente):** `5888` → esperado **54/54 PASS**. Nenhuma execução autorizada; protocolo proposto em `VALIDATION-STRATEGY-E1A.md` (ensaio transacional no LIVE antes da aplicação e aceite depois).

## Riscos e limites conhecidos

1. **Harness 5861 da V1-12** referencia `invite_collection_member(uuid, text)` e não conhece a chave `role`: depois da E1-A a v1.3 falha em 0.1 e 3.1. Corrigido pela `5861_validate_collection_sharing_v1.4.sql` (mesmas 51 verificações). `ROLLBACK_v1_12.sql` exige `ROLLBACK_E1A.sql` antes.
2. **PostgREST**: a 5369 elimina a sobrecarga antiga na mesma transação; o cache de esquema precisa recarregar (automático no Supabase). Verificar o convite pela tela atual na homologação.
3. **md5 derivados**: ver S0.
4. **Concorrência real** (troca de papel × escrita do EDITOR) só existe a partir da E1-B; provada em S8/S10 (E1-E).
5. **Interface**: a tela atual não oferece EDITOR nem troca de papel (E3). Até lá, um EDITOR só pode surgir por chamada direta do titular à API.
