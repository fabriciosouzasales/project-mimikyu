/**
 * BINDER-HERO-STAGE-01 (2026-08-28) — background atmosférico da TELA INICIAL
 * FECHADA do Binder. Pedido de Fabrício: "o fundo está vazio demais... o
 * binder parece solto em um espaço escuro sem contexto... transformar a
 * tela inicial em um 'hero stage' premium... o binder deve continuar sendo
 * o protagonista absoluto." Escopo estritamente limitado ao estado fechado
 * (`!open` em `binder-nav-view.tsx`) — não toca navegação, quick actions,
 * DnD, nem a lógica/visual do Binder aberto.
 *
 * Restrição explícita e importante: SEM arte oficial, personagens, cartas,
 * pokébolas, logos ou símbolos reconhecíveis da franquia. Tudo aqui é
 * puramente abstrato — gradientes, formas orgânicas desfocadas e partículas
 * — sem nenhum asset de imagem (zero dependências novas, zero arquivos
 * binários), só CSS/SVG.
 *
 * Estruturado em 4 camadas reutilizáveis, como pedido explicitamente
 * ("estruturar o fundo em camadas reutilizáveis... para facilitar
 * refinamentos futuros"), renderizadas nesta ordem (fundo → frente):
 *  1. `AtmosphericLayer` — camada mais ao fundo: manchas de cor amplas
 *     (violeta/teal frios no alto, âmbar terroso embaixo) + vinheta vertical
 *     — dá o "mundo"/horizonte abstrato sem nenhuma forma literal.
 *  2. `DepthLayer` — volumes orgânicos desfocados (blobs com fade radial +
 *     leve `blur`) sugerindo silhuetas distantes (terreno/ruína/pico), só
 *     nas bordas — nunca atrás do centro onde o Binder fica, para não
 *     competir com o objeto.
 *  3. `BaseGlowLayer` — o "hero lighting": spot quente concentrado atrás do
 *     Binder (núcleo mais forte + auréola mais ampla e suave) — é o que faz
 *     o objeto ler como "em evidência no palco", não a atmosfera de fundo.
 *  4. `ParticlesLayer` — poucas partículas discretas (SVG, `feGaussianBlur`),
 *     a maior parte estática; uma fração pequena com uma respiração de
 *     opacidade muito lenta e sutil (8-14s) quando `animate` é true — nunca
 *     todas ao mesmo tempo/fase, para não ler como "efeito" chamativo.
 *     Gate de `prefers-reduced-motion` é responsabilidade de quem chama
 *     (mesmo padrão já usado em `PanelTransition`/`BinderPagesNav`: o valor
 *     computado uma vez em `binder-nav-view.tsx` desce como prop `animate`).
 *
 * Todas as camadas são `aria-hidden` e `pointer-events-none` — decoração
 * pura, sem qualquer interação ou concorrência de foco/clique com o botão
 * de abrir o Binder.
 *
 * LIGHT/DARK (2026-08-29) — "Binder fechado" está na lista de cobertura do
 * pedido de tema. As 3 primeiras camadas (Atmospheric/Depth/BaseGlow) agora
 * usam os tokens `--binder-hero-*` (definidos em `globals.css`, escopados
 * via `.binder-nav-01-scope` na raiz de `binder-nav-view.tsx`) em vez de
 * `hsl(...)` literal — claro e escuro têm gradientes DESENHADOS
 * separadamente (não uma inversão; ver comentário dos tokens em
 * `globals.css`), preservando a mesma estrutura de camadas/blur/posições. O
 * escuro mantém os valores originais byte-a-byte. `ParticlesLayer` não
 * mudou — as partículas continuam com as mesmas cores fixas em ambos os
 * temas: são um detalhe de baixo peso visual (pequenos pontos, opacidade
 * baixa) que não compromete legibilidade nem "não degradar" em nenhum dos
 * dois temas, e recalibrá-las fica fora do orçamento desta rodada.
 */

interface Particle {
  x: number;
  y: number;
  r: number;
  opacity: number;
  warm: boolean;
  animated: boolean;
  duration: number;
  delay: number;
}

// Espalhamento assimétrico e deliberadamente "não-grid" — posições fixas
// (não geradas em runtime) para um resultado determinístico entre renders.
// Concentradas nas bordas/cantos; a faixa central (onde o Binder fica) é
// deixada quase livre para não competir com o objeto.
const PARTICLES: Particle[] = [
  { x: 8, y: 18, r: 0.5, opacity: 0.55, warm: true, animated: true, duration: 9, delay: 0 },
  { x: 16, y: 62, r: 0.35, opacity: 0.4, warm: false, animated: false, duration: 0, delay: 0 },
  { x: 6, y: 82, r: 0.6, opacity: 0.5, warm: true, animated: true, duration: 12, delay: 1.5 },
  { x: 22, y: 40, r: 0.3, opacity: 0.35, warm: false, animated: false, duration: 0, delay: 0 },
  { x: 12, y: 33, r: 0.4, opacity: 0.45, warm: false, animated: true, duration: 11, delay: 3 },
  { x: 92, y: 22, r: 0.45, opacity: 0.5, warm: true, animated: false, duration: 0, delay: 0 },
  { x: 85, y: 58, r: 0.55, opacity: 0.5, warm: true, animated: true, duration: 10, delay: 2 },
  { x: 94, y: 75, r: 0.32, opacity: 0.38, warm: false, animated: false, duration: 0, delay: 0 },
  { x: 78, y: 36, r: 0.38, opacity: 0.42, warm: false, animated: true, duration: 13, delay: 4 },
  { x: 88, y: 88, r: 0.5, opacity: 0.45, warm: true, animated: false, duration: 0, delay: 0 },
  { x: 50, y: 10, r: 0.35, opacity: 0.32, warm: false, animated: true, duration: 14, delay: 1 },
  { x: 34, y: 90, r: 0.4, opacity: 0.4, warm: true, animated: false, duration: 0, delay: 0 },
  { x: 66, y: 92, r: 0.32, opacity: 0.35, warm: false, animated: false, duration: 0, delay: 0 },
  { x: 60, y: 6, r: 0.3, opacity: 0.3, warm: false, animated: true, duration: 10, delay: 5 },
];

function AtmosphericLayer() {
  return <div aria-hidden className="pointer-events-none absolute inset-0" style={{ background: "var(--binder-hero-atmospheric)" }} />;
}

function DepthLayer() {
  return (
    <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden">
      {/* Volume 1 — inferior-esquerdo, amplo e baixo (sugere terreno/ruína distante). */}
      <div
        className="absolute -left-[12%] bottom-[-18%] h-[52%] w-[46%] rounded-[50%]"
        style={{ background: "var(--binder-hero-depth-1)", filter: "blur(20px)" }}
      />
      {/* Volume 2 — inferior-direito, mais alto/estreito (sugere pico/torre distante). */}
      <div
        className="absolute -right-[9%] bottom-[-22%] h-[60%] w-[36%] rounded-[50%]"
        style={{ background: "var(--binder-hero-depth-2)", filter: "blur(24px)" }}
      />
      {/* Volume 3 — névoa alta, centrada no topo, bem baixa opacidade. */}
      <div
        className="absolute left-1/2 top-[-28%] h-[46%] w-[78%] -translate-x-1/2 rounded-[50%]"
        style={{ background: "var(--binder-hero-depth-3)", filter: "blur(28px)" }}
      />
    </div>
  );
}

function BaseGlowLayer() {
  return <div aria-hidden className="pointer-events-none absolute inset-0" style={{ background: "var(--binder-hero-glow)" }} />;
}

function ParticlesLayer({ animate }: { animate: boolean }) {
  return (
    <svg aria-hidden className="pointer-events-none absolute inset-0 h-full w-full" viewBox="0 0 100 100" preserveAspectRatio="none">
      {animate && (
        <style>{`
          @keyframes binderHeroParticleDrift {
            0%, 100% { opacity: 0.22; }
            50% { opacity: 0.62; }
          }
        `}</style>
      )}
      <defs>
        <filter id="binder-hero-particle-blur" x="-80%" y="-80%" width="260%" height="260%">
          <feGaussianBlur stdDeviation="0.55" />
        </filter>
      </defs>
      {PARTICLES.map((particle, index) => (
        <circle
          key={index}
          cx={particle.x}
          cy={particle.y}
          r={particle.r}
          fill={particle.warm ? "hsl(40 70% 70%)" : "hsl(210 40% 78%)"}
          opacity={particle.opacity}
          filter="url(#binder-hero-particle-blur)"
          style={
            animate && particle.animated
              ? { animation: `binderHeroParticleDrift ${particle.duration}s ease-in-out ${particle.delay}s infinite` }
              : undefined
          }
        />
      ))}
    </svg>
  );
}

export function HeroStageBackground({ animate }: { animate: boolean }) {
  return (
    <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden">
      <AtmosphericLayer />
      <DepthLayer />
      <BaseGlowLayer />
      <ParticlesLayer animate={animate} />
    </div>
  );
}
