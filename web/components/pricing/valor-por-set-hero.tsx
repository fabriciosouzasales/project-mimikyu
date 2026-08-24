"use client";

import { CheckCircle2, Package } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Card, CardContent } from "@/components/ui/card";
import { Select } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import type { CardCondition, PricingReportSet } from "@/lib/pricing/queries";

function formatMoney(value: number, currencyCode: string): string {
  try {
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency: currencyCode }).format(value);
  } catch {
    return `${currencyCode} ${value.toFixed(2)}`;
  }
}

function formatPercent(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 1 }).format(value) + "%";
}

/**
 * Hero patrimonial de "Valor por Set" (refinamento visual, 2026-08-23,
 * pedido de Fabrício) — substitui os 3 blocos soltos que existiam antes
 * (identificação do Set em `Card` própria, linha de Condição/Moeda em
 * `ValorPorSetFiltros`, 3 `StatCard`s independentes em `StatsRow`) por um
 * único bloco: identidade do Set → valor estimado coberto (maior elemento
 * numérico da tela, único uso de `text-primary-ink` como acento dourado) →
 * indicadores secundários (cobertura, sem cotação) → Condição/Moeda como
 * controles discretos da própria análise, não uma segunda faixa de
 * formulário desconectada. O antigo `valor-por-set-filtros.tsx` (Select de
 * Condição/Moeda isolado) foi removido do repositório — sua lógica de
 * `pushParam` foi trazida para cá, e nada mais o importava.
 *
 * Cobertura parcial: o `Alert` de "valor parcial" (mesmo texto/regra de
 * antes) fica FORA deste `Card`, como um bloco irmão abaixo — evita
 * "card dentro de card" (o próprio `Alert` já tem borda/fundo próprios).
 *
 * Logo: recebe `cardSet.logoUrl` já resolvido pelo caller (`page.tsx`, via
 * `getCardSetLogoUrlById` — leitura pontual por PK, mesmo padrão já usado em
 * "Preço por Carta"). Nenhum fetch novo acontece aqui.
 */
export function ValorPorSetHero({
  cardSet,
  report,
  conditions,
}: {
  cardSet: {
    name: string;
    code: string;
    expansionName: string | null;
    logoUrl: string | null;
    baseSetSize: number;
  };
  report: PricingReportSet;
  conditions: CardCondition[];
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  function pushParam(key: string, value: string) {
    const params = new URLSearchParams(searchParams.toString());
    params.set(key, value);
    router.push(`${pathname}?${params.toString()}`);
  }

  const coverageCaption = `${report.pricedConvertibleCount}/${report.totalActiveCards} ativas`;
  const hasNoPrice = report.noPriceCount > 0;

  // Composição "set base + secretas" (pedido de Fabrício, 2026-08-23) — usa
  // `report.totalActiveCards` (contagem real de ativas) como fonte de
  // verdade, não `card_set.total_set_size` (definição estática do catálogo,
  // pode divergir se houver carta inativa). `baseSetSize` vem do catálogo
  // (`card_set.base_set_size`); secretas = o excedente além da base, nunca
  // negativo. Garante que set base + secretas sempre soma exatamente o total
  // ativo exibido ao lado, sem criar uma segunda fonte de verdade divergente.
  const setBaseCount = Math.min(report.totalActiveCards, cardSet.baseSetSize);
  const secretCount = Math.max(0, report.totalActiveCards - cardSet.baseSetSize);

  return (
    <Card density="compact">
      <CardContent
        density="compact"
        className="flex flex-col gap-4 pt-4 lg:flex-row lg:items-center lg:gap-5 xl:gap-6"
      >
        {/* Identidade do Set — logo sem caixa de fundo (pedido de Fabrício,
            2026-08-23: "a logo deve ganhar destaque", não ficar contida numa
            estrutura cinza), só altura limitada a 80px (`h-20`); a largura
            acompanha a proporção real da imagem (`w-auto` + `object-contain`,
            com um teto de segurança para não estourar o layout em logos
            muito largas). Sem logo, mantém um placeholder discreto (ícone em
            caixa neutra) para não deixar o espaço vazio sem contexto. */}
        <div className="flex min-w-0 items-center gap-3 lg:shrink-0">
          {cardSet.logoUrl ? (
            // Signed URL expira e é gerada por requisição — mesma decisão de
            // `expansao-gallery-card.tsx`/`card-set-gallery-card.tsx`: <img>
            // simples em vez de next/image.
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={cardSet.logoUrl}
              alt=""
              className="h-20 max-w-[220px] shrink-0 object-contain object-left"
            />
          ) : (
            <div className="flex h-20 w-20 shrink-0 items-center justify-center rounded bg-surface-muted">
              <Package className="h-6 w-6 text-muted-foreground/40" aria-hidden="true" />
            </div>
          )}
          <div className="min-w-0">
            <p className="truncate text-base font-semibold text-foreground">{cardSet.name}</p>
            <p className="truncate text-xs text-muted-foreground">
              {cardSet.code}
              {cardSet.expansionName ? ` - ${cardSet.expansionName}` : ""}
            </p>
            <p className="truncate text-xs text-muted-foreground">
              {report.totalActiveCards} cartas ativas ({setBaseCount} set base + {secretCount} secretas)
            </p>
          </div>
        </div>

        <div className="hidden h-10 w-px shrink-0 bg-border lg:block" aria-hidden="true" />

        {/* Valor principal — maior elemento numérico da tela (protagonismo real do valuation) */}
        <div className="lg:shrink-0">
          <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Valor estimado coberto</p>
          <p className="text-2xl font-bold tabular-nums text-primary-ink sm:text-3xl">
            {formatMoney(report.estimatedValueCovered, report.currency)}
          </p>
          <p className="text-xs text-muted-foreground">Condição {report.condition.name}</p>
        </div>

        <div className="hidden h-10 w-px shrink-0 bg-border lg:block" aria-hidden="true" />

        {/* Indicadores secundários + controles de Condição/Moeda — nunca com o
            mesmo peso visual do valor acima (sem StatCard/selo circular, só
            texto pequeno com ícone de apoio). */}
        <div className="flex flex-1 flex-wrap items-center gap-x-5 gap-y-3 lg:justify-end">
          <div className="flex items-center gap-1.5">
            <CheckCircle2 className="h-4 w-4 text-muted-foreground" aria-hidden="true" />
            <div className="leading-tight">
              <p className="text-sm font-medium tabular-nums text-foreground">{formatPercent(report.coveragePct)}</p>
              <p className="text-[10px] text-muted-foreground">{coverageCaption}</p>
            </div>
          </div>

          <div className="flex items-center gap-1.5">
            <Package
              className={cn(
                "h-4 w-4",
                hasNoPrice ? "text-destructive dark:text-destructive-foreground" : "text-muted-foreground",
              )}
              aria-hidden="true"
            />
            <div className="leading-tight">
              <p
                className={cn(
                  "text-sm font-medium tabular-nums",
                  hasNoPrice ? "text-destructive dark:text-destructive-foreground" : "text-foreground",
                )}
              >
                {report.noPriceCount}
              </p>
              <p className="text-[10px] text-muted-foreground">sem cotação</p>
            </div>
          </div>

          <div className="flex items-center gap-3 border-l border-border pl-4">
            <div className="flex items-center gap-1.5">
              <label className="text-[10px] text-muted-foreground" htmlFor="valor-set-condicao">
                Condição
              </label>
              <Select
                id="valor-set-condicao"
                value={report.condition.id}
                onChange={(event) => pushParam("condition", event.target.value)}
                className="h-8 w-32 text-xs"
              >
                {conditions.map((condition) => (
                  <option key={condition.id} value={condition.id}>
                    {condition.name}
                  </option>
                ))}
              </Select>
            </div>

            <div className="flex items-center gap-1.5">
              <label className="text-[10px] text-muted-foreground" htmlFor="valor-set-moeda">
                Moeda
              </label>
              <Select
                id="valor-set-moeda"
                value={report.currency}
                onChange={(event) => pushParam("currency", event.target.value)}
                className="h-8 w-24 text-xs"
              >
                <option value="BRL">BRL</option>
                <option value="USD">USD</option>
              </Select>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
