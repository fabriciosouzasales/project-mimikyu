/*
Project Mimikyu
Edge Function: import-card-assets
Sprint: B2.4.1 — Refatoração para Services (CONFIRMADO publicado via `npx supabase functions deploy import-card-assets` e testado com execução real)

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
  mudança de comportamento observável. A lógica de acesso a dados foi extraída
  para `services/database.ts` (`findImportRun`/`findCardSet`/`listCards`) e os
  tipos para `types.ts`. A partir desta versão, `index.ts` tem responsabilidade
  única de orquestrar o fluxo da função — não conhece SQL, PostgreSQL nem
  TCGdex diretamente, apenas coordena chamadas a serviços especializados
  (novo princípio de arquitetura, válido para todas as Edge Functions futuras
  do projeto, incluindo os serviços ainda não escritos `tcgdex.ts`/`storage.ts`/
  `image.ts`).

Ver docs/06-pipeline-importacao.md, seção "Roteiro de Implementação Incremental
— Bloco B", para o contexto completo, o roteiro de sprints e o status real de
cada etapa (o que foi de fato confirmado vs. o que ainda está planejado).

Convenções permanentes de Edge Functions do Project Mimikyu (ver docs/06):
1. Nunca criar arquivos de Edge Function "na mão" — sempre via
   `npx supabase functions new <nome-da-função>`.
2. Nunca alterar o template oficial da CLI sem necessidade — evoluir sobre ele.
3. Responsabilidade única por função.
4. Execução restrita por padrão (`auth: ["secret"]`) — infraestrutura interna,
   não interface pública.
5. Nunca avançar sem validar — cada sprint fecha só com critério de aceite
   confirmado.
6. `index.ts` apenas orquestra — não conhece SQL/PostgreSQL/fontes externas
   diretamente, apenas coordena chamadas aos serviços especializados.
*/

import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import {
  findImportRun,
  findCardSet,
  listCards,
} from "./services/database.ts";
import type { RequestBody } from "./types.ts";

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
            { success: false, error: "IMPORT_RUN_NOT_FOUND", run_code: runCode },
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

        const cards = await listCards(ctx.supabaseAdmin, run.card_set_id);

        return Response.json({
          success: true,
          function: "import-card-assets",
          version: "1.2.1",
          run,
          card_set: cardSet,
          card_count: cards.length,
          cards,
        });
      } catch (error) {
        const errorCode = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
        return Response.json(
          { success: false, error: errorCode },
          { status: 500 },
        );
      }
    },
  ),
};
