/**
 * Núcleo compartilhado do canal de importação MANUAL de imagens
 * (`ADR-026`, emenda "Segundo ponto de entrada via UI", 2026-08-08).
 *
 * Runtime-neutro por decisão explícita de Fabrício: nenhum import de
 * Next.js, Deno, filesystem ou variáveis de ambiente, e nunca cria seu
 * próprio client Supabase — todo client é recebido já pronto por quem
 * chama. Isso permite que este arquivo sirva a dois adaptadores muito
 * diferentes sem duplicar a regra de negócio entre eles:
 *
 * 1. `scripts/import-manual-assets.ts` (Deno, roda localmente com a
 *    Service Role Key, lê arquivos do disco) — importa este módulo por
 *    caminho relativo; Deno não tem a restrição de "outside root" que
 *    bundlers como o do Next.js aplicam, então reaproveitar um arquivo
 *    que fisicamente mora em `web/lib/` é seguro nessa direção.
 * 2. A Server Action da tela `/catalogo/importar-imagens` (Next.js,
 *    roda com a sessão do próprio administrador) — importa este módulo
 *    normalmente, como qualquer outro arquivo de `web/lib/`.
 *
 * O que NÃO é compartilhado, de propósito: a gravação em si.
 * `scripts/import-manual-assets.ts` grava direto em `card_asset` via
 * Service Role Key (bypassa RLS); a Server Action grava via
 * `admin_persist_manual_card_asset()` (Query 2120, `SECURITY DEFINER`,
 * exige sessão real de administrador — uma chamada autenticada por
 * Service Role Key JAMAIS passaria em `is_admin()`, que depende de
 * `auth.uid()`). São dois caminhos de escrita genuinamente diferentes;
 * forçá-los a compartilhar a mesma função de gravação seria uma
 * abstração artificial. O que os dois caminhos realmente têm em comum
 * — validar extensão/MIME, calcular checksum, resolver Card Set/Card/
 * idioma pela mesma regra — é exatamente o que este arquivo cobre.
 *
 * O client Supabase é sempre recebido como `any` (não `SupabaseClient`
 * de `@supabase/supabase-js`) deliberadamente — evita qualquer
 * dependência de import, mesmo só de tipos, que poderia se comportar
 * de forma diferente entre o especificador `npm:@supabase/supabase-js@2`
 * (Deno) e o import direto (Node/Next.js).
 */

// ---------------------------------------------------------------------------
// Extensão / MIME — mesma whitelist de scripts/import-manual-assets.ts e da
// RPC admin_persist_manual_card_asset() (Query 2120), mantida em paridade
// manual nas três pontas (script, núcleo, banco) — é a mesma lista curta e
// estável há meses (png/webp/jpg/jpeg), risco de divergência baixo.
// ---------------------------------------------------------------------------

export const MANUAL_ASSET_MIME_TYPES: Record<string, string> = {
  png: "image/png",
  webp: "image/webp",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
};

export const MANUAL_ASSET_SUPPORTED_EXTENSIONS = Object.keys(MANUAL_ASSET_MIME_TYPES);

/** Erro estruturado do núcleo — `code` é sempre um dos prefixos já usados historicamente pelo script (CARD_SET_NOT_FOUND, CARD_NOT_FOUND, etc.), preservando o formato de log existente. */
export class ManualAssetImportError extends Error {
  code: string;

  constructor(code: string, detail?: string) {
    super(detail ? `${code}: ${detail}` : code);
    this.code = code;
    this.name = "ManualAssetImportError";
  }
}

export function extensionOf(fileName: string): string {
  const parts = fileName.split(".");
  return parts[parts.length - 1]?.toLowerCase() ?? "";
}

/** Nome do arquivo sem a extensão — usado pelo script como collector_number (convenção de pasta fixa). Não usada pela web (o collector_number lá vem do manifesto já carregado, nunca do nome do arquivo). */
export function stripExtension(fileName: string): string {
  const extension = extensionOf(fileName);
  return extension ? fileName.slice(0, fileName.length - extension.length - 1) : fileName;
}

/** Lança ManualAssetImportError se a extensão/MIME não estiverem na whitelist — mesma checagem feita novamente, de forma independente, pela RPC 2120 (defesa em profundidade: cliente valida por UX, núcleo valida antes de gravar, banco valida uma terceira vez). */
export function validateManualAssetExtensionAndMime(extension: string, mimeType: string): void {
  const normalized = extension.toLowerCase();
  const expectedMime = MANUAL_ASSET_MIME_TYPES[normalized];

  if (!expectedMime) {
    throw new ManualAssetImportError("UNSUPPORTED_EXTENSION", extension);
  }

  if (mimeType !== expectedMime) {
    throw new ManualAssetImportError(
      "MIME_EXTENSION_MISMATCH",
      `extensão ${extension} esperava ${expectedMime}, recebeu ${mimeType}`,
    );
  }
}

/** SHA-256 em hexadecimal via Web Crypto (`crypto.subtle`) — disponível em Deno, Node 19+ e no navegador sem nenhum import adicional. */
export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes as BufferSource);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

// ---------------------------------------------------------------------------
// Lookups — mesma lógica de scripts/import-manual-assets.ts, extraída sem
// alteração de comportamento. `client` é sempre `any`, ver nota de topo.
// ---------------------------------------------------------------------------

export async function findCardSetByCode(client: any, code: string) {
  const { data, error } = await client
    .from("card_set")
    .select("id, code, name")
    .eq("code", code)
    .maybeSingle();

  if (error) {
    throw new ManualAssetImportError("CARD_SET_QUERY_FAILED", error.message);
  }

  return data as { id: string; code: string; name: string } | null;
}

export async function findCardByCollectorNumber(client: any, cardSetId: string, collectorNumber: string) {
  const { data, error } = await client
    .from("card")
    .select("id, collector_number")
    .eq("card_set_id", cardSetId)
    .eq("collector_number", collectorNumber)
    .maybeSingle();

  if (error) {
    throw new ManualAssetImportError("CARD_QUERY_FAILED", error.message);
  }

  return data as { id: string; collector_number: string } | null;
}

export async function findLanguageByCode(client: any, code: string) {
  const { data, error } = await client
    .from("language")
    .select("id, code")
    .eq("code", code)
    .maybeSingle();

  if (error) {
    throw new ManualAssetImportError("LANGUAGE_QUERY_FAILED", error.message);
  }

  return data as { id: string; code: string } | null;
}

export async function findCardAssetTypeByCode(client: any, code: string) {
  const { data, error } = await client
    .from("card_asset_type")
    .select("id, code")
    .eq("code", code)
    .maybeSingle();

  if (error) {
    throw new ManualAssetImportError("CARD_ASSET_TYPE_QUERY_FAILED", error.message);
  }

  return data as { id: string; code: string } | null;
}

export async function findStorageBucketByCode(client: any, code: string) {
  const { data, error } = await client
    .from("storage_bucket")
    .select("id, code")
    .eq("code", code)
    .eq("is_active", true)
    .maybeSingle();

  if (error) {
    throw new ManualAssetImportError("STORAGE_BUCKET_QUERY_FAILED", error.message);
  }

  return data as { id: string; code: string } | null;
}

export type ResolvedManualAssetCard = {
  cardSet: { id: string; code: string; name: string };
  card: { id: string; collector_number: string };
  language: { id: string; code: string };
};

/**
 * Resolve Card Set (por código) + Card (por collector_number dentro do Card
 * Set) + idioma (por código) numa só chamada, com os mesmos erros
 * (`CARD_SET_NOT_FOUND`/`CARD_NOT_FOUND`/`LANGUAGE_NOT_FOUND`) que
 * `processFile()` já lançava inline antes desta extração.
 *
 * Usada pelos dois adaptadores: o script (que só tem o código da Coleção,
 * o idioma da pasta e o nome do arquivo) e a Server Action da web (que
 * recebe `cardSetCode`/`languageCode`/`collectorNumber` do cliente e
 * precisa resolver `card_id` antes de chamar `admin_persist_manual_card_asset()`
 * — o cliente nunca envia UUIDs internos, só os identificadores visíveis).
 */
export async function resolveManualAssetCard(
  client: any,
  params: { cardSetCode: string; collectorNumber: string; languageCode: string },
): Promise<ResolvedManualAssetCard> {
  const cardSetCode = params.cardSetCode.toUpperCase();

  const cardSet = await findCardSetByCode(client, cardSetCode);
  if (!cardSet) {
    throw new ManualAssetImportError("CARD_SET_NOT_FOUND", cardSetCode);
  }

  const card = await findCardByCollectorNumber(client, cardSet.id, params.collectorNumber);
  if (!card) {
    throw new ManualAssetImportError("CARD_NOT_FOUND", `${cardSetCode} #${params.collectorNumber}`);
  }

  const language = await findLanguageByCode(client, params.languageCode);
  if (!language) {
    throw new ManualAssetImportError("LANGUAGE_NOT_FOUND", params.languageCode);
  }

  return { cardSet, card, language };
}

// ---------------------------------------------------------------------------
// Só para o script (Deno): upload de bytes para o Storage e convenção de
// path fixa (`{set}/{idioma}/{collector_number}.{ext}`). A web NUNCA chama
// isto — o navegador sobe o arquivo direto para o Storage, sem passar por
// este núcleo (ver `web/components/catalogo/importar-imagens-manual-picker.tsx`),
// com um path diferente (sempre novo, nunca reaproveitado — ver ADR-026,
// emenda "Segundo ponto de entrada via UI", seção sobre rollback seguro).
// ---------------------------------------------------------------------------

export function buildScriptManualAssetStoragePath(
  cardSetCode: string,
  languageCode: string,
  collectorNumber: string,
  extension: string,
): string {
  return `${cardSetCode.toLowerCase()}/${languageCode}/${collectorNumber}.${extension}`;
}

export async function uploadManualAssetFile(
  client: any,
  bucketCode: string,
  storagePath: string,
  bytes: Uint8Array,
  mimeType: string,
  options?: { upsert?: boolean },
): Promise<void> {
  const { error } = await client.storage.from(bucketCode).upload(storagePath, bytes, {
    contentType: mimeType,
    upsert: options?.upsert ?? false,
  });

  if (error) {
    throw new ManualAssetImportError("STORAGE_UPLOAD_FAILED", error.message);
  }
}
