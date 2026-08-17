import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/**
 * Opções de filtro (Card Set/Categoria/Raridade — sem Jogo, decisão de escopo
 * desta versão) para `/pesquisa` — usa `public.search_card_filter_options`
 * (ver migration 4031, que corrige a 4020 removendo o parâmetro de Jogo fora
 * de escopo) em vez das queries administrativas existentes
 * (`getCategoriaOptions`/`getRaridades`), que operam sob RLS admin-only e
 * retornariam vazio para um usuário comum autenticado.
 */
export async function GET(_request: NextRequest) {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "not_authenticated" }, { status: 401 });
  }

  const { data, error } = await supabase.rpc("search_card_filter_options");

  if (error) {
    console.error("[api/cards/filter-options] search_card_filter_options RPC error", error);
    return NextResponse.json({ error: "filter_options_failed" }, { status: 500 });
  }

  return NextResponse.json(data);
}
