import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type ReceivedInvite,
  SHARED_PAGE_SIZE,
  type PublicBinder,
  type SharedBinder,
  type SharedBinderImage,
  type SharedBinderPage,
  SHARED_BINDER_PAGES_PER_READ,
  SHARED_VISUAL_URL_TTL,
  attachSharedBinderImages,
  parseSharedBinderImages,
  parseSharedCover,
  type SharedCard,
  type SharedCollection,
  type SharedPosition,
  type SharedPositionFilter,
  type SharedWithMe,
  parseInvites,
  parsePublicBinder,
  parseSharedBinder,
  parseSharedBinderPages,
  parseSharedCards,
  parseSharedCollection,
  parseSharedPositions,
  parseSharedWithMe,
} from "./sharing";
import type { SharedIdentity } from "./shared-library";

/**
 * Leituras do compartilhamento (V1-12) — 5309/5311/5312/5313 (proposta).
 * Qualquer falha (inclusive função ainda ausente no banco) vira "nada a
 * mostrar": a página da coleção, a Biblioteca e a rota compartilhada
 * continuam funcionando, só sem a parte compartilhada.
 */

function logFailure(fn: string, startedAt: number, error: { code?: string; message?: string } | null) {
  console.error(JSON.stringify({ scope: "colecoes.sharing.read", fn, ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA" }));
}

/** Convites esperando resposta do usuário da sessão. */
export async function getMyCollectionInvites(supabase: SupabaseClient): Promise<ReceivedInvite[]> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_my_collection_invites");
  if (error) {
    logFailure("get_my_collection_invites", startedAt, error);
    return [];
  }
  return parseInvites(data);
}

/** Coleções em que o usuário da sessão participa (VIEWER). */
export async function getCollectionsSharedWithMe(supabase: SupabaseClient): Promise<SharedWithMe[]> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_collections_shared_with_me");
  if (error) {
    logFailure("get_collections_shared_with_me", startedAt, error);
    return [];
  }
  return parseSharedWithMe(data);
}

/**
 * Identidade da placa das coleções compartilhadas EXIBIDAS na página da
 * Biblioteca (V1-12): Set → logo do Set (5312, `card_set_logo_path`); sem
 * Set → capa enviada e código (5328, URL já assinada para terceiros). Uma
 * leitura por coleção exibida, em paralelo e limitada à página (≤ 48); 5311
 * não devolve esses campos. Falha → sem identidade (placa tipográfica), nunca
 * erro na Biblioteca.
 */
export async function getSharedLibraryIdentities(
  supabase: SupabaseClient,
  items: readonly { id: string; cardSetCode: string | null }[],
): Promise<Map<string, SharedIdentity>> {
  const entries = await Promise.all(
    items.map(async (item): Promise<[string, SharedIdentity] | null> => {
      if (item.cardSetCode) {
        const header = await getSharedCollection(supabase, item.id).catch(() => null);
        return header ? [item.id, { cardSetLogoPath: header.cardSetLogoPath, coverUrl: null, coverCode: null }] : null;
      }
      const cover = await getSharedCollectionCover(supabase, item.id).catch(() => null);
      return cover ? [item.id, { cardSetLogoPath: null, coverUrl: cover.logoUrl, coverCode: cover.code }] : null;
    }),
  );
  return new Map(entries.filter((entry): entry is [string, SharedIdentity] => entry !== null));
}

/** Cabeçalho para VIEWER/público. `null` = sem acesso (ou leitura indisponível) → 404. */
export async function getSharedCollection(supabase: SupabaseClient, collectionId: string): Promise<SharedCollection | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_shared_collection", { p_collection_id: collectionId });
  if (error) {
    logFailure("get_shared_collection", startedAt, error);
    return null;
  }
  return parseSharedCollection(data);
}

/** Uma página da galeria compartilhada. `null` = falha de leitura (≠ coleção vazia). */
export async function getSharedCollectionCards(
  supabase: SupabaseClient,
  collectionId: string,
  page: number,
): Promise<{ items: SharedCard[]; total: number } | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_shared_collection_cards", {
    p_collection_id: collectionId,
    p_limit: SHARED_PAGE_SIZE,
    p_offset: Math.max(0, page - 1) * SHARED_PAGE_SIZE,
  });
  if (error) {
    logFailure("get_shared_collection_cards", startedAt, error);
    return null;
  }
  return parseSharedCards(data);
}

/**
 * Fichário da coleção para o participante (5314). `null` = sem acesso, sem
 * a função no banco ou falha — a página só não oferece o fichário.
 */
export async function getSharedCollectionBinder(supabase: SupabaseClient, collectionId: string): Promise<SharedBinder | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_shared_collection_binder", { p_collection_id: collectionId });
  if (error) {
    logFailure("get_shared_collection_binder", startedAt, error);
    return null;
  }
  return parseSharedBinder(data);
}

/**
 * Primeiro lote de páginas (5315), lido no servidor para a primeira pintura.
 * `null` = falha (o cliente mostra "tentar de novo" no lote).
 */
async function getSharedCollectionBinderPagesFrom(
  fn: "get_shared_collection_binder_pages" | "get_public_collection_binder_pages",
  supabase: SupabaseClient,
  collectionId: string,
  firstPage: number,
  columns: number,
  rows: number,
): Promise<SharedBinderPage[] | null> {
  const startedAt = Date.now();
  const source = fn === "get_public_collection_binder_pages" ? "public" : "shared";
  const [{ data, error }, images] = await Promise.all([
    supabase.rpc(fn, {
      p_collection_id: collectionId,
      p_first_page: firstPage,
      p_page_count: SHARED_BINDER_PAGES_PER_READ,
    }),
    readSharedBinderImages(supabase, source, collectionId, firstPage),
  ]);
  if (error) {
    logFailure(fn, startedAt, error);
    return null;
  }
  const pages = parseSharedBinderPages(data, columns, rows);
  return pages ? attachSharedBinderImages(pages, images) : null;
}

const SLOT_IMAGE_BUCKET = "binder-slot-image";
const COVER_BUCKET = "collection-cover";

function missingFunction(error: { code?: string } | null): boolean {
  return error?.code === "PGRST202" || error?.code === "42883";
}

/**
 * Imagens decorativas das páginas pedidas (5326 participante / 5327 vitrine),
 * com URLs assinadas EM LOTE pela própria sessão do leitor (uma chamada ao
 * Storage por lote de 4 páginas), autorizadas pela política escopada 5329.
 * Elemento decorativo: falha, função ausente ou assinatura negada → nenhuma
 * imagem (o bolso fica vazio, como antes) — nunca bloqueia o fichário.
 */
export async function readSharedBinderImages(
  supabase: SupabaseClient,
  source: "shared" | "public",
  collectionId: string,
  firstPage: number,
): Promise<SharedBinderImage[]> {
  const fn = source === "public" ? "get_public_collection_binder_images" : "get_shared_collection_binder_images";
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc(fn, {
    p_collection_id: collectionId,
    p_first_page: firstPage,
    p_page_count: SHARED_BINDER_PAGES_PER_READ,
  });
  if (error) {
    if (!missingFunction(error)) logFailure(fn, startedAt, error);
    return [];
  }
  const images = parseSharedBinderImages(data);
  if (!images) {
    logFailure(fn, startedAt, null);
    return [];
  }
  if (images.length === 0) return images;
  const paths = [...new Set(images.map((image) => image.path))];
  const { data: signed, error: signError } = await supabase.storage.from(SLOT_IMAGE_BUCKET).createSignedUrls(paths, SHARED_VISUAL_URL_TTL);
  if (signError || !signed) {
    logFailure(`${fn}.sign`, startedAt, { code: "SIGN_FAILED" });
    return [];
  }
  const urlByPath = new Map<string, string>();
  for (const item of signed) if (item.path && item.signedUrl && !item.error) urlByPath.set(item.path, item.signedUrl);
  return images.map((image) => ({ ...image, url: urlByPath.get(image.path) ?? null }));
}

/**
 * Capa personalizada da própria coleção (5328): imagem enviada (assinada pela
 * sessão do leitor, política 5329) e código da capa. Sem acesso, sem capa,
 * função ausente ou assinatura negada → `{ logoUrl: null, code: null }`.
 */
export async function getSharedCollectionCover(
  supabase: SupabaseClient,
  collectionId: string,
): Promise<{ logoUrl: string | null; code: string | null }> {
  const none = { logoUrl: null, code: null };
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_shared_collection_cover", { p_collection_id: collectionId });
  if (error) {
    if (!missingFunction(error)) logFailure("get_shared_collection_cover", startedAt, error);
    return none;
  }
  const cover = parseSharedCover(data);
  if (!cover) return none;
  if (!cover.path) return { logoUrl: null, code: cover.code };
  const { data: signed, error: signError } = await supabase.storage.from(COVER_BUCKET).createSignedUrl(cover.path, SHARED_VISUAL_URL_TTL);
  if (signError || !signed?.signedUrl) return { logoUrl: null, code: cover.code };
  return { logoUrl: signed.signedUrl, code: cover.code };
}

/**
 * Vitrine pública do fichário (5317), sem sessão. `null` = não publicada,
 * inexistente ou leitura indisponível — a página responde 404.
 */
export async function getPublicCollectionBinder(supabase: SupabaseClient, collectionId: string): Promise<PublicBinder | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_public_collection_binder", { p_collection_id: collectionId });
  if (error) {
    logFailure("get_public_collection_binder", startedAt, error);
    return null;
  }
  return parsePublicBinder(data);
}

export async function getSharedCollectionBinderPages(
  supabase: SupabaseClient,
  collectionId: string,
  firstPage: number,
  columns: number,
  rows: number,
): Promise<SharedBinderPage[] | null> {
  return getSharedCollectionBinderPagesFrom("get_shared_collection_binder_pages", supabase, collectionId, firstPage, columns, rows);
}

/** Primeiro lote da vitrine pública (5318), lido no servidor sem sessão. */
export async function getPublicCollectionBinderPages(
  supabase: SupabaseClient,
  collectionId: string,
  firstPage: number,
  columns: number,
  rows: number,
): Promise<SharedBinderPage[] | null> {
  return getSharedCollectionBinderPagesFrom("get_public_collection_binder_pages", supabase, collectionId, firstPage, columns, rows);
}

/**
 * Grade Todas · Tenho · Faltam do participante (5320, proposta), na ordem do
 * Set. `unavailable` = a função ainda não existe no banco (PGRST202/42883):
 * a página volta para a galeria de cartas alocadas (5313), sem filtros
 * decorativos. `error` = falha de leitura (mostra "tentar de novo").
 */
export async function getSharedCollectionPositions(
  supabase: SupabaseClient,
  collectionId: string,
  filter: SharedPositionFilter,
): Promise<{ status: "ok"; page: { items: SharedPosition[]; total: number } } | { status: "unavailable" } | { status: "error" }> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_shared_collection_positions", {
    p_collection_id: collectionId,
    p_filter: filter === "tenho" ? "OWNED" : filter === "faltam" ? "MISSING" : "ALL",
    p_limit: 500,
    p_offset: 0,
  });
  if (error) {
    if (error.code === "PGRST202" || error.code === "42883") return { status: "unavailable" };
    logFailure("get_shared_collection_positions", startedAt, error);
    return { status: "error" };
  }
  const page = parseSharedPositions(data);
  return page ? { status: "ok", page } : { status: "error" };
}
