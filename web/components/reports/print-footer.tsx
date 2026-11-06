"use client";

import { useEffect } from "react";
import { PRINT_FOOTER_CENTER, formatPrintStamp, stampRule, supportsPagedFooter, type BrandVersion } from "@/lib/reports/print-footer";

/**
 * V1-14 — rodapé institucional de impressão dos relatórios contextuais (D7 §2).
 *
 * `PrintFooter` é montado UMA vez em cada casca de relatório contextual (sobreposições do Acervo,
 * de Minhas coleções e da coleção, e a rota direta do Checklist), dentro do elemento marcado com
 * `data-print-footer-scope` — a regra nunca alcança a Central do Catálogo nem o Pricing.
 *
 * Enquanto montado:
 *  - detecta o suporte (`supportsPagedFooter`) e marca `<html data-print-footer="paged">`; sem
 *    suporte a marca não existe e vale o rodapé alternativo abaixo (CSS em `globals.css`);
 *  - mantém uma única `<style id="mmkyu-print-stamp">` com a data/hora da caixa `@bottom-left`;
 *  - escuta `beforeprint` (Ctrl+P e Imprimir) para gravar a hora efetiva; remove o listener, a
 *    regra e a marca ao desmontar (nenhum efeito persiste fora do relatório aberto).
 * `stampPrintFooter()` é idempotente: o botão Imprimir e o `beforeprint` escrevem o mesmo texto.
 */
const STYLE_ID = "mmkyu-print-stamp";

function marginRulesParsed(): boolean {
  try {
    const sheet = new CSSStyleSheet();
    sheet.replaceSync('@page { @bottom-center { content: "x"; } }');
    const rule = sheet.cssRules[0] as (CSSRule & { cssRules?: CSSRuleList }) | undefined;
    return Boolean(rule && rule.cssRules && rule.cssRules.length > 0);
  } catch {
    return false;
  }
}

function brands(): BrandVersion[] | null {
  const data = (navigator as Navigator & { userAgentData?: { brands?: BrandVersion[] } }).userAgentData;
  return Array.isArray(data?.brands) ? data.brands : null;
}

/** Grava a data/hora efetiva da impressão na caixa de margem e no rodapé alternativo. */
export function stampPrintFooter(now: Date = new Date()): void {
  if (typeof document === "undefined") return;
  const stamp = formatPrintStamp(now);
  let style = document.getElementById(STYLE_ID);
  if (!style) {
    style = document.createElement("style");
    style.id = STYLE_ID;
    document.head.appendChild(style);
  }
  const rule = stampRule(stamp);
  if (style.textContent !== rule) style.textContent = rule;
  for (const node of document.querySelectorAll<HTMLElement>("[data-print-footer-stamp]")) {
    if (node.textContent !== stamp) node.textContent = stamp;
  }
}

export function PrintFooter() {
  useEffect(() => {
    const root = document.documentElement;
    if (supportsPagedFooter({ marginRulesParsed: marginRulesParsed(), brands: brands() })) root.dataset.printFooter = "paged";
    stampPrintFooter();
    const onBeforePrint = () => stampPrintFooter();
    window.addEventListener("beforeprint", onBeforePrint);
    return () => {
      window.removeEventListener("beforeprint", onBeforePrint);
      delete root.dataset.printFooter;
      document.getElementById(STYLE_ID)?.remove();
    };
  }, []);

  // Rodapé alternativo (navegador sem caixas de margem): só na impressão, fixo no pé de cada folha.
  return (
    <div data-print-footer-fallback="" aria-hidden="true" className="hidden">
      <span data-print-footer-stamp="" />
      <span>{PRINT_FOOTER_CENTER}</span>
      <span />
    </div>
  );
}
