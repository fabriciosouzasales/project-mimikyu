/**
 * Regras de validação de username/display_name, espelhando exatamente as
 * constraints já vigentes no banco (ver
 * database/schema/1000_create_user_profile_table.sql — CHECK constraints — e
 * database/schema/1020_create_handle_new_user_function.sql — revalidação no
 * trigger). Este espelho é só uma antecipação de UX: a autoridade final
 * continua sendo o banco, que revalida tudo de novo no INSERT/UPDATE real
 * (ver ADR-020).
 */

export const USERNAME_MIN_LENGTH = 3;
export const USERNAME_MAX_LENGTH = 20;
export const USERNAME_FORMAT = /^[a-z0-9_]{3,20}$/;

export const DISPLAY_NAME_MIN_LENGTH = 1;
export const DISPLAY_NAME_MAX_LENGTH = 60;

/** Mesma normalização aplicada por handle_new_user() e username_available(): trim + lowercase. */
export function normalizeUsername(value: string): string {
  return value.trim().toLowerCase();
}

export function isUsernameFormatValid(value: string): boolean {
  return USERNAME_FORMAT.test(value);
}

/** Mesma normalização aplicada pelo trigger enforce_user_profile_invariants(): trim. */
export function normalizeDisplayName(value: string): string {
  return value.trim();
}

export function isDisplayNameValid(value: string): boolean {
  const length = normalizeDisplayName(value).length;
  return length >= DISPLAY_NAME_MIN_LENGTH && length <= DISPLAY_NAME_MAX_LENGTH;
}
