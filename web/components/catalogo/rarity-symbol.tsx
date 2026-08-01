import { Circle, Diamond, Star, Zap, type LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Símbolo visual de raridade — novo em 2026-07-31 (subciclo Card, pedido de
 * Fabrício: "abaixo de cada carta deve aparecer... o símbolo que representa
 * a sua raridade... em fontes pequenas, de forma bem discreta"). `rarity`
 * (Query 130) só guarda `symbol_code` — "a aplicação é responsável por
 * converter symbol_code em um ativo visual" (comentário da própria tabela);
 * esta é essa conversão.
 *
 * Ampliado no mesmo dia (pedido de Fabrício, com print de uma carta real:
 * "os símbolos não estão exatamente como convencionado em nossa base") —
 * a v1.0 só cobria os 5 `symbol_code` citados como "Exemplos" no comentário
 * da Query 130 (`BLACK_CIRCLE`/`BLACK_DIAMOND`/`BLACK_STAR`/
 * `BLACK_DOUBLE_STAR`/`GOLD_DOUBLE_STAR`) e era inteiramente monocromática;
 * o seed real (`database/seeds/830_seed_rarity.sql`, CANÔNICA) usa 9
 * códigos distintos em três famílias de cor (`BLACK_*`/`SILVER_*`/
 * `GOLD_*`), e vários caíam no mesmo fallback genérico — raridades
 * visualmente diferentes na especificação ficavam indistinguíveis na tela.
 * Cores das três famílias reaproveitam tokens já existentes do Design
 * System (`--foreground`/`--muted-foreground`/`--primary` — este último já
 * é o dourado da marca, "dourado #E29C27" nos comentários de `globals.css`,
 * um encaixe natural para `GOLD_*`), não cores novas inventadas.
 *
 * `MEGA_ATTACK` (raridade `MEGA_ATTACK_RARE`, específica da própria
 * Megaevolução) não tem símbolo real documentado em nenhuma fonte —
 * escolha própria (raio, tom dourado) até surgir referência oficial.
 *
 * Divergência sinalizada, não resolvida unilateralmente: o seed 830 lista
 * `ILLUSTRATION_RARE` → `GOLD_STAR`, mas Fabrício descreveu "círculo cinza"
 * para Ilustração Rara no mesmo pedido — meta abaixo, não resolvida aqui.
 */
const SYMBOL_MAP: Record<string, { icon: LucideIcon; count: 1 | 2; tone: string }> = {
  BLACK_CIRCLE: { icon: Circle, count: 1, tone: "text-foreground" },
  BLACK_DIAMOND: { icon: Diamond, count: 1, tone: "text-foreground" },
  BLACK_STAR: { icon: Star, count: 1, tone: "text-foreground" },
  BLACK_DOUBLE_STAR: { icon: Star, count: 2, tone: "text-foreground" },
  SILVER_DOUBLE_STAR: { icon: Star, count: 2, tone: "text-muted-foreground" },
  MEGA_ATTACK: { icon: Zap, count: 1, tone: "text-primary" },
  GOLD_STAR: { icon: Star, count: 1, tone: "text-primary" },
  GOLD_DOUBLE_STAR: { icon: Star, count: 2, tone: "text-primary" },
  GOLD_DIAMOND: { icon: Diamond, count: 1, tone: "text-primary" },
};

export function RaritySymbol({ symbolCode, className }: { symbolCode: string; className?: string }) {
  const entry = SYMBOL_MAP[symbolCode] ?? { icon: Circle, count: 1 as const, tone: "text-muted-foreground" };
  const Icon = entry.icon;

  // `leading-none` — sem isso o `<span>` herda o line-height ambiente de
  // onde é usado (ex.: 20px em `CartaGridCard`), deixando um ícone de 7px
  // boiando dentro de uma caixa de linha bem maior do que ele — o efeito
  // "solto na tela" reportado por Fabrício (2026-07-31) não era a margem
  // para o texto acima, e sim esse espaço em branco embutido no próprio
  // símbolo.
  return (
    <span className={cn("inline-flex items-center gap-[1px] leading-none", entry.tone)} aria-hidden="true">
      {Array.from({ length: entry.count }).map((_, index) => (
        <Icon key={index} className={cn("h-[7px] w-[7px] fill-current stroke-[1.5]", className)} />
      ))}
    </span>
  );
}
