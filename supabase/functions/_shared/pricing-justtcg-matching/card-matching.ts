// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-matching/card-matching.ts
// Correlação de cartas — número de coleção primário, nome só desempata/verifica. Portado de
// scripts/sync-justtcg-pricing.ts (Incrementos P14.2/P14.4.4/P14.4.4 fix/fix v2/P14.4.5) para
// o Incremento P16.2 (Núcleo Compartilhado de Matching, 2026-08-25). Nenhuma mudança de
// comportamento nesta extração — mesma lógica, byte a byte (pesos/thresholds/critérios de
// igualdade/regras de ambiguidade preservados exatamente).

import type { JustTcgCard } from "../pricing-justtcg/mod.ts";
import type { CardMatchResult, LocalCard } from "./types.ts";
import { isUsableExternalNumber, isValidCollectorTotal, normalizeName, normalizeNumber, parseCollectorNumberParts } from "./normalize.ts";

// Índice por número normalizado -> candidatos externos com aquele número. Cartas sem
// número utilizável (ver isUsableExternalNumber) nunca entram aqui.
//
// Deduplicação por external_card_id (decisão de negócio, correção pós-P14.4.4): a mesma
// carta externa pode aparecer mais de uma vez na resposta bruta da JustTCG para o mesmo
// id (observado na evidência histórica de BASE1/ME1 antes desta correção — "candidatos"
// com o mesmo id repetido). Sem deduplicar aqui, contar entradas brutas do array supercontaria
// candidatos e classificaria como AMBIGUOUS/PENDING um número que na verdade tem uma única
// carta externa distinta — bloqueando indevidamente uma promoção que deveria ser CONFIRMED.
// A deduplicação acontece na construção do índice (fonte única, usada por piloto,
// expansion-wave, backfill e reparo) para que a correção valha em todos os caminhos sem
// precisar tocar em cada chamador.
export function buildExternalNumberIndex(externalCards: JustTcgCard[]): Map<string, JustTcgCard[]> {
  const index = new Map<string, JustTcgCard[]>();
  const seenIdsByKey = new Map<string, Set<string>>();
  for (const card of externalCards) {
    if (!isUsableExternalNumber(card.number)) continue;
    const key = normalizeNumber(card.number as string);
    const seenIds = seenIdsByKey.get(key) ?? new Set<string>();
    if (seenIds.has(card.id)) continue; // mesmo external_card_id já contabilizado neste número — não duplica o candidato.
    seenIds.add(card.id);
    seenIdsByKey.set(key, seenIds);
    const bucket = index.get(key) ?? [];
    bucket.push(card);
    index.set(key, bucket);
  }
  return index;
}

// Verificação secundária de nome — nunca a evidência primária. Regra conservadora e
// determinística (sem distância de edição/fuzzy): igualdade normalizada, ou um nome é
// prefixo do outro seguido de espaço (cobre qualificadores como "(...)" / " ex" / " V"
// já observados em P8). Qualquer coisa fora disso é tratada como divergência de nome —
// erra para o lado de marcar ambíguo, nunca para o lado de confirmar sem certeza.
export function isNameCompatible(localName: string, externalName: string): boolean {
  const a = normalizeName(localName);
  const b = normalizeName(externalName);
  if (!a || !b) return false;
  if (a === b) return true;
  if (a.startsWith(`${b} `) || b.startsWith(`${a} `)) return true;
  return false;
}

// P14.4.4 — Correção de causa raiz (identidade canônica de carta), decisão de negócio
// confirmada por Fabrício: a correspondência entre carta local e JustTCG usa
// EXCLUSIVAMENTE (1) Card Set local vinculado a um external_set_id já CONFIRMED, (2)
// collector_number normalizado, (3) exatamente uma carta externa com esse número dentro
// do Set confirmado. Nome NUNCA é critério de matching — nosso catálogo é PT-BR, a
// JustTCG é em inglês, e comparar nomes entre os dois idiomas produzia falsos-AMBIGUOUS
// sistemáticos. Nome é preservado só como evidência de auditoria/exibição, nunca como
// critério que bloqueia ou desempata. Regra única, sem exceção por categoria de carta.
//
// P14.4.4 fix (filtro por denominador, decisão de negócio confirmada por Fabrício após
// auditoria read-only dos 548 PENDING/18 NOT_FOUND): quando há MAIS de um candidato para o
// mesmo numerador, um segundo sinal estrutural — nunca nome, nunca idioma, nunca raridade,
// nunca preferência de edição — pode reduzir a ambiguidade: o denominador declarado no
// número do candidato externo (a parte "/D" de "N/D") comparado a collector_total da carta
// local.
//
// P14.4.4 fix v2 (correção de especificidade estrutural, confirmada por Fabrício após o
// dry-run real divergir em SV6.5 — 0/8 promovidos em vez de 8/8): a versão anterior tratava
// um candidato sem denominador declarado como sobrevivente em pé de igualdade com um
// candidato de identidade completa. Cada candidato é classificado em exatamente uma
// categoria:
//   EXACT_FULL_IDENTITY      — denominador declarado e igual a collector_total da carta local
//   INCOMPATIBLE_DENOMINATOR — denominador declarado e diferente de collector_total
//   INCOMPLETE_NUMBER        — sem denominador declarado (ausência de informação nunca prova
//                              incompatibilidade, mas também nunca prevalece sobre uma
//                              identidade completa comprovada)
// Só EXATAMENTE 1 candidato em EXACT_FULL_IDENTITY promove a carta a SAFE — 2+ candidatos em
// EXACT_FULL_IDENTITY, ou 0 candidatos em EXACT_FULL_IDENTITY (não importa quantos
// INCOMPLETE_NUMBER/INCOMPATIBLE_DENOMINATOR sobrarem), permanecem AMBIGUOUS.
//
// Classificação:
//   1 candidato para Set+número (sem precisar do filtro)
//     -> SAFE      (method SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE)
//   0 candidatos
//     -> ABSENT    (method SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE) — nunca afetado pelo filtro
//   >1 candidatos, collector_total ausente/inválido
//     -> AMBIGUOUS (method SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE) — comportamento
//        conservador anterior, byte a byte, sem nenhum campo novo na evidência
//   >1 candidatos, collector_total válido, exatamente 1 candidato em EXACT_FULL_IDENTITY
//     -> SAFE      (method SET_CONFIRMED_FULL_COLLECTOR_IDENTITY_UNIQUE)
//   >1 candidatos, collector_total válido, 0 ou 2+ candidatos em EXACT_FULL_IDENTITY
//     -> AMBIGUOUS (method SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE) — NUNCA ABSENT/NOT_FOUND,
//        e nunca promovido só porque sobra um candidato INCOMPLETE_NUMBER
//   número local ausente/inutilizável -> ABSENT (mesmo method — nunca cai em outro branch)
//
// `externalSetId` é recebido só para deixar explícito, na própria evidência, sob qual Set
// já CONFIRMED a correspondência foi tentada — nunca usado para resolver/reavaliar o Set
// em si (isso continua sendo responsabilidade exclusiva de resolveSetMatchV2(), fora desta
// função).
export function classifyCardMatch(local: LocalCard, externalIndex: Map<string, JustTcgCard[]>, externalSetId: string): CardMatchResult {
  const localNumNorm = normalizeNumber(local.collector_number);
  const METHOD = "SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE";
  const METHOD_IDENTIDADE_COMPLETA = "SET_CONFIRMED_FULL_COLLECTOR_IDENTITY_UNIQUE";

  // Número local ausente/vazio (normalizeNumber("") devolve "" — nunca "0", reservado para
  // um número real que se reduz a zero, ex. "000") nunca encontra nenhum candidato no índice
  // (que só contém chaves de números externos realmente utilizáveis) — cai naturalmente no
  // branch de 0 candidatos abaixo, sem precisar de um caso especial: mesma garantia "número
  // ausente ou inutilizável -> ABSENT" pedida, sem exceção dedicada no código.
  const candidates = externalIndex.get(localNumNorm) ?? [];

  if (candidates.length === 0) {
    return {
      classification: "ABSENT",
      matched: null,
      method: METHOD,
      evidence: { external_set_id: externalSetId, numero_local: local.collector_number, numero_normalizado: localNumNorm || null, nome_local: local.name, nome_externo: null, divergencia_de_nome: null },
    };
  }

  if (candidates.length === 1) {
    const candidate = candidates[0];
    const divergenciaDeNome = !isNameCompatible(local.name, candidate.name);
    return {
      classification: "SAFE",
      matched: candidate,
      method: METHOD,
      evidence: {
        external_set_id: externalSetId,
        numero_local: local.collector_number,
        numero_normalizado: localNumNorm,
        numero_externo: candidate.number ?? null,
        nome_local: local.name,
        nome_externo: candidate.name,
        // Indicador de auditoria — nunca usado para decidir a classificação, só para
        // deixar visível quando o nome PT-BR local diverge do nome em inglês da JustTCG
        // (comportamento esperado e normal, não um alerta de erro).
        divergencia_de_nome: divergenciaDeNome,
      },
    };
  }

  // Mais de um candidato compartilha o mesmo número dentro do Set confirmado. Sem
  // collector_total válido, comportamento AMBIGUOUS anterior preservado byte a byte —
  // nunca aplica o desempate, nunca acrescenta campo novo à evidência.
  const candidatosBase = candidates.map((c) => ({ id: c.id, name: c.name, number: c.number ?? null }));

  if (!isValidCollectorTotal(local.collector_total)) {
    return {
      classification: "AMBIGUOUS",
      matched: null,
      method: METHOD,
      evidence: {
        external_set_id: externalSetId,
        numero_local: local.collector_number,
        numero_normalizado: localNumNorm,
        nome_local: local.name,
        candidatos: candidatosBase,
        total_candidatos: candidates.length,
      },
    };
  }

  const collectorTotal = local.collector_total;
  const candidatosAvaliados = candidates.map((c) => {
    const parsed = parseCollectorNumberParts(c.number ?? null);
    const categoriaEstrutural: "EXACT_FULL_IDENTITY" | "INCOMPATIBLE_DENOMINATOR" | "INCOMPLETE_NUMBER" = parsed.denominator === null
      ? "INCOMPLETE_NUMBER"
      : parsed.denominator === collectorTotal
      ? "EXACT_FULL_IDENTITY"
      : "INCOMPATIBLE_DENOMINATOR";
    return {
      id: c.id,
      name: c.name,
      number: c.number ?? null,
      numerador_interpretado: parsed.numerator || null,
      denominador_interpretado: parsed.denominator,
      categoria_estrutural: categoriaEstrutural,
    };
  });
  const candidatosIdentidadeCompleta = candidatosAvaliados.filter((c) => c.categoria_estrutural === "EXACT_FULL_IDENTITY");
  const candidatosDenominadorIncompativel = candidatosAvaliados.filter((c) => c.categoria_estrutural === "INCOMPATIBLE_DENOMINATOR");
  const candidatosNumeroIncompleto = candidatosAvaliados.filter((c) => c.categoria_estrutural === "INCOMPLETE_NUMBER");

  // Só EXATAMENTE 1 candidato com identidade completa (numerador+denominador batendo com
  // collector_total) promove a carta a SAFE — nunca 0, nunca 2+, independentemente de quantos
  // candidatos INCOMPLETE_NUMBER/INCOMPATIBLE_DENOMINATOR sobrarem (fix v2: um candidato sem
  // denominador nunca é declarado falso/incompatível, mas também nunca prevalece sobre uma
  // identidade completa única, nem a substitui quando ela está ausente).
  if (candidatosIdentidadeCompleta.length === 1) {
    const selecionado = candidatosIdentidadeCompleta[0];
    const candidate = candidates.find((c) => c.id === selecionado.id)!;
    const divergenciaDeNome = !isNameCompatible(local.name, candidate.name);
    return {
      classification: "SAFE",
      matched: candidate,
      method: METHOD_IDENTIDADE_COMPLETA,
      evidence: {
        external_set_id: externalSetId,
        numero_local: local.collector_number,
        numero_normalizado: localNumNorm,
        numero_externo: candidate.number ?? null,
        nome_local: local.name,
        nome_externo: candidate.name,
        divergencia_de_nome: divergenciaDeNome,
        local_collector_total: collectorTotal,
        candidatos_avaliados_estrutural: candidatosAvaliados,
        candidatos_identidade_completa: candidatosIdentidadeCompleta,
        candidatos_denominador_incompativel: candidatosDenominadorIncompativel,
        candidatos_numero_incompleto: candidatosNumeroIncompleto,
        candidato_selecionado: { id: candidate.id, name: candidate.name, number: candidate.number ?? null },
        motivo_estrutural: "Identidade completa (numerador+denominador) única e mais específica que candidatos de número incompleto ou de denominador incompatível; único candidato com identidade completa promovido.",
      },
    };
  }

  // 0 ou 2+ candidatos com identidade completa -> continua AMBIGUOUS, nunca ABSENT/NOT_FOUND
  // e nunca promovido só porque sobra um candidato de número incompleto. `candidatos`/
  // `total_candidatos` preservados sem alteração para não quebrar nenhum consumidor
  // pré-existente da evidência; os campos do filtro são só ADITIVOS.
  return {
    classification: "AMBIGUOUS",
    matched: null,
    method: METHOD,
    evidence: {
      external_set_id: externalSetId,
      numero_local: local.collector_number,
      numero_normalizado: localNumNorm,
      nome_local: local.name,
      candidatos: candidatosBase,
      total_candidatos: candidates.length,
      local_collector_total: collectorTotal,
      candidatos_avaliados_estrutural: candidatosAvaliados,
      candidatos_identidade_completa: candidatosIdentidadeCompleta,
      candidatos_denominador_incompativel: candidatosDenominadorIncompativel,
      candidatos_numero_incompleto: candidatosNumeroIncompleto,
      motivo_estrutural: candidatosIdentidadeCompleta.length === 0
        ? "Nenhum candidato com identidade completa (numerador+denominador batendo com collector_total) — permanece ambíguo, mesmo havendo candidato(s) de número incompleto; ausência de denominador nunca promove sozinha."
        : "Mais de um candidato com identidade completa (mesmo denominador batendo com collector_total em 2+ candidatos) — permanece ambíguo.",
    },
  };
}
