import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  type ConditionTally,
  conditionDistributionAccessible,
  conditionDistributionText,
  conditionParts,
  summarizeCopyPlacement,
  tallyConditions,
} from "./condition-distribution.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
const A = "00000000-0000-4000-8000-0000000000a1";
const B = "00000000-0000-4000-8000-0000000000b2";
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const at = (r: Record<string, ConditionTally>, k: string): ConditionTally => {
  const t = r[k];
  assert.ok(t, `distribuição de ${k}`);
  return t;
};
const sum = (t: ConditionTally) => Object.values(t.counts).reduce((s, n) => s + n, 0) + t.unrecognized;

test("tally: ordem canônica M, NM, SP, MP, HP, DM; LP→SP, DMG→DM", () => {
  const t = tallyConditions(["DMG", "LP", "NM", "M", "HP", "MP", "NM"]);
  assert.deepEqual(conditionParts(t).map((p) => p.short), ["M", "NM", "SP", "MP", "HP", "DM"]);
  assert.equal(conditionDistributionText(t), "M ×1 · NM ×2 · SP ×1 · MP ×1 · HP ×1 · DM ×1");
  assert.equal(t.total, 7);
  assert.equal(sum(t), 7);
});

test("tally: código inesperado ou ausente não vira condição (nem NM)", () => {
  const t = tallyConditions(["NM", "nm", "XX", null, undefined, "LP"]);
  assert.equal(t.counts.NM, 1, "caixa exata: 'nm' não é NM");
  assert.equal(t.unrecognized, 4);
  assert.equal(sum(t), t.total);
  assert.deepEqual(conditionParts(t).map((p) => p.code), ["NM", "LP"], "só as seis condições válidas");
  assert.equal(conditionDistributionText(t), "NM ×1 · SP ×1 · Condição não reconhecida ×4");
  assert.equal(conditionDistributionAccessible(t), "Condições declaradas: 1 Near Mint, 1 Slightly Played, 4 sem condição reconhecida");
  assert.ok(!conditionDistributionText(t).includes("XX"));
});

test("tally vazio: nada a exibir", () => {
  const t = tallyConditions([]);
  assert.equal(conditionDistributionText(t), "");
  assert.equal(conditionDistributionAccessible(t), "");
});

test("placement: várias condições no mesmo local", () => {
  const copies = [
    { physicalCardId: id(1), conditionCode: "NM" },
    { physicalCardId: id(2), conditionCode: "NM" },
    { physicalCardId: id(3), conditionCode: "LP" },
  ];
  const p = summarizeCopyPlacement(copies, new Map(copies.map((c) => [c.physicalCardId, A])))!;
  assert.deepEqual(p.byStorage, { [A]: 3 });
  assert.equal(conditionDistributionText(at(p.conditionsByStorage, A)), "NM ×2 · SP ×1");
  assert.equal(conditionDistributionText(p.conditions), "NM ×2 · SP ×1");
  assert.equal(p.unlocated, 0);
  assert.equal(p.unlocatedConditions.total, 0);
});

test("placement: mesma carta em vários locais + sem localização; Σ por local = quantidade do local; Σ geral = total", () => {
  const copies = [
    { physicalCardId: id(1), conditionCode: "NM" },
    { physicalCardId: id(2), conditionCode: "MP" },
    { physicalCardId: id(3), conditionCode: "NM" },
    { physicalCardId: id(4), conditionCode: "DMG" },
    { physicalCardId: id(5), conditionCode: "M" },
    { physicalCardId: id(6), conditionCode: "bogus" },
  ];
  const where = new Map<string, string | null>([
    [id(1), A],
    [id(2), A],
    [id(3), B],
    [id(4), null],
    [id(5), null],
    [id(6), B],
  ]);
  const p = summarizeCopyPlacement(copies, where)!;
  assert.equal(p.total, 6);
  assert.deepEqual(p.byStorage, { [A]: 2, [B]: 2 });
  assert.equal(p.unlocated, 2);
  assert.equal(conditionDistributionText(at(p.conditionsByStorage, A)), "NM ×1 · MP ×1");
  assert.equal(conditionDistributionText(at(p.conditionsByStorage, B)), "NM ×1 · Condição não reconhecida ×1");
  assert.equal(conditionDistributionText(p.unlocatedConditions), "M ×1 · DM ×1");
  assert.equal(conditionDistributionText(p.conditions), "M ×1 · NM ×2 · MP ×1 · DM ×1 · Condição não reconhecida ×1");
  for (const [storage, n] of Object.entries(p.byStorage)) {
    assert.equal(at(p.conditionsByStorage, storage).total, n);
    assert.equal(sum(at(p.conditionsByStorage, storage)), n);
  }
  assert.equal(sum(p.unlocatedConditions), p.unlocated);
  assert.equal(sum(p.conditions), p.total);
  assert.equal(Object.values(p.byStorage).reduce((s, n) => s + n, 0) + p.unlocated, p.total);
});

test("placement: exemplar sem local resolvido → null (nunca números parciais)", () => {
  const copies = [
    { physicalCardId: id(1), conditionCode: "NM" },
    { physicalCardId: id(2), conditionCode: "NM" },
  ];
  assert.equal(summarizeCopyPlacement(copies, new Map([[id(1), A]])), null);
});

test("leitura: a mesma 5162/5363 + local físico; nenhuma consulta nova nem escrita", () => {
  const queries = read("lib/colecoes/storage-locations-queries.ts");
  const locate = queries.slice(queries.indexOf("export async function locateCardCopies"), queries.indexOf("export type LocationInventory"));
  assert.equal((locate.match(/supabase\.(from|rpc)\(/g) ?? []).length, 1, "só a leitura de local físico que já existia");
  assert.ok(locate.includes("getAcervoItemDetail(supabase, key)"));
  assert.ok(locate.includes("summarizeCopyPlacement(detail.copies, storage)"));
  assert.ok(!/condition_code|card_condition/.test(locate), "a condição vem da 5363 já mapeada, sem nova coluna/tabela");
  const mod = read("lib/colecoes/condition-distribution.ts");
  assert.ok(!/supabase|\.rpc\(|from\(/.test(mod), "módulo puro");
});

test("Encontrar carta: resumo total + cada local + sem localização; leitor de tela por extenso", () => {
  const manager = read("components/colecoes/locais/locations-manager.tsx");
  const finder = manager.slice(manager.indexOf("function CardFinder"), manager.indexOf("function LocationFormPanel"));
  assert.ok(finder.includes("<ConditionMix tally={located.result.conditions} />"), "resumo da carta");
  assert.ok(finder.includes("located.result.conditionsByStorage?.[id]"), "cada local");
  assert.ok(finder.includes("<ConditionMix tally={located.result.unlocatedConditions} compact />"), "sem localização");
  assert.ok(finder.includes("${mixSpoken ? `. ${mixSpoken}` : \"\"}"), "aria-label do botão inclui a distribuição");
  const mix = manager.slice(manager.indexOf("function ConditionMix"));
  assert.ok(mix.includes('aria-hidden="true"') && mix.includes('className="sr-only"'));
  assert.ok(mix.includes("conditionParts(tally)") && mix.includes("tally.unrecognized > 0"));
  assert.ok(!/\bLP\b|\bDMG\b/.test(mix), "rótulos só do mapa canônico");
  const css = read("components/colecoes/locais/locais.module.css");
  assert.match(css, /\.conditionMixItems \{[^}]*flex-wrap: wrap;/, "quebra em telas estreitas");
  assert.match(css, /\.conditionMixCode \{[^}]*background: hsl\(var\(--surface-muted\)\);/, "tokens do tema (claro/escuro)");
});
