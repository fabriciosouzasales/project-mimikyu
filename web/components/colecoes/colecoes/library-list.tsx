import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { formatCount } from "@/lib/colecoes/acervo";
import { plateCode, plateLogoKey } from "@/lib/colecoes/free-collection";
import { collectionHref, collectionProgressView, collectionSubtitle } from "@/lib/colecoes/colecoes";
import type { CollectionSummary } from "@/lib/colecoes/colecoes-queries";
import { BinderCover } from "./binder-cover";
import styles from "./library-modes.module.css";

/**
 * Minhas coleções — modo Lista (COLLECTION LIBRARY VIEW MODES-01).
 *
 * Recuperação nativa da linha aprovada no spike `collection-list-view`: miniatura
 * do fichário (a mesma capa do modo Cards, em tamanho compacto — cor e identidade
 * do Set), nome, Set/tipo, progresso fino e o número de cartas reunidas. A linha
 * inteira é o link da coleção. Não é tabela administrativa: sem cabeçalho de
 * colunas, sem ações por linha, tipografia contida.
 *
 * Sem estado: renderizado pelo seletor de modos com os mesmos dados da página.
 */
export function LibraryList({
  items,
  logoUrls,
}: {
  items: readonly CollectionSummary[];
  logoUrls: Readonly<Record<string, string>>;
}) {
  return (
    <ul className={styles.list} aria-label="Suas coleções">
      {items.map((collection) => (
        <li key={collection.id}>
          <LibraryRow collection={collection} logoUrls={logoUrls} />
        </li>
      ))}
    </ul>
  );
}

/** Uma linha da Lista (também usada pela Lista reordenável). */
export function LibraryRow({
  collection,
  logoUrls,
}: {
  collection: CollectionSummary;
  logoUrls: Readonly<Record<string, string>>;
}) {
  const progress = collectionProgressView(collection);
  const subtitle = collectionSubtitle(collection);
  const logoKey = plateLogoKey(collection);
  const logoUrl = logoKey ? logoUrls[logoKey] ?? null : null;
  const copies = formatCount(collection.copiesCount);
  const copiesText = `${copies} ${collection.copiesCount === 1 ? "carta" : "cartas"}`;
  const spoken =
    progress.kind === "goal"
      ? `${progress.label}${progress.complete ? ", completa" : `, ${progress.percentText}`}`
      : copiesText;
  return (
    <Link
      href={collectionHref(collection.id)}
      className={styles.row}
      aria-label={`${collection.name}, ${subtitle}, ${spoken}`}
    >
      <span className={styles.rowCover} aria-hidden="true">
        <BinderCover
          finish={collection.finish}
          setName={collection.cardSetName}
          setCode={plateCode(collection)}
          logoUrl={logoUrl}
          fallbackTitle={collection.name}
          complete={collection.isComplete}
          size="compact"
        />
      </span>
      <span className={styles.rowIdentity} aria-hidden="true">
        <span className={styles.rowName}>{collection.name}</span>
        <span className={styles.rowKind}>{subtitle}</span>
      </span>
      <span className={styles.rowProgress} aria-hidden="true">
        {progress.kind === "goal" ? (
          <>
            <span className={styles.track}>
              <span
                className={progress.complete ? `${styles.fill} ${styles.fillComplete}` : styles.fill}
                style={{ width: `${progress.barPercent}%` }}
              />
            </span>
            <span className={styles.rowCount}>
              <strong>{progress.label}</strong>
              <span className={progress.complete ? styles.rowDone : styles.rowPercent}>
                {progress.complete ? "completa" : progress.percentText}
              </span>
            </span>
          </>
        ) : (
          <span className={styles.rowFree}>Sem meta de Set</span>
        )}
      </span>
      <span className={styles.rowCopies} aria-hidden="true">
        {copiesText}
      </span>
      <ChevronRight className={styles.rowChevron} aria-hidden="true" />
    </Link>
  );
}
