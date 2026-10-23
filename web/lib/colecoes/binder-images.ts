import type { BinderPage, BinderSlot, SlotImage } from "./binder.ts";

/**
 * Imagem personalizada no bolso do fichário (C-198,
 * P2-BINDER-CUSTOM-IMAGES-CLOSEOUT-AND-FRONTEND-01) — regras puras.
 *
 * Contratos LIVE `5231`–`5236` (canônicos em `database/schema/`):
 *  - bucket privado `binder-slot-image` (512 KB, WebP/JPEG; leitura,
 *    envio e remoção só na própria pasta; remoção recusada enquanto o
 *    arquivo estiver vinculado; sem UPDATE — nunca sobrescrever);
 *  - `set_my_binder_slot_image` / `set_my_binder_slot_image_focus` /
 *    `clear_my_binder_slot_image` (escrita) e
 *    `get_my_collection_binder_slot_images` /
 *    `get_my_binder_slot_image_summary` /
 *    `list_my_unlinked_binder_slot_images` (leitura).
 *
 * A imagem é um elemento visual do fichário, não um exemplar: não conta em
 * inventário, progresso nem valor, e é exclusiva com carta, reserva, cadeado
 * e mesclagem (o banco garante). Aqui só formato, cálculo e mensagens.
 */

export const SLOT_IMAGE_BUCKET = "binder-slot-image";
/** Mesmo limite do bucket (5231) e da RPC (5233). */
export const SLOT_IMAGE_MAX_BYTES = 524_288;
/** Limite por colecionador (5233; decisão D1 de Fabrício). */
export const SLOT_IMAGE_LIMIT = 500;
/** URLs assinadas: 1 hora, com a sessão do colecionador. */
export const SLOT_IMAGE_SIGNED_TTL = 60 * 60;
/** Arquivo de origem aceito antes da conversão (a saída sempre cabe em 512 KB). */
export const SOURCE_MAX_BYTES = 20 * 1024 * 1024;
/** Teto da imagem gravada: ~2,5× o maior bolso exibido, com folga para enquadrar. */
export const OUTPUT_MAX_WIDTH = 900;
export const OUTPUT_MAX_HEIGHT = 1800;
/** Proporção do bolso (largura / altura) — a mesma das cartas. */
export const POCKET_RATIO = 8 / 11;
export const FOCAL_DEFAULT = 50;

const SOURCE_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
export const SOURCE_ACCEPT = "image/jpeg,image/png,image/webp";
const EXTENSION_BY_MIME: Readonly<Record<string, "webp" | "jpg">> = { "image/webp": "webp", "image/jpeg": "jpg" };

const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
/** Mesmo formato do CHECK de 5232 e da política INSERT de 5231: `<dono>/<fichário>/<uuid>.(webp|jpg)`. */
const SLOT_IMAGE_PATH = new RegExp(`^${UUID}/${UUID}/${UUID}\\.(webp|jpg)$`);

// ---------------------------------------------------------------------------
// Arquivo escolhido
// ---------------------------------------------------------------------------

export type SourceCheck = "ok" | "heic" | "type" | "empty" | "too_large";

/** Validação do arquivo escolhido, antes de decodificar (o bucket e a RPC reconferem a saída). */
export function checkSourceFile(file: { type: string; size: number; name?: string }): SourceCheck {
  const name = (file.name ?? "").toLowerCase();
  const type = (file.type ?? "").toLowerCase();
  if (type === "image/heic" || type === "image/heif" || /\.(heic|heif)$/.test(name)) return "heic";
  const byName = /\.(jpe?g|png|webp)$/.test(name);
  if (type ? !SOURCE_TYPES.has(type) : !byName) return "type";
  if (!Number.isFinite(file.size) || file.size <= 0) return "empty";
  if (file.size > SOURCE_MAX_BYTES) return "too_large";
  return "ok";
}

export function sourceCheckMessage(check: Exclude<SourceCheck, "ok">): string {
  switch (check) {
    case "heic":
      return "Fotos HEIC (iPhone) ainda não são aceitas. Exporte como JPEG ou escolha outra imagem.";
    case "type":
      return "Escolha uma imagem JPEG, PNG ou WebP.";
    case "empty":
      return "Esse arquivo está vazio. Escolha outra imagem.";
    case "too_large":
      return "A imagem passa de 20 MB. Escolha um arquivo menor.";
  }
}

// ---------------------------------------------------------------------------
// Conversão (o navegador faz; aqui só a matemática)
// ---------------------------------------------------------------------------

/** Dimensões dentro do teto, mantendo a proporção; nunca amplia. */
export function fitWithin(width: number, height: number, maxWidth = OUTPUT_MAX_WIDTH, maxHeight = OUTPUT_MAX_HEIGHT): { width: number; height: number } {
  if (!(width > 0) || !(height > 0)) return { width: 0, height: 0 };
  const scale = Math.min(1, maxWidth / width, maxHeight / height);
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) };
}

/**
 * Tentativas de codificação, da melhor para a menor: primeiro só a
 * qualidade, depois também o tamanho. A primeira que couber em 512 KB vale.
 */
export const ENCODE_LADDER: readonly { scale: number; quality: number }[] = [
  { scale: 1, quality: 0.85 },
  { scale: 1, quality: 0.78 },
  { scale: 1, quality: 0.7 },
  { scale: 0.85, quality: 0.72 },
  { scale: 0.72, quality: 0.7 },
  { scale: 0.6, quality: 0.68 },
  { scale: 0.5, quality: 0.65 },
  { scale: 0.4, quality: 0.62 },
];

/** Tipo efetivamente gerado pelo navegador → tipo aceito pelo bucket (WebP preferido, JPEG de reserva). */
export function acceptedOutputType(blobType: string): "image/webp" | "image/jpeg" | null {
  return blobType === "image/webp" || blobType === "image/jpeg" ? blobType : null;
}

// ---------------------------------------------------------------------------
// Caminho no bucket
// ---------------------------------------------------------------------------

export function isSlotImagePath(value: unknown): value is string {
  return typeof value === "string" && SLOT_IMAGE_PATH.test(value);
}

/**
 * Caminho NOVO para cada envio (substituir nunca sobrescreve): o arquivo
 * antigo só é apagado depois que o banco confirma a troca.
 */
export function buildSlotImagePath(userId: string, layoutId: string, mime: string, fileId: string): string | null {
  const extension = EXTENSION_BY_MIME[mime];
  if (!extension) return null;
  const path = `${userId.toLowerCase()}/${layoutId.toLowerCase()}/${fileId.toLowerCase()}.${extension}`;
  return isSlotImagePath(path) ? path : null;
}

// ---------------------------------------------------------------------------
// Enquadramento vertical (0 = topo, 100 = base)
// ---------------------------------------------------------------------------

export function clampFocal(value: unknown): number {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return FOCAL_DEFAULT;
  return Math.min(100, Math.max(0, Math.round(n)));
}

/** Teclado do controle de enquadramento (`role="slider"`). `null` = tecla não tratada. */
export function focalForKey(key: string, current: number): number | null {
  switch (key) {
    case "ArrowUp":
    case "ArrowLeft":
      return clampFocal(current - 2);
    case "ArrowDown":
    case "ArrowRight":
      return clampFocal(current + 2);
    case "PageUp":
      return clampFocal(current - 10);
    case "PageDown":
      return clampFocal(current + 10);
    case "Home":
      return 0;
    case "End":
      return 100;
    default:
      return null;
  }
}

/** Quanto a imagem passa da altura do bolso quando cobre a largura (`object-fit: cover`), em px. */
export function verticalOverflow(imageWidth: number, imageHeight: number, boxWidth: number, boxHeight: number): number {
  if (!(imageWidth > 0) || !(imageHeight > 0) || !(boxWidth > 0) || !(boxHeight > 0)) return 0;
  const scale = Math.max(boxWidth / imageWidth, boxHeight / imageHeight);
  const overflow = imageHeight * scale - boxHeight;
  // Resíduo de ponto flutuante (< 0,01 px) não é sobra.
  return overflow < 0.01 ? 0 : overflow;
}

/** Há o que enquadrar na vertical? (imagem mais alta que o bolso, em proporção) */
export function canFrameVertically(imageWidth: number, imageHeight: number): boolean {
  if (!(imageWidth > 0) || !(imageHeight > 0)) return false;
  return imageWidth / imageHeight < POCKET_RATIO - 0.005;
}

/**
 * Arrastar a imagem: puxar para baixo revela o alto (foco sobe, valor
 * menor). `overflow` = `verticalOverflow` do bolso em que se arrasta.
 */
export function focalFromDrag(startFocal: number, deltaY: number, overflow: number): number {
  if (!(overflow > 0)) return clampFocal(startFocal);
  return clampFocal(startFocal - (deltaY / overflow) * 100);
}

export function focalLabel(value: number): string {
  const v = clampFocal(value);
  if (v <= 15) return "Topo";
  if (v >= 85) return "Base";
  if (v >= 40 && v <= 60) return "Centro";
  return v < 50 ? "Mais para o topo" : "Mais para a base";
}

// ---------------------------------------------------------------------------
// Leituras e respostas das RPCs
// ---------------------------------------------------------------------------

function int(value: unknown): number | null {
  const n = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof n === "number" && Number.isInteger(n) ? n : null;
}

function str(value: unknown): string | null {
  return typeof value === "string" && value !== "" ? value : null;
}

/** 5234 `get_my_collection_binder_slot_images` → imagem por bolso (sem URL). `null` quando o formato não bate. */
export function parseSlotImages(rows: unknown): Map<string, SlotImage> | null {
  if (!Array.isArray(rows)) return null;
  const map = new Map<string, SlotImage>();
  for (const raw of rows) {
    if (!raw || typeof raw !== "object") return null;
    const r = raw as Record<string, unknown>;
    const slotId = str(r.slot_id);
    const path = r.storage_path;
    const focal = int(r.focal_y);
    if (!slotId || !isSlotImagePath(path) || focal === null || focal < 0 || focal > 100) return null;
    map.set(slotId, { path, focalY: focal, updatedAt: str(r.updated_at), url: null });
  }
  return map;
}

export type SlotImageSummary = { layoutCount: number; userCount: number; limit: number };

/** 5234 `get_my_binder_slot_image_summary`. */
export function parseImageSummary(data: unknown): SlotImageSummary | null {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") return null;
  const r = row as Record<string, unknown>;
  const layoutCount = int(r.layout_image_count);
  const userCount = int(r.user_image_count);
  const limit = int(r.user_image_limit);
  if (layoutCount === null || userCount === null || limit === null || layoutCount < 0 || userCount < 0 || limit < 1) return null;
  return { layoutCount, userCount, limit };
}

export function imagesLeft(summary: Pick<SlotImageSummary, "userCount" | "limit">): number {
  return Math.max(0, summary.limit - summary.userCount);
}

/** 5234 `list_my_unlinked_binder_slot_images` → caminhos (só os do formato do bucket). */
export function parseUnlinked(data: unknown): string[] | null {
  if (!Array.isArray(data)) return null;
  const paths: string[] = [];
  for (const raw of data) {
    if (!raw || typeof raw !== "object") return null;
    const path = (raw as Record<string, unknown>).storage_path;
    if (isSlotImagePath(path)) paths.push(path);
  }
  return paths;
}

export type SetImageResult = {
  slotId: string;
  path: string;
  focalY: number;
  operation: "ADDED" | "REPLACED" | "UNCHANGED";
  previousPath: string | null;
};

/** 5233 `set_my_binder_slot_image`. */
export function parseSetImageResult(data: unknown): SetImageResult | null {
  const row = Array.isArray(data) ? data[0] : null;
  if (!row || typeof row !== "object") return null;
  const r = row as Record<string, unknown>;
  const slotId = str(r.slot_id);
  const focal = int(r.focal_y);
  const operation = r.operation;
  const previous = r.previous_path ?? null;
  if (!slotId || !isSlotImagePath(r.storage_path) || focal === null) return null;
  if (operation !== "ADDED" && operation !== "REPLACED" && operation !== "UNCHANGED") return null;
  if (previous !== null && !isSlotImagePath(previous)) return null;
  // Só a troca devolve o arquivo anterior — é ele que o cliente apaga depois.
  if (operation === "REPLACED" && previous === null) return null;
  return { slotId, path: r.storage_path as string, focalY: focal, operation, previousPath: operation === "REPLACED" ? (previous as string) : null };
}

/** 5233 `set_my_binder_slot_image_focus`. */
export function parseFocusResult(data: unknown): { slotId: string; focalY: number } | null {
  const row = Array.isArray(data) ? data[0] : null;
  if (!row || typeof row !== "object") return null;
  const r = row as Record<string, unknown>;
  const slotId = str(r.slot_id);
  const focal = int(r.focal_y);
  if (!slotId || focal === null || focal < 0 || focal > 100) return null;
  return { slotId, focalY: focal };
}

/** 5233 `clear_my_binder_slot_image`. */
export function parseClearResult(data: unknown): { outcome: "REMOVED" | "ALREADY_ABSENT"; previousPath: string | null } | null {
  const row = Array.isArray(data) ? data[0] : null;
  if (!row || typeof row !== "object") return null;
  const r = row as Record<string, unknown>;
  const outcome = r.outcome;
  const previous = r.previous_path ?? null;
  if (outcome !== "REMOVED" && outcome !== "ALREADY_ABSENT") return null;
  if (outcome === "REMOVED" && !isSlotImagePath(previous)) return null;
  return { outcome, previousPath: outcome === "REMOVED" ? (previous as string) : null };
}

// ---------------------------------------------------------------------------
// Sobreposição nas páginas (a 5230 continua chamando esses bolsos de EMPTY)
// ---------------------------------------------------------------------------

/**
 * Põe a imagem em cada bolso que a tem. Defesa extra: imagem só aparece em
 * bolso EMPTY e solto (o banco já garante a exclusividade; se algo divergir,
 * a carta/reserva vence e a página é relida na próxima ação).
 */
export function attachSlotImages(pages: BinderPage[], images: ReadonlyMap<string, SlotImage>): BinderPage[] {
  return pages.map((page) => ({
    ...page,
    slots: page.slots.map((slot) => {
      const image = images.get(slot.slotId);
      return { ...slot, image: image && slot.state === "EMPTY" && !slot.locked ? image : null };
    }),
  }));
}

/** Estado provável do bolso logo depois de gravar/remover a imagem (a tela relê o lote em seguida). */
export function applySlotImage(slot: BinderSlot, image: SlotImage | null): BinderSlot {
  return { ...slot, image };
}

// ---------------------------------------------------------------------------
// Falhas
// ---------------------------------------------------------------------------

export type ImageFailure =
  | "quota"
  | "slot_taken"
  | "slot_reserved"
  | "slot_locked"
  | "slot_region"
  | "file_missing"
  | "file_invalid"
  | "path_invalid"
  | "path_in_use"
  | "image_missing"
  | "archived"
  | "not_found"
  | "not_authenticated"
  | "lock_busy"
  | "invalid"
  | "unknown";

/** Erros das RPCs 5233/5234 (texto = código estável, ver cabeçalho da 5233) → motivo. */
export function classifyImageFailure(code: string | null | undefined, message: string | null | undefined): ImageFailure {
  const text = (message ?? "").toUpperCase();
  if (code === "55P03") return "lock_busy";
  if (code === "28000" || text.includes("NOT_AUTHENTICATED")) return "not_authenticated";
  if (text.includes("IMAGE_QUOTA_REACHED")) return "quota";
  if (text.includes("SLOT_OCCUPIED")) return "slot_taken";
  if (text.includes("SLOT_RESERVED")) return "slot_reserved";
  if (text.includes("SLOT_LOCKED")) return "slot_locked";
  if (text.includes("SLOT_IN_REGION")) return "slot_region";
  if (text.includes("IMAGE_FILE_NOT_FOUND")) return "file_missing";
  if (text.includes("INVALID_IMAGE_FILE")) return "file_invalid";
  if (text.includes("INVALID_IMAGE_PATH")) return "path_invalid";
  if (text.includes("IMAGE_PATH_IN_USE")) return "path_in_use";
  if (text.includes("IMAGE_NOT_FOUND")) return "image_missing";
  if (text.includes("COLLECTION_ARCHIVED")) return "archived";
  if (text.includes("COLLECTION_NOT_FOUND") || text.includes("BINDER_NOT_FOUND") || text.includes("SLOT_NOT_FOUND")) return "not_found";
  if (text.includes("INVALID_FOCAL") || text.includes("INVALID_ARGUMENT") || text.includes("INVALID_PAGE") || code === "22023" || code === "22P02") return "invalid";
  return "unknown";
}

/**
 * Recusa definitiva do banco (a transação não gravou nada)? Só então o
 * arquivo recém-enviado pode ser apagado. `unknown` (rede, tempo esgotado,
 * resposta fora do formato) nunca é tratado como recusa: o vínculo pode ter
 * acontecido — nada é apagado e a página é relida.
 */
export function isDefiniteRefusal(reason: ImageFailure): boolean {
  return reason !== "unknown";
}

export function imageFailureMessage(reason: ImageFailure): string {
  switch (reason) {
    case "quota":
      return `Você chegou ao limite de ${SLOT_IMAGE_LIMIT} imagens. Remova alguma para adicionar outra.`;
    case "slot_taken":
      return "Esse bolso recebeu uma carta em outra tela. A imagem não foi colocada.";
    case "slot_reserved":
      return "Esse bolso está reservado para uma carta. Libere a reserva para usar uma imagem.";
    case "slot_locked":
      return "Esse bolso está fixado. Solte o cadeado para usar uma imagem.";
    case "slot_region":
      return "Esse bolso faz parte de uma área mesclada e não recebe imagem.";
    case "file_missing":
      return "O envio da imagem não foi concluído. Tente de novo.";
    case "file_invalid":
      return "A imagem não passou na conferência de formato ou tamanho. Escolha outra.";
    case "path_invalid":
    case "path_in_use":
      return "Não foi possível vincular a imagem. Tente de novo.";
    case "image_missing":
      return "Esse bolso já não tem imagem. Atualizamos a página.";
    case "archived":
      return "A coleção está arquivada. Reative-a para personalizar o fichário.";
    case "not_found":
      return "O fichário mudou em outra tela. Atualizamos a página para você continuar.";
    case "not_authenticated":
      return "Sua sessão terminou. Entre de novo para continuar.";
    case "lock_busy":
      return "O fichário está sendo atualizado em outra tela. Tente de novo em alguns segundos.";
    case "invalid":
      return "Não foi possível entender o pedido. Recarregue a página e tente de novo.";
    default:
      return "Não conseguimos confirmar com o servidor. Atualizamos a página — confira o bolso antes de tentar de novo.";
  }
}

export type UploadFailure = "too_large" | "type" | "denied" | "exists" | "unknown";

/** Erro do envio ao Storage (antes de qualquer vínculo) → motivo. */
export function classifyUploadError(error: { message?: string; statusCode?: string | number } | null | undefined): UploadFailure {
  const text = (error?.message ?? "").toLowerCase();
  const status = String(error?.statusCode ?? "");
  if (status === "413" || text.includes("too large") || text.includes("maximum allowed size")) return "too_large";
  if (text.includes("mime type") || status === "415") return "type";
  if (text.includes("already exists") || status === "409") return "exists";
  if (text.includes("row-level security") || text.includes("unauthorized") || status === "403" || status === "401") return "denied";
  return "unknown";
}

export function uploadFailureMessage(reason: UploadFailure): string {
  switch (reason) {
    case "too_large":
      return "A imagem ficou grande demais mesmo depois de reduzida. Escolha outra.";
    case "type":
      return "O servidor não aceitou o formato da imagem. Escolha outra.";
    case "denied":
      return "O envio não foi autorizado. Se você tem muitas imagens guardadas, remova algumas e tente de novo.";
    case "exists":
      return "Houve um conflito no envio. Tente de novo.";
    default:
      return "Não foi possível enviar a imagem. Nada mudou no fichário — tente de novo.";
  }
}
