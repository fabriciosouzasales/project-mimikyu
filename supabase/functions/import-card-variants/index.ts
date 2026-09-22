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
  buildTraitsSignatureKey,
  buildVariantIdentityKey,
  buildVariantNormalizedData,
  createVariantJobProcessing,
  failVariantJob,
  findAssetSourceByCode,
  findCardSetExternalReference,
  findCardSetWithGame,
  finalizeVariantJobStaged,
  insertVariantImportRows,
  listActiveEditionContextProfiles,
  listActivePrintingProfiles,
  listCardExternalReferencesMap,
  listCardIdsOfCardSet,
  listCardLineageCorrelationMap,
  listEditionContextExternalMappings,
  listEditionContextTraits,
  listExistingCardVariantsMap,
  listPrintingExternalMappings,
  listPrintingTraits,
  listVariantTypeExternalMappings,
  buildVariantComboKey,
  updateVariantJobProgressStep,
} from "./services/database.ts";
// EIXO 3 — PHASE C-bis. Mora em módulo próprio, e não aqui, porque este
// arquivo registra o servidor no topo do módulo e não exporta nada: uma
// função declarada aqui não poderia ser importada por um teste sem subir um
// listener. O teste de vetores importa de lá e executa o código REAL.
import {
  buildEditionContextIndex,
  isEditionContextResolved,
  routeEditionContext,
} from "./services/edition-context.ts";
import { resolveSetSerieName } from "./services/tcgdex.ts";
import {
  deriveLocalIdFromFilename,
  fetchCardFileSource,
  listSetCardFiles,
  parseVariantSource,
} from "./services/github-source.ts";
import type { VariantSourceShape } from "./services/github-source.ts";
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
  // Origem da correlação (VARIANT-CARD-CORRELATION-FALLBACK-01): diagnóstico
  // e telemetria, NUNCA identidade. `card_variant` não sabe — nem precisa
  // saber — por qual dos dois mapas a Card foi encontrada.
  correlationSource: "REFERENCE" | "LINEAGE" | null;
  // Shape da fonte (SOURCE-VARIANT-SAFETY-01). `null` só quando o arquivo
  // nem chegou a ser lido (fetchError) — nesse caso a Card entra em
  // `fetchFailed` e nunca chega ao guard de cobertura.
  sourceShape: VariantSourceShape | null;
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

// =====================================================================
// CORS — SUPORTE MÍNIMO PARA INVOCAÇÃO PELO BROWSER
// (CORS-BROWSER-INVOKE-01, 2026-09-18)
//
// POR QUE EXISTE. Até aqui, esta function só era chamada server-side (a
// Server Action `iniciarImportacaoVariantes` faz o `fetch` no servidor do
// Next, sem Origin). A primeira campanha `BULK-STAGING-01 / CANARY` tentou
// invocá-la do browser e abortou no preflight — "No 'Access-Control-Allow-
// Origin' header" —, corretamente, ANTES de qualquer escrita (postcheck
// LIVE: SV2/SM12/SV4 com 0 jobs, EX5.5 preservado, card_variant = 7.671).
//
// O QUE ISTO **NÃO** MUDA. Nada da fronteira de identidade: `verify_jwt =
// true` continua em config.toml, `auth.getUser()` e `rpc("is_admin")`
// continuam sendo a autorização real, `service_role` segue interno à
// function. CORS é um contrato de NAVEGADOR — ele decide se o browser
// ENTREGA a resposta ao JavaScript da página, e não tem poder algum sobre
// quem pode executar. Um cliente não-browser (curl, Server Action) ignora
// CORS por completo, então relaxar ou apertar isto não amplia nem reduz a
// superfície de autorização.
//
// ALLOWLIST EXPLÍCITA, nunca `*`. Origin ausente (Server Action de hoje) =
// sem headers CORS, comportamento byte-a-byte idêntico ao anterior. Origin
// presente e não listado = sem `Access-Control-Allow-Origin`, e o browser
// bloqueia — a superfície de confiança não cresce.
// =====================================================================

const CORS_ALLOWED_ORIGINS = new Set<string>([
  "https://mmkyu.vercel.app",
]);

const CORS_ALLOW_METHODS = "POST, OPTIONS";
const CORS_ALLOW_HEADERS = "authorization, apikey, content-type, x-client-info";

/**
 * Devolve os headers CORS aplicáveis a ESTA requisição.
 *
 * - sem `Origin`            → `{}` (nada é acrescentado; caminho do Server Action)
 * - `Origin` não permitido  → só `Vary: Origin` (correção de cache; NUNCA `ACAO`)
 * - `Origin` permitido      → `ACAO` + `Vary`
 *
 * `Vary: Origin` é obrigatório sempre que a resposta PODE variar por Origin:
 * sem ele, um cache intermediário poderia servir a um origin a resposta
 * calculada para outro.
 */
function corsHeadersFor(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin");
  if (origin === null) return {};
  if (!CORS_ALLOWED_ORIGINS.has(origin)) return { Vary: "Origin" };
  return { "Access-Control-Allow-Origin": origin, Vary: "Origin" };
}

/**
 * PONTO DE ENTRADA. Faz três coisas, nesta ordem, e nada mais:
 *   1. calcula os headers CORS desta requisição;
 *   2. responde ao preflight `OPTIONS` de origin permitido SEM entrar na
 *      lógica de negócio (nenhuma linha de `handleImportRequest` roda);
 *   3. delega ao handler intacto e aplica os headers CORS à resposta, seja
 *      ela qual for — 200, 400, 401, 403, 404, 405, 409 ou 500.
 *
 * Centralizar aqui é deliberado: os 11 `Response.json(...)` do handler
 * permanecem EXATAMENTE como estavam, sem um único header duplicado à mão.
 * Status, corpo e contrato de request/response ficam inalterados.
 */
Deno.serve(async (req) => {
  const cors = corsHeadersFor(req);

  // (2) Preflight: curto-circuito ANTES de qualquer lógica de negócio.
  //     `OPTIONS` de origin NÃO permitido não entra aqui — segue o fluxo
  //     normal e recebe o mesmo 405 de sempre, comportamento preservado.
  if (req.method === "OPTIONS" && cors["Access-Control-Allow-Origin"] !== undefined) {
    return new Response(null, {
      status: 204,
      headers: {
        ...cors,
        "Access-Control-Allow-Methods": CORS_ALLOW_METHODS,
        "Access-Control-Allow-Headers": CORS_ALLOW_HEADERS,
        "Access-Control-Max-Age": "86400",
      },
    });
  }

  // (3) Handler intocado + CORS uniforme em TODA resposta.
  const response = await handleImportRequest(req);
  for (const [key, value] of Object.entries(cors)) response.headers.set(key, value);
  return response;
});

async function handleImportRequest(req: Request): Promise<Response> {
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
    // AUTORIDADE DE COMPLETUDE (SOURCE-VARIANT-SAFETY-01/CORRECTION-01):
    // `public.card` do próprio Card Set — nunca `total_set_size`, nunca a
    // contagem de arquivos do GitHub, nunca o snapshot de importação, nunca
    // a contagem de referências externas.
    //
    // A MESMA Promise é injetada em `listCardLineageCorrelationMap`, que já
    // precisava desse conjunto para o G0 (pertença). Uma leitura, dois
    // consumidores: o número de consultas por job NÃO aumentou.
    const cardIdsOfSetPromise = listCardIdsOfCardSet(supabase, cardSetId);

    const [
      cardExternalReferences,
      expectedCardIds,
      cardLineageCorrelations,
      variantTypeMaps,
      printingMappings,
      printingProfiles,
      printingTraits,
      editionContextMappings,
      editionContextProfiles,
      editionContextTraits,
    ] = await Promise
      .all([
        listCardExternalReferencesMap(supabase, assetSource.id, externalSetId),
        cardIdsOfSetPromise,
        // FALLBACK de correlação (VARIANT-CARD-CORRELATION-FALLBACK-01):
        // subordinado por construção — só é consultado onde o mapa primário
        // não responde. Entra no MESMO Promise.all porque tem o mesmo
        // perfil dos demais preloads: número fixo de queries por job,
        // nunca por linha.
        listCardLineageCorrelationMap(supabase, cardSetId, externalSetId, cardIdsOfSetPromise),
        listVariantTypeExternalMappings(supabase, cardSet.game_id, assetSource.id, externalSetId),
        listPrintingExternalMappings(supabase, cardSet.game_id, assetSource.id),
        listActivePrintingProfiles(supabase, cardSet.game_id),
        listPrintingTraits(supabase, cardSet.game_id),
        // EIXO 3 — MESMO Promise.all, MESMO perfil: três queries por JOB,
        // nunca por linha. O roteamento acontece depois, em memória.
        listEditionContextExternalMappings(supabase, cardSet.game_id, assetSource.id),
        listActiveEditionContextProfiles(supabase, cardSet.game_id),
        listEditionContextTraits(supabase, cardSet.game_id),
      ]);

    const printingIndex = buildPrintingIndex(printingMappings, printingProfiles, printingTraits);
    // O índice do eixo 3 é montado UMA vez por JOB e já carrega o escopo:
    // a precedência escopado > global é resolvida aqui dentro, em memória,
    // exatamente como a Query 2211 a resolve em SQL.
    const editionContextIndex = buildEditionContextIndex(
      editionContextMappings,
      editionContextProfiles,
      editionContextTraits,
      externalSetId,
    );

    // Falha de UM arquivo (rede, 404, extração malformada) vira um
    // registro isolado com fetchError — nunca derruba o Set inteiro.
    const fileResults = await processInBatches<typeof cardFiles[number], CardFileResult>(
      cardFiles,
      CARD_FILE_BATCH_SIZE,
      async (file) => {
        const localId = deriveLocalIdFromFilename(file.name);
        const externalCardId = `${externalSetId}-${localId}`;
        const correlationKey = externalCardId.toUpperCase();

        // PRECEDÊNCIA (VARIANT-CARD-CORRELATION-FALLBACK-01). A referência
        // primária é a autoridade e é consultada primeiro, sempre. O
        // lineage só responde onde ela não respondeu — nunca sobrescreve.
        // Onde as duas existiriam elas concordam (15.978/15.978 no LIVE de
        // 2026-09-18, 0 divergências), então a ordem preserva o
        // comportamento anterior bit a bit em vez de apenas empatar com ele.
        const referenceCardId = cardExternalReferences.get(correlationKey) ?? null;
        const lineageCardId = referenceCardId ? null : (cardLineageCorrelations.get(correlationKey) ?? null);
        const cardId = referenceCardId ?? lineageCardId;
        const correlationSource: CardFileResult["correlationSource"] = referenceCardId
          ? "REFERENCE"
          : (lineageCardId ? "LINEAGE" : null);

        try {
          const source = await fetchCardFileSource(file.downloadUrl);
          const parsed = parseVariantSource(source);
          return {
            externalCardId,
            cardId,
            correlationSource,
            sourceShape: parsed.shape,
            combos: parsed.combos,
            fetchError: null,
          };
        } catch (error) {
          const message = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
          console.error(`GITHUB_SOURCE_FETCH_FAILED ${externalCardId}:`, message);
          return {
            externalCardId,
            cardId,
            correlationSource,
            sourceShape: null,
            combos: [],
            fetchError: `GITHUB_SOURCE_FETCH_FAILED: ${message}`,
          };
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

    // Amostra compartilhada pelos três guards abaixo. O error_summary é
    // renderizado na tela e lido por humano: despejar um Set inteiro ali o
    // tornaria ilegível e inútil. Contagem completa + amostra curta.
    const SOURCE_SHAPE_SAMPLE_LIMIT = 10;

    // =================================================================
    // GUARD 1 — FETCH FALHO DE CARD CORRELACIONADA (CORRECTION-01)
    //
    // `correlated` EXCLUI quem tem `fetchError`, então sem este guard uma
    // Card MMKYU conhecida cujo arquivo falhou no fetch sumiria do universo
    // examinado e o job terminaria STAGED com staging parcial.
    //
    // Roda ANTES do guard de cobertura de propósito: uma Card que falhou no
    // fetch também está ausente da cobertura, e reportá-la como
    // `CARD_COVERAGE_INCOMPLETE` (PERMANENTE) seria diagnóstico errado —
    // falha de rede é TRANSITÓRIA e tem retry persistido. A ordem dos
    // guards é, ela própria, a classificação correta do erro.
    //
    // Arquivo EXTRA sem `cardId` que falhou no fetch NÃO entra aqui: não
    // reduz a cobertura de nenhuma Card MMKYU. Segue como diagnóstico em
    // `cards.fetch_failed`.
    // =================================================================
    const fetchFailedCorrelated = fileResults.filter((r) => r.cardId !== null && r.fetchError !== null);
    if (fetchFailedCorrelated.length > 0) {
      const causas = new Map<string, number>();
      for (const r of fetchFailedCorrelated) {
        const causa = String(r.fetchError).split(":").slice(0, 2).join(":").trim();
        causas.set(causa, (causas.get(causa) ?? 0) + 1);
      }
      const amostra = fetchFailedCorrelated.slice(0, SOURCE_SHAPE_SAMPLE_LIMIT).map((r) => r.externalCardId);
      throw new Error(
        "VARIANT_SOURCE_FETCH_FAILED_FOR_CORRELATED_CARDS: " +
          `cards_correlacionadas_com_falha=${fetchFailedCorrelated.length}; ` +
          `causas=${[...causas].map(([c, n]) => `${c} x${n}`).join(" | ")}; ` +
          `amostra(${amostra.length}/${fetchFailedCorrelated.length}): ${amostra.join(", ")}`,
      );
    }

    // =================================================================
    // GUARD 2 — COBERTURA CANÔNICA DE CARDS (CORRECTION-01)
    //
    // `expected_card_ids` MINUS `cards representadas na fonte` = ∅.
    //
    // A autoridade é `public.card` do Card Set. Este guard pega o caso que
    // nenhum outro pega: uma Card MMKYU cujo ARQUIVO simplesmente sumiu da
    // listagem do GitHub — ela não aparece em `uncorrelated` (não há arquivo
    // para correlacionar), não aparece em `fetch_failed` (não houve fetch) e
    // não aparece no guard de shape (não está em `correlated`). Sem isto,
    // sumiria sem deixar rastro e o job iria a STAGED incompleto.
    //
    // Arquivos EXTRA da fonte sem Card MMKYU correspondente não são blocker
    // de completude — a direção testada é uma só, e é a que importa.
    // =================================================================
    const representedCardIds = new Set(correlated.map((r) => r.cardId as string));
    const missingCardIds = [...expectedCardIds].filter((id) => !representedCardIds.has(id));
    if (missingCardIds.length > 0) {
      const amostra = missingCardIds.slice(0, SOURCE_SHAPE_SAMPLE_LIMIT);
      throw new Error(
        "VARIANT_SOURCE_CARD_COVERAGE_INCOMPLETE: " +
          `cards_canonicas=${expectedCardIds.size}; representadas=${representedCardIds.size}; ` +
          `ausentes=${missingCardIds.length}; ` +
          `amostra_card_id(${amostra.length}/${missingCardIds.length}): ${amostra.join(", ")}`,
      );
    }

    // =================================================================
    // GUARD 3 — COBERTURA DE FONTE (SOURCE-VARIANT-SAFETY-01, 2026-09-18)
    //
    // Fecha as DUAS falhas que a CANARY expôs, e que eram indistinguíveis
    // de sucesso porque o job terminava STAGED com error_summary nulo:
    //
    //   sucesso vazio    — SM12: 271 Cards correlacionadas, 0 rows. Todas
    //                      as fontes eram ABSENT; nada a extrair.
    //   sucesso parcial  — Sets MIXED: parte das Cards em ARRAY, parte em
    //     SILENCIOSO       ABSENT. `resolvedRows.length === 0` não detecta
    //                      isso, porque as ARRAY produzem linhas.
    //
    // Por isso o critério é POR CARD, não por total de linhas: TODA Card
    // correlacionada precisa estar em shape ARRAY *e* ter ao menos um combo
    // extraível. Qualquer outra coisa falha o job de forma determinística e
    // PERSISTIDA (o throw cai em failVariantJob → status FAILED, que está
    // fora do índice único parcial e portanto é retentável).
    //
    // O guard roda ANTES de qualquer leitura de mapeamento e antes de
    // qualquer escrita de linha: um Set sem cobertura não consome nem
    // query nem staging.
    //
    // Nota: `correlated.length === 0` não dispara este guard — nenhuma
    // Card correlacionada significa falha de CORRELAÇÃO, não de fonte, e
    // já é reportada por `uncorrelated`/`fetch_failed`.
    // =================================================================
    const shapeTally = {
      ARRAY: 0,
      ARRAY_SEM_VARIANTE: 0,
      ARRAY_EMPTY: 0,
      OBJECT: 0,
      ABSENT: 0,
      UNSUPPORTED: 0,
    };
    const unsupportedSample: string[] = [];

    for (const result of correlated) {
      if (result.sourceShape === "ARRAY" && result.combos.length > 0) {
        shapeTally.ARRAY += 1;
        continue;
      }
      if (result.sourceShape === "ARRAY") shapeTally.ARRAY_SEM_VARIANTE += 1;
      else if (result.sourceShape === "ARRAY_EMPTY") shapeTally.ARRAY_EMPTY += 1;
      else if (result.sourceShape === "OBJECT") shapeTally.OBJECT += 1;
      else if (result.sourceShape === "ABSENT") shapeTally.ABSENT += 1;
      else shapeTally.UNSUPPORTED += 1;
      // Amostra LIMITADA — nunca despejar o Set inteiro no error_summary.
      if (unsupportedSample.length < SOURCE_SHAPE_SAMPLE_LIMIT) {
        unsupportedSample.push(result.externalCardId);
      }
    }

    const semCobertura = correlated.length - shapeTally.ARRAY;
    if (semCobertura > 0) {
      throw new Error(
        "VARIANT_SOURCE_UNSUPPORTED_FOR_CORRELATED_CARDS: " +
          `correlacionadas=${correlated.length}; sem_variante_extraivel=${semCobertura}; ` +
          `ARRAY=${shapeTally.ARRAY}; ARRAY_SEM_VARIANTE=${shapeTally.ARRAY_SEM_VARIANTE}; ` +
          `ARRAY_EMPTY=${shapeTally.ARRAY_EMPTY}; OBJECT=${shapeTally.OBJECT}; ` +
          `ABSENT=${shapeTally.ABSENT}; UNSUPPORTED=${shapeTally.UNSUPPORTED}; ` +
          `amostra(${unsupportedSample.length}/${semCobertura}): ${unsupportedSample.join(", ")}`,
      );
    }

    const correlatedCardIds = Array.from(new Set(correlated.map((r) => r.cardId as string)));

    // Telemetria aditiva (VARIANT-CARD-CORRELATION-FALLBACK-01). Contadas
    // por card_id DISTINTO, exatamente como `correlated` acima — é o que
    // torna a invariante verdadeira por construção, e não por sorte:
    //   correlated === correlated_by_reference + correlated_by_lineage
    // Os dois conjuntos são disjuntos porque `correlationSource` é decidido
    // por um único `??` na correlação: nenhuma Card pode ter as duas origens.
    const cardIdsByReference = new Set(
      correlated.filter((r) => r.correlationSource === "REFERENCE").map((r) => r.cardId as string),
    );
    const cardIdsByLineage = new Set(
      correlated.filter((r) => r.correlationSource === "LINEAGE").map((r) => r.cardId as string),
    );
    const existingVariantsByCardAndType = await listExistingCardVariantsMap(supabase, correlatedCardIds);

    await updateVariantJobProgressStep(supabase, jobId, "RESOLVING_VARIANT_MAPPING");

    const resolvedRows: ResolvedVariantRow[] = [];
    const seenComboByCard = new Set<string>();
    let duplicateResolvedSkipped = 0;
    let printingUnresolvedRows = 0;
    let printingWithProfileRows = 0;
    let editionContextUnresolvedRows = 0;
    let editionContextWithProfileRows = 0;
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

        const printingResolved = printing.state !== "UNRESOLVED";

        // EIXO 3, sobre o RESÍDUO de Impressão — nunca sobre o bruto. O gate
        // de "Impressão não terminal -> NOT_EVALUATED" está DENTRO de
        // routeEditionContext (2211:86-91), e por isso é provado pelos
        // vetores, não por inspeção deste arquivo.
        const editionContext = routeEditionContext(
          editionContextIndex,
          printingResolved,
          printing.residualSubtype,
          printing.residualStamp,
        );
        // Predicado ÚNICO, importado da PHASE C-bis. Com oito estados no
        // vocabulário, uma lista literal duplicada aqui seria uma lista que
        // diverge. Espelha 2211: só os DOIS estados RESOLVED_* são terminais.
        const editionContextResolved = isEditionContextResolved(editionContext.state);

        const residualComboKey = buildVariantComboKey(
          normalizedType,
          normalizedFoil,
          // O Variant Type recebe o resíduo PÓS-DOIS-EIXOS. Usar o resíduo
          // pós-um-eixo casaria contra combos que ainda carregam o token de
          // contexto — a contaminação que este pacote existe para eliminar.
          editionContext.residualSubtype,
          editionContext.residualStamp,
        );
        // >>> PRECEDÊNCIA COM ESCOPO (GATE-A-REV-01) <<<
        // scoped > global > NEEDS_REVIEW. UM nível, sem cascata.
        // `??` e nao `||`: so null/undefined caem para o fallback; um id
        // valido nunca e descartado. Precedencia identica a do SQL
        // (internal.lookup_variant_type_for_row) por construcao.
        const variantTypeId = variantTypeMaps.scopedMap.get(residualComboKey)
          ?? variantTypeMaps.globalMap.get(residualComboKey)
          ?? null;

        // VALID exige os TRÊS eixos. O raciocínio do eixo 1 vale idêntico
        // para o eixo 3: sem Contexto de Edição decidido, o resíduo não é
        // identidade canônica confiável.
        const isValid = printingResolved && editionContextResolved && variantTypeId !== null;

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
          ? `R|${
            buildVariantIdentityKey(
              cardId,
              variantTypeId,
              printing.printingProfileId,
              editionContext.editionContextProfileId,
            )
          }`
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
            buildVariantIdentityKey(
              cardId,
              variantTypeId,
              printing.printingProfileId,
              editionContext.editionContextProfileId,
            ),
          ) ?? null
          : null;

        // TRI-STATE de normalized_data — os três desfechos das Queries
        // 2221/2222, na mesma ordem. A regra inteira (e o porquê de ela ser
        // mais severa do que parece) mora em buildVariantNormalizedData, em
        // services/database.ts: função pura, uma só, exercida pelos vetores
        // do eixo 3 contra ESTE código e não contra uma cópia.
        const normalizedData = buildVariantNormalizedData(
          variantTypeId,
          printingResolved,
          printing.printingProfileId,
          editionContextResolved,
          editionContext.editionContextProfileId,
        );

        if (!printingResolved) printingUnresolvedRows++;
        if (printing.state === "RESOLVED_WITH_PROFILE") printingWithProfileRows++;
        if (!editionContextResolved) editionContextUnresolvedRows++;
        if (editionContext.state === "RESOLVED_WITH_EC_PROFILE") editionContextWithProfileRows++;

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
      // EIXO 3 — bloco aditivo, espelho do de Printing. Nenhum campo acima
      // ou abaixo mudou de nome, tipo ou significado.
      //
      // `profiles_loaded` (e não `active_profiles_loaded`) porque o preload
      // traz ativos E inativos de propósito: ver
      // listActiveEditionContextProfiles.
      edition_context: {
        mappings_loaded: editionContextMappings.length,
        profiles_loaded: editionContextProfiles.length,
        traits_loaded: editionContextTraits.length,
        rows_with_profile: editionContextWithProfileRows,
        rows_unresolved: editionContextUnresolvedRows,
      },
      cards: {
        correlated: correlatedCardIds.length,
        // Aditivos (VARIANT-CARD-CORRELATION-FALLBACK-01). Nenhum campo
        // acima ou abaixo mudou de nome, tipo ou significado.
        // INVARIANTE: correlated === correlated_by_reference + correlated_by_lineage.
        // Em Card Set com referência completa, correlated_by_lineage é 0 —
        // é a prova de não-regressão que a própria resposta carrega.
        correlated_by_reference: cardIdsByReference.size,
        correlated_by_lineage: cardIdsByLineage.size,
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
}
