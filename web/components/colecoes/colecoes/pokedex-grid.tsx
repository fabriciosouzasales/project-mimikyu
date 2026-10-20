"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState, useTransition } from "react";
import { Check, Loader2, Plus, Trophy } from "lucide-react";
import { loadMorePokedexPositions } from "@/app/colecoes/colecoes/actions";
import { CardZoomProvider, CardZoomTrigger } from "@/components/card/card-zoom";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { SpeciesArtwork } from "@/components/pokedex/species-artwork";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { cardFrontUrl, formatCount } from "@/lib/colecoes/acervo";
import {
  type PokedexFilter,
  type PokedexPosition,
  appendPositions,
  formatDex,
  nextOffset,
  stateDescription,
  stateTag,
} from "@/lib/colecoes/pokedex";
import { speciesArtworkUrl } from "@/lib/pokedex/artwork";
import { CardArt } from "../acervo/card-art";
import { POKEDEX_DIALOG_CLOSED_EVENT } from "./pokedex-bulk-link";
import { PokedexPositionPanel } from "./pokedex-position-panel";
import acervoStyles from "../acervo/acervo.module.css";
import styles from "./pokedex.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const GRID_SIZES = "(max-width: 767px) 50vw, 11rem";
/** Mesmo teto de prioridade da grade da Pokédex: só o topo visível carrega cedo. */
const PRIORITY_COUNT = 12;

/**
 * Grade da coleção Pokédex (PKX-02). A primeira página chega pronta do
 * servidor (5204); "Mostrar mais" busca a próxima página da MESMA leitura
 * (mesmo filtro, ordem nacional) e acrescenta sem repetir — nunca a Pokédex
 * inteira de uma vez. Trocar de filtro é navegação (URL), então a grade
 * recomeça do servidor.
 *
 * Conquistada → a carta representante (ampliável, mesmo preview do
 * Catálogo). Não conquistada → a arte oficial da espécie numa moldura de
 * carta, mais apagada quanto mais longe ela está: "No seu acervo" (cor cheia),
 * "Em outra coleção" e "Falta".
 *
 * Vínculo (PKX-03, só com `linkable`): tocar um Pokémon abre o painel da
 * posição — cartas vinculadas, representante, adicionar da mesma espécie ou
 * como exceção confirmada. Sem `linkable` (flag desligada ou coleção
 * arquivada) a grade fica como na PKX-02: carta ampliável ou ficha da Pokédex.
 */
export function PokedexGrid({
  collectionId,
  filter,
  generation,
  initial,
  total,
  label,
  linkable = false,
  focusNumber = null,
}: {
  collectionId: string;
  filter: PokedexFilter;
  generation: string | null;
  initial: PokedexPosition[];
  total: number;
  label: string;
  /** Painel de vínculo disponível (flag PKX + coleção ativa). */
  linkable?: boolean;
  /** Número nacional para levar à vista e destacar (busca, UX-04). */
  focusNumber?: number | null;
}) {
  const [items, setItems] = useState(initial);
  const [count, setCount] = useState(total);
  const [error, setError] = useState(false);
  const [pending, startTransition] = useTransition();
  const [announce, setAnnounce] = useState("");
  const firstNewRef = useRef<string | null>(null);
  // Instantâneo da posição aberta: o painel continua aberto mesmo que, depois de um
  // vínculo, ela saia do filtro atual (ex.: "Faltam") com o refresh da página.
  const [openPosition, setOpenPosition] = useState<PokedexPosition | null>(null);

  // Momento de conquista (UX-05): compara o estado anterior de cada Pokémon com a
  // página nova (refresh depois de um vínculo). Quem passou a "conquistado" é
  // celebrado quando nenhum painel está aberto — senão, ao fechar o painel.
  const knownStateRef = useRef(new Map(initial.map((item) => [item.positionId, item.state])));
  const pendingCelebrationRef = useRef<PokedexPosition[]>([]);
  const [celebrating, setCelebrating] = useState<ReadonlySet<string>>(new Set());

  const flushCelebration = useCallback(function flush(attempt: number = 0) {
    const conquered = pendingCelebrationRef.current;
    if (conquered.length === 0) return;
    if (document.querySelector("[data-pkx-dialog]")) {
      // Painel aberto (ou ainda saindo da tela): tenta de novo por ~3 s; se o painel
      // continuar aberto, o próprio fechamento chama de novo.
      if (attempt < 15) window.setTimeout(() => flush(attempt + 1), 200);
      return;
    }
    pendingCelebrationRef.current = [];
    setCelebrating(new Set(conquered.map((item) => item.positionId)));
    setAnnounce(
      conquered.length === 1
        ? `${conquered[0]?.speciesName ?? "Pokémon"} conquistado!`
        : `${formatCount(conquered.length)} Pokémon conquistados!`,
    );
    window.setTimeout(() => setCelebrating(new Set()), 2600);
  }, []);

  // Nova navegação (filtro/geração/refresh): recomeça da página do servidor.
  useEffect(() => {
    const known = knownStateRef.current;
    const conquered = initial.filter((item) => item.state === "OWNED" && known.has(item.positionId) && known.get(item.positionId) !== "OWNED");
    for (const item of initial) known.set(item.positionId, item.state);
    if (conquered.length > 0) pendingCelebrationRef.current = [...pendingCelebrationRef.current, ...conquered];
    setItems(initial);
    setCount(total);
    setError(false);
    // Depois do commit do React: só celebra se nenhum painel estiver aberto.
    const frame = window.requestAnimationFrame(() => flushCelebration());
    return () => window.cancelAnimationFrame(frame);
  }, [initial, total, flushCelebration]);

  useEffect(() => {
    const onClosed = () => flushCelebration();
    window.addEventListener(POKEDEX_DIALOG_CLOSED_EVENT, onClosed);
    return () => window.removeEventListener(POKEDEX_DIALOG_CLOSED_EVENT, onClosed);
  }, [flushCelebration]);

  // Foco acompanha a carga: vai para o primeiro card novo (teclado e leitor de tela).
  useEffect(() => {
    const id = firstNewRef.current;
    if (!id) return;
    firstNewRef.current = null;
    document.getElementById(tileId(id))?.focus({ preventScroll: true });
  }, [items]);

  // Busca (UX-04): leva o Pokémon procurado à vista, dá o foco ao card e o
  // destaca por um instante. Uma vez por número/navegação.
  const [highlighted, setHighlighted] = useState<string | null>(null);
  const handledFocusRef = useRef<string | null>(null);
  useEffect(() => {
    if (focusNumber === null) return;
    const target = items.find((item) => item.number === focusNumber);
    const key = `${focusNumber}:${initial[0]?.positionId ?? ""}`;
    if (!target || handledFocusRef.current === key) return;
    handledFocusRef.current = key;
    const element = document.getElementById(tileId(target.positionId));
    if (!element) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    element.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "center" });
    element.focus({ preventScroll: true });
    setHighlighted(target.positionId);
    setAnnounce(`#${formatDex(target.number)} ${target.speciesName}.`);
    const timer = window.setTimeout(() => setHighlighted(null), 2400);
    return () => window.clearTimeout(timer);
  }, [focusNumber, items, initial]);

  const offset = nextOffset(items.length, count);

  const loadMore = () => {
    if (offset === null || pending) return;
    setError(false);
    startTransition(async () => {
      const result = await loadMorePokedexPositions({ collectionId, filter, generation, offset }).catch(
        () => ({ ok: false, reason: "unavailable" }) as const,
      );
      if (!result.ok) {
        setError(true);
        return;
      }
      const merged = appendPositions(items, result.page.items);
      const added = merged.length - items.length;
      firstNewRef.current = result.page.items.find((item) => !items.some((current) => current.positionId === item.positionId))?.positionId ?? null;
      setItems(merged);
      // O total pode ter mudado entre as leituras (outra aba): vale o mais recente.
      setCount(result.page.total || merged.length);
      setAnnounce(added > 0 ? `${formatCount(added)} Pokémon a mais carregados.` : "Não há mais Pokémon para mostrar.");
    });
  };

  return (
    <CardZoomProvider>
      <ul className={acervoStyles.grid} aria-label={label}>
        {items.map((position, index) => (
          <li
            key={position.positionId}
            id={tileId(position.positionId)}
            tabIndex={-1}
            className={`outline-none ${styles.tileItem}`}
            data-highlight={highlighted === position.positionId || undefined}
          >
            <PokedexTile
              position={position}
              priority={index < PRIORITY_COUNT}
              onOpen={linkable ? () => setOpenPosition(position) : null}
              celebrating={celebrating.has(position.positionId)}
            />
          </li>
        ))}
      </ul>
      <p className="sr-only" role="status" aria-live="polite">
        {announce}
      </p>
      {offset !== null || error ? (
        <div className={styles.more}>
          <span>
            Mostrando {formatCount(items.length)} de {formatCount(count)}
          </span>
          {error ? (
            <InlineFeedback tone="error">Não conseguimos carregar mais Pokémon agora. Nada foi perdido — tente de novo.</InlineFeedback>
          ) : null}
          <Button variant="outline" className="min-h-11" onClick={loadMore} disabled={pending || offset === null} aria-busy={pending}>
            {pending ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden="true" /> : null}
            {pending ? "Carregando…" : error ? "Tentar novamente" : "Mostrar mais Pokémon"}
          </Button>
        </div>
      ) : null}
      {openPosition ? (
        <PokedexPositionPanel
          collectionId={collectionId}
          position={openPosition}
          onClose={() => {
            setOpenPosition(null);
            // O painel sai do DOM no próximo quadro; aí a conquista aparece na grade.
            window.requestAnimationFrame(() => window.requestAnimationFrame(() => flushCelebration()));
          }}
        />
      ) : null}
    </CardZoomProvider>
  );
}

function tileId(positionId: string): string {
  return `pokedex-pos-${positionId}`;
}

function PokedexTile({
  position,
  priority,
  onOpen,
  celebrating = false,
}: {
  position: PokedexPosition;
  priority: boolean;
  /** Abre o painel da posição (PKX-03); `null` = comportamento da PKX-02. */
  onOpen: (() => void) | null;
  /** Acabou de ser conquistado (UX-05): revelação da carta + selo. */
  celebrating?: boolean;
}) {
  const dex = `#${formatDex(position.number)}`;
  const description = stateDescription(position);
  const representative = position.representative;
  const cardUrl = representative ? cardFrontUrl(SUPABASE_URL, representative.imagePath) : null;
  const artUrl = speciesArtworkUrl(position.artworkPath);
  const showCard = position.state === "OWNED" && representative !== null && cardUrl !== null;
  const caption = representative
    ? [representative.setCode?.toUpperCase(), representative.collectorNumber].filter(Boolean).join(" · ")
    : "";

  return (
    <article
      className={acervoStyles.tile}
      data-conquered={celebrating || undefined}
      aria-label={`${dex} ${position.speciesName}, ${description}`}
    >
      <div className={acervoStyles.artWrap}>
        {onOpen ? (
          <button
            type="button"
            className={`${styles.tileLink} ${styles.tileButton}`}
            onClick={onOpen}
            aria-haspopup="dialog"
            aria-label={`${dex} ${position.speciesName}, ${description}. Abrir para ${position.state === "OWNED" ? "ver e gerenciar as cartas" : "adicionar uma carta"}`}
          >
            {showCard && representative ? (
              <div className={styles.card}>
                <CardArt src={cardUrl} alt="" name={representative.cardName} caption={caption || dex} priority={priority} sizes={GRID_SIZES} />
                <span className={styles.dexBadge} aria-hidden="true">
                  {formatDex(position.number)}
                </span>
              </div>
            ) : (
              <SpeciesSlot position={position} artUrl={artUrl} priority={priority} addable />
            )}
          </button>
        ) : showCard && representative ? (
          <CardZoomTrigger id={position.positionId} imageUrl={cardUrl} name={representative.cardName} className={styles.tileLink}>
            <div className={styles.card}>
              <CardArt src={cardUrl} alt="" name={representative.cardName} caption={caption || dex} priority={priority} sizes={GRID_SIZES} />
              <span className={styles.dexBadge} aria-hidden="true">
                {formatDex(position.number)}
              </span>
            </div>
          </CardZoomTrigger>
        ) : (
          <Link href={`/pokedex/${position.number}`} className={styles.tileLink} prefetch={false}>
            <SpeciesSlot position={position} artUrl={artUrl} priority={priority} addable={false} />
          </Link>
        )}
        {celebrating ? (
          <span className={styles.conquerBadge} aria-hidden="true">
            <Trophy className="h-3.5 w-3.5" strokeWidth={2.5} />
            Conquistado!
          </span>
        ) : null}
        {position.copiesInCollection > 1 ? (
          <span className={`${acervoStyles.qty} ${styles.qtyFooter}`} aria-hidden="true">
            ×{formatCount(position.copiesInCollection)}
          </span>
        ) : null}
      </div>
      {/* UX-01 (ajuste do proprietário): o número nacional vive só dentro do card, como na
          Pokédex; abaixo, só o nome. O nome da carta conquistada continua no zoom, no
          painel e no rótulo acessível. */}
      <div className={acervoStyles.meta} aria-hidden="true">
        <div className={acervoStyles.name}>{position.speciesName}</div>
      </div>
    </article>
  );
}

/**
 * Moldura de carta com a arte oficial da espécie (posição sem carta representante).
 *
 * UX-01: o número nacional fica dentro do card, em contorno, no mesmo padrão da
 * grade da Pokédex (species-grid). Etiqueta
 * visível só onde informa algo acionável ou incomum — "No seu acervo" e "Em outra
 * coleção"; "Falta" é o estado padrão, comunicado pela arte apagada e, para leitor
 * de tela, pela descrição completa do card (`stateDescription`).
 */
function SpeciesSlot({
  position,
  artUrl,
  priority,
  addable,
}: {
  position: PokedexPosition;
  artUrl: string | null;
  priority: boolean;
  addable: boolean;
}) {
  const tagged = position.state === "AVAILABLE" || position.state === "ELSEWHERE";
  return (
    <div className={styles.slot} data-state={position.state}>
      <span className={styles.dexNumber} aria-hidden="true">
        {formatDex(position.number)}
      </span>
      <span className={styles.slotArt}>
        {artUrl ? (
          <SpeciesArtwork src={artUrl} priority={priority} />
        ) : (
          <Pokeball className="h-1/3 w-1/3 text-foreground/[0.08]" strokeWidth={1.25} aria-hidden="true" />
        )}
      </span>
      {position.state === "OWNED" ? (
        <span className={styles.owned} aria-hidden="true">
          <Check className="h-3.5 w-3.5" strokeWidth={3} />
        </span>
      ) : tagged ? (
        <span className={styles.stateTag} data-state={position.state} aria-hidden="true">
          {stateTag(position.state)}
        </span>
      ) : null}
      {addable && position.state !== "OWNED" ? (
        <span className={styles.addHint} data-state={position.state} aria-hidden="true">
          <Plus className="h-4 w-4" strokeWidth={2.5} />
        </span>
      ) : null}
    </div>
  );
}
