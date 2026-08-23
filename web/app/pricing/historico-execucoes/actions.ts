"use server";

import { createClient } from "@/lib/supabase/server";
import { getPricingSyncRunDetail, type PricingSyncRunDetail } from "@/lib/pricing/queries";

/**
 * Wrapper de leitura para o Dialog de detalhe de execução — o Dialog é um
 * Client Component (precisa abrir sob clique e mostrar loading), então o
 * fetch de `admin_get_pricing_sync_run_detail` (que já existe como query de
 * Server Component em `lib/pricing/queries.ts`) precisa de uma Server Action
 * própria para ser chamado a partir dele. Mesmo padrão de "arquivo de
 * actions por rota" já usado em `resolucao-mapeamentos/actions.ts`, mas esta
 * é só leitura — nunca escreve, nunca precisa de `revalidatePath`.
 */
export async function getPricingSyncRunDetailAction(runId: string): Promise<PricingSyncRunDetail | null> {
  const supabase = await createClient();
  return getPricingSyncRunDetail(supabase, runId);
}
