SELECT vt.code, vt.is_active,
  (SELECT COUNT(*) FROM card_variant cv WHERE cv.variant_type_id=vt.id) AS variants,
  (SELECT COUNT(*) FROM card_variant_type_external_mapping m WHERE m.variant_type_id=vt.id) AS mappings,
  (SELECT COUNT(*) FROM pricing_source_variant_mapping p WHERE p.variant_type_id=vt.id) AS psvm,
  (SELECT COUNT(*) FROM pricing_source_card_identity p WHERE p.card_variant_type_id=vt.id) AS pscid,
  (SELECT COUNT(*) FROM physical_card pc JOIN card_variant cv ON cv.id=pc.card_variant_id WHERE cv.variant_type_id=vt.id) AS phys,
  (SELECT COUNT(*) FROM collection_master_set_scope s JOIN card_variant cv ON cv.id=s.card_variant_id WHERE cv.variant_type_id=vt.id) AS scope
FROM card_variant_type vt ORDER BY variants DESC, vt.code;