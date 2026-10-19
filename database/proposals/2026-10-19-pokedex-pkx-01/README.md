# Proposta — Pokédex PKX-01: criação, gerações e grade (`5201`–`5205`)

| Campo | Valor |
|---|---|
| **Status** | **EXECUTADA / CANÔNICA.** `5201`–`5205` CONFIRMADO EXECUTADO no LIVE (2026-10-19, `PKX-01 LIVE EXECUTION GATE-01`); `5844` v1.0 **GATE PASS 37/37**, resíduo zero. Promovidas para `database/schema/`. Esta pasta fica como evidência histórica (o `5844` não é promovido). Ver "Execução no LIVE". |
| **Origem** | `POKEDEX-PKX-01-IMPLEMENTATION-01` (2026-10-19), após `POKEDEX-FOUNDATION-READINESS-01` e `PKX-01-CORREÇÃO-DE-PREMISSAS` (aprovada). |
| **Versões** | `5201`–`5205` v1.0 · `5844` v1.0 |

## Decisões que estes contratos materializam (não reabrir)

- Universo: Pokédex Nacional. Formas, idiomas, edições e acabamentos não criam posições.
- Gerações escolhidas livremente na criação; **todas as catalogadas marcadas por padrão** (a interface envia todas as linhas de `5201`).
- Inclusão/remoção posterior nos Ajustes (`5203`).
- Geração nova catalogada **aparece como opção**, mas **não entra sozinha** em coleção existente (C-02): o escopo é sempre uma lista explícita (`GENERATION_FILTERED`), nunca `FULL_REFERENCE`.
- Mudar gerações não exclui nem move cartas, alocações ou vínculos.
- Conquista = vínculo carta→posição (5102/5103, sem alteração). Uma carta física em no máximo uma coleção (C-04, sem alteração).
- Vinculação excepcional a outra espécie (aviso + confirmação) fica na **PKX-03**, reutilizando `6122`/`6124`.

## Arquivos

| Query | Arquivo | Natureza |
|---|---|---|
| `5201` | `5201_create_get_my_pokedex_generation_options_function.sql` | Leitura nova: gerações catalogadas (ativas, ≥ 1 posição na Pokédex Nacional); com coleção, seleção e conquistadas por geração. |
| `5202` | `5202_create_create_my_pokedex_collection_function.sql` | Criação idempotente (CT-01, irmã da `5167`): local padrão quando necessário, escopo explícito, escrita delegada à `5098`. |
| `5203` | `5203_create_set_my_pokedex_generations_function.sql` | Ajustes: substitui as gerações (lista explícita), idempotente, delegada à `5099`; devolve o progresso. |
| `5204` | `5204_create_get_my_pokedex_positions_function.sql` | Grade paginada no servidor: Todas/Tenho/Faltam, filtro por geração, ordem nacional, arte da espécie, representante, estados `OWNED`/`AVAILABLE`/`ELSEWHERE`/`NOT_FOUND`. |
| `5205` | `5205_revoke_direct_pokedex_scope_contracts.sql` | Revoga `EXECUTE` de `authenticated` (e reafirma PUBLIC/anon) em `5098`/`5099`. Fecha o caminho direto para `FULL_REFERENCE`. |
| `5844` | `5844_validate_pokedex_pkx_01.sql` | Harness: 37 verificações + GATE; fixture sintética (cartas e uma geração nova) desfeita pela sentinela `MS844`; resíduo zero. |

Nenhuma tabela, coluna, índice, trigger ou RLS é alterado. `5098`/`5099`, `5102`/`5103`, `6119`/`6122`/`6124`/`6125`, `5046`/`5047` e `collection_creation_request` são reutilizados sem mudança de corpo.

## Segurança (`5205`)

- **Consumidores de `5098`/`5099` verificados** (repositório e LIVE, 2026-10-19):
  - nenhuma chamada em `web/` nem em `supabase/functions/`;
  - nenhuma função SQL além das próprias;
  - 0 coleções Pokédex no LIVE.
- **Novas portas (`5202`/`5203`):** são `SECURITY DEFINER` do dono `postgres`, que mantém `EXECUTE` implícito. Provado pela `5844` (0.3 e seções 3/5).
- **Sem caminho alternativo:** `authenticated`/`anon` não têm `INSERT`/`UPDATE`/`DELETE` em `collection`, `collection_reference`, `collection_pokedex_reference`, `collection_pokedex_scope_generation` e `collection_creation_request` (`5844` 0.4).
- **Testes negativos:** `authenticated` chamando `5098` (com `FULL_REFERENCE`) e `5099` diretamente recebe `42501`, e nada é criado (`5844` 1.2).
- **Efeito colateral conhecido:** os harnesses históricos `5814`/`5815`/`5816`/`6830` (já executados e encerrados) chamavam `5098` como `authenticated`. Reexecutá-los exigiria chamar como dono. Não há reexecução planejada.

## Desempenho (pré-medição, só leitura no LIVE)

O corpo da `5204` foi executado como consulta equivalente, em transação `read only`, sem criar função:

- Base: Pokédex Nacional inteira (1.025 posições) e o acervo real (1.351 cópias), página de 120.
- **11,4 ms aquecido** (627 ms na primeira execução, a frio).
- A agregação do acervo é proporcional ao acervo do usuário (varredura por `inventory_id`). Com 20.000 cópias, estima-se < 100 ms. Medição definitiva depois da aplicação.

O corpo da `5201` também foi executado da mesma forma: 9 gerações, 151/100/135/107/156/72/88/96/120 posições (total 1.025).

## Plano mínimo de execução no LIVE (só com autorização)

1. **Pré-checagem (leitura):**
   - `to_regprocedure` de `5201`–`5204` = `null`, 0 sobrecargas;
   - `5098`/`5099` presentes, com `EXECUTE` para `authenticated` (estado anterior);
   - 0 coleções Pokédex; 0 transações > 1 min;
   - linha de base (coleções, alocações, cópias, locais, pedidos de criação, usuários).
2. **Aplicar, em ordem:** `5201` → `5202` → `5203` → `5204` → `5205`. Uma migration por arquivo, com a parte executável sem alteração. Registrar o ledger.
3. **Postcheck estrutural:** assinaturas, `SECURITY DEFINER`, `search_path ""`, ACLs (`5201`–`5204`: só `authenticated`; `5098`/`5099`: só `postgres`), corpos idênticos aos arquivos (md5 de `prosrc`).
4. **Rodar `5844` v1.0** (um statement).
5. **Conferência independente:** linha de base igual; 0 objetos sintéticos (`ZZPX%`, `ZZGEN%`, `ZZREG%`).
6. **Medição:** `5204` em transação `read only`, como o dono do acervo real, sobre uma coleção existente (sem criar coleção real).
7. **Security Advisor:** comparar com o estado anterior.
8. **Se PASS:** promover `5201`–`5205` para `database/schema/` e atualizar `05d`/`log`/`INDEX`/HANDOFF.

## Critérios

**PASS (todos):**
- `5844`: `GATE PASS 37/37` e `99.1` resíduo zero.
- Postcheck estrutural conforme o item 3.
- Conferência independente sem diferença.
- `5204` ≤ 300 ms aquecido na página de 120.
- Nenhum alerta novo específico no Security Advisor (o WARN genérico de `SECURITY DEFINER` para `authenticated` é esperado, por desenho).

**STOP (qualquer um):**
- Erro ao aplicar qualquer arquivo. Os seguintes não são aplicados; nada é retentado com alteração.
- `5844` com FAIL ou erro inesperado (`X.0`/`X.1`).
- Resíduo diferente de zero.
- ACL divergente.
- Corpo diferente do arquivo.
- Qualquer coleção real alterada.
- Alerta novo específico no Advisor.

Em STOP: registrar e aplicar a recuperação abaixo, sem corrigir no LIVE.

## Execução no LIVE (2026-10-19)

| Passo | Resultado |
|---|---|
| Pré-checagem | Conforme o item 1 do plano. |
| Ledger | `20261019012649` 5201 · `20261019012714` 5202 · `20261019012736` 5203 · `20261019012808` 5204 · `20261019012818` 5205 |
| Postcheck estrutural | PASS. 4 funções `SECURITY DEFINER`, `search_path=""`, dono `postgres`; 5201/5204 `STABLE`, 5202/5203 `VOLATILE`. ACL das novas: `postgres`, `authenticated`. ACL de 5098/5099: só `postgres`. md5 de `prosrc` igual ao arquivo nas 4. |
| `5844` v1.0 | **GATE PASS 37/37** (0.1–7.3 e 99.1), um statement, sem erro inesperado. Executado depois de Fabrício liberar `execute_sql` para este projeto (a primeira tentativa foi barrada pela política de permissões do agente, antes de chegar ao banco). |
| Conferência independente | Antes e depois do `5844`, linha de base igual à pré-checagem: 4 coleções, 210 alocações, 1.351 cópias, 1 local, 4 pedidos, 3 usuários, 0 vínculos, 9 gerações, 1.025 espécies/posições, 17.676 espécies principais, 0 coleções Pokédex, 0 usuários e 0 objetos sintéticos. |
| Promoção | `5201`–`5205` copiadas para `database/schema/` com o cabeçalho em CONFIRMADO EXECUTADO; parte executável idêntica à da proposta. |
| Desempenho (`5204`, equivalente, só leitura) | 1.025 posições, acervo real, página de 120: **14,1 ms aquecido** (593 ms a frio). Limite: 300 ms. |
| Security Advisor | Sem alerta novo específico. As 4 novas aparecem só no WARN genérico `authenticated_security_definer_function_executable` (esperado). 5098/5099 saíram dessa lista. Nenhuma em `anon_security_definer…` nem em `function_search_path_mutable`. |

Não há falha material: nenhuma recuperação é necessária ou foi aplicada.

## Recuperação

```sql
grant execute on function public.create_reference_based_pokedex_collection(uuid, text, text, uuid, uuid, text, uuid[]) to authenticated;  -- só se 5205 foi aplicada
grant execute on function public.set_collection_pokedex_scope(uuid, text, uuid[]) to authenticated;                                          -- só se 5205 foi aplicada
drop function if exists public.get_my_pokedex_positions(uuid, text, text, integer, integer);
drop function if exists public.set_my_pokedex_generations(uuid, text[]);
drop function if exists public.create_my_pokedex_collection(uuid, text, text[], uuid);
drop function if exists public.get_my_pokedex_generation_options(uuid);
```

Nenhum dado depende destas funções: há 0 coleções Pokédex antes da aplicação.
