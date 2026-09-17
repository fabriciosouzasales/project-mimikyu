// Contrato de contadores da revisão editorial de variantes.
//
// Criado em 2026-09-16 (SV5-DEFERRED-UI-SEMANTICS-01). O contrato existia
// desde o incidente JUMBO, mas sem teste: a regressão que motivou este
// arquivo — linha DEFERIDA (decision_status = SKIPPED) contada como pendência
// de mapeamento — passou despercebida porque nada afirmava o oposto.
//
// Caso real que o arquivo protege: job SV5 601f7c96 fechou COMPLETED com 416
// APPROVED/INSERTED + 12 SKIPPED/UNCHANGED, zero PENDING, zero FAILED. A tela
// mostrava "Concluído com pendências", "11 sem mapeamento" e um botão
// "Resolver mapeamentos pendentes" — três afirmações falsas sobre um job que
// tinha sido fechado corretamente.
//
// Executar: node --experimental-strip-types --test lib/catalogo/variant-size-scope.test.ts
// (a partir de web/, sem instalar nada — `node:test`/`node:assert` nativos,
// mesmo padrão de lib/pricing/pricing-batch-client.test.ts; nenhum framework
// novo é introduzido.)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  VARIANT_REVIEW_REASON_UNSUPPORTED_SIZE,
  VARIANT_SKIP_REASON_SIZE_OUT_OF_SCOPE,
  classifyVariantRowScope,
  deriveVariantImportScopeCounters,
  isVariantRowDeferred,
  isVariantRowMappingPending,
  type VariantRowScopeInput,
} from "./variant-size-scope.ts";

/** Linha IN_SCOPE sem mapeamento, ainda sem decisão. */
function pendingUnmapped(): VariantRowScopeInput {
  return {
    validationStatus: "NEEDS_REVIEW",
    decisionStatus: "PENDING",
    matchStatus: "NEW",
    skipReason: null,
    reviewReason: null,
  };
}

/** Mesma linha, mas DEFERIDA pelo administrador (variante NOVA que ele pulou). */
function deferredUnmapped(): VariantRowScopeInput {
  return {
    validationStatus: "NEEDS_REVIEW",
    decisionStatus: "SKIPPED",
    matchStatus: "NEW",
    skipReason: null,
    reviewReason: null,
  };
}

/**
 * Variante que JÁ EXISTE no catálogo: o importador marca MATCHED e pula
 * AUTOMATICAMENTE (SKIPPED). Não é deferimento — ninguém decidiu nada.
 */
function matchedSkipped(): VariantRowScopeInput {
  return {
    validationStatus: "VALID",
    decisionStatus: "SKIPPED",
    matchStatus: "MATCHED",
    skipReason: null,
    reviewReason: null,
  };
}

/** Linha válida e aprovada — não é pendência de nada. */
function approvedValid(): VariantRowScopeInput {
  return {
    validationStatus: "VALID",
    decisionStatus: "APPROVED",
    matchStatus: "NEW",
    skipReason: null,
    reviewReason: null,
  };
}

/** Linha válida, nova, ainda sem decisão — pronta para APPROVED. */
function pendingValidNew(): VariantRowScopeInput {
  return {
    validationStatus: "VALID",
    decisionStatus: "PENDING",
    matchStatus: "NEW",
    skipReason: null,
    reviewReason: null,
  };
}

/** JUMBO: decisão AUTOMÁTICA do sistema (INVALID + SKIPPED). */
function outOfScope(): VariantRowScopeInput {
  return {
    validationStatus: "INVALID",
    decisionStatus: "SKIPPED",
    matchStatus: "NEW",
    skipReason: VARIANT_SKIP_REASON_SIZE_OUT_OF_SCOPE,
    reviewReason: null,
  };
}

/** `size` desconhecido, ainda sem decisão humana. */
function pendingUnsupportedSize(): VariantRowScopeInput {
  return {
    validationStatus: "NEEDS_REVIEW",
    decisionStatus: "PENDING",
    matchStatus: "NEW",
    skipReason: null,
    reviewReason: VARIANT_REVIEW_REASON_UNSUPPORTED_SIZE,
  };
}

// ---------------------------------------------------------------------------
// REGRA 1 — pendência de mapeamento exige NEEDS_REVIEW + PENDING + IN_SCOPE
// ---------------------------------------------------------------------------

test("pendência de mapeamento: NEEDS_REVIEW + PENDING + IN_SCOPE", () => {
  assert.equal(isVariantRowMappingPending(pendingUnmapped()), true);
});

test("REGRESSÃO SV5: linha DEFERIDA (SKIPPED) não é pendência de mapeamento", () => {
  // O bug: esta linha continuava contando como "sem mapeamento" mesmo depois
  // de o administrador ter decidido — conscientemente — não catalogá-la.
  assert.equal(isVariantRowMappingPending(deferredUnmapped()), false);
});

test("linha REJECTED sem mapeamento também não é pendência", () => {
  const row: VariantRowScopeInput = {
    validationStatus: "NEEDS_REVIEW",
    decisionStatus: "REJECTED",
    matchStatus: "NEW",
    skipReason: null,
    reviewReason: null,
  };
  assert.equal(isVariantRowMappingPending(row), false);
});

test("tamanho desconhecido nunca é pendência de MAPEAMENTO, mesmo PENDING", () => {
  assert.equal(isVariantRowMappingPending(pendingUnsupportedSize()), false);
  assert.equal(classifyVariantRowScope(pendingUnsupportedSize()), "UNSUPPORTED_SIZE");
});

// ---------------------------------------------------------------------------
// REGRA 4 — DEFERIDA é SKIPPED humano; JUMBO mantém contador próprio
// ---------------------------------------------------------------------------

test("deferida: SKIPPED fora do eixo de tamanho", () => {
  assert.equal(isVariantRowDeferred(deferredUnmapped()), true);
});

test("JUMBO chega SKIPPED mas NÃO é deferida — é decisão do sistema", () => {
  assert.equal(isVariantRowDeferred(outOfScope()), false);
  assert.equal(classifyVariantRowScope(outOfScope()), "OUT_OF_SCOPE");
});

test("PENDING não é deferida", () => {
  assert.equal(isVariantRowDeferred(pendingUnmapped()), false);
});

test("REGRESSÃO SEMANTICS-02: MATCHED + SKIPPED NÃO é deferida", () => {
  // O bug: o importador pula automaticamente toda variante que já existe
  // (MATCHED). A primeira versão do predicado só excluía JUMBO, e um job com
  // 414 linhas MATCHED/SKIPPED apareceu como "414 deferidas".
  assert.equal(isVariantRowDeferred(matchedSkipped()), false);
});

test("MATCHED + SKIPPED também não é pendência de mapeamento", () => {
  assert.equal(isVariantRowMappingPending(matchedSkipped()), false);
});

// ---------------------------------------------------------------------------
// REGRA 2 — tamanho desconhecido só é pendência enquanto PENDING
// ---------------------------------------------------------------------------

test("tamanho desconhecido DEFERIDO sai de pendências e entra em deferidas", () => {
  const skipped: VariantRowScopeInput = { ...pendingUnsupportedSize(), decisionStatus: "SKIPPED" };
  const c = deriveVariantImportScopeCounters([skipped]);
  assert.deepEqual(c, { mappingPendingRows: 0, unsupportedSizeRows: 0, outOfScopeRows: 0, deferredRows: 1 });
});

// ---------------------------------------------------------------------------
// CONTADORES — casos consolidados
// ---------------------------------------------------------------------------

test("contadores: as quatro naturezas convivem sem se misturar", () => {
  const c = deriveVariantImportScopeCounters([
    approvedValid(),
    pendingUnmapped(),
    pendingUnmapped(),
    deferredUnmapped(),
    pendingUnsupportedSize(),
    outOfScope(),
  ]);
  assert.deepEqual(c, {
    mappingPendingRows: 2,
    unsupportedSizeRows: 1,
    outOfScopeRows: 1,
    deferredRows: 1,
  });
});

test("CENÁRIO SV5 REAL: 416 aprovadas + 12 deferidas ⇒ zero pendência", () => {
  const rows: VariantRowScopeInput[] = [
    ...Array.from({ length: 416 }, approvedValid),
    ...Array.from({ length: 12 }, deferredUnmapped),
  ];
  const c = deriveVariantImportScopeCounters(rows);

  // O painel declara sucesso quando mappingPending + unsupportedSize === 0.
  assert.equal(c.mappingPendingRows, 0, "nenhuma pendência de mapeamento");
  assert.equal(c.unsupportedSizeRows, 0, "nenhuma pendência de escopo");
  assert.equal(c.deferredRows, 12, "as 12 deferidas continuam visíveis");
  assert.equal(c.outOfScopeRows, 0, "SV5 não tem JUMBO");
  assert.equal(rows.length, 428, "total do job preservado");

  // E o botão "Resolver mapeamentos pendentes" depende de mappingPendingRows.
  assert.equal(c.mappingPendingRows > 0, false, "o botão não deve ser renderizado");
});

test("CENÁRIO SV5 JOB NOVO (SEMANTICS-02): 414 MATCHED/SKIPPED não são deferidas", () => {
  // Job real de 432 linhas que revelou a regressão:
  //   414 VALID / MATCHED / SKIPPED          (já existentes — decisão do importador)
  //    11 NEEDS_REVIEW / NEW / PENDING       (pendência de mapeamento real)
  //     6 INVALID / NEW / SKIPPED / JUMBO    (fora de escopo)
  //     1 VALID / NEW / PENDING              (pronta para aprovar)
  const rows: VariantRowScopeInput[] = [
    ...Array.from({ length: 414 }, matchedSkipped),
    ...Array.from({ length: 11 }, pendingUnmapped),
    ...Array.from({ length: 6 }, outOfScope),
    pendingValidNew(),
  ];
  assert.equal(rows.length, 432, "total do job");

  const c = deriveVariantImportScopeCounters(rows);
  assert.equal(c.deferredRows, 0, "NENHUMA deferida — era o bug (mostrava 414)");
  assert.equal(c.mappingPendingRows, 11, "as 11 pendências reais permanecem");
  assert.equal(c.outOfScopeRows, 6, "os 6 JUMBO no contador próprio");
  assert.equal(c.unsupportedSizeRows, 0);

  // "Pendentes" da tabela de revisão: PENDING, excluindo as travadas (JUMBO).
  const pendentes = rows.filter(
    (r) => classifyVariantRowScope(r) !== "OUT_OF_SCOPE" && r.decisionStatus === "PENDING",
  ).length;
  assert.equal(pendentes, 12, "11 sem mapeamento + 1 VALID pronta para aprovar");

  // E as 414 MATCHED/SKIPPED não caem em NENHUMA das quatro categorias.
  const semCategoria = rows.filter(
    (r) =>
      classifyVariantRowScope(r) !== "OUT_OF_SCOPE" &&
      !isVariantRowDeferred(r) &&
      r.decisionStatus !== "PENDING" &&
      r.decisionStatus !== "APPROVED" &&
      r.decisionStatus !== "REJECTED",
  ).length;
  assert.equal(semCategoria, 414, "já existentes: visíveis só em 'Analisadas'");
});

test("job sem nada decidido continua acusando pendência (não mascarar)", () => {
  // Guard contra a correção exagerar: um job STAGED com 11 linhas sem
  // mapeamento e sem decisão DEVE continuar mostrando 11 pendências.
  const c = deriveVariantImportScopeCounters(Array.from({ length: 11 }, pendingUnmapped));
  assert.equal(c.mappingPendingRows, 11);
  assert.equal(c.deferredRows, 0);
});

test("coleção vazia zera os quatro contadores", () => {
  assert.deepEqual(deriveVariantImportScopeCounters([]), {
    mappingPendingRows: 0,
    unsupportedSizeRows: 0,
    outOfScopeRows: 0,
    deferredRows: 0,
  });
});
