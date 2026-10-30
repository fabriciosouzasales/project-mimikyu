# V1-12 — COLLECTION-SHARING-FOUNDATION-01 + SHARING CORRECTION + PUBLIC BINDER EXPERIENCE (proposta)

| Campo | Valor |
|---|---|
| Status | **EXECUTADA NO LIVE / CANÔNICA (2026-10-30, `V1-12 SCHEMA RECONCILIATION & VISUAL HANDOFF-01`).** 5300–5319 aplicadas (ledger `20261030142055` = 5319, aplicada primeiro; `20261030142130`…`20261030142655` = 5300–5318); texto do ledger ≡ arquivo desta pasta (md5 20/20); promovidas para `database/schema/` (só o bloco Status difere). Harness 5861 v1.3: GATE PASS 51/51, 99.1 PASS. Corpos de 5314 e 5317 substituídos depois por 5321/5322 (`../2026-10-30-v1-12-viewer-parity/`). Os harnesses e o `ROLLBACK_v1_12.sql` permanecem só aqui (não são schema; arquivos inalterados desde a execução). **V1-12 não publicado nem encerrado: homologação visual pendente.** |
| Data | 2026-10-30 |
| Autoridade | C-15, C-141–C-165 (`docs/domain-modeling/collections/concept-decisions.md`), escopo de lançamento V1-12 (ROADMAP 2.55) |
| Frontend | local, já escrito contra estes contratos; sem estas funções no banco, a interface degrada sem erro (painel mostra "indisponível", caixa de convites some, página compartilhada → 404) |

## O que entra

| Ordem | Arquivo | Objeto | Grants |
|---|---|---|---|
| 1 | 5300 | `collection_membership` (VIEWER; PENDING/ACTIVE/DECLINED) | RLS ligada, **nenhuma** política, nenhum privilégio de tabela |
| 2 | 5301 | `chk_collection_visibility` → `PRIVATE`/`PUBLIC` (default segue PRIVATE) | — |
| 3 | 5302 | `collection_share_role(uuid)` — OWNER / VIEWER / PUBLIC / NULL | interna (sem EXECUTE) |
| 4 | 5303 | `invite_collection_member(uuid, text)` | authenticated |
| 5 | 5304 | `respond_collection_invite(uuid, boolean)` | authenticated |
| 6 | 5305 | `remove_collection_member(uuid, uuid)` | authenticated |
| 7 | 5306 | `leave_shared_collection(uuid)` | authenticated |
| 8 | 5307 | `set_collection_visibility(uuid, text)` | authenticated |
| 9 | 5308 | `get_my_collection_sharing(uuid)` (painel do titular) | authenticated |
| 10 | 5309 | `get_my_collection_invites()` (caixa de convites) | authenticated |
| 11 | 5310 | `collection_completion_summary_shared(uuid)` | interna (sem EXECUTE) |
| 12 | 5311 | `get_collections_shared_with_me()` | authenticated |
| 13 | 5312 | `get_shared_collection(uuid)` (cabeçalho do participante, só OWNER/VIEWER) | authenticated |
| 14 | 5313 | `get_shared_collection_cards(uuid, int, int)` (galeria do participante, só OWNER/VIEWER) | authenticated |
| 15 | 5314 | `get_shared_collection_binder(uuid)` (cabeçalho do fichário, só OWNER/VIEWER) | authenticated |
| 16 | 5315 | `collection_binder_masked_pages(uuid, int, int)` — núcleo ÚNICO de bolsos mascarados | interna (sem EXECUTE) |
| 17 | 5316 | `get_shared_collection_binder_pages(uuid, int, int)` (porta do participante) | authenticated |
| 18 | 5317 | `get_public_collection_binder(uuid)` (vitrine: capa, identidade, grade) | **anon** + authenticated |
| 19 | 5318 | `get_public_collection_binder_pages(uuid, int, int)` (porta pública) | **anon** + authenticated |
| 20 | 5319 | `REVOKE TRUNCATE, REFERENCES, TRIGGER` de anon/authenticated nos 8 objetos que ainda os têm (independente) | — |
| — | 5861 | harness v1.3 (51 verificações + GATE; sentinela MS861, resíduo zero). v1.2 executada no LIVE em 2026-10-30: GATE FAIL 26/29 por defeito do harness (0.6/0.7 regex sobre parâmetro de entrada; 3.5 sem captura do `COLLECTION_NOT_FOUND` de `get_my_collection_binder`), 99.1 PASS; v1.3 corrige só o harness. **v1.3 executada no LIVE em 2026-10-30: GATE PASS 51/51, 99.1 PASS, resíduo zero confirmado** | — |

Todas as funções: `SECURITY DEFINER`, `SET search_path = ''`, objetos qualificados, autorização dentro da função. Nenhum contrato `get_my_*` existente é alterado ou aberto a terceiros.

## Visitante público — só a vitrine do fichário (PUBLIC BINDER EXPERIENCE)

Decisão do produto (2026-10-30): coleção **PUBLIC** oferece **apenas** a visualização do Fichário Digital, sem login, por `/fichario/[id]`. O visitante não lê galeria, progresso, acervo nem configurações — por isso 5312/5313 passaram a responder só a titular e participante, e anon perdeu EXECUTE nelas. A vitrine não é o contrato do VIEWER aberto para anon: tem portas próprias (5317/5318), autorizadas **só** por `visibility = 'PUBLIC'` e `lifecycle_status = 'ACTIVE'`, com projeção sanitizada. As duas portas de bolsos (5316 participante, 5318 público) chamam o **mesmo núcleo** 5315 — o mascaramento CARD/RESERVED/EMPTY é idêntico e não depende de quem pergunta. Despublicar ou arquivar revoga na próxima chamada; privada, arquivada e inexistente são indistinguíveis (NULL / `COLLECTION_NOT_FOUND`).

## Decisões operacionais (não normativas)

- **Convite por username exato** (`user_profile.username`, `^[a-z0-9_]{3,20}$`, `@` opcional). Sem busca parcial ou lista de usuários. `USER_NOT_FOUND` revela só o que `username_available()` (1030) já revela.
- **Caixa de convites dentro do app** (Minhas coleções), sem notificação externa (C-153).
- **Recusa fica registrada** (DECLINED) para o titular ver "recusou" e poder convidar de novo; remoção, cancelamento e saída **apagam** a linha (revogação imediata).
- **Arquivada:** não convida nem publica; remover participante e tornar privada continuam possíveis (fechar acesso nunca depende de reativar).
- **Limite:** 50 participações (PENDING+ACTIVE) por coleção, sob lock da coleção.
- **Progresso compartilhado:** cópia interna da matemática da 5188 com a fronteira trocada (5310). Dever de espelho registrado; a 5861 (3.7) prova igualdade para todas as coleções com referência.

## O que um VIEWER vê — e não vê

Vê: nome, descrição, tipo, Set, acabamento da capa, nome de exibição do titular, progresso, quantidade de cartas e a galeria das cartas **alocadas a esta coleção** (carta, número, versão, idioma, imagem, quantidade).

Nunca vê (C-157–C-161): acervo do titular, outras coleções, locais físicos, valores/aquisição, condição/certificação, favoritos, wishlist, ids de usuário/exemplar, username do titular (público).

**Fichário (SHARING CORRECTION):** o participante VIEWER abre o fichário da coleção em modo só leitura por dois contratos próprios (5314/5315) — os `get_my_*` do fichário continuam só do titular. Cada bolso chega em um de três estados: `CARD` (exemplar **alocado a esta coleção**, só com a face pública do catálogo), `RESERVED` (reserva **desta coleção** sem exemplar dela no bolso) ou `EMPTY` (todo o resto: vazio, carta de outra coleção do mesmo fichário, carta sem coleção, reserva alheia, mesclagem/imagem personalizada — indistinguíveis de propósito). Nunca saem ids (página, bolso, exemplar, alocação, posição), local físico, fixação, mesclagens, imagens do Storage privado, referências de espécie, nomes/quantidades de outras coleções, participantes ou cartas disponíveis. O visitante de coleção PUBLIC usa a vitrine (seção acima), com o mesmo núcleo de mascaramento.

## Aplicação (quando autorizada) — sequência definitiva (GATE-04)

Pré-requisitos: autorização expressa de Fabrício; frontend V1-12 **não** publicado ainda (sem as funções ele degrada sem erro, mas não deve ir antes do GATE); nenhuma migration paralela em andamento.

1. **Precheck canônico** (somente leitura) — conferido no LIVE em 2026-10-30 com os valores esperados:
   ```sql
   select to_regclass('public.collection_membership') as tabela,
          (select pg_get_constraintdef(oid) from pg_constraint where conname = 'chk_collection_visibility') as chk,
          (select count(*) from public.collection where visibility <> 'PRIVATE') as nao_privadas,
          (select md5(prosrc) from pg_proc where oid = 'public.collection_completion_summary(uuid)'::regprocedure) as md5_5188,
          (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in
             ('collection_share_role','invite_collection_member','get_shared_collection','get_shared_collection_binder',
              'collection_binder_masked_pages','get_public_collection_binder')) as ja_existem,
          (select count(*) from information_schema.role_table_grants where table_schema = 'public'
             and grantee in ('anon','authenticated') and privilege_type in ('TRUNCATE','REFERENCES','TRIGGER')) as excedentes;
   ```
   Esperado: `NULL` · `CHECK ((visibility = 'PRIVATE'::text))` · `0` · `27ccf51208b270822f01fe5188de06a1` · `0` · `42`. Qualquer divergência → **parar** (md5 diferente = reespelhar a 5310 antes).
2. **5319** sozinha (independente) → validação somente leitura no rodapé do arquivo (excedentes `0`, SELECT/UPDATE preservados).
3. **5300 → 5318**, uma migration por arquivo, nesta ordem: 5300 tabela · 5301 CHECK · 5302 papel · 5303–5309 convite/resposta/remoção/saída/visibilidade/painel/caixa · 5310 progresso · 5311–5314 leituras do participante · 5315 núcleo mascarado · 5316 porta do participante · 5317–5318 vitrine pública. Cada `apply_migration` é transacional: se uma falhar, nada dela fica aplicado.
4. **5861** (`select * from pg_temp.wh_5861_validate();`) — GATE exigido `51/51 PASS` com `99.1` (resíduo zero) PASS. É um único statement; a sentinela MS861 desfaz todas as fixtures.
5. **Security Advisor** — nenhum alerta novo atribuível a 5300–5319.
6. Só então: deploy do frontend (decisão de Fabrício), depois promoção para `database/schema/` e reconciliação de docs.

**Interrupção:**
- Falha no passo 1 → não aplicar nada; reportar o valor divergente.
- Falha em uma migration do passo 3 → parar na hora; a migration que falhou não deixou resíduo; decidir entre corrigir e reaplicar a partir dela ou executar `ROLLBACK_v1_12.sql` (desfaz 5300–5318, idempotente; não toca a 5319).
- GATE da 5861 diferente de `51/51` → não implantar o frontend; reportar os `check_id` em FAIL; corrigir e reexecutar a 5861 (não há estado a limpar) ou executar o rollback.
- Rollback só antes de uso real: aborta sozinho se houver coleção PUBLIC **ou qualquer linha em `collection_membership`** (ACTIVE, PENDING ou DECLINED, inclusive de teste) — nunca apaga participação. O contrato de revogação (5305/5306) apaga a linha; não há histórico de participações encerradas a preservar.

## Revisão de prontidão para o LIVE (2026-10-30, leitura do LIVE + inspeção)

Feita só com leitura no LIVE (`pg_policies`, grants, definições, `EXPLAIN`); **nenhum PASS de banco declarado** — a 5861 nunca rodou.

- **Isolamento entre usuários:** toda leitura/escrita nova passa por `collection_share_role()` (5302) ou por `owner_user_id = auth.uid()` dentro da função; a tabela nova não tem política nem privilégio para anon/authenticated. Nenhuma política RLS existente depende de `visibility` (conferido no LIVE: `collection`, `collection_allocation`, `physical_card`, `collection_layout*` são todas *select-own*) — publicar uma coleção **não** abre leitura direta de tabela.
- **Público × participante:** `PUBLIC` lê **só a vitrine do fichário** (5317/5318: capa, identidade, grade, bolsos mascarados). Cabeçalho, progresso, galeria, listas pessoais e escrita exigem sessão e participação ACTIVE.
- **Privilégios excedentes (GATE-04):** no LIVE, exatamente 42 grants TRUNCATE/REFERENCES/TRIGGER para anon/authenticated, em 8 objetos (`user_profile`, `storage_bucket`, `admin_action_log`, `reserved_username`, `admin_user` e as views `catalog_card_set_variant_coverage`, `catalog_card_set_image_coverage`, `catalog_card_set_metrics`); nenhum outro dos 117 objetos do schema. Sem dependência legítima (app não faz TRUNCATE, não cria FK nem trigger como esses papéis). Origem: default ACL de `supabase_admin`; o de `postgres` já é limpo. Correção: 5319 v2.0 (só D/x/t, só esses objetos; SELECT/UPDATE legítimos e políticas intactos); 5861 0.8 verifica.
- **Revogação:** remover/cancelar/sair apagam a linha; recusar grava DECLINED. Toda leitura reavalia a participação a cada chamada (sem cache de acesso no banco).
- **Outras coleções / dados privados:** galeria e fichário filtram por `collection_allocation.collection_id = p_collection_id`; projeções sem ids, local, valor, condição; 0.5/0.6/3.9/3.10 da 5861 provam por assinatura e por conteúdo.
- **Compatibilidade:** nenhum contrato existente muda. `create_*` usam o default da coluna (`PRIVATE`); `authenticated` só tem SELECT em `collection` (não há UPDATE direto de `visibility` fora da 5307). A cópia 5310 bate com a 5188 viva (`md5(prosrc)` igual).
- **Aplicação segura:** objetos novos; funções com `CREATE OR REPLACE` (reaplicáveis); a 5300 usa `CREATE TABLE` sem `IF NOT EXISTS` de propósito (falha alto se a tabela já existir — o precheck cobre); o único DDL sobre objeto existente é o CHECK da 5301 (validação de 10 linhas no LIVE hoje). Plano da 5315 conferido por `EXPLAIN` no LIVE: só buscas por índice (página → bolso → posição → exemplar → alocação).

## Roteiro manual de concorrência (K)

- K1 — duas abas do titular convidam o mesmo username ao mesmo tempo → uma linha só (UNIQUE + lock da coleção); a segunda resposta é `ALREADY_PENDING`.
- K2 — duas abas do convidado aceitam ao mesmo tempo → um `ACTIVE`, a outra `UNCHANGED`.
- K3 — titular remove o participante enquanto ele navega no fichário → a próxima leitura de página devolve `COLLECTION_NOT_FOUND` e a interface mostra "tentar de novo"; ao recarregar, 404.
