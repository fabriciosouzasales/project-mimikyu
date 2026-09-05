/*
Project Mimikyu
Edge Function: revalidate-catalog-import-rows
Ciclo de cadastro self-service de Raridade (2026-08-07): recalcula
normalized_data/validation_status/match_status de linhas em staging
(catalog_import_row) usando o mesmo núcleo de normalização de
import-catalog-cards (_shared/catalog-normalization/), depois de um novo
mapeamento de raridade externa ser cadastrado (rarity_external_mapping,
Query 2096/2101/2103) ou de uma raridade já mapeada ser corrigida. Nunca
recalcula collector_total (propriedade do Set, não recalculável sem uma
nova chamada à TCGdex) — lê o valor já armazenado em normalized_data,
mesmo raciocínio documentado em resolveCatalogImportRow. Nunca cria
catalog_import_job novo.

Escopo ampliado (2026-08-07, mesmo dia do primeiro deploy — decisão de
Fabrício): além de jobs em STAGED, também revalida CONFIRMING e
COMPLETED_WITH_ERRORS. Motivo real: na prática (GYM1/SWSH1, mesma
sessão), um job raramente fica parado em STAGED esperando uma raridade
nova ser mapeada — o fluxo observado foi aprovar e confirmar tudo pela
tela de Revisão, inclusive linhas NEEDS_REVIEW, e só depois a confirmação
falhar (persistence_status FAILED, ex. violação de NOT NULL em
rarity_id) por raridade não mapeada. svc_apply_catalog_import_
revalidation() (Query 2106 v1.2) destrava essas linhas (FAILED ->
PENDING) quando a revalidação as torna VALID; esta função então chama
admin_confirm_catalog_import() (Query 2082, já existente) de novo — nunca
reimplementa a criação de Card aqui (Princípio da Fonte Canônica: só
admin_confirm_catalog_import()/internal.write_card() escrevem em
public.card).

Fronteira de identidade (Query 2106 v1.1, revisão de segurança de
2026-08-07): esta função exige um JWT de usuário real na requisição —
deployada com verify_jwt: true, então o runtime do Supabase recusa
qualquer requisição sem um JWT validamente assinado antes deste código
sequer rodar. Isso sozinho não basta: um JWT validamente assinado pode
ser só a anon key, sem usuário nenhum por trás. Por isso o código abaixo
cria um segundo client, escopado com o JWT recebido no cabeçalho
Authorization, chama auth.getUser() para confirmar uma sessão real e
rpc('is_admin') para confirmar o papel administrativo (mesma function já
usada em todo o resto do catálogo editorial, avaliada sob o auth.uid()
deste usuário) — só então o id desse usuário, nunca um valor vindo do
corpo da requisição, é repassado como p_actor_id à RPC de persistência
(public.svc_apply_catalog_import_revalidation, Query 2106).

Convenções de Edge Function do projeto (ver import-card-assets/index.ts):
1. Só existe de fato depois de `npx supabase functions new
   revalidate-catalog-import-rows` — nunca criado "na mão".
3. Responsabilidade única: só revalida staging já existente.
6. index.ts só orquestra — SQL/leitura ficam em services/.
8. Cliente Supabase de serviço próprio via SUPABASE_URL/
   SUPABASE_SERVICE_ROLE_KEY — além dele, um segundo cliente escopado
   pelo JWT do chamador, só para autenticação/autorização (ver acima),
   nunca usado para ler ou escrever catalog_import_row/job.
*/

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import {
  applyRevalidation,
  confirmCatalogImport,
  findAssetSourceByCode,
  findCardSetWithGame,
  listCategoriesByGameCode,
  listExistingCardsMap,
  listRarityExternalMappingsByGameAndSource,
  listRevalidatableJobs,
  listRowsForRevalidation,
} from "./services/database.ts";
import { resolveCatalogImportRow } from "../_shared/catalog-normalization/mod.ts";
import type { RawCatalogCard } from "../_shared/catalog-normalization/mod.ts";
import type { RequestBody } from "./types.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Client de serviço — único usado para ler/escrever catalog_import_row,
// catalog_import_job e chamar a RPC de persistência. Nunca recebe o JWT
// do chamador.
const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

type JobResult = {
  job_id: string;
  card_set_id: string;
  rows_updated: number;
  rows_unblocked: number;
  valid_rows: number;
  needs_review_rows: number;
  invalid_rows: number;
  // Preenchidos só quando rows_unblocked > 0 (admin_confirm_catalog_import
  // foi chamada de novo) — null quando nenhuma linha precisou de retomada
  // de persistência.
  confirm_inserted_count: number | null;
  confirm_updated_count: number | null;
  confirm_failed_count: number | null;
  job_status: string | null;
  error: string | null;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ success: false, error: "METHOD_NOT_ALLOWED" }, { status: 405, headers: { Allow: "POST" } });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return Response.json({ success: false, error: "MISSING_AUTHORIZATION" }, { status: 401 });
  }

  // Client escopado pelo JWT do chamador — existe só para autenticação/
  // autorização (auth.getUser() + rpc('is_admin')), nunca para ler ou
  // escrever catalog_import_row/catalog_import_job (isso é sempre feito
  // pelo client de service role, `supabase`, acima).
  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) {
    console.error("REVALIDATE_INVALID_USER_SESSION:", userError);
    return Response.json({ success: false, error: "INVALID_USER_SESSION" }, { status: 401 });
  }

  const { data: isAdminResult, error: isAdminError } = await userClient.rpc("is_admin");
  if (isAdminError || isAdminResult !== true) {
    console.error("REVALIDATE_FORBIDDEN_NOT_ADMIN:", isAdminError);
    return Response.json({ success: false, error: "FORBIDDEN_NOT_ADMIN" }, { status: 403 });
  }

  // Id verificado sob auth.uid() real desta sessão — a única origem
  // aceitável de p_actor_id (Query 2106 v1.1). Nunca lido do corpo da
  // requisição.
  const actorId = userData.user.id;

  let body: RequestBody = {};
  try {
    const rawBody = await req.text();
    body = rawBody ? JSON.parse(rawBody) : {};
  } catch {
    return Response.json({ success: false, error: "INVALID_JSON" }, { status: 400 });
  }

  const jobIds = Array.isArray(body.job_ids) && body.job_ids.length > 0 ? body.job_ids : undefined;

  try {
    const jobs = await listRevalidatableJobs(supabase, jobIds);
    const jobResults: JobResult[] = [];

    for (const job of jobs) {
      try {
        const cardSet = await findCardSetWithGame(supabase, job.card_set_id);
        if (!cardSet) throw new Error("CARD_SET_NOT_FOUND");

        const assetSource = await findAssetSourceByCode(supabase, job.source);
        if (!assetSource) throw new Error(`ASSET_SOURCE_NOT_FOUND: ${job.source}`);

        const rarityMappingByNormalizedValue = await listRarityExternalMappingsByGameAndSource(
          supabase,
          cardSet.game_id,
          assetSource.id,
        );
        const categoriesByCode = await listCategoriesByGameCode(supabase, cardSet.game_id);
        const existingCardsByCollectorNumber = await listExistingCardsMap(supabase, cardSet.id);

        const rows = await listRowsForRevalidation(supabase, job.id);
        if (rows.length === 0) continue;

        const seenCollectorNumbers = new Set<string>();
        const resolvedRows = rows.map((row, index) =>
          resolveCatalogImportRow({
            rawCard: row.raw_data as unknown as RawCatalogCard,
            rawData: row.raw_data,
            indexInSet: index,
            collectorTotal: (row.normalized_data as any)?.collector_total ?? null,
            rarityMappingByNormalizedValue,
            categoriesByCode,
            existingCardsByCollectorNumber,
            seenCollectorNumbers,
            extraNote: null,
          })
        );

        const rowUpdates = resolvedRows.map((resolved, index) => ({
          row_id: rows[index].id,
          normalized_data: resolved.normalized_data as unknown as Record<string, unknown>,
          validation_status: resolved.validation_status,
          match_status: resolved.match_status,
          matched_card_id: resolved.matched_card_id,
        }));

        const result = await applyRevalidation(supabase, job.id, rowUpdates, actorId);
        const unblockedCount = result?.unblocked_count ?? 0;

        // Só re-tenta a persistência quando a revalidação de fato destravou
        // alguma linha (FAILED -> PENDING) — nunca chama
        // admin_confirm_catalog_import() para um job puramente STAGED sem
        // nenhuma tentativa de confirmação anterior (nada para retomar).
        // Usa userClient (JWT do administrador já verificado acima), nunca
        // o client de service role — admin_confirm_catalog_import() exige
        // is_admin()/auth.uid() reais.
        let confirmResult: { inserted_count: number; updated_count: number; failed_count: number; job_status: string } | null = null;
        if (unblockedCount > 0) {
          confirmResult = await confirmCatalogImport(userClient, job.id);

          // Fatia C — Primary Species (2026-09-05, INCREMENTAL-IMPLEMENTATION-01):
          // mesmo ponto de integração único usado pelo Fluxo A
          // (confirmarImportacao(), web/app/catalogo/importar-cartas/tcgdex/
          // actions.ts), chamado aqui só depois que confirmCatalogImport()
          // já teve sucesso. Usa userClient (JWT do administrador já
          // verificado acima) — nunca o client de service role — porque
          // resolve_card_primary_species_for_catalog_import_job() exige
          // is_admin()/auth.uid() reais, mesma exigência de
          // admin_confirm_catalog_import().
          //
          // Checagem direta de { error }, nunca uma função auxiliar que
          // lança exceção (diferente de confirmCatalogImport() acima, que
          // propositalmente `throw`s): esta chamada está dentro do mesmo
          // bloco try/catch por job (linha ~150 abaixo) que já envolve toda
          // a revalidação + confirmação. Se uma falha de Primary Species
          // fosse lançada como exceção aqui, o catch por job a capturaria e
          // reportaria como jobResults[].error — fazendo o job inteiro
          // parecer ter falhado mesmo com os Cards já persistidos com
          // sucesso. Por isso: só loga, nunca lança, nunca altera
          // confirmResult/jobResults.
          const { error: speciesError } = await userClient.rpc(
            "resolve_card_primary_species_for_catalog_import_job",
            { p_job_id: job.id },
          );
          if (speciesError) {
            console.error(
              `RESOLVE_CARD_PRIMARY_SPECIES_FOR_CATALOG_IMPORT_JOB_FAILED ${job.id}:`,
              speciesError,
            );
          }
        }

        jobResults.push({
          job_id: job.id,
          card_set_id: job.card_set_id,
          rows_updated: result?.updated_count ?? 0,
          rows_unblocked: unblockedCount,
          valid_rows: result?.valid_rows ?? 0,
          needs_review_rows: result?.needs_review_rows ?? 0,
          invalid_rows: result?.invalid_rows ?? 0,
          confirm_inserted_count: confirmResult?.inserted_count ?? null,
          confirm_updated_count: confirmResult?.updated_count ?? null,
          confirm_failed_count: confirmResult?.failed_count ?? null,
          job_status: confirmResult?.job_status ?? result?.job_status ?? null,
          error: null,
        });
      } catch (jobError) {
        const message = jobError instanceof Error ? jobError.message : "UNEXPECTED_ERROR";
        console.error(`REVALIDATE_JOB_FAILED ${job.id}:`, message);
        jobResults.push({
          job_id: job.id,
          card_set_id: job.card_set_id,
          rows_updated: 0,
          rows_unblocked: 0,
          valid_rows: 0,
          needs_review_rows: 0,
          invalid_rows: 0,
          confirm_inserted_count: null,
          confirm_updated_count: null,
          confirm_failed_count: null,
          job_status: null,
          error: message,
        });
      }
    }

    return Response.json({
      success: true,
      jobs_processed: jobResults.length,
      results: jobResults,
    });
  } catch (error) {
    console.error(error);
    const message = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
    return Response.json({ success: false, error: message }, { status: 500 });
  }
});
