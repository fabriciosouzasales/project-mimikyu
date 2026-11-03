// V1-11 W1 — Lista de desejos: regras puras.
// Executar: node --experimental-strip-types --test lib/wishlist/wishlist.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  ANY_FINISH,
  SPECIES_CARDS_PAGE_SIZE,
  appendSpeciesCards,
  nextSpeciesCardsOffset,
  parseSpeciesCardsPage,
  WISH_SUCCESS_NOTICE_MS,
  cardWishMode,
  createDismissTimer,
  entryIdsOfVariant,
  initialWishEntry,
  normalizeLanguageCode,
  ownershipLabel,
  parseFinishKey,
  parseFinishVariantOptions,
  parsePageParam,
  parseVariantOptions,
  parseWishlistPage,
  parseWishlistSummary,
  settleChooserWished,
  settleWish,
  toWishedByCardMap,
  toWishedPositionKeys,
  toWishedVariantSet,
  toggleWish,
  variantRemovalPlan,
  visibleWishlistEntries,
  wishErrorMessage,
  wishFailureReason,
  wishLanguageLabel,
  wishToggleLabel,
  wishlistKpis,
  wishFinishKey,
  wishPositionKey,
  wishedCardIds,
} from "./wishlist.ts";

const CARD = "11111111-1111-4111-8111-111111111111";
const CARD_B = "22222222-2222-4222-8222-222222222222";
const V1 = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const V2 = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const E1 = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const E2 = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const fmt = (n: number) => String(n);
const money = (n: number) => `R$ ${n}`;

test("idioma: vazio/inválido = qualquer (null); códigos válidos preservados", () => {
  assert.equal(normalizeLanguageCode(null), null);
  assert.equal(normalizeLanguageCode(""), null);
  assert.equal(normalizeLanguageCode("xx-yy"), null);
  assert.equal(normalizeLanguageCode("pt-BR"), "pt-BR");
  assert.equal(normalizeLanguageCode("en"), "en");
  assert.equal(wishLanguageLabel(null), "Qualquer idioma");
  assert.equal(wishLanguageLabel("pt-BR"), "Português");
  assert.equal(wishLanguageLabel("en"), "Inglês");
});

test("posse: quatro níveis; 'não tem' não ganha selo", () => {
  assert.equal(ownershipLabel("SAME_VARIANT_LANGUAGE"), "Já no acervo");
  assert.equal(ownershipLabel("SAME_VARIANT_OTHER_LANGUAGE"), "No acervo em outro idioma");
  assert.equal(ownershipLabel("OTHER_VARIANT"), "Você tem outra variante");
  assert.equal(ownershipLabel("NONE"), null);
});

test("estado em lote por variante: variante marcada com qualquer idioma; linhas inválidas descartadas", () => {
  const set = toWishedVariantSet([
    { card_variant_id: V1, entry_id: E1 },
    { card_variant_id: V1, entry_id: E2 },
    { card_variant_id: "x", entry_id: E1 },
    { card_variant_id: V2, entry_id: null },
  ]);
  assert.deepEqual([...set], [V1]);
  assert.deepEqual(entryIdsOfVariant([{ card_variant_id: V1, entry_id: E1 }, { card_variant_id: V1, entry_id: E2 }, { card_variant_id: V2, entry_id: E1 }], V1), [E1, E2]);
});

test("estado em lote por carta: agrupa variantes desejadas por carta", () => {
  const map = toWishedByCardMap([
    { card_id: CARD, card_variant_id: V1, entry_id: E1 },
    { card_id: CARD, card_variant_id: V2, entry_id: E2 },
    { card_id: CARD_B, card_variant_id: "bad", entry_id: E1 },
  ]);
  assert.deepEqual([...(map.get(CARD) ?? [])].sort(), [V1, V2].sort());
  assert.equal(map.has(CARD_B), false);
});

test("escolha explícita (C-212): direta só com uma variante ativa; nunca presume", () => {
  const options = parseVariantOptions([
    { card_variant_id: V1, variant_label: "Normal", is_default_variant: true },
    { card_variant_id: V2, variant_label: "", is_default_variant: false },
    { card_variant_id: "nope" },
  ]);
  assert.ok(options);
  assert.equal(options.length, 2);
  assert.equal(options[1]?.label, "Variante");
  assert.equal(cardWishMode(options), "choose");
  assert.equal(cardWishMode(options.slice(0, 1)), "direct");
  assert.equal(cardWishMode([]), "none");
  assert.equal(parseVariantOptions(null), null);
});

test("página: linha completa; variante desativada sinalizada; só true explícito é disponível", () => {
  const page = parseWishlistPage([
    {
      entry_id: E1, card_variant_id: V1, card_id: CARD, card_name: "Pikachu", collector_number: "025", collector_total: 198,
      card_set_code: "SV1", card_set_name: "Escarlate e Violeta", variant_label: "Holográfica", variant_available: true,
      language_code: null, ownership: "OTHER_VARIANT", image_path_pt: "a.png", image_path_en: null,
      wished_at: "2026-11-01T10:00:00Z", total_count: 3,
    },
    {
      entry_id: E2, card_variant_id: V2, card_id: CARD, card_name: "Pikachu", variant_available: null,
      language_code: "pt-BR", ownership: "???", wished_at: "2026-11-01T09:00:00Z", total_count: "3",
    },
    { entry_id: "bad", card_variant_id: V1, card_id: CARD, card_name: "X", wished_at: "t" },
  ]);
  assert.ok(page);
  assert.equal(page.entries.length, 2);
  assert.equal(page.totalCount, 3);
  const [first, second] = page.entries;
  assert.ok(first && second);
  assert.equal(first.variantAvailable, true);
  assert.equal(first.languageCode, null);
  assert.equal(first.ownership, "OTHER_VARIANT");
  assert.equal(second.variantAvailable, false);
  assert.equal(second.languageCode, "pt-BR");
  assert.equal(second.ownership, "NONE");
  assert.equal(parseWishlistPage({}), null);
});

test("resumo (C-216): coerência entre desejos, variantes distintas, cotadas e total", () => {
  assert.deepEqual(parseWishlistSummary([{ entry_count: 3, variant_count: 2, priced_variant_count: 1, total_brl: "12.5" }]), {
    entryCount: 3, variantCount: 2, pricedVariantCount: 1, totalBrl: 12.5,
  });
  assert.deepEqual(parseWishlistSummary({ entry_count: 0, variant_count: 0, priced_variant_count: 0, total_brl: null }), {
    entryCount: 0, variantCount: 0, pricedVariantCount: 0, totalBrl: null,
  });
  // total sem cotação, cotação sem total, mais variantes que desejos, desejos sem variante → rejeitados
  assert.equal(parseWishlistSummary({ entry_count: 1, variant_count: 1, priced_variant_count: 0, total_brl: 0 }), null);
  assert.equal(parseWishlistSummary({ entry_count: 1, variant_count: 1, priced_variant_count: 1, total_brl: null }), null);
  assert.equal(parseWishlistSummary({ entry_count: 1, variant_count: 2, priced_variant_count: 0, total_brl: null }), null);
  assert.equal(parseWishlistSummary({ entry_count: 2, variant_count: 0, priced_variant_count: 0, total_brl: null }), null);
  assert.equal(parseWishlistSummary([{}, {}]), null);
});

test("indicadores: sem cobertura = '—' (nunca R$ 0); cobertura sobre variantes distintas", () => {
  const none = wishlistKpis({ summary: { entryCount: 3, variantCount: 2, pricedVariantCount: 0, totalBrl: null }, fallbackEntryCount: 3, format: fmt, formatMoney: money });
  assert.deepEqual(none.map((k) => k.value), [null, "3", "2"]);
  assert.equal(none[0]?.hint, "0 de 2 variantes com cotação");
  const priced = wishlistKpis({ summary: { entryCount: 2, variantCount: 1, pricedVariantCount: 1, totalBrl: 40 }, fallbackEntryCount: 2, format: fmt, formatMoney: money });
  assert.equal(priced[0]?.value, "R$ 40");
  assert.equal(priced[0]?.hint, "1 de 1 variante com cotação");
  const failed = wishlistKpis({ summary: null, fallbackEntryCount: 5, format: fmt, formatMoney: money });
  assert.deepEqual(failed.map((k) => k.value), [null, "5", null]);
});

test("máquina de intenção: otimista, uma gravação por vez, última intenção vence, falha reverte", () => {
  let step = toggleWish(V1, initialWishEntry(false));
  assert.deepEqual(step.send, { variantId: V1, value: true });
  // Segundo clique durante a gravação: só muda a intenção.
  step = toggleWish(V1, step.entry);
  assert.equal(step.send, null);
  assert.equal(step.entry.desired, false);
  // Servidor confirma true; intenção atual é false → reenvia false.
  const settled = settleWish(V1, step.entry, { ok: true, value: true });
  assert.deepEqual(settled.send, { variantId: V1, value: false });
  // Falha reverte ao confirmado.
  const failed = settleWish(V1, settled.entry, { ok: false });
  assert.equal(failed.reverted, true);
  assert.equal(failed.entry.desired, true);
});

test("erros e rótulos: sem detalhe técnico; nome acessível constante com a variante", () => {
  assert.equal(wishFailureReason("28000"), "not_authenticated");
  assert.equal(wishFailureReason("22023"), "invalid");
  assert.equal(wishFailureReason("P0002"), "variant_unavailable");
  assert.equal(wishFailureReason("PGRST202"), "unavailable");
  assert.equal(wishFailureReason("XX000"), "failed");
  assert.match(wishErrorMessage("Pikachu", "failed"), /Nada foi alterado/);
  assert.equal(wishToggleLabel("Pikachu", "Holográfica"), "Lista de desejos: Pikachu · Holográfica");
  assert.equal(wishToggleLabel("Pikachu", null), "Lista de desejos: Pikachu");
  assert.equal(parsePageParam("2"), 2);
  assert.equal(parsePageParam("0"), 1);
});

test("SQL proposto: unicidade NULLS NOT DISTINCT, RLS só do dono, sem vínculo com coleção, grants mínimos", () => {
  const dir = new URL("../../../database/proposals/2026-11-01-v1-11-w1-wishlist/", import.meta.url);
  const table = readFileSync(new URL("5345_create_card_wishlist_entry_table.sql", dir), "utf8");
  const fns = readFileSync(new URL("5346_create_card_wishlist_functions.sql", dir), "utf8");
  const summary = readFileSync(new URL("5347_create_get_my_wishlist_summary_function.sql", dir), "utf8");
  assert.match(table, /unique nulls not distinct \(user_id, card_variant_id, language_id\)/);
  assert.match(table, /using \(user_id = \(select auth\.uid\(\)\)\)/);
  assert.match(table, /grant select on table public\.card_wishlist_entry to authenticated;/);
  assert.doesNotMatch(table, /collection_id|layout|slot_id|quantity|priority/i);
  for (const sql of [fns, summary]) {
    assert.doesNotMatch(sql, /grant execute[^;]*to (anon|public)/i);
    assert.match(sql, /set search_path = ''/);
    assert.doesNotMatch(sql, /p_user_id/);
  }
  // Inclusão só em variante ativa; remoção nunca exige variante ativa.
  assert.match(fns, /CARD_VARIANT_UNAVAILABLE/);
  assert.match(fns, /on conflict on constraint uq_card_wishlist_entry_user_variant_language do nothing/);
  // Valor agregado: uma referência por variante distinta, via 3983, NULL sem cobertura.
  assert.match(summary, /array_agg\(distinct w\.card_variant_id/);
  assert.match(summary, /get_card_variants_pricing_summary/);
  assert.match(summary, /case when v_priced = 0 then null else v_total end/);
});

test("CORRECTION-02: desmarcar a variante nunca remove vários idiomas de uma vez", () => {
  assert.equal(variantRemovalPlan([]), "none");
  assert.equal(variantRemovalPlan([E1]), "remove");
  assert.equal(variantRemovalPlan([E1, E2]), "blocked");
  assert.equal(wishFailureReason("P0002"), "variant_unavailable");
  assert.match(wishErrorMessage("Pikachu · Holográfica", "multiple_entries"), /mais de um idioma. Nada foi removido/);
  // Bloqueio = falha: a máquina reverte ao confirmado (marcado) e não reenvia.
  const pending = toggleWish(V1, initialWishEntry(true));
  assert.deepEqual(pending.send, { variantId: V1, value: false });
  const settled = settleWish(V1, pending.entry, { ok: false });
  assert.equal(settled.reverted, true);
  assert.equal(settled.entry.desired, true);
  assert.equal(settled.send, null);
  // A action usa o plano: com mais de um desejo responde multiple_entries sem chamar a remoção.
  const actions = readFileSync(new URL("../../app/colecoes/lista-de-desejos/actions.ts", import.meta.url), "utf8");
  const body = actions.slice(actions.indexOf("export async function setVariantWished"), actions.indexOf("export type AddWishResult"));
  assert.ok(body.indexOf('reason: "multiple_entries"') > -1);
  assert.ok(body.indexOf('reason: "multiple_entries"') < body.indexOf("remove_my_wishlist_entries"));
});

// ---------------------------------------------------------------------------
// HOMOLOGATION-04 — regressões dos Defeitos A e B
// ---------------------------------------------------------------------------

test("Defeito A: entrada removida (confirmada) some da grade; demais permanecem", () => {
  const server = [{ entryId: "a" }, { entryId: "b" }, { entryId: "c" }];
  const visible = visibleWishlistEntries(server, new Set(["b"]), []);
  assert.deepEqual(visible.map((e) => e.entryId), ["a", "c"]);
  // Nada oculto = lista do servidor intacta (nenhum outro desejo removido por engano).
  assert.deepEqual(visibleWishlistEntries(server, new Set(), []).map((e) => e.entryId), ["a", "b", "c"]);
});

test("Defeito A: Desfazer recoloca a carta (id novo) sem duplicar quando o servidor relê", () => {
  const before = [{ entryId: "a" }, { entryId: "c" }];
  const restored = [{ entryId: "b2" }];
  // Antes da releitura: aparece na hora.
  assert.deepEqual(visibleWishlistEntries(before, new Set(["b"]), restored).map((e) => e.entryId), ["b2", "a", "c"]);
  // Depois da releitura (servidor já traz b2): uma única vez.
  const after = [{ entryId: "a" }, { entryId: "b2" }, { entryId: "c" }];
  assert.deepEqual(visibleWishlistEntries(after, new Set(["b"]), restored).map((e) => e.entryId), ["a", "b2", "c"]);
  // Restaurado e removido de novo: oculto.
  assert.deepEqual(visibleWishlistEntries(after, new Set(["b", "b2"]), restored).map((e) => e.entryId), ["a", "c"]);
});

test("Defeito A (estático): remoção só depois da confirmação e página relida do servidor", () => {
  const view = readFileSync(new URL("../../components/wishlist/wishlist-view.tsx", import.meta.url), "utf8");
  assert.match(view, /router\.refresh\(\)/);
  assert.match(view, /visibleWishlistEntries\(entries, hidden, restored\)/);
  assert.match(view, /visible\.map\(/);
  assert.doesNotMatch(view, /entries\.map\(\(entry\)/);
  // Ocultar acontece no ramo de sucesso, depois do await (nunca antes da resposta).
  const remove = view.slice(view.indexOf("async function remove("), view.indexOf("async function undo("));
  assert.ok(remove.indexOf("await removeWishlistEntries") < remove.indexOf("setHidden("));
  assert.ok(remove.indexOf("if (ok)") < remove.indexOf("setHidden("));
});

test("Defeito B: estado da escolha vem do servidor; falha volta ao persistido", () => {
  const persisted = new Set(["v1"]);
  assert.deepEqual([...settleChooserWished(persisted, "v2", { ok: true, value: true })].sort(), ["v1", "v2"]);
  assert.deepEqual([...settleChooserWished(persisted, "v1", { ok: true, value: false })], []);
  assert.deepEqual([...settleChooserWished(persisted, "v2", { ok: false })], ["v1"]);
  // Não muta o conjunto original.
  assert.deepEqual([...persisted], ["v1"]);
});

test("Defeito B (estático): opção salvando fica desabilitada, falha aparece dentro do diálogo, fechamento usa o persistido", () => {
  const src = readFileSync(new URL("../../components/wishlist/wishlist-controller.tsx", import.meta.url), "utf8");
  const dialog = src.slice(src.indexOf("<DialogContent>"), src.indexOf("</DialogContent>"));
  assert.match(dialog, /disabled=\{saving\}/);
  assert.match(dialog, /aria-busy=\{saving \|\| undefined\}/);
  assert.match(dialog, /Salvando…/);
  assert.match(dialog, /role="alert"/);
  assert.match(dialog, /chooser\.error/);
  const close = src.slice(src.indexOf("function closeChooser()"), src.indexOf("function onClick("));
  assert.match(close, /confirmCard\(/);
  assert.doesNotMatch(close, /chooser\.wished/);
  const confirm = src.slice(src.indexOf("function confirmCard("), src.indexOf("async function toggleOption("));
  assert.match(confirm, /persistedByCard\.current\.get/);
  // Sem leitura de `chooser` capturado em fechamento antigo dentro de toggleOption.
  const toggle = src.slice(src.indexOf("async function toggleOption("), src.indexOf("function closeChooser()"));
  assert.match(toggle, /chooserRef\.current/);
  assert.doesNotMatch(toggle, /const state = chooser;/);
});

test("Defeito C / CARD GRID UX STANDARDIZATION-01 (estático): grades do módulo Coleções com selo que quebra linha", () => {
  const css = readFileSync(new URL("../../components/colecoes/acervo/acervo.module.css", import.meta.url), "utf8");
  const block = (sel: string) => {
    const start = css.indexOf(`\n${sel} {`);
    assert.ok(start >= 0, `regra ${sel} ausente`);
    return css.slice(start, css.indexOf("}", start));
  };
  const tag = block(".tag");
  assert.match(tag, /max-width:\s*100%/);
  assert.match(tag, /overflow-wrap:\s*anywhere/);
  assert.match(tag, /white-space:\s*normal/);
  assert.doesNotMatch(tag, /white-space:\s*nowrap/);
  // Lista de desejos e Cartas favoritas usam a mesma grade/arte/legenda do Meu acervo.
  for (const file of ["../../components/wishlist/wishlist-view.tsx", "../../components/favorites/favorite-cards-view.tsx"]) {
    const view = readFileSync(new URL(file, import.meta.url), "utf8");
    assert.match(view, /className=\{acervoStyles\.grid\}/, file);
    assert.match(view, /acervoStyles\.art\b/, file);
    assert.match(view, /acervoStyles\.meta\b/, file);
    assert.match(view, /CARD_GRID_SIZES/, file);
  }
});

// TOAST UX CORRECTION-07 — aviso de sucesso com fechamento automático
function fakeClock() {
  let t = 0;
  let seq = 0;
  const timers = new Map<number, { at: number; fn: () => void }>();
  return {
    clock: {
      now: () => t,
      set: (fn: () => void, ms: number) => {
        const id = ++seq;
        timers.set(id, { at: t + ms, fn });
        return id;
      },
      clear: (h: unknown) => {
        timers.delete(h as number);
      },
    },
    advance(ms: number) {
      t += ms;
      for (const [id, timer] of [...timers]) {
        if (timer.at <= t) {
          timers.delete(id);
          timer.fn();
        }
      }
    },
    pending: () => timers.size,
  };
}

test("aviso: fecha sozinho após o prazo (8 s) e uma única vez", () => {
  assert.equal(WISH_SUCCESS_NOTICE_MS, 8000);
  const c = fakeClock();
  let closed = 0;
  const timer = createDismissTimer(() => closed++, WISH_SUCCESS_NOTICE_MS, c.clock);
  timer.start();
  c.advance(7999);
  assert.equal(closed, 0);
  c.advance(1);
  assert.equal(closed, 1);
  c.advance(10_000);
  assert.equal(closed, 1);
});

test("aviso: fechar manualmente/desmontar cancela; nunca dispara depois", () => {
  const c = fakeClock();
  let closed = 0;
  const timer = createDismissTimer(() => closed++, 8000, c.clock);
  timer.start();
  c.advance(3000);
  timer.cancel();
  assert.equal(c.pending(), 0);
  c.advance(20_000);
  assert.equal(closed, 0);
});

test("aviso: nova remoção reinicia o prazo inteiro, sem dois disparos", () => {
  const c = fakeClock();
  let closed = 0;
  const timer = createDismissTimer(() => closed++, 8000, c.clock);
  timer.start();
  c.advance(6000);
  timer.start();
  assert.equal(c.pending(), 1);
  c.advance(6000);
  assert.equal(closed, 0);
  c.advance(2000);
  assert.equal(closed, 1);
});

test("aviso: hover/foco pausam (Desfazer continua disponível) e retomam com o tempo restante", () => {
  const c = fakeClock();
  let closed = 0;
  const timer = createDismissTimer(() => closed++, 8000, c.clock);
  timer.start();
  c.advance(5000);
  timer.pause();
  c.advance(60_000);
  assert.equal(closed, 0);
  timer.resume();
  c.advance(2999);
  assert.equal(closed, 0);
  c.advance(1);
  assert.equal(closed, 1);
});

test("aviso (estático): X acessível, erro sem fechamento automático, Desfazer preservado", () => {
  const view = readFileSync(new URL("../../components/wishlist/wishlist-view.tsx", import.meta.url), "utf8");
  assert.match(view, /aria-label="Fechar aviso"/);
  assert.match(view, /if \(!lastRemoved \|\| error\) return;/);
  assert.match(view, /createDismissTimer\(\(\) => setLastRemoved\(null\), WISH_SUCCESS_NOTICE_MS\)/);
  assert.match(view, /onMouseEnter=\{\(\) => holdNotice\("hover", true\)\}/);
  assert.match(view, /onFocus=\{\(\) => holdNotice\("focus", true\)\}/);
  assert.match(view, /Desfazer/);
  assert.match(view, /timer\.cancel\(\)/);
});

test("aviso (estático): X fora do bloco que quebra linha, sempre à direita", () => {
  const view = readFileSync(new URL("../../components/wishlist/wishlist-view.tsx", import.meta.url), "utf8");
  const success = view.slice(view.indexOf('<InlineFeedback tone="success">'), view.indexOf("</InlineFeedback>", view.indexOf('<InlineFeedback tone="success">')));
  assert.ok(success.indexOf("</span>\n                  <NoticeClose") > 0, "X deve ser irmão do bloco do texto/Desfazer");
  const css = readFileSync(new URL("../../components/wishlist/wishlist.module.css", import.meta.url), "utf8");
  assert.match(css, /\.notice > button:last-child \{[^}]*margin-left:\s*auto/);
});

test("aviso (estático): hover/foco relidos do DOM a cada aviso e zerados ao fechar (prazo nunca fica preso)", () => {
  const view = readFileSync(new URL("../../components/wishlist/wishlist-view.tsx", import.meta.url), "utf8");
  const effect = view.slice(view.indexOf("if (!lastRemoved || error) return;"), view.indexOf("}, [lastRemoved, error]);"));
  assert.match(effect, /hoverRef\.current = node\?\.matches\(":hover"\)/);
  assert.match(effect, /focusRef\.current = node \? node\.contains\(document\.activeElement\)/);
  const cleanup = effect.slice(effect.indexOf("return () => {"));
  assert.match(cleanup, /hoverRef\.current = false;/);
  assert.match(cleanup, /focusRef\.current = false;/);
});

test("FINAL VISUAL POLISH (estático): selos variante → idioma → posse e marcador no canto superior esquerdo", () => {
  const view = readFileSync(new URL("../../components/wishlist/wishlist-view.tsx", import.meta.url), "utf8");
  const row = view.slice(view.indexOf("className={styles.tagRow}"));
  const iVariant = row.indexOf("entry.variantLabel");
  const iLanguage = row.indexOf("wishLanguageLabel(");
  const iOwned = row.indexOf("styles.tagOwned");
  assert.ok(iVariant > 0 && iVariant < iLanguage && iLanguage < iOwned, "ordem variante → idioma → posse");
  const css = readFileSync(new URL("../../components/wishlist/wishlist.module.css", import.meta.url), "utf8");
  const tagRow = css.slice(css.indexOf("\n.tagRow {"), css.indexOf("}", css.indexOf("\n.tagRow {")));
  assert.match(tagRow, /flex-wrap: wrap/);
  const wish = css.slice(css.indexOf("\n.wish {"), css.indexOf("}", css.indexOf("\n.wish {")));
  // Marcador espelha o coração (right -0.1875rem) no canto oposto: áreas de toque nunca se cruzam.
  assert.match(wish, /left: -0\.1875rem;/);
  assert.doesNotMatch(wish, /\bright:/);
  assert.ok(!css.includes("[data-card-fav]"), "o coração não é mais reposicionado pela Lista de desejos");
});

test("W2 (Set padrão): wishedCardIds marca só cartas com ao menos uma variante desejada", () => {
  const A = "11111111-1111-4111-8111-111111111111";
  const B = "22222222-2222-4222-8222-222222222222";
  const map = new Map<string, Set<string>>([
    [A.toUpperCase(), new Set(["v1"])],
    [B, new Set()],
  ]);
  const cards = wishedCardIds(map);
  assert.ok(cards);
  assert.equal(cards.size, 1);
  assert.ok(cards.has(A), "id normalizado em minúsculas, como a grade consulta");
  assert.ok(!cards.has(B), "carta sem variante desejada não acende o marcador");
  assert.equal(wishedCardIds(null), null, "leitura falha → sem marcador (nunca um marcador que não funciona)");
  assert.equal(wishedCardIds(new Map())?.size, 0);
});

test("W2 (estático): grade de Set padrão usa o marcador por carta da W1, uma leitura em lote, sem SQL novo", () => {
  const view = readFileSync(new URL("../../components/colecoes/colecoes/collection-view.tsx", import.meta.url), "utf8");
  assert.match(view, /<WishButton cardId=\{position\.cardId\}/, "marcador por CARTA (escolha explícita quando há várias variantes)");
  assert.match(view, /<WishlistController>/, "mesma ilha controladora da W1 (clique, escolha, Desfazer/erro)");
  assert.doesNotMatch(view, /data-wish-variant|variantId=/, "a posição nunca presume variante");
  const page = readFileSync(new URL("../../app/colecoes/colecoes/[id]/page.tsx", import.meta.url), "utf8");
  assert.equal((page.match(/getMyWishedByCard\(/g) ?? []).length, 1, "uma leitura em lote por página, nunca por posição");
  assert.match(page, /master === null && positions/, "só Set padrão (Master Set fora da W2)");
});

// ---------------------------------------------------------------------------
// W3 — Master Set (posição = carta + acabamento)
// ---------------------------------------------------------------------------

const HOLO = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
const REVERSE = "ffffffff-ffff-4fff-8fff-ffffffffffff";
const V3 = "99999999-9999-4999-8999-999999999999";
const finishRow = (id: string, finish: string | null, isDefault = false) => ({
  card_variant_id: id,
  variant_type_id: finish,
  is_default_variant: isDefault,
  variant_label: `Variante ${id.slice(0, 2)}`,
  variant_order: 1,
});

test("W3: chave de acabamento — NULL é a posição secreta (qualquer acabamento); valor inválido não vira 'qualquer'", () => {
  assert.equal(wishFinishKey(null), ANY_FINISH);
  assert.equal(wishFinishKey(undefined), ANY_FINISH);
  assert.equal(wishFinishKey(HOLO.toUpperCase()), HOLO);
  assert.equal(wishFinishKey("lixo"), null, "acabamento inválido = sem marcador, nunca 'qualquer variante'");
  assert.equal(parseFinishKey(ANY_FINISH), ANY_FINISH);
  assert.equal(parseFinishKey(HOLO), HOLO);
  assert.equal(parseFinishKey(""), null);
  assert.equal(parseFinishKey(undefined), null);
  assert.equal(wishPositionKey(CARD.toUpperCase(), HOLO), `${CARD}|${HOLO}`);
});

test("W3: estado por posição — desejo marca o acabamento da variante e a posição secreta, nunca outro acabamento", () => {
  const keys = toWishedPositionKeys([
    { card_id: CARD, variant_type_id: HOLO, card_variant_id: V1, entry_id: E1 },
    { card_id: CARD, variant_type_id: HOLO, card_variant_id: V1, entry_id: E2 }, // outro idioma, mesma posição
    { card_id: CARD_B, variant_type_id: null, card_variant_id: V2, entry_id: E1 }, // variante sem acabamento
    { card_id: CARD, variant_type_id: REVERSE, card_variant_id: V3, entry_id: null }, // linha incompleta: ignorada
  ]);
  assert.ok(keys.has(wishPositionKey(CARD, HOLO)), "posição (carta, Holo) acesa");
  assert.ok(keys.has(wishPositionKey(CARD, ANY_FINISH)), "posição secreta da carta aceita qualquer acabamento");
  assert.ok(!keys.has(wishPositionKey(CARD, REVERSE)), "outro acabamento da mesma carta NÃO acende (estado inativo)");
  assert.ok(keys.has(wishPositionKey(CARD_B, ANY_FINISH)));
  assert.equal(keys.size, 3);
  assert.equal(toWishedPositionKeys([]).size, 0, "sem desejos = todas as posições inativas");
});

test("W3: opções compatíveis — nenhuma, uma (inclusão direta) ou várias (escolha explícita); incompatíveis nunca entram", () => {
  // Nenhuma compatível: a carta tem variante, mas não neste acabamento.
  const none = parseFinishVariantOptions([finishRow(V1, REVERSE)], HOLO);
  assert.deepEqual(none, []);
  assert.equal(cardWishMode(none ?? []), "none");

  // Uma compatível entre várias variantes da carta: inclusão direta só nela.
  const one = parseFinishVariantOptions([finishRow(V1, HOLO), finishRow(V2, REVERSE, true)], HOLO);
  assert.deepEqual(one?.map((option) => option.variantId), [V1], "a variante padrão de outro acabamento não é presumida");
  assert.equal(cardWishMode(one ?? []), "direct");

  // Várias compatíveis: escolha explícita, na ordem recebida (padrão primeiro, pelo banco).
  const many = parseFinishVariantOptions([finishRow(V2, HOLO, true), finishRow(V1, HOLO), finishRow(V3, REVERSE)], HOLO);
  assert.deepEqual(many?.map((option) => option.variantId), [V2, V1]);
  assert.equal(cardWishMode(many ?? []), "choose");

  // Variante sem acabamento numa posição de acabamento: incompatível.
  assert.deepEqual(parseFinishVariantOptions([finishRow(V1, null)], HOLO), []);

  // Posição secreta: qualquer acabamento vale.
  const secret = parseFinishVariantOptions([finishRow(V1, HOLO), finishRow(V2, REVERSE), finishRow(V3, null)], ANY_FINISH);
  assert.equal(secret?.length, 3);
  assert.equal(cardWishMode(secret ?? []), "choose");

  assert.equal(parseFinishVariantOptions(null, HOLO), null, "resposta fora do contrato = indisponível");
});

test("W3 (SQL 5348, estático): só variantes ativas de carta ativa, filtro por acabamento, identidade só por auth.uid()", () => {
  const sql = readFileSync(
    new URL("../../../database/schema/5348_create_wishlist_finish_functions.sql", import.meta.url),
    "utf8",
  );
  assert.match(sql, /join public\.card_variant cv on cv\.card_id = c\.id and cv\.is_active/, "variante inativa nunca é oferecida");
  assert.match(sql, /and c\.is_active/, "carta inativa nunca é oferecida");
  assert.match(sql, /p_variant_type_id is null or cv\.variant_type_id = p_variant_type_id/, "acabamento da posição (NULL = secreta)");
  assert.match(sql, /where w\.user_id = v_user/, "estado só do usuário da sessão");
  assert.equal((sql.match(/security definer/g) ?? []).length, 2);
  assert.equal((sql.match(/set search_path = ''/g) ?? []).length, 2);
  assert.equal((sql.match(/from anon;/g) ?? []).length, 2, "anon sem EXECUTE");
  assert.doesNotMatch(sql, /insert into|update public|delete from|create table/i, "só leituras — escrita continua na W1 (5346)");
});

test("W3 (estático): grade do Master Set usa marcador por POSIÇÃO, uma leitura em lote, regras de escrita da W1", () => {
  const gallery = readFileSync(new URL("../../components/colecoes/colecoes/master-set-gallery.tsx", import.meta.url), "utf8");
  assert.match(gallery, /<WishButton\s+cardId=\{position\.cardId\}\s+finish=\{wishFinish\}/, "marcador por carta + acabamento");
  assert.doesNotMatch(gallery, /variantId=/, "a posição nunca presume variante");
  assert.match(gallery, /<WishlistController>/, "mesma ilha da W1 (inclusão, escolha, remoção, erros)");
  // Regressão de navegação: zoom, preço, exemplares, adicionar do acervo e paginação preservados.
  for (const kept of ["<CardZoomTrigger id={position.key}", "<VariantPriceSummary", "<ManageCopiesButton", "<AddFromAcervoButton", "<Pager "]) {
    assert.ok(gallery.includes(kept), `preservado: ${kept}`);
  }
  assert.ok(
    gallery.indexOf("</CardZoomTrigger>") < gallery.indexOf("<WishButton"),
    "marcador é IRMÃO do gatilho de ampliação (nunca dentro dele)",
  );

  const page = readFileSync(new URL("../../app/colecoes/colecoes/[id]/page.tsx", import.meta.url), "utf8");
  assert.equal((page.match(/getMyWishedPositionKeys\(/g) ?? []).length, 1, "uma leitura em lote por página");
  assert.match(page, /master\?\.positions\s*\?\s*getMyWishedPositionKeys/, "só Master Set, só a página exibida");

  const controller = readFileSync(new URL("../../components/wishlist/wishlist-controller.tsx", import.meta.url), "utf8");
  assert.match(controller, /readPositionWishOptions\(cardId, finish\)/, "opções restritas ao acabamento da posição");
  assert.match(controller, /:not\(\[data-wish-finish\]\)/, "marcadores da W1/W2 (sem acabamento) pintados como antes");
  assert.match(controller, /\[data-wish-finish="\$\{target\.finish\}"\]/, "posições pintadas por carta + acabamento");
  assert.equal((controller.match(/setVariantWished\(/g) ?? []).length, 1, "inclusão/remoção pela mesma action da W1 (bloqueio com vários desejos)");

  const actions = readFileSync(new URL("../../app/colecoes/lista-de-desejos/actions.ts", import.meta.url), "utf8");
  assert.match(actions, /get_catalog_card_variants_for_finish/);
  assert.match(actions, /parseFinishVariantOptions\(data, finish\)/, "filtro de compatibilidade também no servidor da aplicação");
});

// ---------------------------------------------------------------------------
// W4 — Pokédex (lacuna L3): escolha explícita da carta de uma espécie
// ---------------------------------------------------------------------------

const speciesRow = (id: string, variants: number, total = 3) => ({
  card_id: id,
  card_name: "Pikachu",
  collector_number: "25",
  collector_total: 102,
  card_set_code: "base1",
  card_set_name: "Base Set",
  image_path_pt: null,
  image_path_en: "base1/en/25.webp",
  active_variant_count: variants,
  total_count: total,
});

test("W4: cartas da espécie — nenhuma, uma ou várias; carta sem variante ativa nunca é oferecida", () => {
  const none = parseSpeciesCardsPage([]);
  assert.deepEqual(none, { items: [], total: 0 }, "sem carta elegível = estado vazio, sem ação");

  const one = parseSpeciesCardsPage([speciesRow(V1, 1, 1)]);
  assert.equal(one?.items.length, 1);
  assert.equal(one?.items[0]?.activeVariants, 1);
  assert.equal(one?.items[0]?.collectorTotal, 102);

  const many = parseSpeciesCardsPage([speciesRow(V1, 1), speciesRow(V2, 3), speciesRow(V3, 0)]);
  assert.deepEqual(many?.items.map((card) => card.cardId), [V1, V2], "variante inativa/sem variante ativa: fora");
  assert.equal(many?.total, 3, "total vem do banco (paginação)");
  assert.equal(parseSpeciesCardsPage(null), null, "resposta fora do contrato = indisponível");
  assert.ok(SPECIES_CARDS_PAGE_SIZE >= 1 && SPECIES_CARDS_PAGE_SIZE <= 60, "dentro do limite aceito pela 5349");
});

test("W4: escolha da variante segue a W1 — uma ativa = direta, várias = escolha explícita", () => {
  const single = parseVariantOptions([{ card_variant_id: V1, variant_label: "Normal", is_default_variant: true }]) ?? [];
  const several = parseVariantOptions([
    { card_variant_id: V1, variant_label: "Normal", is_default_variant: true },
    { card_variant_id: V2, variant_label: "Holo", is_default_variant: false },
  ]) ?? [];
  assert.equal(cardWishMode(single), "direct");
  assert.equal(cardWishMode(several), "choose", "nunca presume a variante padrão");
});

test("W4: paginação da escolha não repete carta e para no total", () => {
  const first = parseSpeciesCardsPage([speciesRow(V1, 1, 3), speciesRow(V2, 1, 3)])?.items ?? [];
  const again = parseSpeciesCardsPage([speciesRow(V2, 1, 3), speciesRow(V3, 2, 3)])?.items ?? [];
  const merged = appendSpeciesCards(first, again);
  assert.deepEqual(merged.map((card) => card.cardId), [V1, V2, V3]);
  assert.equal(nextSpeciesCardsOffset(2, 3), 2);
  assert.equal(nextSpeciesCardsOffset(3, 3), null);
});

test("W4 (SQL 5349, estático): só cartas ativas POKEMON da espécie com variante ativa; leitura; auth.uid()", () => {
  const sql = readFileSync(
    new URL("../../../database/schema/5349_create_get_catalog_cards_for_species_function.sql", import.meta.url),
    "utf8",
  );
  assert.match(sql, /join public\.card c\s+on c\.id = cps\.card_id and c\.is_active/);
  assert.match(sql, /cc\.code = 'POKEMON'/, "mesma regra de espécie do vínculo da Pokédex (5208)");
  assert.match(sql, /where cv\.card_id = c\.id and cv\.is_active/, "variante inativa não conta");
  assert.match(sql, /and v\.n > 0/, "carta sem variante ativa fica de fora");
  assert.match(sql, /auth\.uid\(\) is null/);
  assert.match(sql, /security definer/);
  assert.match(sql, /set search_path = ''/);
  assert.match(sql, /from anon;/);
  assert.doesNotMatch(sql, /insert into|update public|delete from|create table|card_wishlist_entry/i, "só leitura de catálogo; sem dado de usuário");
});

test("W4 (estático): Pokédex usa a escolha explícita da W1, sem vínculo com a posição nem com a coleção", () => {
  const picker = readFileSync(new URL("../../components/wishlist/species-wish-picker.tsx", import.meta.url), "utf8");
  assert.match(picker, /<WishButton cardId=\{card\.cardId\}/, "marcador por CARTA (variante pela regra da W1)");
  assert.doesNotMatch(picker, /variantId=|finish=/, "a espécie nunca presume carta nem variante");
  assert.match(picker, /<WishlistController onCardConfirmed=/, "inclusão, escolha, remoção e feedback da W1");
  assert.doesNotMatch(picker, /positionId|collectionId|linkPokedexCopy|colecoes\/colecoes\/actions/, "nada liga o desejo à Pokédex/coleção");
  assert.match(picker, /status: "closed"/, "divulgação progressiva: nada é lido antes de abrir");

  const actions = readFileSync(new URL("../../app/colecoes/lista-de-desejos/actions.ts", import.meta.url), "utf8");
  const body = actions.slice(actions.indexOf("export async function readSpeciesWishCards"));
  assert.match(body, /get_catalog_cards_for_species/);
  assert.equal((body.match(/getMyWishedByCard\(/g) ?? []).length, 1, "estado em lote, uma leitura por página");
  assert.doesNotMatch(body, /add_my_wishlist_entry|remove_my_wishlist_entries/, "abrir a escolha nunca grava");

  const panel = readFileSync(new URL("../../components/colecoes/colecoes/pokedex-position-panel.tsx", import.meta.url), "utf8");
  assert.match(panel, /<SpeciesWishPicker speciesId=\{position\.speciesId\} speciesName=\{position\.speciesName\} \/>/);
  // PANEL-VISIBILITY-FIX-03: a ação fica antes das seções de vínculo (nunca no fim do corpo rolável).
  assert.ok(
    panel.indexOf("<SpeciesWishPicker") < panel.indexOf("---- Nesta posição ----") &&
      panel.indexOf("<SpeciesWishPicker") < panel.indexOf("---- Adicionar ----"),
    "Lista de desejos acima de 'Nesta posição' e 'Adicionar' — visível sem rolar a lista do acervo",
  );
  for (const kept of ["Adicionar a esta posição", "readPokedexLinkCandidates", "Ver {position.speciesName} na Pokédex"]) {
    assert.ok(panel.includes(kept), `painel preservado: ${kept}`);
  }
  const grid = readFileSync(new URL("../../components/colecoes/colecoes/pokedex-grid.tsx", import.meta.url), "utf8");
  assert.doesNotMatch(grid, /WishButton|wishlist/i, "a grade (captura, número, preço) não ganha marcador sobreposto");
});
