"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroCatalogo } from "@/lib/supabase/catalogo-errors";
import type { EntityActionState } from "@/lib/catalogo/admin-action-types";

/**
 * Server Actions de escrita da tela Cartas (/catalogo/cartas). Começou em
 * 2026-08-07 só com `updateCard` (pedido de Fabrício: "Encontrei duas cartas
 * cadastradas com a raridade errada... editar todas as informações
 * possíveis referente aquela carta específica, incluindo a sua raridade").
 * Ampliada no mesmo dia, rodada seguinte, com `createCard`/`deactivateCard`/
 * `reactivateCard` — fecha o subciclo Card do ADR-023 ("criação e
 * desativação/reativação administrativa"). Mesma estrutura de
 * `card-sets/actions.ts`: aliasa o tipo de retorno compartilhado
 * (`EntityActionState`), chama a função `admin_*` via RPC e traduz o erro
 * genuíno do Postgres via `traduzirErroCatalogo`.
 *
 * `card_set_id` e `collector_number` só são aceitos por `createCard` — em
 * `updateCard` continuam de fora por decisão já registrada em ADR-023
 * ("Campos estruturalmente protegidos nunca são alteráveis por
 * atualização"): mudar esses dois campos muda a identidade da Card, não o
 * seu conteúdo — correção é matéria de revisão manual fora da UI, mesmo
 * quando a fonte externa sugerir um número diferente para "a mesma" Card.
 * `is_active` (soft delete) nunca é aceito por `updateCard` nem `createCard`
 * — é responsabilidade exclusiva de `deactivateCard`/`reactivateCard`.
 */
export type CardActionState = EntityActionState;

/**
 * Cadastra uma nova Card via admin_create_card() (Query 2115, ADR-023) —
 * fecha o subciclo Card junto com `deactivateCard`/`reactivateCard` abaixo
 * (2026-08-07). Diferente de `updateCard`, aceita `card_set_id` e
 * `collector_number` — aqui esses dois campos definem a identidade da Card
 * sendo criada, não algo a proteger contra alteração (essa proteção só se
 * aplica depois que a Card já existe, ver comentário de `updateCard`
 * abaixo).
 *
 * Validação de consistência de Game (Raridade/Categoria pertencerem ao
 * mesmo Game do Card Set) e de duplicidade de número/ordem (considerando
 * Cards ativas E inativas) vivem inteiramente no banco (Query 2115) — esta
 * action só valida formato local (campos obrigatórios, números positivos)
 * e traduz o erro genuíno do Postgres via `traduzirErroCatalogo`.
 */
export async function createCard(_prevState: CardActionState, formData: FormData): Promise<CardActionState> {
  const cardSetId = String(formData.get("card_set_id") ?? "");
  const collectorNumber = String(formData.get("collector_number") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const collectorTotalRaw = String(formData.get("collector_total") ?? "").trim();
  const collectorOrderRaw = String(formData.get("collector_order") ?? "").trim();
  const collectorOrder = Number(collectorOrderRaw);
  const rarityId = String(formData.get("rarity_id") ?? "");
  const categoryId = String(formData.get("category_id") ?? "");

  if (!cardSetId) {
    return { error: "Card Set inválido." };
  }
  if (!collectorNumber) {
    return { error: "Informe o número da carta." };
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
  const { data, error } = await supabase.rpc("admin_create_card", {
    p_card_set_id: cardSetId,
    p_collector_number: collectorNumber,
    p_collector_total: collectorTotal,
    p_collector_order: collectorOrder,
    p_rarity_id: rarityId,
    p_category_id: categoryId,
    p_name: name,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/cartas");
  return { error: null, success: true, id: data as string };
}

/**
 * Desativa (soft delete real e irrestrito, ADR-023) uma Card via
 * admin_deactivate_card() (Query 2116). Chamada diretamente pelo componente
 * de confirmação — mesmo padrão de `setCardSetLogo()` (`card-sets/actions.ts`):
 * função simples de um único campo, sem `useActionState`/`<form>`, porque não
 * há nada além do `id` para validar no lado do cliente.
 */
export async function deactivateCard(id: string): Promise<{ error: string | null }> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_deactivate_card", { p_id: id });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/cartas");
  return { error: null };
}

/**
 * Reativa uma Card via admin_reactivate_card() (Query 2117) — espelho exato
 * de `deactivateCard` acima.
 */
export async function reactivateCard(id: string): Promise<{ error: string | null }> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_reactivate_card", { p_id: id });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/cartas");
  return { error: null };
}

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
