/*
===============================================================================
HARNESS OFFLINE — run-bootstrap-cards.mjs
Arquivo......: web/scripts/bootstrap-cards/provas-cards-bootstrap.mjs
Alvo.........: ./run-bootstrap-cards.mjs (mesmo diretorio)
Rodada.......: CATALOG-HISTORICAL-BOOTSTRAP-03 — SM PT-PARTIAL RECOVERY-01

Cobre:
  - alvoDeCobertura (novo) e fontePtParcial;
  - CORRECTION-01: o alvo segue o IDIOMA EFETIVO, nao so a forma da fonte
    (Bloco 6 — importacao en com pt menor e nao vazia mantem alvo en);
  - decidirEstadoDeCobertura: gates A/B/C/D/E, incluindo regressao completa
    dos casos que NAO podem mudar (TK-SM-L, NO_CARDS_AT_SOURCE, banco acima
    da fonte, parcial, completo);
  - decidirPontoDeEntrada: escrever=false sempre vira SKIP;
  - avaliarPoliticaAutoaprovacao: regressao dos estados seguros;
  - idempotencia e convergencia dos 3 Sets pt-parciais.

GARANTIAS DE ISOLAMENTO
  Rede: zero. Banco: zero. Escrita: zero. Credenciais: zero.
  Todas as funcoes exercitadas sao PURAS.

EXECUCAO (a partir da raiz do repositorio):
  node web/scripts/bootstrap-cards/provas-cards-bootstrap.mjs

Criterio de PASS: "RESULTADO: 61/61 OK" e exit code 0.
  (C00 import-safety + C01..C60)
===============================================================================
*/

import { execFileSync } from "node:child_process";

const URL_MODULO = new URL("./run-bootstrap-cards.mjs", import.meta.url).href;

const mod = await import(URL_MODULO);
const {
  alvoDeCobertura,
  fontePtParcial,
  decidirEstadoDeCobertura,
  decidirPontoDeEntrada,
  avaliarPoliticaAutoaprovacao,
  STATUS,
  main,
} = mod;

let total = 0;
const falhas = [];
function ok(nome, cond, detalhe = "") {
  total += 1;
  if (!cond) falhas.push(`${nome}${detalhe ? ` — ${detalhe}` : ""}`);
}

// Perfis reais, medidos na DISCOVERY de 2026-09-10 e confirmados carta a carta
// na rodada PROOF-01 (18/18 HTTP 404 em /pt/cards/{id}).
const SM1 = { idioma_previsto: "pt", source_card_count: 172, source_pt_card_count: 163, declared_total_set_size: 172 };
const SM4 = { idioma_previsto: "pt", source_card_count: 125, source_pt_card_count: 124, declared_total_set_size: 125 };
const SMP = { idioma_previsto: "pt", source_card_count: 248, source_pt_card_count: 240, declared_total_set_size: 248 };
// Regressao: classe B, fonte en menor que o declarado, sem dimensao pt.
const TKSML = { idioma_previsto: "en", source_card_count: 18, source_pt_card_count: null, declared_total_set_size: 30 };
// Regressao: classe C, fonte sem cartas.
const RC = { idioma_previsto: "en", source_card_count: 0, source_pt_card_count: null, declared_total_set_size: 25 };
// Regressao: Set pt normal (pt == en).
const SM2 = { idioma_previsto: "pt", source_card_count: 169, source_pt_card_count: 169, declared_total_set_size: 169 };
// Regressao: Set en puro (pt medido como 0 — /pt veio vazio, fallback en).
const SMA = { idioma_previsto: "en", source_card_count: 94, source_pt_card_count: 0, declared_total_set_size: 94 };

// CORRECTION-01 — caso central: importacao EN com listagem pt NAO vazia e
// MENOR. `fontePtParcial` e verdadeiro, mas o Set sera importado em en, entao
// o alvo TEM que continuar 100. Reduzir para 90 criaria um falso "completo".
const EN100_PT90 = { idioma_previsto: "en", source_card_count: 100, source_pt_card_count: 90, declared_total_set_size: 100 };
// Mesmo perfil de fonte, mudando SO o idioma — prova que o idioma e o que decide.
const PT100_PT90 = { idioma_previsto: "pt", source_card_count: 100, source_pt_card_count: 90, declared_total_set_size: 100 };
// Idioma ausente/desconhecido -> fail-safe para en (alvo maior).
const SEM_IDIOMA = { source_card_count: 100, source_pt_card_count: 90, declared_total_set_size: 100 };

const cob = (perfil, currentCardCount) =>
  decidirEstadoDeCobertura({ currentCardCount, ...perfil });

// ---------------------------------------------------------------------------
// Bloco 0 — import-safety
// ---------------------------------------------------------------------------
total += 1;
try {
  const saida = execFileSync(
    process.execPath,
    ["--input-type=module", "-e", `await import(${JSON.stringify(URL_MODULO)}); console.log("IMPORT_OK");`],
    {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      env: { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot },
      timeout: 30_000,
    },
  );
  if (!saida.includes("IMPORT_OK")) falhas.push(`C00 import-safety — stdout inesperado: ${saida.trim()}`);
  if (saida.includes("ABORTADO")) falhas.push("C00 import-safety — main() executou no import");
} catch (e) {
  falhas.push(`C00 import-safety — processo falhou: ${e.stderr ?? e.message}`);
}
ok("C01 main exportado mas nao invocado", typeof main === "function");

// ---------------------------------------------------------------------------
// Bloco 1 — fontePtParcial (predicado inalterado)
// ---------------------------------------------------------------------------
ok("C02 SM1 e pt parcial", fontePtParcial(SM1) === true);
ok("C03 SM4 e pt parcial", fontePtParcial(SM4) === true);
ok("C04 SMP e pt parcial", fontePtParcial(SMP) === true);
ok("C05 pt null nao e parcial", fontePtParcial(TKSML) === false);
ok("C06 pt zero nao e parcial (vai para fallback en)", fontePtParcial(SMA) === false);
ok("C07 pt igual a en nao e parcial", fontePtParcial(SM2) === false);
ok("C08 pt MAIOR que en nao e parcial",
  fontePtParcial({ source_card_count: 100, source_pt_card_count: 120 }) === false);

// ---------------------------------------------------------------------------
// Bloco 2 — alvoDeCobertura (novo)
// ---------------------------------------------------------------------------
ok("C09 SM1 alvo = 163 (pt)", alvoDeCobertura(SM1) === 163, String(alvoDeCobertura(SM1)));
ok("C10 SM4 alvo = 124 (pt)", alvoDeCobertura(SM4) === 124, String(alvoDeCobertura(SM4)));
ok("C11 SMP alvo = 240 (pt)", alvoDeCobertura(SMP) === 240, String(alvoDeCobertura(SMP)));
ok("C12 SM1 alvo NUNCA e o total en", alvoDeCobertura(SM1) !== SM1.source_card_count);
ok("C13 SM4 alvo NUNCA e o total en", alvoDeCobertura(SM4) !== SM4.source_card_count);
ok("C14 SMP alvo NUNCA e o total en", alvoDeCobertura(SMP) !== SMP.source_card_count);
ok("C15 TK-SM-L alvo = 18 (en, inalterado)", alvoDeCobertura(TKSML) === 18);
ok("C16 RC alvo = 0 (inalterado)", alvoDeCobertura(RC) === 0);
ok("C17 SM2 alvo = 169 (inalterado)", alvoDeCobertura(SM2) === 169);
ok("C18 SMA alvo = 94 (pt vazio -> en, inalterado)", alvoDeCobertura(SMA) === 94);

// ---------------------------------------------------------------------------
// Bloco 3 — pt parcial com banco zerado: ESCREVE, alvo pt (requisito 1 e 2)
// ---------------------------------------------------------------------------
const sm1Zero = cob(SM1, 0);
ok("C19 SM1 0/163 escrever=true", sm1Zero.escrever === true);
ok("C20 SM1 alvo=163", sm1Zero.alvo === 163, String(sm1Zero.alvo));
ok("C21 SM1 estado=PENDING_IMPORT", sm1Zero.estado === STATUS.PENDING_IMPORT, sm1Zero.estado);
ok("C22 SM1 motivo avisa a divergencia pt",
  sm1Zero.motivo.includes("deficit=9") && sm1Zero.motivo.includes("NUNCA en"), sm1Zero.motivo);

const sm4Zero = cob(SM4, 0);
ok("C23 SM4 0/124 escrever=true", sm4Zero.escrever === true);
ok("C24 SM4 alvo=124", sm4Zero.alvo === 124, String(sm4Zero.alvo));
ok("C25 SM4 estado=PENDING_IMPORT", sm4Zero.estado === STATUS.PENDING_IMPORT, sm4Zero.estado);
ok("C26 SM4 motivo avisa deficit=1", sm4Zero.motivo.includes("deficit=1"), sm4Zero.motivo);

const smpZero = cob(SMP, 0);
ok("C27 SMP 0/240 escrever=true", smpZero.escrever === true);
ok("C28 SMP alvo=240", smpZero.alvo === 240, String(smpZero.alvo));
ok("C29 SMP estado=PENDING_IMPORT", smpZero.estado === STATUS.PENDING_IMPORT, smpZero.estado);
ok("C30 SMP motivo avisa deficit=8", smpZero.motivo.includes("deficit=8"), smpZero.motivo);

ok("C31 pt parcial nao produz mais REVIEW_REQUIRED_SOURCE_PARTIAL",
  [SM1, SM4, SMP].every((p) =>
    [0, 1, 50, p.source_pt_card_count - 1, p.source_pt_card_count]
      .every((n) => cob(p, n).estado !== STATUS.REVIEW_REQUIRED_SOURCE_PARTIAL)));

// ---------------------------------------------------------------------------
// Bloco 4 — convergencia: populacao pt atingida => CONCLUSIVO, sem escrita
// (requisito 3 — sem loop, sem reabertura eterna)
// ---------------------------------------------------------------------------
const sm1Cheio = cob(SM1, 163);
ok("C32 SM1 163/163 escrever=false", sm1Cheio.escrever === false);
ok("C33 SM1 163/163 = SOURCE_COMPLETE_WITH_DECLARED_MISMATCH",
  sm1Cheio.estado === STATUS.SOURCE_COMPLETE_WITH_DECLARED_MISMATCH, sm1Cheio.estado);
ok("C34 SM1 completo cita o declarado 172", sm1Cheio.motivo.includes("declarado e 172"), sm1Cheio.motivo);
ok("C35 SM4 124/124 conclusivo sem escrita",
  cob(SM4, 124).escrever === false &&
  cob(SM4, 124).estado === STATUS.SOURCE_COMPLETE_WITH_DECLARED_MISMATCH);
ok("C36 SMP 240/240 conclusivo sem escrita",
  cob(SMP, 240).escrever === false &&
  cob(SMP, 240).estado === STATUS.SOURCE_COMPLETE_WITH_DECLARED_MISMATCH);
ok("C37 convergido nao reabre job (SKIP)",
  decidirPontoDeEntrada({ cobertura: sm1Cheio, jobAtivo: null, jobTerminalComFalha: false }).acao === "SKIP");
ok("C38 idempotencia: reexecutar sobre o convergido da o MESMO resultado",
  JSON.stringify(cob(SM1, 163)) === JSON.stringify(cob(SM1, 163)));
ok("C39 SM1 parcial pos-import (100/163) segue escrevendo",
  cob(SM1, 100).estado === STATUS.PARTIAL_SOURCE_IMPORT && cob(SM1, 100).escrever === true);
ok("C40 SM1 acima do alvo pt vira alarme, nao silencio",
  cob(SM1, 170).estado === STATUS.REVIEW_REQUIRED_COUNT_EXCEEDS_SOURCE);

// ---------------------------------------------------------------------------
// Bloco 5 — REGRESSAO dos gates que NAO podem mudar (requisito 4)
// ---------------------------------------------------------------------------
// TK-SM-L: 18/18 com declarado 30 — comportamento preservado integralmente.
const tk = cob(TKSML, 18);
ok("C41 TK-SM-L 18/18 = SOURCE_COMPLETE_WITH_DECLARED_MISMATCH",
  tk.estado === STATUS.SOURCE_COMPLETE_WITH_DECLARED_MISMATCH, tk.estado);
ok("C42 TK-SM-L escrever=false", tk.escrever === false);
ok("C43 TK-SM-L sem aviso de pt (nao tem dimensao pt)", !tk.motivo.includes("fonte pt parcial"));
ok("C44 TK-SM-L 0/18 continua importavel",
  cob(TKSML, 0).estado === STATUS.PENDING_IMPORT && cob(TKSML, 0).escrever === true);

// NO_CARDS_AT_SOURCE preservado.
ok("C45 RC 0/0 = NO_CARDS_AT_SOURCE",
  cob(RC, 0).estado === STATUS.NO_CARDS_AT_SOURCE && cob(RC, 0).escrever === false);
ok("C46 fonte 0 com banco > 0 e alarme, nao NO_CARDS_AT_SOURCE",
  cob(RC, 3).estado === STATUS.REVIEW_REQUIRED_COUNT_EXCEEDS_SOURCE);

// Sets normais preservados.
ok("C47 SM2 169/169 = ALREADY_SOURCE_COMPLETE",
  cob(SM2, 169).estado === STATUS.ALREADY_SOURCE_COMPLETE && cob(SM2, 169).escrever === false);
ok("C48 SM2 0/169 = PENDING_IMPORT", cob(SM2, 0).estado === STATUS.PENDING_IMPORT);
ok("C49 SMA 94/94 = ALREADY_SOURCE_COMPLETE", cob(SMA, 94).estado === STATUS.ALREADY_SOURCE_COMPLETE);

// escrever=false SEMPRE vira SKIP, qualquer que seja o job.
ok("C50 escrever=false vira SKIP mesmo com job ativo",
  decidirPontoDeEntrada({
    cobertura: cob(RC, 0),
    jobAtivo: { id: "j1", status: "STAGED" },
    jobTerminalComFalha: false,
  }).acao === "SKIP");

// Politica de autoaprovacao inalterada.
ok("C51 VALID/NEW/PENDING e elegivel",
  avaliarPoliticaAutoaprovacao([
    { validation_status: "VALID", match_status: "NEW", decision_status: "PENDING", persistence_status: "PENDING" },
  ]).limpo === true);
ok("C52 CONFLICT contamina o Set inteiro",
  avaliarPoliticaAutoaprovacao([
    { validation_status: "VALID", match_status: "NEW", decision_status: "PENDING", persistence_status: "PENDING" },
    { validation_status: "VALID", match_status: "CONFLICT", decision_status: "PENDING", persistence_status: "PENDING" },
  ]).limpo === false);

// ---------------------------------------------------------------------------
// Bloco 6 — CORRECTION-01: o ALVO segue o IDIOMA, nao so a forma da fonte
// ---------------------------------------------------------------------------
ok("C53 EN-import 100/90: alvo permanece 100",
  alvoDeCobertura(EN100_PT90) === 100, String(alvoDeCobertura(EN100_PT90)));
ok("C54 EN-import: alvo NUNCA cai para 90",
  alvoDeCobertura(EN100_PT90) !== EN100_PT90.source_pt_card_count);
ok("C55 EN-import 90/100 NAO e conclusivo",
  cob(EN100_PT90, 90).estado === STATUS.PARTIAL_SOURCE_IMPORT, cob(EN100_PT90, 90).estado);
ok("C56 EN-import 90/100 continua escrevendo", cob(EN100_PT90, 90).escrever === true);
ok("C57 EN-import 100/100 = ALREADY_SOURCE_COMPLETE",
  cob(EN100_PT90, 100).estado === STATUS.ALREADY_SOURCE_COMPLETE &&
  cob(EN100_PT90, 100).escrever === false);
ok("C58 EN-import nao emite aviso de alvo reduzido",
  !cob(EN100_PT90, 0).motivo.includes("fonte pt parcial"), cob(EN100_PT90, 0).motivo);
ok("C59 idioma ausente e fail-safe para en (alvo 100)",
  alvoDeCobertura(SEM_IDIOMA) === 100 && cob(SEM_IDIOMA, 90).estado === STATUS.PARTIAL_SOURCE_IMPORT);
ok("C60 MESMA fonte com idioma pt: alvo 90 e conclusivo em 90",
  alvoDeCobertura(PT100_PT90) === 90 &&
  cob(PT100_PT90, 90).estado === STATUS.SOURCE_COMPLETE_WITH_DECLARED_MISMATCH,
  `${alvoDeCobertura(PT100_PT90)} / ${cob(PT100_PT90, 90).estado}`);

// ---------------------------------------------------------------------------
console.log(`RESULTADO: ${total - falhas.length}/${total} OK`);
if (falhas.length > 0) {
  console.error(`\nFALHAS (${falhas.length}):`);
  for (const f of falhas) console.error(`  - ${f}`);
  process.exitCode = 1;
}
