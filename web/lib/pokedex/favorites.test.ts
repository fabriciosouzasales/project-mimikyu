// Espécie favorita — regras puras, leitor e contexto de origem (Pokédex P6).
// Executar: node --experimental-strip-types --test lib/pokedex/favorites.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  type FavoriteEntry,
  applyFavoritesFilter,
  countByGeneration,
  favoriteActionHint,
  favoriteAnnouncement,
  favoriteErrorMessage,
  favoriteFailureReason,
  favoriteSpeciesNameFromLabel,
  favoriteToggleLabel,
  filterByGeneration,
  initialFavoriteEntry,
  isValidNationalDexNumber,
  settleFavorite,
  toFavoriteSet,
  toggleFavorite,
} from "./favorites.ts";
import {
  galleryBasePath,
  nationalPokedexHref,
  parseOriginParam,
  pokedexHref,
  speciesDetailHref,
} from "./format.ts";
import { resolveSpeciesNavigation, type NavigationSpecies } from "./navigation.ts";
import { getMyPokedexFavorites } from "./queries.ts";

// ---------------------------------------------------------------------------
// Recorte
// ---------------------------------------------------------------------------

const sp = (n: number) => ({ national_dex_number: n, species_name: `Sp${n}` });

test("recorte de favoritos mantém a ordem recebida e só as favoritas", () => {
  const list = [sp(1), sp(4), sp(6), sp(25), sp(150)];
  assert.deepEqual(
    applyFavoritesFilter(list, new Set([150, 6, 25])).map((s) => s.national_dex_number),
    [6, 25, 150],
  );
});

test("recorte com conjunto vazio devolve lista vazia; favorito fora da lista (pesquisa/geração) é ignorado", () => {
  assert.deepEqual(applyFavoritesFilter([sp(1), sp(2)], new Set()), []);
  assert.deepEqual(applyFavoritesFilter([sp(1), sp(2)], new Set([999])), []);
});

test("toFavoriteSet aceita números válidos (inclusive em texto) e descarta linhas fora do contrato", () => {
  const set = toFavoriteSet([
    { national_dex_number: 25 },
    { national_dex_number: "6" },
    { national_dex_number: 0 },
    { national_dex_number: 10000 },
    { national_dex_number: 2.5 },
    { national_dex_number: null },
    {},
    { national_dex_number: 25 },
  ]);
  assert.deepEqual([...set].sort((a, b) => a - b), [6, 25]);
});

test("isValidNationalDexNumber espelha a faixa da função SQL (1..9999, inteiro)", () => {
  for (const ok of [1, 25, 1025, 9999]) assert.equal(isValidNationalDexNumber(ok), true);
  for (const bad of [0, -1, 10000, 1.5, Number.NaN, "25", null, undefined]) assert.equal(isValidNationalDexNumber(bad), false);
});

// ---------------------------------------------------------------------------
// Máquina de intenção: otimista, serializada, última intenção vence
// ---------------------------------------------------------------------------

test("clique simples: muda na hora e grava o valor desejado", () => {
  const step = toggleFavorite(25, initialFavoriteEntry(false));
  assert.deepEqual(step.entry, { confirmed: false, desired: true, inFlight: true });
  assert.deepEqual(step.send, { number: 25, value: true });

  const done = settleFavorite(25, step.entry, { ok: true, value: true });
  assert.deepEqual(done.entry, { confirmed: true, desired: true, inFlight: false });
  assert.equal(done.send, null);
  assert.equal(done.reverted, false);
});

test("cliques durante a gravação não disparam gravação concorrente; a última intenção sai no settle", () => {
  let entry: FavoriteEntry = initialFavoriteEntry(false);
  const first = toggleFavorite(25, entry); // true, em andamento
  entry = first.entry;
  const second = toggleFavorite(25, entry); // usuário desfaz: false (sem envio)
  assert.equal(second.send, null);
  entry = second.entry;
  const third = toggleFavorite(25, entry); // e refaz: true (sem envio)
  assert.equal(third.send, null);
  entry = third.entry;
  assert.deepEqual(entry, { confirmed: false, desired: true, inFlight: true });

  // A primeira gravação (true) termina: intenção atual (true) = confirmado -> nada a enviar.
  const settled = settleFavorite(25, entry, { ok: true, value: true });
  assert.equal(settled.send, null);
  assert.deepEqual(settled.entry, { confirmed: true, desired: true, inFlight: false });
});

test("mudança de ideia durante a gravação: ao terminar, grava a intenção atual (nunca inverte a tela)", () => {
  let entry = toggleFavorite(25, initialFavoriteEntry(false)).entry; // grava true
  entry = toggleFavorite(25, entry).entry; // desfaz: desejado false, gravação ainda em andamento
  const settled = settleFavorite(25, entry, { ok: true, value: true }); // resposta "atrasada" true
  // A tela continua mostrando false (última intenção) e uma nova gravação false sai.
  assert.equal(settled.entry.desired, false);
  assert.equal(settled.entry.confirmed, true);
  assert.equal(settled.entry.inFlight, true);
  assert.deepEqual(settled.send, { number: 25, value: false });

  const final = settleFavorite(25, settled.entry, { ok: true, value: false });
  assert.deepEqual(final.entry, { confirmed: false, desired: false, inFlight: false });
  assert.equal(final.send, null);
});

test("cliques rápidos em série terminam no estado do último clique (paridade)", () => {
  let entry: FavoriteEntry = initialFavoriteEntry(false);
  const sends: boolean[] = [];
  for (let i = 0; i < 7; i++) {
    const step = toggleFavorite(1, entry);
    entry = step.entry;
    if (step.send) sends.push(step.send.value);
  }
  assert.equal(sends.length, 1, "uma única gravação em andamento");
  assert.equal(entry.desired, true, "7 cliques a partir de não favorito = favorito");
  // Servidor responde a primeira gravação; o desejado (true) já é o confirmado.
  const settled = settleFavorite(1, entry, { ok: true, value: true });
  assert.equal(settled.send, null);
  assert.equal(settled.entry.confirmed, true);
});

test("falha: a tela volta ao último estado confirmado e a falha é sinalizada", () => {
  const entry = toggleFavorite(25, initialFavoriteEntry(true)).entry; // tenta desfavoritar
  assert.equal(entry.desired, false);
  const settled = settleFavorite(25, entry, { ok: false });
  assert.equal(settled.reverted, true);
  assert.equal(settled.send, null);
  assert.deepEqual(settled.entry, { confirmed: true, desired: true, inFlight: false });
});

test("falha depois de mudança de ideia também volta ao confirmado (sem gravação órfã)", () => {
  let entry = toggleFavorite(25, initialFavoriteEntry(false)).entry; // true
  entry = toggleFavorite(25, entry).entry; // false (pendente)
  const settled = settleFavorite(25, entry, { ok: false });
  assert.deepEqual(settled.entry, { confirmed: false, desired: false, inFlight: false });
  assert.equal(settled.send, null);
});

test("idempotência: voltar ao estado confirmado sem gravação em andamento não envia nada", () => {
  const entry: FavoriteEntry = { confirmed: true, desired: false, inFlight: false };
  const step = toggleFavorite(25, entry);
  assert.deepEqual(step.entry, { confirmed: true, desired: true, inFlight: false });
  assert.equal(step.send, null);
});

// ---------------------------------------------------------------------------
// Erros e textos
// ---------------------------------------------------------------------------

test("códigos do banco viram motivos exibíveis, sem detalhe técnico", () => {
  assert.equal(favoriteFailureReason("28000"), "not_authenticated");
  assert.equal(favoriteFailureReason("42501"), "not_authenticated");
  assert.equal(favoriteFailureReason("22023"), "invalid");
  assert.equal(favoriteFailureReason("P0002"), "not_found");
  assert.equal(favoriteFailureReason("PGRST202"), "unavailable");
  assert.equal(favoriteFailureReason("XX000"), "failed");
  assert.equal(favoriteFailureReason(undefined), "failed");
});

test("textos: nome acessível constante (estado em aria-pressed), dica, anúncio e erro", () => {
  assert.equal(favoriteToggleLabel("Pikachu"), "Favoritar Pikachu");
  assert.equal(favoriteSpeciesNameFromLabel(favoriteToggleLabel("Mr. Mime")), "Mr. Mime");
  assert.equal(favoriteSpeciesNameFromLabel("Outra coisa"), null);
  assert.equal(favoriteSpeciesNameFromLabel(null), null);
  assert.equal(favoriteActionHint(false), "Adicionar aos favoritos");
  assert.equal(favoriteActionHint(true), "Remover dos favoritos");
  assert.equal(favoriteAnnouncement("Pikachu", true), "Pikachu adicionado aos favoritos.");
  assert.equal(favoriteAnnouncement("Pikachu", false), "Pikachu removido dos favoritos.");
  assert.match(favoriteErrorMessage("Pikachu", "failed"), /Nada foi alterado/);
  assert.match(favoriteErrorMessage("Pikachu", "not_authenticated"), /sessão expirou/);
  assert.match(favoriteErrorMessage("Pikachu", "unavailable"), /indisponíveis/);
  for (const reason of ["failed", "invalid", "not_found", "unavailable", "not_authenticated"] as const) {
    assert.doesNotMatch(favoriteErrorMessage("Pikachu", reason), /PGRST|SQL|P0002|28000|uuid/i);
  }
});

// ---------------------------------------------------------------------------
// Contexto com origem (rotas da galeria e da ficha)
// ---------------------------------------------------------------------------

test("origem: só 'favoritos' é aceita; o resto é Pokédex Nacional", () => {
  assert.equal(parseOriginParam("favoritos"), "favoritos");
  assert.equal(parseOriginParam(["favoritos", "x"]), "favoritos");
  for (const bad of [undefined, "", "Favoritos", "nacional", "favoritos/../x", ["x"]]) {
    assert.equal(parseOriginParam(bad as string | string[] | undefined), null);
  }
});

test("links da galeria ficam dentro da página de origem, com pesquisa/geração/tipos", () => {
  const fav = { query: "char", generation: 1, types: ["FIRE"], origin: "favoritos" as const };
  assert.equal(galleryBasePath(fav), "/pokedex/favoritos");
  assert.equal(pokedexHref(fav), "/pokedex/favoritos?q=char&geracao=1&tipo=FIRE");
  assert.equal(pokedexHref({ ...fav, origin: null }), "/pokedex?q=char&geracao=1&tipo=FIRE");
  assert.equal(pokedexHref({ query: null, generation: null, origin: "favoritos" }), "/pokedex/favoritos");
});

test("ficha a partir de Favoritos leva ?origem=favoritos; o voltar retorna a Favoritos com âncora", () => {
  const fav = { query: null, generation: 3, types: [], origin: "favoritos" as const };
  assert.equal(speciesDetailHref(25, fav), "/pokedex/25?geracao=3&origem=favoritos");
  assert.equal(speciesDetailHref(25, { query: null, generation: null, origin: "favoritos" }), "/pokedex/25?origem=favoritos");
  assert.equal(nationalPokedexHref(fav, 25), "/pokedex/favoritos?geracao=3#especie-0025");
  // Sem origem: comportamento anterior intacto (regressão P3b/P4a/P5a).
  assert.equal(speciesDetailHref(25, { query: "pika", generation: null }), "/pokedex/25?q=pika");
  assert.equal(nationalPokedexHref({ query: null, generation: null }, 25), "/pokedex#especie-0025");
});

const nav = (n: number, generation: number): NavigationSpecies => ({
  national_dex_number: n,
  species_name: `Sp${n}`,
  artwork_path: null,
  generation_ordinal: generation,
  generation_code: generation === 1 ? "GENERATION_I" : "GENERATION_II",
  region_name: generation === 1 ? "Kanto" : "Johto",
});

test("anterior/próximo seguem a regra da P4a também na origem Favoritos (sem restrição a favoritos) e mantêm a origem", () => {
  const context = { query: null, generation: 1, types: [], origin: "favoritos" as const };
  const result = resolveSpeciesNavigation({ current: { generation_ordinal: 1 }, previous: nav(150, 1), next: nav(152, 2), context });
  assert.equal(result.previous?.national_dex_number, 150);
  assert.equal(result.next, null);
  assert.equal(result.nextGeneration?.first.national_dex_number, 152);
  assert.equal(result.nextGeneration?.context.origin, "favoritos");
  assert.equal(speciesDetailHref(152, result.nextGeneration!.context), "/pokedex/152?geracao=2&origem=favoritos");
});

// ---------------------------------------------------------------------------
// Leitor agregado (get_my_pokedex_favorites)
// ---------------------------------------------------------------------------

type Page = { data: unknown[] | null; error: { code?: string; message?: string } | null };

function fakeClient(pages: Page[]) {
  const calls: Array<{ fn: string; args: unknown; from: number; to: number }> = [];
  let i = 0;
  const client = {
    rpc(fn: string, args?: unknown) {
      return {
        order() {
          return {
            range(from: number, to: number) {
              calls.push({ fn, args, from, to });
              return Promise.resolve(pages[i++] ?? { data: [], error: null });
            },
          };
        },
      };
    },
  };
  return { client: client as never, calls };
}

test("leitor: uma chamada sem parâmetros de identidade; pagina pelo teto de 1.000 (todas as 1.025 favoritas)", async () => {
  const first = Array.from({ length: 1000 }, (_, k) => ({ national_dex_number: k + 1 }));
  const second = Array.from({ length: 25 }, (_, k) => ({ national_dex_number: 1001 + k }));
  const { client, calls } = fakeClient([
    { data: first, error: null },
    { data: second, error: null },
  ]);
  const set = await getMyPokedexFavorites(client);
  assert.ok(set);
  assert.equal(set.size, 1025);
  assert.deepEqual(
    calls.map((c) => [c.fn, c.args, c.from, c.to]),
    [
      ["get_my_pokedex_favorites", undefined, 0, 999],
      ["get_my_pokedex_favorites", undefined, 1000, 1999],
    ],
  );
});

test("leitor: lista vazia = conjunto vazio (não erro); falha = null (indisponível)", async () => {
  const empty = await getMyPokedexFavorites(fakeClient([{ data: [], error: null }]).client);
  assert.ok(empty);
  assert.equal(empty.size, 0);

  const originalError = console.error;
  const originalWarn = console.warn;
  console.error = () => {};
  console.warn = () => {};
  try {
    assert.equal(await getMyPokedexFavorites(fakeClient([{ data: null, error: { code: "28000", message: "not_authenticated" } }]).client), null);
    assert.equal(await getMyPokedexFavorites(fakeClient([{ data: null, error: { code: "PGRST202", message: "missing" } }]).client), null);
    // Falha na segunda página: nada parcial chega à interface.
    const first = Array.from({ length: 1000 }, (_, k) => ({ national_dex_number: k + 1 }));
    assert.equal(
      await getMyPokedexFavorites(fakeClient([{ data: first, error: null }, { data: null, error: { code: "XX000" } }]).client),
      null,
    );
  } finally {
    console.error = originalError;
    console.warn = originalWarn;
  }
});

test("galeria contínua (UX-01): geração é filtro em memória, com contagens por geração", () => {
  // Favoritos de gerações diferentes, já na ordem nacional (como vêm de 6131).
  const favorites = [
    { national_dex_number: 1, generation_ordinal: 1 },
    { national_dex_number: 25, generation_ordinal: 1 },
    { national_dex_number: 152, generation_ordinal: 2 },
    { national_dex_number: 448, generation_ordinal: 4 },
    { national_dex_number: 1025, generation_ordinal: 9 },
  ];
  // Sem geração: a lista inteira, na mesma ordem, sem agrupamento.
  assert.deepEqual(
    filterByGeneration(favorites, null).map((item) => item.national_dex_number),
    [1, 25, 152, 448, 1025],
  );
  // Com geração: só ela, ordem preservada; geração sem favoritos = lista vazia.
  assert.deepEqual(
    filterByGeneration(favorites, 1).map((item) => item.national_dex_number),
    [1, 25],
  );
  assert.deepEqual(filterByGeneration(favorites, 3), []);
  // Não muta a entrada.
  assert.equal(favorites.length, 5);

  const counts = countByGeneration(favorites);
  assert.deepEqual([...counts], [[1, 2], [2, 1], [4, 1], [9, 1]]);
  assert.equal(counts.get(3), undefined);
  assert.equal(countByGeneration([]).size, 0);
});
