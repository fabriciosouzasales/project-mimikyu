import Link from "next/link";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { Alert } from "@/components/ui/alert";
import { GenerationFilter } from "@/components/pokedex/generation-filter";
import { PokedexSearch } from "@/components/pokedex/pokedex-search";
import { SpeciesGrid } from "@/components/pokedex/species-grid";
import { formatCount, formatDexNumber, generationLabel, generationRoman } from "@/lib/pokedex/format";
import { type ChapterTypeCount, type GenerationChapter, buildGenerationChapter, splitChapterTypes } from "@/lib/pokedex/generation-chapter";
import { pokemonTypeStyle } from "@/lib/pokedex/type-palette";
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
 * vocabulário do palco da ficha), pesquisa em destaque, régua de gerações, linha de
 * resultado e a grade. Server Component; ilhas cliente: pesquisa, arte (fade-in/
 * fallback) e o marcador da última ficha.
 */
export function PokedexNationalView({
  generations,
  species,
  speciesTypes,
  query,
  generation,
}: {
  generations: PokedexGeneration[] | null;
  species: PokedexSpecies[] | null;
  /** Tipos por espécie (Query 6135); `null` = indisponível, cards no tom neutro. */
  speciesTypes: Map<number, PokedexSpeciesTypes> | null;
  query: string | null;
  generation: number | null;
}) {
  const totalSpecies = generations?.reduce((sum, item) => sum + item.species_count, 0) ?? 0;
  const firstRegion = generations?.[0]?.region_name;
  const lastRegion = generations?.[generations.length - 1]?.region_name;
  const activeGeneration = generations?.find((item) => item.generation_ordinal === generation) ?? null;
  const isFiltered = query !== null || activeGeneration !== null;
  const generationCount = generations?.length ?? 0;
  const generationWord = NUMBER_WORDS[generationCount] ?? String(generationCount);
  // Pokédex P4b: com geração selecionada, o cabeçalho vira o capítulo da geração.
  const chapter = activeGeneration ? buildGenerationChapter(activeGeneration, speciesTypes) : null;

  return (
    <div className="mx-auto max-w-7xl">
      <header className={chapter ? `${styles.hero} ${styles.heroChapter}` : styles.hero}>
        {chapter ? (
          <span className={`${styles.numeral} ${styles.numeralChapter}`} aria-hidden="true">
            {generationRoman(chapter.generationCode)}
          </span>
        ) : generations ? (
          <span className={styles.numeral} aria-hidden="true">
            {totalSpecies}
          </span>
        ) : null}
        <PokedexLens className={styles.lens} />
        <div className={styles.heroContent}>
          {chapter ? (
            <ChapterHeading chapter={chapter} />
          ) : (
            <h2 className={styles.title}>Pokédex Nacional</h2>
          )}
          {chapter ? null : generations ? (
            <p className={styles.lede}>
              <strong>{formatCount(totalSpecies)} espécies</strong> em {generationWord} {generationCount === 1 ? "geração" : "gerações"}
              {firstRegion && lastRegion && firstRegion !== lastRegion ? `, de ${firstRegion} a ${lastRegion}` : ""}. Abra
              qualquer uma para ver a ficha completa.
            </p>
          ) : null}
          <div className={styles.search}>
            <PokedexSearch
              initialQuery={query}
              generation={activeGeneration ? generation : null}
              maxLength={POKEDEX_QUERY_MAX_LENGTH}
              size="lg"
            />
          </div>
        </div>
      </header>

      <div className="space-y-6">
        {generations ? (
          <GenerationFilter
            generations={generations}
            activeGeneration={activeGeneration ? generation : null}
            query={query}
            totalSpecies={totalSpecies}
          />
        ) : null}

        {species === null || generations === null ? (
          <Alert variant="destructive">
            <p className="font-medium">Não foi possível carregar a Pokédex agora.</p>
            <p className="mt-1 text-sm opacity-90">
              Isso costuma ser passageiro.{" "}
              <Link href={currentHref(query, generation)} className="font-medium underline underline-offset-2">
                Tentar novamente
              </Link>
            </p>
          </Alert>
        ) : species.length === 0 ? (
          <EmptyResult query={query} activeGeneration={activeGeneration} />
        ) : (
          <>
            <p className="text-sm text-muted-foreground" aria-live="polite">
              {isFiltered ? (
                <>
                  <span className="font-medium tabular-nums text-foreground">{formatCount(species.length)}</span>{" "}
                  {species.length === 1 ? "espécie encontrada" : "espécies encontradas"}
                  {query ? <> para “{query}”</> : null}
                  {activeGeneration ? <> em {generationLabel(activeGeneration.generation_code)}</> : null}
                </>
              ) : (
                <>
                  Todas as <span className="font-medium tabular-nums text-foreground">{formatCount(species.length)}</span> espécies, em
                  ordem de número nacional.
                </>
              )}
            </p>
            <SpeciesGrid
              species={species}
              generations={generations}
              speciesTypes={speciesTypes}
              context={{ query, generation: activeGeneration ? generation : null }}
            />
            {activeGeneration ? (
              <ChapterEnd generations={generations} activeGeneration={activeGeneration} query={query} />
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
  query,
}: {
  generations: PokedexGeneration[];
  activeGeneration: PokedexGeneration;
  query: string | null;
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
          href={currentHref(query, following.generation_ordinal)}
          className="font-medium text-primary-ink underline-offset-2 hover:underline"
          aria-label={`Próxima geração: ${followingLabel}${following.region_name ? `, ${following.region_name}` : ""}`}
        >
          Próxima geração: {followingLabel}
          {following.region_name ? ` · ${following.region_name}` : ""} →
        </Link>
      ) : null}
      <Link href={currentHref(query, null)} className="font-medium text-muted-foreground underline-offset-2 hover:text-foreground hover:underline">
        Ver toda a Pokédex Nacional
      </Link>
    </nav>
  );
}

function EmptyResult({ query, activeGeneration }: { query: string | null; activeGeneration: PokedexGeneration | null }) {
  return (
    <div
      className="flex flex-col items-center gap-3 rounded-xl border border-dashed border-border px-6 py-14 text-center"
      aria-live="polite"
    >
      <Pokeball className="h-10 w-10 text-muted-foreground/50" strokeWidth={1.5} aria-hidden="true" />
      <div className="space-y-1">
        <p className="text-base font-medium text-foreground">Nenhum Pokémon encontrado</p>
        <p className="max-w-md text-sm text-muted-foreground">
          {query ? <>Nada corresponde a “{query}”{activeGeneration ? ` em ${generationLabel(activeGeneration.generation_code)}` : ""}. </> : null}
          Confira a grafia ou pesquise pelo número nacional, como 25 ou #0025.
        </p>
      </div>
      <div className="flex flex-wrap justify-center gap-x-4 gap-y-1 text-sm">
        <Link href={currentHref(null, activeGeneration?.generation_ordinal ?? null)} className="font-medium text-primary-ink underline-offset-2 hover:underline">
          Limpar pesquisa
        </Link>
        {activeGeneration ? (
          <Link href={currentHref(query, null)} className="font-medium text-primary-ink underline-offset-2 hover:underline">
            Pesquisar em todas as gerações
          </Link>
        ) : null}
      </div>
    </div>
  );
}

function currentHref(query: string | null, generation: number | null): string {
  const params = new URLSearchParams();
  if (query) params.set("q", query);
  if (generation) params.set("geracao", String(generation));
  const search = params.toString();
  return search ? `/pokedex?${search}` : "/pokedex";
}
