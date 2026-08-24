import { Alert } from "@/components/ui/alert";
import type { PricingReportSet } from "@/lib/pricing/queries";

/**
 * Alerta de "valor parcial" de "Valor por Set" (Bloco 5, migration 3943).
 *
 * v2 (2026-08-23, Hero Patrimonial) — este componente deixou de renderizar
 * `estimatedValueCovered`/cobertura/sem-cotação como `StatCard`s
 * independentes; esses 3 números agora vivem no hero único
 * (`ValorPorSetHero`, `page.tsx`), com o valor em protagonismo real e os
 * demais como indicadores secundários — não mais 3 cards com o mesmo peso
 * visual. O que resta aqui é só o aviso de cobertura incompleta: quando
 * `isPartial`, deixa explícito que o valor somado é parcial (nunca trata
 * ausência de cotação como zero) — mesmo texto/regra de antes, agora como
 * bloco irmão abaixo do hero (nunca aninhado dentro dele, para não virar
 * "card dentro de card").
 */
export function ValorPorSetReport({ report }: { report: PricingReportSet }) {
  if (!report.isPartial) return null;

  return (
    <Alert variant="warning">
      <p className="font-medium">Valor parcial — cobertura incompleta</p>
      <p className="mt-1 text-xs">
        {report.noPriceCount} carta(s) ativa(s) deste Set não têm cotação confirmada nesta condição/moeda — o valor
        acima soma só as cartas com preço, nunca trata a ausência de cotação como zero.
      </p>
    </Alert>
  );
}
