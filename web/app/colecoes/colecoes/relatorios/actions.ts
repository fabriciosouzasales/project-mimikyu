"use server";

import { type CollectionDistributionReportLoad, getCollectionDistributionReport } from "@/lib/reports/collection-distribution-queries";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser } from "@/lib/supabase/request-auth-cache";

/**
 * V1-14 R1-B — dados do relatório "Distribuição do Acervo por coleção" para a sobreposição aberta
 * SOBRE Minhas coleções (só server actions; esta pasta não tem página). Só o titular: sem sessão →
 * erro; as leituras (5160, 5182, 5159) resolvem o dono por `auth.uid()` no banco e não recebem
 * identificador do cliente. Somente leitura.
 */
export async function readCollectionDistributionReport(): Promise<CollectionDistributionReportLoad> {
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) return { status: "error" };
  const supabase = await createClient();
  try {
    return await getCollectionDistributionReport(supabase);
  } catch (error) {
    console.error("[reports] readCollectionDistributionReport falhou", { message: error instanceof Error ? error.message : "unknown" });
    return { status: "error" };
  }
}
