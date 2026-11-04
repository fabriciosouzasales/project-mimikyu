/**
 * V1-11 W8 — sugestão pós-aquisição + remoção em lote: regras puras + verificação estática.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  WISHLIST_REMOVE_LIMIT,
  allVisibleSelected,
  parseWishRemoveIds,
  pruneWishSelection,
  satisfiedSuggestionCount,
  selectWishPage,
  summarizeWishRemove,
  toggleWishSelection,
  wishRemoveConfirmation,
  wishRemoveHeadline,
  wishSatisfied,
} from "./wishlist-selection.ts";
import { ownershipLabel } from "./wishlist.ts";

// Dois desejos da MESMA variante em idiomas diferentes = dois registros distintos (E_PT, E_EN).
const E_PT = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const E_EN = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const E_ANY = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const OTHER_PAGE = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const PAGE = [E_PT, E_EN, E_ANY];

const uuid = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;

test("atendido só com a mesma variante e idioma compatível (C-213)", () => {
  assert.equal(wishSatisfied("SAME_VARIANT_LANGUAGE"), true);
  // Mesma variante em outro idioma, quando o desejo pede idioma: NÃO atende.
  assert.equal(wishSatisfied("SAME_VARIANT_OTHER_LANGUAGE"), false);
  // Outra variante da carta nunca é equivalente.
  assert.equal(wishSatisfied("OTHER_VARIANT"), false);
  assert.equal(wishSatisfied("NONE"), false);
  // O selo "Já no acervo" é o mesmo critério.
  assert.equal(ownershipLabel("SAME_VARIANT_LANGUAGE"), "Já no acervo");
});

test("seleção individual por entryId — idiomas da mesma variante não se confundem", () => {
  let sel = toggleWishSelection(new Set(), E_PT, PAGE);
  assert.deepEqual([...sel], [E_PT]);
  assert.equal(sel.has(E_EN), false);
  sel = toggleWishSelection(sel, E_EN, PAGE);
  assert.deepEqual([...sel].sort(), [E_PT, E_EN].sort());
  sel = toggleWishSelection(sel, E_PT, PAGE);
  assert.deepEqual([...sel], [E_EN]);
});

test("id fora da página exibida nunca entra na seleção", () => {
  const sel = toggleWishSelection(new Set(), OTHER_PAGE, PAGE);
  assert.equal(sel.size, 0);
});

test("selecionar esta página = só os visíveis; limpar e recortar", () => {
  const sel = selectWishPage(PAGE);
  assert.deepEqual([...sel], PAGE);
  assert.equal(allVisibleSelected(sel, PAGE), true);
  assert.equal(allVisibleSelected(new Set([E_PT]), PAGE), false);
  assert.equal(allVisibleSelected(new Set(), []), false);
  // Após remoção/refresh, só o que continua visível permanece selecionado.
  const pruned = pruneWishSelection(new Set([E_PT, E_EN, OTHER_PAGE]), [E_EN, E_ANY]);
  assert.deepEqual([...pruned], [E_EN]);
});

test("pedido de remoção: ids válidos, distintos e dentro do teto", () => {
  assert.deepEqual(parseWishRemoveIds([E_PT, E_EN]), [E_PT, E_EN]);
  // Duplicados (clique duplo, pedido manipulado) contam uma vez.
  assert.deepEqual(parseWishRemoveIds([E_PT, E_PT, E_EN]), [E_PT, E_EN]);
  assert.deepEqual(parseWishRemoveIds([E_PT.toUpperCase()]), [E_PT]);
  assert.equal(parseWishRemoveIds([]), null);
  assert.equal(parseWishRemoveIds(null), null);
  assert.equal(parseWishRemoveIds("x"), null);
  assert.equal(parseWishRemoveIds([E_PT, "não-é-uuid"]), null);
  assert.equal(parseWishRemoveIds([E_PT, 42]), null);
  const limit = Array.from({ length: WISHLIST_REMOVE_LIMIT }, (_, i) => uuid(i + 1));
  assert.equal(parseWishRemoveIds(limit)?.length, WISHLIST_REMOVE_LIMIT);
  assert.equal(parseWishRemoveIds([...limit, uuid(999)]), null);
  assert.ok(WISHLIST_REMOVE_LIMIT <= 500, "teto do app não pode passar do teto da 5346");
});

test("resultado: total, parcial (ids inexistentes/alheios) e repetição segura", () => {
  assert.deepEqual(summarizeWishRemove(3, 3), { requested: 3, removed: 3, notFound: 0 });
  assert.deepEqual(summarizeWishRemove(3, 1), { requested: 3, removed: 1, notFound: 2 });
  // Repetir a mesma remoção: nada sai, nada quebra.
  assert.deepEqual(summarizeWishRemove(3, 0), { requested: 3, removed: 0, notFound: 3 });
  assert.deepEqual(summarizeWishRemove(2, "2"), { requested: 2, removed: 2, notFound: 0 });
  // Fora do contrato.
  assert.equal(summarizeWishRemove(2, 3), null);
  assert.equal(summarizeWishRemove(2, -1), null);
  assert.equal(summarizeWishRemove(2, 1.5), null);
  assert.equal(summarizeWishRemove(2, null), null);
});

test("frases de confirmação e de resultado", () => {
  assert.equal(wishRemoveConfirmation(1), "Remover 1 desejo da sua lista?");
  assert.equal(wishRemoveConfirmation(12), "Remover 12 desejos da sua lista?");
  assert.equal(wishRemoveHeadline({ requested: 1, removed: 1, notFound: 0 }), "1 desejo removido da lista.");
  assert.equal(wishRemoveHeadline({ requested: 4, removed: 4, notFound: 0 }), "4 desejos removidos da lista.");
  assert.equal(
    wishRemoveHeadline({ requested: 4, removed: 3, notFound: 1 }),
    "3 desejos removidos da lista · 1 já não estava na lista.",
  );
  assert.equal(
    wishRemoveHeadline({ requested: 2, removed: 0, notFound: 2 }),
    "Nenhum desejo removido · 2 já não estavam na lista.",
  );
});

test("sugestão pós-aquisição: só com desejos atendidos e fora do filtro 'Já no acervo'", () => {
  assert.equal(satisfiedSuggestionCount(3, false), 3);
  assert.equal(satisfiedSuggestionCount(0, false), 0);
  assert.equal(satisfiedSuggestionCount(undefined, false), 0);
  assert.equal(satisfiedSuggestionCount(null, false), 0);
  assert.equal(satisfiedSuggestionCount(3, true), 0);
});

// ---- verificação estática ----

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");
const actions = read("../../app/colecoes/lista-de-desejos/actions.ts");
const view = read("../../components/wishlist/wishlist-view.tsx");
const sql5346 = read("../../../database/schema/5346_create_card_wishlist_functions.sql");

function slice(source: string, from: string, to: string): string {
  const start = source.indexOf(from);
  assert.ok(start >= 0, `trecho ausente: ${from}`);
  const end = source.indexOf(to, start + from.length);
  return source.slice(start, end < 0 ? undefined : end);
}

test("action em lote: só a 5346, por entryId exato, uma chamada", () => {
  const body = slice(actions, "export async function removeSelectedWishes", "\n}\n");
  assert.match(body, /parseWishRemoveIds\(entryIds\)/);
  assert.match(body, /if \(!ids\) return \{ ok: false, reason: "invalid" \}/);
  const rpcs = [...body.matchAll(/\.rpc\("([a-z_]+)"/g)].map((m) => m[1]);
  assert.deepEqual(rpcs, ["remove_my_wishlist_entries"]);
  assert.match(body, /p_entry_ids: ids/);
  // Nunca por carta ou variante, nunca em laço por item, nunca tocando outros domínios.
  assert.doesNotMatch(body, /card_id|card_variant_id|cardVariantId|p_card/);
  assert.doesNotMatch(body, /for \(|\.map\(|forEach/);
  assert.doesNotMatch(body, /\.from\(/);
});

test("5346: escopo do usuário da sessão, ids exatos, teto 500, só authenticated", () => {
  const fn = slice(sql5346, "function public.remove_my_wishlist_entries", "$$;");
  assert.match(fn, /v_user\s+uuid := auth\.uid\(\)/);
  assert.match(fn, /where w\.user_id = v_user\s+and w\.id = any\(p_entry_ids\)/);
  assert.match(fn, /cardinality\(p_entry_ids\) > 500/);
  assert.match(sql5346, /revoke all on function public\.remove_my_wishlist_entries\(uuid\[\]\) from anon;/);
  assert.match(sql5346, /grant execute on function public\.remove_my_wishlist_entries\(uuid\[\]\) to authenticated;/);
});

test("UI: remoção em lote só depois da confirmação, com contagem exata", () => {
  // A única chamada da action está dentro de removeSelected, acionada pelo botão do diálogo.
  assert.equal(view.match(/removeSelectedWishes\(/g)?.length, 1);
  const fn = slice(view, "async function removeSelected()", "\n  }\n");
  assert.match(fn, /removeSelectedWishes\(ids\)/);
  assert.match(view, /<Dialog open=\{confirmOpen\}/);
  assert.match(view, /onClick=\{\(\) => void removeSelected\(\)\}/);
  assert.match(view, /setConfirmOpen\(true\)/);
  assert.match(view, /wishRemoveConfirmation\(selectedCount\)/);
  // A barra só abre a confirmação — nunca remove direto.
  const bar = slice(view, 'aria-label="Seleção de desejos"', "</div>\n              </div>");
  assert.doesNotMatch(bar, /removeSelected/);
  // Seleção por entryId, recortada pela página visível.
  assert.match(view, /toggleWishSelection\(selected, entry\.entryId, visibleIds\)/);
  assert.match(view, /pruneWishSelection\(selection\.ids, visibleIds\)/);
  // Trocar de página/filtro/ordem recomeça a seleção.
  assert.match(view, /if \(selection\.scope !== scope\)/);
});

test("UI: nada é removido automaticamente pela sugestão", () => {
  const aside = slice(view, "<aside className={styles.suggestion}", "</aside>");
  assert.doesNotMatch(aside, /removeSelected|removeWishlistEntries|setConfirmOpen/);
  assert.match(aside, /ownership: "OWNED"/);
});

test("marcadores em outras grades seguem sem ação de remoção em lote", () => {
  const others = [
    "../../components/wishlist/wish-button.tsx",
    "../../components/wishlist/wishlist-controller.tsx",
    "../../components/wishlist/missing-wishes-launcher.tsx",
    "../../components/wishlist/species-wish-picker.tsx",
    "../../components/colecoes/colecoes/collection-view.tsx",
  ];
  for (const path of others) {
    const source = read(path);
    assert.doesNotMatch(source, /removeSelectedWishes/, path);
  }
});

test("contraste no escuro: os dois botões de remover usam o tratamento destrutivo por tokens", () => {
  assert.equal(view.match(/variant="destructive"/g)?.length, 2);
  assert.equal(view.match(/styles\.dangerAction/g)?.length, 2);
  const css = read("../../components/wishlist/wishlist.module.css");
  const block = css.slice(css.indexOf(":global(.dark) .dangerAction {"));
  assert.match(block, /hsl\(var\(--destructive\)\)/);
  assert.match(block, /hsl\(var\(--destructive-foreground\)/);
  // Só tokens: nenhuma cor literal no ajuste.
  assert.doesNotMatch(block.slice(0, block.indexOf("}", block.indexOf("focus-visible"))), /#[0-9a-f]{3,6}\b|rgb\(/i);
  // Tema claro inalterado: nenhuma regra .dangerAction fora de .dark.
  assert.doesNotMatch(css, /\n\.dangerAction/);
});
