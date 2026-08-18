# ADR-031 — Orquestração Programada de Pricing

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-031 |
| **Título** | Orquestração Programada de Pricing |
| **Status** | Aprovado |
| **Revisão** | 1.1 |
| **Data** | 2026-08-18 |
| **Decisores** | Project Mimikyu |
| **Decisão** | Arquitetura-alvo aprovada para o Incremento P13 — **Supabase Cron (`pg_cron`) + `pg_net` + Edge Function dedicada + Supabase Vault**, decoupled de qualquer visualização de preço (que nunca sincroniza). Autenticação serviço-a-serviço por secret key dedicada, guardada no Vault, nunca a publishable key. Validação decidida para a Edge Function: verificação manual do header `apikey` em tempo constante contra a secret key — não o pacote `@supabase/server` (`auth: 'secret:<nome>'`), por este estar em Public Beta sem versão fixável confirmada; mesma garantia de segurança, sem dependência externa nova. **P13.1 (esta rodada, CONFIRMADO EXECUTADO)**: fundação de schema — `FX_REFRESH` adicionado ao domínio de `run_type` sem reaproveitar `PRICE_REFRESH`; identidade cambial explícita via `pricing_sync_run.fx_source_code` (nunca `pricing_source_id` para BCB/PTAX, que não é e não deve ser uma linha de `pricing_source`); `confirmed_by` passa a ser opcional (`NULL` obrigatório em `SCHEDULED`, admin real obrigatório em `MANUAL` — nenhum administrador sintético criado); aquisição atômica de execução via dois índices únicos parciais (preço por `pricing_source_id`+`run_type`, cambial por `fx_source_code`+`run_type`), nunca advisory lock. Nenhuma extensão habilitada, nenhum Vault secret criado, nenhuma Edge Function implantada, nenhuma chamada externa, nenhum código JustTCG — tudo isso permanece para incrementos futuros (P13.2+). |
| **Documentos Relacionados** | `ADR-029-pricing-domain-model.md`, `ADR-021-administrative-role-model.md`, `../05f-pricing.md`, `../standards/STD-001-database-standards.md` |

**Nota de numeração**: `ADR-030` já está em uso (Card Search Projection, `ADR-INDEX.md`) — este documento recebe o próximo número livre real, `ADR-031`, confirmado por introspecção do índice antes da criação (divergência sinalizada em chat, não aplicada em silêncio).

---

# Context

O Incremento P12 encerrou a exibição de preços no frontend (`ADR-029`, revisão `1.23`) com a arquitetura de sincronização e a de consulta permanecendo desacopladas por desenho: a visualização lê exclusivamente `pricing_observation` já sincronizada, nunca chama fonte externa. A sincronização de PTAX (`scripts/sync-ptax-fx-rate.ts`) e da JustTCG (`scripts/sync-justtcg-pricing.ts`) permanecia inteiramente manual — acionada localmente por Fabrício, sem nenhum mecanismo de agendamento server-side.

Discovery prévio (mesma data) confirmou por introspecção direta do runtime Supabase (`qjfutqujxrbzgrtkpgkg`): `pg_cron`/`pg_net` disponíveis mas não instalados; `supabase_vault` já habilitado; timezone do banco `UTC`; nenhuma infraestrutura de agendamento pré-existente (sem `.github/workflows`, sem Vercel Cron, sem `cron.job`); quatro Edge Functions existentes, todas com `verify_jwt = true`, nenhuma agendada; `pricing_sync_run.pricing_source_id NOT NULL` e `confirmed_by NOT NULL` — ambos incompatíveis, sem alteração, com uma execução `SCHEDULED` de PTAX (que não tem `pricing_source` nem administrador confirmando manualmente).

Fabrício aprovou explicitamente a direção arquitetural (`pg_cron`+`pg_net`+Edge Function dedicada+Vault) e um conjunto detalhado de decisões de modelagem, concorrência e auditoria, pedindo a implementação da fundação de schema (P13.1) nesta rodada — sem habilitar as extensões, sem criar Vault secret, sem Edge Function, sem chamada externa, sem tocar no script PTAX, sem nenhum código JustTCG.

---

# Decision

## Arquitetura-alvo para P13 (P13.2 em diante, não implementada nesta rodada)

**Supabase Cron (`pg_cron`) → `pg_net` (assíncrono, fire-and-forget) → Edge Function dedicada de PTAX → Supabase Vault** para as credenciais. `pg_net.http_post` enfileira a chamada e retorna quase imediatamente — o tempo de execução real da Edge Function nunca conta contra o limite operacional do próprio Job do Cron, o que resolve por arquitetura o requisito de "duração total inferior ao limite operacional do Cron". `cron.job_run_details` nunca substitui auditoria funcional persistente — só `pricing_sync_run`/`pricing_sync_run_call` são fonte de verdade sobre sucesso/falha real da sincronização.

## Autenticação serviço-a-serviço: secret key dedicada, nunca publishable

A Edge Function roda com `verify_jwt = false` (obrigatório — chaves no novo formato `sb_secret_...`/`sb_publishable_...` não são JWT) e valida, no próprio handler, uma secret key dedicada enviada no header `apikey` (nunca `Authorization: Bearer`, reservado a JWT real). A secret key fica exclusivamente no Vault (`vault.create_secret`), nunca em código, log ou variável de ambiente commitada. A publishable key nunca é aceita como autorização suficiente — carrega o mesmo privilégio baixo do antigo `anon`.

**Decisão de implementação**: validação manual do header `apikey` em tempo constante contra o valor decifrado do Vault, dentro do handler da Edge Function — não o pacote `@supabase/server` (padrão `auth: 'secret:<nome>'`, oficialmente documentado pelo Supabase). Mesma garantia de segurança; motivo da escolha: `@supabase/server` está em Public Beta sem versão estável fixável confirmada (sandbox sem acesso a `registry.npmjs.org` para checar), e este projeto já pratica disciplina de não introduzir dependência externa nova quando o equivalente em poucas linhas de código é auditável e não introduz risco de breaking change de um pacote ainda instável.

## Separação total entre frontend e sincronização, preservada

Nenhuma alteração desta rodada, nem da arquitetura-alvo, muda o desenho já validado no P12: visualização de preço lê só `pricing_observation`/`get_cards_pricing_summary`, nunca aciona sincronização. A Edge Function de PTAX é acionada exclusivamente pelo Cron (`SCHEDULED`) — nunca por uma rota de frontend.

## Identidade explícita de fonte cambial — `fx_source_code`, nunca `pricing_source_id` isolado

BCB/PTAX não é e não deve virar uma linha de `pricing_source` — essa tabela foi desenhada para provedores de dado de preço de carta (`default_market_scope`, `requires_commercial_agreement`, `documentation_url`, etc.), colunas que não fazem sentido para uma autoridade cambial pública nacional. `pricing_sync_run` ganha `fx_source_code TEXT`, alinhado ao mesmo domínio já usado por `pricing_fx_rate.rate_source_code` (valor real em produção: `'BCB_PTAX'`) — não uma `FK`, pelo mesmo motivo que `rate_source_code` também não é `FK`: não existe (nem deve existir) uma tabela de fontes cambiais própria neste incremento.

Regra correlacionada, aplicada como `CHECK` (`ck_pricing_sync_run_source_identity`): execuções `FX_REFRESH` têm `pricing_source_id IS NULL` e `fx_source_code IS NOT NULL`; qualquer outro `run_type` tem `pricing_source_id IS NOT NULL` e `fx_source_code IS NULL`. Nenhum estado ambíguo ou duplamente identificado é representável.

## `run_type` estendido — `FX_REFRESH`, nunca reutilizando `PRICE_REFRESH`

`PRICE_REFRESH` já tem semântica própria e consolidada (atualização de preço de carta via fonte de `pricing_source`, ex. JustTCG). Reutilizá-lo para PTAX colidiria duas semânticas distintas no mesmo valor. `ck_pricing_sync_run_type` estendido para `SET_DISCOVERY`/`CARD_SYNC`/`PRICE_REFRESH`/`FX_REFRESH`.

## `confirmed_by` opcional — `SCHEDULED` sem administrador, `MANUAL` sempre com administrador real

`admin_user` não ganha nenhuma linha sintética/de sistema — decisão explícita, alinhada a `ADR-021` (papel administrativo é sempre uma pessoa real vinculada a `auth.users`). Em vez disso, `pricing_sync_run.confirmed_by` passa a aceitar `NULL`, e uma nova regra correlacionada (`ck_pricing_sync_run_confirmed_by_by_trigger`) exige: `triggered_by = 'MANUAL' ⟹ confirmed_by IS NOT NULL`; `triggered_by = 'SCHEDULED' ⟹ confirmed_by IS NULL`. A função `validate_pricing_sync_run_confirmed_by()` (`SECURITY DEFINER`, `search_path=''`, já existente desde a correção pós-P8) passa a só consultar `admin_user` quando `NEW.confirmed_by IS NOT NULL` — quando `NULL` (sempre o caso em `SCHEDULED`, garantido pelo `CHECK` acima), a validação é dispensada por não haver o que validar. Nenhum `REVOKE`/`GRANT` da função foi alterado; `CREATE OR REPLACE` preserva o `EXECUTE` já revogado de todos os papéis.

## Concorrência: aquisição atômica por índice único parcial, nunca advisory lock

Dois índices únicos parciais, um por identidade de fonte, cobrindo os mesmos estados já considerados "ativos" pelo índice pré-existente (`ix_pricing_sync_run_active`: `RECEIVED`/`PROCESSING`):

- `ux_pricing_sync_run_active_price_per_source_type` — `(pricing_source_id, run_type) WHERE status IN ('RECEIVED','PROCESSING') AND pricing_source_id IS NOT NULL`;
- `ux_pricing_sync_run_active_fx_per_source_type` — `(fx_source_code, run_type) WHERE status IN ('RECEIVED','PROCESSING') AND fx_source_code IS NOT NULL`.

Cada índice filtra pela própria coluna `IS NOT NULL`, então nunca indexa `NULL` — diferente de `pricing_observation`/Query `3070`, `NULLS NOT DISTINCT` não é necessário aqui: não há ambiguidade de múltiplos `NULL` dentro de um índice que já exclui `NULL` por predicado. A garantia vem inteiramente do índice, válida mesmo sob PgBouncer transaction pooling — nenhuma dependência de advisory lock de conexão poolada. Estado terminal (`COMPLETED`/`COMPLETED_WITH_ERRORS`/`FAILED`/`CANCELLED`) libera automaticamente o slot para nova execução, por não satisfazer mais o predicado `WHERE`.

## JustTCG permanece inteiramente fora do P13

Nenhuma criação ou agendamento de job JustTCG nesta ADR nem no Incremento P13. `pricing_source.is_active` continua `FALSE`. A fundação de orquestração validada com PTAX (Cron/`pg_net`/Edge Function/Vault) poderá ser reaproveitada por um incremento futuro, condicionado à contratação comercial — sem nenhum código ou schema específico da JustTCG criado neste ADR.

---

# Consequences

## Benefícios

- BCB/PTAX ganha identidade própria (`fx_source_code`) sem forçar uma tabela de fontes de preço de carta a representar uma autoridade cambial nacional — nenhuma coluna de `pricing_source` é distorcida ou deixada semanticamente vazia para acomodar o caso;
- execuções agendadas (`SCHEDULED`) não exigem nenhum administrador sintético nem enfraquecem a garantia já existente de que toda execução `MANUAL` tem um administrador real por trás — a regra correlacionada torna os dois casos mutuamente exclusivos e sempre corretos por construção;
- duas execuções ativas conflitantes (mesma fonte, mesmo tipo) tornam-se estruturalmente impossíveis, garantidas pelo próprio banco, não por lógica de aplicação nem por lock de conexão que poderia não sobreviver a um pooler;
- nenhuma alteração de comportamento, grant ou RLS para os fluxos já em produção (JustTCG `CARD_SYNC`/`MANUAL`) — validado por reprodução exata do formato de insert do conector real, dentro da mesma bateria de testes transacionais;
- a arquitetura-alvo aprovada (Cron/`pg_net`/Edge Function/Vault) resolve por desenho o requisito de duração/resiliência, sem depender de nenhum ajuste fino de timeout.

## Restrições / Pendências

- nenhuma extensão (`pg_cron`/`pg_net`) foi habilitada nesta rodada — P13.2 depende dessa habilitação antes de qualquer agendamento real;
- nenhum Vault secret foi criado — a secret key dedicada de serviço-a-serviço só existe como decisão de desenho, não como credencial real;
- nenhuma Edge Function foi implantada — a decisão de validação manual de `apikey` em tempo constante ainda não tem implementação; fica para P13.3;
- `scripts/sync-ptax-fx-rate.ts` permanece intocado — a extração do módulo compartilhado de busca/normalização/persistência PTAX (para script e Edge Function serem meros adaptadores) fica para P13.2;
- o mecanismo de não sobrescrever automaticamente uma taxa histórica divergente (registrar para análise, nunca substituir silenciosamente) ainda não tem desenho de implementação definido — pendente de P13.2;
- o nome definitivo da Edge Function, do Job de Cron e o tamanho exato de retry/backoff seguem em aberto, decisão de implementação de P13.3;
- JustTCG segue sem nenhuma preparação de agendamento — por decisão explícita, nada além do registro textual desta ADR é feito até contratação comercial.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação deste documento (2026-08-18) — formaliza a arquitetura-alvo de P13 (Supabase Cron + `pg_net` + Edge Function dedicada + Vault) e a fundação de schema do Incremento P13.1: `FX_REFRESH` em `pricing_sync_run.run_type`, `fx_source_code` como identidade cambial explícita, `confirmed_by` opcional com regra correlacionada a `triggered_by`, e dois índices únicos parciais para aquisição atômica de execução (Migrations `3905`/`3906`/`3907`, `CONFIRMADO EXECUTADO`). Numerado `ADR-031` (não `ADR-030`, já em uso por Card Search Projection) após confirmação por introspecção do `ADR-INDEX.md`. |
| 1.1 | **Auditoria final do P13.1 (2026-08-18, mesmo dia) — dois achados reais, ambos corrigidos.** (1) `fx_source_code` não exigia o formato normalizado já usado por `pricing_source.code`/`pricing_fx_rate.rate_source_code` (maiúsculas, `^[A-Z][A-Z0-9_]*$`) — `3905` não foi editada; `3908` (`CONFIRMADO EXECUTADO`) adiciona `ck_pricing_sync_run_fx_source_code_format`, mesmo padrão das duas colunas irmãs, validado com oito cenários transacionais (`ROLLBACK`) antes da aplicação. (2) `3905`–`3907`, embora `CONFIRMADO EXECUTADO` no Supabase, estavam ausentes de `database/migrations/` — quebra da convenção vigente desde a Query `3700`; os quatro arquivos (`3905`–`3908`) foram versionados retroativamente neste ciclo, SQL idêntico ao efetivamente aplicado. `get_advisors` sem achado novo em ambos os pontos. Nenhuma mudança na arquitetura-alvo (seção "Arquitetura-alvo para P13") nem no status do ADR. |
