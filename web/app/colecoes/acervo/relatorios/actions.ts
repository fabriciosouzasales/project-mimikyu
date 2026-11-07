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
import { type DuplicatesReportLoad, getDuplicatesReport } from "@/lib/reports/duplicates-queries";
import { type TopCardsReportLoad, getTopCardsReport } from "@/lib/reports/top-cards-queries";
import { type WishlistReportLoad, getWishlistReport } from "@/lib/reports/wishlist-report-queries";
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

/**
 * V1-14 R1-E — "Minha Lista de Desejos" (5º do Meu acervo): desejos (5350/5351, lista inteira, ordem
 * "Set e número") + referência NM por variante distinta (3989, Pricing Resilience). Só o titular
 * (as RPCs resolvem o dono por `auth.uid()`), nenhum identificador do cliente, somente leitura,
 * sem SQL nova.
 */
export async function readWishlistReport(): Promise<WishlistReportLoad> {
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) return { status: "error" };
  const supabase = await createClient();
  try {
    // Miniaturas: mesma origem pública da página Lista de desejos (bucket `card-front`, síncrono).
    const imageUrl = (path: string) => supabase.storage.from("card-front").getPublicUrl(path).data.publicUrl ?? null;
    return await getWishlistReport(supabase, new Date(), imageUrl);
  } catch (error) {
    console.error("[reports] readWishlistReport falhou", { message: error instanceof Error ? error.message : "unknown" });
    return { status: "error" };
  }
}

/**
 * V1-14 R1-F — "Top 10 cartas mais valiosas" (6º do Meu acervo): leitura compartilhada do acervo
 * (5160/5159) + 3989 por variante (Pricing Resilience), mesma base monetária do Valor estimado
 * total. Só o titular (as RPCs resolvem o dono por `auth.uid()`), nenhum identificador do cliente,
 * somente leitura, sem SQL nova.
 */
export async function readTopCardsReport(): Promise<TopCardsReportLoad> {
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) return { status: "error" };
  const supabase = await createClient();
  try {
    // Miniaturas: mesma origem pública das imagens do Meu acervo (bucket `card-front`, síncrono).
    const imageUrl = (path: string) => supabase.storage.from("card-front").getPublicUrl(path).data.publicUrl ?? null;
    return await getTopCardsReport(supabase, new Date(), imageUrl);
  } catch (error) {
    console.error("[reports] readTopCardsReport falhou", { message: error instanceof Error ? error.message : "unknown" });
    return { status: "error" };
  }
}

/**
 * V1-14 R1-G — "Cartas repetidas" (7º do Meu acervo): leitura compartilhada do acervo (5160/5159)
 * + 3989 por variante (Pricing Resilience) em paralelo com a 5354 (localização física dos grupos
 * repetidos), mesma base monetária do Valor estimado total. Só o titular (as RPCs resolvem o dono
 * por `auth.uid()`), nenhum identificador do cliente, somente leitura.
 */
export async function readDuplicatesReport(): Promise<DuplicatesReportLoad> {
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) return { status: "error" };
  const supabase = await createClient();
  try {
    // Miniaturas: mesma origem pública das imagens do Meu acervo (bucket `card-front`, síncrono).
    const imageUrl = (path: string) => supabase.storage.from("card-front").getPublicUrl(path).data.publicUrl ?? null;
    return await getDuplicatesReport(supabase, new Date(), imageUrl);
  } catch (error) {
    console.error("[reports] readDuplicatesReport falhou", { message: error instanceof Error ? error.message : "unknown" });
    return { status: "error" };
  }
}
