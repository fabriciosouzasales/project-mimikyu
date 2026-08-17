/*
Project Mimikyu
Script administrativo standalone: sync-ptax-fx-rate
Incremento P9 — Ingestão PTAX (2026-08-17).

Objetivo: primeiro fluxo real de ingestão de câmbio, buscando a cotação diária PTAX
USD->BRL na API oficial e pública do Banco Central (Portal de Dados Abertos, API Olinda
PTAX v1) e persistindo append-only em pricing_fx_rate. Não converte pricing_observation,
não implementa "Valor Brasil", não é scheduler/cron e não tem UI — deliberadamente fora
de escopo deste incremento (ver 05f-pricing.md, seção "Incremento P9").

Arquitetura (decisão registrada, não uma Edge Function): mesmo precedente estrutural de
scripts/sync-justtcg-pricing.ts (Incremento P8) e scripts/import-manual-assets.ts — roda
localmente, sob demanda, com a Service Role Key do projeto, nunca é implantado no
Supabase. "Acionado manualmente por administrador" aqui significa que é o próprio
administrador (Fabrício) quem executa este script na sua máquina, com suas próprias
variáveis de ambiente — o mesmo padrão já usado para SQL (CLAUDE.md: "Quem executa o SQL
no Supabase, por padrão, é Fabrício"). Não existe tela nem Route Handler para este
piloto.

Credencial: a API Olinda PTAX do Banco Central é pública e não exige nenhuma API key —
não há JUSTTCG_API_KEY equivalente para o BCB, e nenhuma chave é solicitada, aceita ou
lida para este propósito. A única credencial em jogo é a Service Role Key do próprio
Supabase (SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY), exclusivamente por variável de
ambiente, nunca argumento de linha de comando, nunca logada, nunca persistida em arquivo
ou documentação. Se SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY estiverem ausentes (ou se
--fixture-check for pedido explicitamente), o script roda 100% offline contra uma
fixture sintética embutida, validando parsing/seleção de venda/idempotência sem nenhuma
chamada de rede e sem nenhuma escrita no Supabase — e imprime um aviso explícito de que
nenhum piloto real foi executado.

Decisão cambial (registrada em 05f-pricing.md, "Incremento P9", aprovada por Fabrício via
AskUserQuestion antes desta implementação — CLAUDE.md exige decisão registrada em
documentação antes de código):
  - grava exclusivamente `cotacaoVenda` (nunca `cotacaoCompra`, nunca as duas);
  - `rate_date` é sempre a data efetiva publicada pelo BCB (extraída de
    `dataHoraCotacao`), nunca a data em que o script rodou;
  - fins de semana/feriados sem cotação publicada não geram linha nenhuma — nenhuma taxa
    artificial, nenhuma replicação da última cotação disponível sob uma rate_date que não
    é a real;
  - `rate_source_code` permanece 'BCB_PTAX' (já é o DEFAULT da coluna, Query 3060).

Correção pós-piloto (2026-08-17): a primeira versão deste script usava o nome de
parâmetro errado na URL (`dataFinal` em vez de `dataFinalCotacao`), causando `HTTP 400`
no piloto real executado por Fabrício via `Executar-P9-PTAX-Local.ps1` — exatamente a
lacuna já sinalizada abaixo ("forma da resposta não confirmada por chamada de rede
real"), só que no lado da requisição, não da resposta. Corrigido a partir de um teste
direto bem-sucedido (`Invoke-RestMethod`, executado por Fabrício, 6/6 cotações
retornadas) — a URL exata usada nesse teste está fixada, caractere a caractere, em
`buildPtaxPeriodUrl()`/`runFixtureCheck()` abaixo, nunca reconstituída de memória geral
de novo.

Validação defensiva da forma da resposta: a forma exata do JSON retornado pela API Olinda
(`{"value": [{"cotacaoCompra", "cotacaoVenda", "dataHoraCotacao"}, ...]}`) segue validada
sem presunção silenciosa: validatePtaxResponseShape() falha alto e explícito se a resposta
real não tiver exatamente esse formato, em vez de tentar continuar com um parsing
best-effort. O corpo de um erro HTTP não-2xx é sanitizado e truncado antes de aparecer em
qualquer log/mensagem de erro (ver truncateForDiagnostics(), abaixo) — diagnóstico
suficiente sem arriscar um payload gigante ou um segredo eventualmente embutido.

Fora de escopo (confirmado, não implementado aqui): conversão de pricing_observation,
"Valor Brasil", scheduler/cron, qualquer tela de frontend, qualquer alteração de dado da
JustTCG, armazenamento da cotação de compra (exigiria segunda coluna, decisão futura).

Uso:

  # PowerShell — defina as variáveis de ambiente ANTES de rodar. NUNCA cole a Service
  # Role Key em chat/log. Não existe (nem é necessária) uma chave do Banco Central.
  $env:SUPABASE_URL = "https://qjfutqujxrbzgrtkpgkg.supabase.co"
  $env:SUPABASE_SERVICE_ROLE_KEY = "<service_role_key>"

  # Validação offline (sempre segura, não requer nenhuma variável de rede/segredo):
  deno run --allow-env scripts/sync-ptax-fx-rate.ts --fixture-check

  # Piloto real, datas recentes hardcoded abaixo (ver PILOT_DATA_INICIAL/PILOT_DATA_FINAL):
  deno run --allow-net --allow-env scripts/sync-ptax-fx-rate.ts

  # Piloto real, sem gravar nada (mesma Convenção #7 do projeto — validar antes de executar):
  deno run --allow-net --allow-env scripts/sync-ptax-fx-rate.ts --dry-run
*/

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

// ============================================================================
// 0. Configuração fixa do piloto (Incremento P9 — NÃO ampliar sem nova decisão)
// ============================================================================

const BCB_PTAX_API_BASE = "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata";
const REQUEST_TIMEOUT_MS = 15_000;

const FROM_CURRENCY = "USD";
const TO_CURRENCY = "BRL";
const RATE_SOURCE_CODE = "BCB_PTAX"; // já é o DEFAULT da coluna (Query 3060) — explícito aqui por clareza

// Piloto pequeno com datas recentes (formato MM-DD-YYYY exigido pela API Olinda),
// hardcoded de propósito — cobre um intervalo curto que inclui pelo menos um fim de
// semana, exercitando deliberadamente a regra "sem taxa artificial em dia sem pregão".
// Nunca ampliar para um intervalo largo sem decisão explícita nova.
const PILOT_DATA_INICIAL = "08-10-2026"; // segunda-feira
const PILOT_DATA_FINAL = "08-17-2026"; // segunda-feira seguinte (inclui o fim de semana 15-16/08)

// ============================================================================
// 1. Sanitização — mesma disciplina já usada em sync-justtcg-pricing.ts (Incremento P8)
// ============================================================================

// pricing_fx_rate não tem coluna de payload bruto/erro persistido (tabela enxuta,
// append-only, ver 05f-pricing.md) — sanitize()/sanitizeJson() aqui protegem o que é
// impresso em console/log, defesa em profundidade mesmo a API do BCB sendo pública e
// não exigindo credencial (o mesmo padrão redige Authorization/Bearer/x-api-key caso
// algum dia um proxy/gateway intermediário exija um cabeçalho de autenticação).
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
// 2. Cliente HTTP mínimo — timeout, sem retry automático (endpoint público, sem 401/429
//    documentado no contrato oficial consultado; falha técnica é reportada, não engolida)
// ============================================================================

// Limite de caracteres do corpo de um erro HTTP não-2xx antes de entrar em qualquer
// log/mensagem de erro — diagnóstico suficiente (o corpo de erro OData do BCB é
// tipicamente uma linha curta) sem arriscar um payload grande ou ilegível no console.
const MAX_ERROR_BODY_CHARS = 500;

function truncateForDiagnostics(text: string): string {
  if (text.length <= MAX_ERROR_BODY_CHARS) return text;
  return `${text.slice(0, MAX_ERROR_BODY_CHARS)}... [truncado — ${text.length} caracteres no total]`;
}

type PtaxFetchResult =
  | { status: "SUCCESS"; json: unknown }
  | { status: "TECHNICAL_FAILURE"; detail: string };

async function fetchPtaxPeriod(dataInicial: string, dataFinalCotacao: string): Promise<PtaxFetchResult> {
  const url = buildPtaxPeriodUrl(dataInicial, dataFinalCotacao);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const res = await fetch(url, { method: "GET", headers: { Accept: "application/json" }, signal: controller.signal });
    if (!res.ok) {
      const rawBody = await res.text().catch(() => "");
      const body = sanitize(truncateForDiagnostics(rawBody)) ?? "";
      return { status: "TECHNICAL_FAILURE", detail: `HTTP ${res.status}: ${body}` };
    }
    const json = await res.json();
    return { status: "SUCCESS", json };
  } catch (error) {
    const message = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
    const detail = message === "AbortError" || /aborted/i.test(message) ? `TIMEOUT_APOS_${REQUEST_TIMEOUT_MS}MS` : sanitize(truncateForDiagnostics(message)) ?? "FALHA_DE_CONEXAO";
    return { status: "TECHNICAL_FAILURE", detail };
  } finally {
    clearTimeout(timeout);
  }
}

// Formato de data exigido pela API Olinda nos literais da query string: MM-DD-YYYY
// (confirmado pelo teste real bem-sucedido citado no cabeçalho deste arquivo — mesmo
// formato já usado em PILOT_DATA_INICIAL/PILOT_DATA_FINAL, acima). Validação mantida
// estrita de propósito: um valor fora do formato nunca deve virar uma URL silenciosamente
// malformada — falha alto, antes mesmo de tentar a requisição.
const PTAX_REQUEST_DATE_FORMAT = /^\d{2}-\d{2}-\d{4}$/;

// Sintaxe OData exata confirmada por chamada de rede real bem-sucedida (Invoke-RestMethod,
// executado por Fabrício em 2026-08-17, 6/6 cotações do período retornadas) — corrige a
// hipótese anterior deste arquivo, que usava `dataFinal` em vez do nome de parâmetro real,
// `dataFinalCotacao`, causando HTTP 400 no piloto. A ordem exata dos quatro segmentos da
// query string (@dataInicial, @dataFinalCotacao, $format, $select) também importa para o
// fixture de regressão em runFixtureCheck() (comparação literal, caractere a caractere) —
// nunca reordenar ou renomear um parâmetro aqui sem reconfirmar contra uma chamada real.
// `$select` restringe a resposta aos três campos que este script realmente usa (payload
// mínimo, já exigido desde a primeira versão deste incremento) — `cotacaoCompra` continua
// selecionado mesmo não sendo persistido, porque validatePtaxResponseShape() o exige como
// prova de que a API respondeu no formato documentado (as duas cotações, nunca uma só).
function buildPtaxPeriodUrl(dataInicial: string, dataFinalCotacao: string): string {
  if (!PTAX_REQUEST_DATE_FORMAT.test(dataInicial)) {
    throw new Error(`DATA_INICIAL_FORMATO_INVALIDO: '${dataInicial}' não está no formato MM-DD-YYYY exigido pela API Olinda.`);
  }
  if (!PTAX_REQUEST_DATE_FORMAT.test(dataFinalCotacao)) {
    throw new Error(`DATA_FINAL_COTACAO_FORMATO_INVALIDO: '${dataFinalCotacao}' não está no formato MM-DD-YYYY exigido pela API Olinda.`);
  }
  return (
    `${BCB_PTAX_API_BASE}/CotacaoDolarPeriodo(dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)` +
    `?@dataInicial='${dataInicial}'&@dataFinalCotacao='${dataFinalCotacao}'` +
    `&$format=json&$select=cotacaoCompra,cotacaoVenda,dataHoraCotacao`
  );
}

// ============================================================================
// 3. Parsing defensivo — nunca presumir a forma da resposta silenciosamente
// ============================================================================

type PtaxRawItem = { cotacaoCompra: number; cotacaoVenda: number; dataHoraCotacao: string };

type PtaxRate = { rate_date: string; rate: number };

// Falha alto e explícito se a resposta real não tiver exatamente o formato documentado
// (`{"value": [{"cotacaoCompra", "cotacaoVenda", "dataHoraCotacao"}, ...]}`) — a forma
// exata não foi confirmada por uma chamada de rede bem-sucedida nesta sessão (ver nota no
// cabeçalho do arquivo), então este script nunca tenta um parsing "best effort" sobre uma
// forma diferente da esperada; qualquer divergência aborta o item (ou a execução) com uma
// mensagem específica de qual campo/tipo não bateu, nunca um erro genérico.
function validatePtaxResponseShape(json: unknown): PtaxRawItem[] {
  if (!json || typeof json !== "object" || !("value" in json)) {
    throw new Error("BCB_RESPONSE_SHAPE_INVALID: campo 'value' ausente na resposta.");
  }
  const value = (json as { value: unknown }).value;
  if (!Array.isArray(value)) {
    throw new Error("BCB_RESPONSE_SHAPE_INVALID: 'value' não é um array.");
  }
  return value.map((item, index) => {
    if (!item || typeof item !== "object") {
      throw new Error(`BCB_RESPONSE_SHAPE_INVALID: item [${index}] não é um objeto.`);
    }
    const obj = item as Record<string, unknown>;
    if (typeof obj.cotacaoCompra !== "number") {
      throw new Error(`BCB_RESPONSE_SHAPE_INVALID: item [${index}].cotacaoCompra não é number.`);
    }
    if (typeof obj.cotacaoVenda !== "number") {
      throw new Error(`BCB_RESPONSE_SHAPE_INVALID: item [${index}].cotacaoVenda não é number.`);
    }
    if (typeof obj.dataHoraCotacao !== "string" || !obj.dataHoraCotacao) {
      throw new Error(`BCB_RESPONSE_SHAPE_INVALID: item [${index}].dataHoraCotacao ausente/inválido.`);
    }
    return { cotacaoCompra: obj.cotacaoCompra, cotacaoVenda: obj.cotacaoVenda, dataHoraCotacao: obj.dataHoraCotacao };
  });
}

// Extrai a data efetiva (YYYY-MM-DD) de dataHoraCotacao (formato observado documentado:
// "YYYY-MM-DD HH:MM:SS.mmm", possivelmente com "T" no lugar do espaço) — nunca usa a
// data em que o script rodou. Decisão registrada em 05f-pricing.md, "Incremento P9".
function extractRateDate(dataHoraCotacao: string): string {
  const dataParte = dataHoraCotacao.split(/[T ]/)[0];
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dataParte)) {
    throw new Error(`BCB_RESPONSE_SHAPE_INVALID: dataHoraCotacao '${dataHoraCotacao}' não contém uma data YYYY-MM-DD reconhecível.`);
  }
  return dataParte;
}

// Regra registrada: rate grava exclusivamente a cotação de venda — nunca a de compra,
// nunca as duas (05f-pricing.md, "Incremento P9", decisão aprovada por Fabrício).
function toPtaxRates(items: PtaxRawItem[]): PtaxRate[] {
  return items.map((item) => ({ rate_date: extractRateDate(item.dataHoraCotacao), rate: item.cotacaoVenda }));
}

// ============================================================================
// 4. Classificação de UPSERT — corrigido (2026-08-17, segunda rodada): a versão
//    anterior fazia um .insert() puro (sem .select(), Prefer: return=minimal por
//    default do supabase-js) e distinguia "novo" de "já existia" só pelo TEXTO da
//    mensagem de erro (`.includes("duplicate key")`) — frágil (depende de um
//    detalhe de implementação do Postgres, não do contrato da API) e, mais grave,
//    não é literalmente "ON CONFLICT DO NOTHING" (é uma tentativa de INSERT puro que
//    aborta com erro em conflito, capturado depois). Corrigido para usar
//    .upsert(row, { onConflict: "...", ignoreDuplicates: true }).select() —
//    onConflict aponta exatamente para as quatro colunas da UNIQUE já CONFIRMADO
//    EXECUTADO (uq_pricing_fx_rate_pair_source_date, Query 3060) e ignoreDuplicates
//    traduz para Prefer: resolution=ignore-duplicates, ou seja, literalmente
//    INSERT ... ON CONFLICT (from_currency, to_currency, rate_source_code, rate_date)
//    DO NOTHING no Postgres. .select() força Prefer: return=representation — sem
//    isso, ignoreDuplicates nunca devolveria a linha, e não haveria como distinguir
//    "inseriu de novo" de "conflito ignorado" sem erro nenhum nos dois casos. A
//    distinção passa a ser: `error` não nulo -> OTHER_ERROR; `error` nulo e `data`
//    com a linha -> NEW (inserção real); `error` nulo e `data` vazio -> CONFLICT_IGNORED
//    (a linha já existia, nada foi escrito) — nunca mais depende do texto de uma
//    mensagem de erro. `ON CONFLICT ... DO NOTHING` não escreve nada na linha
//    existente (nem tenta UPDATE) — não exige o privilégio UPDATE, que
//    `service_role` não tem em pricing_fx_rate (revogado explicitamente, Query
//    3060) — nenhuma mudança de grant/schema necessária para esta correção.
// ============================================================================

type UpsertOutcome = "NEW" | "CONFLICT_IGNORED" | "OTHER_ERROR";

function classifyUpsertResult(error: { message: string } | null, rowsReturned: number): UpsertOutcome {
  if (error) return "OTHER_ERROR";
  return rowsReturned > 0 ? "NEW" : "CONFLICT_IGNORED";
}

const PRICING_FX_RATE_CONFLICT_TARGET = "from_currency,to_currency,rate_source_code,rate_date";

// ============================================================================
// 5. Persistência — append-only, idempotente por linha (ON CONFLICT DO NOTHING real,
//    via upsert + ignoreDuplicates, mesma tupla da UNIQUE já CONFIRMADO EXECUTADO na
//    Query 3060 — ver nota da seção 4, acima)
// ============================================================================

async function persistPtaxRates(supabase: SupabaseClient, rates: PtaxRate[], dryRun: boolean) {
  const summary = { resolved: 0, written: 0, failed: 0 };
  const errorParts: string[] = [];

  for (const rate of rates) {
    if (dryRun) {
      console.log(`[DRY-RUN] gravaria: ${FROM_CURRENCY}->${TO_CURRENCY} venda=${rate.rate} rate_date=${rate.rate_date} rate_source_code=${RATE_SOURCE_CODE}`);
      continue;
    }

    const { data, error } = await supabase
      .from("pricing_fx_rate")
      .upsert(
        {
          from_currency: FROM_CURRENCY,
          to_currency: TO_CURRENCY,
          rate: rate.rate,
          rate_date: rate.rate_date,
          rate_source_code: RATE_SOURCE_CODE,
        },
        { onConflict: PRICING_FX_RATE_CONFLICT_TARGET, ignoreDuplicates: true },
      )
      .select("rate_date");

    const outcome = classifyUpsertResult(error, data?.length ?? 0);
    if (outcome === "OTHER_ERROR") {
      summary.failed++;
      errorParts.push(`FX_RATE_UPSERT_FAILED(${rate.rate_date}): ${sanitize((error as { message: string }).message)}`);
      continue;
    }
    summary.resolved++;
    if (outcome === "NEW") summary.written++;
  }

  return { summary, errorParts };
}

// ============================================================================
// 6. Fixture-check — validação 100% offline, sem rede, sem escrita no Supabase
// ============================================================================

function runFixtureCheck() {
  console.log("=== MODO FIXTURE-CHECK (offline, sem rede, sem escrita no Supabase) ===\n");

  const assertions: Array<[string, boolean]> = [];
  const assert = (label: string, cond: boolean) => assertions.push([label, cond]);

  // Sanitização nunca deixa passar um padrão de segredo.
  assert("sanitize() redige Authorization Bearer", sanitize("Authorization: Bearer abc.def.ghi")?.includes("[REDACTED]") === true);
  assert("sanitize() redige x-api-key", sanitize("x-api-key: segredo123")?.includes("[REDACTED]") === true);

  // Fixture sintética mimetizando a forma documentada da resposta da API Olinda PTAX,
  // cobrindo dias úteis normais — cotacaoCompra e cotacaoVenda sempre distintas, como a
  // documentação oficial do BCB confirma ("Retorna a Cotação de Compra e a Cotação de
  // Venda... para a data informada").
  const fixtureResponse = {
    value: [
      { cotacaoCompra: 5.4321, cotacaoVenda: 5.4327, dataHoraCotacao: "2026-08-10 13:04:41.123" },
      { cotacaoCompra: 5.4501, cotacaoVenda: 5.4508, dataHoraCotacao: "2026-08-11 13:02:18.456" },
      // 2026-08-15/16 (sáb/dom) deliberadamente AUSENTES da fixture — simula exatamente
      // o comportamento real da API do BCB em dias sem pregão/cotação PTAX publicada.
      { cotacaoCompra: 5.4610, cotacaoVenda: 5.4617, dataHoraCotacao: "2026-08-17T13:05:59.001" }, // formato com "T", também deve parsear
    ],
  };

  const parsedItems = validatePtaxResponseShape(fixtureResponse);
  assert("validatePtaxResponseShape aceita a fixture válida (3 itens)", parsedItems.length === 3);

  const rates = toPtaxRates(parsedItems);
  assert("toPtaxRates grava a cotação de VENDA, nunca a de compra", rates[0].rate === 5.4327 && rates[0].rate !== 5.4321);
  assert("extractRateDate lida com espaço como separador", rates[0].rate_date === "2026-08-10");
  assert("extractRateDate lida com 'T' como separador", rates[2].rate_date === "2026-08-17");
  assert("fixture não inclui rate_date artificial para o fim de semana (15/16-08)", !rates.some((r) => r.rate_date === "2026-08-15" || r.rate_date === "2026-08-16"));

  // Validação defensiva de forma — nunca deve silenciosamente aceitar uma resposta fora
  // do contrato documentado (regressão direta contra "presumir a forma da API").
  let shapeErrorCount = 0;
  const casosInvalidos: Array<{ nome: string; payload: unknown }> = [
    { nome: "sem campo value", payload: {} },
    { nome: "value não é array", payload: { value: "não é array" } },
    { nome: "item sem cotacaoVenda", payload: { value: [{ cotacaoCompra: 5.0, dataHoraCotacao: "2026-08-10 12:00:00" }] } },
    { nome: "item com cotacaoVenda como string", payload: { value: [{ cotacaoCompra: 5.0, cotacaoVenda: "5.4", dataHoraCotacao: "2026-08-10 12:00:00" }] } },
    { nome: "item sem dataHoraCotacao", payload: { value: [{ cotacaoCompra: 5.0, cotacaoVenda: 5.4 }] } },
  ];
  for (const caso of casosInvalidos) {
    try {
      validatePtaxResponseShape(caso.payload);
    } catch {
      shapeErrorCount++;
    }
  }
  assert(`validatePtaxResponseShape rejeita todos os ${casosInvalidos.length} casos inválidos (falha alto, nunca silencioso)`, shapeErrorCount === casosInvalidos.length);

  // Classificação de UPSERT / idempotência — corrigida (2026-08-17, segunda rodada):
  // agora decidida por `error`/quantidade de linhas retornadas (.select() após
  // .upsert(..., { ignoreDuplicates: true })), nunca por texto de mensagem de erro —
  // ver nota completa na seção 4 do arquivo, acima.
  assert("classifyUpsertResult: sem erro, 1 linha retornada -> NEW (inserção real)", classifyUpsertResult(null, 1) === "NEW");
  assert(
    "classifyUpsertResult: sem erro, 0 linhas retornadas -> CONFLICT_IGNORED (ON CONFLICT DO NOTHING real, linha já existia)",
    classifyUpsertResult(null, 0) === "CONFLICT_IGNORED",
  );
  assert(
    "classifyUpsertResult: erro presente -> OTHER_ERROR, independente do texto da mensagem (nunca mais parsing de 'duplicate key')",
    classifyUpsertResult({ message: "permission denied for table pricing_fx_rate" }, 0) === "OTHER_ERROR" &&
      classifyUpsertResult({ message: "qualquer outro erro, mesmo mencionando duplicate key por coincidência" }, 0) === "OTHER_ERROR",
  );
  assert(
    "PRICING_FX_RATE_CONFLICT_TARGET aponta exatamente para as 4 colunas da UNIQUE já CONFIRMADO EXECUTADO (Query 3060)",
    PRICING_FX_RATE_CONFLICT_TARGET === "from_currency,to_currency,rate_source_code,rate_date",
  );

  // Regressão-chave de idempotência: simula a URL exata do período do piloto — confirma
  // que a construção da URL não muda entre chamadas com os mesmos parâmetros (mesma
  // requisição, sempre determinística, pré-condição para ON CONFLICT DO NOTHING fazer
  // sentido em reexecuções).
  const url1 = buildPtaxPeriodUrl(PILOT_DATA_INICIAL, PILOT_DATA_FINAL);
  const url2 = buildPtaxPeriodUrl(PILOT_DATA_INICIAL, PILOT_DATA_FINAL);
  assert("buildPtaxPeriodUrl é determinística para os mesmos parâmetros", url1 === url2);
  assert("buildPtaxPeriodUrl usa CotacaoDolarPeriodo (não CotacaoDolarDia)", url1.includes("CotacaoDolarPeriodo"));
  assert("buildPtaxPeriodUrl pede $format=json", url1.includes("$format=json"));

  // Regressão-chave de contrato (2026-08-17): comparação literal, caractere a caractere,
  // contra a URL comprovadamente funcional (Invoke-RestMethod, executado por Fabrício,
  // 6/6 cotações do período retornadas com sucesso) — nunca uma checagem parcial
  // (.includes()) para este caso específico, já que foi exatamente um detalhe sutil do
  // nome de um parâmetro (`dataFinal` em vez de `dataFinalCotacao`) que causou o HTTP 400
  // real no piloto. Se este teste falhar no futuro, o problema está em buildPtaxPeriodUrl()
  // — nunca ajustar esta URL esperada sem antes reconfirmar contra uma chamada de rede real.
  const URL_COMPROVADAMENTE_FUNCIONAL =
    "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/CotacaoDolarPeriodo(dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)" +
    "?@dataInicial='08-10-2026'&@dataFinalCotacao='08-17-2026'&$format=json&$select=cotacaoCompra,cotacaoVenda,dataHoraCotacao";
  assert(
    "buildPtaxPeriodUrl produz exatamente a URL comprovadamente funcional (comparação literal, não .includes())",
    url1 === URL_COMPROVADAMENTE_FUNCIONAL,
  );

  // Validação estrita de formato de data na construção da URL — nunca deve gerar uma URL
  // silenciosamente malformada a partir de um valor fora do padrão MM-DD-YYYY.
  let dataInvalidaRejeitada = 0;
  const datasInvalidas = ["2026-08-10", "8-10-2026", "08/10/2026", "", "08-10-26"];
  for (const dataRuim of datasInvalidas) {
    try {
      buildPtaxPeriodUrl(dataRuim, PILOT_DATA_FINAL);
    } catch {
      dataInvalidaRejeitada++;
    }
  }
  assert(
    `buildPtaxPeriodUrl rejeita todos os ${datasInvalidas.length} formatos de data inválidos (falha alto, nunca URL malformada)`,
    dataInvalidaRejeitada === datasInvalidas.length,
  );

  // truncateForDiagnostics — corpo de erro limitado, sem cortar textos já curtos.
  const corpoCurto = "Bad Request: parametro invalido";
  assert("truncateForDiagnostics preserva corpo curto sem alteração", truncateForDiagnostics(corpoCurto) === corpoCurto);
  const corpoLongo = "x".repeat(MAX_ERROR_BODY_CHARS + 250);
  const truncado = truncateForDiagnostics(corpoLongo);
  assert(
    `truncateForDiagnostics limita corpo longo a no máximo ${MAX_ERROR_BODY_CHARS} caracteres úteis + aviso`,
    truncado.length < corpoLongo.length && truncado.startsWith("x".repeat(MAX_ERROR_BODY_CHARS)) && truncado.includes("truncado"),
  );

  const failed = assertions.filter(([, ok]) => !ok);
  for (const [label, ok] of assertions) console.log(`  [${ok ? "OK" : "FALHOU"}] ${label}`);
  console.log(`\n${failed.length === 0 ? "TODAS as asserções passaram" : `${failed.length} asserção(ões) FALHARAM`} (${assertions.length} no total).`);
  console.log("\nNenhuma chamada de rede foi feita. Nenhuma linha foi gravada no Supabase.");
  console.log("Piloto real NÃO executado nesta rodada — variáveis do Supabase ausentes ou --fixture-check pedido explicitamente.");
  console.log("Nota: buildPtaxPeriodUrl() e a forma da resposta foram confirmadas contra uma chamada de rede real bem-sucedida (Invoke-RestMethod, Fabrício, 2026-08-17, 6/6 cotações) — ver cabeçalho do arquivo; validatePtaxResponseShape() segue falhando alto se uma resposta futura divergir do formato documentado.");

  if (failed.length > 0) Deno.exit(1);
}

// ============================================================================
// 7. Piloto real
// ============================================================================

function parseArgs(argv: string[]) {
  const args = { dryRun: false, fixtureCheck: false };
  for (const arg of argv) {
    if (arg === "--dry-run") args.dryRun = true;
    else if (arg === "--fixture-check") args.fixtureCheck = true;
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

async function runRealPilot(args: { dryRun: boolean }) {
  const supabaseUrl = requireEnv("SUPABASE_URL");
  const supabaseServiceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

  console.log(`Piloto PTAX — período ${PILOT_DATA_INICIAL} a ${PILOT_DATA_FINAL} (MM-DD-YYYY), par ${FROM_CURRENCY}->${TO_CURRENCY}, fonte ${RATE_SOURCE_CODE}.`);
  console.log("Cotação gravada: VENDA (cotacaoVenda) — decisão registrada em 05f-pricing.md, Incremento P9.");
  if (args.dryRun) console.log("[DRY-RUN] Nenhuma escrita será persistida.\n");

  const fetchResult = await fetchPtaxPeriod(PILOT_DATA_INICIAL, PILOT_DATA_FINAL);
  if (fetchResult.status !== "SUCCESS") {
    console.error(`Falha técnica ao consultar a API do Banco Central: ${fetchResult.detail}`);
    Deno.exit(1);
  }

  const rawItems = validatePtaxResponseShape(fetchResult.json);
  console.log(`Resposta do BCB: ${rawItems.length} cotação(ões) publicada(s) no período (dias sem pregão simplesmente não aparecem na resposta).`);

  const rates = toPtaxRates(rawItems);
  const { summary, errorParts } = await persistPtaxRates(supabase, rates, args.dryRun);

  console.log("\n=== Resumo do piloto ===");
  console.log(JSON.stringify({ ...summary, cotacoesRecebidas: rawItems.length }, null, 2));
  if (errorParts.length > 0) {
    console.log("\nErros:", errorParts.join(" | "));
    Deno.exit(1);
  }
}

// ============================================================================
// 8. Entrypoint
// ============================================================================

async function main() {
  const args = parseArgs(Deno.args);
  const hasSupabaseEnv = !!Deno.env.get("SUPABASE_URL") && !!Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (args.fixtureCheck || !hasSupabaseEnv) {
    if (!hasSupabaseEnv && !args.fixtureCheck) {
      console.log("SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY ausentes — executando automaticamente em modo --fixture-check.\n");
    }
    runFixtureCheck();
    return;
  }

  await runRealPilot({ dryRun: args.dryRun });
}

if (import.meta.main) {
  await main();
}
