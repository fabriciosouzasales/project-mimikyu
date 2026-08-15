// Project Mimikyu — Edge Function: import-card-variants
// GitHub Source Service — dataset-fonte da TCGdex
// (github.com/tcgdex/cards-database), fonte primária de Card Variant
// (classificação B, frente de validação da fonte, 2026-08-15): a API
// pública simplifica type/foil/subtype/stamp em booleans; o dataset-fonte
// preserva a granularidade que card_variant_type_external_mapping (Query
// 2140) exige.
//
// Duas superfícies HTTP distintas, deliberadamente:
// - api.github.com (Contents API): só para LISTAR os arquivos de um Set
//   (1 chamada por Set) — sujeita a rate limit de 60/h sem autenticação
//   (confirmado esgotado uma vez na frente de validação da fonte), por
//   isso usada o mínimo possível — nunca 1x por carta.
// - raw.githubusercontent.com: para o CONTEÚDO de cada arquivo de carta —
//   sem rate limit observado nesta sessão; é onde o volume real de
//   chamadas acontece (uma por carta do Set), sempre em lotes de
//   concorrência limitada (ver index.ts, mesmo padrão de
//   CARD_DETAIL_BATCH_SIZE de import-catalog-cards).
//
// Os arquivos-fonte são TypeScript, não JSON (confirmado ao vivo nesta
// checagem, ex. data/Mega Evolution/Ascended Heroes/002.ts: chaves sem
// aspas, aspas simples em valores, vírgula final). JSON.parse não serve.
// NUNCA executamos esse conteúdo (eval/Function seria rodar código de
// terceiro não confiável dentro de uma Edge Function com service role —
// inaceitável). extractVariantsFromSource() faz extração estrutural por
// contagem de profundidade de colchetes/chaves, limitada estritamente aos
// 4 campos que interessam (type/foil/subtype/stamp) — nunca interpreta
// thirdParty nem qualquer outro campo do arquivo.

import type { ExternalVariantCombo } from "../types.ts";

const GITHUB_CONTENTS_BASE = "https://api.github.com/repos/tcgdex/cards-database/contents";

export type GithubCardFile = {
  name: string;
  downloadUrl: string;
};

export async function listSetCardFiles(serieName: string, setName: string): Promise<GithubCardFile[]> {
  const path = `data/${encodeURIComponent(serieName)}/${encodeURIComponent(setName)}`;
  const response = await fetch(`${GITHUB_CONTENTS_BASE}/${path}`, {
    headers: { Accept: "application/vnd.github+json" },
  });
  if (!response.ok) {
    throw new Error(`GITHUB_CONTENTS_HTTP_${response.status}`);
  }

  const entries = await response.json();
  if (!Array.isArray(entries)) {
    throw new Error("GITHUB_CONTENTS_UNEXPECTED_SHAPE");
  }

  return entries
    .filter((entry: any) => entry?.type === "file" && typeof entry?.name === "string" && entry.name.endsWith(".ts"))
    .map((entry: any) => ({ name: entry.name, downloadUrl: entry.download_url }));
}

export async function fetchCardFileSource(downloadUrl: string): Promise<string> {
  const response = await fetch(downloadUrl);
  if (!response.ok) {
    throw new Error(`GITHUB_RAW_HTTP_${response.status}`);
  }
  return await response.text();
}

export function deriveLocalIdFromFilename(filename: string): string {
  return filename.replace(/\.ts$/, "");
}

// Extração estrutural por profundidade de colchetes — nunca eval/Function.
// Assume a mesma sintaxe observada em todos os arquivos-fonte reais
// testados nesta frente (chaves sem aspas, aspas simples ou duplas em
// valores, vírgulas finais permitidas).
export function extractVariantsFromSource(source: string): ExternalVariantCombo[] {
  const block = extractBracketBlock(source, "variants");
  if (!block) return [];

  return splitTopLevelObjects(block)
    .map((obj) => ({
      type: extractStringField(obj, "type"),
      foil: extractStringField(obj, "foil"),
      subtype: extractStringField(obj, "subtype"),
      stamp: extractStampArray(obj),
    }))
    .filter((combo): combo is ExternalVariantCombo => typeof combo.type === "string" && combo.type.length > 0);
}

function extractBracketBlock(source: string, key: string): string | null {
  const keyIndex = source.indexOf(`${key}:`);
  if (keyIndex === -1) return null;
  const start = source.indexOf("[", keyIndex);
  if (start === -1) return null;

  let depth = 0;
  for (let i = start; i < source.length; i++) {
    const ch = source[i];
    if (ch === "[") depth++;
    else if (ch === "]") {
      depth--;
      if (depth === 0) return source.slice(start + 1, i);
    }
  }
  return null;
}

function splitTopLevelObjects(block: string): string[] {
  const objects: string[] = [];
  let depth = 0;
  let start = -1;
  for (let i = 0; i < block.length; i++) {
    const ch = block[i];
    if (ch === "{") {
      if (depth === 0) start = i;
      depth++;
    } else if (ch === "}") {
      depth--;
      if (depth === 0 && start !== -1) {
        objects.push(block.slice(start, i + 1));
        start = -1;
      }
    }
  }
  return objects;
}

function extractStringField(obj: string, field: string): string | null {
  const match = obj.match(new RegExp(`(?:^|[,{\\s])${field}\\s*:\\s*["']([^"']*)["']`));
  return match ? match[1] : null;
}

function extractStampArray(obj: string): string[] | null {
  const match = obj.match(/stamp\s*:\s*\[([^\]]*)\]/);
  if (!match) return null;
  const items = [...match[1].matchAll(/["']([^"']*)["']/g)].map((m) => m[1]);
  return items.length > 0 ? items : null;
}
