"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroCatalogo } from "@/lib/supabase/catalogo-errors";
import { ManualAssetImportError, resolveManualAssetCard } from "@/lib/catalogo/manual-asset-import/core";

/**
 * Server Actions do modo Manual da tela `/catalogo/importar-imagens`
 * (ADR-026, emenda "Segundo ponto de entrada via UI", 2026-08-08) —
 * arquivo separado de `tcgdex/actions.ts` (que hospeda o modo API/TCGdex já
 * existente, intocado) para não misturar dois assuntos sem relação na mesma
 * origem de imports.
 *
 * Os bytes do arquivo NUNCA passam por aqui — o navegador já subiu o arquivo
 * direto para o Storage (`card-front`, políticas `card_front_admin_insert`/
 * `_delete`, Query 2119) antes de chamar `persistirImagemManual`. Esta
 * action só resolve metadados (usando a sessão real do administrador, nunca
 * a Service Role Key) e chama `admin_persist_manual_card_asset()` (Query
 * 2120), que faz a validação final de invariantes e o upsert.
 */

export type PersistirImagemManualResult = {
  error: string | null;
  action: "INSERTED" | "UPDATED" | null;
  /** Path anterior do Card Front nesse idioma, se havia — o cliente só remove este arquivo do Storage DEPOIS de receber isto com sucesso (nunca antes, ver ADR-026). `null` quando a linha era nova. */
  previousStoragePath: string | null;
};

export async function persistirImagemManual(params: {
  cardSetId: string;
  cardSetCode: string;
  languageCode: string;
  collectorNumber: string;
  storagePath: string;
  mimeType: string;
  fileExtension: string;
  fileSizeBytes: number;
  checksumSha256: string;
}): Promise<PersistirImagemManualResult> {
  const supabase = await createClient();

  let cardId: string;

  try {
    const resolved = await resolveManualAssetCard(supabase, {
      cardSetCode: params.cardSetCode,
      collectorNumber: params.collectorNumber,
      languageCode: params.languageCode,
    });
    cardId = resolved.card.id;
  } catch (error) {
    const message =
      error instanceof ManualAssetImportError
        ? error.message
        : error instanceof Error
          ? error.message
          : "Falha ao resolver a Carta.";
    return { error: message, action: null, previousStoragePath: null };
  }

  const { data, error } = await supabase.rpc("admin_persist_manual_card_asset", {
    p_card_id: cardId,
    p_card_set_id: params.cardSetId,
    p_language_code: params.languageCode,
    p_storage_path: params.storagePath,
    p_mime_type: params.mimeType,
    p_file_extension: params.fileExtension,
    p_file_size_bytes: params.fileSizeBytes,
    p_checksum_sha256: params.checksumSha256,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message), action: null, previousStoragePath: null };
  }

  const [row] = (data ?? []) as { action: "INSERTED" | "UPDATED"; previous_storage_path: string | null }[];

  return {
    error: null,
    action: row?.action ?? null,
    previousStoragePath: row?.previous_storage_path ?? null,
  };
}

export type FalhaImportacaoManual = {
  collectorNumber: string;
  fileName: string;
  error: string;
};

export type FecharLoteImportacaoManualResult = {
  error: string | null;
  logId: string | null;
};

/**
 * Fecha o lote inteiro (chamada única, não por arquivo) — grava a auditoria
 * agregada via `admin_log_manual_card_asset_import_batch()` (Query 2122).
 * `runId` é gerado no navegador (`crypto.randomUUID()`) antes do primeiro
 * arquivo do lote e repassado aqui, sem uso funcional além de identificar o
 * lote na auditoria.
 */
export async function fecharLoteImportacaoManual(params: {
  cardSetId: string;
  languageCode: string;
  runId: string;
  filesTotal: number;
  insertedCount: number;
  updatedCount: number;
  failedCount: number;
  failures: FalhaImportacaoManual[];
}): Promise<FecharLoteImportacaoManualResult> {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("admin_log_manual_card_asset_import_batch", {
    p_card_set_id: params.cardSetId,
    p_language_code: params.languageCode,
    p_run_id: params.runId,
    p_files_total: params.filesTotal,
    p_inserted_count: params.insertedCount,
    p_updated_count: params.updatedCount,
    p_failed_count: params.failedCount,
    p_failures: params.failures,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message), logId: null };
  }

  revalidatePath("/catalogo/importar-imagens");
  revalidatePath("/catalogo/cartas");

  return { error: null, logId: (data as string) ?? null };
}
