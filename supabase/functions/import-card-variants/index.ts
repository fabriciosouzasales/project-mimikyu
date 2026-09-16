/*
Project Mimikyu
Edge Function: import-card-variants
Incremento 2 do bloco Card Variant (ADR-028) — 2026-08-15.

Processador de importação de Card Variant: recebe um Card Set MMKYU,
resolve o external_set_id do dataset-fonte da TCGdex (github.com/tcgdex/
cards-database) via card_set_external_reference já gravada por Importar
Cartas, busca os arquivos de carta do Set inteiro (não carta a carta na
API pública), correlaciona cada Card externa com a Card MMKYU via
card_external_reference, extrai todas as combinações variants[], resolve
o mapeamento externo -> card_variant_type (Query 2140) e grava somente em
catalog_variant_import_row (staging) — nunca em card_variant (Princípio
da Fonte Canônica, ADR-024). Não cria RPC de confirmação, não tem UI,
não infere vintage/is_default/variant_order.

Diferença deliberada frente a import-catalog-cards: não existe ainda uma
tela/RPC que pré-crie o job com external_set_id resolvido (CV-02 — sem
tela dedicada no V1). Por isso esta function recebe { card_set_id } (não
{ job_id }) e cria o próprio catalog_variant_import_job internamente,
já em PROCESSING, resolvendo external_set_id antes do INSERT.

Fronteira de identidade — mesmo padrão já em produção em
import-catalog-cards/revalidate-catalog-import-rows (Finding 1 da
auditoria de segurança do Catálogo Editorial, 2026-08-13): verify_jwt=true
(supabase/config.toml) garante um JWT assinado válido, mas não basta
sozinho (pode ser só a anon key, sem usuário nenhum por trás). Um segundo
client, escopado pelo JWT recebido no cabeçalho Authorization, chama
auth.getUser() para confirmar uma sessão real e rpc('is_admin') para
confirmar o papel administrativo — só então o código segue para o client
de service role (`supabase`, abaixo), que nunca recebe o JWT do chamador.

Fonte dos arquivos de carta: TypeScript, não JSON (confirmado ao vivo
nesta frente). Nunca executamos esse conteúdo (eval/Function seria rodar
código de terceiro não confiável com service role — inaceitável) — ver
services/github-source.ts para o extrator estrutural por regex/
profundidade de colchetes, limitado aos 4 campos que interessam.
*/

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import {
  buildPrintingProfileKeyPart,
  buildTraitsSignatureKey,
  createVariantJobProcessing,
  failVariantJob,
  findAssetSourceByCode,
  findCardSetExternalReference,
  findCardSetWithGame,
  finalizeVariantJobStaged,
  insertVariantImportRows,
  listActivePrintingProfiles,
  listCardExternalReferencesMap,
  listExistingCardVariantsMap,
  listPrintingExternalMappings,
  listPrintingTraits,
  listVariantTypeExternalMappings,
  buildVariantComboKey,
  updateVariantJobProgressStep,
} from "./services/database.ts";
import { resolveSetSerieName } from "./services/tcgdex.ts";
import {
  deriveLocalIdFromFilename,
  extractVariantsFromSource,
  fetchCardFileSource,
  listSetCardFiles,
} from "./services/github-source.ts";
import { normalizeExternalCatalogValue } from "../_shared/catalog-normalization/mod.ts";
import { classifyVariantSize } from "./services/size-scope.ts";
import type { ExternalVariantCombo, RequestBody, ResolvedVariantRow } from "./types.ts";

const ASSET_SOURCE_CODE = "TCGDEX";
// Mesmo espírito de CARD_DETAIL_BATCH_SIZE (import-catalog-cards): lotes
// de concorrência limitada contra raw.githubusercontent.com, que não tem
// rate limit observado mas ainda assim não deve ser martelado sem limite.
const CARD_FILE_BATCH_SIZE = 10;

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Client de serviço — único usado para ler/escrever catalog_variant_import_
// job/row e os catálogos de apoio. Nunca recebe o JWT do chamador (ver
// Fronteira de identidade acima).
const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

async function processInBatches<T, R>(
  items: T[],
  batchSize: number,
  processor: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
  const results: R[] = [];
  for (let index = 0; index < items.length; index += batchSize) {
    const batch = items.slice(index, index + batchSize);
    const batchResults = await Promise.all(batch.map((item, offset) => processor(item, index + offset)));
    results.push(...batchResults);
  }
  return results;
}

// Normaliza e ORDENA o array de stamp — mesma disciplina exigida pela
// Query 2140 (v1.1) para normalized_stamp: duas combinações com os mesmos
// stamps em ordem diferente na fonte precisam produzir a mesma chave.
function normalizeAndSortStamp(stamp: string[] | null): string[] | null {
  if (!stamp || stamp.length === 0) return null;
  return [...stamp].map((s) => normalizeExternalCatalogValue(s)).sort();
}

type CardFileResult = {
  externalCardId: string;
  cardId: string | null;
  combos: ExternalVariantCombo[];
  fetchError: string | null;
};

// =====================================================================
// PHASE C — ROTEAMENTO DE IMPRESSÃO (Printing)
//
// Espelho, em memória, do contrato que
// internal.compute_variant_residual_signature() (Query 2176 v1.1) já
// aplica no banco. As duas implementações precisam concordar: a Edge
// produz o staging, e a RPC de ratificação reavalia o MESMO dado depois.
// Divergência entre elas apareceria como linha que muda de estado sem
// nenhuma decisão editorial no meio.
//
// Só `subtype` e `stamp` são elegíveis. `type` e `foil` são ACABAMENTO e
// nunca viram Impressão — é a fronteira que impede o modelo de Printing
// de reabsorver a taxonomia que ele existe para simplificar.
// =====================================================================

type PrintingState = "RESOLVED_NO_PRINTING" | "RESOLVED_WITH_PROFILE" | "UNRESOLVED";

type PrintingIndex = {
  // chave -> assinatura de traits do mapping ATIVO daquele token
  activeTraitsByToken: Map<string, string[]>;
  // todo token que o catálogo CONHECE, ativo ou historicamente inativo
  knownTokens: Set<string>;
  // assinatura canônica de traits -> id do Print Profile ATIVO
  profileBySignature: Map<string, string>;
  // traits do Game que estão DESATIVADOS (em minúsculas canônicas)
  inactiveTraitIds: Set<string>;
};

type PrintingRouting = {
  state: PrintingState;
  printingProfileId: string | null;
  residualSubtype: string | null;
  residualStamp: string[] | null;
  // Diagnóstico, não identidade: por que ficou UNRESOLVED. Os quatro
  // motivos espelham os quatro estados de recusa da Query 2176 que a Edge
  // consegue observar em dado já comitado.
  unresolvedReason:
    | "INACTIVE_MAPPING"
    | "INVALID_PRINTING_MAPPING"
    | "INACTIVE_TRAIT"
    | "NO_EXACT_PROFILE"
    | null;
};

function printingTokenKey(
  gameId: string,
  assetSourceId: string,
  rawField: string,
  normalizedToken: string,
): string {
  return `${gameId}|${assetSourceId}|${rawField}|${normalizedToken}`;
}

function buildPrintingIndex(
  mappings: Array<{
    game_id: string;
    asset_source_id: string;
    raw_field: string;
    normalized_token: string;
    traits_signature: string[] | null;
    is_active: boolean;
  }>,
  profiles: Array<{ id: string; traits_signature: string[] | null }>,
  traits: Array<{ id: string; is_active: boolean }>,
): PrintingIndex {
  const activeTraitsByToken = new Map<string, string[]>();
  const knownTokens = new Set<string>();

  for (const mapping of mappings) {
    const key = printingTokenKey(
      mapping.game_id,
      mapping.asset_source_id,
      mapping.raw_field,
      mapping.normalized_token,
    );
    // knownTokens recebe ativos E inativos: é o que permite distinguir
    // "token desconhecido" (volta ao residual) de "token conhecido porém
    // sem mapping ativo" (consumido, mas Printing não resolvido).
    knownTokens.add(key);

    if (mapping.is_active) {
      activeTraitsByToken.set(key, (mapping.traits_signature ?? []).map((id) => String(id)));
    }
  }

  const profileBySignature = new Map<string, string>();
  for (const profile of profiles) {
    profileBySignature.set(buildTraitsSignatureKey(profile.traits_signature), profile.id);
  }

  // Guardamos os INATIVOS, não os ativos: a pergunta do roteamento é
  // "algum trait desta composição está desativado?", e responder isso
  // contra o conjunto dos inativos é uma checagem direta. Minúsculas
  // canônicas, mesma disciplina de buildTraitsSignatureKey.
  const inactiveTraitIds = new Set<string>();
  for (const trait of traits) {
    if (!trait.is_active) inactiveTraitIds.add(String(trait.id).toLowerCase());
  }

  return { activeTraitsByToken, knownTokens, profileBySignature, inactiveTraitIds };
}

// Consome os tokens de Impressão da assinatura bruta e devolve o resíduo
// de acabamento + o estado do eixo de Impressão.
//
// Regra central, e a razão de o token consumido NUNCA voltar ao resíduo
// mesmo quando o Printing não resolve: um token que o catálogo conhece
// pertence ao eixo de Impressão por decisão editorial. Devolvê-lo ao
// resíduo o reclassificaria como acabamento e produziria um Variant Type
// composto — exatamente a explosão combinatória que o Model C2 elimina.
// A Seção S8 do harness prova isso do lado SQL.
function routePrinting(
  index: PrintingIndex,
  gameId: string,
  assetSourceId: string,
  normalizedSubtype: string | null,
  normalizedStampSorted: string[] | null,
): PrintingRouting {
  const traitIds: string[] = [];
  let sawInactiveOnlyToken = false;

  // --- subtype (0 ou 1 token) ---
  let residualSubtype = normalizedSubtype;
  if (normalizedSubtype !== null) {
    const key = printingTokenKey(gameId, assetSourceId, "subtype", normalizedSubtype);
    const activeTraits = index.activeTraitsByToken.get(key);

    if (activeTraits !== undefined) {
      residualSubtype = null;
      // COMPOSIÇÃO EFETIVA VAZIA (correção L-1). Mapping ATIVO sem nenhum
      // trait não é "sem Impressão": o token TEM routing, e o routing está
      // quebrado. A Query 2176 devolve
      // NEEDS_REVIEW_INVALID_PRINTING_MAPPING e retorna na hora; aqui é o
      // mesmo. Hoje isso é inalcançável — o GUARD C da Query 2174 levanta
      // CARD_PRINTING_EXTERNAL_MAPPING_EMPTY_COMPOSITION no COMMIT, e a
      // Edge só lê dado comitado —, mas a Edge não deve DEPENDER de uma
      // invariante de outro sistema para não afirmar uma bobagem.
      if (activeTraits.length === 0) {
        return {
          state: "UNRESOLVED",
          printingProfileId: null,
          residualSubtype,
          residualStamp: null,
          unresolvedReason: "INVALID_PRINTING_MAPPING",
        };
      }
      traitIds.push(...activeTraits);
    } else if (index.knownTokens.has(key)) {
      residualSubtype = null;
      sawInactiveOnlyToken = true;
    }
    // token nunca conhecido: permanece intocado no resíduo.
  }

  // --- stamp (0..N tokens) ---
  const residualStampTokens: string[] = [];
  for (const token of normalizedStampSorted ?? []) {
    const key = printingTokenKey(gameId, assetSourceId, "stamp", token);
    const activeTraits = index.activeTraitsByToken.get(key);

    if (activeTraits !== undefined) {
      // Mesma regra do ramo de subtype (correção L-1).
      if (activeTraits.length === 0) {
        return {
          state: "UNRESOLVED",
          printingProfileId: null,
          residualSubtype,
          residualStamp: null,
          unresolvedReason: "INVALID_PRINTING_MAPPING",
        };
      }
      traitIds.push(...activeTraits);
    } else if (index.knownTokens.has(key)) {
      sawInactiveOnlyToken = true;
    } else {
      residualStampTokens.push(token);
    }
  }
  const residualStamp = residualStampTokens.length > 0 ? residualStampTokens : null;

  // Token conhecido sem mapping ativo tem precedência: o eixo de
  // Impressão está pendente de decisão editorial, e nenhum perfil
  // derivado dos OUTROS tokens descreveria a carta corretamente.
  if (sawInactiveOnlyToken) {
    return {
      state: "UNRESOLVED",
      printingProfileId: null,
      residualSubtype,
      residualStamp,
      unresolvedReason: "INACTIVE_MAPPING",
    };
  }

  if (traitIds.length === 0) {
    return {
      state: "RESOLVED_NO_PRINTING",
      printingProfileId: null,
      residualSubtype,
      residualStamp,
      unresolvedReason: null,
    };
  }

  // TRAIT INATIVO (correção C-1) — avaliado DEPOIS de montar a composição
  // e ANTES de procurar o perfil, exatamente na posição em que a Query
  // 2176 avalia NEEDS_REVIEW_INACTIVE_TRAIT.
  //
  // A ordem importa e não é estética: um perfil ATIVO cuja assinatura
  // contenha um trait DESATIVADO continua existindo e continua casando
  // por igualdade exata. Se a busca viesse primeiro, a Edge resolveria
  // com perfil e marcaria VALID justamente a linha que o banco recusa —
  // e nenhum guard impede esse estado, porque desativar um trait não
  // desativa os perfis que o contêm.
  //
  // Trait inativo NUNCA é tratado como se o trait não existisse: é uma
  // decisão editorial pendente, e o desfecho é chamar o editor.
  if (traitIds.some((id) => index.inactiveTraitIds.has(String(id).toLowerCase()))) {
    return {
      state: "UNRESOLVED",
      printingProfileId: null,
      residualSubtype,
      residualStamp,
      unresolvedReason: "INACTIVE_TRAIT",
    };
  }

  // Perfil por conjunto EXATAMENTE igual — mesma cardinalidade, mesmos
  // ids. Nada de subset/superset: um perfil que contém os traits da
  // carta mais um outro descreve OUTRA impressão.
  const profileId = index.profileBySignature.get(buildTraitsSignatureKey(traitIds)) ?? null;

  if (profileId === null) {
    return {
      state: "UNRESOLVED",
      printingProfileId: null,
      residualSubtype,
      residualStamp,
      unresolvedReason: "NO_EXACT_PROFILE",
    };
  }

  return {
    state: "RESOLVED_WITH_PROFILE",
    printingProfileId: profileId,
    residualSubtype,
    residualStamp,
    unresolvedReason: null,
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ success: false, error: "METHOD_NOT_ALLOWED" }, { status: 405, headers: { Allow: "POST" } });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return Response.json({ success: false, error: "MISSING_AUTHORIZATION" }, { status: 401 });
  }

  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) {
    console.error("IMPORT_CARD_VARIANTS_INVALID_USER_SESSION:", userError);
    return Response.json({ success: false, error: "INVALID_USER_SESSION" }, { status: 401 });
  }

  const { data: isAdminResult, error: isAdminError } = await userClient.rpc("is_admin");
  if (isAdminError || isAdminResult !== true) {
    console.error("IMPORT_CARD_VARIANTS_FORBIDDEN_NOT_ADMIN:", isAdminError);
    return Response.json({ success: false, error: "FORBIDDEN_NOT_ADMIN" }, { status: 403 });
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return Response.json({ success: false, error: "INVALID_JSON" }, { status: 400 });
  }

  const cardSetId = body.card_set_id?.trim();
  if (!cardSetId) {
    return Response.json({ success: false, error: "CARD_SET_ID_REQUIRED" }, { status: 400 });
  }

  let jobId: string | null = null;

  try {
    const cardSet = await findCardSetWithGame(supabase, cardSetId);
    if (!cardSet) {
      return Response.json({ success: false, error: "CARD_SET_NOT_FOUND" }, { status: 404 });
    }

    const assetSource = await findAssetSourceByCode(supabase, ASSET_SOURCE_CODE);
    if (!assetSource) throw new Error(`ASSET_SOURCE_NOT_FOUND: ${ASSET_SOURCE_CODE}`);

    // Importar Variantes pressupõe Importar Cartas já concluído para o
    // Card Set — a referência externa precisa existir antes de qualquer
    // job ser criado (catalog_variant_import_job.external_set_id é NOT
    // NULL, não há valor a gravar sem ela).
    const externalReference = await findCardSetExternalReference(supabase, cardSetId, assetSource.id);
    if (!externalReference?.external_set_id) {
      return Response.json(
        { success: false, error: "CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND: rode Importar Cartas para este Card Set antes de Importar Variantes." },
        { status: 409 },
      );
    }
    const externalSetId = externalReference.external_set_id;

    const { job, alreadyActive } = await createVariantJobProcessing(supabase, {
      cardSetId,
      externalSetId,
      initiatedBy: userData.user.id,
    });
    if (alreadyActive || !job) {
      return Response.json(
        { success: false, error: "JOB_ALREADY_ACTIVE_FOR_CARD_SET: já existe uma importação de variantes em andamento ou em staging para este Card Set." },
        { status: 409 },
      );
    }

    // A partir daqui o job já existe e está em PROCESSING: qualquer saída
    // de erro passa por failVariantJob(), nunca deixa o job preso.
    jobId = job.id;

    const setSerieName = await resolveSetSerieName(externalSetId);

    await updateVariantJobProgressStep(supabase, jobId, "LISTING_SOURCE_FILES");
    const cardFiles = await listSetCardFiles(setSerieName.serieName, setSerieName.name);
    if (cardFiles.length === 0) {
      throw new Error("GITHUB_SOURCE_SET_FOLDER_EMPTY_OR_NOT_FOUND");
    }

    await updateVariantJobProgressStep(supabase, jobId, "FETCHING_CARD_FILES");
    // PRELOAD — número FIXO de queries por job, nunca por linha. Os dois
    // datasets de Printing entram aqui, no mesmo Promise.all dos que já
    // existiam: o roteamento inteiro acontece depois, em memória.
    const [
      cardExternalReferences,
      variantTypeMaps,
      printingMappings,
      printingProfiles,
      printingTraits,
    ] = await Promise
      .all([
        listCardExternalReferencesMap(supabase, assetSource.id, externalSetId),
        listVariantTypeExternalMappings(supabase, cardSet.game_id, assetSource.id, externalSetId),
        listPrintingExternalMappings(supabase, cardSet.game_id, assetSource.id),
        listActivePrintingProfiles(supabase, cardSet.game_id),
        listPrintingTraits(supabase, cardSet.game_id),
      ]);

    const printingIndex = buildPrintingIndex(printingMappings, printingProfiles, printingTraits);

    // Falha de UM arquivo (rede, 404, extração malformada) vira um
    // registro isolado com fetchError — nunca derruba o Set inteiro.
    const fileResults = await processInBatches<typeof cardFiles[number], CardFileResult>(
      cardFiles,
      CARD_FILE_BATCH_SIZE,
      async (file) => {
        const localId = deriveLocalIdFromFilename(file.name);
        const externalCardId = `${externalSetId}-${localId}`;
        const cardId = cardExternalReferences.get(externalCardId.toUpperCase()) ?? null;

        try {
          const source = await fetchCardFileSource(file.downloadUrl);
          const combos = extractVariantsFromSource(source);
          return { externalCardId, cardId, combos, fetchError: null };
        } catch (error) {
          const message = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
          console.error(`GITHUB_SOURCE_FETCH_FAILED ${externalCardId}:`, message);
          return { externalCardId, cardId, combos: [], fetchError: `GITHUB_SOURCE_FETCH_FAILED: ${message}` };
        }
      },
    );

    await updateVariantJobProgressStep(supabase, jobId, "CORRELATING_CARDS");

    const uncorrelated: string[] = [];
    const fetchFailed: string[] = [];
    const correlated = fileResults.filter((result) => {
      if (result.fetchError) {
        fetchFailed.push(result.externalCardId);
        return false;
      }
      if (!result.cardId) {
        uncorrelated.push(result.externalCardId);
        return false;
      }
      return true;
    });

    const correlatedCardIds = Array.from(new Set(correlated.map((r) => r.cardId as string)));
    const existingVariantsByCardAndType = await listExistingCardVariantsMap(supabase, correlatedCardIds);

    await updateVariantJobProgressStep(supabase, jobId, "RESOLVING_VARIANT_MAPPING");

    const resolvedRows: ResolvedVariantRow[] = [];
    const seenComboByCard = new Set<string>();
    let duplicateResolvedSkipped = 0;
    let printingUnresolvedRows = 0;
    let printingWithProfileRows = 0;
    let sizeOutOfScopeRows = 0;
    let sizeUnsupportedRows = 0;

    for (const result of correlated) {
      const cardId = result.cardId as string;

      for (const combo of result.combos) {
        const normalizedType = normalizeExternalCatalogValue(combo.type);
        const normalizedFoil = combo.foil ? normalizeExternalCatalogValue(combo.foil) : null;
        const normalizedSubtype = combo.subtype ? normalizeExternalCatalogValue(combo.subtype) : null;
        const normalizedStamp = normalizeAndSortStamp(combo.stamp);

        // Assinatura BRUTA — preservada para o dedupe de linhas sem
        // identidade canônica (ver abaixo) e para o diagnóstico editorial.
        const rawComboKey = buildVariantComboKey(normalizedType, normalizedFoil, normalizedSubtype, normalizedStamp);

        // raw_data preserva `size` para TODA linha, inclusive as de fluxo
        // legado (null explícito) — é a evidência que o guard server-side da
        // Query 2198 lê. `->> 'size' IS NULL` cobre chave ausente E JSON
        // null, então gravar null é bit a bit equivalente ao comportamento
        // anterior para o motor.
        const rawData: Record<string, unknown> = {
          type: combo.type,
          foil: combo.foil,
          subtype: combo.subtype,
          stamp: combo.stamp,
          size: combo.size ?? null,
        };

        // ===============================================================
        // GATE DE ESCOPO POR TAMANHO — ANTES de qualquer roteamento.
        //
        // Precede deliberadamente routePrinting E o dedupe. Uma linha fora
        // de escopo não pode consumir mapeamentos de Impressão, não pode
        // adquirir identidade canônica e não pode disputar espaço de
        // dedupe com linhas em escopo. Espelha a Query 2198, que fecha o
        // mesmo portão no servidor — aqui é economia e clareza editorial,
        // lá é a garantia.
        //
        // DEDUPE EM ESPAÇO PRÓPRIO (`X|`), com o size normalizado na
        // chave: sem ele, uma combinação `size` desconhecido colidiria com
        // a sua gêmea sem `size` e uma das duas sumiria silenciosamente —
        // exatamente o modo de falha que originou este incidente.
        // ===============================================================
        const sizeScope = classifyVariantSize(combo.size);

        if (sizeScope.kind !== "IN_SCOPE") {
          const sizeDedupeKey = `X|${cardId}|${rawComboKey}|${sizeScope.normalizedSize}`;
          if (seenComboByCard.has(sizeDedupeKey)) {
            duplicateResolvedSkipped++;
            continue;
          }
          seenComboByCard.add(sizeDedupeKey);

          if (sizeScope.kind === "OUT_OF_SCOPE") {
            // JUMBO — fora do escopo do sistema. NÃO é erro de importação e
            // NÃO é pendência editorial: decision_status SKIPPED tira a
            // linha da fila de decisão, e persistence_status fica no
            // default PENDING do banco (a confirmação a trata como
            // UNCHANGED/CONTINUE, auditado LIVE).
            sizeOutOfScopeRows++;
            resolvedRows.push({
              card_id: cardId,
              raw_data: rawData,
              normalized_data: { size: sizeScope.normalizedSize, skip_reason: sizeScope.skipReason },
              validation_status: "INVALID",
              match_status: "NEW",
              decision_status: "SKIPPED",
              matched_variant_id: null,
            });
          } else {
            // Valor desconhecido — fail closed. Vira revisão HUMANA, não
            // pendência de mapeamento: não existe "mapeamento de tamanho",
            // e oferecer um seria converter uma decisão de escopo em
            // tradução de vocabulário.
            sizeUnsupportedRows++;
            resolvedRows.push({
              card_id: cardId,
              raw_data: rawData,
              normalized_data: { size: sizeScope.normalizedSize, review_reason: sizeScope.reviewReason },
              validation_status: "NEEDS_REVIEW",
              match_status: "NEW",
              decision_status: "PENDING",
              matched_variant_id: null,
            });
          }
          continue;
        }

        // EIXO DE IMPRESSÃO primeiro: ele consome os tokens que lhe
        // pertencem e só o RESÍDUO é oferecido ao Variant Type.
        const printing = routePrinting(
          printingIndex,
          cardSet.game_id,
          assetSource.id,
          normalizedSubtype,
          normalizedStamp,
        );

        const residualComboKey = buildVariantComboKey(
          normalizedType,
          normalizedFoil,
          printing.residualSubtype,
          printing.residualStamp,
        );
        // >>> PRECEDÊNCIA COM ESCOPO (GATE-A-REV-01) <<<
        // scoped > global > NEEDS_REVIEW. UM nível, sem cascata.
        // `??` e nao `||`: so null/undefined caem para o fallback; um id
        // valido nunca e descartado. Precedencia identica a do SQL
        // (internal.lookup_variant_type_for_row) por construcao.
        const variantTypeId = variantTypeMaps.scopedMap.get(residualComboKey)
          ?? variantTypeMaps.globalMap.get(residualComboKey)
          ?? null;

        const printingResolved = printing.state !== "UNRESOLVED";
        // VALID exige os DOIS eixos. Variant Type resolvido sozinho não
        // basta: sem Impressão decidida, o resíduo não é identidade
        // canônica confiável.
        const isValid = printingResolved && variantTypeId !== null;

        // ---------------------------------------------------------------
        // DEDUPE — dois espaços, porque são duas naturezas diferentes.
        //
        // R (resolvida): a linha TEM identidade canônica completa, e essa
        // identidade INCLUI o perfil. Deduplicar só por card+type juntaria
        // STANDARD-sem-perfil com STANDARD-SHADOWLESS — duas variantes
        // REAIS e distintas — e descartaria uma delas silenciosamente.
        //
        // U (não resolvida): não há identidade canônica em que confiar. A
        // única chave honesta é a combinação BRUTA inteira: duas
        // combinações diferentes que ambas falham precisam virar duas
        // linhas de revisão, cada uma com a sua evidência.
        //
        // LIÇÃO PRESERVADA (correção de 2026-08-15, incidente real em
        // SV8.5): Lugia ex 082/131 trazia a MESMA combinação
        // normal+set-logo duas vezes na fonte. Enquanto o dedupe só cobria
        // combinações JÁ resolvidas, as duas viravam linhas NEEDS_REVIEW
        // idênticas. O INSERT passava (o índice parcial da Query 2138 só
        // cobre variant_type_id NOT NULL), mas a resolução posterior do
        // mapeamento (Query 2150) tentava gravar o mesmo variant_type_id
        // nas duas — job_id+card_id repetidos — e derrubava a chamada
        // inteira com erro cru de Postgres. Uma combinação repetida na
        // própria fonte nunca deve virar duas linhas de staging, resolvida
        // ou não. A regra sobrevive intacta: combinação idêntica repetida
        // cai na MESMA chave, nos dois espaços.
        // ---------------------------------------------------------------
        const dedupeKey = isValid
          ? `R|${cardId}|${variantTypeId}|${buildPrintingProfileKeyPart(printing.printingProfileId)}`
          : `U|${cardId}|${rawComboKey}`;

        if (seenComboByCard.has(dedupeKey)) {
          duplicateResolvedSkipped++;
          continue;
        }
        seenComboByCard.add(dedupeKey);

        // MATCHING TRIPLO — só linhas com identidade canônica completa
        // participam. Uma linha com Impressão pendente não tem perfil
        // definido, e casá-la contra uma variante existente afirmaria uma
        // identidade que ainda não foi decidida.
        const matchedVariantId = isValid
          ? existingVariantsByCardAndType.get(
            `${cardId}|${variantTypeId}|${buildPrintingProfileKeyPart(printing.printingProfileId)}`,
          ) ?? null
          : null;

        // TRI-STATE de normalized_data — os três desfechos da Query 2181
        // v1.2, na mesma ordem (correção C-3).
        //
        //   A. Printing resolvido + Variant Type resolvido
        //      -> as duas chaves presentes, VALID.
        //
        //   B. Printing resolvido + Variant Type NÃO resolvido
        //      -> só printing_profile_id (JSON null ou UUID), NEEDS_REVIEW.
        //      O perfil resolvido permanece explícito; o variant_type_id
        //      é que fica de fora.
        //
        //   C. Printing NÃO resolvido
        //      -> AS DUAS chaves ausentes, NEEDS_REVIEW.
        //
        // O porquê de C ser mais severo do que parece à primeira vista: o
        // eixo de Impressão consome os tokens que lhe pertencem ANTES de
        // o resíduo ser oferecido ao Variant Type. Se a Impressão não
        // resolveu, o resíduo foi derivado de uma premissa que não se
        // sustenta, e o variant_type_id encontrado a partir dele é uma
        // conclusão correta tirada de premissa inválida. Gravá-lo seria
        // preservar a conclusão e jogar fora a dúvida.
        //
        // Isto NÃO é hipótese remota: quando um token é consumido por um
        // mapping inativo, ele SAI do resíduo, e o resíduo reduzido
        // (NORMAL|||, HOLOFOIL|||) casa com os mapeamentos existentes com
        // facilidade. Era exatamente por aí que os dois produtores de
        // normalized_data discordavam.
        //
        // Ausência nunca significa null: `jsonb_typeof` distingue os dois,
        // `->>` não, e é sobre essa distinção que os índices de identidade
        // da Query 2177 e o guard da Query 2179 se apoiam.
        const normalizedData: Record<string, unknown> = {};
        if (printingResolved) {
          if (variantTypeId !== null) normalizedData.variant_type_id = variantTypeId;
          normalizedData.printing_profile_id = printing.printingProfileId;
        }

        if (!printingResolved) printingUnresolvedRows++;
        if (printing.state === "RESOLVED_WITH_PROFILE") printingWithProfileRows++;

        resolvedRows.push({
          card_id: cardId,
          raw_data: rawData,
          normalized_data: normalizedData,
          validation_status: isValid ? "VALID" : "NEEDS_REVIEW",
          match_status: matchedVariantId ? "MATCHED" : "NEW",
          decision_status: matchedVariantId ? "SKIPPED" : "PENDING",
          matched_variant_id: matchedVariantId,
        });
      }
    }

    await updateVariantJobProgressStep(supabase, jobId, "PREPARING_REVIEW");
    await insertVariantImportRows(supabase, jobId, resolvedRows);

    const validRows = resolvedRows.filter((r) => r.validation_status === "VALID").length;
    const needsReviewRows = resolvedRows.filter((r) => r.validation_status === "NEEDS_REVIEW").length;
    const failedCards = uncorrelated.length + fetchFailed.length;

    const errorSummaryParts: string[] = [];
    if (uncorrelated.length > 0) errorSummaryParts.push(`CARDS_NAO_CORRELACIONADAS(${uncorrelated.length}): ${uncorrelated.slice(0, 10).join(", ")}`);
    if (fetchFailed.length > 0) errorSummaryParts.push(`ARQUIVOS_COM_FALHA_DE_FETCH(${fetchFailed.length}): ${fetchFailed.slice(0, 10).join(", ")}`);
    if (duplicateResolvedSkipped > 0) errorSummaryParts.push(`COMBINACOES_DUPLICADAS_IGNORADAS: ${duplicateResolvedSkipped}`);
    // DELIBERADAMENTE FORA do error_summary: nem "fora de escopo" nem
    // "tamanho desconhecido" são falha de importação, e a tela renderiza
    // error_summary em vermelho. Escrevê-los aqui pintaria de erro um job
    // perfeitamente sadio — o oposto do que este guard existe para fazer.
    // As contagens reais chegam à UI pelas próprias linhas de staging
    // (mappingPendingRows / unsupportedSizeRows / outOfScopeRows) e à
    // automação pelo bloco `rows` da resposta, logo abaixo.
    const errorSummary = errorSummaryParts.length > 0 ? errorSummaryParts.join(" | ") : null;

    await finalizeVariantJobStaged(
      supabase,
      jobId,
      { total_rows: resolvedRows.length, valid_rows: validRows, failed_rows: failedCards },
      errorSummary,
    );

    return Response.json({
      success: true,
      version: "2.0.0",
      job: { id: jobId, card_set_id: cardSetId, external_set_id: externalSetId },
      set: { serie: setSerieName.serieName, name: setSerieName.name, card_files: cardFiles.length },
      rows: {
        total: resolvedRows.length,
        valid: validRows,
        needs_review: needsReviewRows,
        // needs_review acima INCLUI size_unsupported: as duas contagens
        // respondem perguntas diferentes (quantas linhas precisam de decisão
        // humana vs. quantas delas são por tamanho). size_out_of_scope é
        // disjunto de ambas — aquelas linhas são INVALID.
        size_out_of_scope: sizeOutOfScopeRows,
        size_unsupported: sizeUnsupportedRows,
      },
      printing: {
        mappings_loaded: printingMappings.length,
        active_profiles_loaded: printingProfiles.length,
        rows_with_profile: printingWithProfileRows,
        rows_unresolved: printingUnresolvedRows,
      },
      cards: {
        correlated: correlatedCardIds.length,
        uncorrelated: uncorrelated.length,
        fetch_failed: fetchFailed.length,
      },
      duplicate_resolved_skipped: duplicateResolvedSkipped,
    });
  } catch (error) {
    console.error(error);
    const message = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
    if (jobId) await failVariantJob(supabase, jobId, message);
    return Response.json({ success: false, error: message }, { status: 500 });
  }
});
