import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { VARIANT_PRICING_MAX_BODY_BYTES, parseVariantPrices, validateVariantIdsBody } from "@/lib/pricing/variant-pricing";
import { readJsonBodyWithLimit } from "@/lib/pricing/variant-pricing-request";

export const dynamic = "force-dynamic";

const NO_STORE = { "Cache-Control": "private, no-store" } as const;

function reject(status: number, error: string) {
  return NextResponse.json({ error }, { status, headers: NO_STORE });
}

/**
 * Preço NM por variante em lote para o fichário do dono (V1-09, A2 + C2).
 *
 * POST { variantIds: uuid[] } → { results: Record<variantId, preço da 3983> }.
 * Ordem (deny by default, barato primeiro):
 *  1. sessão — sem usuário, 401 antes de ler o corpo;
 *  2. corpo limitado a 20 000 bytes (Content-Length e leitura incremental), 413
 *     acima disso; Content-Type não JSON, 415; vazio ou JSON malformado, 400;
 *  3. estrutura — objeto com `variantIds` não vazio; até 400 entradas brutas
 *     (`too_many_entries`), só UUIDs, até 100 distintos (`too_many_variant_ids`);
 *     repetições colapsam.
 * Nunca `service_role`: a leitura usa a sessão do próprio usuário (a 3983
 * também exige `auth.uid()`). Só preço de catálogo trafega; o erro do banco
 * nunca é repassado ao cliente.
 */
export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return reject(401, "not_authenticated");

  const read = await readJsonBodyWithLimit(request.headers, request.body, VARIANT_PRICING_MAX_BODY_BYTES);
  if (!read.ok) return reject(read.status, read.error);

  const valid = validateVariantIdsBody(read.value);
  if (!valid.ok) return reject(400, valid.error);

  const { data, error } = await supabase.rpc("get_card_variants_pricing_summary", { p_card_variant_ids: valid.ids });
  if (error) {
    console.error(JSON.stringify({ scope: "api.colecoes.precos", code: error.code ?? "UNKNOWN", ids: valid.ids.length }));
    return reject(502, "pricing_unavailable");
  }
  const parsed = parseVariantPrices(data);
  if (!parsed) return reject(502, "pricing_unavailable");
  return NextResponse.json({ results: Object.fromEntries(parsed) }, { headers: NO_STORE });
}
