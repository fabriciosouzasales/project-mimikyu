/*
Project Mimikyu
Edge Function: import-card-assets
Sprint: B3.3 — Deploy real confirmado da v1.3.0 (`npx supabase functions deploy import-card-assets`,
saída real "Deployed Functions on project ...: import-card-assets"). Invocação de ponta a
ponta (com resposta real da TCGdex) ainda NÃO confirmada nesta revisão — ver "Pendências"
abaixo e docs/06-pipeline-importacao.md, "Sprint B3.3", para o contexto completo.

Este arquivo é uma cópia versionada do código confirmado como publicado no
projeto Supabase, seguindo o mesmo princípio já usado em `database/` para SQL:
copiado para o repositório apenas depois de confirmado (ver `database/README.md`).

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
- v1.3.0 (Sprint B3.3, CONFIRMADO DEPLOYADO nesta revisão — primeira vez que a
  função chama uma fonte externa real): fluxo passa a incluir
  `findCardSetExternalReference` e uma chamada real a `TcgdexClient.getSet()`
  (novo `services/tcgdex.ts`, também confirmado deployado nesta revisão pela
  primeira vez). Resposta passa a incluir `external_reference`/`tcgdex_set`.
  **Nota importante**: o deploy foi confirmado com sucesso, mas nenhuma chamada
  real bem-sucedida (com resposta da TCGdex) foi confirmada ainda — as tentativas
  de invocação nesta revisão falharam por causas externas ao código da função
  (erro de sintaxe PowerShell, depois HTTP 401 por uso de uma API Key do tipo
  "Secret Keys" em vez do JWT `service_role`, exigido por `auth: ["secret"]`).
  Uma mudança para remover `auth: ["secret"]` durante a fase de desenvolvimento
  foi recomendada nesta revisão, mas AINDA NÃO aplicada neste arquivo.
  Também nesta versão, `RequestBody` passou a ser definido localmente em vez de
  importado de `./types.ts` — mudança não discutida explicitamente pela sessão
  pareada, registrada aqui por transparência (`types.ts` permanece no
  repositório, mas não é mais importado por este arquivo nesta versão).

Ver docs/06-pipeline-importacao.md, seção "Roteiro de Implementação Incremental
— Bloco B" e "Sprint B3.3", para o contexto completo, o roteiro de sprints e o
status real de cada etapa (o que foi de fato confirmado vs. o que ainda está
planejado).

Convenções permanentes de Edge Functions do Project Mimikyu (ver docs/06):
1. Nunca criar arquivos de Edge Function "na mão" — sempre via
   `npx supabase functions new <nome-da-função>`.
2. Nunca alterar o template oficial da CLI sem necessidade — evoluir sobre ele.
3. Responsabilidade única por função.
4. Execução restrita por padrão (`auth: ["secret"]`) — infraestrutura interna,
   não interface pública. (Remoção temporária durante desenvolvimento
   recomendada no Sprint B3.3, ainda não aplicada.)
5. Nunca avançar sem validar — cada sprint fecha só com critério de aceite
   confirmado.
6. `index.ts` apenas orquestra — não conhece SQL/PostgreSQL/fontes externas
   diretamente, apenas coordena chamadas aos serviços especializados.
7. Fluxo padrão de validação antes de cada deploy (Sprint B3.3): `deno check
   index.ts` executado de dentro da pasta da função (onde está o `deno.json`),
   depois `npx supabase functions deploy <nome-da-função>` executado na raiz
   do projeto (onde está o `config.toml`).
*/

import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import {
  findImportRun,
  findCardSet,
  findCardSetExternalReference,
} from "./services/database.ts";
import { TcgdexClient } from "./services/tcgdex.ts";

type RequestBody = {
  run_code?: string;
};

export default {
  fetch: withSupabase(
    { auth: ["secret"] },
    async (req, ctx) => {
      if (req.method !== "POST") {
        return Response.json(
          { success: false, error: "METHOD_NOT_ALLOWED" },
          { status: 405, headers: { Allow: "POST" } },
        );
      }

      let body: RequestBody;
      try {
        body = await req.json();
      } catch {
        return Response.json(
          { success: false, error: "INVALID_JSON" },
          { status: 400 },
        );
      }

      const runCode = body.run_code?.trim();

      if (!runCode) {
        return Response.json(
          { success: false, error: "RUN_CODE_REQUIRED" },
          { status: 400 },
        );
      }

      try {
        const run = await findImportRun(ctx.supabaseAdmin, runCode);

        if (!run) {
          return Response.json(
            { success: false, error: "IMPORT_RUN_NOT_FOUND" },
            { status: 404 },
          );
        }

        const cardSet = await findCardSet(ctx.supabaseAdmin, run.card_set_id);

        if (!cardSet) {
          return Response.json(
            { success: false, error: "CARD_SET_NOT_FOUND" },
            { status: 404 },
          );
        }

        const externalReference = await findCardSetExternalReference(
          ctx.supabaseAdmin,
          run.card_set_id,
          run.asset_source_id,
        );

        if (!externalReference) {
          return Response.json(
            { success: false, error: "CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND" },
            { status: 404 },
          );
        }

        const tcgdex = new TcgdexClient("en");
        const set = await tcgdex.getSet(externalReference.external_set_id);

        return Response.json({
          success: true,
          version: "1.3.0",
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
            error: error instanceof Error ? error.message : "UNEXPECTED_ERROR",
          },
          { status: 500 },
        );
      }
    },
  ),
};
