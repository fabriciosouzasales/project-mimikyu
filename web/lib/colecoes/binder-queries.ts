import type { SupabaseClient } from "@supabase/supabase-js";
import { type BinderHeader, type BinderPage, PAGES_PER_READ, type SlotImage, classifyBinderFailure, parseBinderHeader, parseBinderPages } from "./binder.ts";
import { SLOT_IMAGE_BUCKET, SLOT_IMAGE_SIGNED_TTL, attachSlotImages, classifyImageFailure, parseSlotImages } from "./binder-images.ts";
import { type JoinCandidate, parseJoinCandidates } from "./binder-share.ts";
import { logReadFailure } from "./colecoes-queries.ts";

/**
 * Leituras do Fichário Digital (5223). Sessão obrigatória; a fronteira de
 * autorização é o banco (SECURITY DEFINER, dono da coleção, sem enumerar
 * coleção alheia). Mesmo padrão das demais leituras de Coleções:
 *  - `undefined` → coleção inexistente ou de outra pessoa (P0002);
 *  - `null`      → falha de leitura (a página mostra erro, nunca um vazio enganoso).
 */
export async function getMyCollectionBinder(supabase: SupabaseClient, collectionId: string): Promise<BinderHeader | null | undefined> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_collection_binder", { p_collection_id: collectionId });
  if (error) {
    if (classifyBinderFailure(error.code, error.message) === "not_found") return undefined;
    logReadFailure("get_my_collection_binder", startedAt, error);
    return null;
  }
  const header = Array.isArray(data) && data.length === 1 ? parseBinderHeader(data[0]) : null;
  if (!header) {
    logReadFailure("get_my_collection_binder", startedAt, { code: "BAD_SHAPE" });
    return null;
  }
  return header;
}

/**
 * Até quatro páginas a partir de `firstPage` (teto do contrato), com as
 * imagens personalizadas dos bolsos (5234) sobrepostas. As duas leituras
 * correm em paralelo; a 5230 continua devolvendo bolso com imagem como
 * EMPTY. Se a leitura de imagens falhar, o lote falha inteiro (a tela mostra
 * "tentar de novo") — nunca um bolso com imagem aparece como vazio.
 */
export async function getMyCollectionBinderPages(
  supabase: SupabaseClient,
  collectionId: string,
  firstPage: number,
): Promise<BinderPage[] | null | undefined> {
  const startedAt = Date.now();
  const [pagesRead, images] = await Promise.all([
    supabase.rpc("get_my_collection_binder_pages", {
      p_collection_id: collectionId,
      p_first_page: firstPage,
      p_page_count: PAGES_PER_READ,
    }),
    getMyBinderSlotImages(supabase, collectionId, firstPage),
  ]);
  const { data, error } = pagesRead;
  if (error) {
    if (classifyBinderFailure(error.code, error.message) === "not_found") return undefined;
    logReadFailure("get_my_collection_binder_pages", startedAt, error);
    return null;
  }
  const pages = parseBinderPages(data);
  if (!pages) {
    logReadFailure("get_my_collection_binder_pages", startedAt, { code: "BAD_SHAPE" });
    return null;
  }
  if (images === undefined) return undefined;
  if (images === null) return null;
  return images.size > 0 ? attachSlotImages(pages, images) : pages;
}

/**
 * Imagens personalizadas dos bolsos de até quatro páginas (5234), com URLs
 * assinadas em lote (1 h) pela sessão do colecionador — a política SELECT do
 * bucket só deixa assinar arquivos da própria pasta. Falha ao assinar não
 * esconde a imagem: o bolso continua marcado como "com imagem" (`url: null`)
 * e mostra o aviso de imagem indisponível.
 */
export async function getMyBinderSlotImages(
  supabase: SupabaseClient,
  collectionId: string,
  firstPage: number,
): Promise<Map<string, SlotImage> | null | undefined> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_collection_binder_slot_images", {
    p_collection_id: collectionId,
    p_first_page: firstPage,
    p_page_count: PAGES_PER_READ,
  });
  if (error) {
    if (classifyImageFailure(error.code, error.message) === "not_found") return undefined;
    logReadFailure("get_my_collection_binder_slot_images", startedAt, error);
    return null;
  }
  const images = parseSlotImages(data);
  if (!images) {
    logReadFailure("get_my_collection_binder_slot_images", startedAt, { code: "BAD_SHAPE" });
    return null;
  }
  if (images.size === 0) return images;
  const paths = [...new Set([...images.values()].map((image) => image.path))];
  const { data: signed, error: signError } = await supabase.storage.from(SLOT_IMAGE_BUCKET).createSignedUrls(paths, SLOT_IMAGE_SIGNED_TTL);
  if (signError || !signed) {
    logReadFailure("binder_slot_image_sign", startedAt, { code: "SIGN_FAILED" });
    return images;
  }
  const urlByPath = new Map<string, string>();
  for (const item of signed) if (item.path && item.signedUrl && !item.error) urlByPath.set(item.path, item.signedUrl);
  for (const [slotId, image] of images) images.set(slotId, { ...image, url: urlByPath.get(image.path) ?? null });
  return images;
}

/**
 * Fichários que esta coleção pode usar (5230 `list_my_binder_join_candidates`).
 * Só leitura; vazio quando a coleção já tem fichário, já é convidada, está
 * arquivada ou não está guardada num fichário físico.
 */
export async function getMyBinderJoinCandidates(supabase: SupabaseClient, collectionId: string): Promise<JoinCandidate[] | null | undefined> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("list_my_binder_join_candidates", { p_collection_id: collectionId });
  if (error) {
    if (classifyBinderFailure(error.code, error.message) === "not_found") return undefined;
    logReadFailure("list_my_binder_join_candidates", startedAt, error);
    return null;
  }
  const candidates = parseJoinCandidates(data);
  if (!candidates) {
    logReadFailure("list_my_binder_join_candidates", startedAt, { code: "BAD_SHAPE" });
    return null;
  }
  return candidates;
}
