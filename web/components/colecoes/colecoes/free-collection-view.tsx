import Link from "next/link";
import { BinderCoverLink, BinderEntry } from "@/components/colecoes/fichario/binder-entry";
import { type BinderHeader, binderEntryVisible } from "@/lib/colecoes/binder";
import type { ReactNode } from "react";
import { AlertTriangle, ArrowLeft, Layers, ShieldCheck, Sparkles } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  PRIORITY_CARD_COUNT,
  cardFrontUrl,
  formatCollectorNumber,
  formatCount,
  pluralize,
  variantTag,
} from "@/lib/colecoes/acervo";
import type { AcervoItem, AcervoItemsPage } from "@/lib/colecoes/acervo-queries";
import { COLECOES_PATH } from "@/lib/colecoes/colecoes";
import type { CollectionSummary } from "@/lib/colecoes/colecoes-queries";
import { FREE_COVER_CODE_ENABLED, FREE_COVER_UPLOAD_ENABLED, distinctSetCount, freeCollectionHref, freeHeroCards, freeTotalPages } from "@/lib/colecoes/free-collection";
import { CardZoomProvider, CardZoomTrigger } from "@/components/card/card-zoom";
import { CardArt } from "../acervo/card-art";
import acervoStyles from "../acervo/acervo.module.css";
import { BinderCover } from "./binder-cover";
import { CollectionHeroBackdrop, CollectionHeroFan } from "./collection-hero-fan";
import heroStyles from "./collection-hero.module.css";
import { CollectionTitle } from "./collection-title";
import freeStyles from "./free-collection.module.css";
import { FreePickerBarButton, FreePickerButton, FreePickerProvider } from "./free-link-picker";
import { COLLECTION_MANAGE_ENABLED } from "@/lib/colecoes/collection-manage";
import { CollectionAddLauncher } from "./collection-add";
import type { RegisterMode } from "@/lib/colecoes/collection-add";
import { CollectionManageProvider, CollectionSettingsButton, ManageCopiesButton } from "./collection-manage";
import { ReactivateCollectionButton, ReactivatedStatus } from "./collection-lifecycle";
import manageStyles from "./collection-manage.module.css";
import styles from "./colecoes.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const GRID_SIZES = "(max-width: 767px) 50vw, 11rem";

/**
 * Coleção livre (Server Component) — FREE-COLLECTION-FRONTEND-COMPLETION-01.
 *
 * Mesma página da coleção de Set (hero com fichário 3D, nome editável, as seis
 * cores, leque de cartas reais, galeria na moldura da Biblioteca), sem nada
 * que pertença a um Set: nem progresso, nem faltantes, nem total esperado,
 * nem logo ou secretas. O que existe é posse: quantas cartas a coleção reúne,
 * quantas diferentes e — quando a página contém todas — de quantos Sets.
 *
 * O leque mostra as cartas mais recentes da coleção (todas do colecionador).
 * Vazia, a coleção não parece quebrada: convida a escolher as primeiras
 * cartas do acervo, com a mesma ação.
 *
 * Leituras: R1 (resumo) e 5159 com `p_collection_id` (cartas, paginadas).
 *
 * Gerenciar (COLLECTION-MANAGEMENT-RECOVERY-01, só coleção ativa): "Ajustes"
 * no topo e o botão de exemplares em cada carta (tirar um exemplar, 5047).
 * Tirar não cria progresso: só a galeria e as contagens mudam.
 */
export function FreeCollectionView({
  collection,
  items,
  page,
  available,
  openPicker,
  coverLogoUrl = null,
  userId = null,
  binder = null,
  registerMode = null,
}: {
  collection: CollectionSummary;
  /** Cartas da coleção (5159); `null` = leitura falhou. */
  items: AcervoItemsPage | null;
  page: number;
  /** Cartas diferentes livres no acervo; `null` = leitura falhou. */
  available: number | null;
  /** Abrir o seletor ao chegar (`?adicionar=1`, vindo da criação). */
  openPicker: boolean;
  /** URL assinada da capa enviada (proposta 5176–5178); `null` = placa tipográfica. */
  coverLogoUrl?: string | null;
  /** Dono da sessão — pasta do envio da capa; `null` = envio indisponível. */
  userId?: string | null;
  /** Cabeçalho do Fichário Digital (5223); `null` = sem leitura. */
  binder?: BinderHeader | null;
  /** V1-06: `?cadastrar=` — abre o cadastro de cartas novas ao chegar. */
  registerMode?: RegisterMode | null;
}) {
  const active = collection.lifecycleStatus === "ACTIVE";
  const copies = collection.copiesCount;
  const distinct = items?.totalGroups ?? null;
  const sets = items ? distinctSetCount(items.items, items.totalGroups) : null;
  // Leque: só a partir da primeira página (as mais recentes).
  const fan = page === 1 && items ? freeHeroCards(items.items, 5) : [];
  const selection = { cards: fan, secret: 0 };
  const empty = items !== null && items.totalGroups === 0;
  const pages = items ? freeTotalPages(items.totalGroups) : 1;

  const canManage = COLLECTION_MANAGE_ENABLED && active;
  const launcher = (showCount: boolean) => (active ? <FreePickerButton available={available} showCount={showCount} /> : null);
  const addTarget = { collectionId: collection.id, collectionName: collection.name, kind: "free" as const, cardSet: null };

  const cover = (
    <BinderCover
      finish={collection.finish}
      setName={null}
      setCode={collection.coverCode}
      logoUrl={coverLogoUrl}
      fallbackTitle={collection.name}
      complete={false}
      size="compact"
      priority
    />
  );

  const pageContent = (
    <div className={acervoStyles.root}>
      <header className={`${acervoStyles.hero} ${heroStyles.hero}`} data-has-fan={fan.length > 0 || undefined}>
        <div className={acervoStyles.stageGlow} aria-hidden="true" />
        <CollectionHeroBackdrop selection={selection} />
        <div className={manageStyles.heroBar}>
          <Link href={COLECOES_PATH} className={styles.backLink}>
            <ArrowLeft className="h-4 w-4" aria-hidden="true" />
            Minhas coleções
          </Link>
          {canManage ? (
            <div className={manageStyles.heroBarActions}>
              <ReactivatedStatus collectionId={collection.id} />
              <CollectionSettingsButton
                collectionId={collection.id}
                collectionName={collection.name}
                kind="free"
                identity={{
                  name: collection.name,
                  finish: collection.finish,
                  finishEditable: collection.finishEditable,
                  coverCode: FREE_COVER_CODE_ENABLED ? collection.coverCode : undefined,
                  hasCoverImage: FREE_COVER_UPLOAD_ENABLED ? collection.coverLogoPath !== null : undefined,
                  userId: FREE_COVER_UPLOAD_ENABLED ? userId : null,
                }}
              />
            </div>
          ) : !active ? (
            <ReactivateCollectionButton collectionId={collection.id} collectionName={collection.name} />
          ) : null}
        </div>
        <div className={heroStyles.stage}>
          <div className={heroStyles.text}>
            <div className={heroStyles.identity}>
              <div className={heroStyles.identityCover}>
                <BinderCoverLink collectionId={collection.id} ready={Boolean(binder?.hasBinder && binder.pageCount > 0)} available={binderEntryVisible(binder)}>{cover}</BinderCoverLink>
              </div>
              <div className={heroStyles.identityText}>
                <div className={heroStyles.title}>
                  <CollectionTitle name={collection.name} archived={!active} />
                </div>
                <p className={heroStyles.setLine}>
                  <span className={freeStyles.kindLine}>
                    <Sparkles className={freeStyles.kindMark} aria-hidden="true" />
                    <strong>Coleção livre</strong>
                  </span>
                  <span>
                    Organizada do seu jeito
                  </span>
                </p>
              </div>
            </div>

            <section className={freeStyles.summary} aria-label="Resumo da coleção">
              <div className={styles.progressFigure}>
                <span className={heroStyles.progressBig}>{formatCount(copies)}</span>
                <span className={styles.progressOf}>{copies === 1 ? "carta na coleção" : "cartas na coleção"}</span>
              </div>
              {copies > 0 && distinct !== null ? (
                <p className={freeStyles.summaryFacts}>
                  <span>
                    <strong>{formatCount(distinct)}</strong> {distinct === 1 ? "diferente" : "diferentes"}
                  </span>
                  {sets !== null ? (
                    <span>
                      de <strong>{formatCount(sets)}</strong> {sets === 1 ? "Set" : "Sets"}
                    </span>
                  ) : null}
                </p>
              ) : (
                <p className={freeStyles.summaryNote}>Sem meta e sem lista fixa — cartas de qualquer Set, escolhidas por você.</p>
              )}
            </section>

            <BinderEntry collectionId={collection.id} collectionName={collection.name} coverCode={collection.coverCode} finish={collection.finish} binder={binder} />
          </div>

          <CollectionHeroFan selection={selection} label="Cartas mais recentes da coleção" />
        </div>
      </header>


      <section className={heroStyles.gallery} aria-labelledby="colecao-cartas">
        <div className={heroStyles.galleryHead}>
          <div className={heroStyles.galleryHeadText}>
            <h2 id="colecao-cartas" className={heroStyles.galleryTitle}>
              Cartas da coleção
            </h2>
            {items !== null && !empty ? (
              <p className={heroStyles.galleryMeta}>
                {pluralize(items.totalGroups, "carta diferente", "cartas diferentes")} · as mais recentes primeiro
              </p>
            ) : null}
          </div>
          {!empty && items !== null ? (
            // Mesmo padrão da coleção de Set: sempre visível; desabilitado sem carta disponível.
            <div className={heroStyles.galleryTools}>
              <FreePickerBarButton available={active ? available : 0} />
              {canManage ? <CollectionAddLauncher target={addTarget} autoOpen={registerMode} /> : null}
            </div>
          ) : null}
        </div>

        {items === null ? (
          <ReadError retryHref={freeCollectionHref(collection.id, { page })} />
        ) : empty ? (
          <FreeEmpty
            available={available}
            active={active}
            launcher={launcher(false)}
            register={canManage ? <CollectionAddLauncher target={addTarget} layout="empty" autoOpen={registerMode} /> : null}
          />
        ) : items.items.length === 0 ? (
          <PastEnd href={freeCollectionHref(collection.id)} />
        ) : (
          <>
            {/* Clicar na carta amplia — mesmo preview e mesmo morph do Catálogo Editorial. */}
            <CardZoomProvider>
              <ul className={acervoStyles.grid} aria-label="Cartas da coleção">
                {items.items.map((item, index) => (
                  <li key={`${item.cardVariantId}.${item.languageCode}`}>
                    <FreeTile item={item} priority={page === 1 && index < PRIORITY_CARD_COUNT} manageable={canManage} />
                  </li>
                ))}
              </ul>
            </CardZoomProvider>
            {pages > 1 ? <Pagination collectionId={collection.id} page={page} pages={pages} /> : null}
          </>
        )}
      </section>
    </div>
  );

  return active ? (
    <FreePickerProvider collectionId={collection.id} collectionName={collection.name} autoOpen={openPicker}>
      {canManage ? (
        <CollectionManageProvider collectionId={collection.id} collectionName={collection.name} kind="free">
          {pageContent}
        </CollectionManageProvider>
      ) : (
        pageContent
      )}
    </FreePickerProvider>
  ) : (
    pageContent
  );
}

function FreeTile({ item, priority, manageable }: { item: AcervoItem; priority: boolean; manageable: boolean }) {
  const number = formatCollectorNumber(item.collectorNumber, item.collectorTotal);
  const caption = `${item.cardSetCode.toUpperCase()} · ${number}`;
  const tag = variantTag(item.isDefaultVariant, item.variantLabel);
  const copies = item.copiesCount;
  const imageUrl = cardFrontUrl(SUPABASE_URL, item.imagePath);
  const spoken = [item.cardName, caption, tag, item.languageName, pluralize(copies, "exemplar nesta coleção", "exemplares nesta coleção")]
    .filter(Boolean)
    .join(", ");
  return (
    <article className={`${acervoStyles.tile} ${freeStyles.tileStatic}`} aria-label={spoken}>
      <div className={copies > 1 ? `${acervoStyles.artWrap} ${acervoStyles.stack}` : acervoStyles.artWrap}>
        <CardZoomTrigger
          id={`${item.cardVariantId}.${item.languageCode}`}
          imageUrl={imageUrl}
          name={item.cardName}
          className={styles.zoomTrigger}
        >
          <div className={acervoStyles.art}>
            <CardArt src={imageUrl} alt="" name={item.cardName} caption={caption} priority={priority} sizes={GRID_SIZES} />
          </div>
        </CardZoomTrigger>
        {copies > 1 ? (
          <span className={acervoStyles.qty} aria-hidden="true">
            ×{formatCount(copies)}
          </span>
        ) : null}
        {manageable ? (
          <ManageCopiesButton
            target={{
              query: { kind: "group", cardVariantId: item.cardVariantId, languageCode: item.languageCode },
              cardName: item.cardName,
              caption: [caption, tag, item.languageName].filter(Boolean).join(" · "),
              imageUrl,
            }}
          />
        ) : null}
      </div>
      <div className={acervoStyles.meta} aria-hidden="true">
        <div className={acervoStyles.name}>{item.cardName}</div>
        <div className={acervoStyles.sub}>
          <span>{caption}</span>
          {tag ? <span className={acervoStyles.tag}>{tag}</span> : null}
          <span className={acervoStyles.tag}>{item.languageCode}</span>
        </div>
      </div>
    </article>
  );
}

function FreeEmpty({
  available,
  active,
  launcher,
  register,
}: {
  available: number | null;
  active: boolean;
  launcher: ReactNode;
  /** V1-06: cadastrar cartas novas direto na coleção. */
  register: ReactNode;
}) {
  const promises = [
    { icon: Layers, title: "Cartas de qualquer Set", text: "Junte numa coleção só as cartas que contam uma história para você." },
    { icon: Sparkles, title: "Você escolhe cada exemplar", text: "Veja versão e idioma e escolha exatamente quais cartas físicas entram." },
    { icon: ShieldCheck, title: "Nada sai do lugar", text: "As cartas continuam no seu acervo; nenhuma é tirada de outra coleção." },
  ];
  const noneFree = available === 0;
  return (
    <section className={acervoStyles.emptyStage} aria-labelledby="colecao-livre-vazia">
      <div className={acervoStyles.binderPage} aria-hidden="true">
        {Array.from({ length: 9 }, (_, index) => (
          <span key={index} className={index === 4 ? `${acervoStyles.socket} ${acervoStyles.socketLit}` : acervoStyles.socket} />
        ))}
      </div>
      <div className={acervoStyles.emptyCopy}>
        <h2 id="colecao-livre-vazia" className={acervoStyles.emptyTitle}>
          Escolha as primeiras cartas
        </h2>
        <p className={acervoStyles.emptyText}>
          {!active
            ? "Esta coleção está arquivada. Reative-a para voltar a reunir cartas."
            : noneFree
              ? "No momento, todas as cartas do seu acervo já estão em alguma coleção. Cadastre cartas novas — elas entram no acervo e já nesta coleção."
              : available !== null
                ? `Você tem ${pluralize(available, "carta disponível", "cartas disponíveis")} no acervo. Escolha as que fazem parte desta coleção.`
                : "Escolha no seu acervo as cartas que fazem parte desta coleção."}
        </p>
        <ul className={acervoStyles.promiseList}>
          {promises.map(({ icon: Icon, title, text }) => (
            <li key={title} className={acervoStyles.promise}>
              <span className={acervoStyles.promiseIcon} aria-hidden="true">
                <Icon className="h-4 w-4" />
              </span>
              <div>
                <p className={acervoStyles.promiseTitle}>{title}</p>
                <p className={acervoStyles.promiseText}>{text}</p>
              </div>
            </li>
          ))}
        </ul>
        {active ? (
          <div className={freeStyles.emptyActions}>
            {launcher}
            {register}
          </div>
        ) : null}
      </div>
    </section>
  );
}

function Pagination({ collectionId, page, pages }: { collectionId: string; page: number; pages: number }) {
  const current = Math.min(page, pages);
  return (
    <nav className={freeStyles.pagination} aria-label="Páginas da coleção">
      {current > 1 ? (
        <Button asChild variant="outline" className="h-11 min-w-11">
          <Link href={freeCollectionHref(collectionId, { page: current - 1 })}>Anterior</Link>
        </Button>
      ) : null}
      <span aria-current="page">
        Página {formatCount(current)} de {formatCount(pages)}
      </span>
      {current < pages ? (
        <Button asChild variant="outline" className="h-11 min-w-11">
          <Link href={freeCollectionHref(collectionId, { page: current + 1 })}>Próxima</Link>
        </Button>
      ) : null}
    </nav>
  );
}

function PastEnd({ href }: { href: string }) {
  return (
    <section className={acervoStyles.state} aria-labelledby="colecao-fim">
      <h2 id="colecao-fim" className={acervoStyles.stateTitle}>
        Esta página não existe
      </h2>
      <p className={acervoStyles.stateText}>A coleção tem menos páginas. Volte ao início.</p>
      <Button asChild variant="outline" className={acervoStyles.stateAction}>
        <Link href={href}>Ver a coleção</Link>
      </Button>
    </section>
  );
}

function ReadError({ retryHref }: { retryHref: string }) {
  return (
    <section className={acervoStyles.state} role="alert" aria-labelledby="colecao-erro">
      <div className={`${acervoStyles.stateIcon} ${acervoStyles.stateIconDanger}`} aria-hidden="true">
        <AlertTriangle className="h-6 w-6" />
      </div>
      <h2 id="colecao-erro" className={acervoStyles.stateTitle}>
        Não conseguimos carregar as cartas desta coleção
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
