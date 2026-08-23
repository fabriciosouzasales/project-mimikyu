/**
 * Gráfico de linha (série temporal de preço) — SVG desenhado à mão, sem
 * dependência externa. Nenhuma biblioteca de gráfico está instalada no
 * projeto (`recharts`/`chart.js`/`d3` — nenhuma consta em `package.json`) e o
 * sandbox de execução deste agente não tem acesso ao registro npm para
 * instalar uma nova (mesma limitação já documentada para
 * lint/build — ver `docs/development/HANDOFF-2026-08-21.md`); pedir a
 * Fabrício para instalar localmente ficaria fora do "não criar otimização
 * nova nesta rodada" combinado para o Bloco 5. Decorativo/complementar — os
 * valores exatos já aparecem em tabela ao lado, então o gráfico não precisa
 * de tooltip interativo para cumprir "usar gráficos onde agregarem valor".
 *
 * Uma linha por combinação fonte+variante (`series`), sempre a partir de
 * zero no eixo Y (nunca corta a base — evita exagerar visualmente uma
 * variação pequena).
 */
export type PriceHistorySeries = {
  label: string;
  points: Array<{ observedAt: string; price: number }>;
};

const SERIES_COLORS = ["#2563eb", "#16a34a", "#d97706", "#dc2626", "#7c3aed", "#0891b2", "#db2777"];

const dateAxisFormatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit" });

export function PriceHistoryChart({ series }: { series: PriceHistorySeries[] }) {
  const nonEmpty = series.filter((s) => s.points.length > 0);
  if (nonEmpty.length === 0) return null;

  const width = 640;
  const height = 220;
  const padding = { top: 12, right: 12, bottom: 24, left: 44 };
  const plotWidth = width - padding.left - padding.right;
  const plotHeight = height - padding.top - padding.bottom;

  const allPoints = nonEmpty.flatMap((s) => s.points);
  const times = allPoints.map((p) => new Date(p.observedAt).getTime());
  const minTime = Math.min(...times);
  const maxTime = Math.max(...times);
  const timeSpan = maxTime - minTime || 1;
  const maxPrice = Math.max(...allPoints.map((p) => p.price)) * 1.1 || 1;

  const xScale = (t: number) => padding.left + ((t - minTime) / timeSpan) * plotWidth;
  const yScale = (v: number) => padding.top + plotHeight - (v / maxPrice) * plotHeight;

  return (
    <div className="space-y-2">
      <svg
        viewBox={`0 0 ${width} ${height}`}
        className="w-full"
        role="img"
        aria-label="Gráfico de histórico de preço no período selecionado — os valores exatos estão na tabela ao lado."
      >
        {[0, 0.5, 1].map((frac) => {
          const y = padding.top + frac * plotHeight;
          const value = maxPrice - frac * maxPrice;
          return (
            <g key={frac}>
              <line x1={padding.left} y1={y} x2={width - padding.right} y2={y} stroke="currentColor" className="text-border" strokeWidth={1} />
              <text x={padding.left - 6} y={y} textAnchor="end" dominantBaseline="middle" className="fill-current text-[9px] text-muted-foreground">
                {value.toFixed(0)}
              </text>
            </g>
          );
        })}

        <text x={padding.left} y={height - 6} className="fill-current text-[9px] text-muted-foreground">
          {dateAxisFormatter.format(minTime)}
        </text>
        <text x={width - padding.right} y={height - 6} textAnchor="end" className="fill-current text-[9px] text-muted-foreground">
          {dateAxisFormatter.format(maxTime)}
        </text>

        {nonEmpty.map((s, i) => {
          const sorted = [...s.points].sort((a, b) => new Date(a.observedAt).getTime() - new Date(b.observedAt).getTime());
          const d = sorted
            .map((p, idx) => `${idx === 0 ? "M" : "L"} ${xScale(new Date(p.observedAt).getTime())} ${yScale(p.price)}`)
            .join(" ");
          const color = SERIES_COLORS[i % SERIES_COLORS.length];
          return (
            <g key={s.label}>
              <path d={d} fill="none" stroke={color} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
              {sorted.map((p, idx) => (
                <circle key={idx} cx={xScale(new Date(p.observedAt).getTime())} cy={yScale(p.price)} r={2.5} fill={color} />
              ))}
            </g>
          );
        })}
      </svg>

      <div className="flex flex-wrap gap-x-4 gap-y-1">
        {nonEmpty.map((s, i) => (
          <div key={s.label} className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
            <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: SERIES_COLORS[i % SERIES_COLORS.length] }} aria-hidden="true" />
            {s.label}
          </div>
        ))}
      </div>
    </div>
  );
}
