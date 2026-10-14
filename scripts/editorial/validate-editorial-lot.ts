/*
Project Mimikyu
Script offline: validate-editorial-lot
Pokédex P3e — validação do JSON editorial MMKYU pt-BR (2026-10-12).

O que faz
  Confere um lote editorial (ex.: database/proposals/2026-10-12-pokedex-p3e-editorial-lote-01/
  lote-01-pt-BR.json) antes de cada revisão e, no fim, antes de gerar a seed de publicação:
    - formato e campos obrigatórios de cada entrada;
    - quantidade, unicidade e pertença à seleção aprovada;
    - estados (PROPOSTO, APROVADO, REPROVADO) e, com --require-approved, lote 100% aprovado;
    - md5 e tamanho declarados de cada texto (mesmo md5() do Postgres, UTF-8);
    - conflito com espécies de lotes já publicados (--published, repetível);
    - padrões proibidos pelo guia editorial v0.2 e termos a evitar do glossário do lote;
    - base factual: md5 da descrição/classificação oficial usada vs. snapshot do LIVE (--snapshot).

O que NÃO faz
  Não substitui a revisão de precisão factual, originalidade ou qualidade narrativa.
  Não acessa rede nem banco: o snapshot é gerado à parte por uma consulta só de leitura
  (source-snapshot.sql da pasta do lote). Não grava nada.

Uso (Deno ou Node 22+, sem dependências)
  deno run --allow-read scripts/editorial/validate-editorial-lot.ts --lot <arquivo> \
    [--published <json>]... [--snapshot <json>] [--require-approved]
  node --experimental-strip-types scripts/editorial/validate-editorial-lot.ts --lot <arquivo> ...

Saída: relatório legível; código de saída 1 se houver ERRO (avisos não bloqueiam).

Preparação para 6137/6848: as funções exportadas (loadLot, validateLot) são o ponto de entrada
para a futura geração determinística da seed — a geração só deve rodar sobre um lote que passe
com --require-approved.
*/

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import process from "node:process";

export type Severity = "ERRO" | "AVISO";
export type Finding = { severity: Severity; dex: number | null; code: string; message: string };

export type LotEntry = {
  national_dex_number: number;
  species_name: string;
  language: string;
  origin: string;
  status: string;
  genus: string;
  description: string;
  description_length: number;
  facts: string[];
  content_md5: { genus: string; description: string };
  source_basis: { flavor_version: string; flavor_md5: string; genus_md5: string };
  [key: string]: unknown;
};

export type GlossaryTerm = { source: string; pt: string; avoid?: string[]; note?: string };

export type Lot = {
  batch: string;
  guide_version: string;
  revision: number;
  selection: number[];
  glossary?: GlossaryTerm[];
  entries: LotEntry[];
  [key: string]: unknown;
};

export type SnapshotSpecies = {
  national_dex_number: number;
  species_name: string;
  flavor_version: string;
  flavor_md5: string;
  genus_md5: string;
  editorial_rows: number;
};

export const VALID_STATUSES = ["PROPOSTO", "APROVADO", "REPROVADO"] as const;
export const DESCRIPTION_SOFT_MIN = 120;
export const DESCRIPTION_SOFT_MAX = 320;
export const DESCRIPTION_HARD_MAX = 2000;

/**
 * Palavra(s) inteira(s) com limites Unicode. Em JavaScript, \b só reconhece letras ASCII
 * ("você", "pés", "única" escapariam); hífen conta como parte da palavra ("lembra-me").
 */
export function words(alternatives: string): RegExp {
  return new RegExp(`(?<![\\p{L}\\p{N}-])(?:${alternatives})(?![\\p{L}\\p{N}-])`, "iu");
}

// Padrões do guia v0.2. ERRO = viola regra explícita; AVISO = exige olhar humano.
const FORBIDDEN: Array<{ re: RegExp; severity: Severity; code: string; message: string }> = [
  { re: words("vocês?"), severity: "ERRO", code: "VOZ_SEGUNDA_PESSOA", message: "uso de \"você\"" },
  { re: /!/u, severity: "ERRO", code: "EXCLAMACAO", message: "ponto de exclamação" },
  { re: words("eu|me|meu|minha|meus|minhas|nós|nosso|nossa|nossos|nossas"), severity: "ERRO", code: "PRIMEIRA_PESSOA", message: "primeira pessoa (converter em relato atribuído)" },
  { re: words("mph|milhas?|pés|polegadas?|libras?|feet|foot|inch|inches|pounds?|lbs?"), severity: "ERRO", code: "UNIDADE_IMPERIAL", message: "unidade imperial (usar sistema métrico)" },
  { re: words("tradução|traduzido|traduzida|oficial|oficiais"), severity: "ERRO", code: "ATRIBUICAO", message: "texto editorial não se apresenta como tradução ou oficial" },
  { re: words("únic[oa]s?|(?:o|a|os|as) mais"), severity: "AVISO", code: "SUPERLATIVO", message: "superlativo/exclusividade — confirmar suporte na base" },
  { re: words("sempre|nunca|todos|todas|qualquer|absolut[oa]s?|jamais"), severity: "AVISO", code: "ABSOLUTO", message: "afirmação absoluta — confirmar suporte na base" },
];

const MD5_RE = /^[0-9a-f]{32}$/;

export function md5(text: string): string {
  return createHash("md5").update(text, "utf8").digest("hex");
}

/** Comprimento como o length() do Postgres (pontos de código), não unidades UTF-16. */
export function pgLength(text: string): number {
  return Array.from(text).length;
}

function textShapeFindings(dex: number, field: string, text: string): Finding[] {
  const out: Finding[] = [];
  if (text !== text.normalize("NFC")) out.push({ severity: "ERRO", dex, code: "NAO_NFC", message: `${field} não está em Unicode NFC` });
  if (text !== text.trim()) out.push({ severity: "ERRO", dex, code: "ESPACO_BORDA", message: `${field} com espaço no início ou fim` });
  if (/ {2,}|\t|\r|\n/u.test(text)) out.push({ severity: "ERRO", dex, code: "ESPACAMENTO", message: `${field} com espaço duplo, tabulação ou quebra de linha` });
  return out;
}

export function validateLot(
  lot: Lot,
  opts: { published?: Set<number>; snapshot?: SnapshotSpecies[]; requireApproved?: boolean } = {},
): Finding[] {
  const findings: Finding[] = [];
  const err = (dex: number | null, code: string, message: string) => findings.push({ severity: "ERRO", dex, code, message });
  const warn = (dex: number | null, code: string, message: string) => findings.push({ severity: "AVISO", dex, code, message });

  // Cabeçalho do lote
  for (const key of ["batch", "guide_version"] as const) {
    if (typeof lot[key] !== "string" || !(lot[key] as string).trim()) err(null, "CABECALHO", `campo "${key}" ausente`);
  }
  if (!Number.isInteger(lot.revision) || lot.revision < 1) err(null, "CABECALHO", "campo \"revision\" deve ser inteiro ≥ 1");
  if (!Array.isArray(lot.selection) || lot.selection.length === 0) {
    err(null, "SELECAO", "\"selection\" ausente ou vazia");
    return findings;
  }
  if (!Array.isArray(lot.entries)) {
    err(null, "ENTRADAS", "\"entries\" ausente");
    return findings;
  }

  const selection = new Set<number>();
  for (const n of lot.selection) {
    if (!Number.isInteger(n) || n < 1) err(null, "SELECAO", `número inválido na seleção: ${n}`);
    else if (selection.has(n)) err(n, "SELECAO_DUPLICADA", "número repetido na seleção");
    else selection.add(n);
  }

  const published = opts.published ?? new Set<number>();
  for (const n of selection) {
    if (published.has(n)) err(n, "JA_PUBLICADA", "espécie da seleção já tem editorial publicado em outro lote");
  }

  const snapshotByDex = new Map<number, SnapshotSpecies>();
  for (const s of opts.snapshot ?? []) snapshotByDex.set(s.national_dex_number, s);
  if (opts.snapshot) {
    for (const n of selection) if (!snapshotByDex.has(n)) err(n, "SNAPSHOT_AUSENTE", "espécie da seleção ausente do snapshot");
  }

  const seen = new Set<number>();
  const genusSeen = new Map<string, number>();
  const descSeen = new Map<string, number>();
  const avoid = (lot.glossary ?? []).flatMap((g) => (g.avoid ?? []).map((a) => ({ term: a, preferred: g.pt })));

  for (const e of lot.entries) {
    const dex = Number.isInteger(e?.national_dex_number) ? e.national_dex_number : null;
    if (dex === null) {
      err(null, "ENTRADA", "entrada sem national_dex_number inteiro");
      continue;
    }
    if (seen.has(dex)) err(dex, "ENTRADA_DUPLICADA", "mais de uma entrada para a mesma espécie");
    seen.add(dex);
    if (!selection.has(dex)) err(dex, "FORA_DA_SELECAO", "entrada não pertence à seleção aprovada");
    if (published.has(dex)) err(dex, "JA_PUBLICADA", "entrada para espécie já publicada");

    if (e.language !== "pt-BR") err(dex, "IDIOMA", "language deve ser pt-BR");
    if (e.origin !== "MMKYU_EDITORIAL") err(dex, "ORIGEM", "origin deve ser MMKYU_EDITORIAL");
    if (!(VALID_STATUSES as readonly string[]).includes(e.status)) err(dex, "ESTADO", `estado inválido: ${e.status}`);
    if (typeof e.species_name !== "string" || !e.species_name) err(dex, "NOME", "species_name ausente");

    const genus = typeof e.genus === "string" ? e.genus : "";
    const desc = typeof e.description === "string" ? e.description : "";
    if (!genus) err(dex, "CLASSIFICACAO", "genus ausente");
    if (!desc) err(dex, "DESCRICAO", "description ausente");

    if (genus) {
      findings.push(...textShapeFindings(dex, "genus", genus));
      if (!/^Pokémon \S/u.test(genus)) err(dex, "CLASSIFICACAO_FORMA", "classificação deve começar por \"Pokémon \"");
      if (pgLength(genus) > 60) err(dex, "CLASSIFICACAO_TAMANHO", "classificação acima de 60 caracteres");
      const prev = genusSeen.get(genus);
      if (prev !== undefined) warn(dex, "CLASSIFICACAO_REPETIDA", `mesma classificação de #${prev}`);
      genusSeen.set(genus, dex);
    }

    if (desc) {
      findings.push(...textShapeFindings(dex, "description", desc));
      const len = pgLength(desc);
      if (len > DESCRIPTION_HARD_MAX) err(dex, "DESCRICAO_TAMANHO", `descrição acima de ${DESCRIPTION_HARD_MAX} caracteres`);
      else if (len < DESCRIPTION_SOFT_MIN || len > DESCRIPTION_SOFT_MAX) warn(dex, "DESCRICAO_FAIXA", `descrição com ${len} caracteres (referência ${DESCRIPTION_SOFT_MIN}–${DESCRIPTION_SOFT_MAX})`);
      if (e.description_length !== len) err(dex, "TAMANHO_DECLARADO", `description_length ${e.description_length} ≠ ${len}`);
      if (!/[.…]$/u.test(desc)) warn(dex, "PONTUACAO_FINAL", "descrição não termina com ponto");
      const prev = descSeen.get(desc);
      if (prev !== undefined) err(dex, "DESCRICAO_REPETIDA", `descrição idêntica à de #${prev}`);
      descSeen.set(desc, dex);

      for (const rule of FORBIDDEN) {
        if (rule.re.test(desc) || (rule.code !== "SUPERLATIVO" && rule.code !== "ABSOLUTO" && rule.re.test(genus))) {
          findings.push({ severity: rule.severity, dex, code: rule.code, message: rule.message });
        }
      }
      for (const a of avoid) {
        const re = words(a.term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
        if (re.test(desc) || re.test(genus)) err(dex, "GLOSSARIO", `termo a evitar "${a.term}" (usar "${a.preferred}")`);
      }
    }

    // Integridade declarada
    const cm = e.content_md5;
    if (!cm || !MD5_RE.test(cm.genus ?? "") || !MD5_RE.test(cm.description ?? "")) {
      err(dex, "MD5_AUSENTE", "content_md5.genus/description ausentes ou mal formados");
    } else {
      if (genus && cm.genus !== md5(genus)) err(dex, "MD5_CLASSIFICACAO", "content_md5.genus não confere com o texto");
      if (desc && cm.description !== md5(desc)) err(dex, "MD5_DESCRICAO", "content_md5.description não confere com o texto");
    }

    if (!Array.isArray(e.facts) || e.facts.length === 0) err(dex, "FATOS", "lista \"facts\" vazia");

    // Base factual
    const sb = e.source_basis;
    if (!sb || !MD5_RE.test(sb.flavor_md5 ?? "") || !MD5_RE.test(sb.genus_md5 ?? "") || !sb.flavor_version) {
      err(dex, "BASE_AUSENTE", "source_basis (flavor_version, flavor_md5, genus_md5) ausente ou mal formado");
    } else if (opts.snapshot) {
      const snap = snapshotByDex.get(dex);
      if (snap) {
        if (snap.flavor_md5 !== sb.flavor_md5 || snap.flavor_version !== sb.flavor_version) {
          err(dex, "FONTE_ALTERADA", `descrição oficial mudou (${sb.flavor_version}/${sb.flavor_md5.slice(0, 8)} → ${snap.flavor_version}/${snap.flavor_md5.slice(0, 8)}) — revisar o texto`);
        }
        if (snap.genus_md5 !== sb.genus_md5) err(dex, "FONTE_ALTERADA", "classificação oficial mudou — revisar a classificação");
        if (snap.editorial_rows !== 0) err(dex, "EDITORIAL_EXISTENTE", `LIVE já tem ${snap.editorial_rows} linha(s) editorial(is) para a espécie`);
        if (snap.species_name !== e.species_name) err(dex, "NOME", `species_name "${e.species_name}" ≠ "${snap.species_name}"`);
      }
    }
  }

  if (opts.requireApproved) {
    for (const n of selection) {
      const e = lot.entries.find((x) => x?.national_dex_number === n);
      if (!e) err(n, "PENDENTE", "espécie da seleção sem entrada redigida");
      else if (e.status !== "APROVADO") err(n, "NAO_APROVADO", `estado ${e.status} — publicação exige APROVADO`);
    }
  }

  return findings;
}

export function loadJson<T>(path: string): T {
  return JSON.parse(readFileSync(path, "utf8")) as T;
}

/** Números de espécies publicadas a partir de JSONs de lotes já publicados (formato do piloto P3d). */
export function publishedNumbers(lots: Array<{ entries?: Array<{ national_dex_number: number }>; publication?: { published?: boolean } }>): Set<number> {
  const out = new Set<number>();
  for (const l of lots) {
    if (l.publication && l.publication.published !== true) continue;
    for (const e of l.entries ?? []) out.add(e.national_dex_number);
  }
  return out;
}

function parseArgs(argv: string[]) {
  const args = { lot: "", published: [] as string[], snapshot: "", requireApproved: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--lot") args.lot = argv[++i] ?? "";
    else if (a === "--published") args.published.push(argv[++i] ?? "");
    else if (a === "--snapshot") args.snapshot = argv[++i] ?? "";
    else if (a === "--require-approved") args.requireApproved = true;
    else throw new Error(`argumento desconhecido: ${a}`);
  }
  if (!args.lot) throw new Error("informe --lot <arquivo.json>");
  return args;
}

function main(): number {
  const args = parseArgs(process.argv.slice(2));
  const lot = loadJson<Lot>(args.lot);
  const published = publishedNumbers(args.published.map((p) => loadJson(p)));
  const snapshot = args.snapshot ? loadJson<{ species: SnapshotSpecies[] }>(args.snapshot).species : undefined;
  const findings = validateLot(lot, { published, snapshot, requireApproved: args.requireApproved });

  const byStatus = new Map<string, number>();
  for (const e of lot.entries ?? []) byStatus.set(e.status, (byStatus.get(e.status) ?? 0) + 1);
  const errors = findings.filter((f) => f.severity === "ERRO");
  const warnings = findings.filter((f) => f.severity === "AVISO");

  console.log(`Lote ${lot.batch} · revisão ${lot.revision} · guia ${lot.guide_version}`);
  console.log(`Seleção: ${lot.selection?.length ?? 0} · entradas: ${lot.entries?.length ?? 0} · ${[...byStatus].map(([k, v]) => `${k} ${v}`).join(" · ") || "sem entradas"}`);
  console.log(`Publicadas consideradas: ${published.size} · snapshot: ${snapshot ? `${snapshot.length} espécies` : "não informado"}`);
  for (const f of [...errors, ...warnings]) {
    console.log(`${f.severity.padEnd(5)} ${f.dex === null ? "lote " : `#${String(f.dex).padStart(4, "0")}`} ${f.code}: ${f.message}`);
  }
  console.log(errors.length ? `RESULTADO: FALHA (${errors.length} erro(s), ${warnings.length} aviso(s))` : `RESULTADO: OK (${warnings.length} aviso(s) para revisão humana)`);
  return errors.length ? 1 : 0;
}

const isMain = (() => {
  const meta = import.meta as unknown as { main?: boolean; url: string };
  if (typeof meta.main === "boolean") return meta.main;
  const entry = process.argv[1];
  return !!entry && meta.url.endsWith(entry.replace(/\\/g, "/").split("/").pop() ?? "\u0000");
})();

if (isMain) {
  try {
    process.exitCode = main();
  } catch (e) {
    console.error(`ERRO  ${(e as Error).message}`);
    process.exitCode = 2;
  }
}
