"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroCatalogo } from "@/lib/supabase/catalogo-errors";
import { searchTcgdexSetsManually, type TcgdexSetCandidate } from "@/lib/catalogo/tcgdex-lookup";

/**
 * Server Actions do fluxo de importação via TCGdex (Ciclo 2, ADR-024),
 * adicionadas em 2026-08-01.
 */

export type IniciarImportacaoTcgdexActionState = { error: string | null };

/**
 * Inicia o fluxo de importação para uma Coleção: abre o job
 * (admin_start_catalog_import, Query 2080) e invoca a Edge Function
 * processadora (import-catalog-cards, Ciclo 2 Sprint 1) — aguarda a
 * resposta antes de redirecionar (chamada síncrona; para Coleções muito
 * grandes isso pode se aproximar do limite de execução — risco já
 * sinalizado no plano do Ciclo 2, não resolvido preventivamente aqui).
 *
 * external_set_id chega já resolvido pelo formulário (localização
 * automática ou escolha manual em MatchResultPanel/ManualSearchPanel) —
 * esta action nunca pede esse valor ao administrador.
 */
export async function iniciarImportacaoTcgdex(
  _prevState: IniciarImportacaoTcgdexActionState,
  formData: FormData,
): Promise<IniciarImportacaoTcgdexActionState> {
  const cardSetId = String(formData.get("card_set_id") ?? "");
  const externalSetId = String(formData.get("external_set_id") ?? "").trim();

  if (!cardSetId) {
    return { error: "Selecione uma Coleção." };
  }
  if (!externalSetId) {
    return { error: "Não foi possível determinar o Set da TCGdex." };
  }

  const supabase = await createClient();
  const { data: jobId, error } = await supabase.rpc("admin_start_catalog_import", {
    p_card_set_id: cardSetId,
    p_source: "TCGDEX",
    p_external_set_id: externalSetId,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  const functionUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/import-catalog-cards`;

  let response: Response;
  try {
    response = await fetch(functionUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ job_id: jobId }),
    });
  } catch (fetchError) {
    const message = fetchError instanceof Error ? fetchError.message : "Falha de rede.";
    return { error: `Falha ao chamar o processador: ${message}` };
  }

  if (!response.ok) {
    const body = await response.json().catch(() => null);
    return { error: `Falha ao processar a importação: ${body?.error ?? response.status}` };
  }

  redirect(`/catalogo/importar-cartas/tcgdex/${jobId}`);
}

/**
 * Busca manual de Sets na TCGdex por nome — chamada diretamente do
 * componente cliente (sem formulário), usada só quando a localização
 * automática não resolve sozinha (ambígua ou sem correspondência).
 */
export async function buscarSetsTcgdexManualmente(query: string): Promise<TcgdexSetCandidate[]> {
  return searchTcgdexSetsManually(query);
}
