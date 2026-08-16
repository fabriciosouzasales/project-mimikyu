import Image from "next/image";
import type { CSSProperties } from "react";
import { cn } from "@/lib/utils";
import { AuthProtagonistFloat } from "./auth-protagonist-motion";
import styles from "./auth-hero.module.css";

const HEADLINE = "Sua coleção. Organizada, completa e sempre com você.";
const SUBHEADLINE =
  "Da primeira carta ao Master Set, o MMKYU TCG Collector transforma sua coleção Pokémon TCG em uma experiência viva. Organize suas cartas, acompanhe seu progresso, gerencie cada variação e construa coleções do seu jeito. Tudo em um só lugar!";

/**
 * Auth Hero — direção "cartas reais" (protótipos v3 → v4, aprovados
 * 2026-08-15). 1 carta protagonista grande e legível (Mimikyu/Safeguard,
 * `svp-075v1`), 2 secundárias parcialmente sobrepostas em profundidades
 * diferentes, 1 slot vazio tratado como reentrância física (não um
 * placeholder de UI com borda tracejada/ícone/texto) — "cartas presentes =
 * coleção construída, slot vazio = coleção a completar", ecoando a headline.
 *
 * Ativos estáticos versionados em `public/auth/hero/` — decisão
 * arquitetural fechada nesta rodada (ver docs/log.md): sem Supabase
 * Storage, sem catálogo, sem TCGdex, sem seleção aleatória/dinâmica, sem
 * fetch em runtime. `hero-mimikyu.webp` (640×896) é a ÚNICA imagem com
 * `priority` (candidata a LCP); as duas secundárias carregam lazy (padrão
 * do `next/image`) e, por viverem dentro de um contêiner `hidden sm:block`
 * na composição "cluster", nunca dão fetch em viewport mobile (elemento
 * `display:none` nunca cruza o IntersectionObserver que dispara o lazy
 * load).
 *
 * Três composições, não duas — "tablet não é desktop simplesmente
 * comprimido" (instrução explícita da rodada de implementação):
 *   - `cluster` (renderizado a partir de `sm:`, ou seja tablet E desktop):
 *     as 4 peças completas. Tablet: card constant width um pouco), headline
 *     à direita — usa a largura horizontal do tablet em vez de espremer o
 *     layout de 2 colunas do desktop. Desktop: pilha vertical (cluster em
 *     cima, headline embaixo), replicando a composição exata do protótipo
 *     v4.
 *   - `compact` (abaixo de `sm:`, mobile): só a carta protagonista,
 *     centralizada, sem secundárias/slot vazio — headline abaixo, menor.
 * Nota de transparência: v4 só especificou o viewport desktop; as
 * composições tablet/mobile abaixo são interpretação nova desta rodada
 * (não vistas em nenhum protótipo aprovado) — vale conferência visual
 * dedicada de Fabrício nesses dois breakpoints.
 *
 * Server Component em maioria (sem "use client" neste arquivo): zero JS
 * novo no bundle do cliente, exceto a peça protagonista, que usa
 * `AuthProtagonistFloat` — único Client Component "folha" desta rodada de
 * polish (ver esse arquivo para o racional da flutuação sutil, extraída de
 * `holo-card.tsx`). Posições/rotação de cada peça vêm de constantes
 * determinísticas (nunca `Math.random()`), expressas em % do "stage" (ver
 * auth-hero.module.css para a correção do bug de especificidade herdado
 * dos protótipos v3/v4: inline `transform: rotate()` nunca teria permitido
 * o hover funcionar).
 *
 * Rodada de polish (2026-08-16, protagonismo + motion + slot vazio + copy,
 * ver docs/log.md): larguras do cluster aumentadas moderadamente (mais
 * sobreposição = menos "distância" percebida entre as cartas, sem redesenho
 * de posições), secundárias com menos blur/dessaturação (ver
 * auth-hero.module.css), slot vazio com brilho dourado interno lento
 * (`.ghostGlow`), gap entre cluster e headline reduzido para ler como uma
 * narrativa única.
 *
 * Copy definitiva (rodada de polish final, mesma data): `HEADLINE`/
 * `SUBHEADLINE` fixas abaixo, sem mecanismo de variante — o andaime
 * temporário de comparação (`?copy=a|b|c`, `auth-copy-variants.ts`) foi
 * removido depois da decisão de Fabrício. Headline/subheadline em Inter
 * (`var(--font-sans)`, ver `auth-hero.module.css`) — Fraunces descartada,
 * "funcionou na exploração mas ficou pesada demais para a direção final".
 * A subheadline é bem mais longa que a anterior; os contêineres do hero
 * (`auth-hero-shell.tsx`) usam `min-h-*` em vez de `h-*` abaixo do
 * desktop para crescer com o texto sem cortar nada — por isso os blocos
 * internos usam `lg:h-full` (não `h-full` incondicional): só no desktop o
 * grid garante uma altura definida para centralizar verticalmente: abaixo
 * disso, altura automática é o comportamento certo.
 */

type Piece = {
  key: string;
  left: number;
  top: number;
  width: number;
  rotate: number;
  scale?: number;
  delayMs: number;
  z?: number;
};

// Percentuais derivados das posições absolutas (px) do protótipo v4, sobre
// um "stage" de referência de 540×460 — preserva a composição exata em
// qualquer largura via aspect-ratio, sem hack de `transform: scale()`.
// Larguras aumentadas moderadamente nesta rodada de polish (protagonismo
// do cluster) — mesmas posições left/top do v4, só a escala de cada peça
// cresceu, o que também aproxima visualmente as cartas entre si.
const SECONDARY_1: Piece = { key: "sec-1", left: 0, top: 20.9, width: 36, rotate: -8, scale: 0.94, delayMs: 0 };
const SECONDARY_2: Piece = { key: "sec-2", left: 24.4, top: 0.4, width: 34, rotate: 7, scale: 0.92, delayMs: 90 };
const GHOST: Piece = { key: "ghost", left: 62.2, top: 23.9, width: 35.7, rotate: -2, delayMs: 180 };
const PROTAGONIST: Piece = { key: "hero", left: 29.3, top: 5.7, width: 49, rotate: -4, delayMs: 260, z: 5 };

function pieceStyle(p: Piece): CSSProperties {
  return {
    left: `${p.left}%`,
    top: `${p.top}%`,
    width: `${p.width}%`,
    animationDelay: `${p.delayMs}ms`,
    zIndex: p.z,
    // Consumidas por auth-hero.module.css — nunca `transform` direto (ver
    // comentário no módulo sobre o bug de especificidade dos protótipos).
    ["--piece-rotate" as string]: `${p.rotate}deg`,
    ...(p.scale ? { ["--piece-scale" as string]: p.scale } : {}),
  } as CSSProperties;
}

function ClusterStage() {
  return (
    <div className={styles.stage} aria-hidden="true">
      <div className={cn(styles.piece, styles.secondary)} style={pieceStyle(SECONDARY_1)}>
        <div className={styles.art}>
          <Image src="/auth/hero/hero-secondary-01.webp" alt="" fill sizes="(min-width: 1024px) 200px, 130px" />
        </div>
        <div className={styles.vignette} />
      </div>

      <div className={cn(styles.piece, styles.secondary)} style={pieceStyle(SECONDARY_2)}>
        <div className={styles.art}>
          <Image src="/auth/hero/hero-secondary-02.webp" alt="" fill sizes="(min-width: 1024px) 190px, 125px" />
        </div>
        <div className={styles.vignette} />
      </div>

      <div className={cn(styles.piece, styles.ghost)} style={pieceStyle(GHOST)}>
        <div className={styles.residual} />
        <div className={styles.ghostGlow} />
      </div>

      <AuthProtagonistFloat className={cn(styles.piece, styles.heroPiece)} style={pieceStyle(PROTAGONIST)}>
        <div className={styles.art}>
          <Image
            src="/auth/hero/hero-mimikyu.webp"
            alt="Carta Mimikyu (Safeguard) da coleção MMKYU"
            fill
            sizes="(min-width: 1024px) 400px, 280px"
            priority
          />
        </div>
        <div className={styles.vignette} />
        <div className={styles.sheen} />
        <div className={styles.rim} />
      </AuthProtagonistFloat>
    </div>
  );
}

export function AuthHero() {
  return (
    <div className="relative overflow-hidden bg-[radial-gradient(130%_100%_at_26%_16%,hsl(var(--auth-hero-1)),hsl(var(--auth-hero-2))_68%)] lg:h-full">
      <div className={styles.glow} aria-hidden="true" />

      {/* Tablet + Desktop — as 4 peças completas. */}
      <div className="hidden sm:flex sm:flex-col sm:justify-center sm:px-10 sm:py-10 lg:h-full lg:px-16 lg:py-16">
        {/* Tablet: cluster + headline lado a lado (usa a largura horizontal). */}
        <div className="flex flex-row items-center gap-7 lg:hidden">
          <div className="w-[240px] shrink-0">
            <ClusterStage />
          </div>
          <div className="min-w-0">
            <h1 className={cn(styles.headline, "max-w-[380px] text-[28px] leading-[1.15] text-[hsl(var(--auth-hero-ink))]")}>
              {HEADLINE}
            </h1>
            <p className={cn(styles.sub, "mt-3 max-w-[400px] text-[13.5px] leading-[1.6] text-[hsl(var(--auth-hero-ink)/0.6)]")}>
              {SUBHEADLINE}
            </p>
          </div>
        </div>

        {/* Desktop: cluster em cima, headline embaixo — composição exata do v4,
            gap reduzido (cluster+slot+headline como uma narrativa única).
            Headline/subheadline redimensionadas nesta rodada para Inter e
            para o texto definitivo (bem mais longo) — max-width mais largo
            na subheadline em vez de espremer a fonte para caber. */}
        <div className="hidden lg:block">
          <div className="mx-auto w-full max-w-[560px]">
            <div className="mb-6">
              <ClusterStage />
            </div>
            <h1 className={cn(styles.headline, "max-w-[560px] text-[42px] leading-[1.15] text-[hsl(var(--auth-hero-ink))]")}>
              {HEADLINE}
            </h1>
            <p className={cn(styles.sub, "mt-5 max-w-[480px] text-[15px] leading-[1.62] text-[hsl(var(--auth-hero-ink)/0.6)]")}>
              {SUBHEADLINE}
            </p>
          </div>
        </div>
      </div>

      {/* Mobile — só a protagonista, centralizada, sem secundárias/slot vazio.
          Card preservado no mesmo tamanho (não alterar tamanho/hierarquia das
          cartas) — o contêiner cresce (`min-h-*` no shell) para acomodar a
          subheadline bem mais longa, em vez de reduzir a fonte para caber. */}
      <div className="flex flex-col items-center justify-center gap-3 px-6 py-7 text-center sm:hidden">
        <AuthProtagonistFloat
          className={cn(styles.piece, styles.heroPiece, "w-[138px]")}
          style={{ position: "relative", animationDelay: "120ms" } as CSSProperties}
        >
          <div className={styles.art}>
            <Image
              src="/auth/hero/hero-mimikyu.webp"
              alt="Carta Mimikyu (Safeguard) da coleção MMKYU"
              fill
              sizes="150px"
            />
          </div>
          <div className={styles.vignette} />
          <div className={styles.sheen} />
          <div className={styles.rim} />
        </AuthProtagonistFloat>
        <div>
          <h1 className={cn(styles.headline, "text-[22px] leading-[1.2] text-[hsl(var(--auth-hero-ink))]")}>
            {HEADLINE}
          </h1>
          <p className={cn(styles.sub, "mt-2 max-w-[300px] text-[12.5px] leading-[1.55] text-[hsl(var(--auth-hero-ink)/0.6)]")}>
            {SUBHEADLINE}
          </p>
        </div>
      </div>
    </div>
  );
}
