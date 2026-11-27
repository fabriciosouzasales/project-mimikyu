// V1-13 · E3-7a — acabamento sem SQL: histórico da Pokédex do titular, toque de 44 px no painel do
// titular, caminho de entrada na sessão expirada e filtro contextual "Pokémon nos bolsos".
// Executar: node --experimental-strip-types --test lib/colecoes/e3-7a-polish.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { ACTIVITY_FILTERS, SIGN_IN_PATH, historyFilters } from "./binder-activity.ts";
import { SHARED_ACTIVITY_FILTERS } from "./shared-binder-activity.ts";

const WEB = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const read = (f: string) => readFileSync(join(WEB, f), "utf8");

test("filtro contextual: 'Pokémon nos bolsos' só com referências de espécie; demais filtros e 'Todas' intactos", () => {
  const off = historyFilters(ACTIVITY_FILTERS, false).map((f) => f.key);
  const on = historyFilters(ACTIVITY_FILTERS, true).map((f) => f.key);
  assert.deepEqual(off, ["ALL", "CARDS", "RESERVATIONS", "LOCKS", "PAGES", "CATALOG", "BINDER"]);
  assert.deepEqual(on, [...off, "SPECIES"]);
  assert.deepEqual(historyFilters(SHARED_ACTIVITY_FILTERS, false).map((f) => f.key), ["ALL", "CARDS", "RESERVATIONS", "LOCKS", "PAGES", "CATALOG"]);
  assert.deepEqual(historyFilters(SHARED_ACTIVITY_FILTERS, true).map((f) => f.key), ["ALL", "CARDS", "RESERVATIONS", "LOCKS", "PAGES", "CATALOG", "SPECIES"]);
  // Nada muda nas listas originais (a leitura e a validação no servidor continuam aceitando SPECIES).
  assert.ok(ACTIVITY_FILTERS.some((f) => f.key === "SPECIES"));
  // Decidido pelo que a tela já sabe: titular pelo controle de espécies do fichário; participante pela modalidade.
  assert.match(read("components/colecoes/fichario/binder-control.tsx"), /speciesEnabled=\{species !== null\}/);
  assert.match(read("components/colecoes/sharing/shared-collection-activity.tsx"), /sharedActivitySource\(collectionId, pokedex\)/);
  assert.match(read("components/colecoes/fichario/binder-history.tsx"), /speciesEnabled = false/);
});

test("sessão expirada: caminho fixo /login, sem parâmetros, no painel e nos três históricos", () => {
  assert.equal(SIGN_IN_PATH, "/login");
  assert.doesNotMatch(SIGN_IN_PATH, /[?#&=]/);
  const history = read("components/colecoes/fichario/binder-history.tsx");
  assert.match(history, /<Link href=\{SIGN_IN_PATH\}/);
  assert.match(history, /signIn: result\.reason === "not_authenticated"/, "histórico do fichário do titular");
  const shared = read("components/colecoes/sharing/shared-collection-activity.tsx");
  assert.equal(shared.match(/signIn: r\.reason === "not_authenticated"/g)?.length, 2, "fichário do participante e Pokédex");
  const panel = read("components/colecoes/sharing/shared-pokedex-editor-panel.tsx");
  assert.match(panel, /<Link href=\{SIGN_IN_PATH\}>Entrar de novo<\/Link>/);
  for (const src of [history, shared, panel]) {
    assert.doesNotMatch(src, /href=\{`\$\{SIGN_IN_PATH\}|SIGN_IN_PATH \+|\/login\?/, "nenhum retorno, token ou id na URL");
  }
  // O fluxo de autenticação não foi tocado.
  assert.doesNotMatch(read("app/(auth)/actions.ts"), /E3-7a|SIGN_IN_PATH/);
});

test("histórico da Pokédex do titular: mesma leitura (5395), mesmos rótulos e autoria, atrás da configuração D-E3-1", () => {
  const owner = read("components/colecoes/colecoes/pokedex-collection-view.tsx");
  assert.match(owner, /editorCurationFlagOn\(process\.env\) \? \(\s*<SharedCollectionActivityButton/);
  assert.match(owner, /binder=\{false\}\s*pokedex\s*label="Atividade da Pokédex"/);
  const ui = read("components/colecoes/sharing/shared-collection-activity.tsx");
  assert.match(ui, /import \{ readCollectionActivity \} from "@\/app\/colecoes\/collection-activity-actions";/);
  // Uma única action para titular e participante; a antiga (sob compartilhada) foi movida, não duplicada.
  const action = read("app/colecoes/collection-activity-actions.ts");
  assert.match(action, /supabase\.rpc\(COLLECTION_ACTIVITY_RPC/);
  assert.doesNotMatch(action, /service_role|user_profile|auth\.users|owner_user_id/, "sem privilégio nem enriquecimento do autor");
  assert.ok(!readdirSync(join(WEB, "app/colecoes/compartilhada/[id]")).includes("collection-activity-actions.ts"));
  // Interpretação dos eventos não duplicada: só collection-activity.ts conhece os tipos da Pokédex.
  for (const f of ["components/colecoes/colecoes/pokedex-collection-view.tsx", "components/colecoes/sharing/shared-collection-activity.tsx", "app/colecoes/collection-activity-actions.ts"]) {
    assert.doesNotMatch(read(f), /POKEDEX_POSITION_|POKEDEX_REPRESENTATIVE_/, f);
  }
});

test("toque: painel do titular com 44 px nas ações por exemplar, confirmações e controles da posição", () => {
  const css = read("components/colecoes/colecoes/pokedex.module.css");
  assert.match(css, /\.copyAction \{\s*min-height: 2\.75rem;/);
  assert.match(css, /\.confirmActions > button \{\s*min-height: 2\.75rem;/);
  const owner = read("components/colecoes/colecoes/pokedex-position-panel.tsx");
  assert.doesNotMatch(owner, /className="h-9 gap-1\.5"/);
  assert.match(owner, /className="h-11 gap-1\.5"/, "Adicionar / Usar nesta posição");
  assert.match(owner, /variant="ghost" size="sm" className="min-h-11" onClick=\{onLoadMore\}/);
  assert.match(owner, /variant="outline" className="min-h-11" onClick=\{onClose\}/);
  assert.match(owner, /inline-flex min-h-11 items-center/, "link da Pokédex");
  // As classes alteradas só existem nos dois painéis de posição.
  for (const f of readdirSync(join(WEB, "components/colecoes/colecoes")).filter((n) => n.endsWith(".tsx"))) {
    const src = read(`components/colecoes/colecoes/${f}`);
    // Só importa quem usa a folha da Pokédex (outros módulos têm classes homônimas próprias).
    if (/from "\.\/pokedex\.module\.css"/.test(src) && /\.(copyAction|confirmActions)\b/.test(src)) assert.equal(f, "pokedex-position-panel.tsx", f);
  }
  // Comportamento preservado: as escritas do titular continuam as mesmas.
  for (const fn of ["removePokedexLink", "setPokedexRepresentative", "unlinkCopyFromCollection", "linkPokedexCopy"]) assert.match(owner, new RegExp(fn));
});

test("contratos SQL e painel colaborativo sem mudança de lógica", () => {
  for (const f of ["app/colecoes/collection-activity-actions.ts", "app/colecoes/compartilhada/[id]/pokedex-editor-actions.ts"]) {
    assert.doesNotMatch(read(f), /get_shared_binder_placeable_cards|editor_place_card_in_binder|editor_preview_binder_auto_arrange/, f);
  }
  const panel = read("components/colecoes/sharing/shared-pokedex-editor-panel.tsx");
  assert.equal(panel.match(/writeEditorPokedex\(/g)?.length, 1);
  assert.match(panel, /planAfter\(outcome\)/);
});
