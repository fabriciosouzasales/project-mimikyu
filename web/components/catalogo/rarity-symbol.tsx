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
 *
 * Três símbolos novos (2026-08-02, `database/seeds/830_seed_rarity.sql`
 * v1.4, ACE_SPEC_RARE/SHINY_RARE/SHINY_ULTRA_RARE) — Fabrício confirmou os
 * símbolos oficiais por referência visual direta: `ACE_SPEC` é uma estrela
 * rosa/magenta (cor nova, fora das três famílias `BLACK_*`/`SILVER_*`/
 * `GOLD_*` já existentes — `text-pink-500`, cor pura do Tailwind, sem token
 * de Design System dedicado ainda).
 *
 * `GOLD_SPARKLE`/`GOLD_DOUBLE_SPARKLE`, ajustado no mesmo dia (rodada
 * seguinte) a partir de feedback direto de Fabrício vendo o resultado já em
 * tela: "Os símbolos da shine e Shine Ultra são estrelas com bordas
 * amarelas e centro cinza. As quantidades de estrelas estão certas, só
 * precisa borda amarela" — corrige a primeira tentativa, que usava o ícone
 * `Sparkle` (4 pontas) inteiramente dourado (borda e centro na mesma cor).
 * Agora usa `Star` (5 pontas, mesmo ícone de `GOLD_STAR`/`BLACK_STAR`) com
 * duas cores independentes: borda em `text-primary` (dourado da marca,
 * "amarelo" no pedido) e centro em `fill-muted-foreground` (cinza, mesmo
 * tom de `SILVER_DOUBLE_STAR`) — daí o novo campo opcional `fillTone` no
 * mapa (quando ausente, ícone continua monocromático via `fill-current`,
 * como todos os outros símbolos: a borda por padrão já é `currentColor`
 * herdado do `tone` do `<span>`, então só o preenchimento precisa de uma
 * cor própria para o efeito de duas cores).
 *
 * Detalhe técnico deliberado: `fillTone` guarda uma classe `fill-*` (cor
 * literal, ex. `fill-muted-foreground`), nunca `text-*` — aplicar `text-*`
 * diretamente no `<Icon>` mudaria o `currentColor` do próprio elemento SVG,
 * o que sobrescreveria TANTO o `stroke` (herdado via `currentColor` do
 * `tone` do `<span>` pai) QUANTO o `fill`, perdendo o efeito de duas cores.
 * `fill-{cor}` define o preenchimento com um valor literal, independente de
 * `currentColor`, sem tocar no `stroke`.
 *
 * `GOLD_TRIPLE_STAR` (2026-08-02, mesmo dia, rodada seguinte, Query 830
 * v1.5) — correção real reportada por Fabrício com referência visual
 * oficial ("★★★ = Rara Hiper"): `HYPER_RARE` aparecia com uma única
 * estrela dourada porque seu `symbol_code` era `GOLD_STAR`, o mesmo símbolo
 * de `ILLUSTRATION_RARE` (colisão existente desde a v1.0/v1.1, nunca
 * sinalizada até agora) — deveria mostrar três. `HYPER_RARE` passou a usar
 * um `symbol_code` dedicado, `GOLD_TRIPLE_STAR` (`count: 3`, mesma família
 * `text-primary`/dourada de `GOLD_STAR`/`GOLD_DOUBLE_STAR`), em vez de
 * ampliar `GOLD_STAR` para 3 pontas — isso preservaria a colisão, só
 * transferindo o problema (`ILLUSTRATION_RARE` passaria a mostrar 3
 * estrelas por engano). `count` ampliado de `1 | 2` para `1 | 2 | 3` para
 * acomodar o novo símbolo — nenhum símbolo existente muda de contagem.
 *
 * `BLACK_WHITE_STAR` (2026-08-06, Query 830 v1.6) — gap real na revisão de
 * importação ("Rara Preto e Branco", cartas Victini 171/86 e Zekrom ex
 * 172/86). Símbolo oficial informado por Fabrício: "★☆" — uma estrela
 * preenchida + uma vazada, o primeiro símbolo do mapa que não é uniforme
 * (todo símbolo anterior repete o mesmo ícone/preenchimento `count` vezes).
 * Novo campo opcional `emptyCount`: quantos ícones adicionais, além de
 * `count`, renderizam sem preenchimento (`fill-none`, só contorno) — mantém
 * todo entry existente compatível (sem `emptyCount`, comportamento idêntico
 * a antes).
 */
const SYMBOL_MAP: Record<
  string,
  { icon: LucideIcon; count: 1 | 2 | 3; tone: string; fillTone?: string; emptyCount?: 1 }
> = {
  BLACK_CIRCLE: { icon: Circle, count: 1, tone: "text-foreground" },
  BLACK_DIAMOND: { icon: Diamond, count: 1, tone: "text-foreground" },
  BLACK_STAR: { icon: Star, count: 1, tone: "text-foreground" },
  BLACK_DOUBLE_STAR: { icon: Star, count: 2, tone: "text-foreground" },
  SILVER_DOUBLE_STAR: { icon: Star, count: 2, tone: "text-muted-foreground" },
  MEGA_ATTACK: { icon: Zap, count: 1, tone: "text-primary" },
  GOLD_STAR: { icon: Star, count: 1, tone: "text-primary" },
  GOLD_DOUBLE_STAR: { icon: Star, count: 2, tone: "text-primary" },
  GOLD_TRIPLE_STAR: { icon: Star, count: 3, tone: "text-primary" },
  GOLD_DIAMOND: { icon: Diamond, count: 1, tone: "text-primary" },
  ACE_SPEC: { icon: Star, count: 1, tone: "text-pink-500" },
  GOLD_SPARKLE: { icon: Star, count: 1, tone: "text-primary", fillTone: "fill-muted-foreground" },
  GOLD_DOUBLE_SPARKLE: { icon: Star, count: 2, tone: "text-primary", fillTone: "fill-muted-foreground" },
  BLACK_WHITE_STAR: { icon: Star, count: 1, tone: "text-foreground", emptyCount: 1 },
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
  const totalCount = entry.count + (entry.emptyCount ?? 0);

  return (
    <span className={cn("inline-flex items-center gap-[1px] leading-none", entry.tone)} aria-hidden="true">
      {Array.from({ length: totalCount }).map((_, index) => (
        <Icon
          key={index}
          className={cn(
            "h-[7px] w-[7px] stroke-[1.5]",
            index < entry.count ? (entry.fillTone ?? "fill-current") : "fill-none",
            className,
          )}
        />
      ))}
    </span>
  );
}
