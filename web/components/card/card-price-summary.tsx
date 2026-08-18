"use client";

import { CircleDollarSign } from "lucide-react";
import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { Badge } from "@/components/ui/badge";
import { useAnchoredPopover } from "@/hooks/use-anchored-popover";
import {
  fetchLiveDetail,
  getCachedLiveDetail,
  type PricingCacheEntry,
  type PricingSnapshotRow,
} from "@/lib/pricing/pricing-batch-client";
import { cn } from "@/lib/utils";

// USD sempre no padrão PT-BR ("US$ 0,22", vírgula decimal, prefixo "US$")
// — nunca o padrão nativo `en-US` ("$0.22"). Bug identificado em QA visual
// (2026-08-18): `Intl.NumberFormat("en-US", ...)` produzia o formato errado
// mesmo com o restante da UI em PT-BR.
const usdFormatter = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "USD" });
const brlFormatter = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
const rateFormatter = new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 4, maximumFractionDigits: 4 });
const dateRefFormatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });

// Rótulos em PT-BR, sem os códigos técnicos que o banco guarda em inglês
// (`card_condition.name` = "Near Mint", `pricing_product.source_printing_label`
// = "Normal"/"Holofoil"/"Reverse Holofoil") — pedido explícito de Fabrício
// (2026-08-18, ajuste visual final do P12): "Remova da interface códigos
// técnicos como JUSTTCG_AGGREGATE, CONVERTED, NEAR MINT, NORMAL e REVERSE
// HOLOFOIL". Nunca lidos de `row.conditionName`/`row.printingLabel`
// diretamente — sempre traduzidos por este mapa fixo.
const PRINTING_LABEL_PT: Record<string, string> = {
  Normal: "Normal",
  Holofoil: "Holográfica",
  "Reverse Holofoil": "Holográfica reversa",
};

// Hierarquia já aprovada, reconfirmada em QA visual (2026-08-18): NM+Normal
// -> NM+Holográfica -> NM+Holográfica reversa. Só decide a ORDEM de exibição
// no popover (qual linha aparece primeiro/destacada) — nunca decide qual
// preço aciona o pill do grid, que continua sendo estritamente
// NM+Normal+MARKET (modo live via `get_cards_pricing_summary`, modo prévia
// via `selectDisplayRows` abaixo aplicando a mesma regra estrita antes de
// considerar a hierarquia). NM é a condição padrão de comparação/exibição
// em todo o produto por representar mais de 95% das negociações
// consideradas (ver `docs/05f-pricing.md`) — por isso nunca aparecem linhas
// de Lightly Played, Moderately Played, Heavily Played ou Damaged aqui.
const PRINTING_ORDER = ["Normal", "Holofoil", "Reverse Holofoil"];

/**
 * Filtra e ordena as linhas de detalhe (sempre em condição NM, sempre
 * `price_type` MARKET, sempre convertidas em BRL) na ordem da hierarquia
 * aprovada, uma linha por variante (printing). Reaproveitado tanto pelo modo
 * `preview` (linhas já vêm completas no lote) quanto pelo modo `live`
 * (`fetchLiveDetail`, sob demanda) — o filtro é o mesmo dos dois lados,
 * porque as duas fontes trazem o detalhe completo (todas as condições/
 * variantes/tipos de preço), nunca só o resumo.
 */
function selectDisplayRows(rows: PricingSnapshotRow[]): PricingSnapshotRow[] {
  const eligible = rows.filter(
    (row) =>
      row.conditionCode === "NM" &&
      row.priceType === "MARKET" &&
      row.fxStatus === "CONVERTED" &&
      row.equivalentBrlAmount !== null &&
      row.fxRate !== null,
  );
  const byPrinting = new Map<string, PricingSnapshotRow>();
  for (const row of eligible) {
    if (!byPrinting.has(row.printingLabel)) byPrinting.set(row.printingLabel, row);
  }
  return PRINTING_ORDER.filter((printing) => byPrinting.has(printing)).map((printing) => byPrinting.get(printing)!);
}

/**
 * Pill de preço inline — mesmo padrão visual do indicador de quantidade de
 * variantes (`Layers` + contagem, `cartas-gallery.tsx`): altura, borda,
 * fundo, raio e espaçamento idênticos (pedido de Fabrício, 2026-08-18). O
 * pill mostra só `R$ 1,14` (ícone + valor formatado), nunca a
 * variante/condição no próprio grid; esse detalhe existe só no popover (ver
 * `CardPriceDetails`, abaixo).
 *
 * Ajustes de QA visual (2026-08-18): ícone trocado de `Coins` (lido como um
 * elo/corrente) para `CircleDollarSign`; texto em `text-foreground` (não
 * `text-muted-foreground`) e `font-semibold` em vez de `font-medium` — o
 * cinza fraco sobre `bg-surface-muted` não garantia contraste AA para texto
 * de 9-10px; um `text-[10px]` discreto (1px acima do anterior) mantém a
 * altura do pill praticamente idêntica ao contador de variantes (mesmo
 * `py-0.5`/`leading-none`) e melhora a legibilidade sem virar destaque.
 *
 * Renderização condicionada só à presença de um preço já resolvido pelo
 * `usePricingBatch` do grid pai — nunca a hover/foco/toque. O pill inteiro é
 * o próprio elemento clicável/focável (`aria-haspopup="dialog"`); hover,
 * foco ou toque nele abrem o popover de detalhe.
 */
export function CardPriceSummary({
  cardId,
  cardName,
  entry,
  className,
}: {
  cardId: string;
  cardName: string;
  entry: PricingCacheEntry | undefined;
  className?: string;
}) {
  const { anchorRef, contentRef, open, position, scheduleOpen, scheduleClose, openNow, closeNow, toggle } =
    useAnchoredPopover<HTMLButtonElement, HTMLDivElement>();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  if (!entry) return null;

  let brlAmount: number | null = null;
  if (entry.mode === "live") {
    if (!entry.summary.hasPricing || entry.summary.brlAmount === null) return null;
    brlAmount = entry.summary.brlAmount;
  } else {
    const rows = selectDisplayRows(entry.rows);
    if (rows.length === 0) return null;
    brlAmount = rows[0]!.equivalentBrlAmount;
  }
  if (brlAmount === null) return null;

  const priceText = brlFormatter.format(brlAmount);
  const popoverId = `card-price-summary-${cardId}`;

  return (
    <>
      <button
        ref={anchorRef}
        type="button"
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-controls={open ? popoverId : undefined}
        aria-label={`Ver preços — equivalente em BRL ${priceText}`}
        onMouseEnter={() => scheduleOpen()}
        onMouseLeave={() => scheduleClose()}
        onFocus={() => openNow()}
        onBlur={() => scheduleClose()}
        onClick={(event) => {
          event.stopPropagation();
          toggle();
        }}
        className={cn(
          "inline-flex shrink-0 items-center gap-0.5 whitespace-nowrap rounded-full bg-surface-muted px-1.5 py-0.5 text-[10px] font-semibold leading-none text-foreground hover:bg-surface-muted/70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
          className,
        )}
      >
        <CircleDollarSign className="h-2.5 w-2.5 shrink-0" aria-hidden="true" />
        {priceText}
      </button>

      {mounted && open
        ? createPortal(
            <div
              ref={contentRef}
              id={popoverId}
              role="dialog"
              aria-modal="false"
              aria-label={`Preço de mercado de ${cardName}`}
              onMouseEnter={openNow}
              onMouseLeave={() => scheduleClose()}
              style={{
                position: "fixed",
                top: position?.top ?? -9999,
                left: position?.left ?? -9999,
                visibility: position ? "visible" : "hidden",
              }}
              className="z-50 w-[280px] max-w-[calc(100vw-16px)] rounded-lg border border-border bg-surface p-3.5 shadow-panel"
            >
              <CardPriceDetails cardId={cardId} entry={entry} />
            </div>,
            document.body,
          )
        : null}
    </>
  );
}

function CardPriceDetails({ cardId, entry }: { cardId: string; entry: PricingCacheEntry }) {
  // Modo prévia: `entry.rows` já veio completo no lote (P11/P12) — nada para
  // buscar. Modo live: o resumo em lote só tem NM+Normal; o detalhe completo
  // (necessário para eventuais linhas de Holográfica/Holográfica reversa) é
  // buscado sob demanda aqui, na abertura do popover, reaproveitando o
  // contrato por-carta inalterado (`GET /api/cards/[cardId]/pricing`).
  const [liveRows, setLiveRows] = useState<PricingSnapshotRow[] | undefined>(
    entry.mode === "live" ? getCachedLiveDetail(cardId) : undefined,
  );
  const [liveStatus, setLiveStatus] = useState<"idle" | "loading" | "loaded" | "error">(
    entry.mode === "live" && getCachedLiveDetail(cardId) ? "loaded" : "idle",
  );

  useEffect(() => {
    if (entry.mode !== "live") return;
    if (liveStatus !== "idle") return;

    let cancelled = false;
    setLiveStatus("loading");
    fetchLiveDetail(cardId).then((rows) => {
      if (cancelled) return;
      setLiveRows(rows);
      setLiveStatus(rows.length > 0 ? "loaded" : "error");
    });
    return () => {
      cancelled = true;
    };
  }, [entry.mode, cardId, liveStatus]);

  if (entry.mode === "live" && liveStatus === "loading") {
    return <p className="text-[11px] text-muted-foreground">Carregando detalhes…</p>;
  }

  const rawRows = entry.mode === "preview" ? entry.rows : (liveRows ?? []);
  const rows = selectDisplayRows(rawRows);

  if (rows.length === 0) {
    return <p className="text-[11px] text-muted-foreground">Sem detalhes disponíveis.</p>;
  }

  const primary = rows[0]!;
  const others = rows.slice(1);

  // Pares rótulo/valor do cabeçalho — layout em linha (rótulo à esquerda,
  // fraco; valor à direita, forte) em vez do parágrafo corrido anterior
  // ("Rótulo: valor" como texto contínuo). Pedido explícito de QA visual
  // (2026-08-18): "reduzir sensação de bloco administrativo usando
  // hierarquia visual e pares rótulo/valor". Ordem e conteúdo seguem o
  // cabeçalho aprovado à risca — sem "Condição:"/"Variante:" como linhas
  // próprias (isso agora é só o "NM · Normal" logo abaixo do preço) e sem o
  // sufixo "por US$ 1" na taxa de câmbio.
  const fields: Array<{ label: string; value: string }> = [
    { label: "Preço original", value: usdFormatter.format(primary.originalAmount) },
    { label: "Fonte do preço", value: "JustTCG" },
    { label: "Data de referência", value: dateRefFormatter.format(new Date(primary.observedAt)) },
    { label: "Taxa de conversão", value: `R$ ${rateFormatter.format(primary.fxRate!)}` },
    { label: "Fonte cambial", value: "Banco Central do Brasil" },
  ];

  return (
    <div className="space-y-3">
      {entry.mode === "preview" && (
        <Badge variant="warning" className="w-fit">
          Prévia técnica — fonte inativa
        </Badge>
      )}

      {/* Preço destacado — sempre a primeira linha da hierarquia disponível
          (NM+Normal quando existe; NM+Holográfica/Holográfica reversa só se
          Normal não tiver preço, embora isso hoje nunca aconteça no pill do
          grid, que exige Normal — ver comentário de `PRINTING_ORDER` acima).
          "NM · Normal" logo abaixo substitui as antigas linhas separadas de
          Condição/Variante — mais compacto, mesma informação. */}
      <div>
        <p className="text-xl font-bold leading-none text-foreground">
          {brlFormatter.format(primary.equivalentBrlAmount!)}
        </p>
        <p className="mt-1 text-[11px] font-medium leading-none text-muted-foreground">
          NM · {PRINTING_LABEL_PT[primary.printingLabel] ?? primary.printingLabel}
        </p>
      </div>

      <dl className="space-y-1.5 text-[11px] leading-none">
        {fields.map((field) => (
          <div key={field.label} className="flex items-center justify-between gap-3">
            <dt className="text-muted-foreground">{field.label}</dt>
            <dd className="text-right font-medium text-foreground">{field.value}</dd>
          </div>
        ))}
      </dl>

      {/* Outras variantes em NM (quando a carta tem mais de um printing com
          preço real) — nunca Lightly Played/Moderately Played/Heavily
          Played/Damaged: `selectDisplayRows` já restringe a NM antes de
          chegar aqui. Alinhamento em duas colunas (pedido de Fabrício,
          2026-08-18, correção de QA): nome da variante à esquerda, valores
          BRL · USD à direita — não mais texto de linha única com travessão. */}
      {others.length > 0 && (
        <div className="space-y-1 border-t border-border pt-2.5">
          <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
            Outras variantes em NM
          </p>
          {others.map((row) => (
            <div key={row.printingLabel} className="flex items-baseline justify-between gap-2 text-[11px]">
              <span className="text-muted-foreground">{PRINTING_LABEL_PT[row.printingLabel] ?? row.printingLabel}</span>
              <span className="text-right font-medium text-foreground">
                {brlFormatter.format(row.equivalentBrlAmount!)}
                <span className="font-normal text-muted-foreground"> · {usdFormatter.format(row.originalAmount)}</span>
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
