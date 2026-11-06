"use server";

import {
  type AcervoValueReportLoad,
  type SetInventoryReportLoad,
  type SetSummaryReportLoad,
  getAcervoValueReport,
  getSetInventoryReport,
  getSetSummaryReport,
} from "@/lib/reports/acervo-set-inventory-queries";
import { type FavoritesReportLoad, getFavoritesReport } from "@/lib/reports/favorites-report-queries";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser } from "@/lib/supabase/request-auth-cache";

/**
 * V1-14 R1-B — dados do relatório 01, "Inventário resumido por Card Set": todo o acervo físico por
 * Card Set do catálogo. Só o titular (5160 e 5159 resolvem o dono por `auth.uid()`), nenhum
 * identificador do cliente, somente leitura.
 */
export async function readSetSummaryReport(): Promise<SetSummaryReportLoad> {
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) return { status: "error" };
  const supabase = await createClient();
  try {
    return await getSetSummaryReport(supabase);
  } catch (error) {
    console.error("[reports] readSetSummaryReport falhou", { message: error instanceof Error ? error.message : "unknown" });
    return { status: "error" };
  }
}

/**
 * V1-14 R1-B — dados do relatório 02, "Inventário detalhado por Card Set": todo o acervo físico,
 * independente de coleção. Mesmas garantias: só o titular (5160, 5159, 3983 resolvem o dono por
 * `auth.uid()`), nenhum identificador do cliente, somente leitura.
 */
export async function readSetInventoryReport(): Promise<SetInventoryReportLoad> {
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) return { status: "error" };
  const supabase = await createClient();
  try {
    return await getSetInventoryReport(supabase);
  } catch (error) {
    console.error("[reports] readSetInventoryReport falhou", { message: error instanceof Error ? error.message : "unknown" });
    return { status: "error" };
  }
}

/**
 * V1-14 R1-C — dados do relatório 03, "Valor estimado total": a mesma leitura do 02 (5160, 5159,
 * 3989 — dono por `auth.uid()`), projetada por Card Set. Nenhum identificador do cliente, somente
 * leitura, sem SQL nova.
 */
export async function readAcervoValueReport(): Promise<AcervoValueReportLoad> {
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) return { status: "error" };
  const supabase = await createClient();
  try {
    return await getAcervoValueReport(supabase);
  } catch (error) {
    console.error("[reports] readAcervoValueReport falhou", { message: error instanceof Error ? error.message : "unknown" });
    return { status: "error" };
  }
}

/**
 * V1-14 R1-D — dados do relatório 04, "Minhas favoritas": favoritas (5336), referência por carta
 * (`get_cards_pricing_summary`) e posse (5160/5159 + `get_my_card_favorites_by_variant`). Só o
 * titular (todas resolvem o dono por `auth.uid()`), nenhum identificador do cliente, somente
 * leitura, sem SQL nova.
 */
export async function readFavoritesReport(): Promise<FavoritesReportLoad> {
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) return { status: "error" };
  const supabase = await createClient();
  try {
    // Miniaturas: mesma origem pública da página Cartas favoritas (bucket `card-front`, síncrono).
    const imageUrl = (path: string) => supabase.storage.from("card-front").getPublicUrl(path).data.publicUrl ?? null;
    return await getFavoritesReport(supabase, new Date(), imageUrl);
  } catch (error) {
    console.error("[reports] readFavoritesReport falhou", { message: error instanceof Error ? error.message : "unknown" });
    return { status: "error" };
  }
}
