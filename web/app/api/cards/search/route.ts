import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const DEFAULT_LIMIT = 36;
const MAX_LIMIT = 60;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type SearchCardsRow = {
  card_id: string;
  card_name: string;
  collector_number: string;
  collector_total: number | null;
  card_set_id: string;
  card_set_code: string;
  card_set_name: string;
  category_id: string | null;
  category_code: string | null;
  category_name: string | null;
  rarity_id: string | null;
  rarity_code: string | null;
  rarity_name: string | null;
  rarity_symbol_code: string | null;
  image_path_pt: string | null;
  image_path_en: string | null;
  total_count: number;
};

/**
 * Rota autenticada de pesquisa global de cartas — Incremento "Pesquisa Global
 * de Cartas" (2026-08-17, ver ADR-030). Único ponto de entrada HTTP para a
 * função `public.search_cards` (SECURITY DEFINER, ver migration 4030 —
 * corrige a 4010, que havia incluído indevidamente um filtro de Jogo fora do
 * escopo aprovado): usa o client autenticado (cookies da sessão via
 * `createClient()`), nunca `service_role`; parâmetros vão via `.rpc()`
 * (bind, sem interpolação de texto livre em filtro PostgREST). Alimenta
 * tanto o combobox do header (poucos resultados, sem filtros) quanto a
 * página `/pesquisa` (paginado, com filtros de Card Set/Categoria/Raridade
 * — sem Jogo, decisão de escopo desta versão).
 */
export async function GET(request: NextRequest) {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  }

  const searchParams = request.nextUrl.searchParams;

  const qRaw = searchParams.get("q");
  const q = qRaw && qRaw.trim().length > 0 ? qRaw.trim().slice(0, 200) : null;

  const cardIdRaw = searchParams.get("card");
  const cardId = cardIdRaw && UUID_RE.test(cardIdRaw) ? cardIdRaw : null;

  const cardSetCode = searchParams.get("set")?.trim().slice(0, 50) || null;
  const categoryCode = searchParams.get("category")?.trim().slice(0, 50) || null;
  const rarityCode = searchParams.get("rarity")?.trim().slice(0, 50) || null;

  const limitParam = Number.parseInt(searchParams.get("limit") ?? "", 10);
  const limit = Number.isFinite(limitParam) ? Math.min(Math.max(limitParam, 1), MAX_LIMIT) : DEFAULT_LIMIT;

  const offsetParam = Number.parseInt(searchParams.get("offset") ?? "", 10);
  const offset = Number.isFinite(offsetParam) && offsetParam > 0 ? offsetParam : 0;

  // Nada para pesquisar: sem termo, sem carta fixada e sem nenhum filtro —
  // evita ida ao banco para um estado inicial vazio (ex.: combobox recém-aberto).
  if (!q && !cardId && !cardSetCode && !categoryCode && !rarityCode) {
    return NextResponse.json({ cards: [], totalCount: 0, hasMore: false });
  }

  const { data, error } = await supabase.rpc("search_cards", {
    p_query: q,
    p_card_id: cardId,
    p_card_set_code: cardSetCode,
    p_category_code: categoryCode,
    p_rarity_code: rarityCode,
    p_limit: limit,
    p_offset: offset,
  });

  if (error) {
    console.error("[api/cards/search] search_cards RPC error", error);
    return NextResponse.json({ error: "search_failed" }, { status: 500 });
  }

  const rows = (data ?? []) as SearchCardsRow[];
  const totalCount = rows[0]?.total_count ?? 0;

  const cards = rows.map((row) => ({
    id: row.card_id,
    name: row.card_name,
    collectorNumber: row.collector_number,
    collectorTotal: row.collector_total,
    cardSet: { id: row.card_set_id, code: row.card_set_code, name: row.card_set_name },
    category: row.category_code ? { id: row.category_id, code: row.category_code, name: row.category_name } : null,
    rarity: row.rarity_code
      ? { id: row.rarity_id, code: row.rarity_code, name: row.rarity_name, symbolCode: row.rarity_symbol_code }
      : null,
    imageUrlPt: row.image_path_pt
      ? supabase.storage.from("card-front").getPublicUrl(row.image_path_pt).data.publicUrl
      : null,
    imageUrlEn: row.image_path_en
      ? supabase.storage.from("card-front").getPublicUrl(row.image_path_en).data.publicUrl
      : null,
  }));

  return NextResponse.json({
    cards,
    totalCount,
    hasMore: offset + cards.length < totalCount,
  });
}
