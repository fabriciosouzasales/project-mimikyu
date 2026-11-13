import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type ConditionTally,
  PAGE_CONDITION_READ_MAX,
  type PageConditionGroup,
  pageConditionMix,
} from "./condition-distribution.ts";

/**
 * V1-16 UX-C (G1) — resumo de condições da página do Meu acervo.
 *
 * UMA leitura por página, em paralelo com preço/favoritos/desejos: os
 * exemplares NÃO-NM (`condition_code <> 'NM'`) das variantes exibidas (≤ 48),
 * direto em `physical_card` sob a RLS `physical_card_select_own` (só o
 * inventário do usuário da sessão; `anon` sem grant). Só três colunas, sem id
 * de exemplar. `count: "exact"` prova que a resposta veio inteira; acima de
 * `PAGE_CONDITION_READ_MAX` a página fica sem resumo. `get_my_inventory_items`
 * não muda. Índice: `ix_physical_card_inventory_variant`.
 *
 * Grupo sem nenhum não-NM numa leitura completa = todo NM (`NM ×N`, UX-C
 * CORRECTION-01). Falha, resposta incompleta ou incoerente → `null` ou grupos
 * ausentes (nunca NM presumido): a
 * galeria segue igual, só sem os chips; a causa vai para o log, sem dados do
 * usuário.
 */
export async function getPageConditionMix(
  supabase: SupabaseClient,
  groups: readonly PageConditionGroup[],
  languages: readonly { id: string; code: string }[],
): Promise<Map<string, ConditionTally> | null> {
  if (groups.length === 0) return new Map();
  const startedAt = Date.now();
  if (languages.length === 0) {
    log(startedAt, "NO_LANGUAGES", 0, []);
    return null;
  }
  const variantIds = [...new Set(groups.map((g) => g.cardVariantId.toLowerCase()))];
  try {
    const { data, error, count } = await supabase
      .from("physical_card")
      .select("card_variant_id, language_id, condition_code", { count: "exact" })
      .in("card_variant_id", variantIds)
      .neq("condition_code", "NM")
      .limit(PAGE_CONDITION_READ_MAX);
    if (error || !Array.isArray(data)) {
      log(startedAt, error?.code ?? "NO_DATA", 0, []);
      return null;
    }
    const { mix, issues } = pageConditionMix({ groups, languages, rows: data, count });
    if (issues.length > 0) log(startedAt, "PARTIAL", data.length, issues);
    return mix;
  } catch {
    log(startedAt, "THROWN", 0, []);
    return null;
  }
}

function log(startedAt: number, code: string, rows: number, issues: readonly string[]) {
  console.error(JSON.stringify({ scope: "acervo.read", fn: "physical_card.condition_mix", ms: Date.now() - startedAt, code, rows, issues }));
}
