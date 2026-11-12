// V1-10 (extensão) — Favoritos na página da coleção. COLLECTION PAGE FAVORITES INTEGRATION-01.
// Executar: node --experimental-strip-types --test lib/favorites/collection-page-favorites.test.ts (a partir de web/)
// Verificações ESTRUTURAIS (código e CSS); a interação renderizada fica para a homologação visual.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
const code = (src: string) => src.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, "");

test("botão: variante `corner` opcional; sem ela, exatamente o coração de antes (Acervo, Pesquisa, Cartas favoritas)", () => {
  const button = code(read("components/favorites/card-favorite-button.tsx"));
  assert.ok(button.includes('indicator = "chip"'), "padrão = chip");
  assert.ok(button.includes('indicator === "corner" ? `${styles.favorite} ${styles.corner}` : styles.favorite'));
  assert.ok(button.includes("data-card-fav={cardId}") && button.includes("aria-pressed={isFavorite}") && button.includes("aria-label={favoriteToggleLabel(cardName)}"), "mesmo contrato com o controlador");
  for (const file of ["components/colecoes/acervo/acervo-view.tsx", "components/pesquisa/pesquisa-view.tsx", "components/favorites/favorite-cards-view.tsx"]) {
    assert.ok(!code(read(file)).includes('indicator="corner"'), `${file} inalterado`);
  }
});

test("CSS do canto: triângulo só na favorita em repouso; coração com hover/foco; toque sem controle invisível", () => {
  const css = read("components/favorites/card-favorite.module.css");
  assert.ok(/\.cornerMark \{\s*display: none;[\s\S]*background: hsl\(var\(--favorite\)\);[\s\S]*clip-path: polygon\(0 0, 100% 0, 100% 100%\);[\s\S]*pointer-events: none;/.test(css));
  assert.ok(/\.corner\[aria-pressed="true"\] \.cornerMark \{\s*display: block;/.test(css), "favorita: triângulo");
  assert.ok(/\.corner\[aria-pressed="true"\] \.favoriteIcon \{\s*opacity: 0;/.test(css), "favorita em repouso: sem coração sobre a arte");
  assert.ok(/\.corner:focus-visible \.favoriteIcon \{\s*opacity: 1;/.test(css) && /\.corner:focus-visible \.cornerMark \{\s*display: none;/.test(css), "teclado: coração visível, triângulo some");
  const desktop = css.slice(css.lastIndexOf("@media (hover: hover) and (pointer: fine)"));
  assert.ok(desktop.includes('.favoriteHost:hover .corner[aria-pressed="true"] .favoriteIcon') && desktop.includes(".favoriteHost:hover .corner .cornerMark"), "desktop: hover revela o coração e esconde o triângulo");
  // Não favorita: regra do V1-10 — desktop só em hover/foco; toque sempre visível (nunca um controle invisível clicável).
  assert.ok(/@media \(hover: hover\) and \(pointer: fine\) \{\s*\.favorite\[aria-pressed="false"\] \.favoriteIcon \{\s*opacity: 0;/.test(css));
  // A regra padrão (chip) não foi tocada.
  assert.ok(/\.favorite\[aria-pressed="true"\] \.favoriteIcon \{\s*fill: hsl\(var\(--favorite\)\);/.test(css));
});

test("página da coleção: leitura em lote (5336) da página exibida; controlador homologado; id da CARTA", () => {
  const page = code(read("app/colecoes/colecoes/[id]/page.tsx"));
  assert.ok(page.includes("getMyCardFavoriteIds(supabase, shownCardIds)"), "Set padrão/Master Set: uma leitura em lote");
  assert.ok(page.includes("getMyCardFavoritesByVariant(supabase, items.items.map((item) => item.cardVariantId))"), "livre: a mesma do Acervo");
  assert.ok(!/\.map\([^)]*setCardFavorite|getMyCardFavoriteIds\(supabase, \[/.test(page), "nunca por carta");
  const view = code(read("components/colecoes/colecoes/collection-view.tsx"));
  assert.ok(view.includes("<CardFavoritesController>{children}</CardFavoritesController>"), "mesmo controlador (otimista, reversão, sincronia)");
  assert.ok(view.includes("favorite={favoriteCards ? favoriteCards.has(position.cardId.toLowerCase()) : undefined}"));
  assert.ok(view.includes('<CardFavoriteButton cardId={position.cardId} cardName={`${position.cardName} (${caption})`} isFavorite={favorite} indicator="corner" />'));
  const master = code(read("components/colecoes/colecoes/master-set-gallery.tsx"));
  assert.ok(master.includes("cardId={position.cardId}") && master.includes('indicator="corner"'), "Master Set: o favorito é da carta, igual em todo acabamento");
  const free = code(read("components/colecoes/colecoes/free-collection-view.tsx"));
  assert.ok(free.includes('<CardFavoriteButton cardId={favorite.cardId} cardName={`${item.cardName} (${caption})`} isFavorite={favorite.isFavorite} indicator="corner" />'));
});

test("convivência: Desejos no canto esquerdo, coração no direito, quantidade desce; lupa e posse intactas", () => {
  for (const file of ["components/colecoes/colecoes/collection-view.tsx", "components/colecoes/colecoes/master-set-gallery.tsx", "components/colecoes/colecoes/free-collection-view.tsx"]) {
    const src = code(read(file));
    assert.ok(src.includes("styles.qtyBelowFavorite"), `${file}: ×N fora do canto do coração`);
    // O coração é irmão da ampliação (nunca dentro do gatilho da lupa).
    const zoomClose = src.indexOf("</CardZoomTrigger>");
    assert.ok(zoomClose > 0 && src.indexOf('indicator="corner"', zoomClose) > zoomClose, `${file}: fora da lupa`);
  }
  assert.ok(/\.qtyBelowFavorite \{\s*top: 2\.75rem;/.test(read("components/colecoes/colecoes/colecoes.module.css")));
  assert.ok(/\.wish \{\s*position: absolute;\s*top: -0\.1875rem;[\s\S]*?left: -0\.1875rem;/.test(read("components/wishlist/wishlist.module.css")), "Desejos segue no canto superior esquerdo");
});

test("acesso: só a página da coleção do titular; compartilhada/pública sem coração; nada de permissão nova", () => {
  const shared = code(read("components/colecoes/sharing/shared-collection-view.tsx"));
  assert.ok(!/favorite=|CardFavorite|favoriteCards/.test(shared), "participante e vitrine: sem Favoritos nesta rodada");
  const page = code(read("app/colecoes/colecoes/[id]/page.tsx"));
  assert.ok(!/service_role|\.insert\(|\.update\(|\.delete\(/.test(page));
});
