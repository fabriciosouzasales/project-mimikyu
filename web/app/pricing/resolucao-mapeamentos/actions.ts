"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroPricing } from "@/lib/pricing/pricing-errors";

/**
 * Server Actions do fluxo de Resolução de Mapeamentos (Bloco 2 do Pricing
 * Admin, migration 3940) — mesmo padrão de `app/catalogo/importar-variantes/actions.ts`:
 * arquivo próprio com `"use server"` no topo, retorno sempre
 * `{ error: string | null, ... }` (nunca lança para o componente tratar),
 * erro traduzido via `traduzirErroPricing`, `revalidatePath` nas duas rotas
 * afetadas (a lista de Pendências perde a linha resolvida; a própria tela de
 * Resolução some o mapping já decidido).
 */

export type IdentityAssignmentInput = {
  identityId: string;
  identityRole: "PRIMARY" | "ALTERNATE" | "ALIAS";
  canonicalIdentityId: string | null;
  cardVariantTypeId: string | null;
};

export type ResolvePricingMappingResult =
  | { error: string; decision?: undefined; externalCardId?: undefined }
  | { error: null; decision: "CONFIRMED"; externalCardId: string }
  | { error: null; decision: "REJECTED"; externalCardId?: undefined };

/**
 * Confirma um mapping com 1..N identidades candidatas (single ou
 * multi-identity — mesma RPC atômica para os dois casos). Nunca cria
 * card_variant_type nem toca pricing_product/pricing_observation — só
 * `admin_resolve_pricing_mapping` faz o write, sempre com exatamente 1
 * linha nova em pricing_admin_action_log por decisão.
 */
export async function confirmarMapeamentoPricing(
  mappingId: string,
  assignments: IdentityAssignmentInput[],
): Promise<ResolvePricingMappingResult> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_resolve_pricing_mapping", {
    p_mapping_id: mappingId,
    p_decision: "CONFIRMED",
    p_identity_assignments: assignments.map((a) => ({
      identity_id: a.identityId,
      identity_role: a.identityRole,
      canonical_identity_id: a.canonicalIdentityId,
      card_variant_type_id: a.cardVariantTypeId,
    })),
    p_reject_reason: null,
  });

  if (error) {
    return { error: traduzirErroPricing(error.message) };
  }

  const result = data as { external_card_id: string };
  revalidatePath("/pricing/pendencias");
  revalidatePath("/pricing/resolucao-mapeamentos");
  return { error: null, decision: "CONFIRMED", externalCardId: result.external_card_id };
}

/** Rejeita um mapping — motivo obrigatório, nunca cria identity nova. */
export async function rejeitarMapeamentoPricing(
  mappingId: string,
  rejectReason: string,
): Promise<ResolvePricingMappingResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_resolve_pricing_mapping", {
    p_mapping_id: mappingId,
    p_decision: "REJECTED",
    p_identity_assignments: null,
    p_reject_reason: rejectReason,
  });

  if (error) {
    return { error: traduzirErroPricing(error.message) };
  }

  revalidatePath("/pricing/pendencias");
  revalidatePath("/pricing/resolucao-mapeamentos");
  return { error: null, decision: "REJECTED" };
}
