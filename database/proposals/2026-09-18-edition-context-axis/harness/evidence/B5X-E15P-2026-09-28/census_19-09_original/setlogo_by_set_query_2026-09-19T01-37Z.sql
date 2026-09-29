SELECT vt.code,
  (SELECT COUNT(*) FROM card_variant cv WHERE cv.variant_type_id=vt.id) AS variants,
  (SELECT string_agg(cs.code||':'||x.n, ' ' ORDER BY x.n DESC, cs.code)
     FROM (SELECT c.card_set_id AS sid, COUNT(*) n FROM card_variant cv JOIN card c ON c.id=cv.card_id WHERE cv.variant_type_id=vt.id GROUP BY 1) x
     JOIN card_set cs ON cs.id=x.sid) AS por_set,
  (SELECT string_agg(COALESCE(m.external_set_id,'GLOBAL')||' :: '||m.normalized_type||'|'||COALESCE(m.normalized_foil,'-')||'|'||COALESCE(m.normalized_subtype,'-')||'|'||COALESCE(array_to_string(m.normalized_stamp,'+'),'-'), ' ; ')
     FROM card_variant_type_external_mapping m WHERE m.variant_type_id=vt.id) AS mappings
FROM card_variant_type vt
WHERE vt.code LIKE 'SET_LOGO%'
ORDER BY vt.code;