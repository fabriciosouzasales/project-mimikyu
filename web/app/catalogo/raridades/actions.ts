"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroCatalogo } from "@/lib/supabase/catalogo-errors";
import type { DeleteEntitiesActionState, EntityActionState } from "@/lib/catalogo/admin-action-types";

/**
 * Server Actions da tela /catalogo/raridades (task #336, ciclo de cadastro
 * self-service de Raridade — ver `docs/log.md` 2026-08-06/07).
 *
 * Jogo/Fonte externa não são campos do formulário: o catálogo hoje tem um
 * único Game real (POKEMON) e uma única fonte ativa de importação de cartas
 * (TCGDEX) — resolvidos aqui, não pedidos ao administrador. Se um segundo
 * Jogo/fonte externa entrar em cena, isso precisa virar campo de formulário;
 * sinalizado, não resolvido preventivamente (mesmo critério já usado em
 * outras telas do módulo, ex. `getJogos`, "só 1 registro hoje").
 */

async function resolveGameId(supabase: Awaited<ReturnType<typeof createClient>>): Promise<string | null> {
  const { data } = await supabase.from("game").select("id").limit(1).maybeSingle();
  return data?.id ?? null;
}

async function resolveAssetSourceId(
  supabase: Awaited<ReturnType<typeof createClient>>,
  code: string,
): Promise<string | null> {
  const { data } = await supabase.from("asset_source").select("id").eq("code", code).maybeSingle();
  return data?.id ?? null;
}

export type RarityActionState = EntityActionState;
export type DeleteRaridadesActionState = DeleteEntitiesActionState;

/**
 * Cadastra uma raridade canônica nova junto com seu primeiro mapeamento
 * externo, atomicamente, via admin_create_rarity_with_external_mapping()
 * (Query 2103).
 */
export async function createRarityWithMapping(
  _prevState: RarityActionState,
  formData: FormData,
): Promise<RarityActionState> {
  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const symbolCode = String(formData.get("symbolCode") ?? "").trim();
  const displayOrder = Number.parseInt(String(formData.get("displayOrder") ?? ""), 10);
  const externalValue = String(formData.get("externalValue") ?? "").trim();

  if (!code) return { error: "Informe o código da raridade." };
  if (!name) return { error: "Informe o nome da raridade." };
  if (!symbolCode) return { error: "Escolha um símbolo." };
  if (!Number.isFinite(displayOrder)) return { error: "Ordem de exibição inválida." };
  if (!externalValue) return { error: "Informe o valor exatamente como aparece na fonte externa." };

  const supabase = await createClient();
  const gameId = await resolveGameId(supabase);
  const assetSourceId = await resolveAssetSourceId(supabase, "TCGDEX");

  if (!gameId || !assetSourceId) {
    return { error: "Não foi possível resolver Jogo/fonte externa. Verifique o cadastro base." };
  }

  const { data, error } = await supabase.rpc("admin_create_rarity_with_external_mapping", {
    p_game_id: gameId,
    p_code: code,
    p_name: name,
    p_symbol_code: symbolCode,
    p_display_order: displayOrder,
    p_asset_source_id: assetSourceId,
    p_external_value: externalValue,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  const result = Array.isArray(data) ? data[0] : data;
  revalidatePath("/catalogo/raridades");
  return { error: null, success: true, id: result?.rarity_id as string | undefined };
}

/**
 * Vincula um novo valor externo a uma raridade canônica já existente, via
 * admin_create_rarity_external_mapping() (Query 2101) — caminho mais curto
 * para o caso comum de "a raridade já existe, só falta esse sinônimo"
 * (ex.: RARE_HOLO já cadastrada com "Rare Holo", faltando "Rara Holo").
 */
export async function createRarityMapping(
  _prevState: RarityActionState,
  formData: FormData,
): Promise<RarityActionState> {
  const rarityId = String(formData.get("rarityId") ?? "").trim();
  const externalValue = String(formData.get("externalValue") ?? "").trim();

  if (!rarityId) return { error: "Escolha a raridade existente." };
  if (!externalValue) return { error: "Informe o valor exatamente como aparece na fonte externa." };

  const supabase = await createClient();
  const gameId = await resolveGameId(supabase);
  const assetSourceId = await resolveAssetSourceId(supabase, "TCGDEX");

  if (!gameId || !assetSourceId) {
    return { error: "Não foi possível resolver Jogo/fonte externa. Verifique o cadastro base." };
  }

  const { data, error } = await supabase.rpc("admin_create_rarity_external_mapping", {
    p_game_id: gameId,
    p_asset_source_id: assetSourceId,
    p_rarity_id: rarityId,
    p_external_value: externalValue,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/raridades");
  return { error: null, success: true, id: data as string | undefined };
}

/**
 * Atualiza nome/símbolo/ordem de uma raridade já cadastrada via
 * admin_update_rarity() (Query 2100). Código é imutável (a função nem
 * recebe esse parâmetro), mesmo critério de Jogo/Expansão/Coleção.
 */
export async function updateRarity(_prevState: RarityActionState, formData: FormData): Promise<RarityActionState> {
  const id = String(formData.get("id") ?? "");
  const name = String(formData.get("name") ?? "").trim();
  const symbolCode = String(formData.get("symbolCode") ?? "").trim();
  const displayOrder = Number.parseInt(String(formData.get("displayOrder") ?? ""), 10);

  if (!id) return { error: "Raridade inválida." };
  if (!name) return { error: "Informe o nome da raridade." };
  if (!symbolCode) return { error: "Escolha um símbolo." };
  if (!Number.isFinite(displayOrder)) return { error: "Ordem de exibição inválida." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_update_rarity", {
    p_id: id,
    p_name: name,
    p_symbol_code: symbolCode,
    p_display_order: displayOrder,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/raridades");
  return { error: null, success: true, id };
}

export type RevalidarTudoState = {
  error: string | null;
  success?: boolean;
  jobsProcessados?: number;
  linhasAtualizadas?: number;
  linhasDestravadas?: number;
  falhas?: { jobId: string; erro: string }[];
};

/**
 * Dispara revalidate-catalog-import-rows (Edge Function, `verify_jwt:
 * true`) sem `job_ids` — revalida TODOS os jobs hoje elegíveis (`STAGED`/
 * `CONFIRMING`/`COMPLETED_WITH_ERRORS`) numa única chamada, em vez de job
 * por job (decisão de Fabrício, 2026-08-07, antes desta tela nascer).
 *
 * A Edge Function autentica o chamador pelo próprio JWT (auth.getUser() +
 * is_admin()) e deriva o actor_id gravado em catalog_admin_action_log a
 * partir dessa sessão — o access_token repassado aqui só prova quem está
 * chamando, nunca declara um actor_id (revisão de segurança do mesmo dia,
 * Query 2106 v1.1).
 */
export async function revalidarTudo(
  _prevState: RevalidarTudoState,
  _formData: FormData,
): Promise<RevalidarTudoState> {
  const supabase = await createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return { error: "Sessão inválida. Faça login novamente." };
  }

  const functionUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/revalidate-catalog-import-rows`;

  let response: Response;
  try {
    response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({}),
    });
  } catch {
    return { error: "Não foi possível contatar o serviço de revalidação. Tente novamente." };
  }

  const result = await response.json().catch(() => null);

  if (!response.ok || !result?.success) {
    return { error: result?.error ?? `Falha inesperada (HTTP ${response.status}).` };
  }

  const results = (result.results ?? []) as Array<{
    job_id: string;
    rows_updated: number;
    rows_unblocked: number;
    error: string | null;
  }>;

  const falhas = results
    .filter((r) => r.error)
    .map((r) => ({ jobId: r.job_id, erro: r.error as string }));
  const linhasAtualizadas = results.reduce((sum, r) => sum + (r.rows_updated ?? 0), 0);
  const linhasDestravadas = results.reduce((sum, r) => sum + (r.rows_unblocked ?? 0), 0);

  revalidatePath("/catalogo/raridades");
  revalidatePath("/catalogo/importar-cartas");

  return {
    error: null,
    success: true,
    jobsProcessados: result.jobs_processed ?? results.length,
    linhasAtualizadas,
    linhasDestravadas,
    falhas: falhas.length > 0 ? falhas : undefined,
  };
}
