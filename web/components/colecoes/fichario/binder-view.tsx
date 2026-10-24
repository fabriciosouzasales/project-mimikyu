import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { BinderCover } from "@/components/colecoes/colecoes/binder-cover";
import { type BinderHeader, type BinderPage, createBlocker, createBlockerMessage } from "@/lib/colecoes/binder";
import type { BinderFinish } from "@/lib/colecoes/binder-finish";
import type { JoinCandidate } from "@/lib/colecoes/binder-share";
import { collectionHref } from "@/lib/colecoes/colecoes";
import { BinderAssembly } from "./binder-assembly";
import { BinderJoinOrCreate } from "./binder-join";
import { BinderWorkspace } from "./binder-workspace";
import styles from "./binder.module.css";

/**
 * Fichário Digital de uma coleção (P2-B; área de trabalho em
 * P2-B-UX-CORRECTION-01) — composição no servidor; só a área de trabalho e a
 * montagem são Client Components.
 *
 * Três situações:
 *  - fichário existe → área de trabalho em tela cheia do conteúdo (capa,
 *    spreads, ferramentas, Bandeja), sem cabeçalho de página;
 *  - não existe e a coleção é elegível (5223 `can_create`) → montagem;
 *  - não existe e não é elegível → explicação e caminho, sem botão que não
 *    funcionaria (a 5224 revalida tudo de qualquer forma).
 */
export function BinderView({
  collection,
  header,
  initialAnchor,
  initialPages,
  joinCandidates = null,
}: {
  collection: { id: string; name: string; finish: BinderFinish; setName: string | null; setCode: string | null; policy: string };
  header: BinderHeader;
  /** Página pedida na URL; 0 = abrir pela capa. */
  initialAnchor: number;
  initialPages: BinderPage[] | null;
  /** Fichários existentes no mesmo local físico (5230); com algum, usar vem antes de montar. */
  joinCandidates?: JoinCandidate[] | null;
}) {
  const backHref = collectionHref(collection.id);
  const blocker = createBlocker(header);

  if (header.hasBinder && header.columns && header.rows && header.pageCount > 0 && initialPages) {
    return (
      <BinderWorkspace
        variant="page"
        collectionId={collection.id}
        collectionName={collection.name}
        identity={header.identity ?? null}
        columns={header.columns}
        rows={header.rows}
        totalPages={header.pageCount}
        layoutId={header.layoutId}
        filledCount={header.filledCount}
        role={header.role}
        ownerCollectionId={header.ownerCollectionId}
        ownerCollectionName={header.ownerCollectionName}
        participantCount={header.participantCount}
        ownUnplacedCount={header.ownUnplacedCount}
        availableCount={header.availableCount}
        editable={header.editable}
        initialAnchor={initialAnchor}
        initialPages={initialPages}
        backHref={backHref}
      />
    );
  }

  return (
    <div className={styles.root}>
      <div className={styles.top}>
        <Link href={backHref} className={styles.backLink}>
          <ArrowLeft className="h-4 w-4" aria-hidden="true" />
          Voltar à coleção
        </Link>
      </div>

      <div className={styles.titleRow}>
        <h1 className={styles.title}>
          {header.hasBinder ? collection.name : joinCandidates && joinCandidates.length > 0 ? `Fichário de ${collection.name}` : `Montar o fichário de ${collection.name}`}
        </h1>
      </div>

      {header.hasBinder ? (
        header.pageCount === 0 ? (
          <Blocked
            finish={collection.finish}
            setName={collection.setName}
            name={collection.name}
            title="Este fichário está sem páginas"
            body="As páginas foram removidas. O fichário continua existindo e pode ser organizado de novo."
            backHref={backHref}
          />
        ) : (
          <div className="mx-auto max-w-md py-16 text-center" role="alert">
            <p className="font-heading text-xl font-extrabold">Não conseguimos abrir as páginas</p>
            <p className="mt-2 text-sm text-muted-foreground">Nada foi perdido. Recarregue a página em instantes.</p>
          </div>
        )
      ) : joinCandidates && joinCandidates.length > 0 ? (
        <BinderJoinOrCreate
          collectionId={collection.id}
          collectionName={collection.name}
          candidates={joinCandidates}
          createOwn={
            blocker ? (
              <Blocked
                finish={collection.finish}
                setName={collection.setName}
                name={collection.name}
                {...createBlockerMessage(blocker, header.defaultStorageName)}
                backHref={backHref}
              />
            ) : (
              <BinderAssembly collectionId={collection.id} finish={collection.finish} kind={header.kind} />
            )
          }
        />
      ) : blocker ? (
        <Blocked
          finish={collection.finish}
          setName={collection.setName}
          name={collection.name}
          {...createBlockerMessage(blocker, header.defaultStorageName)}
          backHref={backHref}
        />
      ) : (
        <BinderAssembly collectionId={collection.id} finish={collection.finish} kind={header.kind} />
      )}
    </div>
  );
}

function Blocked({
  finish,
  setName,
  name,
  title,
  body,
  backHref,
}: {
  finish: BinderFinish;
  setName: string | null;
  name: string;
  title: string;
  body: string;
  backHref: string;
}) {
  return (
    <section className={styles.blocked} aria-labelledby="fichario-indisponivel">
      <BinderCover finish={finish} setName={setName} setCode={null} logoUrl={null} fallbackTitle={name} complete={false} size="compact" />
      <div>
        <h2 id="fichario-indisponivel" className={styles.blockedTitle}>
          {title}
        </h2>
        <p className={styles.blockedBody}>{body}</p>
        <div className={styles.blockedActions}>
          <Link href={backHref} className="inline-flex h-10 items-center rounded-md border border-border px-5 text-sm font-medium hover:bg-surface-muted">
            Voltar à coleção
          </Link>
        </div>
      </div>
    </section>
  );
}
