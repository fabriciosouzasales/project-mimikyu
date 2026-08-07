"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroCatalogo } from "@/lib/supabase/catalogo-errors";
import type { EntityActionState } from "@/lib/catalogo/admin-action-types";

/**
 * Server Actions de escrita da tela Cartas (/catalogo/cartas), novo em
 * 2026-08-07 (pedido de Fabrício: "Encontrei duas cartas cadastradas com a
 * raridade errada. Preciso que implemente uma tela de alteração de dados das
 * cartas... possibilitando editar todas as informações possíveis referente
 * aquela carta específica, incluindo a sua raridade"). Mesma estrutura de
 * `card-sets/actions.ts` (`updateCardSet`): aliasa o tipo de retorno
 * compartilhado (`EntityActionState`), chama a função `admin_*` via RPC e
 * traduz o erro genuíno do Postgres via `traduzirErroCatalogo`.
 *
 * `card_set_id` e `collector_number` nunca são aceitos aqui — imutáveis por
 * decisão já registrada em ADR-023 ("Campos estruturalmente protegidos
 * nunca são alteráveis por atualização"): mudar esses dois campos muda a
 * identidade da Card, não o seu conteúdo — correção é matéria de revisão
 * manual fora da UI, mesmo quando a fonte externa sugerir um número
 * diferente para "a mesma" Card. `is_active` (soft delete) também fica de
 * fora — não pedido, e exclusão de Card é uma ação distinta de edição.
 *
 * Até Fabrício confirmar a execução de `admin_update_card()` (Query 2114,
 * ADR-023) no Supabase, esta action retorna o erro genuíno do Postgres
 * (função inexistente) — mesma situação já vivida por `updateCardSet`/
 * `createCardSet` até suas Queries serem confirmadas.
 */
export type CardActionState = EntityActionState;

export async function updateCard(_prevState: CardActionState, formData: FormData): Promise<CardActionState> {
  const id = String(formData.get("id") ?? "");
  const name = String(formData.get("name") ?? "").trim();
  const collectorTotalRaw = String(formData.get("collector_total") ?? "").trim();
  const collectorOrderRaw = String(formData.get("collector_order") ?? "").trim();
  const collectorOrder = Number(collectorOrderRaw);
  const rarityId = String(formData.get("rarity_id") ?? "");
  const categoryId = String(formData.get("category_id") ?? "");

  if (!id) {
    return { error: "Card inválida." };
  }
  if (!name) {
    return { error: "Informe o nome da carta." };
  }
  if (!collectorOrderRaw || !Number.isInteger(collectorOrder) || collectorOrder <= 0) {
    return { error: "Informe uma ordem editorial válida (número inteiro positivo)." };
  }
  if (!rarityId) {
    return { error: "Selecione a Raridade." };
  }
  if (!categoryId) {
    return { error: "Selecione a Categoria." };
  }

  const collectorTotal = collectorTotalRaw ? Number(collectorTotalRaw) : null;
  if (collectorTotalRaw && (!Number.isInteger(collectorTotal) || (collectorTotal as number) <= 0)) {
    return { error: "Informe um total válido (número inteiro positivo) ou deixe em branco." };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_update_card", {
    p_id: id,
    p_name: name,
    p_collector_total: collectorTotal,
    p_collector_order: collectorOrder,
    p_rarity_id: rarityId,
    p_category_id: categoryId,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/cartas");
  return { error: null, success: true, id };
}
