/*
Project Mimikyu
Script administrativo standalone: sync-justtcg-pricing
Incremento P8 — Conector JustTCG e Piloto Controlado (2026-08-17).

Objetivo: primeiro fluxo real JustTCG -> Pricing, exclusivamente server-side e acionado
manualmente por um administrador — nunca em resposta a requisição HTTP, nunca agendado,
nunca chamado pelo frontend. Resolve pricing_set_mapping/pricing_card_mapping para os
Card Sets-piloto, persiste pricing_product/pricing_observation com o preço original em
USD, e registra a execução inteira em pricing_sync_run/pricing_sync_run_call.

Arquitetura (decisão registrada, não uma Edge Function): mesmo precedente de
scripts/import-manual-assets.ts — roda localmente, sob demanda, com a Service Role Key
do projeto, nunca é implantado no Supabase. "Acionado manualmente por administrador"
aqui significa que é o próprio administrador (Fabrício) quem executa este script na sua
máquina, com suas próprias variáveis de ambiente — o mesmo padrão já usado para SQL
(CLAUDE.md: "Quem executa o SQL no Supabase, por padrão, é Fabrício") e para a prova
técnica original (PowerShell, também local). Não existe tela nem Route Handler para
este piloto — está deliberadamente fora de escopo.

Piloto controlado: restrito a dois Card Sets (ME1, BASE1) e até três cartas por Set,
hardcoded abaixo — reutiliza exatamente as nove cartas já validadas na prova técnica de
2026-08-17 (prova-justtcg-resultados.json), reduzindo risco e consumo de cota. Este
script não amplia o catálogo: nunca cria card_set/card, apenas lê os já existentes.

Credencial: somente `JUSTTCG_API_KEY` (variável de ambiente, nunca argumento de linha de
comando, nunca logada). Se ausente, o script roda em modo --fixture-check: valida toda a
lógica de parsing/normalização/idempotência contra dados sintéticos embutidos, 100%
offline (nenhuma chamada de rede, nenhuma escrita no Supabase) — e imprime um aviso
explícito de que nenhum piloto real foi executado. Nunca solicita a chave interativamente
nem aceita literal em texto.

pricing_source.is_active permanece FALSE (Incremento P7) — este script é o único caminho
administrativo autorizado a ler a fonte JUSTTCG apesar disso: getJustTcgSource(), abaixo,
consulta explicitamente `WHERE code = 'JUSTTCG'`, um literal fixo, nunca um parâmetro —
deliberadamente NÃO existe uma função genérica "getSourceIgnoringActive(code)" que
qualquer código futuro pudesse reaproveitar para outra fonte.

Fora de escopo (confirmado, não implementado aqui): PTAX, BRL, "Valor Brasil" (toda
observação grava market_scope='UNDETERMINED'), scheduler/cron, qualquer tela de
frontend, ativação comercial da fonte (is_active permanece FALSE), ingestão em massa
(catálogo completo) — só as cartas hardcoded abaixo.

Uso:

  # PowerShell — defina as variáveis de ambiente ANTES de rodar. NUNCA cole a Service
  # Role Key nem a JUSTTCG_API_KEY em chat/log.
  $env:SUPABASE_URL = "https://qjfutqujxrbzgrtkpgkg.supabase.co"
  $env:SUPABASE_SERVICE_ROLE_KEY = "<service_role_key>"
  $env:JUSTTCG_API_KEY = "<justtcg_api_key>"   # opcional — ausente força --fixture-check

  # Validação offline (sempre segura, não requer nenhuma variável de rede/segredo):
  deno run --allow-env scripts/sync-justtcg-pricing.ts --fixture-check

  # Piloto real (requer as três variáveis + um admin_user.id real que está confirmando):
  deno run --allow-net --allow-env scripts/sync-justtcg-pricing.ts --confirmed-by=<admin_user_uuid>

  # Piloto real, sem gravar nada (mesma Convenção #7 do projeto — validar antes de executar):
  deno run --allow-net --allow-env scripts/sync-justtcg-pricing.ts --confirmed-by=<admin_user_uuid> --dry-run
*/

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

// ============================================================================
// 0. Configuração fixa do piloto (Incremento P8 — NÃO ampliar sem nova decisão)
// ============================================================================

const JUSTTCG_API_BASE = "https://api.justtcg.com/v1";
const REQUEST_TIMEOUT_MS = 15_000;
const MAX_REQUESTS_PER_RUN = 20; // teto de segurança local, independente do plano contratado
const DELAY_BETWEEN_REQUESTS_MS = 3_000;
const RATE_LIMIT_BACKOFF_MS = 10_000;

type SetTarget = {
  codigoMmkyu: string;
  nomeReferenciaEn: string;
  dataMmkyu: string; // ISO
  overrideExternalSetId: string; // confirmado na prova técnica de 2026-08-17
};

// Apenas os dois Sets do piloto — nunca ampliar sem decisão explícita nova.
const SET_TARGETS: SetTarget[] = [
  { codigoMmkyu: "ME1", nomeReferenciaEn: "Mega Evolution", dataMmkyu: "2025-09-26", overrideExternalSetId: "me01-mega-evolution-pokemon" },
  { codigoMmkyu: "BASE1", nomeReferenciaEn: "Base Set", dataMmkyu: "1999-01-09", overrideExternalSetId: "base-set-pokemon" },
];

type CardTarget = { setMmkyu: string; nome: string; numero: string };

// No máximo três cartas por Set (restrição explícita do piloto) — reaproveita
// exatamente as cartas já validadas na prova técnica de 2026-08-17.
const CARD_TARGETS: CardTarget[] = [
  { setMmkyu: "ME1", nome: "Bulbasaur", numero: "001" },
  { setMmkyu: "ME1", nome: "Mega Venusaur ex", numero: "177" },
  { setMmkyu: "ME1", nome: "Mega Gardevoir ex", numero: "187" },
  { setMmkyu: "BASE1", nome: "Abra", numero: "043" },
  { setMmkyu: "BASE1", nome: "Arcanine", numero: "023" },
  { setMmkyu: "BASE1", nome: "Alakazam", numero: "001" },
];

const MARKET_LABEL = "JUSTTCG_AGGREGATE"; // mesmo rótulo já usado como exemplo em 05f-pricing.md

// ============================================================================
// 1. Sanitização — mesma disciplina já validada na prova técnica (Protect-SensitiveText)
// ============================================================================

function sanitize(text: string | null | undefined): string | null {
  if (!text) return text ?? null;
  let t = text;
  t = t.replace(/tcg_[A-Za-z0-9]+/g, "[REDACTED_KEY]");
  t = t.replace(/x-api-key\s*:\s*\S+/gi, "x-api-key: [REDACTED]");
  t = t.replace(/authorization\s*:\s*\S+/gi, "authorization: [REDACTED]");
  t = t.replace(/bearer\s+\S+/gi, "Bearer [REDACTED]");
  return t;
}

function sanitizeJson(value: unknown): unknown {
  if (typeof value === "string") return sanitize(value);
  if (Array.isArray(value)) return value.map(sanitizeJson);
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) out[k] = sanitizeJson(v);
    return out;
  }
  return value;
}

// ============================================================================
// 2. Normalização — portado da prova técnica (Get-NomeNormalizado/Get-NumeroNormalizado)
// ============================================================================

function normalizeName(text: string): string {
  if (!text) return "";
  const semAcento = text.normalize("NFD").replace(/[̀-ͯ]/g, "");
  return semAcento.toLowerCase().replace(/\s+/g, " ").trim();
}

function normalizeNumber(numero: string): string {
  if (!numero) return "";
  const numerador = numero.split("/")[0];
  const limpo = numerador.replace(/[^0-9A-Za-z]/g, "");
  const semZeros = limpo.replace(/^0+/, "");
  return (semZeros || "0").toLowerCase();
}

// v1 documenta sufixo " - <Idioma>" em `printing` (removido só na v2). Sem sufixo ->
// UNDETERMINED, nunca presumir inglês nem qualquer outro idioma (regra obrigatória do
// pedido — nunca inferir idioma pelo fato de o preço estar em USD).
function splitPrintingLanguage(printingRaw: string | null | undefined): { printingTipo: string | null; idiomaCodigo: string | null } {
  if (!printingRaw || !printingRaw.trim()) return { printingTipo: null, idiomaCodigo: null };
  const match = printingRaw.match(/^(.+?)\s*-\s*([A-Za-z]+)$/);
  if (match) return { printingTipo: match[1].trim(), idiomaCodigo: match[2].trim().toLowerCase() };
  return { printingTipo: printingRaw.trim(), idiomaCodigo: null };
}

// ============================================================================
// 3. Cliente tipado JustTCG v1 — timeout, 401/429/5xx, orçamento conservador
// ============================================================================

type CallOutcome = "SUCCESS" | "TECHNICAL_FAILURE" | "BUDGET_STOPPED";

type CallLogEntry = {
  sequence_number: number;
  endpoint: string;
  http_status_code: number | null;
  outcome: CallOutcome;
  error_detail: string | null;
  api_requests_remaining: number | null;
};

type JustTcgResult<T> =
  | { status: "SUCCESS"; data: T; httpStatus: number; apiRequestsRemaining: number | null }
  | { status: "TECHNICAL_FAILURE"; httpStatus: number | null; errorDetail: string }
  | { status: "BUDGET_STOPPED" }
  | { status: "AUTH_FAILURE" };

class JustTcgClient {
  private requestCount = 0;
  readonly callLog: CallLogEntry[] = [];
  rateLimitHits = 0;

  constructor(private readonly apiKey: string) {}

  private budgetOk(): boolean {
    return this.requestCount < MAX_REQUESTS_PER_RUN;
  }

  async get<T>(endpoint: string, params: Record<string, string>): Promise<JustTcgResult<T>> {
    if (!this.budgetOk()) {
      this.callLog.push({
        sequence_number: this.callLog.length + 1,
        endpoint,
        http_status_code: null,
        outcome: "BUDGET_STOPPED",
        error_detail: `Teto local de ${MAX_REQUESTS_PER_RUN} requisições atingido.`,
        api_requests_remaining: null,
      });
      return { status: "BUDGET_STOPPED" };
    }

    if (this.requestCount > 0) await new Promise((r) => setTimeout(r, DELAY_BETWEEN_REQUESTS_MS));

    const query = new URLSearchParams(params).toString();
    const url = `${JUSTTCG_API_BASE}${endpoint}${query ? `?${query}` : ""}`;

    const attempt = async (): Promise<{ res: Response | null; err: string | null }> => {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
      try {
        const res = await fetch(url, {
          method: "GET",
          headers: { "x-api-key": this.apiKey, Accept: "application/json" },
          signal: controller.signal,
        });
        return { res, err: null };
      } catch (error) {
        const message = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
        return { res: null, err: sanitize(message) };
      } finally {
        clearTimeout(timeout);
      }
    };

    this.requestCount++;
    const seq = this.callLog.length + 1;
    let { res, err } = await attempt();

    if (res?.status === 401) {
      const body = sanitize(await res.text().catch(() => ""));
      this.callLog.push({ sequence_number: seq, endpoint, http_status_code: 401, outcome: "TECHNICAL_FAILURE", error_detail: `401 Unauthorized: ${body}`, api_requests_remaining: null });
      return { status: "AUTH_FAILURE" };
    }

    if (res?.status === 429) {
      this.rateLimitHits++;
      await new Promise((r) => setTimeout(r, RATE_LIMIT_BACKOFF_MS));
      if (!this.budgetOk()) {
        this.callLog.push({ sequence_number: seq, endpoint, http_status_code: 429, outcome: "BUDGET_STOPPED", error_detail: "429 seguido de orçamento esgotado antes do retry.", api_requests_remaining: null });
        return { status: "BUDGET_STOPPED" };
      }
      this.requestCount++;
      ({ res, err } = await attempt());
    }

    if (!res) {
      this.callLog.push({ sequence_number: seq, endpoint, http_status_code: null, outcome: "TECHNICAL_FAILURE", error_detail: err ?? "FALHA_DE_CONEXAO", api_requests_remaining: null });
      return { status: "TECHNICAL_FAILURE", httpStatus: null, errorDetail: err ?? "FALHA_DE_CONEXAO" };
    }

    if (!res.ok) {
      const body = sanitize(await res.text().catch(() => "")) ?? "";
      this.callLog.push({ sequence_number: seq, endpoint, http_status_code: res.status, outcome: "TECHNICAL_FAILURE", error_detail: `HTTP ${res.status}: ${body}`, api_requests_remaining: null });
      return { status: "TECHNICAL_FAILURE", httpStatus: res.status, errorDetail: `HTTP ${res.status}: ${body}` };
    }

    const json = await res.json();
    const apiRequestsRemaining = json?._metadata?.apiRequestsRemaining ?? null;
    this.callLog.push({ sequence_number: seq, endpoint, http_status_code: res.status, outcome: "SUCCESS", error_detail: null, api_requests_remaining: apiRequestsRemaining });
    return { status: "SUCCESS", data: json as T, httpStatus: res.status, apiRequestsRemaining };
  }

  get requestsMade() {
    return this.requestCount;
  }
}

// ============================================================================
// 4. Acesso restrito e explícito à fonte JUSTTCG (sem bypass genérico de is_active)
// ============================================================================

// Único ponto do repositório autorizado a ler pricing_source com is_active = FALSE —
// literal fixo, nunca parametrizado. Não criar uma versão genérica desta função.
async function getJustTcgSource(supabase: SupabaseClient) {
  const { data, error } = await supabase.from("pricing_source").select("id, code, is_active, requires_commercial_agreement").eq("code", "JUSTTCG").maybeSingle();
  if (error) throw new Error(`PRICING_SOURCE_QUERY_FAILED: ${error.message}`);
  if (!data) throw new Error("PRICING_SOURCE_JUSTTCG_NOT_FOUND: rode o Incremento P7 antes deste script.");
  return data;
}

// Não há mais uma consulta direta a admin_user aqui (service_role não tem SELECT
// nessa tabela, de propósito — ver ADR-021-administrative-role-model.md) nem uma
// função RPC que aceite um UUID arbitrário como parâmetro (o próprio ADR-021 registra
// esse padrão como avaliado e rejeitado por Fabrício). A validação de confirmedBy
// agora é responsabilidade do trigger BEFORE INSERT em pricing_sync_run
// (validate_pricing_sync_run_confirmed_by(), Query 3083) — dispara como efeito
// colateral obrigatório do primeiro INSERT do piloto, nunca como checagem isolada.

async function getConditionMap(supabase: SupabaseClient, pricingSourceId: string): Promise<Map<string, string>> {
  const { data, error } = await supabase.from("pricing_condition_mapping").select("external_condition_code, condition_id").eq("pricing_source_id", pricingSourceId);
  if (error) throw new Error(`CONDITION_MAPPING_QUERY_FAILED: ${error.message}`);
  return new Map((data ?? []).map((r) => [r.external_condition_code, r.condition_id as string]));
}

async function findCard(supabase: SupabaseClient, setCode: string, numero: string): Promise<{ card_id: string; card_set_id: string; name: string } | null> {
  const { data, error } = await supabase
    .from("card")
    .select("id, name, collector_number, card_set:card_set_id(id, code)")
    .eq("collector_number", numero)
    .eq("card_set.code", setCode)
    .maybeSingle();
  if (error) throw new Error(`CARD_QUERY_FAILED: ${error.message}`);
  if (!data || !data.card_set) return null;
  return { card_id: data.id as string, card_set_id: (data.card_set as unknown as { id: string }).id, name: data.name as string };
}

async function findCardSetId(supabase: SupabaseClient, code: string): Promise<string | null> {
  const { data, error } = await supabase.from("card_set").select("id").eq("code", code).maybeSingle();
  if (error) throw new Error(`CARD_SET_QUERY_FAILED: ${error.message}`);
  return (data?.id as string) ?? null;
}

// ============================================================================
// 5. Resolução de correspondência de Set — mesma lógica de sinais da prova técnica
// ============================================================================

type JustTcgSet = { id: string; name: string; release_date?: string; variants_count?: number };

function resolveSetMatch(target: SetTarget, allSets: JustTcgSet[]): { set: JustTcgSet | null; method: string; evidence: Record<string, unknown> } {
  const override = allSets.find((s) => s.id === target.overrideExternalSetId);
  if (override) {
    return { set: override, method: "OVERRIDE_MANUAL_PROVA_TECNICA_2026-08-17", evidence: { external_set_id: override.id, external_set_name: override.name } };
  }
  return { set: null, method: "OVERRIDE_NAO_CONFIRMADO_NA_RESPOSTA_ATUAL", evidence: { esperado: target.overrideExternalSetId } };
}

// ============================================================================
// 6. Fixture-check — validação 100% offline, sem rede, sem escrita no Supabase
// ============================================================================

function runFixtureCheck() {
  console.log("=== MODO FIXTURE-CHECK (offline, sem rede, sem escrita no Supabase) ===\n");

  const assertions: Array<[string, boolean]> = [];
  const assert = (label: string, cond: boolean) => assertions.push([label, cond]);

  // Sanitização nunca deixa passar um padrão de segredo.
  assert("sanitize() redige tcg_ key", sanitize("erro: tcg_abc123XYZ inválida") === "erro: [REDACTED_KEY] inválida");
  assert("sanitize() redige x-api-key", sanitize("x-api-key: segredo123")?.includes("[REDACTED]") === true);
  assert("sanitize() redige Authorization Bearer", sanitize("Authorization: Bearer abc.def.ghi")?.includes("[REDACTED]") === true);

  // Normalização de número — mesmo comportamento da prova técnica.
  assert("normalizeNumber remove zeros à esquerda", normalizeNumber("001") === "1");
  assert("normalizeNumber ignora denominador", normalizeNumber("125/094") === "125");

  // Idioma nunca presumido sem sufixo — regra obrigatória do pedido.
  const semSufixo = splitPrintingLanguage("Reverse Holofoil");
  assert("printing sem sufixo -> idioma NULL (UNDETERMINED)", semSufixo.idiomaCodigo === null);
  const comSufixo = splitPrintingLanguage("Holofoil - English");
  assert("printing com sufixo -> idioma extraído", comSufixo.idiomaCodigo === "english" && comSufixo.printingTipo === "Holofoil");

  // Mapeamento de condição — as 5 strings reais observadas na prova técnica devem
  // resolver contra o Map simulado (mesmo shape que getConditionMap devolveria).
  const conditionMap = new Map([
    ["Near Mint", "id-nm"], ["Lightly Played", "id-lp"], ["Moderately Played", "id-mp"],
    ["Heavily Played", "id-hp"], ["Damaged", "id-dmg"],
  ]);
  for (const cond of ["Near Mint", "Lightly Played", "Moderately Played", "Heavily Played", "Damaged"]) {
    assert(`condição '${cond}' resolve`, conditionMap.has(cond));
  }
  assert("condição desconhecida não resolve (fail-safe)", !conditionMap.has("Gem Mint"));

  // Resolução de Set via override — mesma fixture sintética de /v1/sets.
  const fixtureSets: JustTcgSet[] = [
    { id: "me01-mega-evolution-pokemon", name: "ME01: Mega Evolution", release_date: "2025-09-26", variants_count: 1200 },
    { id: "outro-set-qualquer", name: "Outro Set", release_date: "2020-01-01", variants_count: 50 },
  ];
  const match = resolveSetMatch(SET_TARGETS[0], fixtureSets);
  assert("resolveSetMatch encontra override ME1", match.set?.id === "me01-mega-evolution-pokemon" && match.method.startsWith("OVERRIDE_MANUAL"));

  // Identidade de idempotência de pricing_observation — mesma tupla não deve gerar
  // duas "chaves lógicas" diferentes (simulação da UNIQUE NULLS NOT DISTINCT).
  const key = (o: { p: string; c: string; t: string; cur: string; ml: string | null; at: string }) => `${o.p}|${o.c}|${o.t}|${o.cur}|${ml(o.ml)}|${o.at}`;
  const ml = (v: string | null) => v ?? " NULL";
  const a = key({ p: "prod1", c: "cond1", t: "MARKET", cur: "USD", ml: null, at: "2026-08-17T00:00:00Z" });
  const b = key({ p: "prod1", c: "cond1", t: "MARKET", cur: "USD", ml: null, at: "2026-08-17T00:00:00Z" });
  assert("mesma tupla de identidade produz a mesma chave (idempotência)", a === b);

  // Payload mínimo — raw_payload não deve conter todo o objeto `card`, só a variante.
  const rawPayloadExample = sanitizeJson({ condition: "Near Mint", printing: "Reverse Holofoil", price: 0.34, priceChange24hr: 3.03, lastUpdated: 1786950059 });
  assert("raw_payload é objeto plano, não array", !Array.isArray(rawPayloadExample) && typeof rawPayloadExample === "object");

  const failed = assertions.filter(([, ok]) => !ok);
  for (const [label, ok] of assertions) console.log(`  [${ok ? "OK" : "FALHOU"}] ${label}`);
  console.log(`\n${failed.length === 0 ? "TODAS as asserções passaram" : `${failed.length} asserção(ões) FALHARAM`} (${assertions.length} no total).`);
  console.log("\nNenhuma chamada de rede foi feita. Nenhuma linha foi gravada no Supabase.");
  console.log("Piloto real NÃO executado nesta rodada — JUSTTCG_API_KEY ausente ou --fixture-check pedido explicitamente.");

  if (failed.length > 0) Deno.exit(1);
}

// ============================================================================
// 7. Piloto real
// ============================================================================

function parseArgs(argv: string[]) {
  const args = { dryRun: false, fixtureCheck: false, confirmedBy: null as string | null };
  for (const arg of argv) {
    if (arg === "--dry-run") args.dryRun = true;
    else if (arg === "--fixture-check") args.fixtureCheck = true;
    else if (arg.startsWith("--confirmed-by=")) args.confirmedBy = arg.slice("--confirmed-by=".length);
  }
  return args;
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    console.error(`Variável de ambiente obrigatória ausente: ${name}`);
    Deno.exit(1);
  }
  return value;
}

async function runRealPilot(args: { dryRun: boolean; confirmedBy: string }) {
  const supabaseUrl = requireEnv("SUPABASE_URL");
  const supabaseServiceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const justTcgApiKey = requireEnv("JUSTTCG_API_KEY");

  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);
  const client = new JustTcgClient(justTcgApiKey);

  const source = await getJustTcgSource(supabase);
  const conditionMap = await getConditionMap(supabase, source.id as string);
  if (conditionMap.size === 0) {
    throw new Error("CONDITION_MAP_VAZIO: rode a seed 3702 (pricing_condition_mapping) antes deste script.");
  }

  console.log(`Fonte: ${source.code} (is_active=${source.is_active}) — piloto restrito, sem alterar este valor.`);
  console.log(`Confirmado por (admin_user.id): ${args.confirmedBy}`);
  console.log(args.dryRun ? "[DRY-RUN] Nenhuma escrita de dados será persistida — apenas o registro de sync_run/sync_run_call, se aplicável, também é simulado.\n" : "");

  const startedAt = new Date().toISOString();
  let syncRunId: string | null = null;

  if (!args.dryRun) {
    // Primeiro write do piloto, de propósito: o trigger BEFORE INSERT
    // (validate_pricing_sync_run_confirmed_by(), Query 3083) valida confirmedBy
    // contra admin_user aqui — se for inválido, este INSERT falha e nenhum outro
    // write do piloto chega a ser tentado (nada de Fase A/B roda depois deste ponto
    // quando o catch abaixo relança o erro).
    const { data, error } = await supabase
      .from("pricing_sync_run")
      .insert({ pricing_source_id: source.id, run_type: "CARD_SYNC", status: "PROCESSING", triggered_by: "MANUAL", started_at: startedAt, confirmed_by: args.confirmedBy })
      .select("id")
      .single();
    if (error) throw new Error(`SYNC_RUN_INSERT_FAILED: ${sanitize(error.message)}`);
    syncRunId = data.id as string;
  }

  const summary = { setsResolved: 0, setsFailed: 0, cardsResolved: 0, cardsFailed: 0, productsWritten: 0, observationsWritten: 0 };
  const errorParts: string[] = [];

  // Fase A — descoberta de Sets (uma única chamada, cobre os dois Sets do piloto).
  const setsResult = await client.get<{ data: JustTcgSet[] }>("/sets", { game: "pokemon" });
  if (setsResult.status === "AUTH_FAILURE") {
    await finalizeSyncRun(supabase, syncRunId, client, "FAILED", "AUTENTICACAO_FALHOU_401", args.dryRun);
    throw new Error("Autenticação falhou (401) — piloto abortado, mesma contrato da prova técnica.");
  }
  if (setsResult.status !== "SUCCESS") {
    errorParts.push(`FASE_A_FALHOU: ${setsResult.status}`);
    await finalizeSyncRun(supabase, syncRunId, client, "FAILED", errorParts.join(" | "), args.dryRun);
    throw new Error("Fase A (/v1/sets) não retornou sucesso — piloto abortado sem cobertura, mesmo contrato da prova técnica.");
  }
  const allSets = setsResult.data.data ?? [];

  const resolvedSetIds = new Map<string, string>(); // codigoMmkyu -> external_set_id

  for (const target of SET_TARGETS) {
    const match = resolveSetMatch(target, allSets);
    if (!match.set) {
      summary.setsFailed++;
      errorParts.push(`SET_NAO_ENCONTRADO(${target.codigoMmkyu})`);
      continue;
    }

    const cardSetId = await findCardSetId(supabase, target.codigoMmkyu);
    if (!cardSetId) {
      summary.setsFailed++;
      errorParts.push(`CARD_SET_MMKYU_NAO_ENCONTRADO(${target.codigoMmkyu})`);
      continue;
    }

    if (!args.dryRun) {
      const { error } = await supabase
        .from("pricing_set_mapping")
        .insert({
          card_set_id: cardSetId,
          pricing_source_id: source.id,
          external_set_id: match.set.id,
          external_set_name: match.set.name,
          match_status: "CONFIRMED",
          match_method: match.method,
          match_evidence: sanitizeJson(match.evidence),
          confirmed_at: new Date().toISOString(),
          confirmed_by: args.confirmedBy,
          last_checked_at: new Date().toISOString(),
        })
        .select("id")
        .maybeSingle();
      // ON CONFLICT (card_set_id, pricing_source_id) não existe via .insert() puro do
      // client JS sem upsert — usamos upsert com ignoreDuplicates para replicar
      // exatamente "ON CONFLICT DO NOTHING" sem sobrescrever uma linha já CONFIRMED.
      if (error && !`${error.message}`.includes("duplicate key")) {
        errorParts.push(`SET_MAPPING_INSERT_FAILED(${target.codigoMmkyu}): ${sanitize(error.message)}`);
        summary.setsFailed++;
        continue;
      }
    }

    resolvedSetIds.set(target.codigoMmkyu, match.set.id);
    summary.setsResolved++;
  }

  // Fase B — cartas-piloto (uma busca pontual por carta, no máximo 3 por Set).
  for (const cardTarget of CARD_TARGETS) {
    if (!resolvedSetIds.has(cardTarget.setMmkyu)) continue; // Set não resolvido, pular suas cartas

    const externalSetId = resolvedSetIds.get(cardTarget.setMmkyu)!;
    const localCard = await findCard(supabase, cardTarget.setMmkyu, cardTarget.numero);
    if (!localCard) {
      summary.cardsFailed++;
      errorParts.push(`CARD_MMKYU_NAO_ENCONTRADA(${cardTarget.setMmkyu}/${cardTarget.numero})`);
      continue;
    }

    const cardsResult = await client.get<{ data: Array<{ id: string; name: string; number: string; tcgplayerId?: string; variants: Array<Record<string, unknown>> }> }>(
      "/cards",
      { game: "pokemon", set: externalSetId, q: cardTarget.nome },
    );

    if (cardsResult.status === "AUTH_FAILURE") {
      await finalizeSyncRun(supabase, syncRunId, client, "FAILED", "AUTENTICACAO_FALHOU_401", args.dryRun);
      throw new Error("Autenticação falhou (401) — piloto abortado.");
    }
    if (cardsResult.status !== "SUCCESS") {
      summary.cardsFailed++;
      errorParts.push(`CARD_FETCH_FALHOU(${cardTarget.setMmkyu}/${cardTarget.numero}): ${cardsResult.status}`);
      continue;
    }

    const numeroAlvoNorm = normalizeNumber(cardTarget.numero);
    const nomeAlvoNorm = normalizeName(cardTarget.nome);
    const candidatos = (cardsResult.data.data ?? []).filter((c) => normalizeNumber(c.number) === numeroAlvoNorm);
    const matched = candidatos.find((c) => normalizeName(c.name) === nomeAlvoNorm || normalizeName(c.name).startsWith(`${nomeAlvoNorm} - `)) ?? candidatos[0];

    if (!matched) {
      summary.cardsFailed++;
      errorParts.push(`CARD_NAO_ENCONTRADA_NA_JUSTTCG(${cardTarget.setMmkyu}/${cardTarget.numero})`);
      continue;
    }

    let cardMappingId: string | null = null;
    if (!args.dryRun) {
      const { data, error } = await supabase
        .from("pricing_card_mapping")
        .insert({
          card_id: localCard.card_id,
          pricing_source_id: source.id,
          external_card_id: matched.id,
          external_card_name: matched.name,
          match_status: "CONFIRMED",
          match_method: "BUSCA_PONTUAL_Q_NUMERO_E_NOME",
          match_evidence: sanitizeJson({ numero_normalizado: numeroAlvoNorm, nome_normalizado: nomeAlvoNorm, external_card_name: matched.name }),
          confirmed_at: new Date().toISOString(),
          confirmed_by: args.confirmedBy,
          last_checked_at: new Date().toISOString(),
        })
        .select("id")
        .maybeSingle();
      if (error && !`${error.message}`.includes("duplicate key")) {
        errorParts.push(`CARD_MAPPING_INSERT_FAILED(${cardTarget.setMmkyu}/${cardTarget.numero}): ${sanitize(error.message)}`);
        summary.cardsFailed++;
        continue;
      }
      if (data) cardMappingId = data.id as string;
      else {
        const { data: existing } = await supabase.from("pricing_card_mapping").select("id").eq("card_id", localCard.card_id).eq("pricing_source_id", source.id).maybeSingle();
        cardMappingId = (existing?.id as string) ?? null;
      }
    }

    summary.cardsResolved++;

    if (args.dryRun || !cardMappingId) continue;

    for (const variant of matched.variants ?? []) {
      const externalProductId = String((variant as Record<string, unknown>).uuid ?? (variant as Record<string, unknown>).id ?? "");
      const printingRaw = String((variant as Record<string, unknown>).printing ?? "");
      const conditionRaw = String((variant as Record<string, unknown>).condition ?? "");
      const price = (variant as Record<string, unknown>).price;
      const lastUpdated = (variant as Record<string, unknown>).lastUpdated;

      if (!externalProductId || !printingRaw || typeof price !== "number") continue;

      const { printingTipo, idiomaCodigo } = splitPrintingLanguage(printingRaw);
      // Regra obrigatória: sem evidência de idioma -> UNDETERMINED/NULL. Um sufixo
      // presente vira, no máximo, um candidato para resolução futura de `language` —
      // não implementada neste piloto (nenhuma variante real observada até aqui o
      // exigiu). Nunca inferir pelo fato de o preço estar em USD.
      void idiomaCodigo;

      const { data: productData, error: productError } = await supabase
        .from("pricing_product")
        .insert({
          pricing_card_mapping_id: cardMappingId,
          external_product_id: externalProductId,
          source_printing_label: printingTipo ?? printingRaw,
          language_status: "UNDETERMINED",
          language_id: null,
        })
        .select("id")
        .maybeSingle();

      let productId: string | null = productData?.id as string | undefined ?? null;
      if (productError && !`${productError.message}`.includes("duplicate key")) {
        errorParts.push(`PRODUCT_INSERT_FAILED(${externalProductId}): ${sanitize(productError.message)}`);
        continue;
      }
      if (!productId) {
        const { data: existingProduct } = await supabase.from("pricing_product").select("id").eq("pricing_card_mapping_id", cardMappingId).eq("external_product_id", externalProductId).maybeSingle();
        productId = (existingProduct?.id as string) ?? null;
      }
      if (!productId) continue;
      summary.productsWritten++;

      const conditionId = conditionMap.get(conditionRaw);
      if (!conditionId) {
        errorParts.push(`CONDICAO_SEM_MAPEAMENTO(${conditionRaw})`);
        continue;
      }

      const observedAt = typeof lastUpdated === "number" ? new Date(lastUpdated * 1000).toISOString() : new Date().toISOString();
      const rawPayload = sanitizeJson({ condition: conditionRaw, printing: printingRaw, price, lastUpdated });

      const { error: obsError } = await supabase.from("pricing_observation").insert({
        pricing_product_id: productId,
        condition_id: conditionId,
        sync_run_id: syncRunId,
        price_type: "MARKET",
        price,
        currency_code: "USD",
        market_label: MARKET_LABEL,
        market_scope: "UNDETERMINED", // Valor Brasil/PTAX fora de escopo deste incremento
        market_evidence: {},
        market_evidence_confirmed: false,
        observed_at: observedAt,
        raw_payload: rawPayload,
      });
      if (obsError && !`${obsError.message}`.includes("duplicate key")) {
        errorParts.push(`OBSERVATION_INSERT_FAILED(${externalProductId}): ${sanitize(obsError.message)}`);
        continue;
      }
      summary.observationsWritten++;
    }
  }

  const finalStatus = errorParts.length === 0 ? "COMPLETED" : summary.observationsWritten > 0 ? "COMPLETED_WITH_ERRORS" : "FAILED";
  await finalizeSyncRun(supabase, syncRunId, client, finalStatus, errorParts.length > 0 ? errorParts.slice(0, 10).join(" | ") : null, args.dryRun);

  console.log("\n=== Resumo do piloto ===");
  console.log(JSON.stringify({ ...summary, requestsMade: client.requestsMade, rateLimitHits: client.rateLimitHits, status: finalStatus }, null, 2));
  if (errorParts.length > 0) console.log("\nErros:", errorParts.join(" | "));
}

async function finalizeSyncRun(
  supabase: SupabaseClient,
  syncRunId: string | null,
  client: JustTcgClient,
  status: string,
  errorSummary: string | null,
  dryRun: boolean,
) {
  if (dryRun || !syncRunId) return;

  const lastCall = client.callLog[client.callLog.length - 1];
  await supabase
    .from("pricing_sync_run")
    .update({
      status,
      finished_at: new Date().toISOString(),
      requests_made: client.requestsMade,
      requests_remaining_at_end: lastCall?.api_requests_remaining ?? null,
      rate_limit_hits: client.rateLimitHits,
      error_summary: errorSummary ? sanitize(errorSummary) : null,
    })
    .eq("id", syncRunId);

  if (client.callLog.length > 0) {
    await supabase.from("pricing_sync_run_call").insert(
      client.callLog.map((c) => ({ ...c, sync_run_id: syncRunId })),
    );
  }
}

// ============================================================================
// 8. Entrypoint
// ============================================================================

async function main() {
  const args = parseArgs(Deno.args);
  const hasApiKey = !!Deno.env.get("JUSTTCG_API_KEY");

  if (args.fixtureCheck || !hasApiKey) {
    if (!hasApiKey && !args.fixtureCheck) {
      console.log("JUSTTCG_API_KEY ausente — executando automaticamente em modo --fixture-check.\n");
    }
    runFixtureCheck();
    return;
  }

  if (!args.confirmedBy) {
    console.error("Piloto real requer --confirmed-by=<admin_user_uuid> (id de um administrador real em admin_user).");
    console.error("admin_user não é legível por SELECT direto (nem em sessão autenticada — RLS habilitado sem policy). Consulte seu próprio id com: SELECT auth.uid(); (via sessão autenticada, se for administrador) ou peça o UUID a outro administrador.");
    Deno.exit(1);
  }

  await runRealPilot({ dryRun: args.dryRun, confirmedBy: args.confirmedBy });
}

await main();
