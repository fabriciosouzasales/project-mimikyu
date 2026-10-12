"use server";

import { revalidatePath } from "next/cache";
import sharp from "sharp";
import { makeHttp, processSpecies } from "@/scripts/import-pokemon-artwork/artwork-lib.mjs";
import { artworkErrorLabel } from "@/lib/pokedex/admin-artwork-format";
import { getArtworkRow } from "@/lib/pokedex/admin-artwork";
import { formatDexNumber } from "@/lib/pokedex/format";
import { createClient } from "@/lib/supabase/server";

/**
 * Reprocessamento individual da arte de uma espécie (Pokédex P2 Lote E).
 *
 * Reaproveita, sem alterar, o núcleo do importador de linha de comando
 * (`processSpecies` em scripts/import-pokemon-artwork/artwork-lib.mjs):
 * mesma resolução pela PokéAPI, mesmas validações de PNG/WebP, mesmos
 * caminhos imutáveis por checksum (`upsert: false`) e o mesmo registro pelas
 * funções admin da Query 6132.
 *
 * Nenhum privilégio novo: roda no servidor com a SESSÃO do administrador
 * (cookie) — o upload passa pela policy admin do bucket e as RPCs exigem
 * `is_admin()`. Sem `service_role`. A checagem de admin aqui é só para
 * responder cedo; a autoridade é o banco/Storage.
 *
 * Concorrência: um reprocessamento por espécie por instância (trava em
 * memória) + botão desabilitado na interface. Entre instâncias, a operação
 * já é idempotente: mesmo conteúdo → mesmos caminhos → `ALREADY_PRESENT` e
 * registro `UNCHANGED`.
 */

const USER_AGENT = "MMKYU-Collector-artwork-admin/1.0 (+reprocessamento administrativo pontual)";
const inFlight = new Set<number>();

export type ReprocessArtworkResult =
  | { ok: true; number: number; action: "INSERTED" | "RECOVERED" | "REPLACED" | "UNCHANGED"; message: string }
  | {
      ok: false;
      number: number;
      reason: "invalid" | "denied" | "busy" | "needs_confirmation" | "failed" | "error";
      message: string;
      errorCode?: string;
      imagePreserved?: boolean;
    };

const SUCCESS_MESSAGE: Record<string, string> = {
  INSERTED: "imagem importada.",
  RECOVERED: "imagem importada; a falha anterior foi resolvida.",
  REPLACED: "a origem mudou e a nova imagem foi registrada.",
  UNCHANGED: "nada mudou — a imagem na origem é a mesma já registrada.",
};

export async function reprocessSpeciesArtwork(input: {
  nationalDexNumber: number;
  confirmReplace: boolean;
}): Promise<ReprocessArtworkResult> {
  const n = input.nationalDexNumber;
  if (!Number.isInteger(n) || n < 1 || n > 9999) {
    return { ok: false, number: n, reason: "invalid", message: "Número nacional inválido." };
  }
  const label = `Nº ${formatDexNumber(n)}`;

  const supabase = await createClient();
  const [
    {
      data: { user },
    },
    { data: isAdmin },
  ] = await Promise.all([supabase.auth.getUser(), supabase.rpc("is_admin")]);
  if (!user || isAdmin !== true) {
    return { ok: false, number: n, reason: "denied", message: "Acesso restrito a administradores." };
  }

  if (inFlight.has(n)) {
    return { ok: false, number: n, reason: "busy", message: `${label}: já existe um reprocessamento em andamento.` };
  }
  inFlight.add(n);
  const startedAt = Date.now();

  try {
    const current = await getArtworkRow(supabase, n);
    if (!current) {
      return { ok: false, number: n, reason: "invalid", message: `${label}: espécie não encontrada na Pokédex Nacional.` };
    }
    const name = `${label} ${current.species_name}`;

    // Substituir uma imagem válida exige confirmação explícita na interface.
    if (current.artwork_status === "IMPORTED" && !input.confirmReplace) {
      return {
        ok: false,
        number: n,
        reason: "needs_confirmation",
        message: `${name} já tem imagem válida. Confirme para reprocessar.`,
      };
    }

    const record = await processSpecies(
      n,
      { ...makeHttp({ userAgent: USER_AGENT }), sharp, supabase, now: () => new Date() },
      { apply: true, force: current.artwork_status === "IMPORTED", currentStatus: current.artwork_status },
    );

    console.info(
      `[pokedex-imagens] reprocessamento ${label} por ${user.id}: ${record.outcome}${
        record.error_code ? ` (${record.error_code})` : ""
      } em ${Date.now() - startedAt} ms`,
    );

    revalidatePath("/pokedex/imagens");
    revalidatePath("/pokedex");

    const action = record.outcome?.startsWith("IMPORTED_") ? record.outcome.slice("IMPORTED_".length) : null;
    if (action === "INSERTED" || action === "RECOVERED" || action === "REPLACED" || action === "UNCHANGED") {
      return { ok: true, number: n, action, message: `${name}: ${SUCCESS_MESSAGE[action]}` };
    }

    const preserved = record.image_preserved === true || current.artwork_status === "IMPORTED";
    const reason = artworkErrorLabel(record.error_code) ?? "Falha no reprocessamento.";
    return {
      ok: false,
      number: n,
      reason: "failed",
      errorCode: record.error_code,
      imagePreserved: preserved,
      message: `${name}: ${reason}${preserved ? " A imagem anterior foi preservada." : ""}`,
    };
  } catch (error) {
    console.error(`[pokedex-imagens] reprocessamento ${label} abortado: ${error instanceof Error ? error.message : "erro"}`);
    return { ok: false, number: n, reason: "error", message: `${label}: não foi possível concluir. Tente novamente em instantes.` };
  } finally {
    inFlight.delete(n);
  }
}
