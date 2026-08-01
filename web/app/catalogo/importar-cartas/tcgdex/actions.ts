"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroCatalogo } from "@/lib/supabase/catalogo-errors";
import { searchTcgdexSetsManually, type TcgdexSetCandidate } from "@/lib/catalogo/tcgdex-lookup";
import {
  getCatalogImportJobStatus,
  getCatalogImportRows,
  type CatalogImportJobStatus,
  type CatalogImportRowView,
} from "@/lib/catalogo/queries";

/**
 * Server Actions do fluxo de importação via TCGdex (Ciclo 2, ADR-024),
 * adicionadas em 2026-08-01.
 */

export type IniciarImportacaoTcgdexActionState = { error: string | null; jobId: string | null };

/**
 * Inicia o fluxo de importação para uma Coleção: abre o job
 * (admin_start_catalog_import, Query 2080) e invoca a Edge Function
 * processadora (import-catalog-cards, Ciclo 2 Sprint 1) — aguarda a
 * resposta antes de devolver o resultado (chamada síncrona; para Coleções
 * muito grandes isso pode se aproximar do limite de execução — risco já
 * sinalizado no plano do Ciclo 2, não resolvido preventivamente aqui).
 *
 * external_set_id chega já resolvido pelo formulário (localização
 * automática ou escolha manual em MatchResultPanel/ManualSearchPanel) —
 * esta action nunca pede esse valor ao administrador.
 *
 * Devolve `{ jobId }` em vez de redirecionar (era `redirect(".../tcgdex/
 * ${jobId}")`, depois `redirect("/catalogo/importar-cartas?jobId=...")` —
 * as duas trocadas em 2026-08-01, terceira rodada: qualquer `redirect()`
 * força uma navegação de página, que remonta tudo do zero e destrói o
 * estado do componente cliente — exatamente o motivo de "o progresso
 * desaparece"/"abre em outra página" que Fabrício reportou. `importar-
 * tcgdex-view.tsx` guarda o jobId recebido em estado React e busca
 * job+linhas via getImportacaoJobData abaixo, sem nunca navegar.
 */
export async function iniciarImportacaoTcgdex(
  _prevState: IniciarImportacaoTcgdexActionState,
  formData: FormData,
): Promise<IniciarImportacaoTcgdexActionState> {
  const cardSetId = String(formData.get("card_set_id") ?? "");
  const externalSetId = String(formData.get("external_set_id") ?? "").trim();

  if (!cardSetId) {
    return { error: "Selecione uma Coleção.", jobId: null };
  }
  if (!externalSetId) {
    return { error: "Não foi possível determinar o Set da TCGdex.", jobId: null };
  }

  const supabase = await createClient();
  const { data: jobId, error } = await supabase.rpc("admin_start_catalog_import", {
    p_card_set_id: cardSetId,
    p_source: "TCGDEX",
    p_external_set_id: externalSetId,
  });

  if (error) {
    // ADMIN_START_CATALOG_IMPORT_ALREADY_ACTIVE (Query 2080): a constraint
    // uq_catalog_import_job_fingerprint_active já bloqueia corretamente um
    // segundo job para o mesmo Card Set+origem — mas um erro em texto é um
    // beco sem saída para o administrador, que não tem como saber o id do
    // job existente. Descoberto na prática em 2026-08-01 (Fabrício testou
    // ME5 duas vezes): em vez de só mostrar o erro, localiza o job ativo e
    // devolve o id dele — o componente cliente mostra o mesmo status/
    // revisão que ele já ia querer ver de qualquer forma.
    if (error.message.startsWith("ADMIN_START_CATALOG_IMPORT_ALREADY_ACTIVE")) {
      const { data: existingJob } = await supabase
        .from("catalog_import_job")
        .select("id")
        .eq("card_set_id", cardSetId)
        .eq("source", "TCGDEX")
        .in("status", ["RECEIVED", "PROCESSING", "STAGED", "CONFIRMING"])
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (existingJob) {
        return { error: null, jobId: existingJob.id as string };
      }
    }

    return { error: traduzirErroCatalogo(error.message), jobId: null };
  }

  const functionUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/import-catalog-cards`;

  let response: Response;
  try {
    response = await fetch(functionUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ job_id: jobId }),
    });
  } catch (fetchError) {
    const message = fetchError instanceof Error ? fetchError.message : "Falha de rede.";
    return { error: `Falha ao chamar o processador: ${message}`, jobId: null };
  }

  if (!response.ok) {
    const body = await response.json().catch(() => null);
    return { error: `Falha ao processar a importação: ${body?.error ?? response.status}`, jobId: null };
  }

  revalidatePath("/catalogo/importar-cartas");
  return { error: null, jobId: String(jobId) };
}

/**
 * Busca manual de Sets na TCGdex por nome — chamada diretamente do
 * componente cliente (sem formulário), usada só quando a localização
 * automática não resolve sozinha (ambígua ou sem correspondência).
 */
export async function buscarSetsTcgdexManualmente(query: string): Promise<TcgdexSetCandidate[]> {
  return searchTcgdexSetsManually(query);
}

/**
 * Busca job + linhas de staging em uma única chamada — usada pelo
 * componente cliente (2026-08-01, terceira rodada) tanto logo após
 * iniciarImportacaoTcgdex devolver um jobId quanto para "atualizar" depois
 * de decidirLinhasImportacao/confirmarImportacao, substituindo o antigo
 * `router.refresh()` (que dependia de `?jobId=` na URL e de um Server
 * Component re-renderizando — o fluxo não navega mais, então não há mais
 * URL nem Server Component pra fazer isso). Reviewable usa o mesmo critério
 * de sempre (STAGED/CONFIRMING) — sem importar de job-status-view.tsx
 * (client component) pra dentro deste arquivo "use server", só repete a
 * checagem, mais simples que arriscar um import cruzado de boundary.
 */
export async function getImportacaoJobData(
  jobId: string,
): Promise<{ job: CatalogImportJobStatus | null; rows: CatalogImportRowView[] }> {
  const supabase = await createClient();
  const job = await getCatalogImportJobStatus(supabase, jobId);
  const reviewable = job?.status === "STAGED" || job?.status === "CONFIRMING";
  const rows = reviewable ? await getCatalogImportRows(supabase, jobId) : [];
  return { job, rows };
}

// ---------------------------------------------------------------------------
// Revisão e Confirmação (Ciclo 2, Sprint 2b, ADR-024) — adicionadas em
// 2026-08-01, mesmo arquivo do restante do fluxo TCGdex.
// ---------------------------------------------------------------------------

export type DecidirLinhasResult = { error: string | null };

/**
 * Decide o destino de uma ou mais linhas de staging (aprovar/rejeitar/pular/
 * desfazer via admin_decide_catalog_import_row, Query 2081) — chamada direta
 * a partir de cliques na tela de Revisão (linha única ou seleção em massa),
 * sem <form>/useActionState — mesmo padrão de buscarSetsTcgdexManualmente
 * acima.
 */
export async function decidirLinhasImportacao(
  jobId: string,
  rowIds: string[],
  decisionStatus: "PENDING" | "APPROVED" | "REJECTED" | "SKIPPED",
): Promise<DecidirLinhasResult> {
  if (rowIds.length === 0) {
    return { error: null };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_decide_catalog_import_row", {
    p_row_ids: rowIds,
    p_decision_status: decisionStatus,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  // `/catalogo/importar-cartas` (era `/catalogo/importar-cartas/tcgdex/${jobId}`,
  // rota removida do fluxo principal em 2026-08-01 — ver comentário de
  // iniciarImportacaoTcgdex acima). `jobId` não é mais usado para montar o
  // path, mas continua no parâmetro da função — RevisaoImportacaoTable
  // ainda o repassa e ele identifica as linhas na chamada RPC acima.
  revalidatePath("/catalogo/importar-cartas");
  return { error: null };
}

/** Tamanho de lote por chamada de admin_confirm_catalog_import() — recomendação operacional do próprio ADR-024. */
const CONFIRM_CHUNK_SIZE = 50;

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

export type ConfirmarImportacaoResult = {
  error: string | null;
  insertedCount: number;
  updatedCount: number;
  unchangedCount: number;
  failedCount: number;
  pendingCount: number;
  jobStatus: string | null;
};

type AdminConfirmCatalogImportRow = {
  inserted_count: number;
  updated_count: number;
  unchanged_count: number;
  failed_count: number;
  pending_count: number;
  job_status: string;
};

const EMPTY_CONFIRM_RESULT: Omit<ConfirmarImportacaoResult, "error"> = {
  insertedCount: 0,
  updatedCount: 0,
  unchangedCount: 0,
  failedCount: 0,
  pendingCount: 0,
  jobStatus: null,
};

/**
 * Confirma a importação — persiste as linhas aprovadas/puladas em
 * public.card via admin_confirm_catalog_import() (Query 2082). Busca
 * primeiro os ids elegíveis (persistence_status = PENDING e decision_status
 * IN (APPROVED, SKIPPED)) e chama a RPC em lotes de CONFIRM_CHUNK_SIZE,
 * sequencialmente — cada chamada devolve contadores recalculados sobre o
 * job inteiro (agregação, não incremento), então o resultado devolvido é
 * sempre o da última chamada, que já reflete o estado final acumulado. Sem
 * linhas elegíveis, ainda assim faz uma chamada (p_row_ids = NULL) — é o
 * que transiciona o job de STAGED para COMPLETED mesmo quando tudo foi
 * rejeitado/pulado.
 *
 * Linha que falhar (persistence_status = FAILED) fica permanentemente fora
 * de tentativas futuras — admin_confirm_catalog_import() só considera
 * persistence_status = PENDING (Query 2082) e nenhuma função deste ciclo
 * reseta esse campo. Sem mecanismo de nova tentativa nesta rodada
 * (backlog, fora do escopo do fluxo vertical aprovado para o Ciclo 2) — a
 * linha permanece visível na tela de Revisão com error_detail, mas uma
 * nova chamada de confirmarImportacao não a tocará.
 *
 * Risco conhecido (mesmo já sinalizado em iniciarImportacaoTcgdex): para
 * Coleções muito grandes, o número de lotes sequenciais pode se aproximar
 * do limite de execução da Server Action — não resolvido preventivamente
 * aqui.
 */
export async function confirmarImportacao(jobId: string): Promise<ConfirmarImportacaoResult> {
  const supabase = await createClient();

  const { data: eligibleRows, error: fetchError } = await supabase
    .from("catalog_import_row")
    .select("id")
    .eq("job_id", jobId)
    .eq("persistence_status", "PENDING")
    .in("decision_status", ["APPROVED", "SKIPPED"]);

  if (fetchError) {
    return { error: traduzirErroCatalogo(fetchError.message), ...EMPTY_CONFIRM_RESULT };
  }

  const rowIds = (eligibleRows ?? []).map((row) => row.id as string);
  const batches: (string[] | null)[] = rowIds.length > 0 ? chunk(rowIds, CONFIRM_CHUNK_SIZE) : [null];

  let lastResult: ConfirmarImportacaoResult = { error: null, ...EMPTY_CONFIRM_RESULT };

  for (const batch of batches) {
    const { data, error } = await supabase.rpc("admin_confirm_catalog_import", {
      p_job_id: jobId,
      p_row_ids: batch,
    });

    if (error) {
      // ...lastResult primeiro, error depois: lastResult também tem seu
      // próprio campo `error` (sempre null até aqui) — se viesse depois do
      // spread, sobrescreveria a mensagem de erro real por null.
      return { ...lastResult, error: traduzirErroCatalogo(error.message) };
    }

    const rows = (data ?? []) as AdminConfirmCatalogImportRow[];
    const [row] = rows;
    if (row) {
      lastResult = {
        error: null,
        insertedCount: row.inserted_count,
        updatedCount: row.updated_count,
        unchangedCount: row.unchanged_count,
        failedCount: row.failed_count,
        pendingCount: row.pending_count,
        jobStatus: row.job_status,
      };
    }
  }

  // Revalida também as telas que derivam "Coleções sem cartas" de
  // public.card (Cartas e Importar Cartas, ambas via getCardSetsForCartas)
  // — descoberto na prática em 2026-08-01 (Fabrício confirmou ME5 com
  // sucesso, mas o indicador "Sem Cartas" continuou mostrando 5 em vez de
  // 4): revalidar só a própria página do job não bastava, essas duas telas
  // ficavam com o Next.js cache antigo.
  // Rotas antigas (`/catalogo/importar-cartas/tcgdex/${jobId}`,
  // `/catalogo/importar-cartas/tcgdex`) saíram do fluxo principal em
  // 2026-08-01 — mantidas aqui não custa nada (revalidatePath numa rota que
  // ainda existe fisicamente, só não é mais navegada), evita esquecer se
  // algum link direto ainda apontar pra lá.
  revalidatePath(`/catalogo/importar-cartas/tcgdex/${jobId}`);
  revalidatePath("/catalogo/importar-cartas/tcgdex");
  revalidatePath("/catalogo/importar-cartas");
  revalidatePath("/catalogo/cartas");
  return lastResult;
}
