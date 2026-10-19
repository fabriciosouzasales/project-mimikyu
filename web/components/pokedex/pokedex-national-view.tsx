import Link from "next/link";
import { Heart } from "lucide-react";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { Alert } from "@/components/ui/alert";
import { FavoritesController } from "@/components/pokedex/favorites-controller";
import { type FavoritesGenerationOption, FavoritesGenerationFilter } from "@/components/pokedex/favorites-generation-filter";
import { GenerationFilter } from "@/components/pokedex/generation-filter";
import { type CompactBarGeneration, GenerationCompactBar } from "@/components/pokedex/generation-compact-bar";
import { PokedexSearch } from "@/components/pokedex/pokedex-search";
import { type ActiveTypeChip, type TypeFilterOption, TypeFilter } from "@/components/pokedex/type-filter";
import { SpeciesGrid } from "@/components/pokedex/species-grid";
import { type PokedexContext, formatCount, formatDexNumber, generationLabel, generationRoman, pokedexHref } from "@/lib/pokedex/format";
import { applyFavoritesFilter, countByGeneration, filterByGeneration } from "@/lib/pokedex/favorites";
import { type ChapterTypeCount, type GenerationChapter, buildGenerationChapter, splitChapterTypes } from "@/lib/pokedex/generation-chapter";
import { pokemonTypeStyle } from "@/lib/pokedex/type-palette";
import { MAX_TYPE_FILTERS, applyTypeFilter, joinTypeLabels, toggleType, typeLabels } from "@/lib/pokedex/type-filter";
import { PokedexLens } from "@/components/pokedex/detail/pokedex-lens";
import {
  POKEDEX_QUERY_MAX_LENGTH,
  type PokedexGeneration,
  type PokedexSpecies,
  type PokedexSpeciesTypes,
} from "@/lib/pokedex/queries";
import styles from "./pokedex-national.module.css";

/** Nove → "nove": números pequenos por extenso no texto do cabeçalho. */
const NUMBER_WORDS = ["zero", "uma", "duas", "três", "quatro", "cinco", "seis", "sete", "oito", "nove", "dez"];

/**
 * Pokédex Nacional (Pokédex P1; visual premium P3c, 2026-10-12) — composição da
 * página: cabeçalho com o total em numeral de contorno e a lente da Pokédex (mesmo
 * vocabulário do palco da ficha), pesquisa em destaque, régua de gerações, filtro por
 * tipo (P5a), linha de resultado e a grade. Server Component; ilhas cliente: pesquisa,
 * abrir/fechar do filtro por tipo, arte (fade-in/fallback) e o marcador da última ficha.
 *
 * P5a: o filtro por tipo é aplicado aqui, numa passagem sobre a lista que já veio de
 * 6131 (pesquisa/geração) e o índice 6135 — sem consulta nova. Contagens da régua e
 * do capítulo continuam totais (decisão D4); sem índice de tipos, o seletor some e um
 * `?tipo=` da URL é avisado e ignorado, nunca aplicado pela metade.
 *
 * P6 (2026-10-15): a MESMA composição serve à página Pokémon Favoritos
 * (`mode="favorites"`, `/pokedex/favoritos`) — nenhuma segunda galeria. O recorte de
 * favoritos é aplicado aqui, sobre a lista de 6131, antes do filtro por tipo; todos os
 * links (régua, barra, pesquisa, tipos, cards) carregam a origem e ficam dentro da
 * página. Cabeçalho próprio (sem capítulo de geração), estados vazios próprios e erro
 * específico quando a leitura de favoritos falha. Corações em todos os cards (ilha
 * FavoritesController).
 *
 * P6, Correção de UX-01 (2026-10-15): na página Favoritos a grade é CONTÍNUA (sem
 * capítulos por geração) e a régua de nove gerações dá lugar a um filtro compacto de
 * geração, recolhido por padrão. A lista chega sem filtro de geração (só a pesquisa) e
 * a geração é aplicada aqui, depois do recorte de favoritos — o filtro compacto conta
 * os favoritos de cada geração com a pesquisa e os tipos atuais, sem leitura extra. A
 * Pokédex Nacional (capítulos, régua, barra compacta) não muda.
 */
export function PokedexNationalView({
  generations,
  species,
  speciesTypes,
  query,
  generation,
  types,
  favorites,
  mode = "national",
}: {
  generations: PokedexGeneration[] | null;
  species: PokedexSpecies[] | null;
  /** Tipos por espécie (Query 6135); `null` = indisponível, cards no tom neutro. */
  speciesTypes: Map<number, PokedexSpeciesTypes> | null;
  query: string | null;
  generation: number | null;
  /** Tipos já canônicos (`?tipo=`, P5a). */
  types: string[];
  /** Favoritos do usuário (P6); `null` = leitura indisponível. */
  favorites: ReadonlySet<number> | null;
  /** P6: "favorites" = página Pokémon Favoritos. */
  mode?: "national" | "favorites";
}) {
  const isFavoritesPage = mode === "favorites";
  const totalSpecies = generations?.reduce((sum, item) => sum + item.species_count, 0) ?? 0;
  const firstRegion = generations?.[0]?.region_name;
  const lastRegion = generations?.[generations.length - 1]?.region_name;
  const activeGeneration = generations?.find((item) => item.generation_ordinal === generation) ?? null;
  const contextGeneration = activeGeneration ? generation : null;
  // P5a: tipos só valem com o índice de tipos; sem ele, `?tipo=` não é aplicado e é avisado.
  const typeIndexAvailable = speciesTypes !== null;
  const appliedTypes = typeIndexAvailable ? types : [];
  const typeUnavailableNotice = !typeIndexAvailable && types.length > 0;
  const context: PokedexContext = { query, generation: contextGeneration, types, origin: isFavoritesPage ? "favoritos" : null };
  const labels = speciesTypes ? typeLabels(speciesTypes) : null;
  // P6: na página Favoritos, o recorte vem antes do filtro por tipo (as contagens do
  // seletor de tipo passam a ser dos favoritos). Sem leitura de favoritos, não há lista.
  // UX-01: favoritos de todas as gerações (com a pesquisa) → contagens por geração com
  // os tipos atuais → recorte da geração escolhida.
  const favoritesAllGenerations = isFavoritesPage ? (species && favorites ? applyFavoritesFilter(species, favorites) : null) : null;
  const favoritesForGenerationCounts =
    favoritesAllGenerations && speciesTypes
      ? applyTypeFilter(favoritesAllGenerations, speciesTypes, appliedTypes).species
      : favoritesAllGenerations;
  const baseSpecies = isFavoritesPage
    ? favoritesAllGenerations
      ? filterByGeneration(favoritesAllGenerations, contextGeneration)
      : null
    : species;
  const typeResult = baseSpecies && speciesTypes ? applyTypeFilter(baseSpecies, speciesTypes, appliedTypes) : null;
  const visibleSpecies = typeResult ? typeResult.species : baseSpecies;
  const favoritesCount = favorites?.size ?? 0;
  // Favoritos sem nenhum item (ou indisponíveis): régua e filtros não têm o que filtrar.
  const showFilters = !isFavoritesPage || (favorites !== null && favoritesCount > 0);
  const appliedTypeLabels = appliedTypes.map((code) => labels?.get(code) ?? code);
  const isFiltered = query !== null || activeGeneration !== null || appliedTypes.length > 0;
  const generationCount = generations?.length ?? 0;
  const generationWord = NUMBER_WORDS[generationCount] ?? String(generationCount);
  // Pokédex P4b: com geração selecionada, o cabeçalho vira o capítulo da geração.
  const chapter = activeGeneration && !isFavoritesPage ? buildGenerationChapter(activeGeneration, speciesTypes) : null;

  // Filtro por tipo (P5a) — o mesmo nas duas páginas; em Favoritos entra na barra de
  // ferramentas (`inline`, UX-02).
  const typeFilter =
    typeResult && labels && labels.size > 0 && generations && showFilters
      ? (inline: boolean) => (
          <TypeFilter
            inline={inline}
            options={typeFilterOptions(labels, typeResult.counts, appliedTypes, context)}
            active={appliedTypes.map(
              (code): ActiveTypeChip => ({
                code,
                label: labels.get(code) ?? code,
                removeHref: pokedexHref({ ...context, types: toggleType(appliedTypes, code) }),
              }),
            )}
            clearHref={pokedexHref({ ...context, types: [] })}
          />
        )
      : null;

  return (
    <div className="mx-auto max-w-7xl">
      <header
        className={chapter ? `${styles.hero} ${styles.heroChapter}` : isFavoritesPage ? `${styles.hero} ${styles.heroFavorites}` : styles.hero}
      >
        {chapter ? (
          <span className={`${styles.numeral} ${styles.numeralChapter}`} aria-hidden="true">
            {generationRoman(chapter.generationCode)}
          </span>
        ) : isFavoritesPage ? (
          favorites ? (
            <span className={styles.numeral} aria-hidden="true">
              {favoritesCount}
            </span>
          ) : null
        ) : generations ? (
          <span className={styles.numeral} aria-hidden="true">
            {totalSpecies}
          </span>
        ) : null}
        <PokedexLens className={styles.lens} />
        <div className={styles.heroContent}>
          {chapter ? (
            <ChapterHeading chapter={chapter} />
          ) : isFavoritesPage ? (
            <>
              <p className={styles.eyebrow}>Pokédex</p>
              <h2 className={styles.title}>Pokémon Favoritos</h2>
            </>
          ) : (
            <h2 className={styles.title}>Pokédex Nacional</h2>
          )}
          {isFavoritesPage ? (
            favorites ? (
              <p className={styles.lede}>
                {favoritesCount === 0 ? (
                  <>As espécies que você marcar com o coração aparecem aqui.</>
                ) : (
                  <>
                    <strong>
                      {formatCount(favoritesCount)} {favoritesCount === 1 ? "espécie favorita" : "espécies favoritas"}
                    </strong>
                    . Toque no coração de um card para tirá-lo da lista.
                  </>
                )}
              </p>
            ) : null
          ) : chapter ? null : generations ? (
            <p className={styles.lede}>
              <strong>{formatCount(totalSpecies)} espécies</strong> em {generationWord} {generationCount === 1 ? "geração" : "gerações"}
              {firstRegion && lastRegion && firstRegion !== lastRegion ? `, de ${firstRegion} a ${lastRegion}` : ""}. Abra
              qualquer uma para ver a ficha completa.
            </p>
          ) : null}
          <div className={styles.search}>
            <PokedexSearch
              initialQuery={query}
              generation={contextGeneration}
              types={types}
              origin={context.origin ?? null}
              maxLength={POKEDEX_QUERY_MAX_LENGTH}
              size="lg"
            />
          </div>
        </div>
      </header>

      {/* P4c: na visão nacional (desktop), a barra compacta de orientação surge quando a
          régua sai de vista; data-pk-compact-nav ajusta a margem de rolagem das âncoras
          (#especie-NNNN) para o card do "voltar" não ficar sob a barra. */}
      <div
        className={isFavoritesPage ? styles.favoritesBody : "space-y-6"}
        data-pk-compact-nav={activeGeneration || isFavoritesPage ? undefined : ""}
      >
        {/* UX-01/UX-02: em Favoritos, Geração e Tipo formam uma barra de ferramentas numa
            linha só (os painéis abrem logo abaixo, na largura toda); régua e barra
            compacta são exclusivas da Pokédex Nacional. */}
        {isFavoritesPage ? (
          generations && showFilters && favoritesForGenerationCounts ? (
            <div className={styles.favoritesToolbar} role="group" aria-label="Filtros dos favoritos">
              <FavoritesGenerationFilter
                options={favoritesGenerationOptions(generations, countByGeneration(favoritesForGenerationCounts), contextGeneration, context)}
                allHref={pokedexHref({ ...context, generation: null })}
                allCount={favoritesForGenerationCounts.length}
              />
              {typeFilter ? typeFilter(true) : null}
            </div>
          ) : null
        ) : (
          <>
            {generations ? (
              <GenerationFilter
                generations={generations}
                activeGeneration={contextGeneration}
                query={query}
                types={types}
                origin={context.origin ?? null}
                totalSpecies={totalSpecies}
              />
            ) : null}
            {generations && !activeGeneration && visibleSpecies && visibleSpecies.length > 0 ? (
              <GenerationCompactBar
                key={`${query ?? ""}|${types.join(",")}`}
                generations={compactBarGenerations(generations)}
                query={query}
                types={types}
                origin={context.origin ?? null}
              />
            ) : null}
            {typeFilter ? typeFilter(false) : null}
          </>
        )}

        {typeUnavailableNotice && species !== null ? (
          <Alert variant="warning">
            <p className="font-medium">O filtro por tipo está indisponível no momento.</p>
            <p className="mt-1 text-sm opacity-90">
              Mostrando as espécies sem esse filtro.{" "}
              <Link href={pokedexHref(context)} className="font-medium underline underline-offset-2">
                Tentar novamente
              </Link>
              {" · "}
              <Link href={pokedexHref({ ...context, types: [] })} className="font-medium underline underline-offset-2">
                Remover filtro de tipo
              </Link>
            </p>
          </Alert>
        ) : null}

        {!isFavoritesPage && favorites === null && species !== null ? (
          <p className="text-sm text-muted-foreground" role="status">
            Os favoritos estão indisponíveis no momento — os corações voltam quando a conexão for restabelecida.
          </p>
        ) : null}

        {isFavoritesPage && favorites === null && species !== null ? (
          <Alert variant="destructive">
            <p className="font-medium">Não foi possível carregar seus favoritos agora.</p>
            <p className="mt-1 text-sm opacity-90">
              Seus favoritos continuam salvos; isso costuma ser passageiro.{" "}
              <Link href={pokedexHref(context)} className="font-medium underline underline-offset-2">
                Tentar novamente
              </Link>
              {" · "}
              <Link href={pokedexHref({ ...context, origin: null })} className="font-medium underline underline-offset-2">
                Ir para a Pokédex Nacional
              </Link>
            </p>
          </Alert>
        ) : visibleSpecies === null || generations === null ? (
          <Alert variant="destructive">
            <p className="font-medium">Não foi possível carregar a Pokédex agora.</p>
            <p className="mt-1 text-sm opacity-90">
              Isso costuma ser passageiro.{" "}
              <Link href={pokedexHref(context)} className="font-medium underline underline-offset-2">
                Tentar novamente
              </Link>
            </p>
          </Alert>
        ) : isFavoritesPage && favoritesCount === 0 ? (
          <FavoritesEmpty />
        ) : visibleSpecies.length === 0 ? (
          <EmptyResult
            context={context}
            activeGeneration={activeGeneration}
            typeLabels={appliedTypeLabels}
            favoritesPage={isFavoritesPage}
          />
        ) : (
          <>
            {isFavoritesPage ? (
              <div className={styles.favoritesResults}>
                <FavoritesResultsBar shown={visibleSpecies.length} total={favoritesCount} filtered={isFiltered} />
                <FavoritesController mode="favorites">
                  <SpeciesGrid
                    species={visibleSpecies}
                    generations={generations}
                    speciesTypes={speciesTypes}
                    context={context}
                    favorites={favorites}
                    layout="continuous"
                  />
                </FavoritesController>
              </div>
            ) : (
              <>
                <p className="text-sm text-muted-foreground" aria-live="polite">
                  {isFiltered ? (
                    <>
                      <span className="font-medium tabular-nums text-foreground">{formatCount(visibleSpecies.length)}</span>{" "}
                      {visibleSpecies.length === 1 ? "espécie encontrada" : "espécies encontradas"}
                      {appliedTypes.length > 0 ? (
                        <>
                          {" "}
                          {appliedTypes.length === 1 ? "do tipo" : "com os tipos"} {joinTypeLabels(appliedTypeLabels)}
                        </>
                      ) : null}
                      {query ? <> para “{query}”</> : null}
                      {activeGeneration ? <> em {generationLabel(activeGeneration.generation_code)}</> : null}
                    </>
                  ) : (
                    <>
                      Todas as <span className="font-medium tabular-nums text-foreground">{formatCount(visibleSpecies.length)}</span> espécies, em
                      ordem de número nacional.
                    </>
                  )}
                </p>
                <FavoritesController mode="national">
                  <SpeciesGrid
                    species={visibleSpecies}
                    generations={generations}
                    speciesTypes={speciesTypes}
                    context={context}
                    favorites={favorites}
                    layout="chapters"
                  />
                </FavoritesController>
              </>
            )}
            {activeGeneration && !isFavoritesPage ? (
              <ChapterEnd generations={generations} activeGeneration={activeGeneration} context={context} />
            ) : null}
          </>
        )}
      </div>
    </div>
  );
}

/**
 * Cabeçalho do capítulo da geração (Pokédex P4b, 2026-10-13). Mesmo palco da Pokédex
 * Nacional (numeral em contorno — agora o romano da geração —, lente ao fundo, mesma
 * tipografia), com a identidade nacional mantida na linha de sobretítulo. Indicadores:
 * espécies, intervalo de números e tipos presentes, rotulados para não confundir
 * espécies com tipos; a composição mostra os tipos mais frequentes e abre o resto num
 * `<details>` nativo (sem JavaScript). Todos os números vêm de lib/pokedex/generation-chapter.ts.
 */
function ChapterHeading({ chapter }: { chapter: GenerationChapter }) {
  const label = generationLabel(chapter.generationCode);
  const title = chapter.regionName ?? label;
  const range =
    chapter.firstNumber !== null && chapter.lastNumber !== null
      ? `${formatDexNumber(chapter.firstNumber)}–${formatDexNumber(chapter.lastNumber)}`
      : null;
  const composition = chapter.composition;
  const { visible, hidden } = splitChapterTypes(composition?.types ?? []);

  return (
    <>
      <p className={styles.eyebrow}>
        Pokédex Nacional <span aria-hidden="true">·</span> {label}
      </p>
      <h2 className={styles.title}>
        {chapter.regionName ? (
          <>
            <span className="sr-only">{label}, </span>
            {title}
          </>
        ) : (
          title
        )}
      </h2>
      <dl className={styles.facts}>
        <div>
          <dt>Espécies</dt>
          <dd>{formatCount(chapter.speciesCount)}</dd>
        </div>
        {range ? (
          <div>
            <dt>Números</dt>
            <dd>
              <span className="sr-only">de </span>
              {range}
            </dd>
          </div>
        ) : null}
        {composition ? (
          <div>
            <dt>Tipos presentes</dt>
            <dd>
              {composition.types.length} <span className={styles.factOf}>de 18</span>
            </dd>
          </div>
        ) : null}
      </dl>
      {composition ? (
        <div className={styles.composition}>
          <p className={styles.compositionLabel} id="capitulo-tipos">
            Tipos mais frequentes <span className={styles.compositionHint}>· espécies com o tipo, primário ou secundário</span>
          </p>
          <ul className={styles.typeList} aria-labelledby="capitulo-tipos">
            {visible.map((type) => (
              <ChapterType key={type.code} type={type} />
            ))}
          </ul>
          {hidden.length > 0 ? (
            <details className={styles.moreTypes}>
              <summary>
                Ver os outros {hidden.length} {hidden.length === 1 ? "tipo" : "tipos"}
              </summary>
              <ul className={styles.typeList} aria-label="Demais tipos presentes">
                {hidden.map((type) => (
                  <ChapterType key={type.code} type={type} />
                ))}
              </ul>
            </details>
          ) : null}
          {composition.typedSpecies < chapter.speciesCount ? (
            <p className={styles.compositionHint}>
              Tipos disponíveis para {formatCount(composition.typedSpecies)} de {formatCount(chapter.speciesCount)} espécies.
            </p>
          ) : null}
        </div>
      ) : null}
    </>
  );
}

function ChapterType({ type }: { type: ChapterTypeCount }) {
  return (
    <li className={styles.typeItem} style={pokemonTypeStyle(type.code, "t1")}>
      <span className={styles.typeDot} aria-hidden="true" />
      <span className={styles.typeName}>{type.label}</span>
      <span className={styles.typeCount}>
        {formatCount(type.count)}
        <span className="sr-only"> {type.count === 1 ? "espécie" : "espécies"}</span>
      </span>
    </li>
  );
}

/**
 * Fim do capítulo da geração filtrada (Pokédex P4a): continuar para a próxima
 * geração — preservando a pesquisa, como a régua — ou voltar à Pokédex Nacional.
 * Na última geração só resta a saída para a Pokédex Nacional. Links simples,
 * renderizados no servidor.
 */
function ChapterEnd({
  generations,
  activeGeneration,
  context,
}: {
  generations: PokedexGeneration[];
  activeGeneration: PokedexGeneration;
  context: PokedexContext;
}) {
  const following = generations.find((item) => item.generation_ordinal === activeGeneration.generation_ordinal + 1) ?? null;
  const followingLabel = following ? generationLabel(following.generation_code) : null;
  return (
    <nav
      aria-label="Continuar explorando"
      className="flex flex-col items-center gap-x-6 gap-y-2 border-t border-border/60 pt-6 text-sm sm:flex-row sm:justify-center"
    >
      {following && followingLabel ? (
        <Link
          href={pokedexHref({ ...context, generation: following.generation_ordinal })}
          className="font-medium text-primary-ink underline-offset-2 hover:underline"
          aria-label={`Próxima geração: ${followingLabel}${following.region_name ? `, ${following.region_name}` : ""}`}
        >
          Próxima geração: {followingLabel}
          {following.region_name ? ` · ${following.region_name}` : ""} →
        </Link>
      ) : null}
      <Link href={pokedexHref({ ...context, generation: null })} className="font-medium text-muted-foreground underline-offset-2 hover:text-foreground hover:underline">
        Ver toda a Pokédex Nacional
      </Link>
    </nav>
  );
}

/**
 * Faixa de resultados da página Favoritos (UX-02), logo acima da grade: com filtros,
 * "Exibindo X de Y favoritos" (Y = total do cabeçalho); sem filtros, não repete a
 * contagem do cabeçalho. À direita, só a indicação da ordem existente (número nacional) —
 * informativa, sem controle de ordenação.
 */
function FavoritesResultsBar({ shown, total, filtered }: { shown: number; total: number; filtered: boolean }) {
  return (
    <div className={styles.resultsBar}>
      <p aria-live="polite">
        {filtered ? (
          <>
            Exibindo <strong>{formatCount(shown)}</strong> de {formatCount(total)} {total === 1 ? "favorito" : "favoritos"}
          </>
        ) : (
          <>Todos os seus favoritos</>
        )}
      </p>
      <p className={styles.resultsOrder}>
        Ordem: <span>Número nacional</span>
      </p>
    </div>
  );
}

/**
 * Opções do filtro compacto de geração da página Favoritos (UX-01): cada geração com a
 * contagem de favoritos (pesquisa e tipos atuais); sem favoritos = indisponível (sem
 * link), a não ser que já esteja selecionada. Os links preservam pesquisa, tipos e a
 * origem.
 */
function favoritesGenerationOptions(
  generations: PokedexGeneration[],
  counts: Map<number, number>,
  selected: number | null,
  context: PokedexContext,
): FavoritesGenerationOption[] {
  return generations.map((item) => {
    const count = counts.get(item.generation_ordinal) ?? 0;
    const isSelected = item.generation_ordinal === selected;
    return {
      ordinal: item.generation_ordinal,
      label: generationLabel(item.generation_code),
      regionName: item.region_name,
      count,
      selected: isSelected,
      href: isSelected || count > 0 ? pokedexHref({ ...context, generation: item.generation_ordinal }) : null,
    };
  });
}

/** Dados mínimos da régua para a barra compacta (P4c) — os mesmos rótulos da régua. */
function compactBarGenerations(generations: PokedexGeneration[]): CompactBarGeneration[] {
  return generations.map((item) => ({
    code: item.generation_code,
    ordinal: item.generation_ordinal,
    label: generationLabel(item.generation_code),
    roman: generationRoman(item.generation_code),
    regionName: item.region_name,
    speciesCount: formatCount(item.species_count),
  }));
}

/**
 * Opções do seletor de tipo (P5a), na ordem oficial: cada uma liga/desliga o tipo
 * preservando pesquisa e geração. Indisponível (sem link) quando já há dois tipos ou
 * quando acrescentá-la esvaziaria o resultado.
 */
function typeFilterOptions(
  labels: Map<string, string>,
  counts: Map<string, number>,
  selected: string[],
  context: PokedexContext,
): TypeFilterOption[] {
  const atLimit = selected.length >= MAX_TYPE_FILTERS;
  return [...labels].map(([code, label]) => {
    const isSelected = selected.includes(code);
    const count = isSelected ? null : (counts.get(code) ?? 0);
    const enabled = isSelected || (!atLimit && (count ?? 0) > 0);
    return {
      code,
      label,
      selected: isSelected,
      count,
      href: enabled ? pokedexHref({ ...context, types: toggleType(selected, code) }) : null,
    };
  });
}

/**
 * Página Pokémon Favoritos sem nenhum favorito (P6): explica o gesto e oferece o
 * caminho de volta à Pokédex Nacional — nunca uma tela "vazia de sistema".
 */
function FavoritesEmpty() {
  return (
    <div
      className="flex flex-col items-center gap-3 rounded-xl border border-dashed border-border px-6 py-14 text-center"
      aria-live="polite"
    >
      <Heart className="h-10 w-10 text-[hsl(var(--favorite))]" strokeWidth={1.5} aria-hidden="true" />
      <div className="space-y-1">
        <p className="text-base font-medium text-foreground">Você ainda não tem Pokémon favoritos</p>
        <p className="max-w-md text-sm text-muted-foreground">
          Toque no coração de qualquer espécie, na Pokédex Nacional ou na ficha, para guardá-la aqui. Favoritar não depende de
          ter cartas.
        </p>
      </div>
      <Link href="/pokedex" className="text-sm font-medium text-primary-ink underline-offset-2 hover:underline">
        Explorar a Pokédex Nacional
      </Link>
    </div>
  );
}

function EmptyResult({
  context,
  activeGeneration,
  typeLabels: labels,
  favoritesPage = false,
}: {
  context: PokedexContext;
  activeGeneration: PokedexGeneration | null;
  typeLabels: string[];
  favoritesPage?: boolean;
}) {
  const { query } = context;
  const hasTypes = labels.length > 0;
  const where = activeGeneration ? ` em ${generationLabel(activeGeneration.generation_code)}` : "";
  return (
    <div
      className="flex flex-col items-center gap-3 rounded-xl border border-dashed border-border px-6 py-14 text-center"
      aria-live="polite"
    >
      <Pokeball className="h-10 w-10 text-muted-foreground/50" strokeWidth={1.5} aria-hidden="true" />
      <div className="space-y-1">
        <p className="text-base font-medium text-foreground">{favoritesPage ? "Nenhum favorito encontrado" : "Nenhum Pokémon encontrado"}</p>
        <p className="max-w-md text-sm text-muted-foreground">
          {query ? (
            <>
              Nada corresponde a “{query}”{hasTypes ? ` ${labels.length === 1 ? "do tipo" : "com os tipos"} ${joinTypeLabels(labels)}` : ""}
              {where}.{" "}
            </>
          ) : hasTypes ? (
            <>
              {favoritesPage ? "Nenhum favorito" : "Nenhuma espécie"} {labels.length === 1 ? "do tipo" : "com os tipos"}{" "}
              {joinTypeLabels(labels)}
              {where}.{" "}
            </>
          ) : favoritesPage && activeGeneration ? (
            <>Nenhum favorito{where}. </>
          ) : null}
          {query ? "Confira a grafia ou pesquise pelo número nacional, como 25 ou #0025." : null}
        </p>
      </div>
      <div className="flex flex-wrap justify-center gap-x-4 gap-y-1 text-sm">
        {query ? (
          <Link href={pokedexHref({ ...context, query: null })} className="font-medium text-primary-ink underline-offset-2 hover:underline">
            Limpar pesquisa
          </Link>
        ) : null}
        {hasTypes ? (
          <Link href={pokedexHref({ ...context, types: [] })} className="font-medium text-primary-ink underline-offset-2 hover:underline">
            Remover filtro de tipo
          </Link>
        ) : null}
        {activeGeneration ? (
          <Link href={pokedexHref({ ...context, generation: null })} className="font-medium text-primary-ink underline-offset-2 hover:underline">
            {query ? "Pesquisar em todas as gerações" : "Ver em todas as gerações"}
          </Link>
        ) : null}
      </div>
    </div>
  );
}
