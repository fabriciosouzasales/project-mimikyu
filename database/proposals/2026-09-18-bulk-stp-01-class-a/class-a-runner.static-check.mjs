/* ============================================================================
Project Mimikyu — BULK-STP-01 / CLASSE A — Provas estáticas do runner
Arquivo...: database/proposals/2026-09-18-bulk-stp-01-class-a/class-a-runner.static-check.mjs
Versão....: 1.0
Status....: PROPOSTA — verificação local, não toca LIVE
Criado em.: 2026-09-18, em `BULK-STP-01-CLASS-A-RUNNER-STAGING-01`

O QUE ESTE ARQUIVO FAZ
  Lê class-a-runner.js como TEXTO e prova propriedades estruturais que
  precisam valer ANTES de qualquer execução. Não importa o runner, não abre
  rede, não toca no Supabase, não executa nada do runner.

COMO RODAR
  node database/proposals/2026-09-18-bulk-stp-01-class-a/class-a-runner.static-check.mjs
============================================================================ */

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(join(HERE, "class-a-runner.js"), "utf8");

/** Código executável = fonte menos comentários de bloco e de linha. */
const CODE = SRC
  .replace(/\/\*[\s\S]*?\*\//g, "")
  .replace(/^[ \t]*\/\/.*$/gm, "");

/** Código sem literais de string/template — para provas que não podem casar prosa. */
const CODE_NOSTR = CODE
  .replace(/`(?:\\.|[^`\\])*`/g, "``")
  .replace(/"(?:\\.|[^"\\])*"/g, '""')
  .replace(/'(?:\\.|[^'\\])*'/g, "''");

let pass = 0;
const fails = [];
function check(id, label, ok, detail) {
  if (ok) { pass += 1; console.log(`  OK    ${id}  ${label}`); }
  else { fails.push(`${id} ${label}${detail ? ` — ${detail}` : ""}`); console.log(`  FALHA ${id}  ${label}${detail ? ` — ${detail}` : ""}`); }
}

console.log("=".repeat(78));
console.log("BULK-STP-01 / CLASSE A — PROVAS ESTÁTICAS DO RUNNER");
console.log("=".repeat(78));

// ---------------------------------------------------------------------------
// S1 — p_row_ids = NULL não aparece em NENHUMA chamada de confirm
// ---------------------------------------------------------------------------
const confirmCalls = [...CODE.matchAll(/admin_confirm_catalog_variant_import"\s*,\s*\{([^}]*)\}/g)]
  .map((m) => m[1]);
check("S1a", "há pelo menos uma chamada de confirm", confirmCalls.length > 0, `${confirmCalls.length}`);
check(
  "S1b",
  "p_row_ids NUNCA é null/undefined/omitido no confirm",
  confirmCalls.length > 0 &&
    confirmCalls.every((a) => /p_row_ids\s*:\s*S2?\b/.test(a)) &&
    !/p_row_ids\s*:\s*(null|undefined)/.test(CODE),
  confirmCalls.join(" | ")
);

// ---------------------------------------------------------------------------
// S2 — service_role ausente
// ---------------------------------------------------------------------------
check("S2", "nenhuma menção a service_role no código executável", !/service_role/i.test(CODE));

// ---------------------------------------------------------------------------
// S3 — nenhum SQL direto / nenhuma escrita em tabela
// ---------------------------------------------------------------------------
check("S3a", "nenhum SQL direto (INSERT/UPDATE/DELETE/SELECT ... FROM)",
  !/\b(insert\s+into|update\s+\w+\s+set|delete\s+from|select\s+[^;]*\s+from\s+)\b/i.test(CODE));
check("S3b", "nenhum endpoint execute_sql / pg_ / rpc de SQL cru",
  !/execute_sql|pg_query|\/sql\b/i.test(CODE));
check("S3c", "nenhum método HTTP de escrita direta em tabela (POST/PATCH/DELETE em /rest/v1/<tabela>)",
  !/method:\s*"(PATCH|PUT|DELETE)"/i.test(CODE) &&
  !/rest\/v1\/(?!rpc\/)[a-z_]+`?,\s*\{\s*method:\s*"POST"/i.test(CODE));

// ---------------------------------------------------------------------------
// S4 — só as duas RPCs autorizadas
// ---------------------------------------------------------------------------
const rpcNames = [...CODE.matchAll(/rpc\(\s*"([a-z_]+)"/g)].map((m) => m[1]);
const allowed = new Set(["admin_decide_catalog_variant_import_row", "admin_confirm_catalog_variant_import"]);
check("S4", "somente as 2 RPCs autorizadas são chamadas",
  rpcNames.length > 0 && rpcNames.every((n) => allowed.has(n)),
  [...new Set(rpcNames)].join(", "));

// ---------------------------------------------------------------------------
// S5 — manifesto: exatamente 113 codes, sem duplicata
// ---------------------------------------------------------------------------
const mBlock = CODE.match(/TARGET_SET_CODES\s*=\s*Object\.freeze\(\[([\s\S]*?)\]\)/);
const codes = mBlock ? [...mBlock[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]) : [];
check("S5a", "manifesto tem exatamente 113 codes", codes.length === 113, `${codes.length}`);
check("S5b", "manifesto sem duplicatas", new Set(codes).size === codes.length);

// ---------------------------------------------------------------------------
// S6 — SM12 fora do manifesto e declarado como DEFERRED STAGED
// ---------------------------------------------------------------------------
check("S6a", "SM12 NÃO pertence ao manifesto", !codes.includes("SM12"));
check("S6b", "SM12 está declarado em DEFERRED_STAGED_OUT_OF_SCOPE",
  /DEFERRED_STAGED_OUT_OF_SCOPE\s*=\s*Object\.freeze\(\[\s*"SM12"\s*\]\)/.test(CODE));
check("S6c", "há asserção que impede DEFERRED no manifesto",
  /MANIFEST_DEFERRED_LEAK/.test(CODE));

// ---------------------------------------------------------------------------
// S7 — CANARY: exatamente os 4 Sets aprovados, todos no manifesto
// ---------------------------------------------------------------------------
const cBlock = CODE.match(/CANARY_SET_CODES\s*=\s*Object\.freeze\(\[([\s\S]*?)\]\)/);
const canary = cBlock ? [...cBlock[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]) : [];
const canaryExpected = ["FUT2020", "NEO3", "NEO1", "BASE2"];
check("S7a", "CANARY tem exatamente 4 Sets", canary.length === 4, canary.join(","));
check("S7b", "CANARY é exatamente o conjunto aprovado",
  canaryExpected.every((c) => canary.includes(c)) && canary.every((c) => canaryExpected.includes(c)),
  canary.join(","));
check("S7c", "todos os Sets do CANARY estão no manifesto", canary.every((c) => codes.includes(c)));

// ---------------------------------------------------------------------------
// S8 — C fechado: INVALID + SKIPPED + PENDING + SIZE_OUT_OF_SCOPE
// ---------------------------------------------------------------------------
check("S8a", "C exige validation INVALID",
  /v\s*===\s*"INVALID"\s*&&\s*reason\s*===\s*"SIZE_OUT_OF_SCOPE"/.test(CODE));
check("S8b", "C só é considerado sob decision SKIPPED + persistence PENDING",
  /d\s*===\s*"SKIPPED"\s*&&\s*p\s*===\s*"PENDING"/.test(CODE));
check("S8c", "SKIPPED fora do predicado vira strayC e dispara STOP",
  /strayC\.push/.test(CODE) && /UNEXPECTED_SKIPPED_KIND/.test(CODE));

// ---------------------------------------------------------------------------
// S9 — RUN_MODE default é DRY_RUN
// ---------------------------------------------------------------------------
check("S9a", 'RUN_MODE default é "DRY_RUN"', /const\s+RUN_MODE\s*=\s*"DRY_RUN"\s*;/.test(CODE));
{
  // Sem literais de string, a ÚNICA atribuição a RUN_MODE deve ser a declaração const.
  const assigns = [...CODE_NOSTR.matchAll(/\bRUN_MODE\s*=(?!=)/g)];
  const decl = [...CODE_NOSTR.matchAll(/\bconst\s+RUN_MODE\s*=(?!=)/g)];
  check("S9b", "RUN_MODE só é atribuído na declaração const (fora de strings)",
    decl.length === 1 && assigns.length === 1, `atribuições=${assigns.length} declarações=${decl.length}`);
}

// ---------------------------------------------------------------------------
// S10 — zero auto-FULL e zero interação
// ---------------------------------------------------------------------------
check("S10a", "nenhuma atribuição de RUN_MODE para CANARY/FULL em runtime",
  !/RUN_MODE\s*=\s*"(CANARY|FULL)"/.test(CODE));
check("S10b", "nenhum prompt/confirm/alert interativo",
  !/\b(window\.)?(prompt|confirm|alert)\s*\(/.test(CODE));
check("S10c", "DRY_RUN retorna antes de qualquer escrita",
  /RUN_MODE\s*===\s*"DRY_RUN"[\s\S]{0,400}?return;/.test(CODE));

// ---------------------------------------------------------------------------
// S11 — DRY_RUN é somente leitura: nenhuma RPC antes do return do DRY_RUN
// ---------------------------------------------------------------------------
const idxDryReturn = CODE.search(/RUN_MODE\s*===\s*"DRY_RUN"/);
const mainStart = CODE.search(/log\("=".repeat\(78\)\)/);
const beforeDry = idxDryReturn > 0 && mainStart > 0 ? CODE.slice(mainStart, idxDryReturn) : "";
check("S11", "nenhuma chamada de RPC no caminho do DRY_RUN",
  beforeDry.length > 0 && !/\brpc\(/.test(beforeDry));

// ---------------------------------------------------------------------------
// S12 — F (FAILED) é estado de primeira classe
// ---------------------------------------------------------------------------
check("S12a", "F é classificado em loadSets", /if\s*\(p\s*===\s*"FAILED"\)/.test(CODE));
check("S12b", "F>0 dispara STOP", /FAILED_ROWS_PRESENT/.test(CODE));
check("S12c", "confirm com FAILED dispara CONFIRM_COMMITTED_WITH_FAILURES",
  /CONFIRM_COMMITTED_WITH_FAILURES/.test(CODE));
{
  // Prova estrutural: todo bloco que detecta FAILED termina em stop() e nunca
  // reemite rpc(). Busca no código SEM strings, para não casar a própria frase
  // que declara a ausência de retry.
  const blocks = [...CODE_NOSTR.matchAll(/persistence_status\s*===\s*``|\.F\.length[\s\S]{0,600}?\}/g)].map((m) => m[0]);
  const failedBlocks = [...CODE_NOSTR.matchAll(/(failed\s*>\s*0|\.F\.length)[\s\S]{0,500}?(stop\(|\n\s*\})/g)].map((m) => m[0]);
  const anyRpcAfterFailed = failedBlocks.some((b) => /\brpc\(/.test(b));
  check("S12d", "nenhum caminho reemite rpc() após detectar FAILED",
    failedBlocks.length > 0 && !anyRpcAfterFailed, `blocos=${failedBlocks.length}`);
  void blocks;
}

// ---------------------------------------------------------------------------
// S13 — decide somente sobre A, com gate rows_affected === |A|
// ---------------------------------------------------------------------------
check("S13a", "decide recebe pre.A", /p_row_ids:\s*pre\.A\b/.test(CODE));
check("S13b", "gate rows_affected === |A|",
  /DECIDE_ROWS_MISMATCH/.test(CODE) && /n\s*!==\s*pre\.A\.length/.test(CODE));
check("S13c", "após decide, relê e prova que A migrou para B",
  /DECIDE_NOT_REFLECTED/.test(CODE) && /DECIDE_LEFTOVER_A/.test(CODE));

// ---------------------------------------------------------------------------
// S14 — RESUME_PARTIAL
// ---------------------------------------------------------------------------
check("S14", "A>0 && B>0 dispara RESUME_PARTIAL",
  /pre\.A\.length\s*>\s*0\s*&&\s*pre\.B\.length\s*>\s*0/.test(CODE) && /RESUME_PARTIAL/.test(CODE));

// ---------------------------------------------------------------------------
// S15 — NO_RESPONSE tem protocolo próprio, sem retry cego
// ---------------------------------------------------------------------------
check("S15a", "existe reconcileConfirmNoResponse", /function\s+reconcileConfirmNoResponse/.test(CODE));
check("S15b", "cobre os 4 ramos A/B/C/D",
  /nenhuma linha saiu de PENDING|stillPending\s*===\s*S\.length/.test(CODE) &&
  /terminal\s*===\s*S\.length/.test(CODE) &&
  /CONFIRM_COMMITTED_WITH_FAILURES/.test(CODE) &&
  /INDETERMINATE_CONFIRM_STATE/.test(CODE));
check("S15c", "NETWORK_ERROR_NO_RESPONSE fora das allowlists de retry",
  !/ERR_TRANSIENT[\s\S]{0,80}NO_RESPONSE|NO_RESPONSE[\s\S]{0,80}ERR_TRANSIENT/.test(CODE));

// ---------------------------------------------------------------------------
// S16 — deltas por snapshot, nunca pelos contadores da RPC
// ---------------------------------------------------------------------------
check("S16a", "não usa inserted_count/unchanged_count da RPC como delta",
  !/inserted_count|unchanged_count|failed_count|pending_count/.test(CODE));
check("S16b", "delta derivado de snapshots PRE/POST",
  /postInserted\s*-\s*preInserted/.test(CODE) && /postUnchanged\s*-\s*preUnchanged/.test(CODE));

// ---------------------------------------------------------------------------
// S17 — baselines mode-aware (FULL não usa 7671)
// ---------------------------------------------------------------------------
const fullBlock = CODE.match(/FULL:\s*\{([\s\S]*?)\}/);
check("S17a", "FULL espera card_variant 8159 (pós-canary), não 7671",
  !!fullBlock && /cardVariant:\s*8159/.test(fullBlock[1]) && !/cardVariant:\s*7671/.test(fullBlock[1]));
check("S17b", "FULL espera 110 TARGET STAGED e 3 COMPLETED",
  !!fullBlock && /targetStaged:\s*110/.test(fullBlock[1]) && /targetCompleted:\s*3/.test(fullBlock[1]));
check("S17c", "FULL espera Classe A 16734 e execDelta 16734",
  !!fullBlock && /classA:\s*16734/.test(fullBlock[1]) && /execDelta:\s*16734/.test(fullBlock[1]));
check("S17d", "DRY_RUN/CANARY esperam o baseline inicial 7671 / 17222",
  /DRY_RUN:\s*\{[\s\S]*?cardVariant:\s*7671[\s\S]*?\}/.test(CODE) &&
  /CANARY:\s*\{[\s\S]*?classA:\s*17222[\s\S]*?\}/.test(CODE));

// ---------------------------------------------------------------------------
// S18 — tetos do contrato
// ---------------------------------------------------------------------------
check("S18", "tetos declarados: decide 10000, confirm 1000",
  /MAX_DECIDE_IDS\s*=\s*10000/.test(CODE) && /MAX_CONFIRM_IDS\s*=\s*1000/.test(CODE));

// ---------------------------------------------------------------------------
// S19 — logs sem segredos
// ---------------------------------------------------------------------------
check("S19a", "nenhuma variável de token/authorization chega a log/console (fora de strings)",
  !/(log|console\.(log|error|warn|info))\s*\([^;]{0,200}\b(token|accessToken|readAccessToken|authHeaders)\b/i.test(CODE_NOSTR));
check("S19b", "nenhuma persistência de sessão",
  !/localStorage|sessionStorage|document\.cookie\s*=/.test(CODE));
check("S19c", "Authorization nunca é logado",
  !/log\([^)]*Authorization/i.test(CODE));

// ---------------------------------------------------------------------------
// S20 — CAMPAIGN FREEZE registrado no próprio arquivo
// ---------------------------------------------------------------------------
check("S20", "CAMPAIGN FREEZE documentado no header do runner",
  /CAMPAIGN FREEZE/.test(SRC) && /não é precedente|NÃO é precedente/.test(SRC));

console.log("");
console.log("=".repeat(78));
console.log(`RESULTADO: ${pass} PASS · ${fails.length} FALHA`);
if (fails.length) {
  for (const f of fails) console.log(`  ✗ ${f}`);
  console.log("=".repeat(78));
  process.exit(1);
}
console.log("=".repeat(78));
