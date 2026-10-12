"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroCatalogo } from "@/lib/supabase/catalogo-errors";
import {
  getCardVariantTypesForJob,
  getCatalogVariantImportJobStatus,
  getCatalogVariantImportRows,
  getCatalogVariantImportScopeCounters,
  type CardVariantTypeOption,
  type CatalogVariantImportJobStatus,
  type CatalogVariantImportRowView,
} from "@/lib/catalogo/queries";
import {
  deriveVariantImportScopeCounters,
  type VariantImportScopeCounters,
} from "@/lib/catalogo/variant-size-scope";
import {
  effectiveScope,
  parseAxisPreview,
  parseRowDiagnosis,
  type AxisPreview,
  type AxisProfileOption,
  type MappingAxis,
  type MappingDraft,
  type NamedRef,
  type RowDiagnosis,
} from "@/lib/catalogo/axis-resolution";

/**
 * Server Actions do fluxo Importar Variantes (Incremento 4, ADR-028),
 * adicionadas em 2026-08-15 — mesmo padrão de
 * `catalogo/importar-cartas/tcgdex/actions.ts`, uma instância nova dele para
 * o staging de Card Variant. Diferença estrutural real: a Edge Function
 * `import-card-variants` recebe `{ card_set_id }` (não `{ job_id }`) e cria o
 * próprio job internamente — não existe aqui um RPC "abrir job" equivalente a
 * `admin_start_catalog_import` (CV-02, tela dedicada de job pré-criado, está
 * deliberadamente fora do escopo desta rodada).
 */

export type IniciarImportacaoVariantesActionState = { error: string | null; jobId: string | null };

/**
 * Inicia a importação de variantes para uma Coleção: invoca
 * import-card-variants diretamente com `card_set_id` (a function resolve
 * external_set_id via card_set_external_reference e cria o job em
 * PROCESSING internamente — ver comentário no topo da Edge Function).
 * Devolve `{ jobId }` em vez de redirecionar — mesmo motivo de
 * `iniciarImportacaoTcgdex` (ver tcgdex/actions.ts): qualquer `redirect()`
 * destruiria o estado de progresso do componente cliente.
 *
 * `JOB_ALREADY_ACTIVE_FOR_CARD_SET` (409): diferente de
 * `admin_start_catalog_import`/Query 2080, a Edge Function não devolve o id
 * do job já ativo — só o próprio erro. Localiza o job ativo diretamente na
 * tabela (mesmo raciocínio de `iniciarImportacaoTcgdex` para
 * `ADMIN_START_CATALOG_IMPORT_ALREADY_ACTIVE`) para não deixar o
 * administrador num beco sem saída.
 */
export async function iniciarImportacaoVariantes(
  _prevState: IniciarImportacaoVariantesActionState,
  formData: FormData,
): Promise<IniciarImportacaoVariantesActionState> {
  const cardSetId = String(formData.get("card_set_id") ?? "");

  if (!cardSetId) {
    return { error: "Selecione uma Coleção.", jobId: null };
  }

  const supabase = await createClient();

  // Fronteira de identidade (mesmo padrão de import-catalog-cards/
  // import-card-assets, Finding 1 da auditoria de segurança do Catálogo
  // Editorial, 2026-08-13): o access_token da sessão do próprio
  // administrador é repassado, nunca lido do corpo da requisição.
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return { error: "Sessão inválida. Faça login novamente.", jobId: null };
  }

  const functionUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/import-card-variants`;

  let response: Response;
  try {
    response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({ card_set_id: cardSetId }),
    });
  } catch (fetchError) {
    const message = fetchError instanceof Error ? fetchError.message : "Falha de rede.";
    return { error: `Falha ao chamar o processador: ${message}`, jobId: null };
  }

  const body = await response.json().catch(() => null);

  if (!response.ok) {
    if (typeof body?.error === "string" && body.error.startsWith("JOB_ALREADY_ACTIVE_FOR_CARD_SET")) {
      const { data: existingJob } = await supabase
        .from("catalog_variant_import_job")
        .select("id")
        .eq("card_set_id", cardSetId)
        .in("status", ["RECEIVED", "PROCESSING", "STAGED", "CONFIRMING"])
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (existingJob) {
        return { error: null, jobId: existingJob.id as string };
      }
    }

    return { error: `Falha ao processar a importação: ${body?.error ?? response.status}`, jobId: null };
  }

  revalidatePath("/catalogo/importar-variantes");
  return { error: null, jobId: String(body?.job?.id ?? "") || null };
}

/**
 * Busca job + linhas de staging + Card Variant Types do Game (para o
 * seletor do Dialog "Resolver mapeamento") em uma única chamada — mesmo
 * papel de getImportacaoJobData (tcgdex/actions.ts). cardVariantTypes só é
 * buscado quando o job é revisável, mesmo critério já usado para `rows` —
 * evita uma leitura sem uso nos estados PROCESSING/COMPLETED/FAILED.
 */
export type ImportacaoVariantesJobData = {
  job: CatalogVariantImportJobStatus | null;
  rows: CatalogVariantImportRowView[];
  cardVariantTypes: CardVariantTypeOption[];
  /**
   * Contadores de escopo por tamanho. `null` SIGNIFICA "não foi possível
   * apurar" — nunca zero. Ver dataError.
   */
  counters: VariantImportScopeCounters | null;
  /**
   * Mensagem quando a leitura das linhas falhou. `counters === null` se e
   * somente se `dataError !== null`.
   */
  dataError: string | null;
};

export async function getImportacaoVariantesJobData(jobId: string): Promise<ImportacaoVariantesJobData> {
  const supabase = await createClient();
  const job = await getCatalogVariantImportJobStatus(supabase, jobId);
  const reviewable = job?.status === "STAGED" || job?.status === "CONFIRMING";

  try {
    if (reviewable) {
      const [rows, cardVariantTypes] = await Promise.all([
        getCatalogVariantImportRows(supabase, jobId),
        getCardVariantTypesForJob(supabase, jobId),
      ]);
      // >>> FONTE ÚNICA <<< As linhas já estão aqui, completas e paginadas.
      // Derivar os contadores delas custa zero round-trip e torna impossível
      // o painel discordar da tabela — que conta a mesma coleção com a mesma
      // função pura.
      return { job, rows, cardVariantTypes, counters: deriveVariantImportScopeCounters(rows), dataError: null };
    }

    if (!job) return { job: null, rows: [], cardVariantTypes: [], counters: null, dataError: null };

    // Job não revisável (COMPLETED / COMPLETED_WITH_ERRORS / FAILED /
    // PROCESSING): a tabela não é renderizada, mas o painel de conclusão
    // precisa dos três números. Leitura mínima, paginada e strict — a menor
    // alternativa coerente, e ainda assim classificada pelo mesmo predicado.
    return {
      job,
      rows: [],
      cardVariantTypes: [],
      counters: await getCatalogVariantImportScopeCounters(supabase, jobId),
      dataError: null,
    };
  } catch (error) {
    // FAIL-CLOSED. Antes, uma falha de leitura virava `[]` + zeros e a tela
    // anunciava sucesso. Agora o job continua sendo exibido (status, código do
    // Set), mas a tela sabe que NÃO sabe: counters null + dataError.
    console.error("getImportacaoVariantesJobData", error);
    return {
      job,
      rows: [],
      cardVariantTypes: [],
      counters: null,
      dataError:
        "Não foi possível ler as linhas desta importação. Os números abaixo não puderam ser apurados — recarregue a página antes de concluir qualquer coisa a partir desta tela.",
    };
  }
}

export type ResolverMapeamentoVarianteResult = {
  error: string | null;
  rowsUpdated?: number;
  jobsAffected?: number;
};

/**
 * Resolve, a partir de uma linha NEEDS_REVIEW, uma combinação externa
 * (type/foil/subtype/stamp) sem mapeamento para um Card Variant Type já
 * existente — admin_resolve_catalog_variant_import_mapping() (Query 2150).
 * O mapeamento criado é canônico para Game+Fonte+combinação: a própria RPC
 * revalida em lote todas as linhas NEEDS_REVIEW compatíveis em qualquer job
 * ainda revisável (STAGED) do mesmo Game+Fonte, não só o job de origem —
 * por isso `rowsUpdated`/`jobsAffected` podem ser maiores que 1, mesmo
 * quando a ação foi disparada a partir de uma única linha na tela.
 * Nunca cria um Card Variant Type novo — só associa a um já cadastrado.
 */
export async function resolverMapeamentoVariante(
  rowId: string,
  variantTypeId: string,
): Promise<ResolverMapeamentoVarianteResult> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_resolve_catalog_variant_import_mapping", {
    p_row_id: rowId,
    p_variant_type_id: variantTypeId,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  const result = Array.isArray(data) ? data[0] : data;
  revalidatePath("/catalogo/importar-variantes");
  return { error: null, rowsUpdated: result?.rows_updated as number | undefined, jobsAffected: result?.jobs_affected as number | undefined };
}

export type CriarTipoVariacaoEResolverMapeamentoResult = {
  error: string | null;
  variantTypeId?: string;
  mappingId?: string;
  rowsUpdated?: number;
  jobsAffected?: number;
};

/**
 * Incremento 3 da Governança da Taxonomia de Card Variant Type (ADR-028):
 * a partir de uma linha NEEDS_REVIEW sem correspondência em nenhum Card
 * Variant Type existente, cria um tipo canônico novo e resolve o mapping
 * dessa combinação na mesma operação —
 * admin_create_card_variant_type_with_import_mapping() (Query 2158),
 * wrapper transacional fino sobre admin_create_card_variant_type() (2154)
 * e admin_resolve_catalog_variant_import_mapping() (2150). game_id nunca é
 * enviado — a RPC resolve a partir da própria linha, mesma garantia de
 * `resolverMapeamentoVariante` acima. Se qualquer uma das duas etapas
 * falhar (código duplicado, display_order duplicado, combinação já
 * mapeada), a chamada inteira reverte — nenhum tipo órfão fica criado.
 */
export async function criarTipoVariacaoEResolverMapeamento(
  rowId: string,
  novoTipo: { code: string; name: string; description: string | null; displayOrder: number },
): Promise<CriarTipoVariacaoEResolverMapeamentoResult> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_create_card_variant_type_with_import_mapping", {
    p_row_id: rowId,
    p_code: novoTipo.code,
    p_name: novoTipo.name,
    p_description: novoTipo.description,
    p_display_order: novoTipo.displayOrder,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  const result = Array.isArray(data) ? data[0] : data;
  revalidatePath("/catalogo/importar-variantes");
  revalidatePath("/catalogo/tipos-variacao");
  return {
    error: null,
    variantTypeId: result?.variant_type_id as string | undefined,
    mappingId: result?.mapping_id as string | undefined,
    rowsUpdated: result?.rows_updated as number | undefined,
    jobsAffected: result?.jobs_affected as number | undefined,
  };
}

// ---------------------------------------------------------------------------
// P3b — Impressão e Contexto de Edição na revisão (Queries 2271–2274)
// ---------------------------------------------------------------------------
//
// Toda decisão passa pelas RPCs administrativas (SECURITY DEFINER, is_admin()
// no banco). As actions só repassam a intenção do administrador; o jogo, o Set
// e o escopo efetivo são resolvidos pelo próprio banco a partir da linha.

export type DiagnosticarLinhaResult = { error: string | null; diagnosis: RowDiagnosis | null };

/** Diagnóstico dos três eixos de uma linha (Query 2271, só leitura). */
export async function diagnosticarLinhaVariante(rowId: string): Promise<DiagnosticarLinhaResult> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_explain_catalog_variant_import_row", { p_row_id: rowId });
  if (error) return { error: traduzirErroCatalogo(error.message), diagnosis: null };
  return { error: null, diagnosis: parseRowDiagnosis(data) };
}

export type AxisTraitOption = NamedRef & { family: string | null; displayOrder: number };

export type CatalogoEixoResult = {
  error: string | null;
  traits: AxisTraitOption[];
  profiles: AxisProfileOption[];
};

const AXIS_TABLES: Record<MappingAxis, { trait: string; profile: string; traitColumns: string }> = {
  PRINTING: {
    trait: "card_printing_trait",
    profile: "card_printing_profile",
    traitColumns: "id, code, name, display_order",
  },
  EDITION_CONTEXT: {
    trait: "card_edition_context_trait",
    profile: "card_edition_context_profile",
    traitColumns: "id, code, name, display_order, family",
  },
};

/**
 * Características e perfis ATIVOS do eixo, no jogo da linha. Leitura sob a
 * RLS admin-only dessas tabelas; carregada uma vez por eixo e reaproveitada
 * pelo diálogo enquanto a tela estiver aberta.
 */
export async function carregarCatalogoEixo(rowId: string, axis: MappingAxis): Promise<CatalogoEixoResult> {
  const supabase = await createClient();
  const { data: row, error: rowError } = await supabase
    .from("catalog_variant_import_row")
    .select("card:card_id(card_set:card_set_id(expansion:expansion_id(game_id)))")
    .eq("id", rowId)
    .maybeSingle();
  const gameId = (row as unknown as { card: { card_set: { expansion: { game_id: string } } } } | null)?.card?.card_set
    ?.expansion?.game_id;
  if (rowError || !gameId) {
    return { error: "Não foi possível identificar o jogo desta linha.", traits: [], profiles: [] };
  }

  const tables = AXIS_TABLES[axis];
  const [traitsRes, profilesRes] = await Promise.all([
    supabase
      .from(tables.trait)
      .select(tables.traitColumns)
      .eq("game_id", gameId)
      .eq("is_active", true)
      .order("display_order", { ascending: true }),
    supabase
      .from(tables.profile)
      .select("id, code, name, display_order, traits_signature")
      .eq("game_id", gameId)
      .eq("is_active", true)
      .order("display_order", { ascending: true }),
  ]);
  if (traitsRes.error || profilesRes.error) {
    return { error: "Não foi possível carregar características e perfis deste eixo.", traits: [], profiles: [] };
  }

  type TraitRow = { id: string; code: string; name: string; display_order: number; family?: string | null };
  type ProfileRow = { id: string; code: string; name: string; display_order: number; traits_signature: string[] | null };
  return {
    error: null,
    traits: ((traitsRes.data ?? []) as unknown as TraitRow[]).map((t) => ({
      id: t.id,
      code: t.code,
      name: t.name,
      family: t.family ?? null,
      displayOrder: t.display_order,
    })),
    profiles: ((profilesRes.data ?? []) as unknown as ProfileRow[])
      // Perfil sem selo não tem identidade utilizável — não é oferecido.
      .filter((p) => Array.isArray(p.traits_signature) && p.traits_signature.length > 0)
      .map((p) => ({
        id: p.id,
        code: p.code,
        name: p.name,
        displayOrder: p.display_order,
        traitIds: p.traits_signature ?? [],
      })),
  };
}

export type SimularMapeamentoEixoResult = { error: string | null; preview: AxisPreview | null };

/**
 * Prévia (Query 2272). Executa a RPC de escrita real numa subtransação e a
 * desfaz — tem custo de escrita e trava as linhas atingidas por instantes.
 * Chamada apenas por ação explícita do administrador, nunca a cada digitação.
 */
export async function simularMapeamentoEixo(rowId: string, draft: MappingDraft): Promise<SimularMapeamentoEixoResult> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_preview_catalog_variant_import_axis_mapping", {
    p_row_id: rowId,
    p_axis: draft.axis,
    p_raw_field: draft.field,
    p_token: draft.token,
    p_trait_ids: draft.traitIds,
    p_scope: effectiveScope(draft.axis, draft.scope),
  });
  if (error) return { error: traduzirErroCatalogo(error.message), preview: null };
  const preview = parseAxisPreview(data);
  if (preview.error) preview.error = traduzirErroCatalogo(preview.error);
  return { error: null, preview };
}

export type NovoPerfilEixo = { code: string; name: string; description: string | null; displayOrder: number };

export type ResolverMapeamentoEixoResult = {
  error: string | null;
  /** Perfil criado nesta chamada — informado mesmo quando o mapeamento falha depois. */
  createdProfileName?: string;
  rowsTouched?: number;
  rowsRevalidated?: number;
  rowsStillPending?: number;
  jobsAffected?: number;
};

/**
 * Grava a decisão. Com perfil novo, cria o perfil primeiro
 * (admin_create_card_*_profile_with_backfill: composição selada, sem linha
 * atingida ainda) e depois o mapeamento — nessa ordem, nenhuma linha válida
 * passa por um estado "sem perfil". Se o mapeamento falhar, o perfil criado
 * continua existindo e é informado: é reutilizável na próxima tentativa.
 */
export async function resolverMapeamentoEixo(
  rowId: string,
  draft: MappingDraft,
  novoPerfil: NovoPerfilEixo | null,
): Promise<ResolverMapeamentoEixoResult> {
  const supabase = await createClient();
  let createdProfileName: string | undefined;

  if (novoPerfil) {
    const fn =
      draft.axis === "PRINTING"
        ? "admin_create_card_printing_profile_with_backfill"
        : "admin_create_card_edition_context_profile_with_backfill";
    const { error } = await supabase.rpc(fn, {
      p_code: novoPerfil.code,
      p_name: novoPerfil.name,
      p_description: novoPerfil.description,
      p_display_order: novoPerfil.displayOrder,
      p_trait_ids: draft.traitIds,
    });
    if (error) return { error: traduzirErroCatalogo(error.message) };
    createdProfileName = novoPerfil.name;
  }

  const { data, error } =
    draft.axis === "PRINTING"
      ? await supabase.rpc("admin_resolve_catalog_variant_import_printing_mapping", {
          p_row_id: rowId,
          p_raw_field: draft.field,
          p_token: draft.token,
          p_trait_ids: draft.traitIds,
        })
      : await supabase.rpc("admin_resolve_catalog_variant_import_edition_context_mapping", {
          p_row_id: rowId,
          p_raw_field: draft.field,
          p_token: draft.token,
          p_trait_ids: draft.traitIds,
          p_scope: effectiveScope(draft.axis, draft.scope),
        });

  revalidatePath("/catalogo/importar-variantes");
  if (error) {
    const message = traduzirErroCatalogo(error.message);
    return {
      error: createdProfileName
        ? `O perfil "${createdProfileName}" foi criado, mas o mapeamento não foi gravado: ${message}`
        : message,
      createdProfileName,
    };
  }

  const r = (Array.isArray(data) ? data[0] : data) as Record<string, number> | null;
  // A RPC de Impressão (2181) devolve rows_updated; a de Contexto (2273), rows_touched/rows_revalidated.
  const touched = r?.rows_touched ?? r?.rows_updated ?? 0;
  const pending = r?.rows_still_pending ?? 0;
  return {
    error: null,
    createdProfileName,
    rowsTouched: touched,
    rowsRevalidated: r?.rows_revalidated ?? Math.max(touched - pending, 0),
    rowsStillPending: pending,
    jobsAffected: r?.jobs_affected ?? 0,
  };
}

export type DecidirLinhasVariantesResult = { error: string | null };

/**
 * Decide o destino de uma ou mais linhas de staging (admin_decide_catalog_
 * variant_import_row, Query 2144) — mesmo padrão de decidirLinhasImportacao.
 * A própria RPC recusa APPROVED para linhas NEEDS_REVIEW (validation_status
 * <> VALID) — o erro chega aqui já traduzido pelo mesmo helper, a UI evita
 * oferecer essa ação quando dá para saber de antemão (ver
 * revisao-importacao-variantes-table.tsx), mas a garantia real está no
 * banco, não no componente.
 */
export async function decidirLinhasVariantes(
  jobId: string,
  rowIds: string[],
  decisionStatus: "PENDING" | "APPROVED" | "REJECTED" | "SKIPPED",
): Promise<DecidirLinhasVariantesResult> {
  if (rowIds.length === 0) {
    return { error: null };
  }

  const supabase = await createClient();

  // >>> AUTORIDADE DA DECISÃO: A RPC, NÃO ESTA AÇÃO (2026-09-16, BLOCKER-4) <<<
  // A Correction-01 tinha posto aqui um precheck `.in("id", rowIds)` para
  // barrar linhas SIZE_OUT_OF_SCOPE antes da chamada. Foi removido, por três
  // razões concretas:
  //
  //   1. DUPLICAÇÃO DE REGRA. A Query 2199 põe o mesmo invariante DENTRO de
  //      `admin_decide_catalog_variant_import_row`, que é SECURITY DEFINER e
  //      o único writer de `decision_status`. Duas cópias da mesma regra em
  //      camadas diferentes divergem com o tempo — e a cópia de fora é a que
  //      ninguém lembra de atualizar.
  //   2. CONTRATO DE LOTE. A RPC aceita até 10.000 UUIDs por chamada (teto da
  //      Query 2163). Um `.in()` com 10.000 UUIDs vira querystring de ~370 KB
  //      no PostgREST — acima do limite usual de linha de requisição — e
  //      acrescentaria um round-trip a CADA decisão. Preservar isso exigiria
  //      chunking arbitrário do lado da aplicação, complexidade que a RPC já
  //      resolve em uma instrução atômica.
  //   3. ATOMICIDADE. O precheck e o UPDATE eram duas transações distintas:
  //      entre a leitura e a chamada, nada impedia a linha de mudar. O guard
  //      da 2199 avalia e escreve na MESMA transação.
  //
  // O que sobra, e é suficiente: a UI não deixa selecionar nem acionar a
  // linha travada (isVariantRowSelectable / canDecideVariantRow), e a RPC
  // recusa o lote inteiro se um id fora de escopo chegar mesmo assim.
  //
  // DEPENDÊNCIA DE SEQUÊNCIA: enquanto a 2199 não estiver LIVE, a única
  // barreira é a da UI. Isto está registrado como blocker de ordem de
  // implantação — a 2199 precede o deploy do frontend.
  const { error } = await supabase.rpc("admin_decide_catalog_variant_import_row", {
    p_row_ids: rowIds,
    p_decision_status: decisionStatus,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  // `jobId` não monta mais nenhuma URL (mesmo motivo de decidirLinhasImportacao)
  // — continua no parâmetro só para identificar as linhas na chamada acima.
  void jobId;
  revalidatePath("/catalogo/importar-variantes");
  return { error: null };
}

/** Mesmo tamanho de lote de confirmarImportacao (tcgdex/actions.ts) — recomendação operacional do ADR-024, reaproveitada aqui. */
const CONFIRM_CHUNK_SIZE = 50;

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

export type ConfirmarImportacaoVariantesResult = {
  error: string | null;
  insertedCount: number;
  unchangedCount: number;
  failedCount: number;
  pendingCount: number;
  jobStatus: string | null;
};

type AdminConfirmCatalogVariantImportRow = {
  inserted_count: number;
  unchanged_count: number;
  failed_count: number;
  pending_count: number;
  job_status: string;
};

const EMPTY_CONFIRM_RESULT: Omit<ConfirmarImportacaoVariantesResult, "error"> = {
  insertedCount: 0,
  unchangedCount: 0,
  failedCount: 0,
  pendingCount: 0,
  jobStatus: null,
};

/**
 * Confirma a importação — persiste as Card Variant aprovadas/puladas via
 * admin_confirm_catalog_variant_import() (Query 2145). Mesmo desenho de
 * confirmarImportacao (tcgdex/actions.ts): busca ids elegíveis
 * (persistence_status = PENDING e decision_status IN (APPROVED, SKIPPED)),
 * chama a RPC em lotes de CONFIRM_CHUNK_SIZE sequencialmente — cada chamada
 * devolve contadores recalculados sobre o job inteiro (agregação, não
 * incremento), o resultado devolvido é sempre o da última chamada. Sem
 * linhas elegíveis, ainda assim faz uma chamada (p_row_ids = NULL) — é o que
 * transiciona o job de STAGED para COMPLETED mesmo quando tudo foi
 * rejeitado/pulado. Sem `updatedCount` (diferença real frente a
 * ConfirmarImportacaoResult — ver Query 2145: card_variant não tem UPDATE).
 */
export async function confirmarImportacaoVariantes(jobId: string): Promise<ConfirmarImportacaoVariantesResult> {
  const supabase = await createClient();

  const { data: eligibleRows, error: fetchError } = await supabase
    .from("catalog_variant_import_row")
    .select("id")
    .eq("job_id", jobId)
    .eq("persistence_status", "PENDING")
    .in("decision_status", ["APPROVED", "SKIPPED"]);

  if (fetchError) {
    return { error: traduzirErroCatalogo(fetchError.message), ...EMPTY_CONFIRM_RESULT };
  }

  const rowIds = (eligibleRows ?? []).map((row) => row.id as string);
  const batches: (string[] | null)[] = rowIds.length > 0 ? chunk(rowIds, CONFIRM_CHUNK_SIZE) : [null];

  let lastResult: ConfirmarImportacaoVariantesResult = { error: null, ...EMPTY_CONFIRM_RESULT };

  for (const batch of batches) {
    const { data, error } = await supabase.rpc("admin_confirm_catalog_variant_import", {
      p_job_id: jobId,
      p_row_ids: batch,
    });

    if (error) {
      return { ...lastResult, error: traduzirErroCatalogo(error.message) };
    }

    const rows = (data ?? []) as AdminConfirmCatalogVariantImportRow[];
    const [row] = rows;
    if (row) {
      lastResult = {
        error: null,
        insertedCount: row.inserted_count,
        unchangedCount: row.unchanged_count,
        failedCount: row.failed_count,
        pendingCount: row.pending_count,
        jobStatus: row.job_status,
      };
    }
  }

  revalidatePath("/catalogo/importar-variantes");
  return lastResult;
}
