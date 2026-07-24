/*
Project Mimikyu
Edge Function: import-card-assets
Sprint: B2.4 — Descoberta das Cartas (CONFIRMADO publicado via `npx supabase functions deploy import-card-assets` e testado com execução real)

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
  por `collector_order`).

Pendência real, registrada por transparência: uma refatoração em módulos
(`services/database.ts` + `types.ts`) foi proposta e aprovada no Sprint B2.4,
e um código v1.2.1 já foi escrito no Sprint B2.4.1 — mas o deploy dessa versão
ainda não foi confirmado. Este arquivo permanece na v1.2.0 (última versão com
deploy e teste real confirmados) até essa confirmação chegar.

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
*/

import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

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

      const { data: run, error: runError } = await ctx.supabaseAdmin
        .from("asset_import_run")
        .select("*")
        .eq("run_code", runCode)
        .maybeSingle();

      if (runError) {
        console.error("Failed to read asset_import_run:", runError);
        return Response.json(
          { success: false, error: "IMPORT_RUN_QUERY_FAILED" },
          { status: 500 },
        );
      }

      if (!run) {
        return Response.json(
          { success: false, error: "IMPORT_RUN_NOT_FOUND", run_code: runCode },
          { status: 404 },
        );
      }

      const { data: cardSet, error: cardSetError } = await ctx.supabaseAdmin
        .from("card_set")
        .select(`
          id, expansion_id, code, name, set_type,
          release_order, release_date, base_set_size, total_set_size
        `)
        .eq("id", run.card_set_id)
        .maybeSingle();

      if (cardSetError) {
        console.error("Failed to read card_set:", cardSetError);
        return Response.json(
          { success: false, error: "CARD_SET_QUERY_FAILED" },
          { status: 500 },
        );
      }

      if (!cardSet) {
        return Response.json(
          { success: false, error: "CARD_SET_NOT_FOUND", card_set_id: run.card_set_id },
          { status: 404 },
        );
      }

      const { data: cards, error: cardsError } = await ctx.supabaseAdmin
        .from("card")
        .select(`
          id, card_set_id, rarity_id, category_id,
          collector_number, collector_total, collector_order, name
        `)
        .eq("card_set_id", run.card_set_id)
        .order("collector_order", { ascending: true });

      if (cardsError) {
        console.error("Failed to read cards:", cardsError);
        return Response.json(
          { success: false, error: "CARDS_QUERY_FAILED" },
          { status: 500 },
        );
      }

      return Response.json({
        success: true,
        function: "import-card-assets",
        version: "1.2.0",
        run,
        card_set: cardSet,
        card_count: cards.length,
        cards,
      });
    },
  ),
};
