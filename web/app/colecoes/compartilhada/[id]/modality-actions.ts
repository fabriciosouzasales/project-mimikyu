"use server";

import { isCollectionId } from "@/lib/colecoes/colecoes";
import { editorCurationFlagOn } from "@/lib/colecoes/editor-binder";
import type { PokedexFilter, PokedexPositionsPage } from "@/lib/colecoes/pokedex";
import { validSharedOffset } from "@/lib/colecoes/shared-modalities";
import { getSharedPokedexPositions } from "@/lib/colecoes/shared-modalities-queries";
import { createClient } from "@/lib/supabase/server";

/**
 * V1-13 · E3-6 — "Mostrar mais Pokémon" do participante (5324, só leitura).
 * Configuração D-E3-1 conferida antes de qualquer chamada; o banco decide o
 * acesso (sem acesso ou barreira fechada → zero linhas). Sem geração: a
 * grade do participante não filtra por geração.
 */
export async function loadMoreSharedPokedexPositions(input: {
  collectionId: string;
  filter: PokedexFilter;
  generation: string | null;
  offset: number;
}): Promise<{ ok: true; page: PokedexPositionsPage } | { ok: false; reason: "disabled" | "invalid" | "unavailable" }> {
  if (!editorCurationFlagOn(process.env)) return { ok: false, reason: "disabled" };
  const filter = input?.filter;
  if (!isCollectionId(input?.collectionId) || (filter !== "todas" && filter !== "tenho" && filter !== "faltam") || input.generation !== null || !validSharedOffset(input.offset)) {
    return { ok: false, reason: "invalid" };
  }
  const supabase = await createClient();
  const page = await getSharedPokedexPositions(supabase, input.collectionId.toLowerCase(), filter, input.offset);
  if (page === null) return { ok: false, reason: "unavailable" };
  // Zero linhas depois de uma página com dados: acesso ou barreira mudou — nunca "fim" silencioso.
  if (page.items.length === 0) return { ok: false, reason: "unavailable" };
  return { ok: true, page };
}
