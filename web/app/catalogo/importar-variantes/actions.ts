"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroCatalogo } from "@/lib/supabase/catalogo-errors";
import {
  getCatalogVariantImportJobStatus,
  getCatalogVariantImportRows,
  type CatalogVariantImportJobStatus,
  type CatalogVariantImportRowView,
} from "@/lib/catalogo/queries";

/**
 * Server Actions do fluxo Importar Variantes (Incremento 4, ADR-028),
 * adicionadas em 2026-08-15 — mesmo padrão de
 * `catalogo/importar-cartas/tcgdex/actions.ts`, uma instância nova dele para
 * o staging de Card Variant. Diferença estrutural real: a Edge Function
 * `import-card-variants` recebe `{ card_set_id }` (não `{ job_id }`) e cria o
 * próprio job internamente — não existe aqui um RPC "abrir job" equivalente a
 * `admin_start_catalog_import` (CV-02, tela dedicada de job pré-criado, está
 * deliberadamente fora do escopo desta rodada).
 */

export type IniciarImportacaoVariantesActionState = { error: string | null; jobId: string | null };

/**
 * Inicia a importação de variantes para uma Coleção: invoca
 * import-card-variants diretamente com `card_set_id` (a function resolve
 * external_set_id via card_set_external_reference e cria o job em
 * PROCESSING internamente — ver comentário no topo da Edge Function).
 * Devolve `{ jobId }` em vez de redirecionar — mesmo motivo de
 * `iniciarImportacaoTcgdex` (ver tcgdex/actions.ts): qualquer `redirect()`
 * destruiria o estado de progresso do componente cliente.
 *
 * `JOB_ALREADY_ACTIVE_FOR_CARD_SET` (409): diferente de
 * `admin_start_catalog_import`/Query 2080, a Edge Function não devolve o id
 * do job já ativo — só o próprio erro. Localiza o job ativo diretamente na
 * tabela (mesmo raciocínio de `iniciarImportacaoTcgdex` para
 * `ADMIN_START_CATALOG_IMPORT_ALREADY_ACTIVE`) para não deixar o
 * administrador num beco sem saída.
 */
export async function iniciarImportacaoVariantes(
  _prevState: IniciarImportacaoVariantesActionState,
  formData: FormData,
): Promise<IniciarImportacaoVariantesActionState> {
  const cardSetId = String(formData.get("card_set_id") ?? "");

  if (!cardSetId) {
    return { error: "Selecione uma Coleção.", jobId: null };
  }

  const supabase = await createClient();

  // Fronteira de identidade (mesmo padrão de import-catalog-cards/
  // import-card-assets, Finding 1 da auditoria de segurança do Catálogo
  // Editorial, 2026-08-13): o access_token da sessão do próprio
  // administrador é repassado, nunca lido do corpo da requisição.
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return { error: "Sessão inválida. Faça login novamente.", jobId: null };
  }

  const functionUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/import-card-variants`;

  let response: Response;
  try {
    response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({ card_set_id: cardSetId }),
    });
  } catch (fetchError) {
    const message = fetchError instanceof Error ? fetchError.message : "Falha de rede.";
    return { error: `Falha ao chamar o processador: ${message}`, jobId: null };
  }

  const body = await response.json().catch(() => null);

  if (!response.ok) {
    if (typeof body?.error === "string" && body.error.startsWith("JOB_ALREADY_ACTIVE_FOR_CARD_SET")) {
      const { data: existingJob } = await supabase
        .from("catalog_variant_import_job")
        .select("id")
        .eq("card_set_id", cardSetId)
        .in("status", ["RECEIVED", "PROCESSING", "STAGED", "CONFIRMING"])
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (existingJob) {
        return { error: null, jobId: existingJob.id as string };
      }
    }

    return { error: `Falha ao processar a importação: ${body?.error ?? response.status}`, jobId: null };
  }

  revalidatePath("/catalogo/importar-variantes");
  return { error: null, jobId: String(body?.job?.id ?? "") || null };
}

/** Busca job + linhas de staging em uma única chamada — mesmo papel de getImportacaoJobData (tcgdex/actions.ts). */
export async function getImportacaoVariantesJobData(
  jobId: string,
): Promise<{ job: CatalogVariantImportJobStatus | null; rows: CatalogVariantImportRowView[] }> {
  const supabase = await createClient();
  const job = await getCatalogVariantImportJobStatus(supabase, jobId);
  const reviewable = job?.status === "STAGED" || job?.status === "CONFIRMING";
  const rows = reviewable ? await getCatalogVariantImportRows(supabase, jobId) : [];
  return { job, rows };
}

export type DecidirLinhasVariantesResult = { error: string | null };

/**
 * Decide o destino de uma ou mais linhas de staging (admin_decide_catalog_
 * variant_import_row, Query 2144) — mesmo padrão de decidirLinhasImportacao.
 * A própria RPC recusa APPROVED para linhas NEEDS_REVIEW (validation_status
 * <> VALID) — o erro chega aqui já traduzido pelo mesmo helper, a UI evita
 * oferecer essa ação quando dá para saber de antemão (ver
 * revisao-importacao-variantes-table.tsx), mas a garantia real está no
 * banco, não no componente.
 */
export async function decidirLinhasVariantes(
  jobId: string,
  rowIds: string[],
  decisionStatus: "PENDING" | "APPROVED" | "REJECTED" | "SKIPPED",
): Promise<DecidirLinhasVariantesResult> {
  if (rowIds.length === 0) {
    return { error: null };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_decide_catalog_variant_import_row", {
    p_row_ids: rowIds,
    p_decision_status: decisionStatus,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  // `jobId` não monta mais nenhuma URL (mesmo motivo de decidirLinhasImportacao)
  // — continua no parâmetro só para identificar as linhas na chamada acima.
  void jobId;
  revalidatePath("/catalogo/importar-variantes");
  return { error: null };
}

/** Mesmo tamanho de lote de confirmarImportacao (tcgdex/actions.ts) — recomendação operacional do ADR-024, reaproveitada aqui. */
const CONFIRM_CHUNK_SIZE = 50;

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

export type ConfirmarImportacaoVariantesResult = {
  error: string | null;
  insertedCount: number;
  unchangedCount: number;
  failedCount: number;
  pendingCount: number;
  jobStatus: string | null;
};

type AdminConfirmCatalogVariantImportRow = {
  inserted_count: number;
  unchanged_count: number;
  failed_count: number;
  pending_count: number;
  job_status: string;
};

const EMPTY_CONFIRM_RESULT: Omit<ConfirmarImportacaoVariantesResult, "error"> = {
  insertedCount: 0,
  unchangedCount: 0,
  failedCount: 0,
  pendingCount: 0,
  jobStatus: null,
};

/**
 * Confirma a importação — persiste as Card Variant aprovadas/puladas via
 * admin_confirm_catalog_variant_import() (Query 2145). Mesmo desenho de
 * confirmarImportacao (tcgdex/actions.ts): busca ids elegíveis
 * (persistence_status = PENDING e decision_status IN (APPROVED, SKIPPED)),
 * chama a RPC em lotes de CONFIRM_CHUNK_SIZE sequencialmente — cada chamada
 * devolve contadores recalculados sobre o job inteiro (agregação, não
 * incremento), o resultado devolvido é sempre o da última chamada. Sem
 * linhas elegíveis, ainda assim faz uma chamada (p_row_ids = NULL) — é o que
 * transiciona o job de STAGED para COMPLETED mesmo quando tudo foi
 * rejeitado/pulado. Sem `updatedCount` (diferença real frente a
 * ConfirmarImportacaoResult — ver Query 2145: card_variant não tem UPDATE).
 */
export async function confirmarImportacaoVariantes(jobId: string): Promise<ConfirmarImportacaoVariantesResult> {
  const supabase = await createClient();

  const { data: eligibleRows, error: fetchError } = await supabase
    .from("catalog_variant_import_row")
    .select("id")
    .eq("job_id", jobId)
    .eq("persistence_status", "PENDING")
    .in("decision_status", ["APPROVED", "SKIPPED"]);

  if (fetchError) {
    return { error: traduzirErroCatalogo(fetchError.message), ...EMPTY_CONFIRM_RESULT };
  }

  const rowIds = (eligibleRows ?? []).map((row) => row.id as string);
  const batches: (string[] | null)[] = rowIds.length > 0 ? chunk(rowIds, CONFIRM_CHUNK_SIZE) : [null];

  let lastResult: ConfirmarImportacaoVariantesResult = { error: null, ...EMPTY_CONFIRM_RESULT };

  for (const batch of batches) {
    const { data, error } = await supabase.rpc("admin_confirm_catalog_variant_import", {
      p_job_id: jobId,
      p_row_ids: batch,
    });

    if (error) {
      return { ...lastResult, error: traduzirErroCatalogo(error.message) };
    }

    const rows = (data ?? []) as AdminConfirmCatalogVariantImportRow[];
    const [row] = rows;
    if (row) {
      lastResult = {
        error: null,
        insertedCount: row.inserted_count,
        unchangedCount: row.unchanged_count,
        failedCount: row.failed_count,
        pendingCount: row.pending_count,
        jobStatus: row.job_status,
      };
    }
  }

  revalidatePath("/catalogo/importar-variantes");
  return lastResult;
}
