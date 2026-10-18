import Link from "next/link";
import { AlertTriangle, Check, Sparkles, Trophy } from "lucide-react";
import { Button } from "@/components/ui/button";
import { CardZoomProvider, CardZoomTrigger } from "@/components/card/card-zoom";
import { PRIORITY_CARD_COUNT, cardFrontUrl, formatCollectorNumber, formatCount } from "@/lib/colecoes/acervo";
import { type PositionFilter, collectionHref } from "@/lib/colecoes/colecoes";
import {
  MASTER_SET_ADD_FROM_ACERVO_ENABLED,
  type MasterSetPosition,
  type MasterSetPositionsPage,
  finishBadge,
  masterSetTotalPages,
  positionStatusText,
} from "@/lib/colecoes/master-set";
import { CardArt } from "../acervo/card-art";
import acervoStyles from "../acervo/acervo.module.css";
import { ManageCopiesButton } from "./collection-manage";
import styles from "./colecoes.module.css";
import { AddFromAcervoButton, OutOfScopeSection } from "./master-set-client";
import msStyles from "./master-set.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const GRID_SIZES = "(max-width: 767px) 50vw, 11rem";

/**
 * Grade do Master Set (MASTER-SET-FRONTEND-PHASE-02), Server Component.
 *
 * Mesma grade, arte, ampliação e etiquetas da coleção de Set padrão; cada item
 * é uma POSIÇÃO (carta + acabamento, ou carta secreta genérica) vinda de
 * 5189/5198 — uma página por vez (`?pagina=`), nunca o Set inteiro. Idioma,
 * contexto de edição e impressão não multiplicam posições (C-187): a grade só
 * mostra o que o banco devolve. O acabamento aparece como uma linha discreta
 * sob o número da carta.
 */
export function MasterSetGallery({
  collectionId,
  collectionName,
  filter,
  page,
  positions,
  outOfScopeCount,
  setCode,
  manageable,
}: {
  collectionId: string;
  collectionName: string;
  filter: PositionFilter;
  page: number;
  positions: MasterSetPositionsPage | null;
  outOfScopeCount: number | null;
  setCode: string | null;
  /** Coleção ativa com gerenciamento ligado: botões de exemplares/adicionar. */
  manageable: boolean;
}) {
  const pages = positions ? masterSetTotalPages(positions.total) : 1;
  const retryHref = pageHref(collectionId, filter, page);

  return (
    <>
      {positions === null ? (
        <ReadError retryHref={retryHref} />
      ) : positions.items.length === 0 ? (
        <MasterEmpty filter={filter} collectionName={collectionName} collectionId={collectionId} />
      ) : (
        <>
          <CardZoomProvider>
            <ul className={acervoStyles.grid} aria-label="Posições do Master Set">
              {positions.items.map((position, index) => (
                <li key={position.key}>
                  <MasterTile
                    collectionId={collectionId}
                    position={position}
                    priority={page === 1 && index < PRIORITY_CARD_COUNT}
                    setCode={setCode}
                    manageable={manageable}
                  />
                </li>
              ))}
            </ul>
          </CardZoomProvider>
          {pages > 1 ? <Pager collectionId={collectionId} filter={filter} page={page} pages={pages} /> : null}
        </>
      )}
      {outOfScopeCount !== null && outOfScopeCount > 0 ? (
        <OutOfScopeSection collectionId={collectionId} total={outOfScopeCount} />
      ) : null}
    </>
  );
}

function MasterTile({
  collectionId,
  position,
  priority,
  setCode,
  manageable,
}: {
  collectionId: string;
  position: MasterSetPosition;
  priority: boolean;
  setCode: string | null;
  manageable: boolean;
}) {
  const number = formatCollectorNumber(position.collectorNumber, position.collectorTotal);
  const caption = setCode ? `${setCode.toUpperCase()} · ${number}` : number;
  const imageUrl = cardFrontUrl(SUPABASE_URL, position.imagePath);
  const finish = finishBadge(position);
  const canAdd =
    MASTER_SET_ADD_FROM_ACERVO_ENABLED && manageable && !position.isSatisfied && position.copiesAvailable > 0;

  return (
    <article
      className={acervoStyles.tile}
      aria-label={`${position.cardName}, ${caption}, ${position.isSecret ? "carta secreta, " : ""}${finish}, ${positionStatusText(position)}`}
    >
      <div className={acervoStyles.artWrap}>
        <CardZoomTrigger id={position.key} imageUrl={imageUrl} name={position.cardName} className={styles.zoomTrigger}>
          <div className={position.isSatisfied ? acervoStyles.art : `${acervoStyles.art} ${styles.missing}`}>
            <CardArt src={imageUrl} alt="" name={position.cardName} caption={caption} priority={priority} sizes={GRID_SIZES} />
            {!position.isSatisfied ? (
              <span
                className={position.copiesAvailable > 0 ? `${styles.missingTag} ${styles.availableTag}` : styles.missingTag}
                aria-hidden="true"
              >
                {position.copiesAvailable > 0 ? "No seu acervo" : "Falta"}
              </span>
            ) : null}
          </div>
        </CardZoomTrigger>
        {position.copiesInCollection > 1 ? (
          <span className={acervoStyles.qty} aria-hidden="true">
            ×{formatCount(position.copiesInCollection)}
          </span>
        ) : null}
        {manageable && setCode && position.copiesInCollection > 0 ? (
          <ManageCopiesButton
            target={{
              query: { kind: "set_card", setCode, collectorNumber: position.collectorNumber },
              cardName: position.cardName,
              caption,
              imageUrl,
            }}
          />
        ) : null}
      </div>
      <div className={acervoStyles.meta}>
        <div className={acervoStyles.name} aria-hidden="true">
          {position.cardName}
        </div>
        <div className={acervoStyles.sub} aria-hidden="true">
          <span>{caption}</span>
          {position.isSatisfied ? (
            <span className={acervoStyles.tag}>
              <Check className="mr-0.5 inline h-3 w-3" />
              Tenho
            </span>
          ) : null}
        </div>
        <div className={msStyles.finishLine} data-secret={position.isSecret || undefined} aria-hidden="true">
          {position.isSecret ? <Sparkles className={msStyles.secretIcon} /> : null}
          <span className={msStyles.finishText}>
            {position.isSecret && position.variantTypeId === null ? `Secreta · ${finish.toLowerCase()}` : finish}
          </span>
        </div>
        {canAdd ? (
          <AddFromAcervoButton
            collectionId={collectionId}
            cardId={position.cardId}
            variantTypeId={position.variantTypeId}
            cardName={position.cardName}
            caption={caption}
            finish={finish}
            imageUrl={imageUrl}
            available={position.copiesAvailable}
          />
        ) : null}
      </div>
    </article>
  );
}

function pageHref(collectionId: string, filter: PositionFilter, page: number): string {
  const base = collectionHref(collectionId, filter);
  if (page <= 1) return base;
  return `${base}${base.includes("?") ? "&" : "?"}pagina=${page}`;
}

function Pager({ collectionId, filter, page, pages }: { collectionId: string; filter: PositionFilter; page: number; pages: number }) {
  const current = Math.min(page, pages);
  return (
    <nav className={acervoStyles.pagination} aria-label="Páginas do Master Set">
      {current > 1 ? (
        <Button asChild variant="outline" className="h-11 min-w-11">
          <Link href={pageHref(collectionId, filter, current - 1)} scroll={false}>
            Anterior
          </Link>
        </Button>
      ) : null}
      <span aria-current="page">
        Página {formatCount(current)} de {formatCount(pages)}
      </span>
      {current < pages ? (
        <Button asChild variant="outline" className="h-11 min-w-11">
          <Link href={pageHref(collectionId, filter, current + 1)} scroll={false}>
            Próxima
          </Link>
        </Button>
      ) : null}
    </nav>
  );
}

function MasterEmpty({ filter, collectionName, collectionId }: { filter: PositionFilter; collectionName: string; collectionId: string }) {
  if (filter === "faltam") {
    return (
      <section className={acervoStyles.state} aria-labelledby="master-completo">
        <div className={acervoStyles.stateIcon} aria-hidden="true">
          <Trophy className="h-6 w-6" />
        </div>
        <h2 id="master-completo" className={acervoStyles.stateTitle}>
          Master Set completo
        </h2>
        <p className={acervoStyles.stateText}>
          {collectionName} tem todas as posições do objetivo — cada carta em cada acabamento escolhido.
        </p>
      </section>
    );
  }
  if (filter === "tenho") {
    return (
      <section className={acervoStyles.state} aria-labelledby="master-vazio">
        <h2 id="master-vazio" className={acervoStyles.stateTitle}>
          Nenhuma posição preenchida ainda
        </h2>
        <p className={acervoStyles.stateText}>
          As cartas que entrarem nesta coleção no acabamento certo aparecem aqui. Veja em “Faltam” o que ainda precisa.
        </p>
        <Button asChild variant="outline" className={acervoStyles.stateAction}>
          <Link href={collectionHref(collectionId, "faltam")}>Ver o que falta</Link>
        </Button>
      </section>
    );
  }
  return (
    <section className={acervoStyles.state} aria-labelledby="master-sem-posicoes">
      <h2 id="master-sem-posicoes" className={acervoStyles.stateTitle}>
        Esta página não tem posições
      </h2>
      <p className={acervoStyles.stateText}>O objetivo pode ter mudado. Volte ao início da coleção.</p>
      <Button asChild variant="outline" className={acervoStyles.stateAction}>
        <Link href={collectionHref(collectionId)}>Ver a coleção</Link>
      </Button>
    </section>
  );
}

function ReadError({ retryHref }: { retryHref: string }) {
  return (
    <section className={acervoStyles.state} role="alert" aria-labelledby="master-erro">
      <div className={`${acervoStyles.stateIcon} ${acervoStyles.stateIconDanger}`} aria-hidden="true">
        <AlertTriangle className="h-6 w-6" />
      </div>
      <h2 id="master-erro" className={acervoStyles.stateTitle}>
        Não conseguimos carregar as posições
      </h2>
      <p className={acervoStyles.stateText}>Nada foi perdido. Tente novamente em instantes.</p>
      <Button asChild className={acervoStyles.stateAction}>
        <Link href={retryHref} prefetch={false}>
          Tentar novamente
        </Link>
      </Button>
    </section>
  );
}
