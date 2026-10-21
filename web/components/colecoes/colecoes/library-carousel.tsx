"use client";

import Link from "next/link";
import {
  type CSSProperties,
  type KeyboardEvent as ReactKeyboardEvent,
  type MouseEvent as ReactMouseEvent,
  type PointerEvent as ReactPointerEvent,
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";
import { ArrowRight, ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatCount } from "@/lib/colecoes/acervo";
import { plateCode, plateLogoKey } from "@/lib/colecoes/free-collection";
import { collectionHref, collectionProgressView, collectionSubtitle } from "@/lib/colecoes/colecoes";
import type { CollectionSummary } from "@/lib/colecoes/colecoes-queries";
import { BinderCover } from "./binder-cover";
import { isPokedexCollection } from "@/lib/colecoes/pokedex";
import coverStyles from "./binder-cover.module.css";
import { CollectionKindLine } from "./collection-kind-badge";
import styles from "./library-carousel.module.css";

/**
 * Minhas coleções — modo Carrossel (COLLECTION LIBRARY VIEW MODES-01 +
 * COLLECTION CAROUSEL EXPERIENCE REFINEMENT-01).
 *
 * Experiência aprovada (North Star §5.1, log 29/08): motor do Character
 * Filmstrip com a identidade Binder MMKYU — aqui com o fichário 3D oficial
 * (NS-16, o mesmo do modo Cards), nativo, sem iframe.
 *
 * Composição por quantidade:
 * - **1 coleção** → "vitrine": o fichário maior, com nome, Set, progresso e
 *   "Abrir coleção" ao lado (empilhados no celular). Sem fita, sem controles,
 *   sem fichários simulados; altura = altura do fichário.
 * - **2 coleções** → fita linear (o laço faria o vizinho trocar de lado);
 *   só aparece a seta que tem para onde ir.
 * - **3 ou mais** → fita circular, como o Filmstrip do spike: as setas nunca
 *   ficam inativas e os vizinhos sempre existem dos dois lados.
 *
 * Do spike (curvas inalteradas): foco `e^(-d²·1,28)`, escala
 * `0,54 + side·0,15 + focus·0,54` (normalizada para a frente valer 1), recuo
 * `z = focus·145 − d·148`, giro para o centro, `rotateZ = d·0,7`, opacidade
 * `max(0,13, side·0,76 + focus·0,24)` e a aproximação exponencial por quadro
 * `1 − 0,001^(dt/1000)`. Fora do spike, por decisão de produto: sem balanço
 * ocioso nem varredura ao passar o ponteiro (o carrossel só anda quando
 * pedido), sem blur (custo de pintura) e o laço para quando assenta.
 *
 * Interação: setas ‹ › ao lado do título (perto do fichário), ←/→, Home/End,
 * roda horizontal, arrasto/swipe, clique num vizinho traz para a frente;
 * clique/Enter no da frente abre a coleção. prefers-reduced-motion: troca
 * instantânea, sem inclinação.
 */

const VISIBLE_RANGE = 4.5;
/** Passo horizontal = fração da largura do fichário (vizinhos parcialmente encobertos). */
const SPACING_RATIO = 0.64;
const DRAG_THRESHOLD = 6;
const WHEEL_STEP = 48;
/** Até quantas coleções a posição aparece como pontos; acima disso, "3 / 48". */
const DOTS_MAX = 12;

type Pose = { transform: string; opacity: number; zIndex: number; visible: boolean };

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function mod(value: number, size: number): number {
  return ((value % size) + size) % size;
}

/** Distância do item ao centro: circular a partir de 3 coleções, linear com 2. */
function deltaOf(index: number, phase: number, count: number, circular: boolean): number {
  let delta = index - phase;
  if (!circular) return delta;
  while (delta > count / 2) delta -= count;
  while (delta < -count / 2) delta += count;
  return delta;
}

/** Pose de um item a `delta` posições do centro (curvas do spike). */
function poseFor(delta: number, tiltX: number, tiltY: number): Pose {
  const distance = Math.abs(delta);
  const focus = Math.exp(-distance * distance * 1.28);
  const side = Math.max(0, 1 - distance / 5);
  const sign = delta === 0 ? 0 : delta > 0 ? 1 : -1;
  const y = distance * 6 + tiltY * focus * 8;
  const z = focus * 145 - distance * 148;
  const scale = (0.54 + side * 0.15 + focus * 0.54) / 1.23;
  // O spike girava em degrau a partir de d = 0,2; aqui a entrada é contínua.
  const turn = Math.min(1, distance / 0.6) * (14 + Math.min(distance, 3) * 5);
  const rotateY = -sign * turn + tiltX * focus * 4;
  const rotateZ = delta * 0.7;
  const opacity = Math.max(0.13, side * 0.76 + focus * 0.24);
  const transform =
    `translate(-50%, -50%) translate3d(calc(var(--lib-card-w) * ${(delta * SPACING_RATIO).toFixed(4)}), ` +
    `${y.toFixed(2)}px, ${z.toFixed(2)}px) rotateY(${rotateY.toFixed(2)}deg) rotateZ(${rotateZ.toFixed(2)}deg) ` +
    `scale(${scale.toFixed(4)})`;
  return { transform, opacity, zIndex: Math.round(1000 - distance * 100), visible: distance <= VISIBLE_RANGE };
}

function poseStyle(pose: Pose): CSSProperties {
  return {
    transform: pose.transform,
    opacity: pose.opacity,
    zIndex: pose.zIndex,
    visibility: pose.visible ? "visible" : "hidden",
  };
}

function spokenProgress(collection: CollectionSummary): string {
  const view = collectionProgressView(collection);
  return view.kind === "goal"
    ? `${view.label}${view.complete ? ", completa" : `, ${view.percentText}`}`
    : `${formatCount(view.copies)} ${view.copies === 1 ? "carta" : "cartas"}`;
}

/** Nome, Set e progresso da coleção em foco — o mesmo bloco na vitrine e na fita. */
function FocusDetails({ collection, compact }: { collection: CollectionSummary; compact?: boolean }) {
  const progress = collectionProgressView(collection);
  return (
    <>
      <p className={styles.focusName}>{collection.name}</p>
      <p className={styles.focusKind}>
        <CollectionKindLine collection={collection} />
      </p>
      {progress.kind === "goal" ? (
        <div className={styles.focusProgress} data-compact={compact || undefined}>
          <span className={styles.track}>
            <span
              key={collection.id}
              className={progress.complete ? `${styles.fill} ${styles.fillComplete}` : styles.fill}
              style={{ width: `${progress.barPercent}%` }}
            />
          </span>
          <span className={styles.focusCount}>
            <strong>{progress.label}</strong>
            <span className={progress.complete ? styles.focusDone : undefined}>
              {progress.complete ? "completa" : progress.percentText}
            </span>
          </span>
        </div>
      ) : (
        <p className={styles.focusCopies}>
          <strong>{formatCount(progress.copies)}</strong> {progress.copies === 1 ? "carta reunida" : "cartas reunidas"}
        </p>
      )}
    </>
  );
}

export function LibraryCarousel(props: {
  items: readonly CollectionSummary[];
  logoUrls: Readonly<Record<string, string>>;
  initialIndex: number;
  onActiveChange?: (index: number) => void;
}) {
  if (props.items.length === 1 && props.items[0]) {
    return <LibrarySpotlight collection={props.items[0]} logoUrls={props.logoUrls} />;
  }
  return <LibraryFilmstrip {...props} />;
}

/** Uma coleção: vitrine, sem fita nem controles. */
function LibrarySpotlight({
  collection,
  logoUrls,
}: {
  collection: CollectionSummary;
  logoUrls: Readonly<Record<string, string>>;
}) {
  const logoKey = plateLogoKey(collection);
        const logoUrl = logoKey ? logoUrls[logoKey] ?? null : null;
  return (
    <section className={styles.carousel} aria-label="Sua coleção">
      <div className={styles.spotlight}>
        <Link
          href={collectionHref(collection.id)}
          className={`${styles.spotlightCover} ${coverStyles.trigger}`}
          aria-label={`Abrir ${collection.name}, ${collectionSubtitle(collection)}, ${spokenProgress(collection)}`}
        >
          <span className={styles.spotlightGlow} aria-hidden="true" />
          <BinderCover
            finish={collection.finish}
            setName={collection.cardSetName}
            setCode={plateCode(collection)}
            logoUrl={logoUrl}
            fallbackTitle={collection.name}
            emblem={isPokedexCollection(collection) ? "pokedex" : null}
            complete={collection.isComplete}
            priority
          />
        </Link>
        <div className={styles.spotlightInfo}>
          <FocusDetails collection={collection} />
          <div className={styles.focusActions}>
            <Button asChild variant="outline-primary" className="h-10 px-4">
              <Link href={collectionHref(collection.id)}>
                Abrir coleção
                <ArrowRight className="h-4 w-4" aria-hidden="true" />
              </Link>
            </Button>
          </div>
        </div>
      </div>
    </section>
  );
}

function LibraryFilmstrip({
  items,
  logoUrls,
  initialIndex,
  onActiveChange,
}: {
  items: readonly CollectionSummary[];
  logoUrls: Readonly<Record<string, string>>;
  initialIndex: number;
  onActiveChange?: (index: number) => void;
}) {
  const count = items.length;
  const last = count - 1;
  const circular = count >= 3;
  const [startIndex] = useState(() => clamp(initialIndex, 0, Math.max(0, last)));
  const [active, setActive] = useState(startIndex);

  const stageRef = useRef<HTMLDivElement>(null);
  const cardRefs = useRef<(HTMLLIElement | null)[]>([]);
  const linkRefs = useRef<(HTMLAnchorElement | null)[]>([]);
  const motion = useRef({
    phase: startIndex,
    target: startIndex,
    tiltX: 0,
    tiltY: 0,
    tiltTargetX: 0,
    tiltTargetY: 0,
    raf: 0,
    lastTime: 0,
    reduced: false,
    activeIndex: startIndex,
  });
  const drag = useRef({
    pointerId: -1,
    startX: 0,
    startTarget: 0,
    spacing: 1,
    dragging: false,
    lastX: 0,
    lastT: 0,
    velocity: 0,
    suppressClick: false,
  });
  const wheelAccumulator = useRef(0);

  // Poses da primeira pintura (servidor e hidratação). Constantes: o React nunca
  // reescreve o `style` depois disso; o laço de animação é o único escritor.
  const [initialPoses] = useState(() =>
    items.map((_, index) => poseStyle(poseFor(deltaOf(index, startIndex, count, circular), 0, 0))),
  );

  const indexAt = useCallback(
    (position: number) => (circular ? mod(Math.round(position), count) : clamp(Math.round(position), 0, last)),
    [circular, count, last],
  );

  const apply = useCallback(() => {
    const state = motion.current;
    for (let index = 0; index < cardRefs.current.length; index += 1) {
      const element = cardRefs.current[index];
      if (!element) continue;
      const pose = poseFor(deltaOf(index, state.phase, count, circular), state.tiltX, state.tiltY);
      element.style.transform = pose.transform;
      element.style.opacity = String(pose.opacity);
      element.style.zIndex = String(pose.zIndex);
      element.style.visibility = pose.visible ? "visible" : "hidden";
    }
  }, [circular, count]);

  const step = useCallback(
    (now: number) => {
      const state = motion.current;
      const dt = state.lastTime ? Math.min(64, now - state.lastTime) : 16;
      state.lastTime = now;
      const ease = state.reduced ? 1 : 1 - Math.pow(0.001, dt / 1000);
      state.phase += (state.target - state.phase) * ease;
      state.tiltX += (state.tiltTargetX - state.tiltX) * ease;
      state.tiltY += (state.tiltTargetY - state.tiltY) * ease;
      const settled =
        Math.abs(state.target - state.phase) < 0.0005 &&
        Math.abs(state.tiltTargetX - state.tiltX) < 0.002 &&
        Math.abs(state.tiltTargetY - state.tiltY) < 0.002;
      if (settled && drag.current.pointerId === -1) {
        state.phase = state.target;
        state.tiltX = state.tiltTargetX;
        state.tiltY = state.tiltTargetY;
        apply();
        state.raf = 0;
        state.lastTime = 0;
        return;
      }
      apply();
      state.raf = requestAnimationFrame(step);
    },
    [apply],
  );

  const kick = useCallback(() => {
    const state = motion.current;
    if (state.raf) return;
    state.lastTime = 0;
    state.raf = requestAnimationFrame(step);
  }, [step]);

  const syncActive = useCallback(
    (index: number) => {
      if (motion.current.activeIndex === index) return;
      motion.current.activeIndex = index;
      setActive(index);
      onActiveChange?.(index);
    },
    [onActiveChange],
  );

  /** Anda `offset` posições a partir do alvo atual (na fita circular, sem limite). */
  const shift = useCallback(
    (offset: number, moveFocus: boolean) => {
      const state = motion.current;
      const base = Math.round(state.target);
      const next = circular ? base + offset : clamp(base + offset, 0, last);
      state.target = next;
      const index = indexAt(next);
      syncActive(index);
      kick();
      if (moveFocus) linkRefs.current[index]?.focus({ preventScroll: true });
    },
    [circular, indexAt, kick, last, syncActive],
  );

  /** Traz um índice para a frente pelo caminho mais curto. */
  const moveTo = useCallback(
    (index: number, moveFocus: boolean) => {
      const current = indexAt(motion.current.target);
      let offset = index - current;
      if (circular) {
        if (offset > count / 2) offset -= count;
        if (offset < -count / 2) offset += count;
      }
      shift(offset, moveFocus);
    },
    [circular, count, indexAt, shift],
  );

  useEffect(() => {
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => {
      motion.current.reduced = query.matches;
      if (query.matches) {
        motion.current.tiltTargetX = 0;
        motion.current.tiltTargetY = 0;
        kick();
      }
    };
    update();
    query.addEventListener("change", update);
    const state = motion.current;
    return () => {
      query.removeEventListener("change", update);
      if (state.raf) cancelAnimationFrame(state.raf);
      state.raf = 0;
    };
  }, [kick]);

  // Itens trocados sem remontar (ex.: atualização da página): reposiciona e
  // mantém a seleção válida.
  useEffect(() => {
    const state = motion.current;
    if (!circular && state.target > last) {
      state.target = Math.max(0, last);
      state.phase = state.target;
    }
    syncActive(indexAt(state.target));
    apply();
  }, [items, circular, last, apply, indexAt, syncActive]);

  // Roda: só o eixo horizontal (trackpad) ou Shift + roda. A rolagem vertical
  // da página nunca é capturada.
  useEffect(() => {
    const stage = stageRef.current;
    if (!stage) return;
    const onWheel = (event: WheelEvent) => {
      const horizontal = Math.abs(event.deltaX) > Math.abs(event.deltaY);
      const delta = horizontal ? event.deltaX : event.shiftKey ? event.deltaY : 0;
      if (delta === 0) return;
      event.preventDefault();
      wheelAccumulator.current += delta;
      if (Math.abs(wheelAccumulator.current) >= WHEEL_STEP) {
        const direction = wheelAccumulator.current > 0 ? 1 : -1;
        wheelAccumulator.current = 0;
        shift(direction, false);
      }
    };
    stage.addEventListener("wheel", onWheel, { passive: false });
    return () => stage.removeEventListener("wheel", onWheel);
  }, [shift]);

  const onKeyDown = (event: ReactKeyboardEvent) => {
    if (event.key === "ArrowRight") shift(1, true);
    else if (event.key === "ArrowLeft") shift(-1, true);
    else if (event.key === "Home") moveTo(0, true);
    else if (event.key === "End") moveTo(last, true);
    else return;
    event.preventDefault();
  };

  const onPointerDown = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (event.button !== 0) return;
    const firstCard = cardRefs.current[0];
    drag.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startTarget: motion.current.target,
      spacing: Math.max(1, (firstCard?.offsetWidth ?? 200) * SPACING_RATIO),
      dragging: false,
      lastX: event.clientX,
      lastT: event.timeStamp,
      velocity: 0,
      suppressClick: false,
    };
  };

  const onPointerMove = (event: ReactPointerEvent<HTMLDivElement>) => {
    const state = drag.current;
    if (state.pointerId === event.pointerId) {
      const dx = event.clientX - state.startX;
      if (!state.dragging && Math.abs(dx) > DRAG_THRESHOLD) {
        state.dragging = true;
        event.currentTarget.setPointerCapture(event.pointerId);
      }
      if (state.dragging) {
        const dt = Math.max(1, event.timeStamp - state.lastT);
        state.velocity = state.velocity * 0.6 + ((event.clientX - state.lastX) / dt) * 0.4;
        state.lastX = event.clientX;
        state.lastT = event.timeStamp;
        const raw = state.startTarget - dx / state.spacing;
        // Na fita linear, resistência elástica além das pontas.
        const target = circular ? raw : raw < 0 ? raw * 0.35 : raw > last ? last + (raw - last) * 0.35 : raw;
        motion.current.target = target;
        syncActive(indexAt(target));
        kick();
      }
      return;
    }
    // Inclinação sutil do fichário da frente (só mouse, sem reduced-motion).
    if (event.pointerType === "mouse" && !motion.current.reduced) {
      const rect = event.currentTarget.getBoundingClientRect();
      motion.current.tiltTargetX = clamp(((event.clientX - rect.left) / rect.width - 0.5) * 2, -1, 1);
      motion.current.tiltTargetY = clamp(((event.clientY - rect.top) / rect.height - 0.5) * 2, -1, 1);
      kick();
    }
  };

  const endDrag = (event: ReactPointerEvent<HTMLDivElement>) => {
    const state = drag.current;
    if (state.pointerId !== event.pointerId) return;
    state.pointerId = -1;
    if (!state.dragging) return;
    state.dragging = false;
    state.suppressClick = true;
    // Arremesso: a velocidade final empurra até ~2 posições.
    const fling = clamp((-state.velocity * 160) / state.spacing, -2, 2);
    const target = Math.round(motion.current.target + fling);
    motion.current.target = circular ? target : clamp(target, 0, last);
    syncActive(indexAt(motion.current.target));
    kick();
  };

  const onPointerLeave = () => {
    motion.current.tiltTargetX = 0;
    motion.current.tiltTargetY = 0;
    kick();
  };

  const onCardClick = (event: ReactMouseEvent, index: number) => {
    if (drag.current.suppressClick) {
      drag.current.suppressClick = false;
      event.preventDefault();
      return;
    }
    if (index !== active) {
      event.preventDefault();
      moveTo(index, true);
    }
  };

  const current = items[active];
  if (!current) return null;
  const canPrev = circular || active > 0;
  const canNext = circular || active < last;

  return (
    <section className={styles.carousel} aria-roledescription="carrossel" aria-label="Suas coleções">
      <div
        ref={stageRef}
        className={styles.stage}
        onKeyDown={onKeyDown}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={endDrag}
        onPointerCancel={endDrag}
        onPointerLeave={onPointerLeave}
        onClickCapture={(event) => {
          // Clique sintetizado no palco depois de um arrasto (captura do ponteiro).
          if (drag.current.suppressClick && !(event.target instanceof Element && event.target.closest("a"))) {
            drag.current.suppressClick = false;
          }
        }}
      >
        <span className={styles.stageGlow} aria-hidden="true" />
        <span className={styles.stageFloor} aria-hidden="true" />
        <ul className={styles.deck}>
          {items.map((collection, index) => {
            const logoKey = plateLogoKey(collection);
        const logoUrl = logoKey ? logoUrls[logoKey] ?? null : null;
            const isActive = index === active;
            return (
              <li
                key={collection.id}
                ref={(element) => {
                  cardRefs.current[index] = element;
                }}
                className={styles.slide}
                style={initialPoses[index]}
                data-active={isActive || undefined}
                aria-roledescription="fichário"
                aria-label={`${formatCount(index + 1)} de ${formatCount(count)}`}
              >
                <Link
                  ref={(element) => {
                    linkRefs.current[index] = element;
                  }}
                  href={collectionHref(collection.id)}
                  className={styles.slideLink}
                  tabIndex={isActive ? 0 : -1}
                  draggable={false}
                  onClick={(event) => onCardClick(event, index)}
                  aria-label={`${collection.name}, ${collectionSubtitle(collection)}, ${spokenProgress(collection)}${
                    isActive ? "" : ". Trazer para a frente"
                  }`}
                >
                  <BinderCover
                    finish={collection.finish}
                    setName={collection.cardSetName}
                    setCode={plateCode(collection)}
                    logoUrl={logoUrl}
                    fallbackTitle={collection.name}
                    emblem={isPokedexCollection(collection) ? "pokedex" : null}
                    complete={collection.isComplete}
                    size="compact"
                    priority={Math.abs(deltaOf(index, startIndex, count, circular)) <= 2}
                  />
                </Link>
              </li>
            );
          })}
        </ul>
      </div>

      <div className={styles.focusPanel}>
        <Button
          type="button"
          variant="outline"
          className={styles.stepButton}
          onClick={() => shift(-1, false)}
          disabled={!canPrev}
          data-hidden={!canPrev || undefined}
          aria-label="Coleção anterior"
        >
          <ChevronLeft className="h-5 w-5" aria-hidden="true" />
        </Button>

        <div className={styles.focusInfo}>
          <FocusDetails collection={current} compact />
          <div className={styles.focusActions}>
            <Button asChild variant="outline-primary" className="h-10 px-4">
              <Link href={collectionHref(current.id)}>
                Abrir coleção
                <ArrowRight className="h-4 w-4" aria-hidden="true" />
              </Link>
            </Button>
            {count <= DOTS_MAX ? (
              <span className={styles.dots} aria-hidden="true">
                {items.map((collection, index) => (
                  <span key={collection.id} className={styles.dot} data-active={index === active || undefined} />
                ))}
              </span>
            ) : (
              <span className={styles.focusPosition} aria-hidden="true">
                {formatCount(active + 1)} / {formatCount(count)}
              </span>
            )}
          </div>
        </div>

        <Button
          type="button"
          variant="outline"
          className={styles.stepButton}
          onClick={() => shift(1, false)}
          disabled={!canNext}
          data-hidden={!canNext || undefined}
          aria-label="Próxima coleção"
        >
          <ChevronRight className="h-5 w-5" aria-hidden="true" />
        </Button>
      </div>

      <p className="sr-only" aria-live="polite" aria-atomic="true">
        {`${current.name}, ${formatCount(active + 1)} de ${formatCount(count)}`}
      </p>
    </section>
  );
}
