/**
 * Formatos de retorno compartilhados pelas Server Actions administrativas do
 * Catálogo Editorial (ADR-023) — usados por Game e reutilizados pelos ciclos
 * seguintes (Expansion, Card Set), para que os componentes genéricos de
 * listagem (`components/catalogo/admin-list`) não precisem conhecer o tipo
 * específico de cada entidade.
 */
export type EntityActionState = {
  error: string | null;
  success?: boolean;
  id?: string;
};

export type DeleteEntitiesActionState = {
  error: string | null;
  success?: boolean;
  deletedIds?: string[];
  failures?: { id: string; error: string }[];
};
