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

// Timeout explícito (2026-08-15, correção do incidente SV10) — mesmo motivo
// e mesmo padrão de TCGDEX_METADATA_TIMEOUT_MS (services/tcgdex.ts) e de
// IMAGE_DOWNLOAD_TIMEOUT_MS (import-card-assets/services/storage.ts):
// qualquer uma das duas superfícies HTTP deste arquivo pendurada sem
// resposta consumia sozinha todo o orçamento de execução da Edge Function,
// sem o código nunca chegar ao catch()/failVariantJob(). Um valor único
// para as duas chamadas — a listagem (1x por Set) e o conteúdo (1x por
// Card, em lote) têm o mesmo perfil de payload pequeno.
const GITHUB_FETCH_TIMEOUT_MS = 15000;

export type GithubCardFile = {
  name: string;
  downloadUrl: string;
};

export async function listSetCardFiles(serieName: string, setName: string): Promise<GithubCardFile[]> {
  const path = `data/${encodeURIComponent(serieName)}/${encodeURIComponent(setName)}`;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), GITHUB_FETCH_TIMEOUT_MS);

  let response: Response;
  try {
    response = await fetch(`${GITHUB_CONTENTS_BASE}/${path}`, {
      headers: { Accept: "application/vnd.github+json" },
      signal: controller.signal,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error(`GITHUB_CONTENTS_TIMEOUT: sem resposta em ${GITHUB_FETCH_TIMEOUT_MS}ms`);
    }
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }

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
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), GITHUB_FETCH_TIMEOUT_MS);

  let response: Response;
  try {
    response = await fetch(downloadUrl, { signal: controller.signal });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error(`GITHUB_RAW_TIMEOUT: sem resposta em ${GITHUB_FETCH_TIMEOUT_MS}ms`);
    }
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }

  if (!response.ok) {
    throw new Error(`GITHUB_RAW_HTTP_${response.status}`);
  }
  return await response.text();
}

export function deriveLocalIdFromFilename(filename: string): string {
  return filename.replace(/\.ts$/, "");
}

// =====================================================================
// SHAPE DA FONTE DE VARIANTE (SOURCE-VARIANT-SAFETY-01, 2026-09-18)
//
// A TCGdex tem mais de uma forma real para `variants` dentro de
// `data/<Serie>/<Set>/*.ts`, e a auditoria SOURCE-VARIANT-SCHEMA-
// COVERAGE-AUDIT-01 mediu a distribuição nos 169 Card Sets elegíveis:
//
//   ARRAY        `variants: [ {type,foil,subtype,stamp,size}, ... ]`
//                → 113 Sets puros. ÚNICA forma que este parser extrai.
//   OBJECT       `variants: { normal, reverse, holo, firstEdition }`
//                → 2 Sets (SWSH1, SWSH3.5). NÃO convertida aqui: o objeto
//                  não carrega `foil` nem `subtype` (os dois eixos do
//                  modelo C2, ADR-028) e fixa `size` em "standard".
//                  Converter fabricaria significado editorial.
//   ABSENT       sem a chave `variants` → 46 Sets. O compilador da TCGdex
//                (server/compiler/utils/cardUtil.ts) preenche o vazio com
//                `normal: true` hardcoded e marca `variantId:"generated"`.
//                Isso é SUPOSIÇÃO do compilador, não dado da fonte.
//   ARRAY_EMPTY  `variants: []` — array presente e deliberadamente vazio.
//                Distinto de ABSENT: aqui a fonte AFIRMA que não há
//                variante; em ABSENT ela apenas não diz nada.
//   UNSUPPORTED  qualquer outra forma (valor que não é `[` nem `{`,
//                array não terminado). Fail-closed por construção.
//
// POR QUE A ÂNCORA IMPORTA (fail-open fechado nesta rodada): a versão
// anterior fazia `indexOf("variants:")` e depois `indexOf("[", …)` — ou
// seja, pegava o PRÓXIMO colchete do arquivo, não o valor de `variants`.
// Num arquivo OBJECT, o próximo `[` é de OUTRO campo, e se esse campo for
// um array de objetos com a chave `type` (`weaknesses`, `abilities`,
// `resistances`) o parser devolvia variantes FABRICADAS — provado:
// `variants:{…} + weaknesses:[{type:"Fire"}]` → `[{type:"Fire"}]`.
// Nos arquivos reais o `variants` vem depois desses campos, então o bug
// nunca disparou — segurança por sorte de ordenação, não por contrato.
// Agora o valor é lido EXATAMENTE na posição que segue os dois-pontos.
//
// Continua valendo: extração estrutural por profundidade de colchetes,
// NUNCA eval/Function (rodar código de terceiro dentro de uma Edge
// Function com service role é inaceitável).
// =====================================================================

export type VariantSourceShape = "ARRAY" | "ARRAY_EMPTY" | "OBJECT" | "ABSENT" | "UNSUPPORTED";

export type VariantSourceParse = {
  shape: VariantSourceShape;
  /** Só pode ser não-vazio quando `shape === "ARRAY"`. */
  combos: ExternalVariantCombo[];
};

export function parseVariantSource(source: string): VariantSourceParse {
  const valueAt = locateVariantsValue(source);
  if (valueAt === null) return { shape: "ABSENT", combos: [] };

  const ch = source[valueAt];
  if (ch === "{") return { shape: "OBJECT", combos: [] };
  if (ch !== "[") return { shape: "UNSUPPORTED", combos: [] };

  const block = readBracketBlockAt(source, valueAt);
  if (block === null) return { shape: "UNSUPPORTED", combos: [] };
  if (block.trim() === "") return { shape: "ARRAY_EMPTY", combos: [] };

  // ALL-OR-NOTHING (CORRECTION-01). Antes, um array com um objeto válido e
  // outro ilegível devolvia `ARRAY` com os combos que deram certo — sucesso
  // PARCIAL silencioso, exatamente a classe de erro que esta frente existe
  // para eliminar. Agora: ou TODOS os objetos top-level são reconhecidos e
  // têm `type` string não-vazia, ou o array inteiro é UNSUPPORTED.
  const objects = splitTopLevelObjects(block);

  // Bloco não vazio que não produz nenhum objeto top-level: há conteúdo ali
  // que este parser não sabe ler (array de escalares, sintaxe nova, lixo).
  // Fail-closed — nunca tratar como "sem variantes".
  if (objects.length === 0) return { shape: "UNSUPPORTED", combos: [] };

  const combos: ExternalVariantCombo[] = [];
  for (const obj of objects) {
    const type = extractStringField(obj, "type");
    if (typeof type !== "string" || type.length === 0) {
      return { shape: "UNSUPPORTED", combos: [] };
    }
    combos.push({
      type,
      foil: extractStringField(obj, "foil"),
      subtype: extractStringField(obj, "subtype"),
      stamp: extractStampArray(obj),
      // size (2026-09-15, incidente JUMBO): antes era descartado aqui, o que
      // fazia uma variante `size: "jumbo"` entrar no pipeline como se fosse
      // padrão. Preservado bruto, sem interpretação — a classificação de
      // escopo acontece no index.ts.
      size: extractStringField(obj, "size"),
    });
  }

  // INVARIANTE: `shape === "ARRAY"` ⇒ `combos.length >= 1`. Um array vazio
  // já saiu como ARRAY_EMPTY; qualquer objeto ilegível já saiu como
  // UNSUPPORTED. `thirdParty` e quaisquer outros campos aninhados não
  // integram identidade e são simplesmente ignorados — a contagem de
  // profundidade de `splitTopLevelObjects` os mantém dentro do objeto pai.
  return { shape: "ARRAY", combos };
}

/** Compatibilidade: mesma saída de antes para quem só precisa dos combos. */
export function extractVariantsFromSource(source: string): ExternalVariantCombo[] {
  return parseVariantSource(source).combos;
}

/**
 * Devolve o índice do primeiro caractere do VALOR de `variants`, ou null se
 * a chave não existir. Âncora estrutural:
 *   - `(?:^|[^A-Za-z0-9_$])` impede casar sufixo de outro identificador;
 *   - exige `:` logo após o nome, tolerando whitespace dos dois lados
 *     (`variants:`, `variants :`, `variants\n\t:` são equivalentes);
 *   - por exigir o `:` colado ao nome, `variants_detailed:` NUNCA casa.
 */
function locateVariantsValue(source: string): number | null {
  const match = /(?:^|[^A-Za-z0-9_$])variants[ \t\r\n]*:[ \t\r\n]*/.exec(source);
  if (!match) return null;
  const valueAt = match.index + match[0].length;
  return valueAt < source.length ? valueAt : null;
}

/**
 * Lê o bloco `[...]` que COMEÇA exatamente em `start`. Nunca procura um
 * colchete adiante: se `source[start]` não for `[`, é erro do chamador.
 * Devolve null quando o array não é terminado (fonte malformada).
 */
function readBracketBlockAt(source: string, start: number): string | null {
  if (source[start] !== "[") return null;
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
