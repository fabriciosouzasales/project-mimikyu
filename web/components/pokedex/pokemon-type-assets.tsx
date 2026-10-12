import { POKEMON_TYPE_PALETTE, NEUTRAL_TYPE_TONE, type PokemonTypeCode } from "@/lib/pokedex/type-palette";

/**
 * Recursos de tipo compartilhados pela galeria (Pokédex P3c, 2026-10-12).
 *
 * Com 1.025 cards, estilo e ícone por card custariam caro em HTML (estilo inline e um
 * SVG completo por chip). Aqui cada um existe uma vez por página:
 *
 * - `PokemonTypeStyles`: 36 regras `[data-t1="FIRE"]` / `[data-t2="FIRE"]` geradas da
 *   paleta oficial (lib/pokedex/type-palette.ts), definindo as mesmas variáveis usadas
 *   na ficha (--pk-t1-l/-d, --pk-t1-ink-l/-d, idem t2). O card só leva `data-t1`/`data-t2`.
 *   Escopo `[data-pk-types]`: a especificidade vence o tom neutro padrão do escopo.
 * - `PokemonTypeSprite`: um `<symbol>` por tipo com o ícone Lucide; os chips usam `<use>`.
 *
 * Conteúdo 100% estático (constantes do código) — nada vindo de usuário ou do banco é
 * interpolado no CSS.
 */
const TYPE_CODES = Object.keys(POKEMON_TYPE_PALETTE) as PokemonTypeCode[];

function buildTypeCss(): string {
  const n = NEUTRAL_TYPE_TONE;
  let css =
    `[data-pk-types]{--pk-t1-l:${n.light};--pk-t1-d:${n.dark};--pk-t1-ink-l:${n.inkLight};--pk-t1-ink-d:${n.inkDark};` +
    `--pk-t2-l:${n.light};--pk-t2-d:${n.dark};--pk-t2-ink-l:${n.inkLight};--pk-t2-ink-d:${n.inkDark}}`;
  for (const code of TYPE_CODES) {
    const t = POKEMON_TYPE_PALETTE[code];
    css +=
      `[data-pk-types] [data-t1="${code}"]{--pk-t1-l:${t.light};--pk-t1-d:${t.dark};--pk-t1-ink-l:${t.inkLight};--pk-t1-ink-d:${t.inkDark}}` +
      `[data-pk-types] [data-t2="${code}"]{--pk-t2-l:${t.light};--pk-t2-d:${t.dark};--pk-t2-ink-l:${t.inkLight};--pk-t2-ink-d:${t.inkDark}}`;
  }
  return css;
}

const TYPE_CSS = buildTypeCss();

export function PokemonTypeStyles() {
  return <style>{TYPE_CSS}</style>;
}

export function pokemonTypeSymbolId(code: string): string {
  return `pk-type-${code}`;
}

export function PokemonTypeSprite() {
  return (
    <svg width="0" height="0" style={{ position: "absolute" }} aria-hidden="true" focusable="false">
      {TYPE_CODES.map((code) => {
        const Icon = POKEMON_TYPE_PALETTE[code].icon;
        return (
          <symbol key={code} id={pokemonTypeSymbolId(code)} viewBox="0 0 24 24">
            <Icon width={24} height={24} strokeWidth={2.25} />
          </symbol>
        );
      })}
    </svg>
  );
}
