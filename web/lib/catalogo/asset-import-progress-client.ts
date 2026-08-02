import { createClient } from "@/lib/supabase/client";
import type { ProgressoImportacaoImagens } from "@/app/catalogo/importar-cartas/tcgdex/actions";

/**
 * Teto de tentativas do retry automático client-side (2026-08-02, pedido
 * explícito de Fabrício depois de ver a importação de SV4 falhar de novo com
 * HTTP 504, apesar do progresso real de 115→169 imagens): a Edge Function
 * `import-card-assets` tem um teto de tempo de execução da própria
 * plataforma que não muda (não é algo que o código da função controle) — uma
 * Coleção grande sempre vai precisar de várias chamadas para terminar. Em
 * vez de exigir um clique manual em "Importar Imagens" a cada falha, o
 * cliente (`useAnalyzeJob`/`importar-imagens-view.tsx`) repete a chamada
 * automaticamente (mesmo `run_code`, sem reabrir a run) até `imagesFailed`
 * chegar a zero ou parar de progredir. Este teto existe só como rede de
 * segurança contra um loop sem fim numa falha real e persistente (ex.: rede
 * fora do ar) — 25 tentativas, a ~5 cartas por lote reportado por
 * `updateImportRunProgress` (`IMAGE_BATCH_SIZE`), cobre folgadamente
 * qualquer Coleção do catálogo atual.
 */
export const MAX_IMAGE_IMPORT_RETRY_ATTEMPTS = 25;

/**
 * Leitura de `asset_import_run` por `run_code`, direto do navegador (2026-08-02,
 * substitui a implementação original via Server Action — `getProgressoImportacaoImagens`,
 * ainda exportada de `tcgdex/actions.ts`, mas não usada mais para o polling em si).
 *
 * Bug real reportado por Fabrício no primeiro teste em produção: o contador
 * "X de Y" nunca apareceu durante uma importação real de ~1 minuto na SV4
 * (54 imagens efetivamente gravadas no intervalo, confirmadas pela contagem
 * final), mesmo com `updateImportRunProgress` (Edge Function v2.7.0)
 * gravando o progresso real a cada lote — tempo de sobra para várias
 * consultas de polling a cada 2s terem sucesso, se a leitura funcionasse. A
 * causa exata do polling via Server Action nunca responder não foi
 * confirmada com certeza (não há acesso a logs do servidor/rede do
 * navegador de Fabrício para isolar se as chamadas nem saíam do navegador,
 * se voltavam vazias, ou se o estado React nunca re-renderizava) — em vez de
 * insistir num mecanismo que já falhou uma vez em produção, trocado pelo
 * padrão mais simples e mais testado neste projeto para leitura client-side:
 * o mesmo `createBrowserClient` (`@/lib/supabase/client`) já usado por
 * `card-set-logo-uploader.tsx`/`expansao-logo-uploader.tsx`/`avatar-uploader.tsx`/
 * `users-table.tsx` — uma consulta REST direta (anon key + RLS via
 * `catalog_admin_select`, a mesma policy que já autorizava a versão anterior),
 * sem a camada adicional (e a superfície de incerteza) de uma Server Action
 * chamada repetidamente a partir de um `setInterval`.
 */
export async function fetchProgressoImportacaoImagens(runCode: string): Promise<ProgressoImportacaoImagens | null> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("asset_import_run")
    .select("requested_count, processed_count, success_count, failed_count, status, error_summary")
    .eq("run_code", runCode)
    .maybeSingle();

  if (error) {
    console.error("FETCH PROGRESSO IMPORTACAO IMAGENS ERROR:", error);
  }
  if (error || !data) return null;

  return {
    requestedCount: data.requested_count,
    processedCount: data.processed_count,
    successCount: data.success_count,
    failedCount: data.failed_count,
    status: data.status,
    errorSummary: data.error_summary,
  };
}

/** Status terminais de `asset_import_run` — ver `govern_asset_import_run()` (`database/schema/221_asset_import_run_triggers.sql`). */
const TERMINAL_RUN_STATUSES = new Set(["COMPLETED", "COMPLETED_WITH_ERRORS", "FAILED", "CANCELLED"]);

/**
 * Acompanha uma run que já está em andamento (aberta por outra aba/sessão —
 * `admin_start_asset_import_run()` devolveu `already_active = true`) até ela
 * chegar a um status terminal, chamando `onProgress` a cada leitura (mesmo
 * intervalo de 2s do polling normal) — 2026-08-02, mesmo dia, rodada
 * seguinte.
 *
 * Bug real corrigido: antes, o caminho `alreadyActive` (`handleImportar`/
 * `useAnalyzeJob`) simplesmente marcava a importação como concluída com
 * `imagesImported: 0`/`imagesFailed: 0`, sem checar nada — Fabrício viu isso
 * na prática (ME5): clicou "Importar Imagens" enquanto uma tentativa
 * anterior ainda processava de verdade em segundo plano (40/120 processadas
 * até então) e a tela mostrou "0 importadas · 0 pendentes" com tom de
 * sucesso, como se nada tivesse pra fazer — enganoso, porque na verdade uma
 * importação real estava em andamento.
 *
 * Teto de segurança `MAX_WAIT_POLLS` (300 tentativas × 2s = 10 minutos) —
 * mesma lógica de `MAX_IMAGE_IMPORT_RETRY_ATTEMPTS` acima: rede de segurança
 * contra uma run genuinamente presa (nunca chega a um status terminal),
 * nunca deve ser atingido em uso normal. Devolve `null` se o teto for
 * atingido — quem chama trata isso como "ainda não sabemos o resultado",
 * nunca como sucesso.
 */
const MAX_WAIT_POLLS = 300;
const WAIT_POLL_INTERVAL_MS = 2000;

export async function waitForActiveRunToFinish(
  runCode: string,
  onProgress: (progress: ProgressoImportacaoImagens) => void,
): Promise<ProgressoImportacaoImagens | null> {
  for (let attempt = 0; attempt < MAX_WAIT_POLLS; attempt += 1) {
    const progress = await fetchProgressoImportacaoImagens(runCode);
    if (progress) {
      onProgress(progress);
      if (TERMINAL_RUN_STATUSES.has(progress.status)) {
        return progress;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, WAIT_POLL_INTERVAL_MS));
  }
  return null;
}
