// WHERE-05A — organizar os exemplares de uma coleção no local padrão (regras puras).
// Executar: node --experimental-strip-types --test lib/colecoes/collection-organize.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  type OrganizePlan,
  PLAN_TOKEN,
  autoProposalKind,
  classifyOrganizeFailure,
  confirmationSentence,
  defaultMode,
  eligibleFor,
  laterActionLabel,
  leavingOtherPlaces,
  leavingSentence,
  limitNotice,
  modeOptions,
  organizeFailureMessage,
  parseOrganizePlan,
  planFailureMessage,
  planVerdict,
  proposalSubtitle,
  proposalTitle,
  reconcileMode,
  recoveryFor,
  resultSentence,
  verdictMessage,
} from "./collection-organize.ts";

const C = "3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b";
const S = "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d";
const TOKEN = "v1:0123456789abcdef0123456789abcdef";

/** Linha da 5221 como o PostgREST devolve. */
function row(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    collection_id: C,
    storage_container_id: S,
    collection_active: true,
    target_is_default: true,
    total_count: 6,
    unlocated_count: 2,
    at_target_count: 2,
    elsewhere_count: 2,
    eligible_unlocated: 2,
    eligible_all: 4,
    max_per_operation: 10000,
    plan_token: TOKEN,
    ...overrides,
  };
}

function plan(overrides: Record<string, unknown> = {}): OrganizePlan {
  const parsed = parseOrganizePlan(row(overrides));
  assert.ok(parsed, "fixture válida");
  return parsed;
}

test("5221: converte a linha real do contrato (12 colunas)", () => {
  const p = plan();
  assert.deepEqual(p, {
    collectionId: C,
    storageContainerId: S,
    collectionActive: true,
    targetIsDefault: true,
    totalCount: 6,
    unlocatedCount: 2,
    atTargetCount: 2,
    elsewhereCount: 2,
    eligibleUnlocated: 2,
    eligibleAll: 4,
    maxPerOperation: 10000,
    planToken: TOKEN,
  });
  assert.ok(PLAN_TOKEN.test(TOKEN));
});

test("5221: formato inesperado → null (nunca adivinha números)", () => {
  assert.equal(parseOrganizePlan(null), null);
  assert.equal(parseOrganizePlan([]), null);
  assert.equal(parseOrganizePlan(row({ total_count: null })), null);
  assert.equal(parseOrganizePlan(row({ eligible_all: -1 })), null);
  assert.equal(parseOrganizePlan(row({ eligible_all: 1.5 })), null);
  assert.equal(parseOrganizePlan(row({ plan_token: "abc" })), null);
  assert.equal(parseOrganizePlan(row({ plan_token: "v1:XYZ" })), null);
  assert.equal(parseOrganizePlan(row({ collection_active: "true" })), null);
  assert.equal(parseOrganizePlan(row({ target_is_default: undefined })), null);
});

test("situações: precedência archived > not_default > too_large > empty > all_at_target > ready", () => {
  assert.equal(planVerdict(plan()), "ready");
  assert.equal(planVerdict(plan({ collection_active: false, target_is_default: false })), "archived");
  assert.equal(planVerdict(plan({ target_is_default: false, total_count: 20000 })), "not_default");
  assert.equal(planVerdict(plan({ total_count: 10001, eligible_all: 1, eligible_unlocated: 1 })), "too_large");
  assert.equal(planVerdict(plan({ total_count: 10000 })), "ready", "teto é inclusivo (D6 recusa só acima)");
  assert.equal(
    planVerdict(plan({ total_count: 0, unlocated_count: 0, at_target_count: 0, elsewhere_count: 0, eligible_unlocated: 0, eligible_all: 0 })),
    "empty",
  );
  assert.equal(
    planVerdict(plan({ total_count: 6, unlocated_count: 0, at_target_count: 6, elsewhere_count: 0, eligible_unlocated: 0, eligible_all: 0 })),
    "all_at_target",
  );
});

test("proposta automática só quando pertinente (após salvar o padrão)", () => {
  assert.equal(autoProposalKind(plan()), "propose");
  assert.equal(autoProposalKind(plan({ total_count: 0, eligible_unlocated: 0, eligible_all: 0 })), "none", "coleção vazia");
  assert.equal(autoProposalKind(plan({ eligible_unlocated: 0, eligible_all: 0 })), "none", "tudo no destino");
  assert.equal(autoProposalKind(plan({ collection_active: false })), "none", "arquivada");
  assert.equal(autoProposalKind(plan({ target_is_default: false })), "none", "destino não é mais o padrão");
  assert.equal(autoProposalKind(plan({ total_count: 12000 })), "limit_notice", "D6: aviso, nunca a proposta");
});

test("UNLOCATED preserva exemplares em outros locais; ALL retira e avisa", () => {
  const p = plan();
  assert.equal(eligibleFor(p, "UNLOCATED"), 2);
  assert.equal(eligibleFor(p, "ALL"), 4);
  assert.equal(leavingOtherPlaces(p, "UNLOCATED"), 0, "UNLOCATED nunca retira de outro local");
  assert.equal(leavingOtherPlaces(p, "ALL"), 2);
  assert.equal(leavingSentence(leavingOtherPlaces(p, "UNLOCATED")), null);
  assert.equal(leavingSentence(2), "Destes, 2 serão retirados de outros locais físicos.");
  assert.equal(leavingSentence(1), "Destes, 1 será retirado de outro local físico.");
  assert.equal(leavingSentence(1200), "Destes, 1.200 serão retirados de outros locais físicos.");
});

test("modalidade padrão é a conservadora; ALL nunca substitui em silêncio", () => {
  assert.equal(defaultMode(plan()), "UNLOCATED");
  const noneUnlocated = plan({ unlocated_count: 0, eligible_unlocated: 0, at_target_count: 4, eligible_all: 2 });
  assert.equal(defaultMode(noneUnlocated), null, "sem exemplares sem local: nenhuma pré-seleção");
  const [unloc, all] = modeOptions(noneUnlocated);
  assert.ok(unloc && all);
  assert.equal(unloc.mode, "UNLOCATED");
  assert.equal(unloc.available, false);
  assert.equal(unloc.unavailableReason, "Todos os exemplares desta coleção já têm um local definido.");
  assert.equal(all.mode, "ALL");
  assert.equal(all.available, true);
  assert.equal(all.count, 2);
});

test("nova prévia mantém a escolha se ainda fizer sentido", () => {
  assert.equal(reconcileMode(plan(), "ALL"), "ALL");
  assert.equal(reconcileMode(plan(), null), "UNLOCATED");
  // A escolha anterior era UNLOCATED, mas não sobrou nenhum sem local: não troca para ALL sozinho.
  assert.equal(reconcileMode(plan({ eligible_unlocated: 0, unlocated_count: 0 }), "UNLOCATED"), null);
  assert.equal(reconcileMode(plan({ eligible_all: 0, eligible_unlocated: 0 }), "ALL"), null);
});

test("títulos contextuais pelo tipo do local", () => {
  assert.equal(proposalTitle("BINDER"), "Organizar cartas neste fichário?");
  assert.equal(proposalTitle("BOX"), "Organizar cartas nesta caixa?");
  assert.equal(proposalTitle("FOLDER"), "Organizar cartas nesta pasta?");
  assert.equal(proposalTitle("CASE"), "Organizar cartas nesta maleta?");
  assert.equal(proposalTitle("OTHER"), "Organizar cartas neste local?");
  assert.equal(proposalTitle(null), "Organizar cartas neste local?");
  assert.equal(laterActionLabel("BINDER"), "Organizar cartas neste fichário");
  assert.equal(laterActionLabel(undefined), "Organizar cartas neste local");
});

test("subtítulo só fala em atualização quando houve salvamento", () => {
  assert.equal(proposalSubtitle("after_save"), "O local padrão da coleção foi atualizado.");
  assert.ok(!proposalSubtitle("later").includes("atualizado"));
});

test("confirmação e resultado com números exatos", () => {
  assert.equal(
    confirmationSentence(42, "F001 — Fichário ME5.5"),
    "Você está prestes a organizar 42 exemplares em F001 — Fichário ME5.5.",
  );
  assert.equal(confirmationSentence(1, "Caixa"), "Você está prestes a organizar 1 exemplar em Caixa.");
  assert.equal(resultSentence(42, "Fichário"), "42 exemplares agora estão guardados em Fichário.");
  assert.equal(resultSentence(1, "Fichário"), "1 exemplar agora está guardado em Fichário.");
  assert.match(resultSentence(0, "Fichário"), /Nenhum exemplar precisou mudar/);
});

test("estados especiais: mensagens de colecionador", () => {
  const p = plan();
  assert.equal(verdictMessage("empty", p), "Nenhuma carta vinculada a esta coleção.");
  assert.equal(verdictMessage("all_at_target", p), "Todas as cartas desta coleção já estão neste local.");
  assert.match(verdictMessage("archived", p), /arquivada/);
  assert.match(verdictMessage("not_default", p), /não é mais o padrão/);
  assert.equal(verdictMessage("too_large", p), limitNotice(10000));
  assert.match(limitNotice(10000), /mais de 10\.000 exemplares/);
});

test("erros contratuais da 5221/5222 → classe", () => {
  assert.equal(classifyOrganizeFailure("P0001", "PLAN_CHANGED"), "plan_changed");
  assert.equal(classifyOrganizeFailure("P0001", "DEFAULT_CHANGED"), "default_changed");
  assert.equal(classifyOrganizeFailure("55P03", "LOCK_BUSY"), "lock_busy");
  assert.equal(classifyOrganizeFailure("55P03", "canceling statement due to lock timeout"), "lock_busy");
  assert.equal(classifyOrganizeFailure("54000", "COLLECTION_TOO_LARGE"), "too_large");
  assert.equal(classifyOrganizeFailure("55000", "COLLECTION_ARCHIVED"), "archived");
  assert.equal(classifyOrganizeFailure("P0002", "COLLECTION_NOT_FOUND"), "not_found");
  assert.equal(classifyOrganizeFailure("P0002", "STORAGE_NOT_FOUND"), "not_found");
  assert.equal(classifyOrganizeFailure("28000", "not_authenticated"), "not_authenticated");
  assert.equal(classifyOrganizeFailure("22023", "INVALID_MODE"), "invalid");
  assert.equal(classifyOrganizeFailure("22023", "INVALID_ARGUMENT"), "invalid");
  assert.equal(classifyOrganizeFailure("57014", "canceling statement due to statement timeout"), "unknown");
  assert.equal(classifyOrganizeFailure(undefined, undefined), "unknown");
});

test("recuperação: nunca repete a escrita sozinha", () => {
  assert.equal(recoveryFor("plan_changed"), "refresh_plan");
  assert.equal(recoveryFor("unknown"), "refresh_plan", "resultado desconhecido: reconsulta antes de qualquer nova confirmação");
  assert.equal(recoveryFor("too_large"), "refresh_plan");
  assert.equal(recoveryFor("archived"), "refresh_plan");
  assert.equal(recoveryFor("default_changed"), "reload_destination");
  assert.equal(recoveryFor("lock_busy"), "retry_allowed");
  assert.equal(recoveryFor("not_found"), "stop");
  assert.equal(recoveryFor("invalid"), "stop");
});

test("mensagens não declaram sucesso nem expõem texto técnico", () => {
  for (const reason of ["plan_changed", "default_changed", "lock_busy", "too_large", "archived", "not_found", "invalid"] as const) {
    const text = organizeFailureMessage(reason);
    assert.match(text, /Nada foi movido/, reason);
    assert.doesNotMatch(text, /PLAN_CHANGED|LOCK_BUSY|55P03|token|5222/i, reason);
  }
  assert.doesNotMatch(organizeFailureMessage("unknown"), /Nada foi movido|concluída com sucesso/);
  assert.match(planFailureMessage("unavailable" as never, "after_save"), /^O local padrão foi salvo\./);
  assert.match(planFailureMessage("unknown", "later"), /Nenhuma carta foi movida/);
  assert.doesNotMatch(planFailureMessage("unknown", "later"), /foi salvo/);
});
