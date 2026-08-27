"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroPricing } from "@/lib/pricing/pricing-errors";

/**
 * Server Actions do fluxo de Resolução de Mapeamentos (Bloco 2 do Pricing
 * Admin, migration 3940; extensão NOT_FOUND manual, migration 3963) — mesmo
 * padrão de `app/catalogo/importar-variantes/actions.ts`: arquivo próprio
 * com `"use server"` no topo, erro sempre `{ error: string, ... }` (nunca
 * lança para o componente tratar), traduzido via `traduzirErroPricing`.
 *
 * Decisão terminal bem-sucedida (CONFIRMED/REJECTED/NOT_FOUND) termina com
 * `redirect("/pricing/mapeamentos-cartas")` — nunca com um `return` normal
 * (2026-08-27, correção de gap de UX, 2ª rodada). Uma primeira correção
 * (remover `router.refresh()` do componente cliente e navegar via
 * `router.push` num `useEffect` local) não resolveu o problema: confirmado
 * por Fabrício, mesmo print, "continua o mesmo comportamento". Causa raiz
 * real, confirmada em docs oficiais do Next.js: uma Server Action sempre
 * re-renderiza a rota que a invocou como parte do próprio protocolo (a
 * resposta da action inclui um RSC Payload novo dessa rota) — isso
 * independe de qualquer `revalidatePath`/`router.refresh()`/`router.push()`
 * explícito no componente cliente. Como o `match_status` já mudou, `page.tsx`
 * recalculava e trocava para o Alert "já foi decidido" antes que qualquer
 * navegação client-side tivesse chance de agir. `redirect()` chamado
 * DENTRO da própria action evita esse re-render por completo: o Next.js
 * intercepta a exceção especial que `redirect()` lança e devolve uma
 * instrução de navegação direta ao destino, sem nunca chegar a renderizar
 * esta rota de novo com o status já mudado. Por isso as 4 funções abaixo
 * não retornam mais um resultado de sucesso ao chamador — só erro (que não
 * chama `redirect`, então continua resolvendo normalmente para o
 * componente mostrar o Alert local).
 */

export type IdentityAssignmentInput = {
  identityId: string;
  identityRole: "PRIMARY" | "ALTERNATE" | "ALIAS";
  canonicalIdentityId: string | null;
  cardVariantTypeId: string | null;
};

/**
 * Só o caminho de erro é de fato retornado ao chamador — toda decisão
 * bem-sucedida termina em `redirect()` (ver comentário do arquivo), então
 * o componente cliente nunca recebe um valor de sucesso resolvido.
 */
export type ResolvePricingMappingResult = { error: string };

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
  const { error } = await supabase.rpc("admin_resolve_pricing_mapping", {
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

  revalidatePath("/pricing/mapeamentos-cartas");
  redirect("/pricing/mapeamentos-cartas");
}

/**
 * Confirma um mapping a partir de um candidato bruto de
 * `match_evidence.candidatos` (migration 3964) — caso AMBIGUOUS típico:
 * nenhuma `pricing_source_card_identity` foi materializada ainda para os
 * candidatos não escolhidos. O backend valida o `candidateExternalCardId`
 * contra o próprio `match_evidence` do mapping antes de escrever, cria (ou
 * reutiliza, se já existir) SOMENTE a identity escolhida, e confirma o
 * mapping na mesma transação. Distinto de `confirmarMapeamentoPricing`:
 * aquele exige 1..N identities PENDING já persistidas; este nunca depende
 * de identity pré-existente.
 */
export async function confirmarCandidatoMapeamentoPricing(
  mappingId: string,
  candidateExternalCardId: string,
): Promise<ResolvePricingMappingResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_resolve_pricing_mapping", {
    p_mapping_id: mappingId,
    p_decision: "CONFIRMED",
    p_identity_assignments: null,
    p_reject_reason: null,
    p_candidate_external_card_id: candidateExternalCardId,
  });

  if (error) {
    return { error: traduzirErroPricing(error.message) };
  }

  revalidatePath("/pricing/mapeamentos-cartas");
  redirect("/pricing/mapeamentos-cartas");
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

  revalidatePath("/pricing/mapeamentos-cartas");
  redirect("/pricing/mapeamentos-cartas");
}

/**
 * Marca um mapping PENDING sem candidata alguma (`identities.length === 0`)
 * como NOT_FOUND — busca concluída sem correspondência nesta fonte, motivo
 * obrigatório, nunca cria identity, nunca preenche confirmed_at/confirmed_by
 * (migration 3963). Distinto de rejeitarMapeamentoPricing: REJECTED é "um
 * candidato específico foi rejeitado", NOT_FOUND é "nenhum candidato
 * existiu" — só faz sentido quando a carta não tem nenhuma candidata.
 */
export async function marcarMapeamentoComoNaoEncontrado(
  mappingId: string,
  reason: string,
): Promise<ResolvePricingMappingResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_resolve_pricing_mapping", {
    p_mapping_id: mappingId,
    p_decision: "NOT_FOUND",
    p_identity_assignments: null,
    p_reject_reason: reason,
  });

  if (error) {
    return { error: traduzirErroPricing(error.message) };
  }

  revalidatePath("/pricing/mapeamentos-cartas");
  redirect("/pricing/mapeamentos-cartas");
}
