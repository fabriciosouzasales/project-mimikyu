/*
Project Mimikyu
Edge Function: import-card-assets
Sprint: B3.6 — Marco real: o HTTP 401 que bloqueava toda invocação desde o
Sprint B3.3 foi definitivamente eliminado, confirmado por teste real de
terminal. CONFIRMADO DEPLOYADO: `npx supabase functions deploy
import-card-assets` bem-sucedido, seguido de uma chamada real SEM nenhum
header de autenticação (agora desnecessário — ver abaixo) retornando HTTP 500
em vez do 401 histórico, prova de que a função finalmente executa. Ver
docs/06-pipeline-importacao.md, "Sprint B3.6", para o contexto completo.

Este arquivo é uma cópia versionada do código confirmado como publicado no
projeto Supabase, seguindo o mesmo princípio já usado em `database/` para SQL:
copiado para o repositório apenas depois de confirmado (ver `database/README.md`).

MUDANÇA ARQUITETURAL REAL, decidida e confirmada nesta revisão: a biblioteca
`@supabase/server` (`withSupabase`) foi abandonada para esta função — e,
esperado, para as futuras Edge Functions do projeto — depois de três revisões
consecutivas (Sprints B3.3/B3.4/B3.5) sem conseguir fazer `auth: ["secret"]`
autenticar com sucesso uma Secret Key real, mesmo após múltiplas hipóteses
reais testadas e descartadas (tipo/nome da chave, `verify_jwt`, header
`apikey`, remoção do próprio `auth: ["secret"]`). Substituída por
`Deno.serve()` puro + `@supabase/supabase-js`, com um cliente Supabase criado
uma única vez, no escopo do módulo, a partir de `SUPABASE_URL`/
`SUPABASE_SERVICE_ROLE_KEY` (variáveis de ambiente padrão de toda Edge
Function Supabase, não secrets customizados). Decisão explicitamente
concordada por Fabrício ("Concordo completamente... eu também abandonaria o
@supabase/server. A arquitetura ficará mais simples e muito mais previsível.").
A Convenção #4 (execução restrita via `auth: ["secret"]`), declarada na
revisão `0.9` de docs/06-pipeline-importacao.md, está SUPERSEDIDA por esta
mudança — ver nova Convenção #8 abaixo.

Consequência prática: validações que antes eram implícitas via `withSupabase`
(método HTTP, parsing de JSON, corpo obrigatório) agora são feitas manualmente
neste arquivo — sem alteração de comportamento observável para quem chama a
função.

Histórico:
- v1.0.0 (Sprint B2.1/B2.2, CONFIRMADO publicado e invocado com sucesso):
  respondia apenas `{ success: true, function: "import-card-assets", version: "1.0.0", status: "ready" }`.
- v1.1.0 (Sprint B2.3, CONFIRMADO publicado e testado): recebe `run_code` via
  payload JSON e consulta `asset_import_run`.
- v1.2.0 (Sprint B2.4, CONFIRMADO publicado e testado com execução real —
  `card_set` `ME0`/"Black Star Promos", `card_count: 0`): fluxo ampliado para
  `run_code` → `asset_import_run` → `card_set` → listagem de `card` (ordenada
  por `collector_order`). Toda a lógica vivia em um único arquivo.
- v1.2.1 (Sprint B2.4.1, CONFIRMADO publicado e testado — mesmo resultado do
  teste anterior, apenas com `version: "1.2.1"`): refatoração estrutural, sem
  mudança de comportamento observável. Lógica de acesso a dados extraída para
  `services/database.ts`.
- v1.3.0 (Sprint B3.3, CONFIRMADO DEPLOYADO — primeira vez que a função chama
  uma fonte externa real): fluxo passa a incluir `findCardSetExternalReference`
  e uma chamada real a `TcgdexClient.getSet()` (`services/tcgdex.ts`, também
  confirmado deployado nessa revisão pela primeira vez). Deploy confirmado,
  mas nenhuma invocação bem-sucedida — bloqueada por HTTP 401.
- v1.3.1 (Sprint B3.4/B3.5, aplicada e testada por Fabrício): removia
  `{ auth: ["secret"] }` de `withSupabase(...)`, mantendo a biblioteca. Testada
  de ponta a ponta no Sprint B3.5 — o 401 PERSISTIU, invalidando essa hipótese
  como correção suficiente. Nunca copiada a este arquivo no repositório.
- v2.0.0 (Sprint B3.6, CONFIRMADO DEPLOYADO, COM O 401 ELIMINADO POR TESTE
  REAL): remove completamente `@supabase/server`/`withSupabase`; cliente
  Supabase criado manualmente via `createClient(SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY)` no escopo do módulo; mesmo fluxo funcional das
  versões anteriores (`findImportRun`→`findCardSet`→
  `findCardSetExternalReference`→`TcgdexClient.getSet()`), agora com
  validação manual de método HTTP/corpo JSON/`run_code` (antes implícita via
  `withSupabase`). Teste real sem nenhum header de autenticação (correto
  agora — a autenticação é interna à função, via variável de ambiente)
  retornou HTTP 500 em vez de 401, confirmando que a função finalmente
  executa. Causa do 500 diagnosticada como GRANT ausente em
  `card_set_external_reference` para `service_role` (a tabela nunca recebeu
  `GRANT SELECT/INSERT/UPDATE/DELETE` explícito) — corrigida por uma nova
  migration real (ver `database/migrations/250_grant_card_set_external_reference_permissions.sql`)
  e reconfirmada por consulta real a `information_schema.role_table_grants`.
  **Nota importante**: uma resposta final `success: true` com `tcgdex_set`
  populado por uma chamada real de ponta a ponta ainda não foi explicitamente
  confirmada nesta revisão — todos os bloqueios conhecidos (401 e GRANT)
  foram eliminados, mas o próximo teste real ainda precisa confirmar o
  resultado final.

Ver docs/06-pipeline-importacao.md, seção "Sprint B3.6", para o contexto
completo, o roteiro de sprints e o status real de cada etapa (o que foi de
fato confirmado vs. o que ainda está planejado).

Convenções permanentes de Edge Functions do Project Mimikyu (ver docs/06):
1. Nunca criar arquivos de Edge Function "na mão" — sempre via
   `npx supabase functions new <nome-da-função>`.
2. Nunca alterar o template oficial da CLI sem necessidade — evoluir sobre ele.
3. Responsabilidade única por função.
4. [SUPERSEDIDA no Sprint B3.6] Execução restrita por padrão via
   `auth: ["secret"]` (`@supabase/server`) — substituída pela Convenção #8
   abaixo, depois de três revisões reais sem sucesso em autenticar com essa
   biblioteca.
5. Nunca avançar sem validar — cada sprint fecha só com critério de aceite
   confirmado.
6. `index.ts` apenas orquestra — não conhece SQL/PostgreSQL/fontes externas
   diretamente, apenas coordena chamadas aos serviços especializados.
7. Fluxo padrão de validação antes de cada deploy: `deno cache index.ts` +
   `deno check index.ts`, executados de dentro da pasta da função (onde está
   o `deno.json`), depois `npx supabase functions deploy <nome-da-função>`
   executado na raiz do projeto (onde está o `config.toml`).
8. [NOVA, Sprint B3.6] Toda Edge Function cria seu próprio cliente Supabase
   manualmente, via `createClient(Deno.env.get("SUPABASE_URL")!,
   Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)`, uma única vez, no escopo do
   módulo — não usa `withSupabase`/`@supabase/server`. Validações de método
   HTTP, corpo e payload passam a ser responsabilidade explícita do próprio
   `index.ts`.
*/

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import {
  findImportRun,
  findCardSet,
  findCardSetExternalReference,
} from "./services/database.ts";
import { TcgdexClient } from "./services/tcgdex.ts";

type RequestBody = {
  run_code?: string;
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json(
      {
        success: false,
        error: "METHOD_NOT_ALLOWED",
      },
      {
        status: 405,
        headers: {
          Allow: "POST",
        },
      },
    );
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return Response.json(
      {
        success: false,
        error: "INVALID_JSON",
      },
      { status: 400 },
    );
  }

  const runCode = body.run_code?.trim();

  if (!runCode) {
    return Response.json(
      {
        success: false,
        error: "RUN_CODE_REQUIRED",
      },
      { status: 400 },
    );
  }

  try {
    const run = await findImportRun(
      supabase,
      runCode,
    );

    if (!run) {
      return Response.json(
        {
          success: false,
          error: "IMPORT_RUN_NOT_FOUND",
        },
        { status: 404 },
      );
    }

    const cardSet = await findCardSet(
      supabase,
      run.card_set_id,
    );

    if (!cardSet) {
      return Response.json(
        {
          success: false,
          error: "CARD_SET_NOT_FOUND",
        },
        { status: 404 },
      );
    }

    const externalReference =
      await findCardSetExternalReference(
        supabase,
        run.card_set_id,
        run.asset_source_id,
      );

    if (!externalReference) {
      return Response.json(
        {
          success: false,
          error: "CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND",
        },
        { status: 404 },
      );
    }

    const tcgdex = new TcgdexClient("en");
    const set = await tcgdex.getSet(
      externalReference.external_set_id,
    );

    return Response.json({
      success: true,
      version: "2.0.0",
      run,
      card_set: cardSet,
      external_reference: externalReference,
      tcgdex_set: set,
    });
  } catch (error) {
    console.error(error);
    return Response.json(
      {
        success: false,
        error:
          error instanceof Error
            ? error.message
            : "UNEXPECTED_ERROR",
      },
      { status: 500 },
    );
  }
});
