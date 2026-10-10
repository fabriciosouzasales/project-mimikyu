/*
Project Mimikyu — Edge Function: import-classic-collection-assets
Operação PONTUAL (2026-10-10, aprovada por Fabrício: "Importação pontual das 30.
Veja se isso se aplica também para a classic collection de 25 anos").

Por quê: a TCGdex não publica imagem para as Coleções Clássicas (30th-c e
cel25cc, 0 de 55). O pokemontcg.io publica, em subconjuntos que mantêm a
numeração da carta ORIGINAL homenageada (me55c-4 = Charizard, cel25c-15_D =
Claydol). Por isso a correspondência é uma tabela fixa, conferida carta a carta
por nome — nunca derivada do número.

Contrato:
- SEM entrada do chamador: Card Sets, números e URLs estão fixos abaixo. O body
  é ignorado. Não há como apontar a função para outra URL ou outra carta.
- Só roda com o portão `public.oneshot_operation_gate` (code = GATE_CODE)
  habilitado; o portão é consumido ANTES de qualquer download (segunda chamada
  = 409, mesmo concorrente).
- Fail closed: o Set precisa ter exatamente as cartas mapeadas; mime não
  suportado, 4xx/5xx ou checksum vazio => a carta falha e as demais seguem.
- Idempotente: carta que já tem CARD_FRONT/en ativo é pulada.
- Grava como o import-card-assets: bucket card-front, caminho
  `<set>/en/<numero>.<ext>`, card_asset (source_code POKEMON_TCG_API) e
  card_external_reference (asset_source POKEMON_TCG_API, idioma en).
- Só inglês: nenhuma fonte publica estas cartas em português.
*/

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

const GATE_CODE = "CLASSIC_COLLECTION_ASSETS_2026_10_10";
const SOURCE_CODE = "POKEMON_TCG_API";
const LANGUAGE_CODE = "en";
const BUCKET_CODE = "card-front";
const ASSET_TYPE_CODE = "CARD_FRONT";

type Item = { number: string; externalId: string; url: string; expectedName: string };
type Plan = { setCode: string; externalSetId: string; items: Item[] };

const scrydex = (id: string) => `https://images.scrydex.com/pokemon/${id}/large`;
const ptcgHires = (n: string) => `https://images.pokemontcg.io/cel25c/${n}_hires.png`;

const PLANS: Plan[] = [
  {
    setCode: "ME5.5CC",
    externalSetId: "me55c",
    items: [
      ["001", "4", "Charizard"], ["002", "5", "Delcatty"], ["003", "11", "Metagross"],
      ["004", "11g", "Genesect"], ["005", "18", "Misty"], ["006", "19", "Tyranitar"],
      ["007", "25", "Sneasel"], ["008", "33", "Zekrom"], ["009", "41", "Greninja"],
      ["010", "43", "Uxie"], ["011", "47", "Crobat"], ["012", "50", "Raikou"],
      ["013", "57", "Buzzwole"], ["014", "58", "Pikachu"], ["015", "69", "Jigglypuff"],
      ["016", "85", "Rayquaza"], ["017", "89", "Solgaleo"], ["018", "94", "Gengar"],
      ["019", "99", "Darkrai"], ["020", "100", "Darkrai"], ["021", "101", "N"],
      ["022", "106p", "Palkia"], ["023", "106m", "Gardevoir"], ["024", "106", "Celebi"],
      ["025", "108", "Scizor"], ["026", "114", "Mew"], ["027", "123", "Arceus"],
      ["028", "138", "Zacian"], ["029", "149", "Lugia"], ["030", "203", "Magikarp"],
    ].map(([number, n, expectedName]) => ({
      number, externalId: `me55c-${n}`, url: scrydex(`me55c-${n}`), expectedName,
    })),
  },
  {
    setCode: "CEL25CC",
    externalSetId: "cel25c",
    items: [
      ["CC001", "2_A", "2_A", "Blastoise"], ["CC002", "4_A", "4_A", "Charizard"],
      ["CC003", "15_A1", "15_A", "Venusaur"], ["CC004", "73_A", "73_A", "Oak"],
      ["CC005", "8_A", "8_A", "Gyarados"], ["CC006", "15_A2", "15_B", "Team Rocket"],
      ["CC007", "15_A3", "15_C", "Zapdos"], ["CC008", "24_A", "24_A", "Pikachu"],
      ["CC009", "20_A", "20_A", "Cleffa"], ["CC010", "66_A", "66_A", "Magikarp"],
      ["CC011", "9_A", "9_A", "Groudon"], ["CC012", "86_A", "86_A", "Admin"],
      ["CC013", "88_A", "88_A", "Mew"], ["CC014", "93_A", "93_A", "Gardevoir"],
      ["CC015", "17_A", "17_A", "Umbreon"], ["CC016", "15_A4", "15_D", "Claydol"],
      ["CC017", "109_A", "109_A", "Luxray"], ["CC018", "145_A", "145_A", "Garchomp"],
      ["CC019", "107_A", "107_A", "Donphan"], ["CC020", "113_A", "113_A", "Reshiram"],
      ["CC021", "114_A", "114_A", "Zekrom"], ["CC022", "54_A", "54_A", "Mewtwo"],
      ["CC023", "97_A", "97_A", "Xerneas"], ["CC024", "76_A", "76_A", "Rayquaza"],
      ["CC025", "60_A", "60_A", "Tapu Lele"],
    ].map(([number, id, img, expectedName]) => ({
      number, externalId: `cel25c-${id}`, url: ptcgHires(img), expectedName,
    })),
  },
];

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

async function sha256Hex(buf: ArrayBuffer): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", buf);
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function download(url: string): Promise<{ buf: ArrayBuffer; mime: string; ext: string }> {
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 20_000);
    try {
      const r = await fetch(url, { signal: ctrl.signal });
      if (!r.ok) {
        if ((r.status === 429 || r.status >= 500) && attempt < 3) {
          await new Promise((res) => setTimeout(res, attempt * 1500));
          continue;
        }
        throw new Error(`HTTP_${r.status}`);
      }
      const mime = (r.headers.get("content-type") ?? "").split(";")[0].trim();
      const ext = MIME_EXT[mime];
      if (!ext) throw new Error(`MIME_NAO_SUPORTADO: ${mime}`);
      const buf = await r.arrayBuffer();
      if (buf.byteLength < 1024) throw new Error(`ARQUIVO_VAZIO: ${buf.byteLength}`);
      return { buf, mime, ext };
    } catch (e) {
      if (attempt >= 3) throw e;
      await new Promise((res) => setTimeout(res, attempt * 1500));
    } finally {
      clearTimeout(t);
    }
  }
  throw new Error("DOWNLOAD_FALHOU");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") {
    return Response.json({ success: false, error: "METHOD_NOT_ALLOWED" }, { status: 405, headers: CORS });
  }

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // Consome o portão atomicamente: só uma chamada passa.
  const { data: gate, error: gateError } = await supabase
    .from("oneshot_operation_gate")
    .update({ enabled: false, consumed_at: new Date().toISOString() })
    .eq("code", GATE_CODE)
    .eq("enabled", true)
    .select("code")
    .maybeSingle();
  if (gateError) {
    return Response.json({ success: false, error: `GATE_QUERY_FAILED: ${gateError.message}` }, { status: 500, headers: CORS });
  }
  if (!gate) {
    return Response.json({ success: false, error: "GATE_CLOSED" }, { status: 409, headers: CORS });
  }

  const one = async (table: string, col: string, val: string) => {
    const { data, error } = await supabase.from(table).select("id").eq(col, val).single();
    if (error || !data) throw new Error(`${table.toUpperCase()}_NOT_FOUND: ${val}`);
    return data.id as string;
  };

  const report: Record<string, unknown>[] = [];
  try {
    const sourceId = await one("asset_source", "code", SOURCE_CODE);
    const languageId = await one("language", "code", LANGUAGE_CODE);
    const bucketId = await one("storage_bucket", "code", BUCKET_CODE);
    const assetTypeId = await one("card_asset_type", "code", ASSET_TYPE_CODE);

    for (const plan of PLANS) {
      const setId = await one("card_set", "code", plan.setCode);
      const { data: cards, error } = await supabase
        .from("card").select("id, collector_number, name").eq("card_set_id", setId).eq("is_active", true);
      if (error) throw new Error(`CARDS_QUERY_FAILED: ${error.message}`);
      const byNumber = new Map((cards ?? []).map((c: any) => [c.collector_number, c]));
      if (byNumber.size !== plan.items.length || plan.items.some((i) => !byNumber.has(i.number))) {
        throw new Error(`SET_DIVERGENTE: ${plan.setCode} tem ${byNumber.size} cartas, plano ${plan.items.length}`);
      }

      const { data: existing } = await supabase
        .from("card_asset").select("card_id")
        .in("card_id", (cards ?? []).map((c: any) => c.id))
        .eq("asset_type_id", assetTypeId).eq("language_id", languageId).eq("is_active", true);
      const done = new Set((existing ?? []).map((a: any) => a.card_id));

      for (const item of plan.items) {
        const card = byNumber.get(item.number)!;
        const entry: Record<string, unknown> = { set: plan.setCode, number: item.number, externalId: item.externalId };
        report.push(entry);
        if (!String(card.name).toLowerCase().includes(item.expectedName.toLowerCase())) {
          entry.status = "NOME_DIVERGENTE";
          entry.name = card.name;
          continue;
        }
        if (done.has(card.id)) {
          entry.status = "JA_EXISTE";
          continue;
        }
        try {
          const img = await download(item.url);
          const checksum = await sha256Hex(img.buf);
          const storagePath = `${plan.setCode.toLowerCase()}/${LANGUAGE_CODE}/${item.number}.${img.ext}`;
          const up = await supabase.storage.from(BUCKET_CODE).upload(storagePath, img.buf, {
            contentType: img.mime, cacheControl: "3600", upsert: true,
          });
          if (up.error) throw new Error(`STORAGE_UPLOAD_FAILED: ${up.error.message}`);

          const ins = await supabase.from("card_asset").insert({
            card_id: card.id, asset_type_id: assetTypeId, source_code: SOURCE_CODE,
            source_reference: item.externalId, storage_path: storagePath, external_url: null,
            mime_type: img.mime, file_extension: img.ext, file_size_bytes: img.buf.byteLength,
            checksum_sha256: checksum, is_primary: true, asset_order: 1, is_active: true,
            language_id: languageId, storage_bucket_id: bucketId,
          });
          if (ins.error) throw new Error(`CARD_ASSET_INSERT_FAILED: ${ins.error.message}`);

          const ref = await supabase.from("card_external_reference").upsert({
            card_id: card.id, asset_source_id: sourceId, language_id: languageId,
            external_card_id: item.externalId, external_set_id: plan.externalSetId,
            source_number: item.externalId.split("-").slice(1).join("-"),
            source_url: `https://api.pokemontcg.io/v2/cards/${item.externalId}`,
            image_source_url: item.url, metadata: { operation: GATE_CODE }, is_active: true,
            updated_at: new Date().toISOString(),
          }, { onConflict: "card_id,asset_source_id,language_id" });
          if (ref.error) throw new Error(`CARD_EXTERNAL_REFERENCE_FAILED: ${ref.error.message}`);

          entry.status = "IMPORTADA";
          entry.bytes = img.buf.byteLength;
          entry.path = storagePath;
        } catch (e) {
          entry.status = "FALHOU";
          entry.error = e instanceof Error ? e.message : String(e);
        }
      }
    }
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    await supabase.from("oneshot_operation_gate").update({ result: { error: message, report } }).eq("code", GATE_CODE);
    return Response.json({ success: false, error: message, report }, { status: 500, headers: CORS });
  }

  const summary = report.reduce((acc: Record<string, number>, r) => {
    const s = String(r.status);
    acc[s] = (acc[s] ?? 0) + 1;
    return acc;
  }, {});
  await supabase.from("oneshot_operation_gate").update({ result: { summary, report } }).eq("code", GATE_CODE);
  return Response.json({ success: true, summary, report }, { headers: CORS });
});
