import { MmkyuWordmark } from "./wordmark";

/**
 * Capa fechada do BINDER-NAV-01 — Rodada 8 (2026-08-28), refinamento pedido
 * por Fabrício a partir de fotos reais de um binder PRETO com zíper
 * (referência mais recente, substituindo a referência marrom/couro usada
 * nas Rodadas 1-7). Cópia local, NÃO edição de `binder-spike/binder-cover.tsx`
 * — aquele componente continua servindo Binder-First/BINDER-VIS-02 e os
 * spikes de motion encerrados exatamente como estava (isolamento
 * experimental total, mesmo padrão já aplicado a todo o resto de
 * `binder-nav-01/`). Reaproveita só a ESTRUTURA (lombada + espessura
 * traseira + capa frontal com zíper/costura) do componente original — todos
 * os tons, texturas e detalhes foram redesenhados para a referência preta.
 *
 * Mudanças pedidas explicitamente por Fabrício nesta rodada:
 *  1. Preto/grafite muito escuro (não mais o marrom `LEATHER_HUE=26` do
 *     Binder-First) — `BLACK_HUE` quase acromático, grão fino e discreto
 *     (`blackLeatherSurface()`), bem menos contraste que o couro marrom
 *     original.
 *  2. Removido o escudo central (glifo SVG) — substituído por wordmark
 *     tipográfico "MMKYU" discreto, debossed, canto inferior esquerdo (ver
 *     `wordmark.tsx`) — "sem inventar um brasão genérico".
 *  3. Removido o bolso frontal (retângulo escuro no canto inferior
 *     direito) — não existe na referência preta e lia como elemento de UI
 *     solto, não como detalhe físico do produto.
 *  4. Zíper/puxador recoloridos para metal escuro/grafite (antes dourado)
 *     — o dourado ficava "brilho artificial" demais para a sobriedade da
 *     referência preta; o puxador também encolheu.
 *  5. Cantos mais arredondados (`rounded-xl` → `rounded-2xl`) e costura
 *     periférica mais discreta (opacidade menor, traço mais fino).
 * O glow/halo dourado ambiente (pedido "reduzir excesso de glow") foi
 * tratado em `binder-nav-view.tsx`, não aqui — é um efeito de palco atrás do
 * objeto, não da capa em si.
 *
 * Ajuste adicional (2026-08-28, mesma rodada) — "melhorar a dobra do
 * binder", a partir de uma segunda referência (fichário preto saffiano,
 * vista frontal). Primeira tentativa (sombreamento cilíndrico + duas
 * costuras internas + lombada larga a 12%) foi REJEITADA por Fabrício: "do
 * jeito que ficou é a visão lateral do binder e não a visão frontal, como
 * queremos" — a lombada larga com textura e costuras próprias competia
 * visualmente com a capa frontal e lia como um segundo painel de perfil, não
 * como a borda fina de um objeto visto de frente.
 *
 * Correção: lombada reduzida para uma fresta fina (`SPINE_PCT` 12 → 5) e
 * simplificada para `spineSurface()` — um único gradiente escuro-claro-escuro
 * sem grão próprio, lendo como uma borda que se afasta do olhar (like a
 * quina de um livro visto quase de frente), não como uma segunda face
 * plana. Removidas as duas costuras internas da lombada (eram o principal
 * motivo da leitura de "perfil") — o vinco na borda esquerda da capa
 * frontal (`boxShadow` "Vinco da dobra") já basta para separar os dois
 * painéis sem competir com a capa.
 */

export const BLACK_HUE = 30; // leve calor neutro — evita ler como preto 100% chapado/plástico
const SPINE_PCT = 5;

// Exportados para reuso em `binder-pages-nav.tsx` — a moldura interna (borda,
// zíper, puxador) precisa da MESMA paleta preta da capa fechada em vez do
// marrom/dourado herdado de `binder-spike/binder-cover.tsx` (pedido de
// Fabrício, 2026-08-28: "a cor da borda da parte interna deve sempre estar
// de acordo com a cor do binder").
export function blackLeatherSurface() {
  return [
    "repeating-linear-gradient(115deg, hsl(0 0% 100% / 0.025) 0px, hsl(0 0% 100% / 0.025) 1px, transparent 1px, transparent 2.5px)",
    "repeating-linear-gradient(25deg, hsl(0 0% 0% / 0.05) 0px, hsl(0 0% 0% / 0.05) 1px, transparent 1px, transparent 3px)",
    "linear-gradient(125deg, hsl(0 0% 100% / 0.05) 0%, transparent 26%)",
    `linear-gradient(155deg, hsl(${BLACK_HUE} 6% 13%) 0%, hsl(${BLACK_HUE} 5% 8%) 55%, hsl(${BLACK_HUE} 6% 4%) 100%)`,
  ].join(", ");
}

function spineSurface() {
  // Fresta fina única — sem grão próprio (evita competir com a capa frontal
  // e ler como um segundo painel/vista lateral). Só um gradiente
  // escuro-claro-escuro bem sutil, suficiente para sugerir a curvatura de
  // uma borda que se afasta do olhar.
  return `linear-gradient(90deg, hsl(${BLACK_HUE} 5% 2%) 0%, hsl(${BLACK_HUE} 6% 7%) 45%, hsl(${BLACK_HUE} 5% 3%) 100%)`;
}

export function darkZipperTeeth(vertical: boolean) {
  const angle = vertical ? "180deg" : "90deg";
  return `repeating-linear-gradient(${angle}, hsl(0 0% 42%) 0px, hsl(0 0% 42%) 1.5px, hsl(0 0% 10%) 1.5px, hsl(0 0% 10%) 3px)`;
}

export function BinderCoverClosed({ viewTransitionName }: { viewTransitionName?: string }) {
  return (
    <div
      className="relative"
      style={{
        width: "clamp(240px, min(80vw, 58dvh), 480px)",
        aspectRatio: "0.72",
        viewTransitionName,
        filter: "drop-shadow(0 40px 46px rgba(0,0,0,0.55))",
      }}
    >
      {/* Lombada — fresta fina simulando a borda do binder visto de frente
          (ver nota de correção 2026-08-28 no topo do arquivo). Sem costuras
          nem grão próprios — só o gradiente de `spineSurface()`. */}
      <div
        className="absolute rounded-l-2xl"
        style={{
          top: 3,
          bottom: -7,
          left: 0,
          width: `${SPINE_PCT}%`,
          backgroundImage: spineSurface(),
          boxShadow: "inset -3px 0 6px rgba(0,0,0,0.7), inset 2px 0 4px rgba(0,0,0,0.5)",
        }}
        aria-hidden
      />
      {/* Espessura traseira. */}
      <div
        className="absolute rounded-2xl"
        style={{ top: 5, left: `${SPINE_PCT}%`, right: -7, bottom: -9, background: `hsl(${BLACK_HUE} 5% 3%)` }}
        aria-hidden
      />
      {/* Capa frontal. */}
      <div
        className="absolute overflow-hidden rounded-2xl"
        style={{
          top: 0,
          left: `${SPINE_PCT}%`,
          right: 0,
          bottom: 0,
          backgroundImage: blackLeatherSurface(),
          boxShadow: [
            "inset 0 1px 0 hsl(0 0% 100% / 0.08)",
            "inset 0 -3px 8px hsl(0 0% 0% / 0.55)",
            "inset 1px 0 0 hsl(0 0% 100% / 0.03)",
            // Vinco da dobra — sombra estreita junto à borda esquerda, onde a
            // capa frontal articula com a lombada (reforça a leitura de dois
            // painéis reais, não uma textura única cortada ao meio).
            "inset 7px 0 10px -7px hsl(0 0% 0% / 0.6)",
          ].join(", "),
          border: "1px solid hsl(0 0% 0% / 0.5)",
        }}
      >
        {/* Costura periférica — discreta. */}
        <div
          className="pointer-events-none absolute rounded-xl"
          style={{ inset: 9, border: "1.25px dashed hsl(0 0% 100% / 0.1)" }}
          aria-hidden
        />

        {/* Zíper — topo, direita, base (a esquerda é a lombada). */}
        <div
          className="pointer-events-none absolute inset-x-4 top-[7px] h-[2.5px] rounded-full"
          style={{ backgroundImage: darkZipperTeeth(false), boxShadow: "0 1px 1px rgba(0,0,0,0.6)" }}
          aria-hidden
        />
        <div
          className="pointer-events-none absolute inset-y-4 right-[6px] w-[2.5px] rounded-full"
          style={{ backgroundImage: darkZipperTeeth(true), boxShadow: "0 0 1px rgba(0,0,0,0.6)" }}
          aria-hidden
        />
        <div
          className="pointer-events-none absolute inset-x-4 bottom-[7px] h-[2.5px] rounded-full"
          style={{ backgroundImage: darkZipperTeeth(false), boxShadow: "0 -1px 1px rgba(0,0,0,0.6)" }}
          aria-hidden
        />
        {/* Puxador — metal escuro/grafite, pequeno e discreto (antes dourado e maior). */}
        <div
          className="absolute right-[3px] top-[9%] h-3 w-[7px] rounded-[2px]"
          style={{
            background: "linear-gradient(160deg, hsl(0 0% 46%), hsl(0 0% 16%))",
            boxShadow: "0 1px 2px rgba(0,0,0,0.55), inset 0 1px 0 hsl(0 0% 100% / 0.2)",
          }}
          aria-hidden
        />

        {/* Identidade — wordmark tipográfico, canto inferior esquerdo, debossed/baixo contraste
            (substitui o escudo central — "não quero aquele escudo central como protagonista"). */}
        <div className="absolute bottom-[7%] left-[9%]" aria-hidden>
          <MmkyuWordmark size="sm" tone={`hsl(${BLACK_HUE} 5% 24%)`} />
        </div>
      </div>
    </div>
  );
}
