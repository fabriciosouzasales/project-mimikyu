# Meu acervo — leitura de idiomas do cadastro (INVENTORY-LANGUAGE-READ-01)

| Campo | Valor |
|---|---|
| Data | 2026-10-17 |
| Status | **5164 APLICADA NO LIVE (2026-10-17, autorização exclusiva de Fabrício), ledger `20261017033443`.** Pós-check somente leitura PASS (§6). `5828` não executado (as mesmas provas foram feitas por consultas somente leitura). **Promovida para `database/schema/` em 2026-10-17** (corpo idêntico ao LIVE, conferido por md5 de `prosrc`). **CLOSED.** |
| Bloqueio resolvido | `MY-INVENTORY-ACTIONS-01`: as RPCs de cadastro (5150/5155, 5157, 5158) exigem `language_id`, mas `public.language` é admin-only (ADR-022). Sem esta leitura, "Adicionar cartas" e "Adicionar um Set inteiro" só funcionam para o administrador. |
| Contratos C-*/LDM-* | **Inalterados.** Nenhuma regra de domínio muda; a RLS de `public.language` continua como está. |

## 1. Artefatos

| Query | Objeto | Papel |
|---|---|---|
| 5164 | `get_registrable_languages()` | Idiomas **ativos**, na ordem editorial: `language_id`, `code`, `name`, `language_order`. Sem `native_name`, `is_active` nem timestamps. |
| 5828 | Harness (somente leitura) | Estrutura, `search_path`, ACL, anon (42501), sem `auth.uid()` (28000), usuário **não admin** recebe os idiomas ativos enquanto a leitura direta da tabela continua devolvendo 0 linhas. Gate 9/9. |

Ordem: 5164 → 5828 (`SELECT * FROM pg_temp.li_5828_validate('<UUID não admin>')`).

## 2. Por que esta é a menor solução

- **Mesmo padrão já aprovado** (5159–5163, `search_cards`/ADR-030): leitura `SECURITY DEFINER` estreita para o colecionador, em vez de abrir a tabela.
- **Não alterada:** RLS/policies de `public.language`, grants da tabela, RPCs de cadastro, Preview.
- **Sem `service_role`** na web.
- Dado de referência global (hoje 2 linhas), sem dono: não há isolamento entre usuários a provar além de "só autenticado".

## 3. Segurança

`SECURITY DEFINER`, `STABLE`, `search_path = ''`, objeto qualificado, `auth.uid()` obrigatório (28000), `EXECUTE` só para `authenticated` (revogado de PUBLIC e anon). Efeito esperado no Security Advisor: +1 em `0029 authenticated_security_definer_function_executable` (mesma classe das leituras 5159–5163, por desenho).

## 4. Frontend (já adaptado, local)

`web/lib/colecoes/acervo-queries.ts` → `getAddLanguages()` chama `get_registrable_languages` (não lê mais a tabela). Os dois fluxos (`acervo-add.tsx`) já consomem essa lista; nenhuma mudança visual. Até 5164 ser aplicada, a RPC não existe → lista vazia → as ações de adicionar ficam ocultas para todos, inclusive o administrador (comportamento seguro, sem ação que não funcione).

## 5. Verificação já feita (somente leitura)

- A consulta interna da função, executada no LIVE como leitura, devolve `pt-BR`, `en` (ativos, ordem 1, 2).
- Confirmado antes: usuário não admin lê 0 linhas de `public.language` (RLS).
- Nada foi aplicado; 5828 não foi executado (depende de 5164).

## 6. Execução no LIVE (2026-10-17)

- Antes: função ausente; último ledger `20261017024331`.
- Aplicação: `apply_migration` (transação da ferramenta; `BEGIN`/`COMMIT` do arquivo omitidos), uma vez, sem erro. Ledger `20261017033443 5164_create_get_registrable_languages_function`.
- Pós-check (somente leitura; trocas de papel em transação com ROLLBACK, nenhum objeto criado):
  - `SECURITY DEFINER`, `STABLE`, `search_path=""`, owner `postgres`, ACL exatamente `postgres=X, authenticated=X` (anon sem EXECUTE); retorno `TABLE(language_id uuid, code text, name text, language_order integer)`.
  - Corpo LIVE = arquivo (md5 `a8046bb747d39140d91b8667f7d12130`).
  - anon → `42501`; authenticated sem `auth.uid()` → `28000`.
  - Usuário real **não admin**: leitura direta de `public.language` = 0 linhas (RLS intacta); função = `pt-BR,en` (2 linhas, ordem editorial).
- Security Advisor: a função aparece só em `authenticated_security_definer_function_executable` (esperado, mesma classe de 5159–5163); nenhuma entrada em `anon_security_definer_function_executable`.
