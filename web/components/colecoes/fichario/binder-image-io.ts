"use client";

import {
  clearSlotImage,
  listUnlinkedSlotImages,
  mergeSlotsWithImage,
  separateSlots,
  setRegionImage,
  setSlotImage,
} from "@/app/colecoes/colecoes/[id]/fichario/actions";
import {
  ENCODE_LADDER,
  type ImageFailure,
  SLOT_IMAGE_BUCKET,
  SLOT_IMAGE_MAX_BYTES,
  type SetImageResult,
  acceptedOutputType,
  buildSlotImagePath,
  checkSourceFile,
  classifyUploadError,
  fitWithin,
  imageFailureMessage,
  isDefiniteRefusal,
  sourceCheckMessage,
  uploadFailureMessage,
} from "@/lib/colecoes/binder-images";
import { type RegionFailure, isDefiniteRegionRefusal, regionFailureMessage } from "@/lib/colecoes/binder-region";
import { createClient } from "@/lib/supabase/client";

/**
 * Imagem do bolso no navegador (C-198): preparar, enviar, vincular, remover.
 *
 * Ordem segura (mesma família do avatar e da capa, endurecida pela
 * AUDIT-CORRECTION-01 da proposta 5231–5236):
 *   1. o arquivo é relido num canvas (sai sem EXIF/GPS), reduzido a no
 *      máximo 900×1800 e codificado em WebP (JPEG se o navegador não gera
 *      WebP) até caber em 512 KB;
 *   2. é enviado para um caminho NOVO (`upsert: false` — o bucket não tem
 *      UPDATE, sobrescrever é impossível);
 *   3. o banco vincula (5233), conferindo dono, pasta, tipo e tamanho;
 *   4. só depois da resposta:
 *      - sucesso com troca → apaga o arquivo ANTERIOR;
 *      - recusa definitiva → apaga só o arquivo que acabou de enviar;
 *      - resposta incerta (rede, tempo esgotado) → não apaga nada; a tela
 *        relê o bolso. Sobra, no máximo, um arquivo sem vínculo, que a
 *        limpeza (5234, > 1 h) recolhe depois.
 *   A política DELETE do bucket recusa apagar arquivo vinculado — mesmo um
 *   engano aqui não apaga a imagem de um bolso.
 */

export type PreparedImage = {
  blob: Blob;
  mime: "image/webp" | "image/jpeg";
  width: number;
  height: number;
  bytes: number;
  /** Prévia local (`blob:`) — revogar quando não for mais usada. */
  url: string;
};

export type PrepareResult = { ok: true; image: PreparedImage } | { ok: false; message: string };

async function decode(file: File): Promise<{ source: CanvasImageSource; width: number; height: number; close: () => void } | null> {
  if (typeof createImageBitmap === "function") {
    try {
      const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
      return { source: bitmap, width: bitmap.width, height: bitmap.height, close: () => bitmap.close() };
    } catch {
      // cai para <img> (navegadores sem a opção de orientação)
    }
  }
  const url = URL.createObjectURL(file);
  try {
    const img = new Image();
    img.decoding = "async";
    img.src = url;
    await img.decode();
    return { source: img, width: img.naturalWidth, height: img.naturalHeight, close: () => URL.revokeObjectURL(url) };
  } catch {
    URL.revokeObjectURL(url);
    return null;
  }
}

function toBlob(canvas: HTMLCanvasElement, type: string, quality: number): Promise<Blob | null> {
  return new Promise((resolve) => canvas.toBlob(resolve, type, quality));
}

/** Lê, reduz e codifica a imagem escolhida. Nada sai do navegador aqui. */
export async function prepareSlotImage(file: File): Promise<PrepareResult> {
  const check = checkSourceFile(file);
  if (check !== "ok") return { ok: false, message: sourceCheckMessage(check) };
  const decoded = await decode(file);
  if (!decoded || decoded.width < 1 || decoded.height < 1) {
    return { ok: false, message: "Não conseguimos abrir essa imagem. Ela pode estar corrompida ou num formato que o navegador não lê." };
  }
  try {
    const base = fitWithin(decoded.width, decoded.height);
    const canvas = document.createElement("canvas");
    const context = canvas.getContext("2d", { alpha: true });
    if (!context) return { ok: false, message: "O navegador não conseguiu preparar a imagem. Tente outro navegador." };
    let preferWebp = true;
    for (const step of ENCODE_LADDER) {
      const width = Math.max(1, Math.round(base.width * step.scale));
      const height = Math.max(1, Math.round(base.height * step.scale));
      canvas.width = width;
      canvas.height = height;
      context.clearRect(0, 0, width, height);
      if (!preferWebp) {
        // JPEG não tem transparência: fundo grafite, o mesmo do bolso.
        context.fillStyle = "#121212";
        context.fillRect(0, 0, width, height);
      }
      context.imageSmoothingQuality = "high";
      context.drawImage(decoded.source, 0, 0, width, height);
      let blob = preferWebp ? await toBlob(canvas, "image/webp", step.quality) : null;
      if (preferWebp && (!blob || !acceptedOutputType(blob.type))) {
        // Navegador sem codificador WebP: refaz este passo em JPEG.
        preferWebp = false;
        context.fillStyle = "#121212";
        context.globalCompositeOperation = "destination-over";
        context.fillRect(0, 0, width, height);
        context.globalCompositeOperation = "source-over";
        blob = null;
      }
      if (!blob) blob = await toBlob(canvas, "image/jpeg", step.quality);
      const mime = blob ? acceptedOutputType(blob.type) : null;
      if (blob && mime && blob.size > 0 && blob.size <= SLOT_IMAGE_MAX_BYTES) {
        return { ok: true, image: { blob, mime, width, height, bytes: blob.size, url: URL.createObjectURL(blob) } };
      }
    }
    return { ok: false, message: "Não conseguimos deixar essa imagem com até 512 KB. Escolha uma imagem mais simples." };
  } finally {
    decoded.close();
  }
}

/** Apaga arquivos da própria pasta. Melhor esforço: nunca lança; a política recusa os vinculados. */
async function removeFiles(paths: string[]): Promise<boolean> {
  if (paths.length === 0) return true;
  try {
    const { error } = await createClient().storage.from(SLOT_IMAGE_BUCKET).remove(paths);
    return !error;
  } catch {
    return false;
  }
}

export type LinkOutcome =
  | { ok: true; result: SetImageResult; previousRemoved: boolean }
  | { ok: false; message: string; reason: ImageFailure | "upload"; uncertain: boolean };

/**
 * Envia a imagem preparada para um caminho novo e a vincula ao bolso.
 * Serve para colocar e para substituir (a 5233 troca e devolve o anterior).
 */
export async function linkNewSlotImage(input: {
  collectionId: string;
  layoutId: string;
  slotId: string;
  image: PreparedImage;
  focalY: number;
  onStage?: (stage: "upload" | "link") => void;
}): Promise<LinkOutcome> {
  const supabase = createClient();
  const { data } = await supabase.auth.getSession();
  const userId = data.session?.user.id;
  if (!userId) return { ok: false, reason: "not_authenticated", uncertain: false, message: imageFailureMessage("not_authenticated") };
  const path = buildSlotImagePath(userId, input.layoutId, input.image.mime, crypto.randomUUID());
  if (!path) return { ok: false, reason: "invalid", uncertain: false, message: imageFailureMessage("invalid") };

  input.onStage?.("upload");
  const sent = await supabase.storage
    .from(SLOT_IMAGE_BUCKET)
    .upload(path, input.image.blob, { contentType: input.image.mime, upsert: false, cacheControl: "3600" })
    .catch((error: unknown) => ({ error: error as { message?: string } }));
  if (sent.error) {
    // Nada foi vinculado; o arquivo, se chegou a existir, fica para a limpeza.
    return { ok: false, reason: "upload", uncertain: false, message: uploadFailureMessage(classifyUploadError(sent.error as { message?: string; statusCode?: string })) };
  }

  input.onStage?.("link");
  const linked = await setSlotImage({ collectionId: input.collectionId, slotId: input.slotId, path, focalY: input.focalY }).catch(
    () => ({ ok: false as const, reason: "unknown" as const }),
  );
  if (!linked.ok) {
    if (isDefiniteRefusal(linked.reason)) {
      // O banco recusou e não gravou nada: o arquivo novo não serve a ninguém.
      await removeFiles([path]);
      return { ok: false, reason: linked.reason, uncertain: false, message: imageFailureMessage(linked.reason) };
    }
    // Incerto: o vínculo pode ter acontecido. Não apaga nada.
    return { ok: false, reason: "unknown", uncertain: true, message: imageFailureMessage("unknown") };
  }
  const previous = linked.result.previousPath;
  const previousRemoved = previous ? await removeFiles([previous]) : true;
  return { ok: true, result: linked.result, previousRemoved };
}

/** Envia a imagem preparada para um caminho NOVO. Mesma regra do bolso. */
async function uploadNew(layoutId: string, image: PreparedImage): Promise<{ ok: true; path: string } | { ok: false; reason: RegionFailure | "upload"; message: string }> {
  const supabase = createClient();
  const { data } = await supabase.auth.getSession();
  const userId = data.session?.user.id;
  if (!userId) return { ok: false, reason: "not_authenticated", message: regionFailureMessage("not_authenticated") };
  const path = buildSlotImagePath(userId, layoutId, image.mime, crypto.randomUUID());
  if (!path) return { ok: false, reason: "invalid", message: regionFailureMessage("invalid") };
  const sent = await supabase.storage
    .from(SLOT_IMAGE_BUCKET)
    .upload(path, image.blob, { contentType: image.mime, upsert: false, cacheControl: "3600" })
    .catch((error: unknown) => ({ error: error as { message?: string } }));
  if (sent.error) return { ok: false, reason: "upload", message: uploadFailureMessage(classifyUploadError(sent.error as { message?: string; statusCode?: string })) };
  return { ok: true, path };
}

export type RegionLinkOutcome =
  | { ok: true; regionId: string; path: string; focalX: number; focalY: number; previousRemoved: boolean }
  | { ok: false; message: string; reason: RegionFailure | "upload"; uncertain: boolean };

/**
 * Imagem em 2 bolsos (5240): envia para caminho novo e então
 * - sem `regionId`: une os 2 bolsos e vincula na mesma transação;
 * - com `regionId`: substitui a imagem da área (apaga a anterior só depois).
 * Recusa definitiva apaga só o arquivo novo; resposta incerta não apaga nada.
 */
export async function linkNewRegionImage(input: {
  collectionId: string;
  layoutId: string;
  leftSlotId: string;
  regionId: string | null;
  image: PreparedImage;
  focalX: number;
  focalY: number;
  onStage?: (stage: "upload" | "link") => void;
}): Promise<RegionLinkOutcome> {
  input.onStage?.("upload");
  const sent = await uploadNew(input.layoutId, input.image);
  if (!sent.ok) return { ...sent, uncertain: false };
  input.onStage?.("link");
  const unknown = { ok: false as const, reason: "unknown" as const };
  const linked = input.regionId
    ? await setRegionImage({ collectionId: input.collectionId, regionId: input.regionId, path: sent.path, focalX: input.focalX, focalY: input.focalY }).catch(() => unknown)
    : await mergeSlotsWithImage({ collectionId: input.collectionId, leftSlotId: input.leftSlotId, path: sent.path, focalX: input.focalX, focalY: input.focalY }).catch(() => unknown);
  if (!linked.ok) {
    if (isDefiniteRegionRefusal(linked.reason)) {
      await removeFiles([sent.path]);
      return { ok: false, reason: linked.reason, uncertain: false, message: regionFailureMessage(linked.reason) };
    }
    return { ok: false, reason: "unknown", uncertain: true, message: regionFailureMessage("unknown") };
  }
  const previous = "previousPath" in linked.result ? linked.result.previousPath : null;
  const previousRemoved = previous ? await removeFiles([previous]) : true;
  return { ok: true, regionId: linked.result.regionId, path: linked.result.path, focalX: linked.result.focalX, focalY: linked.result.focalY, previousRemoved };
}

/** Separa os bolsos; o arquivo só é apagado depois que o banco desfez o vínculo. */
export async function separateRegionAndFile(input: { collectionId: string; regionId: string }): Promise<{ ok: true; separated: boolean } | { ok: false; reason: RegionFailure; message: string }> {
  const done = await separateSlots(input).catch(() => ({ ok: false as const, reason: "unknown" as const }));
  if (!done.ok) return { ok: false, reason: done.reason, message: regionFailureMessage(done.reason) };
  if (done.previousPath) await removeFiles([done.previousPath]);
  return { ok: true, separated: done.outcome === "SEPARATED" };
}

export type ClearOutcome = { ok: true; removed: boolean } | { ok: false; reason: ImageFailure; message: string };

/** Tira a imagem do bolso; o arquivo só é apagado depois da confirmação do banco. */
export async function clearSlotImageAndFile(input: { collectionId: string; slotId: string }): Promise<ClearOutcome> {
  const cleared = await clearSlotImage(input).catch(() => ({ ok: false as const, reason: "unknown" as const }));
  if (!cleared.ok) return { ok: false, reason: cleared.reason, message: imageFailureMessage(cleared.reason) };
  if (cleared.previousPath) await removeFiles([cleared.previousPath]);
  return { ok: true, removed: cleared.outcome === "REMOVED" };
}

let cleanupStarted = false;

/**
 * Limpeza oportunista de envios abandonados (uma vez por sessão da página):
 * lista os arquivos da própria pasta sem vínculo há mais de 1 hora (5234) e
 * os apaga. Silenciosa; falha não afeta nada.
 */
export function cleanupUnlinkedSlotImagesOnce(): void {
  if (cleanupStarted) return;
  cleanupStarted = true;
  void (async () => {
    const listed = await listUnlinkedSlotImages().catch(() => null);
    if (listed?.ok && listed.paths.length > 0) await removeFiles(listed.paths);
  })();
}
