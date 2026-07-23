/*
Project Mimikyu
Edge Function: import-card-assets
Sprint: B2.3 — Integração com Banco (CONFIRMADO publicado via `npx supabase functions deploy import-card-assets`)

Este arquivo é uma cópia versionada do código confirmado como publicado no
projeto Supabase, seguindo o mesmo princípio já usado em `database/` para SQL:
copiado para o repositório apenas depois de confirmado (ver `database/README.md`).

Histórico:
- v1.0.0 (Sprint B2.1/B2.2, CONFIRMADO publicado e invocado com sucesso):
  respondia apenas `{ success: true, function: "import-card-assets", version: "1.0.0", status: "ready" }`.
- v1.1.0 (Sprint B2.3, CONFIRMADO publicado; teste com execução real ainda
  pendente): recebe `run_code` via payload JSON e consulta `asset_import_run`.

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

      const { data: run, error } = await ctx.supabaseAdmin
        .from("asset_import_run")
        .select("*")
        .eq("run_code", runCode)
        .maybeSingle();

      if (error) {
        console.error("Failed to read asset_import_run:", error);
        return Response.json(
          { success: false, error: "DATABASE_QUERY_FAILED" },
          { status: 500 },
        );
      }

      if (!run) {
        return Response.json(
          { success: false, error: "IMPORT_RUN_NOT_FOUND", run_code: runCode },
          { status: 404 },
        );
      }

      return Response.json({
        success: true,
        function: "import-card-assets",
        version: "1.1.0",
        run,
      });
    },
  ),
};
