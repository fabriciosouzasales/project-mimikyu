// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-matching/pricing-justtcg-matching.test.ts
// Bateria de testes offline do núcleo compartilhado de matching JustTCG — Incremento P16.2
// (Núcleo Compartilhado de Matching, 2026-08-25).
//
// 100% offline, zero dependência de rede/Supabase/CLI — mesma disciplina de
// set-refresh-core.test.ts (runXTests()/Deno.test guardado por `typeof Deno !== "undefined"`,
// para permanecer importável a partir de Node no sandbox de validação).
//
// Cenários portados byte a byte (mesmos dados/expectativas) da suíte runFixtureCheck() do
// CLI scripts/sync-justtcg-pricing.ts (P14.2/P14.2.1/P14.4.1/P14.4.3/P14.4.4/fix/fix v2/
// P14.4.5) — nenhum resultado esperado foi inventado ou alterado nesta extração. Cobre, no
// mínimo, os quatro grupos exigidos por Fabrício no pedido de P16.2: (1) correspondência de
// Set — candidato seguro/ambíguo/não encontrado/já confirmado; (2) correspondência de carta —
// seguro/ambiguidade/ausência/variantes relevantes (nome divergente, dedup por
// external_card_id, filtro por denominador); (3) decisão de upsert de mapeamento — reutiliza/
// cria/nunca sobrescreve indevidamente uma confirmação; (4) normalização de release_date na
// fronteira JustTCG (pré-requisito direto de resolveSetMatchV2).

import type { JustTcgSet } from "../pricing-justtcg/mod.ts";
import {
  buildExternalNumberIndex,
  classifyCardMatch,
  classifySetForExpansionPlan,
  decideMappingUpsert,
  type LocalCard,
  normalizeExternalSetReleaseDate,
  normalizeJustTcgSets,
  resolveSetMatchV2,
} from "./mod.ts";

export interface TestSuiteResult {
  assertions: Array<[string, boolean]>;
  failedCount: number;
}

export async function runPricingJusttcgMatchingTests(): Promise<TestSuiteResult> {
  const assertions: Array<[string, boolean]> = [];
  const assert = (label: string, cond: boolean) => assertions.push([label, cond]);

  // ==========================================================================
  // Grupo 1 — resolveSetMatchV2(): release_date exato, nunca nome (P14.2)
  // ==========================================================================
  {
    const allSets: JustTcgSet[] = [
      { id: "base-set-2-pokemon", name: "Base Set 2", release_date: "2000-02-24" },
      { id: "outro-set", name: "Outro Set", release_date: "2020-01-01" },
    ];
    const match = resolveSetMatchV2({ codigoMmkyu: "BASE4", releaseDateIso: "2000-02-24" }, allSets);
    assert("resolveSetMatchV2: release_date única -> CONFIRMED", match.status === "CONFIRMED" && match.set.id === "base-set-2-pokemon");
  }
  {
    const allSets: JustTcgSet[] = [{ id: "outro-set", name: "Outro Set", release_date: "2020-01-01" }];
    const match = resolveSetMatchV2({ codigoMmkyu: "BASE4", releaseDateIso: "2000-02-24" }, allSets);
    assert("resolveSetMatchV2: zero candidatos -> NOT_FOUND", match.status === "NOT_FOUND");
  }
  {
    const allSets: JustTcgSet[] = [
      { id: "set-a", name: "Set A", release_date: "2000-02-24" },
      { id: "set-b", name: "Set B", release_date: "2000-02-24" },
    ];
    const match = resolveSetMatchV2({ codigoMmkyu: "BASE4", releaseDateIso: "2000-02-24" }, allSets);
    assert("resolveSetMatchV2: mais de um candidato com a mesma data -> AMBIGUOUS, nunca auto-confirmado", match.status === "AMBIGUOUS");
  }
  {
    const allSets: JustTcgSet[] = [{ id: "override-set", name: "Override", release_date: "1999-01-01" }];
    const match = resolveSetMatchV2({ codigoMmkyu: "BASEP", releaseDateIso: "2000-02-24", overrideExternalSetId: "override-set" }, allSets);
    assert("resolveSetMatchV2: overrideExternalSetId presente e encontrado -> CONFIRMED via OVERRIDE_MANUAL", match.status === "CONFIRMED" && match.method === "OVERRIDE_MANUAL");
  }
  {
    const allSets: JustTcgSet[] = [{ id: "outro", name: "Outro", release_date: "1999-01-01" }];
    const match = resolveSetMatchV2({ codigoMmkyu: "BASEP", releaseDateIso: "2000-02-24", overrideExternalSetId: "inexistente" }, allSets);
    assert("resolveSetMatchV2: overrideExternalSetId não encontrado na resposta atual -> NOT_FOUND", match.status === "NOT_FOUND");
  }

  // --- Fix P14.2.1: normalização de release_date na fronteira JustTCG (pré-requisito
  // direto de resolveSetMatchV2) ------------------------------------------------------
  {
    assert("normalizeExternalSetReleaseDate: data pura passa intacta", normalizeExternalSetReleaseDate("2000-02-24") === "2000-02-24");
    assert(
      "normalizeExternalSetReleaseDate: datetime ISO completo (formato real da API) -> extrai só a data",
      normalizeExternalSetReleaseDate("2000-02-24T00:00:00.000Z") === "2000-02-24",
    );
    assert(
      "normalizeExternalSetReleaseDate: nunca faz conversão de timezone (regex de prefixo, nunca Date/toISOString)",
      normalizeExternalSetReleaseDate("2000-02-24T23:59:59.000-05:00") === "2000-02-24",
    );
    assert("normalizeExternalSetReleaseDate: ausente (undefined) -> null", normalizeExternalSetReleaseDate(undefined) === null);
    assert("normalizeExternalSetReleaseDate: ausente (null) -> null", normalizeExternalSetReleaseDate(null) === null);
    assert("normalizeExternalSetReleaseDate: valor inválido -> null", normalizeExternalSetReleaseDate("data-invalida") === null);
    assert("normalizeExternalSetReleaseDate: string vazia -> null", normalizeExternalSetReleaseDate("") === null);
  }
  {
    // Reprodução exata do bug relatado por Fabrício: local 2000-02-24, API com datetime ISO
    // completo -> CONFIRMED (não mais SET_NOT_FOUND).
    const rawSets: JustTcgSet[] = [{ id: "base-set-2-pokemon", name: "Base Set 2", release_date: "2000-02-24T00:00:00.000Z" }];
    const allSets = normalizeJustTcgSets(rawSets);
    const match = resolveSetMatchV2({ codigoMmkyu: "BASE4", releaseDateIso: "2000-02-24" }, allSets);
    assert(
      "reprodução do bug real: local 2000-02-24 + API 2000-02-24T00:00:00.000Z -> CONFIRMED (era SET_NOT_FOUND antes do fix)",
      match.status === "CONFIRMED" && match.set.id === "base-set-2-pokemon",
    );
  }
  {
    const rawSets: JustTcgSet[] = [{ id: "sem-data", name: "Set Sem Data" }];
    const allSets = normalizeJustTcgSets(rawSets);
    const match = resolveSetMatchV2({ codigoMmkyu: "BASE4", releaseDateIso: "2000-02-24" }, allSets);
    assert("release_date ausente na API -> NOT_FOUND, nunca confirmado", match.status === "NOT_FOUND");
  }
  {
    const rawSets: JustTcgSet[] = [
      { id: "set-a", name: "Set A", release_date: "2000-02-24" },
      { id: "set-b", name: "Set B", release_date: "2000-02-24T00:00:00.000Z" },
    ];
    const allSets = normalizeJustTcgSets(rawSets);
    const match = resolveSetMatchV2({ codigoMmkyu: "BASE4", releaseDateIso: "2000-02-24" }, allSets);
    assert("ambiguidade preservada com formatos mistos (data pura + datetime ISO) -> AMBIGUOUS", match.status === "AMBIGUOUS");
  }

  // ==========================================================================
  // Grupo 2 — classifyCardMatch(): número de coleção primário, nome nunca bloqueia (P14.2/
  // P14.4.4/fix/fix v2/P14.4.5)
  // ==========================================================================
  {
    const externalIndex = buildExternalNumberIndex([{ id: "ext-1", name: "Abra", number: "58", variants: [] }]);
    const result = classifyCardMatch({ card_id: "local-1", name: "Abra", collector_number: "058" }, externalIndex, "fixture-set-x");
    assert("correspondência segura: candidato único por Set+número -> SAFE", result.classification === "SAFE" && result.matched?.id === "ext-1");
  }
  {
    const externalIndex = buildExternalNumberIndex([{ id: "ext-energy", name: "Fire Energy", number: "N/A", variants: [] }]);
    assert("número ausente: carta externa 'N/A' nunca entra no índice por número", externalIndex.size === 0);
    const result = classifyCardMatch({ card_id: "local-x", name: "Fire Energy", collector_number: "999" }, externalIndex, "fixture-set-x");
    assert("número ausente: local sem candidato por número -> ABSENT (nunca casado só por nome)", result.classification === "ABSENT");
  }
  {
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-alt-1", name: "Pikachu", number: "25", variants: [] },
      { id: "ext-alt-2", name: "Pikachu", number: "25", variants: [] },
    ]);
    const result = classifyCardMatch({ card_id: "local-pika", name: "Pikachu", collector_number: "025" }, externalIndex, "fixture-set-x");
    assert("ambíguo: dois candidatos com mesmo número, sem desempate seguro -> AMBIGUOUS (nunca auto-confirmado)", result.classification === "AMBIGUOUS" && result.matched === null);
  }
  {
    // P14.4.4 — decisão de negócio: nome NUNCA é critério de matching. Candidato único por
    // Set+número -> SAFE mesmo com nome totalmente diferente (Abra local vs. "Alakazam"
    // externo é um fixture deliberadamente extremo, reproduz o caso real de BASE1/ME1).
    const externalIndex = buildExternalNumberIndex([{ id: "ext-alakazam", name: "Alakazam", number: "1", variants: [] }]);
    const result = classifyCardMatch({ card_id: "local-abra", name: "Abra", collector_number: "001" }, externalIndex, "fixture-set-x");
    assert(
      "P14.4.4: candidato único por Set+número -> SAFE mesmo com nome divergente (nome nunca bloqueia)",
      result.classification === "SAFE" && result.matched?.id === "ext-alakazam",
    );
  }
  {
    // Carta externa sem contraparte local nunca gera mapeamento (laço guiado pelo local, não
    // pelo externo) — não é erro, é comportamento correto.
    const externalIndex = buildExternalNumberIndex([{ id: "ext-orphan", name: "Órfã Externa", number: "200", variants: [] }]);
    const localCards: LocalCard[] = [{ card_id: "local-1", name: "Outra Carta", collector_number: "001" }];
    const results = localCards.map((c) => classifyCardMatch(c, externalIndex, "fixture-set-x"));
    assert("carta externa sem equivalente local: nunca gera mapeamento (laço guiado pelo local)", results.every((r) => r.classification === "ABSENT"));
    assert("carta externa sem equivalente local: continua endereçável para relato informativo (não descartada do índice)", externalIndex.get("200")?.[0].id === "ext-orphan");
  }

  // --- P14.4.5: dedup por external_card_id em buildExternalNumberIndex --------------
  {
    const externalIndexDup = buildExternalNumberIndex([
      { id: "ext-tangela", name: "Tangela", number: "6", variants: [] },
      { id: "ext-tangela", name: "Tangela", number: "6", variants: [] }, // mesmo id, entrada duplicada na resposta bruta
    ]);
    assert(
      "P14.4.5 dedup: buildExternalNumberIndex() nunca duplica o mesmo external_card_id no mesmo número — bucket tem 1 candidato, não 2",
      (externalIndexDup.get("6") ?? []).length === 1,
    );
    const resultDup = classifyCardMatch({ card_id: "local-tangela", name: "Tangela", collector_number: "006" }, externalIndexDup, "fixture-set-x");
    assert(
      "P14.4.5 dedup: candidatos duplicados pelo mesmo external_card_id -> SAFE (nunca AMBIGUOUS) — reproduz e corrige o caso real de ME1",
      resultDup.classification === "SAFE" && resultDup.matched?.id === "ext-tangela",
    );
  }
  {
    // Contraprova: dedup nunca esconde ambiguidade real (2 ids genuinamente distintos).
    const externalIndexMisto = buildExternalNumberIndex([
      { id: "ext-a", name: "Card A", number: "9", variants: [] },
      { id: "ext-a", name: "Card A", number: "9", variants: [] },
      { id: "ext-b", name: "Card B", number: "9", variants: [] },
    ]);
    assert(
      "P14.4.5 dedup: 3 entradas brutas (ext-a duplicado + ext-b) -> 2 candidatos distintos, nunca 3 nem 1",
      (externalIndexMisto.get("9") ?? []).length === 2,
    );
    const resultMisto = classifyCardMatch({ card_id: "local-x9", name: "Card A", collector_number: "009" }, externalIndexMisto, "fixture-set-x");
    assert(
      "P14.4.5 dedup: deduplicar não esconde ambiguidade real — 2 external_card_id genuinamente distintos continuam AMBIGUOUS mesmo com um deles duplicado na resposta bruta",
      resultMisto.classification === "AMBIGUOUS" && resultMisto.matched === null,
    );
  }

  // --- P14.4.4 fix v2: filtro por denominador (EXACT_FULL_IDENTITY vs.
  // INCOMPATIBLE_DENOMINATOR vs. INCOMPLETE_NUMBER) -----------------------------------
  {
    // 1 exato + 1 incompatível -> SAFE pelo exato.
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-mew9", name: "Mew (9)", number: "09/53", variants: [] },
      { id: "ext-seadra", name: "Misty's Seadra (Prerelease)", number: "009/132", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-mew9", name: "Mew", collector_number: "09", collector_total: 53 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "fix v2 (denominador compatível único, com 1 incompatível): SAFE, candidato ext-mew9 selecionado, método SET_CONFIRMED_FULL_COLLECTOR_IDENTITY_UNIQUE",
      result.classification === "SAFE" && result.matched?.id === "ext-mew9" && result.method === "SET_CONFIRMED_FULL_COLLECTOR_IDENTITY_UNIQUE",
    );
  }
  {
    // 1 exato + 1 incompleto (sem denominador declarado) -> SAFE pelo exato — reproduz o bug
    // real SV6.5 (Joltik "001/064" vs. "Basic Grass Energy" "1").
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-joltik", name: "Joltik", number: "001/064", variants: [] },
      { id: "ext-basic-energy", name: "Basic Grass Energy", number: "1", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-joltik", name: "Joltik", collector_number: "1", collector_total: 64 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "fix v2 (1 exato + 1 incompleto -> SAFE pelo exato, reprodução do bug real SV6.5): SAFE, candidato ext-joltik selecionado",
      result.classification === "SAFE" && result.matched?.id === "ext-joltik" && result.method === "SET_CONFIRMED_FULL_COLLECTOR_IDENTITY_UNIQUE",
    );
  }
  {
    // 1 incompatível + 1 incompleto (zero exato) -> AMBIGUOUS.
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-incompat-82", name: "Incompatível", number: "09/82", variants: [] },
      { id: "ext-incompleto-8", name: "Incompleto", number: "09", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-ambiguo-misto", name: "Local", collector_number: "09", collector_total: 60 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "fix v2 (incompatível + incompleto continua ambíguo): AMBIGUOUS, matched null, zero identidade completa",
      result.classification === "AMBIGUOUS" && result.matched === null && (result.evidence.candidatos_identidade_completa as unknown[]).length === 0,
    );
  }
  {
    // 2 candidatos EXACT_FULL_IDENTITY -> AMBIGUOUS (nunca promove com 2+ exatos).
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-exato-a", name: "Exato A", number: "09/53", variants: [] },
      { id: "ext-exato-b", name: "Exato B", number: "09/53", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-2-exatos", name: "Local", collector_number: "09", collector_total: 53 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "fix v2 (2 candidatos exatos): AMBIGUOUS, matched null, 2 candidatos em identidade completa",
      result.classification === "AMBIGUOUS" && result.matched === null && (result.evidence.candidatos_identidade_completa as unknown[]).length === 2,
    );
  }
  {
    // Somente incompletos (nenhum denominador declarado) -> AMBIGUOUS.
    const externalIndex = buildExternalNumberIndex([
      { id: "ext-so-incompleto-1", name: "Incompleto A", number: "09", variants: [] },
      { id: "ext-so-incompleto-2", name: "Incompleto B", number: "09", variants: [] },
    ]);
    const local: LocalCard = { card_id: "local-so-incompletos", name: "Local", collector_number: "09", collector_total: 60 };
    const result = classifyCardMatch(local, externalIndex, "fixture-set-denom");
    assert(
      "fix v2 (somente incompletos): AMBIGUOUS, matched null, zero identidade completa, zero incompatível, 2 incompletos",
      result.classification === "AMBIGUOUS" &&
        result.matched === null &&
        (result.evidence.candidatos_identidade_completa as unknown[]).length === 0 &&
        (result.evidence.candidatos_denominador_incompativel as unknown[]).length === 0 &&
        (result.evidence.candidatos_numero_incompleto as unknown[]).length === 2,
    );
  }

  // ==========================================================================
  // Grupo 3 — classifySetForExpansionPlan(): ALREADY_CONFIRMED_COMPLETE/INCOMPLETE,
  // SAFE_CANDIDATE, AMBIGUOUS, NOT_FOUND (P14.4.1/P14.4.3)
  // ==========================================================================
  {
    const externalSets: JustTcgSet[] = normalizeJustTcgSets([
      { id: "ext-b", name: "Ext B", release_date: "2020-02-01", variants_count: 500 },
      { id: "ext-c1", name: "Ext C1", release_date: "2020-03-01" },
      { id: "ext-c2", name: "Ext C2", release_date: "2020-03-01" },
      { id: "ext-f", name: "Nome Completamente Diferente", release_date: "2020-05-01" },
    ]);

    const jaConfirmadoCompleto = classifySetForExpansionPlan(
      { releaseDateIso: "2020-01-01", localCardCount: 10 },
      { cardSetId: "cs-a", matchStatus: "CONFIRMED", externalSetId: "ext-a", externalSetName: "Ext A" },
      externalSets,
      { mappedCards: 10 },
    );
    assert(
      "Set já CONFIRMED com mappedCards >= localCardCount (10/10) -> ALREADY_CONFIRMED_COMPLETE, preservado, nunca reavaliado contra a lista externa",
      jaConfirmadoCompleto.status === "ALREADY_CONFIRMED_COMPLETE" && jaConfirmadoCompleto.externalSetId === "ext-a",
    );

    const jaConfirmadoIncompleto = classifySetForExpansionPlan(
      { releaseDateIso: "2020-01-01", localCardCount: 102 },
      { cardSetId: "cs-base1", matchStatus: "CONFIRMED", externalSetId: "ext-base1", externalSetName: "Base Set" },
      externalSets,
      { mappedCards: 3 },
    );
    assert(
      "Set já CONFIRMED com mappedCards < localCardCount (3/102, cenário real BASE1) -> ALREADY_CONFIRMED_INCOMPLETE, nunca reavaliado contra a lista externa",
      jaConfirmadoIncompleto.status === "ALREADY_CONFIRMED_INCOMPLETE" && jaConfirmadoIncompleto.externalSetId === "ext-base1",
    );

    const jaConfirmadoSemCobertura = classifySetForExpansionPlan(
      { releaseDateIso: "2020-01-01", localCardCount: 5 },
      { cardSetId: "cs-b", matchStatus: "CONFIRMED", externalSetId: "ext-b2", externalSetName: "Ext B2" },
      externalSets,
      null,
    );
    assert(
      "Set já CONFIRMED sem nenhuma linha de cobertura (coverage=null) -> tratado como 0 cartas mapeadas -> ALREADY_CONFIRMED_INCOMPLETE, nunca assumido completo por omissão",
      jaConfirmadoSemCobertura.status === "ALREADY_CONFIRMED_INCOMPLETE",
    );

    const candidatoUnico = classifySetForExpansionPlan({ releaseDateIso: "2020-02-01", localCardCount: 5 }, null, externalSets, null);
    assert(
      "candidato único por release_date -> SAFE_CANDIDATE, com id/nome/variants_count corretos",
      candidatoUnico.status === "SAFE_CANDIDATE" && candidatoUnico.externalSetId === "ext-b" && candidatoUnico.externalVariantsCount === 500,
    );

    const doisCandidatos = classifySetForExpansionPlan({ releaseDateIso: "2020-03-01", localCardCount: 5 }, null, externalSets, null);
    assert("dois candidatos na mesma release_date -> AMBIGUOUS, nunca confirmado automaticamente", doisCandidatos.status === "AMBIGUOUS" && doisCandidatos.candidateCount === 2);

    const nenhumCandidato = classifySetForExpansionPlan({ releaseDateIso: "2020-04-01", localCardCount: 5 }, null, externalSets, null);
    assert("nenhum candidato na release_date -> NOT_FOUND", nenhumCandidato.status === "NOT_FOUND" && nenhumCandidato.reason === "RELEASE_DATE_SEM_CORRESPONDENCIA_EXTERNA");

    const semReleaseDate = classifySetForExpansionPlan({ releaseDateIso: null, localCardCount: 5 }, null, externalSets, null);
    assert("Set local sem release_date -> NOT_FOUND, nunca tenta casar por nome", semReleaseDate.status === "NOT_FOUND" && semReleaseDate.reason === "SET_LOCAL_SEM_RELEASE_DATE");

    const nomeDivergente = classifySetForExpansionPlan({ releaseDateIso: "2020-05-01", localCardCount: 5 }, null, externalSets, null);
    assert(
      "nome completamente divergente NUNCA bloqueia um candidato único e seguro por data (nome nunca é fundamento isolado — só release_date confirma)",
      nomeDivergente.status === "SAFE_CANDIDATE" && nomeDivergente.externalSetId === "ext-f",
    );
  }

  // ==========================================================================
  // Grupo 4 — decideMappingUpsert(): idempotência (corrige a lacuna de P8) (P8/P14.2)
  // ==========================================================================
  assert("idempotência: sem linha existente -> INSERTED", decideMappingUpsert(null, "CONFIRMED") === "INSERTED");
  assert(
    "idempotência: já CONFIRMED, nova classificação também CONFIRMED -> no-op (zero escrita)",
    decideMappingUpsert({ id: "m1", match_status: "CONFIRMED" }, "CONFIRMED") === "NOOP_SAME_STATUS",
  );
  assert(
    "idempotência: NOT_FOUND antigo + nova classificação CONFIRMED -> promovido (corrige a lacuna de P8)",
    decideMappingUpsert({ id: "m2", match_status: "NOT_FOUND" }, "CONFIRMED") === "UPGRADED_TO_CONFIRMED",
  );
  assert(
    "idempotência: CONFIRMED nunca é rebaixado por uma nova classificação pior",
    decideMappingUpsert({ id: "m3", match_status: "CONFIRMED" }, "NOT_FOUND") === "NOOP_KEEP_CONFIRMED_DIVERGENT_INPUT",
  );
  assert(
    "idempotência: PENDING permanece PENDING quando a nova classificação também é ambígua",
    decideMappingUpsert({ id: "m4", match_status: "PENDING" }, "PENDING") === "NOOP_SAME_STATUS",
  );

  const failedCount = assertions.filter(([, ok]) => !ok).length;
  return { assertions, failedCount };
}

// ----------------------------------------------------------------------------
// Registro no runner nativo do Deno — mesma disciplina de set-refresh-core.test.ts:
// guardado por `typeof Deno !== "undefined"` para permanecer importável a partir de Node
// (validação offline no sandbox). 100% offline — nenhuma permissão --allow-* necessária.
// ----------------------------------------------------------------------------
if (typeof Deno !== "undefined") {
  Deno.test(
    "pricing-justtcg-matching — suíte offline do núcleo compartilhado de matching (P16.2, 2026-08-25)",
    async () => {
      const result = await runPricingJusttcgMatchingTests();
      const falhas = result.assertions.filter(([, ok]) => !ok);
      if (falhas.length > 0) {
        throw new Error(
          `${falhas.length}/${result.assertions.length} asserções falharam:\n` +
            falhas.map(([label]) => `  - ${label}`).join("\n"),
        );
      }
    },
  );
}
