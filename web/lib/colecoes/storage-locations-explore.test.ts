// Meus locais — Central de organização física (STORAGE LOCATIONS UX REDESIGN-01).
// Executar: node --experimental-strip-types --test lib/colecoes/storage-locations-explore.test.ts (a partir de web/)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  LOCATION_SORT_OPTIONS,
  type StorageLocation,
  UNLOCATED_ACERVO_HREF,
  exploreLocations,
  kindFilterOptions,
  locationAcervoHref,
  organizationShare,
  organizationShareText,
  pendingOrganizationText,
  acervoShareText,
  acervoShareWidth,
  cardsCopiesLabel,
  groupBySet,
  organizeLabel,
  searchKey,
  splitLocationCode,
  storageDeleteBlock,
} from "./storage-locations.ts";
import { parseAcervoState, toItemsRpcParams } from "./acervo.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
const code = (src: string) => src.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, "");
const uuid = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;

const KINDS = [
  { code: "BINDER", label: "Fichário" },
  { code: "BOX", label: "Caixa" },
  { code: "ETB", label: "ETB" },
];

function loc(n: number, name: string, kindCode: string | null, cardCount: number, defaults = 0): StorageLocation {
  const kind = KINDS.find((k) => k.code === kindCode);
  return { id: uuid(n), name, kindCode, kindLabel: kind?.label ?? null, cardCount, defaultCollectionCount: defaults, canDelete: cardCount === 0 && defaults === 0 };
}

const LOCATIONS = [
  loc(1, "Fichário azul — Escarlate e Violeta, coleção principal de 2024", "BINDER", 360, 1),
  loc(2, "caixa do armário", "BOX", 1204),
  loc(3, "ETB Evoluções Prismáticas", "ETB", 0),
  loc(4, "Álbum antigo", null, 12),
  loc(5, "Fichário vermelho", "BINDER", 12),
];

test("percentual de organização: mesma base da 5219, truncado; acervo vazio sem porcentagem", () => {
  // L2-01: uma casa decimal, arredondada, pt-BR; nunca 100,0% com exemplar sem local.
  assert.equal(organizationShare({ totalCards: 4062, locatedCards: 4009 }), 98.7);
  assert.equal(organizationShareText({ totalCards: 4062, locatedCards: 4009 }), "98,7%");
  assert.equal(organizationShareText({ totalCards: 3, locatedCards: 2 }), "66,7%");
  assert.equal(organizationShareText({ totalCards: 10000, locatedCards: 9999 }), "99,9%", "99,99% não vira 100,0%");
  assert.equal(organizationShareText({ totalCards: 4000, locatedCards: 1 }), "<0,1%");
  assert.equal(organizationShareText({ totalCards: 40, locatedCards: 40 }), "100,0%");
  assert.equal(organizationShare({ totalCards: 40, locatedCards: 40 }), 100);
  assert.equal(organizationShare({ totalCards: 0, locatedCards: 0 }), null);
  assert.equal(organizationShareText({ totalCards: 0, locatedCards: 0 }), "—");
});

test("organização pendente: frase dinâmica; nada pendente → null", () => {
  assert.equal(pendingOrganizationText(53), "53 exemplares aguardam organização.");
  assert.equal(pendingOrganizationText(1), "1 exemplar aguarda organização.");
  assert.equal(pendingOrganizationText(1234), "1.234 exemplares aguardam organização.");
  assert.equal(pendingOrganizationText(0), null);
});

test("links reaproveitam o filtro de local do Meu acervo (WHERE-04, filtro no banco pela 5220)", () => {
  assert.equal(UNLOCATED_ACERVO_HREF, "/colecoes/acervo?local=sem");
  assert.equal(locationAcervoHref(uuid(7)), `/colecoes/acervo?local=${uuid(7)}`);
  const none = toItemsRpcParams(parseAcervoState({ local: "sem" }));
  assert.equal(none.p_without_storage, true);
  assert.equal(none.p_storage_container_id, null);
  const one = toItemsRpcParams(parseAcervoState({ local: uuid(7) }));
  assert.equal(one.p_storage_container_id, uuid(7));
  assert.equal(one.p_without_storage, false);
});

test("filtro de tipo: só tipos presentes (ordem do catálogo) + 'Sem tipo definido'; nenhum tipo artificial", () => {
  const options = kindFilterOptions(LOCATIONS, KINDS);
  assert.deepEqual(options.map((o) => [o.value, o.label, o.count, o.copies]), [
    ["all", "Todos os locais", 5, 1588],
    ["BINDER", "Fichário", 2, 372],
    ["BOX", "Caixa", 1, 1204],
    ["ETB", "ETB", 1, 0],
    ["none", "Sem tipo definido", 1, 12],
  ]);
  // Soma das facetas = exemplares com local definido (cada exemplar localizado está em um só local).
  assert.equal(options.filter((o) => o.value !== "all").reduce((n, o) => n + o.copies, 0), options[0]!.copies);
  const onlyBoxes = kindFilterOptions([loc(9, "A", "BOX", 1)], KINDS);
  assert.deepEqual(onlyBoxes.map((o) => o.value), ["all", "BOX"], "sem local sem tipo → sem a opção");
});

test("busca por nome (sem acento, sem maiúsculas) e filtro de tipo combinados", () => {
  const ids = (list: StorageLocation[]) => list.map((l) => l.id);
  assert.equal(searchKey("  Álbum   ANTIGO "), "album antigo");
  assert.deepEqual(ids(exploreLocations(LOCATIONS, { query: "fichario", kind: "all", sort: "name" })), [uuid(1), uuid(5)]);
  assert.deepEqual(ids(exploreLocations(LOCATIONS, { query: "album", kind: "all", sort: "name" })), [uuid(4)]);
  assert.deepEqual(ids(exploreLocations(LOCATIONS, { query: "", kind: "BINDER", sort: "name" })), [uuid(1), uuid(5)]);
  assert.deepEqual(ids(exploreLocations(LOCATIONS, { query: "", kind: "none", sort: "name" })), [uuid(4)]);
  assert.deepEqual(ids(exploreLocations(LOCATIONS, { query: "azul", kind: "BOX", sort: "name" })), [], "sem correspondência");
});

test("ordem: nome A–Z (padrão, pt-BR), mais e menos exemplares (empate pelo nome)", () => {
  assert.deepEqual(LOCATION_SORT_OPTIONS.map((o) => o.value), ["name", "most", "least"]);
  const names = (sort: "name" | "most" | "least") => exploreLocations(LOCATIONS, { query: "", kind: "all", sort }).map((l) => l.name);
  assert.deepEqual(names("name"), ["Álbum antigo", "caixa do armário", "ETB Evoluções Prismáticas", "Fichário azul — Escarlate e Violeta, coleção principal de 2024", "Fichário vermelho"]);
  assert.deepEqual(names("most").slice(0, 2), ["caixa do armário", "Fichário azul — Escarlate e Violeta, coleção principal de 2024"]);
  assert.deepEqual(names("most").slice(-3), ["Álbum antigo", "Fichário vermelho", "ETB Evoluções Prismáticas"], "empate (12) pelo nome; vazio por último");
  assert.equal(names("least")[0], "ETB Evoluções Prismáticas");
  // Não altera a lista recebida.
  assert.equal(LOCATIONS[0]!.name.startsWith("Fichário azul"), true);
});

test("regras de exclusão preservadas (5218): só vazio e sem ser local padrão", () => {
  assert.equal(storageDeleteBlock(LOCATIONS[0]!), "has_cards");
  assert.equal(storageDeleteBlock(LOCATIONS[2]!), null);
  assert.equal(storageDeleteBlock(loc(8, "x", null, 0, 2)), "collection_default");
});

test("página (Conceito B): cabeçalho compacto, coluna de organização, nenhum relatório de Locais exposto", () => {
  const view = code(read("components/colecoes/locais/locations-view.tsx"));
  assert.ok(view.includes("Saiba onde estão suas cartas e acompanhe seus espaços de armazenamento."));
  assert.ok(!view.includes("acervoStyles.numeral"), "numeral decorativo removido");
  assert.ok(view.includes("organizeLabel(summary.unlocatedCards)") && view.includes("href={UNLOCATED_ACERVO_HREF}"));
  assert.ok(view.includes('role="progressbar"'));
  assert.ok(!/relat[oó]rio|Relatórios/i.test(view), "nenhum atalho para relatório inexistente");
  const manager = code(read("components/colecoes/locais/locations-manager.tsx"));
  assert.ok(!/relat[oó]rio/i.test(manager));
  assert.ok(!manager.includes("Para excluir, o local precisa estar vazio."), "aviso não se repete em todo cartão");
  assert.ok(manager.includes('aria-haspopup="menu"') && manager.includes('role="menuitem"'), "Editar/Excluir no menu de mais ações");
  assert.ok(manager.includes("readLocationContents({ id: location.id })"), "consulta do conteúdo é leitura");
});

test("consulta do local: só leitura, mesma leitura do Meu acervo e fichário digital por link", () => {
  const queries = code(read("lib/colecoes/storage-locations-queries.ts"));
  const fn = queries.slice(queries.indexOf("export async function readAllLocationItems"));
  assert.ok(fn.includes("getAcervoItems(supabase, base)"));
  assert.ok(fn.includes('storage: { kind: "location", id: storageId }'));
  assert.ok(!/\.insert\(|\.update\(|\.delete\(|\.upsert\(/.test(fn), "nenhuma escrita");
  assert.ok(!/capacidade|ocupa/i.test(fn), "sem capacidade/ocupação inventadas");
  const actions = code(read("app/colecoes/locais/actions.ts"));
  const read5220 = actions.slice(actions.indexOf("export async function readLocationContents"));
  assert.ok(read5220.includes("if (!isUuid(input?.id)) return { ok: false };"));
  assert.ok(!read5220.includes("revalidate"), "leitura não revalida nada");
});

// ---------------------------------------------------------------------------
// Conceito B — inventário (STORAGE LOCATIONS CONCEPT B IMPLEMENTATION-01)

test("código do colecionador: só o padrão inequívoco no começo do nome; nunca inventado", () => {
  assert.deepEqual(splitLocationCode("F001 - Fichário Coleção ME1"), { code: "F001", title: "Fichário Coleção ME1" });
  assert.deepEqual(splitLocationCode("ETB002.5 - Heróis Excelsos (ME2.5)"), { code: "ETB002.5", title: "Heróis Excelsos (ME2.5)" });
  assert.deepEqual(splitLocationCode("BX001 – Card Box Vermelha"), { code: "BX001", title: "Card Box Vermelha" });
  assert.deepEqual(splitLocationCode("F00X - Fichário Minha Pokédex"), { code: "F00X", title: "Fichário Minha Pokédex" });
  for (const name of ["Local padrão", "Caixa do armário", "ME3 Equilíbrio", "fichario-1 - azul", "F001-Fichário", "Deck - principal", "F001 - "]) {
    assert.deepEqual(splitLocationCode(name), { code: null, title: name }, name);
  }
});

test("participação no acervo: uma casa, arredondada; vazio sem número", () => {
  assert.equal(acervoShareText(576, 4062), "14,2%", "L2-01: arredondado, mesmo denominador da barra");
  assert.equal(acervoShareWidth(576, 4062).toFixed(2), "14.18");
  assert.equal(acervoShareWidth(0, 4062), 0);
  assert.equal(acervoShareWidth(5, 0), 0);
  assert.equal(acervoShareText(76, 4062), "1,9%");
  assert.equal(acervoShareText(1, 4062), "<0,1%");
  assert.equal(acervoShareText(4062, 4062), "100,0%");
  assert.equal(acervoShareText(0, 4062), null);
  assert.equal(acervoShareText(5, 0), null);
});

test("ação de pendência e agrupamento do painel por Card Set (na ordem recebida)", () => {
  assert.equal(organizeLabel(53), "Organizar 53 exemplares");
  assert.equal(organizeLabel(1), "Organizar 1 exemplar");
  assert.equal(organizeLabel(1234), "Organizar 1.234 exemplares");
  const groups = groupBySet([
    { cardSetCode: "me3", cardSetName: "Equilíbrio Perfeito", n: 1 },
    { cardSetCode: "me3", cardSetName: "Equilíbrio Perfeito", n: 2 },
    { cardSetCode: "me2", cardSetName: "Fogo Fantasmagórico", n: 3 },
  ]);
  assert.deepEqual(groups.map((g) => [g.code, g.items.length]), [["me3", 2], ["me2", 1]]);
  assert.deepEqual(groupBySet([]), []);
});

test("índice e painel: linhas com recipiente desenhado, participação (não capacidade) e cartas em grade", () => {
  const manager = code(read("components/colecoes/locais/locations-manager.tsx"));
  assert.ok(manager.includes("<StorageGlyph kindCode={location.kindCode} />"), "recipiente na linha");
  assert.ok(manager.includes("acervoShareText(count, totalCards)"));
  assert.ok(!/ocupa[çc][ãa]o|espa[çc]o livre|cheio|capacidade/i.test(manager), "nenhum termo de capacidade");
  assert.ok(manager.includes("splitLocationCode(location.name)"));
  assert.ok(manager.includes('aria-pressed={pressed}'), "facetas com estado ativo acessível");
  assert.ok(manager.includes("groupBySet(ready.items)"), "cartas por Set no painel (leitura completa)");
  assert.ok(!manager.includes("<Select id={kindId}"), "sem segunda barra de filtro de tipo");
  const glyph = code(read("components/colecoes/locais/storage-glyph.tsx"));
  for (const kind of ["BINDER", "ETB", "BOX", "FOLDER", "DECK_BOX", "CASE", "SAFE"]) assert.ok(glyph.includes(`case "${kind}":`), kind);
  assert.ok(glyph.includes('aria-hidden="true"'));
});

// ---------------------------------------------------------------------------
// L2-01 — refinamentos, encontrar carta, prévia, totais por Set, inventário

test("totais por Card Set: cartas (identidades) e exemplares, com singular/plural", () => {
  const items = [
    { cardSetCode: "me3", cardSetName: "Equilíbrio Perfeito", copiesCount: 5 },
    { cardSetCode: "me3", cardSetName: "Equilíbrio Perfeito", copiesCount: 1 },
    { cardSetCode: "me2", cardSetName: "Fogo Fantasmagórico", copiesCount: 1 },
  ];
  const groups = groupBySet(items);
  assert.deepEqual(groups.map((g) => [g.code, g.cards, g.copies]), [["me3", 2, 6], ["me2", 1, 1]]);
  assert.equal(cardsCopiesLabel(1, 1), "1 carta · 1 exemplar");
  assert.equal(cardsCopiesLabel(2, 5), "2 cartas · 5 exemplares");
  assert.equal(cardsCopiesLabel(30, 55), "30 cartas · 55 exemplares");
  assert.equal(cardsCopiesLabel(1234, 5678), "1.234 cartas · 5.678 exemplares");
});

test("painel: totais do Set vêm da leitura COMPLETA; prévia sem navegar; sem Editar/Excluir; inventário no rodapé", () => {
  const manager = code(read("components/colecoes/locais/locations-manager.tsx"));
  const panel = manager.slice(manager.indexOf("function LocationContentPanel"), manager.indexOf("function CardPreview"));
  assert.ok(panel.includes("cardsCopiesLabel(group.cards, group.copies)"));
  assert.ok(panel.includes("visibleGroups(groups, visible)"), "só a exibição é fatiada");
  assert.ok(panel.includes("onOpen={() => setPreview(item)}"));
  assert.ok(!panel.includes("acervoHref("), "a miniatura não navega para o Meu acervo");
  assert.ok(!/Editar|Excluir/.test(panel), "Editar e Excluir só no menu da relação");
  assert.ok(panel.includes("Gerar inventário deste local"));
  assert.ok(!panel.includes("Abrir no Meu acervo"));
  const preview = manager.slice(manager.indexOf("function CardPreview"), manager.indexOf("function CardFinder"));
  assert.ok(preview.includes("<DialogPrimitive.Root"), "diálogo: Esc e foco pelo Radix");
  assert.ok(!/update|delete|move/i.test(preview), "prévia sem operações");
  const queries = code(read("lib/colecoes/storage-locations-queries.ts"));
  const contents = queries.slice(queries.indexOf("export async function getLocationContents"));
  assert.ok(contents.includes("readAllLocationItems(supabase, storageId)"));
});

test("encontrar carta: busca do Meu acervo + exemplares da 5162 + local físico de cada exemplar; Σ = total", () => {
  const queries = code(read("lib/colecoes/storage-locations-queries.ts"));
  const search = queries.slice(queries.indexOf("export async function searchAcervoCards"), queries.indexOf("export type CardLocations"));
  assert.ok(search.includes("query: q"), "busca canônica do Meu acervo (5220 p_search)");
  assert.ok(!search.includes("storage:"), "sem filtro de local: o acervo todo do titular");
  const locate = queries.slice(queries.indexOf("export async function locateCardCopies"), queries.indexOf("export type LocationInventory"));
  assert.ok(locate.includes("getAcervoItemDetail(supabase, key)"), "identidade = variante + idioma (5162)");
  assert.ok(locate.includes('.select("id, storage_container_id")'), "local FÍSICO do exemplar");
  assert.ok(!locate.includes("collection"), "alocação em coleção não substitui localização");
  assert.ok(locate.includes("if (storage.size !== ids.length)"), "todos os exemplares localizados ou erro");
  assert.ok(!/\.insert\(|\.update\(|\.delete\(|\.upsert\(/.test(queries), "nenhuma escrita");
  const manager = code(read("components/colecoes/locais/locations-manager.tsx"));
  assert.ok(manager.includes('role="tablist"') && manager.includes("Encontrar carta") && manager.includes("Explorar locais"));
  assert.ok(manager.includes("located.result.unlocated"), "sem localização aparece");
  assert.ok(manager.includes('onClick={() => open({ kind: "view", location })}'), "local encontrado abre o painel");
});

test("título e barra: Meus Locais de Armazenamento; barra no mesmo denominador do percentual", () => {
  const view = code(read("components/colecoes/locais/locations-view.tsx"));
  assert.ok(view.includes("Meus Locais de Armazenamento"));
  const manager = code(read("components/colecoes/locais/locations-manager.tsx"));
  assert.ok(manager.includes("acervoShareWidth(count, totalCards)"));
  assert.ok(!manager.includes("largest"), "sem normalizar pelo maior local");
});

test("prévia da carta: quantidades nomeadas (Neste local / No acervo), retorno na base, sem navegação", () => {
  const manager = code(read("components/colecoes/locais/locations-manager.tsx"));
  const preview = manager.slice(manager.indexOf("function CardPreview"), manager.indexOf("function CardFinder"));
  assert.ok(preview.includes("<dt>Neste local</dt>") && preview.includes("<dt>No acervo</dt>"));
  assert.ok(preview.includes('pluralize(item.copiesCount, "exemplar", "exemplares")'));
  assert.ok(preview.includes('pluralize(item.copiesOwned, "exemplar", "exemplares")'));
  assert.ok(!preview.includes("storageMatchLabel"), "sem a forma condensada \"8 aqui · 10 no total\"");
  assert.ok(preview.includes("<DialogPrimitive.Close asChild>") && preview.includes("Voltar às cartas"));
  assert.ok(!/href=|Link/.test(preview), "não navega");
  const css = read("components/colecoes/locais/locais.module.css");
  assert.ok(/\.previewBack \{\s*margin-top: auto;/.test(css), "botão na base da coluna");
  assert.ok(css.includes("aspect-ratio: 63 / 88") && css.includes("object-fit: contain"), "carta sem corte nem distorção");
});

test("prévia (UX-02): número e idioma em linhas próprias; local do painel; raridade e variante canônicas; nenhuma leitura nova", () => {
  const manager = code(read("components/colecoes/locais/locations-manager.tsx"));
  const preview = manager.slice(manager.indexOf("function CardPreview"), manager.indexOf("function CardFinder"));
  for (const label of ["Número", "Idioma", "Raridade", "Variante", "Local de armazenamento"]) assert.ok(preview.includes(label), label);
  assert.ok(!/Nº \{formatCollectorNumber[^\n]*· \{languageLabel/.test(preview), "número e idioma não dividem mais a mesma linha");
  assert.ok(preview.includes("variantName(item.variantLabel)"), "variante pelo nome canônico (padrão também nomeada)");
  assert.ok(preview.includes("{locationName}"), "nome real do local");
  assert.ok(!/readLocation|readCard|supabase/.test(preview), "sem consulta na prévia");
  const panel = manager.slice(manager.indexOf("function LocationContentPanel"), manager.indexOf("function CardTile"));
  assert.ok(panel.includes("locationName={location.name}"), "o local do painel que originou a prévia");
  assert.ok(panel.includes("previewRarityLabel(item.rarityCode, ready?.rarityNames ?? null)"));
  const queries = code(read("lib/colecoes/storage-locations-queries.ts"));
  const contents = queries.slice(queries.indexOf("export async function getLocationContents"), queries.indexOf("export async function searchAcervoCards"));
  assert.ok(contents.includes("readRarityCatalog("), "catálogo canônico de raridades (5355), em paralelo com a leitura do local");
  assert.ok(!/\.insert\(|\.update\(|\.delete\(|\.upsert\(/.test(queries));
});

test("raridade: nome do catálogo; sem código ou catálogo indisponível → estado honesto, nada inferido", async () => {
  const { previewRarityLabel } = await import("./storage-locations.ts");
  const names = { SPECIAL_ILLUSTRATION_RARE: "Ilustração Rara Especial", COMMON: "Comum" };
  assert.equal(previewRarityLabel("SPECIAL_ILLUSTRATION_RARE", names), "Ilustração Rara Especial");
  assert.equal(previewRarityLabel(null, names), "Não cadastrada");
  assert.equal(previewRarityLabel("COMMON", null), "Indisponível no momento");
  assert.equal(previewRarityLabel("UNKNOWN_CODE", names), "Indisponível no momento");
});

test("filtro contextual: identidade exata (variante + idioma), nunca pelo nome", async () => {
  const { findLocatedItem } = await import("./storage-locations.ts");
  const V = "00000000-0000-4000-8000-000000000001";
  const R = "00000000-0000-4000-8000-000000000002";
  const items = [
    { cardVariantId: V, languageCode: "pt-BR", cardName: "Misdreavus", copiesCount: 1 },
    { cardVariantId: V, languageCode: "en", cardName: "Misdreavus", copiesCount: 2 },
    { cardVariantId: R, languageCode: "pt-BR", cardName: "Misdreavus", copiesCount: 3 },
  ];
  assert.equal(findLocatedItem(items, { cardVariantId: V, languageCode: "pt-BR" })?.copiesCount, 1);
  assert.equal(findLocatedItem(items, { cardVariantId: R, languageCode: "pt-BR" })?.copiesCount, 3, "reversa não se mistura com a padrão");
  assert.equal(findLocatedItem(items, { cardVariantId: V.toUpperCase(), languageCode: "en" })?.copiesCount, 2, "idiomas separados");
  assert.equal(findLocatedItem(items, { cardVariantId: R, languageCode: "en" }), null, "não está neste local");
});

test("filtro contextual: só pela origem Encontrar carta; reversível no mesmo painel; totais e relatório do local inteiro", () => {
  const manager = code(read("components/colecoes/locais/locations-manager.tsx"));
  const finder = manager.slice(manager.indexOf("function CardFinder"), manager.indexOf("function LocationFormPanel"));
  assert.ok(finder.includes('open({ kind: "view", location, focus: { cardVariantId: selected.cardVariantId, languageCode: selected.languageCode } })'));
  const row = manager.slice(manager.indexOf("function LocationRow"), manager.indexOf("function ActionsMenu"));
  assert.ok(row.includes('open({ kind: "view", location })') && !row.includes("focus:"), "Explorar locais: conteúdo completo");
  const provider = manager.slice(manager.indexOf("export function LocationsProvider"), manager.indexOf("export function NewLocationButton"));
  assert.ok(provider.includes("focus={panel.focus ?? null}"));
  assert.ok(provider.includes('setPanel({ kind: "report", location })'), "relatório sem o filtro");
  const panel = manager.slice(manager.indexOf("function LocationContentPanel"), manager.indexOf("function CardTile"));
  assert.ok(panel.includes("useState<CardIdentity | null>(focus)"), "o filtro nasce a cada abertura (reaplicado ao reabrir pela pesquisa)");
  assert.ok(panel.includes("findLocatedItem(ready.items, filter)"), "sobre a MESMA leitura completa — nenhuma consulta nova");
  assert.ok(panel.includes("setFilter(null)") && panel.includes("contentHeadRef.current?.focus()"), "remove só o filtro, foco no título do conteúdo");
  assert.ok(panel.includes("location.cardCount") && panel.includes("ready.totalGroups"), "totais do local inteiro");
  assert.ok(panel.includes("Totais do local inteiro"));
  assert.ok(panel.includes("onClick={() => onReport(location)}"), "inventário sempre do local inteiro");
  const located = manager.slice(manager.indexOf("function LocatedCard"), manager.indexOf("function CardPreview"));
  assert.ok(located.includes("Carta localizada") === false && located.includes("Ver todas as cartas deste local"));
  assert.ok(located.includes("<CardTile"), "mesma miniatura da grade, que abre a mesma prévia");
  assert.ok(located.includes("item.copiesCount"), "quantidade desta versão NESTE local");
  assert.ok(panel.includes('"Carta localizada"'));
});

test("cabeçalho (HEADER ALIGNMENT-01): palco comum do módulo, grafismo de armazenamento, sem números duplicados; botão do módulo", () => {
  const view = code(read("components/colecoes/locais/locations-view.tsx"));
  const header = view.slice(view.indexOf("function Header"), view.indexOf("function HeroStorage"));
  assert.ok(header.includes("acervoStyles.hero") && header.includes("colecoesStyles.libraryHero"), "mesmo palco de Minhas coleções e Cartas favoritas");
  assert.ok(header.includes("acervoStyles.title") && header.includes("acervoStyles.lede"), "mesma escala de título e lede");
  assert.ok(header.includes("Meus Locais de Armazenamento") && header.includes("Saiba onde estão suas cartas"));
  assert.ok(!/numeral|Ledger|formatCount|summary/.test(header), "indicadores só na coluna lateral");
  const hero = view.slice(view.indexOf("function HeroStorage"), view.indexOf("function Organization"));
  assert.ok(hero.includes('aria-hidden="true"') && hero.includes("colecoesStyles.heroShelf"), "grafismo decorativo, baixo contraste do módulo");
  assert.ok(view.includes("regionStyles.region"), "passagem para a área de trabalho pela região comum");
  const manager = code(read("components/colecoes/locais/locations-manager.tsx"));
  const button = manager.slice(manager.indexOf("export function NewLocationButton"), manager.indexOf("export function LocationsNotice"));
  assert.ok(button.includes("addStyles.launchPrimary") && button.includes("addStyles.launcherHero"), "mesmo lançador de Nova coleção / Adicionar cartas");
  assert.ok(button.includes('open({ kind: "create" })'), "função preservada");
});
