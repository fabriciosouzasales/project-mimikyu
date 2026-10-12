/*
Project Mimikyu — Edge Function: import-scrydex-assets-2
Operação PONTUAL em lotes (2026-10-11). Mandato de Fabrício, 2026-10-11: importar pela Scrydex as
imagens que faltam em Importar Imagens (1. "Pode"), usar a mesma imagem nas versões a/b de Aquapolis
(2. "Sim") e confirmar o nome da SM2 143 antes (3., confirmado em plan.ts).

Mesmo desenho de import-scrydex-assets (operação SCRYDEX_ASSETS_2026_10_10), com UMA diferença:
o critério de pendência é "sem CARD_FRONT ativo em INGLÊS" (antes: em qualquer idioma). SM3.5, SM6
e SM2 já têm imagem pt-BR; o que falta é a imagem en, que a tela conta com o filtro EN. A imagem pt
existente não é tocada (o primário é por idioma).

Contrato (igual ao da v1):
- Body {} ou {"mode":"probe"}; cartas e URLs fixas em plan.ts (119 cartas).
- Só roda com o portão public.oneshot_operation_gate (code = GATE_CODE) habilitado; lease atômico;
  lotes de até BATCH_SIZE; fecha o portão quando não sobra pendência.
- probe: HEAD nas URLs pendentes, não grava nada.
- Fail closed por carta (nome divergente, carta ausente, HTTP ≠ 2xx, MIME, < 1 KB).
- Idempotente: pula carta que já tem CARD_FRONT ativo em en; storage com upsert;
  card_external_reference com upsert por (carta, fonte, idioma).
- Grava: bucket card-front, `<set>/en/<numero>.<ext>`, card_asset (source_code POKEMON_TCG_API,
  idioma en, primário) e card_external_reference (metadata.provider = scrydex).
*/

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import { PLAN, PLAN_TOTAL, type PlanRow } from "./plan.ts";

const GATE_CODE = "SCRYDEX_ASSETS_2026_10_11";
const SOURCE_CODE = "POKEMON_TCG_API";
const LANGUAGE_CODE = "en";
const BUCKET_CODE = "card-front";
const ASSET_TYPE_CODE = "CARD_FRONT";
const BATCH_SIZE = 120;
const CONCURRENCY = 6;
const LEASE_MS = 5 * 60 * 1000;

const imageUrl = (scrydexId: string) => `https://images.scrydex.com/pokemon/${scrydexId}/large`;

const MIME_EXT: Record<string, string> = {
  "image/png": "png",
  "image/webp": "webp",
  "image/jpeg": "jpg",
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Pending = {
  setCode: string;
  cardId: string;
  number: string;
  scrydexId: string;
  scrydexName: string;
};

type Entry = Record<string, unknown>;

async function sha256Hex(buf: ArrayBuffer): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", buf);
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function fetchWithRetry(url: string, method: "GET" | "HEAD"): Promise<Response> {
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 20_000);
    try {
      const r = await fetch(url, { method, signal: ctrl.signal });
      if ((r.status === 429 || r.status >= 500) && attempt < 3) {
        await r.body?.cancel();
        await new Promise((res) => setTimeout(res, attempt * 1500));
        continue;
      }
      return r;
    } catch (e) {
      if (attempt >= 3) throw e;
      await new Promise((res) => setTimeout(res, attempt * 1500));
    } finally {
      clearTimeout(t);
    }
  }
  throw new Error("FETCH_FALHOU");
}

async function download(url: string): Promise<{ buf: ArrayBuffer; mime: string; ext: string }> {
  const r = await fetchWithRetry(url, "GET");
  if (!r.ok) {
    await r.body?.cancel();
    throw new Error(`HTTP_${r.status}`);
  }
  const mime = (r.headers.get("content-type") ?? "").split(";")[0].trim();
  const ext = MIME_EXT[mime];
  if (!ext) {
    await r.body?.cancel();
    throw new Error(`MIME_NAO_SUPORTADO: ${mime}`);
  }
  const buf = await r.arrayBuffer();
  if (buf.byteLength < 1024) throw new Error(`ARQUIVO_VAZIO: ${buf.byteLength}`);
  return { buf, mime, ext };
}

/** Executa `fn` sobre `items` com no máximo `limit` chamadas simultâneas. */
async function pool<T>(items: T[], limit: number, fn: (item: T) => Promise<void>): Promise<void> {
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const item = items[next];
      next += 1;
      await fn(item);
    }
  });
  await Promise.all(workers);
}

function tally(entries: Entry[]): Record<string, number> {
  return entries.reduce((acc: Record<string, number>, r) => {
    const s = String(r.status);
    acc[s] = (acc[s] ?? 0) + 1;
    return acc;
  }, {});
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") {
    return Response.json({ success: false, error: "METHOD_NOT_ALLOWED" }, { status: 405, headers: CORS });
  }

  let mode: "import" | "probe" = "import";
  try {
    const text = await req.text();
    if (text.trim()) {
      const body = JSON.parse(text);
      if (body?.mode === "probe") mode = "probe";
      else if (body?.mode !== undefined && body.mode !== "import") {
        return Response.json({ success: false, error: "MODE_INVALIDO" }, { status: 400, headers: CORS });
      }
    }
  } catch {
    return Response.json({ success: false, error: "BODY_INVALIDO" }, { status: 400, headers: CORS });
  }

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // Portão: probe só exige portão habilitado; import adquire o lease atomicamente.
  const leaseCutoff = new Date(Date.now() - LEASE_MS).toISOString();
  const leaseStart = new Date().toISOString();
  if (mode === "probe") {
    const { data: gate, error } = await supabase
      .from("oneshot_operation_gate").select("code").eq("code", GATE_CODE).eq("enabled", true).maybeSingle();
    if (error) return Response.json({ success: false, error: `GATE_QUERY_FAILED: ${error.message}` }, { status: 500, headers: CORS });
    if (!gate) return Response.json({ success: false, error: "GATE_CLOSED" }, { status: 409, headers: CORS });
  } else {
    const { data: gate, error } = await supabase
      .from("oneshot_operation_gate")
      .update({ consumed_at: leaseStart })
      .eq("code", GATE_CODE)
      .eq("enabled", true)
      .or(`consumed_at.is.null,consumed_at.lt.${leaseCutoff}`)
      .select("code, result")
      .maybeSingle();
    if (error) return Response.json({ success: false, error: `GATE_QUERY_FAILED: ${error.message}` }, { status: 500, headers: CORS });
    if (!gate) return Response.json({ success: false, error: "GATE_CLOSED_OR_BUSY" }, { status: 409, headers: CORS });
  }

  const one = async (table: string, col: string, val: string) => {
    const { data, error } = await supabase.from(table).select("id").eq(col, val).single();
    if (error || !data) throw new Error(`${table.toUpperCase()}_NOT_FOUND: ${val}`);
    return data.id as string;
  };

  const report: Entry[] = [];
  let remainingAfter = 0;
  try {
    const sourceId = await one("asset_source", "code", SOURCE_CODE);
    const languageId = await one("language", "code", LANGUAGE_CODE);
    const bucketId = await one("storage_bucket", "code", BUCKET_CODE);
    const assetTypeId = await one("card_asset_type", "code", ASSET_TYPE_CODE);

    // 1. Levanta as cartas pendentes (sem CARD_FRONT ativo em inglês).
    const pending: Pending[] = [];
    for (const [setCode, { sx, rows }] of Object.entries(PLAN)) {
      const setId = await one("card_set", "code", setCode);
      const { data: cards, error } = await supabase
        .from("card").select("id, collector_number, name").eq("card_set_id", setId).eq("is_active", true);
      if (error) throw new Error(`CARDS_QUERY_FAILED: ${error.message}`);
      const byNumber = new Map((cards ?? []).map((c: any) => [c.collector_number as string, c]));

      const ids = (cards ?? []).map((c: any) => c.id);
      const { data: existing, error: exError } = await supabase
        .from("card_asset").select("card_id")
        .in("card_id", ids.length ? ids : ["00000000-0000-0000-0000-000000000000"])
        .eq("asset_type_id", assetTypeId).eq("language_id", languageId).eq("is_active", true);
      if (exError) throw new Error(`ASSETS_QUERY_FAILED: ${exError.message}`);
      const done = new Set((existing ?? []).map((a: any) => a.card_id));

      for (const row of rows as readonly PlanRow[]) {
        const [number, mmkyuName, scrydexNumber, scrydexNameOverride] = row;
        const scrydexId = `${sx}-${scrydexNumber}`;
        const card = byNumber.get(number);
        if (!card) {
          report.push({ set: setCode, number, scrydexId, status: "CARTA_AUSENTE" });
          continue;
        }
        if (card.name !== mmkyuName) {
          report.push({ set: setCode, number, scrydexId, status: "NOME_DIVERGENTE", name: card.name });
          continue;
        }
        if (done.has(card.id)) continue; // já tem imagem en: fora do lote, sem ruído no relatório
        pending.push({ setCode, cardId: card.id, number, scrydexId, scrydexName: scrydexNameOverride ?? mmkyuName });
      }
    }

    // 2. Probe: só consulta as URLs, sem gravar.
    if (mode === "probe") {
      await pool(pending, 12, async (p) => {
        const { number, scrydexId } = p;
        const entry: Entry = { set: p.setCode, number, scrydexId };
        report.push(entry);
        try {
          const r = await fetchWithRetry(imageUrl(scrydexId), "HEAD");
          await r.body?.cancel();
          const mime = (r.headers.get("content-type") ?? "").split(";")[0].trim();
          entry.http = r.status;
          entry.mime = mime;
          entry.bytes = Number(r.headers.get("content-length") ?? 0) || null;
          entry.status = r.ok && MIME_EXT[mime] ? "DISPONIVEL" : "INDISPONIVEL";
        } catch (e) {
          entry.status = "INDISPONIVEL";
          entry.error = e instanceof Error ? e.message : String(e);
        }
      });
      const summary = tally(report);
      return Response.json(
        { success: true, mode, plan_total: PLAN_TOTAL, pending: pending.length, summary,
          problems: report.filter((r) => r.status !== "DISPONIVEL") },
        { headers: CORS },
      );
    }

    // 3. Import: processa um lote.
    const batch = pending.slice(0, BATCH_SIZE);
    await pool(batch, CONCURRENCY, async (p) => {
      const { number, scrydexId, scrydexName } = p;
      const url = imageUrl(scrydexId);
      const entry: Entry = { set: p.setCode, number, scrydexId };
      report.push(entry);
      try {
        const img = await download(url);
        const checksum = await sha256Hex(img.buf);
        const storagePath = `${p.setCode.toLowerCase()}/${LANGUAGE_CODE}/${number}.${img.ext}`;
        const up = await supabase.storage.from(BUCKET_CODE).upload(storagePath, img.buf, {
          contentType: img.mime, cacheControl: "3600", upsert: true,
        });
        if (up.error) throw new Error(`STORAGE_UPLOAD_FAILED: ${up.error.message}`);

        const ins = await supabase.from("card_asset").insert({
          card_id: p.cardId, asset_type_id: assetTypeId, source_code: SOURCE_CODE,
          source_reference: scrydexId, storage_path: storagePath, external_url: null,
          mime_type: img.mime, file_extension: img.ext, file_size_bytes: img.buf.byteLength,
          checksum_sha256: checksum, is_primary: true, asset_order: 1, is_active: true,
          language_id: languageId, storage_bucket_id: bucketId,
        });
        if (ins.error) throw new Error(`CARD_ASSET_INSERT_FAILED: ${ins.error.message}`);

        const ref = await supabase.from("card_external_reference").upsert({
          card_id: p.cardId, asset_source_id: sourceId, language_id: languageId,
          external_card_id: scrydexId, external_set_id: scrydexId.slice(0, scrydexId.lastIndexOf("-")),
          source_number: scrydexId.slice(scrydexId.lastIndexOf("-") + 1),
          source_url: null, image_source_url: url,
          metadata: { operation: GATE_CODE, provider: "scrydex", provider_name: scrydexName },
          is_active: true, updated_at: new Date().toISOString(),
        }, { onConflict: "card_id,asset_source_id,language_id" });
        if (ref.error) throw new Error(`CARD_EXTERNAL_REFERENCE_FAILED: ${ref.error.message}`);

        entry.status = "IMPORTADA";
        entry.bytes = img.buf.byteLength;
      } catch (e) {
        entry.status = "FALHOU";
        entry.error = e instanceof Error ? e.message : String(e);
      }
    });
    remainingAfter = pending.length - report.filter((r) => r.status === "IMPORTADA").length;
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    if (mode === "import") {
      // Só libera o lease; o histórico de lotes em `result` é preservado.
      await supabase.from("oneshot_operation_gate").update({ consumed_at: null }).eq("code", GATE_CODE);
    }
    return Response.json({ success: false, error: message, report }, { status: 500, headers: CORS });
  }

  // Libera o lease; fecha o portão quando não sobra pendência importável.
  const summary = tally(report);
  // Falhas persistentes mantêm o portão aberto para nova tentativa; fechar à mão se forem definitivas.
  const finished = remainingAfter === 0;
  const { data: gateRow } = await supabase.from("oneshot_operation_gate").select("result").eq("code", GATE_CODE).single();
  const prev = (gateRow?.result ?? {}) as { batches?: unknown[] };
  const batches = [...(Array.isArray(prev.batches) ? prev.batches : []),
    { at: leaseStart, summary, remaining_after: remainingAfter,
      failures: report.filter((r) => r.status !== "IMPORTADA") }];
  await supabase.from("oneshot_operation_gate").update({
    enabled: !finished,
    consumed_at: finished ? new Date().toISOString() : null,
    result: { plan_total: PLAN_TOTAL, remaining: remainingAfter, batches },
  }).eq("code", GATE_CODE);

  return Response.json(
    { success: true, mode, summary, remaining: remainingAfter, finished,
      failures: report.filter((r) => r.status !== "IMPORTADA") },
    { headers: CORS },
  );
});
