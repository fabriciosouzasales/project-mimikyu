const SET_TYPE_LABEL: Record<string, string> = {
  REGULAR: "Regular",
  SPECIAL: "Especial",
  PROMO: "Promo",
  ENERGY: "Energia",
};

/**
 * Um hue discreto por tipo — não mais neutro para os quatro (ajuste pedido
 * por Fabrício, 2026-07-26: "recupere parte da personalidade... categorias
 * devem continuar sendo representadas por badges discretos, cada uma com
 * uma identidade visual sutil e consistente"). `REGULAR` reaproveita
 * `primary` (token global existente); os outros três usam cores puras do
 * Tailwind, só neste componente — nenhum novo token global foi criado.
 * Intensidade propositalmente baixa (`/10` de fundo, `/25` de borda) para
 * não competir com o conteúdo ao redor.
 *
 * 2026-07-26 — mesmo ajuste de altura aplicado ao `StateBadge`: `leading-none`
 * + padding calibrado por medição real do Supabase (badge real: 17.48px de
 * altura, fonte 9px, padding 3px/5.5px). Sem `leading-none`, o texto herdava
 * a `line-height` do corpo e inflava a caixa do badge.
 *
 * `uppercase` — regra confirmada por Fabrício para todo o sistema (mesma
 * convenção já usada no `Badge` global, `ui/badge.tsx`).
 */
const SET_TYPE_CLASSES: Record<string, string> = {
  REGULAR: "border-primary/25 bg-primary/10 text-primary-ink",
  SPECIAL: "border-violet-500/25 bg-violet-500/10 text-violet-700 dark:text-violet-400",
  PROMO: "border-sky-500/25 bg-sky-500/10 text-sky-700 dark:text-sky-400",
  ENERGY: "border-orange-500/25 bg-orange-500/10 text-orange-700 dark:text-orange-400",
};

export function SetTypeTag({ setType }: { setType: string }) {
  const classes = SET_TYPE_CLASSES[setType] ?? "border-border bg-transparent text-muted-foreground";

  return (
    <span
      className={`inline-flex items-center rounded-full border px-[7px] py-[3px] text-[9px] font-medium uppercase leading-none ${classes}`}
    >
      {SET_TYPE_LABEL[setType] ?? setType}
    </span>
  );
}
