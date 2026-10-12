/**
 * Tipos do núcleo do importador (artwork-lib.mjs) — só declarações, nenhuma
 * lógica. Permitem que a tela administrativa Pokédex → Imagens (Lote E)
 * reutilize exatamente o mesmo processo do importador de linha de comando
 * a partir de uma Server Action, sem duplicar nem alterar o importador.
 */

export const BUCKET: string;
export const PILOT_NUMBERS: number[];
export const MAX_BYTES: number;
export const DISPLAY_MAX: number;

export type ArtworkCurrentStatus = "PENDING" | "IMPORTED" | "FAILED";

export interface ArtworkFileRecord {
  path: string;
  width: number;
  height: number;
  size_bytes: number;
  sha256: string;
  upload?: "UPLOADED" | "ALREADY_PRESENT";
}

export interface ArtworkRecord {
  national_dex_number: number;
  mode: "APPLY" | "DRY_RUN";
  /** SKIPPED_ALREADY_IMPORTED | DRY_RUN_OK | IMPORTED_<INSERTED|REPLACED|RECOVERED|UNCHANGED> | FAILED */
  outcome: string | null;
  warnings: string[];
  source_species_id?: string;
  source_pokemon_id?: string;
  source_url?: string;
  original?: ArtworkFileRecord;
  display?: ArtworkFileRecord;
  error_code?: string;
  error_message?: string;
  failure_recorded?: boolean;
  image_preserved?: boolean | null;
  failure_record_error?: string;
}

export interface ArtworkHttp {
  fetchJson(url: string): Promise<unknown>;
  fetchBinary(url: string): Promise<Buffer>;
}

export interface ArtworkDeps extends ArtworkHttp {
  sharp: unknown;
  supabase: unknown;
  now: () => Date;
  writePreview?: (n: number, png: Buffer, webp: Buffer) => Promise<void>;
}

export function sanitizeMessage(message: unknown): string;
export function dexPad(n: number): string;

export function makeHttp(options: {
  userAgent: string;
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
  retryDelayMs?: number;
  sleep?: (ms: number) => Promise<void>;
}): ArtworkHttp;

export function processSpecies(
  n: number,
  deps: ArtworkDeps,
  opts: { apply: boolean; force: boolean; currentStatus: ArtworkCurrentStatus },
): Promise<ArtworkRecord>;
