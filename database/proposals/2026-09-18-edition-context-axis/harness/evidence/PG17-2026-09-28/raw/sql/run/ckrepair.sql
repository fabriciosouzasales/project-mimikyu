BEGIN;
SET LOCAL search_path = '';
SET LOCAL lock_timeout = '5s';
DO $g$ BEGIN
  IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid = 'public.card_printing_external_mapping'::regclass AND conname = 'ck_card_printing_external_mapping_raw_field') IS DISTINCT FROM 'CHECK (((raw_field)::text = ANY (ARRAY[(''subtype''::character varying)::text, (''stamp''::character varying)::text])))' THEN
    RAISE EXCEPTION 'CKREPAIR_PRE %', 'ck_card_printing_external_mapping_raw_field'; END IF; END $g$;
ALTER TABLE public.card_printing_external_mapping DROP CONSTRAINT ck_card_printing_external_mapping_raw_field;
ALTER TABLE public.card_printing_external_mapping ADD CONSTRAINT ck_card_printing_external_mapping_raw_field CHECK (raw_field IN ('subtype', 'stamp'));
DO $g$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.card_printing_external_mapping'::regclass AND c.conname = 'ck_card_printing_external_mapping_raw_field'
                   AND c.contype = 'c' AND c.convalidated AND NOT c.condeferrable AND NOT c.connoinherit
                   AND pg_get_constraintdef(c.oid) = 'CHECK (((raw_field)::text = ANY ((ARRAY[''subtype''::character varying, ''stamp''::character varying])::text[])))'
                   AND md5(c.contype::text || ':' || c.condeferrable || ':' || c.condeferred || ':' || pg_get_constraintdef(c.oid)) = '8ebcee645389f5c2246671ecc6387ef9') THEN
    RAISE EXCEPTION 'CKREPAIR_POST %', 'ck_card_printing_external_mapping_raw_field'; END IF; END $g$;
DO $g$ BEGIN
  IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid = 'public.card_set'::regclass AND conname = 'ck_card_set_type') IS DISTINCT FROM 'CHECK (((set_type)::text = ANY (ARRAY[(''REGULAR''::character varying)::text, (''SPECIAL''::character varying)::text, (''PROMO''::character varying)::text, (''ENERGY''::character varying)::text])))' THEN
    RAISE EXCEPTION 'CKREPAIR_PRE %', 'ck_card_set_type'; END IF; END $g$;
ALTER TABLE public.card_set DROP CONSTRAINT ck_card_set_type;
ALTER TABLE public.card_set ADD CONSTRAINT ck_card_set_type CHECK (set_type IN ('REGULAR', 'SPECIAL', 'PROMO', 'ENERGY'));
DO $g$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.card_set'::regclass AND c.conname = 'ck_card_set_type'
                   AND c.contype = 'c' AND c.convalidated AND NOT c.condeferrable AND NOT c.connoinherit
                   AND pg_get_constraintdef(c.oid) = 'CHECK (((set_type)::text = ANY ((ARRAY[''REGULAR''::character varying, ''SPECIAL''::character varying, ''PROMO''::character varying, ''ENERGY''::character varying])::text[])))'
                   AND md5(c.contype::text || ':' || c.condeferrable || ':' || c.condeferred || ':' || pg_get_constraintdef(c.oid)) = '2b548c67bd0ba97cdbc58c3d7761b261') THEN
    RAISE EXCEPTION 'CKREPAIR_POST %', 'ck_card_set_type'; END IF; END $g$;
COMMIT;