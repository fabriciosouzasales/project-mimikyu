/*
===============================================================================
PHASE C-bis — ROTEAMENTO DE CONTEXTO DE EDIÇÃO (Edition Context)

Terceiro eixo de identidade, espelho em memória da Query 2211. Vive em módulo
próprio, e não inline no `index.ts`, por uma razão operacional: `index.ts`
chama `Deno.serve()` no topo e não exporta nada, então uma função declarada lá
não pode ser importada por um teste sem subir um listener HTTP. O teste
`edition-context.test.ts` importa DESTE arquivo e executa o código REAL de
produção — sem réplica. É a mesma disciplina de `services/size-scope.ts` e
`services/database.ts`, e o que impede a classe de defeito em que uma suíte
verde prova a própria cópia em vez de provar a Edge.

A ordem dos eixos é normativa e não é negociável: este eixo consome o RESÍDUO
que Impressão deixou, nunca a assinatura bruta. Um token já consumido por
Impressão não pode ser reinterpretado como contexto de edição — seria contar o
mesmo sinal duas vezes, em dois eixos, e produzir duas identidades para a
mesma carta.

FAIL-CLOSED PARA MAPPING CONHECIDO SEM ROUTING ATIVO. Esta é a regra menos
óbvia e a mais importante deste módulo. Ver 2211:127-144 (subtype) e
2211:171-184 (stamp): quando um token NÃO tem mapping ativo, a 2211 faz uma
SEGUNDA busca, sem o filtro `is_active`, no MESMO universo de escopo. Se o
token é conhecido, o retorno é NEEDS_REVIEW_INACTIVE_EC_MAPPING, na hora, e o
token NÃO volta ao resíduo de Finish.

Deixá-lo voltar seria fail-OPEN: o token viraria acabamento, o Variant Type
seria procurado sobre um resíduo contaminado, e a linha poderia virar VALID
com a identidade errada. É o achado A3 do GATE-A-01, que a 2211 corrigiu do
lado SQL — e que uma Edge ingênua reintroduziria.

TABELA DE PARIDADE — cada ramo desta função e sua âncora na Query 2211

  | Situação                              | Estado                            | 2211     |
  |---------------------------------------|-----------------------------------|----------|
  | Printing não terminal                 | NOT_EVALUATED                     | 86-91    |
  | nenhum token de contexto              | RESOLVED_NO_EDITION_CONTEXT       | 191-196  |
  | token ativo, composição vazia         | NEEDS_REVIEW_INVALID_EC_MAPPING   | 119, 164 |
  | token conhecido, nenhum ativo         | NEEDS_REVIEW_INACTIVE_EC_MAPPING  | 137, 178 |
  | token desconhecido                    | fica no resíduo, eixo prossegue   | 143, 185 |
  | scoped inativo + global ativo         | resolve pelo GLOBAL               | 109, 157 |
  | scoped ativo + global ativo           | scoped vence                      | 115, 160 |
  | job sem escopo + mapping escopado     | fora do universo: desconhecido    | 110-111  |
  | trait inativo na composição           | NEEDS_REVIEW_INACTIVE_EC_TRAIT    | 200-202  |
  | perfil ausente                        | NEEDS_REVIEW_NO_EC_PROFILE        | 207-208  |
  | perfil encontrado porém inativo       | NEEDS_REVIEW_INACTIVE_EC_PROFILE  | 209-212  |
  | resolvido                             | RESOLVED_WITH_EC_PROFILE          | 214      |

Autoridade dos vetores: `database/proposals/2026-09-18-edition-context-axis/
test-vectors/edition-context-axis-vectors.json` — o MESMO arquivo que o runner
SQL 2834 consome.
===============================================================================
*/

import { buildTraitsSignatureKey } from "./database.ts";

// Os OITO estados da Query 2211, literalmente. Um vocabulário divergente aqui
// tornaria os dois lados incomparáveis, e a fixture deixaria de ser autoridade
// única.
export type EditionContextState =
  | "NOT_EVALUATED"
  | "RESOLVED_NO_EDITION_CONTEXT"
  | "RESOLVED_WITH_EC_PROFILE"
  | "NEEDS_REVIEW_INVALID_EC_MAPPING"
  | "NEEDS_REVIEW_INACTIVE_EC_MAPPING"
  | "NEEDS_REVIEW_INACTIVE_EC_TRAIT"
  | "NEEDS_REVIEW_NO_EC_PROFILE"
  | "NEEDS_REVIEW_INACTIVE_EC_PROFILE";

// Só os DOIS estados RESOLVED_* são terminais. Os cinco NEEDS_REVIEW_* e
// NOT_EVALUATED não são. Um conjunto único, exportado, em vez de uma lista
// literal repetida no ponto de uso: com oito estados no vocabulário, uma lista
// duplicada é uma lista que diverge.
export const EDITION_CONTEXT_TERMINAL_STATES: ReadonlySet<EditionContextState> = new Set([
  "RESOLVED_NO_EDITION_CONTEXT",
  "RESOLVED_WITH_EC_PROFILE",
]);

export function isEditionContextResolved(state: EditionContextState): boolean {
  return EDITION_CONTEXT_TERMINAL_STATES.has(state);
}

export type EditionContextIndex = {
  // ATIVOS, separados por escopo — a precedência opera SÓ entre ativos,
  // porque o WHERE de 2211:109/157 filtra is_active ANTES do ORDER BY.
  activeTraitsByScopedToken: Map<string, string[]>;
  activeTraitsByGlobalToken: Map<string, string[]>;
  // CONHECIDOS: ativos E inativos. É o universo da segunda busca de
  // 2211:131-136 / 172-177. Separados por escopo pelo mesmo motivo do par
  // acima: um mapping escopado a OUTRO Set não é "conhecido" aqui.
  knownScopedTokens: Set<string>;
  knownGlobalTokens: Set<string>;
  profileBySignature: Map<string, string>;
  inactiveProfileIds: Set<string>;
  inactiveTraitIds: Set<string>;
};

export type EditionContextRouting = {
  state: EditionContextState;
  editionContextProfileId: string | null;
  editionContextTraitIds: string[];
  residualSubtype: string | null;
  residualStamp: string[] | null;
};

export type EditionContextMappingInput = {
  external_set_id: string | null;
  raw_field: string;
  normalized_token: string;
  traits_signature: string[] | null;
  is_active: boolean;
};

export type EditionContextProfileInput = {
  id: string;
  traits_signature: string[] | null;
  is_active: boolean;
};

export type EditionContextTraitInput = {
  id: string;
  is_active: boolean;
};

function ecTokenKey(rawField: string, normalizedToken: string): string {
  return `${rawField}|${normalizedToken}`;
}

export function buildEditionContextIndex(
  mappings: readonly EditionContextMappingInput[],
  profiles: readonly EditionContextProfileInput[],
  traits: readonly EditionContextTraitInput[],
  externalSetId: string | null,
): EditionContextIndex {
  const activeTraitsByScopedToken = new Map<string, string[]>();
  const activeTraitsByGlobalToken = new Map<string, string[]>();
  const knownScopedTokens = new Set<string>();
  const knownGlobalTokens = new Set<string>();

  for (const m of mappings) {
    // UNIVERSO DE ESCOPO (2211:110-111): { global } ∪ { escopado a ESTE Set,
    // e só quando o job TEM escopo }. Um mapping de outro Set é descartado
    // ANTES de qualquer outra consideração — nem ativo, nem conhecido.
    const isGlobal = m.external_set_id === null;
    const isThisScope = externalSetId !== null && m.external_set_id === externalSetId;
    if (!isGlobal && !isThisScope) continue;

    const key = ecTokenKey(m.raw_field, m.normalized_token);

    // CONHECIDO recebe ativos E inativos. É o que permite distinguir "token
    // desconhecido" (volta ao resíduo) de "token conhecido porém sem routing
    // ativo" (fail-closed). Mesma disciplina de buildPrintingIndex.knownTokens.
    if (isGlobal) knownGlobalTokens.add(key);
    else knownScopedTokens.add(key);

    if (!m.is_active) continue;

    const sig = (m.traits_signature ?? []).map((id) => String(id));
    if (isGlobal) activeTraitsByGlobalToken.set(key, sig);
    else activeTraitsByScopedToken.set(key, sig);
  }

  const profileBySignature = new Map<string, string>();
  const inactiveProfileIds = new Set<string>();
  for (const p of profiles) {
    // Sem filtro de is_active, como 2211:204-206: o perfil é ENCONTRADO por
    // assinatura e só depois recusado, para que o estado seja "perfil
    // inativo" e não "perfil inexistente".
    profileBySignature.set(buildTraitsSignatureKey(p.traits_signature), p.id);
    if (!p.is_active) inactiveProfileIds.add(String(p.id));
  }

  const inactiveTraitIds = new Set<string>();
  for (const t of traits) {
    if (!t.is_active) inactiveTraitIds.add(String(t.id).toLowerCase());
  }

  return {
    activeTraitsByScopedToken,
    activeTraitsByGlobalToken,
    knownScopedTokens,
    knownGlobalTokens,
    profileBySignature,
    inactiveProfileIds,
    inactiveTraitIds,
  };
}

/**
 * Roteia o terceiro eixo sobre o resíduo PÓS-IMPRESSÃO.
 *
 * `printingTerminal` é o gate de 2211:86-91 e faz parte DESTA função de
 * propósito: se ele vivesse no chamador, o estado NOT_EVALUATED seria uma
 * decisão inline no `index.ts`, fora do alcance de teste comportamental — e o
 * vetor E16 voltaria a ser provado por uma cópia. Aqui ele é executado pelo
 * mesmo código que a produção executa.
 */
export function routeEditionContext(
  index: EditionContextIndex,
  printingTerminal: boolean,
  residualSubtype: string | null,
  residualStampSorted: string[] | null,
): EditionContextRouting {
  // RETORNO ANTECIPADO: devolve o resíduo PÓS-PRINTING **INTACTO**.
  // 2211:122/140/167/182 devolvem p.residual_subtype / p.residual_stamp, e não
  // as variáveis parciais do eixo 3. A diferença é observável: um token já
  // consumido antes do aborto NÃO some do resíduo devolvido.
  const untouched = (state: EditionContextState): EditionContextRouting => ({
    state,
    editionContextProfileId: null,
    editionContextTraitIds: [],
    residualSubtype,
    residualStamp: residualStampSorted,
  });

  // 2211:86-91 — o eixo 3 nem roda quando Impressão não é terminal. O resíduo
  // que chegaria ao Variant Type foi derivado de uma premissa que não se
  // sustenta; avaliar contexto sobre ele produziria uma conclusão correta a
  // partir de premissa inválida.
  if (!printingTerminal) return untouched("NOT_EVALUATED");

  const traitIds: string[] = [];

  // Precedência escopado > global, UM nível, sem cascata — e SÓ entre ativos,
  // espelhando o ORDER BY de 2211:115/160 sobre um WHERE que já filtrou
  // is_active.
  const lookupActive = (key: string): string[] | undefined =>
    index.activeTraitsByScopedToken.get(key) ?? index.activeTraitsByGlobalToken.get(key);

  const isKnown = (key: string): boolean =>
    index.knownScopedTokens.has(key) || index.knownGlobalTokens.has(key);

  let outSubtype = residualSubtype;
  if (residualSubtype !== null && residualSubtype.trim() !== "") {
    const key = ecTokenKey("subtype", residualSubtype);
    const sig = lookupActive(key);
    if (sig !== undefined) {
      // COMPOSIÇÃO EFETIVA VAZIA (2211:119-124). Mapping ATIVO sem nenhum
      // trait não é "sem contexto": o token TEM routing, e o routing está
      // quebrado. Mesmo princípio da correção L-1 de routePrinting.
      if (sig.length === 0) return untouched("NEEDS_REVIEW_INVALID_EC_MAPPING");
      traitIds.push(...sig);
      outSubtype = null;
    } else if (isKnown(key)) {
      return untouched("NEEDS_REVIEW_INACTIVE_EC_MAPPING");
    }
    // Token DESCONHECIDO: permanece no resíduo de Finish, e o eixo segue.
  }

  const outStampTokens: string[] = [];
  for (const token of residualStampSorted ?? []) {
    const key = ecTokenKey("stamp", token);
    const sig = lookupActive(key);
    if (sig !== undefined) {
      if (sig.length === 0) return untouched("NEEDS_REVIEW_INVALID_EC_MAPPING");
      traitIds.push(...sig);
    } else if (isKnown(key)) {
      // RETORNO IMEDIATO DE DENTRO DO LOOP, como 2211:180-183. Os tokens
      // seguintes NÃO são avaliados. Marcar um flag e continuar produziria
      // uma composição parcial que a 2211 nunca produz.
      return untouched("NEEDS_REVIEW_INACTIVE_EC_MAPPING");
    } else {
      outStampTokens.push(token);
    }
  }
  // 2211:189 ordena o resíduo remanescente.
  const outStamp = outStampTokens.length > 0 ? [...outStampTokens].sort() : null;

  if (traitIds.length === 0) {
    return {
      state: "RESOLVED_NO_EDITION_CONTEXT",
      editionContextProfileId: null,
      editionContextTraitIds: [],
      residualSubtype: outSubtype,
      residualStamp: outStamp,
    };
  }

  // 2211:198 — DISTINCT + ORDER BY. buildTraitsSignatureKey é
  // Set + lowercase + sort + join, equivalente por construção.
  const signatureKey = buildTraitsSignatureKey(traitIds);
  const signature = signatureKey.length > 0 ? signatureKey.split(",") : [];

  // RETORNO FINAL: devolve o resíduo PÓS-DOIS-EIXOS (2211:218-220).
  const final = (
    state: EditionContextState,
    profileId: string | null,
  ): EditionContextRouting => ({
    state,
    editionContextProfileId: profileId,
    editionContextTraitIds: signature,
    residualSubtype: outSubtype,
    residualStamp: outStamp,
  });

  // Trait inativo ANTES da busca de perfil (2211:200-202). A ordem importa: o
  // perfil pode existir, e ainda assim o estado é INACTIVE_EC_TRAIT.
  if (signature.some((id) => index.inactiveTraitIds.has(id))) {
    return final("NEEDS_REVIEW_INACTIVE_EC_TRAIT", null);
  }

  const profileId = index.profileBySignature.get(signatureKey);

  // JAMAIS criar Perfil durante a importação (2211:208).
  if (profileId === undefined) return final("NEEDS_REVIEW_NO_EC_PROFILE", null);

  // 2211:209-212 — encontrado por assinatura, recusado por inatividade, e o id
  // é zerado explicitamente.
  if (index.inactiveProfileIds.has(profileId)) {
    return final("NEEDS_REVIEW_INACTIVE_EC_PROFILE", null);
  }

  return final("RESOLVED_WITH_EC_PROFILE", profileId);
}
