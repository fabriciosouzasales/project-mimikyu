/**
 * Leitura limitada do corpo do endpoint em lote `/api/colecoes/precos`
 * (V1-09, C2). Sem dependências de Next: recebe cabeçalhos e o fluxo do corpo
 * (Web Streams), então é testável em Node puro.
 *
 * Ordem das recusas, sempre antes de interpretar o JSON por inteiro:
 *  1. `Content-Type` presente e não JSON → 415.
 *  2. `Content-Length` ilegível → 400; acima do teto → 413 (nada é lido).
 *  3. Leitura incremental: passou do teto (corpo sem `Content-Length` ou que
 *     mente o tamanho) → 413, leitura cancelada no ato.
 *  4. Corpo vazio → 400; UTF-8 inválido ou JSON malformado → 400.
 */
export type BodyReadResult =
  | { ok: true; value: unknown }
  | { ok: false; status: 400 | 413 | 415; error: "unsupported_media_type" | "invalid_content_length" | "payload_too_large" | "empty_body" | "invalid_json" };

export async function readJsonBodyWithLimit(
  headers: Headers,
  body: ReadableStream<Uint8Array> | null,
  maxBytes: number,
): Promise<BodyReadResult> {
  const type = headers.get("content-type");
  if (type !== null && !/^application\/json\b/i.test(type.trim())) {
    return { ok: false, status: 415, error: "unsupported_media_type" };
  }
  const declared = headers.get("content-length");
  if (declared !== null) {
    if (!/^\d+$/.test(declared.trim())) return { ok: false, status: 400, error: "invalid_content_length" };
    if (Number(declared) > maxBytes) return { ok: false, status: 413, error: "payload_too_large" };
  }
  if (!body) return { ok: false, status: 400, error: "empty_body" };

  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel().catch(() => {});
      return { ok: false, status: 413, error: "payload_too_large" };
    }
    chunks.push(value);
  }
  if (total === 0) return { ok: false, status: 400, error: "empty_body" };

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return { ok: false, status: 400, error: "invalid_json" };
  }
  try {
    return { ok: true, value: JSON.parse(text) as unknown };
  } catch {
    return { ok: false, status: 400, error: "invalid_json" };
  }
}
