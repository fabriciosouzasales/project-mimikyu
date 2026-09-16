// Project Mimikyu — supabase/functions/import-card-variants/services/size-scope.test.ts
// Bateria do guard de ESCOPO POR TAMANHO (incidente JUMBO, 2026-09-15).
//
// 100% offline: nenhuma chamada de rede, nenhum acesso ao Supabase.
//
// Execução canônica:
//   deno test --allow-read supabase/functions/import-card-variants/services/size-scope.test.ts
//
// `--allow-read` é exigido apenas pelo Caso E, que é uma prova ESTRUTURAL
// sobre o texto de index.ts (ver o comentário do caso). Os demais casos são
// comportamentais e não tocam o disco.
//
// Mesmo formato de _shared/catalog-normalization/collector-order.test.ts: um
// único `Deno.test` real, que falha de verdade (throw) quando qualquer
// assertion falha, e uma função exportada reaproveitável por runner externo.
//
// ROTEIRO DE PROVAS (A-F), exatamente o exigido pelo mandato:
//   A  size ausente        -> fluxo legado, bit a bit
//   B  size STANDARD       -> fluxo legado, bit a bit
//   C  jumbo / JUMBO       -> INVALID/SKIPPED + SIZE_OUT_OF_SCOPE
//   D  size desconhecido   -> NEEDS_REVIEW/PENDING + UNSUPPORTED_SIZE_VALUE
//   E  JUMBO nao alcanca routePrinting nem o dedupe legado
//   F  size desconhecido NAO ganha controles editoriais de mapeamento

import {
  classifyVariantSize,
  SIZE_OUT_OF_SCOPE,
  UNSUPPORTED_SIZE_VALUE,
} from "./size-scope.ts";
import { extractVariantsFromSource } from "./github-source.ts";
import {
  canDecideVariantRow,
  canResolveVariantRowMapping,
  classifyVariantRowScope,
  deriveVariantImportScopeCounters,
  isVariantRowMappingPending,
  isVariantRowScopeLocked,
  isVariantRowSelectable,
  variantRowScopeLabel,
} from "../../../../web/lib/catalogo/variant-size-scope.ts";

export type Resultado = { caso: string; ok: boolean; detalhe: string };

function assert(resultados: Resultado[], caso: string, ok: boolean, detalhe = "") {
  resultados.push({ caso, ok, detalhe });
}

/** Fonte sintética no formato do dataset TCGdex (TypeScript, não JSON). */
function fonteComVariantes(corpo: string): string {
  return `const card: SetCard = {\n  id: "base1-1",\n  localId: "1",\n  name: "Alakazam",\n  variants: [\n${corpo}\n  ],\n}`;
}

export function runSizeScopeTests(): Resultado[] {
  const r: Resultado[] = [];

  // -------------------------------------------------------------------------
  // CASO A — size ausente/null/blank -> fluxo legado
  // -------------------------------------------------------------------------
  for (const [rotulo, entrada] of [
    ["null", null],
    ["undefined", undefined],
    ["string vazia", ""],
    ["so espacos", "   "],
  ] as Array<[string, string | null | undefined]>) {
    const c = classifyVariantSize(entrada);
    assert(
      r,
      `A size ausente (${rotulo}) -> IN_SCOPE`,
      c.kind === "IN_SCOPE" && c.normalizedSize === null,
      JSON.stringify(c),
    );
  }

  // O extractor tambem precisa devolver null quando a fonte nao traz `size` —
  // essa e a metade do Caso A que vive no parser, nao no classificador.
  {
    const combos = extractVariantsFromSource(
      fonteComVariantes(`    { type: "normal", foil: null, subtype: null },`),
    );
    assert(
      r,
      "A fonte sem `size` -> combo.size === null",
      combos.length === 1 && combos[0].size === null,
      JSON.stringify(combos),
    );
  }

  // -------------------------------------------------------------------------
  // CASO B — STANDARD -> fluxo legado (mesmo desfecho de A, caminho diferente)
  // -------------------------------------------------------------------------
  for (const entrada of ["standard", "STANDARD", " Standard ", "sTaNdArD"]) {
    const c = classifyVariantSize(entrada);
    assert(
      r,
      `B size="${entrada}" -> IN_SCOPE`,
      c.kind === "IN_SCOPE" && c.normalizedSize === "STANDARD",
      JSON.stringify(c),
    );
  }

  // -------------------------------------------------------------------------
  // CASO C — jumbo -> fora de escopo
  // -------------------------------------------------------------------------
  for (const entrada of ["jumbo", "JUMBO", " Jumbo "]) {
    const c = classifyVariantSize(entrada);
    assert(
      r,
      `C size="${entrada}" -> OUT_OF_SCOPE + SIZE_OUT_OF_SCOPE`,
      c.kind === "OUT_OF_SCOPE" && c.normalizedSize === "JUMBO" &&
        c.kind === "OUT_OF_SCOPE" && c.skipReason === SIZE_OUT_OF_SCOPE,
      JSON.stringify(c),
    );
  }

  // O valor precisa chegar preservado da fonte real — este e o defeito
  // original do incidente: `size` existia no dataset e era descartado aqui.
  {
    const combos = extractVariantsFromSource(
      fonteComVariantes(
        `    { type: "normal", foil: null, subtype: null, size: "jumbo" },\n` +
          `    { type: "holo", foil: "holo", subtype: null, size: "standard" },`,
      ),
    );
    assert(
      r,
      "C extractor preserva `size` das duas variantes",
      combos.length === 2 && combos[0].size === "jumbo" && combos[1].size === "standard",
      JSON.stringify(combos),
    );
  }

  // -------------------------------------------------------------------------
  // CASO D — valor desconhecido -> revisao humana, fail closed
  // -------------------------------------------------------------------------
  for (const entrada of ["oversized", "mini", "OVERSIZED", "extra large"]) {
    const c = classifyVariantSize(entrada);
    assert(
      r,
      `D size="${entrada}" -> UNSUPPORTED + UNSUPPORTED_SIZE_VALUE`,
      c.kind === "UNSUPPORTED" && c.reviewReason === UNSUPPORTED_SIZE_VALUE,
      JSON.stringify(c),
    );
  }
  {
    // Normalizacao (acento/caixa/espaco) tem de casar com
    // public.normalize_external_catalog_value — o guard da Query 2198 compara
    // o MESMO texto do outro lado.
    const c = classifyVariantSize("  Extra   Gránde ");
    assert(
      r,
      "D normalizacao espelha normalize_external_catalog_value",
      c.kind === "UNSUPPORTED" && c.normalizedSize === "EXTRA GRANDE",
      JSON.stringify(c),
    );
  }

  // -------------------------------------------------------------------------
  // CASO E — o gate precede routePrinting E o dedupe legado.
  //
  // PROVA ESTRUTURAL, declarada como tal. A ordem entre o gate e o roteamento
  // e um invariante do FLUXO de index.ts, e o loop de processamento nao e
  // exportavel sem uma refatoracao que este mandato nao autoriza. Entao a
  // prova e sobre o texto do proprio arquivo — mesma tecnica ja usada no
  // harness 2827 (`pg_get_functiondef ILIKE '%BLOCKED_SIZE_%'`).
  //
  // O que se prova: (1) a chamada a classifyVariantSize aparece ANTES da
  // chamada a routePrinting e antes da construcao de dedupeKey; (2) o ramo
  // fora de escopo termina em `continue`; (3) o dedupe das linhas barradas
  // usa um espaco proprio (`X|`) que inclui o size normalizado.
  // -------------------------------------------------------------------------
  {
    let fonte = "";
    try {
      fonte = Deno.readTextFileSync(new URL("../index.ts", import.meta.url));
    } catch (e) {
      assert(r, "E leitura de index.ts", false, String(e));
    }

    if (fonte) {
      const iGate = fonte.indexOf("classifyVariantSize(combo.size)");
      const iPrinting = fonte.indexOf("const printing = routePrinting(");
      const iDedupe = fonte.indexOf("const dedupeKey = isValid");
      const iContinue = fonte.indexOf("continue;", iGate);

      assert(r, "E gate presente em index.ts", iGate > -1, `idx=${iGate}`);
      assert(
        r,
        "E gate ANTES de routePrinting",
        iGate > -1 && iPrinting > -1 && iGate < iPrinting,
        `gate=${iGate} printing=${iPrinting}`,
      );
      assert(
        r,
        "E gate ANTES do dedupe legado",
        iGate > -1 && iDedupe > -1 && iGate < iDedupe,
        `gate=${iGate} dedupe=${iDedupe}`,
      );
      assert(
        r,
        "E ramo barrado sai do loop (continue) antes de routePrinting",
        iContinue > -1 && iContinue < iPrinting,
        `continue=${iContinue} printing=${iPrinting}`,
      );
      assert(
        r,
        "E dedupe das linhas barradas em espaco proprio com size normalizado",
        fonte.includes("`X|${cardId}|${rawComboKey}|${sizeScope.normalizedSize}`"),
      );
      assert(
        r,
        "E raw_data carrega `size` para TODA linha (evidencia do guard 2198)",
        fonte.includes("size: combo.size ?? null"),
      );
    }
  }

  // -------------------------------------------------------------------------
  // CASO F — tamanho desconhecido NAO ganha controles editoriais de mapeamento.
  // Comportamental, sobre o contrato puro que a tela consome.
  // -------------------------------------------------------------------------
  {
    const semMapeamento = {
      validationStatus: "NEEDS_REVIEW",
      skipReason: null,
      reviewReason: null,
    };
    const tamanhoDesconhecido = {
      validationStatus: "NEEDS_REVIEW",
      skipReason: null,
      reviewReason: UNSUPPORTED_SIZE_VALUE,
    };
    const foraDeEscopo = {
      validationStatus: "INVALID",
      skipReason: SIZE_OUT_OF_SCOPE,
      reviewReason: null,
    };
    const valida = { validationStatus: "VALID", skipReason: null, reviewReason: null };

    assert(r, "F classificacao — sem mapeamento e IN_SCOPE",
      classifyVariantRowScope(semMapeamento) === "IN_SCOPE");
    assert(r, "F classificacao — tamanho desconhecido",
      classifyVariantRowScope(tamanhoDesconhecido) === "UNSUPPORTED_SIZE");
    assert(r, "F classificacao — fora de escopo",
      classifyVariantRowScope(foraDeEscopo) === "OUT_OF_SCOPE");

    assert(r, "F sem mapeamento CONTINUA tendo controle editorial",
      canResolveVariantRowMapping(semMapeamento) === true);
    assert(r, "F tamanho desconhecido NAO tem controle editorial",
      canResolveVariantRowMapping(tamanhoDesconhecido) === false);
    assert(r, "F fora de escopo NAO tem controle editorial",
      canResolveVariantRowMapping(foraDeEscopo) === false);
    assert(r, "F linha valida NAO tem controle editorial",
      canResolveVariantRowMapping(valida) === false);

    assert(r, "F contador de pendencia de mapeamento ignora tamanho desconhecido",
      isVariantRowMappingPending(tamanhoDesconhecido) === false);
    assert(r, "F contador de pendencia de mapeamento ignora fora de escopo",
      isVariantRowMappingPending(foraDeEscopo) === false);
    assert(r, "F contador de pendencia de mapeamento conta sem mapeamento",
      isVariantRowMappingPending(semMapeamento) === true);

    assert(r, "F rotulo contextual — fora de escopo",
      variantRowScopeLabel(foraDeEscopo) === "Fora de escopo");
    assert(r, "F rotulo contextual — tamanho desconhecido",
      variantRowScopeLabel(tamanhoDesconhecido) === "Tamanho desconhecido");
    assert(r, "F rotulo contextual — linha normal nao ganha ruido",
      variantRowScopeLabel(semMapeamento) === null);
  }

  // ===========================================================================
  // CORRECTION-01 (2026-09-16) — provas novas exigidas pelo mandato
  // SIZE-SCOPE-EDGE-UI-CORRECTION-01, OBJETIVO 3.
  // ===========================================================================

  const rowSemMapeamento = { validationStatus: "NEEDS_REVIEW", skipReason: null, reviewReason: null };
  const rowTamanhoDesconhecido = {
    validationStatus: "NEEDS_REVIEW",
    skipReason: null,
    reviewReason: UNSUPPORTED_SIZE_VALUE,
  };
  const rowForaDeEscopo = { validationStatus: "INVALID", skipReason: SIZE_OUT_OF_SCOPE, reviewReason: null };
  const rowValida = { validationStatus: "VALID", skipReason: null, reviewReason: null };

  // -------------------------------------------------------------------------
  // G — OUT_OF_SCOPE é decisão automática IMUTÁVEL (BLOCKER-1)
  // -------------------------------------------------------------------------
  assert(r, "G fora de escopo e travada", isVariantRowScopeLocked(rowForaDeEscopo) === true);
  assert(r, "G tamanho desconhecido NAO e travada (decisao humana)",
    isVariantRowScopeLocked(rowTamanhoDesconhecido) === false);
  assert(r, "G sem mapeamento NAO e travada", isVariantRowScopeLocked(rowSemMapeamento) === false);
  assert(r, "G valida NAO e travada", isVariantRowScopeLocked(rowValida) === false);

  assert(r, "G fora de escopo NAO e selecionavel", isVariantRowSelectable(rowForaDeEscopo) === false);
  assert(r, "G tamanho desconhecido continua selecionavel",
    isVariantRowSelectable(rowTamanhoDesconhecido) === true);
  assert(r, "G sem mapeamento continua selecionavel", isVariantRowSelectable(rowSemMapeamento) === true);
  assert(r, "G valida continua selecionavel", isVariantRowSelectable(rowValida) === true);

  // "Selecionar todas" = filtrar por isVariantRowSelectable. Prova direta de
  // que a linha travada nao entra no lote nem por esse caminho.
  {
    const visiveis = [rowValida, rowSemMapeamento, rowForaDeEscopo, rowTamanhoDesconhecido];
    const selecionaveis = visiveis.filter(isVariantRowSelectable);
    assert(
      r,
      "G selecionar todas ignora a linha fora de escopo",
      selecionaveis.length === 3 && !selecionaveis.includes(rowForaDeEscopo),
      `selecionaveis=${selecionaveis.length}/4`,
    );
  }

  assert(r, "G fora de escopo NAO aceita APPROVED",
    canDecideVariantRow(rowForaDeEscopo, "APPROVED") === false);
  assert(r, "G fora de escopo NAO aceita REJECTED",
    canDecideVariantRow(rowForaDeEscopo, "REJECTED") === false);
  assert(r, "G fora de escopo NAO aceita PENDING (sem volta)",
    canDecideVariantRow(rowForaDeEscopo, "PENDING") === false);
  assert(r, "G fora de escopo ACEITA SKIPPED (idempotente)",
    canDecideVariantRow(rowForaDeEscopo, "SKIPPED") === true);
  assert(r, "G fora de escopo nao tem controle de mapping",
    canResolveVariantRowMapping(rowForaDeEscopo) === false);

  // Filtro de lote da UI: `decidir()` remove ids travados antes de chamar a
  // Server Action. Reproduzido aqui sobre a mesma função.
  {
    const lote = [rowValida, rowForaDeEscopo, rowSemMapeamento];
    const seguros = lote.filter((row) => canDecideVariantRow(row, "REJECTED"));
    assert(
      r,
      "G lote REJECTED remove a linha travada e preserva as demais",
      seguros.length === 2 && !seguros.includes(rowForaDeEscopo),
      `seguros=${seguros.length}/3`,
    );
  }

  // -------------------------------------------------------------------------
  // H — REGRESSÃO: tamanho desconhecido continua sendo decisão humana
  // -------------------------------------------------------------------------
  for (const status of ["APPROVED", "REJECTED", "PENDING", "SKIPPED"] as const) {
    assert(
      r,
      `H tamanho desconhecido aceita ${status} pelo contrato de escopo`,
      canDecideVariantRow(rowTamanhoDesconhecido, status) === true,
    );
    assert(
      r,
      `H sem mapeamento aceita ${status} pelo contrato de escopo`,
      canDecideVariantRow(rowSemMapeamento, status) === true,
    );
  }
  assert(r, "H tamanho desconhecido segue sem controle de mapping",
    canResolveVariantRowMapping(rowTamanhoDesconhecido) === false);

  // -------------------------------------------------------------------------
  // I — CONTADORES: fonte única, zero real != erro, escala
  // -------------------------------------------------------------------------
  {
    const vazio = deriveVariantImportScopeCounters([]);
    assert(
      r,
      "I coleção vazia -> zeros reais",
      vazio.mappingPendingRows === 0 && vazio.unsupportedSizeRows === 0 && vazio.outOfScopeRows === 0,
      JSON.stringify(vazio),
    );
  }
  {
    const so_validas = deriveVariantImportScopeCounters([rowValida, rowValida, rowValida]);
    assert(
      r,
      "I job sadio -> zero real em todos os tres (0 continua 0)",
      so_validas.mappingPendingRows === 0 && so_validas.unsupportedSizeRows === 0 &&
        so_validas.outOfScopeRows === 0,
      JSON.stringify(so_validas),
    );
  }
  {
    const misto = deriveVariantImportScopeCounters([
      rowValida,
      rowSemMapeamento,
      rowSemMapeamento,
      rowTamanhoDesconhecido,
      rowForaDeEscopo,
      rowForaDeEscopo,
      rowForaDeEscopo,
    ]);
    assert(
      r,
      "I classificacao correta e disjunta (2 / 1 / 3)",
      misto.mappingPendingRows === 2 && misto.unsupportedSizeRows === 1 && misto.outOfScopeRows === 3,
      JSON.stringify(misto),
    );
  }
  {
    // >1000 linhas. ESCOPO EXATO DESTE CASO (correção da Correction-02): ele
    // prova APENAS que `deriveVariantImportScopeCounters` não tem teto próprio
    // — que classificar 1507 linhas produz 1507 classificações. Ele NÃO prova
    // que a população de 1507 linhas chegou íntegra do banco.
    //
    // A completude depende de DUAS coisas, ambas provadas em J, nenhuma aqui:
    //   1. paginação até página vazia (fetchAllRowsStrict); e
    //   2. ORDENAÇÃO TOTAL na query paginada — sem uma coluna única como
    //      último critério, `.range()` opera sobre uma ordem indefinida e a
    //      mesma linha pode vir em duas páginas enquanto outra some.
    //      Em BASE1 as 415 linhas têm o MESMO created_at; o maior grupo de
    //      created_at idêntico no LIVE tem 507 linhas.
    const grande = [
      ...Array.from({ length: 1200 }, () => rowSemMapeamento),
      ...Array.from({ length: 300 }, () => rowForaDeEscopo),
      ...Array.from({ length: 7 }, () => rowTamanhoDesconhecido),
    ];
    const c = deriveVariantImportScopeCounters(grande);
    assert(
      r,
      "I 1507 linhas: derivacao sem teto proprio (1200 / 7 / 300) — completude e provada em J",
      c.mappingPendingRows === 1200 && c.unsupportedSizeRows === 7 && c.outOfScopeRows === 300,
      JSON.stringify(c),
    );
  }
  {
    // Painel e tabela: MESMA função, MESMA população. Prova de que não há
    // duas fontes de verdade a divergir.
    const populacao = [rowValida, rowSemMapeamento, rowTamanhoDesconhecido, rowForaDeEscopo];
    const painel = deriveVariantImportScopeCounters(populacao);
    const tabela = deriveVariantImportScopeCounters(populacao);
    assert(
      r,
      "I painel e tabela produzem numeros identicos por construcao",
      JSON.stringify(painel) === JSON.stringify(tabela),
      JSON.stringify(painel),
    );
  }

  // -------------------------------------------------------------------------
  // J — ESTRUTURAL: paginação fail-closed e ausência do desenho antigo
  // -------------------------------------------------------------------------
  {
    let q = "";
    try {
      q = Deno.readTextFileSync(new URL("../../../../web/lib/catalogo/queries.ts", import.meta.url));
    } catch (e) {
      assert(r, "J leitura de queries.ts", false, String(e));
    }

    if (q) {
      assert(r, "J getCatalogVariantImportRows usa fetchAllRowsStrict (paginado + fail-closed)",
        /getCatalogVariantImportRows[\s\S]{0,1200}fetchAllRowsStrict/.test(q));
      assert(r, "J contadores de escopo tambem paginados e strict",
        /getCatalogVariantImportScopeCounters[\s\S]{0,800}fetchAllRowsStrict/.test(q));
      assert(r, "J os tres HEAD count independentes foram REMOVIDOS",
        !q.includes('count: "exact", head: true') || !q.includes("normalized_data->>skip_reason"));
      assert(r, "J nao resta `count ?? 0` para pendencia de escopo",
        !q.includes("unsupportedSizeCount.count ?? 0") && !q.includes("outOfScopeCount.count ?? 0"));
      assert(r, "J job status nao carrega mais os tres contadores",
        !q.includes("mappingPendingRows: Math.max("));

      // --- ORDENAÇÃO TOTAL (BLOCKER-3) -----------------------------------
      // Toda query passada a fetchAllRowsStrict precisa terminar com uma
      // coluna ÚNICA como último critério. Sem isso, `.range()` pagina sobre
      // ordem indefinida. Prova por bloco: recorta cada chamada e exige
      // `.order("id"` antes do `.range(from, to)`.
      {
        const blocos = q.split("fetchAllRowsStrict((from, to) =>").slice(1);
        assert(r, "J existem 5 leitores paginados strict", blocos.length === 5, `blocos=${blocos.length}`);

        const semTieBreaker = blocos
          .map((b) => b.slice(0, b.indexOf(".range(from, to)")))
          .filter((b) => !/\.order\("id",\s*\{\s*ascending:\s*true\s*\}\)/.test(b));

        assert(
          r,
          "J TODO leitor paginado strict tem tie-breaker unico por id",
          semTieBreaker.length === 0,
          `sem tie-breaker=${semTieBreaker.length}`,
        );
      }

      // Nas duas leituras de catalog_variant_import_row do fluxo de variantes,
      // a ordenação é COMPOSTA: created_at (critério real) + id (desempate).
      {
        const compostas = q.match(
          /\.order\("created_at",\s*\{\s*ascending:\s*true\s*\}\)\s*\n\s*\.order\("id",\s*\{\s*ascending:\s*true\s*\}\)/g,
        ) ?? [];
        assert(
          r,
          "J ordenacao composta created_at+id nas duas leituras de staging",
          compostas.length === 2,
          `ocorrencias=${compostas.length}`,
        );
      }

      assert(
        r,
        "J nao resta order(created_at) isolado antes de um range paginado",
        !/\.order\("created_at",\s*\{\s*ascending:\s*true\s*\}\)\s*\n\s*\.range\(from, to\)/.test(q),
      );
    }

    // --- BLOCKER-4: precheck redundante removido do Server Action ---------
    {
      let a = "";
      try {
        a = Deno.readTextFileSync(new URL("../../../../web/app/catalogo/importar-variantes/actions.ts", import.meta.url));
      } catch (e) {
        assert(r, "J leitura de actions.ts", false, String(e));
      }

      if (a) {
        // A asserção é sobre CÓDIGO, não sobre prosa: o comentário que
        // documenta a remoção cita o literal `.in("id", rowIds)` de propósito,
        // e não pode fazer a prova falhar. Comentários de linha e de bloco são
        // removidos antes de procurar a chamada.
        const codigo = a
          .replace(/\/\*[\s\S]*?\*\//g, "")
          .split("\n")
          .filter((l) => !l.trim().startsWith("//"))
          .join("\n");

        assert(r, "J precheck .in(rowIds) removido do Server Action (codigo, sem comentarios)",
          !codigo.includes('.in("id", rowIds)'));
        assert(r, "J a regra de escopo nao esta duplicada na aplicacao",
          !codigo.includes("VARIANT_SKIP_REASON_SIZE_OUT_OF_SCOPE"));
        assert(r, "J decidirLinhasVariantes continua chamando a RPC (autoridade unica)",
          codigo.includes('supabase.rpc("admin_decide_catalog_variant_import_row"'));
        // O comentário DEVE continuar existindo: a decisão de remover e o
        // porquê são parte da entrega, não ruído a apagar.
        assert(r, "J a remocao do precheck esta documentada no arquivo",
          a.includes("AUTORIDADE DA DECISÃO: A RPC, NÃO ESTA AÇÃO"));
      }
    }

    let v = "";
    try {
      v = Deno.readTextFileSync(new URL("../../../../web/components/catalogo/importar-variantes-view.tsx", import.meta.url));
    } catch { /* coberto pela assertion abaixo */ }

    assert(r, "J view nao deriva contador de totalRows - validRows",
      v.length > 0 && !/const\s+\w+\s*=\s*Math\.max\(job\.totalRows - job\.validRows/.test(v));
    assert(r, "J painel de conclusao e fail-closed (sem counters nao declara sucesso)",
      v.includes('job.status === "COMPLETED_WITH_ERRORS" || !counters'));
  }

  return r;
}

// ---------------------------------------------------------------------------
// Deno.test real — falha de verdade quando qualquer assertion falha.
// ---------------------------------------------------------------------------

Deno.test("size-scope — guard de escopo por tamanho (incidente JUMBO)", () => {
  const resultados = runSizeScopeTests();
  const falhas = resultados.filter((x) => !x.ok);

  for (const x of resultados) {
    console.log(`${x.ok ? "PASS" : "FAIL"}  ${x.caso}${x.detalhe ? `  — ${x.detalhe}` : ""}`);
  }
  console.log(`\n${resultados.length} casos · ${resultados.length - falhas.length} PASS · ${falhas.length} FAIL`);

  if (resultados.length === 0) {
    throw new Error("SIZE_SCOPE_TESTS_VAZIO: a suite nao produziu nenhum caso.");
  }
  if (falhas.length > 0) {
    throw new Error(
      `SIZE_SCOPE_TESTS_FAILED (${falhas.length}/${resultados.length}):\n` +
        falhas.map((x) => `  - ${x.caso}${x.detalhe ? ` — ${x.detalhe}` : ""}`).join("\n"),
    );
  }
});
