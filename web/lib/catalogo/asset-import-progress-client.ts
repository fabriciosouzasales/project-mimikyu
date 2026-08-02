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
    .select("requested_count, processed_count, success_count, failed_count, status")
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
  };
}
