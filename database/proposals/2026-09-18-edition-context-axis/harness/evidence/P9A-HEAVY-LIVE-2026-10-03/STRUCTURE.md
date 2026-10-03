# Estrutura dos planos (derivada das saídas integrais *.plan.txt; sem interpretação de tempo)

## S2-P9A-B
- linhas de plano: 46; nó raiz: `Aggregate`
- CTEs: 2; InitPlans: 5; SubPlans: 0
- tipos de nó: Aggregate×3, Append×1, CTE Scan×5, Function Scan×2, Hash×3, Hash Join×2, Hash Right Join×1, Index Scan×3, Memoize×1, Nested Loop×1, Nested Loop Left Join×1, Seq Scan×3, Sort×1, Subquery Scan×1, Values Scan×1
- Seq Scan por relação: card×1, catalog_variant_import_job×1, catalog_variant_import_row×1
- Index/Index Only Scan: uq_asset_source_code on asset_source (Index Scan)×2, uq_game_code on game (Index Scan)×1
- Function Scan: resolve_variant_mapping_scope×1, resolve_variant_row_axes×1
- nós de escrita/LockRows/JIT/tempo: nenhum

## S3-P9A-M
- linhas de plano: 11; nó raiz: `Aggregate`
- CTEs: 0; InitPlans: 0; SubPlans: 0
- tipos de nó: Aggregate×1, Append×1, Hash×1, Hash Join×1, Seq Scan×2, Sort×1, Subquery Scan×1, Values Scan×1
- Seq Scan por relação: catalog_variant_import_job×1, catalog_variant_import_row×1
- Index/Index Only Scan: nenhum
- Function Scan: nenhum
- nós de escrita/LockRows/JIT/tempo: nenhum

## S4-P9A-5X
- linhas de plano: 789; nó raiz: `Result`
- CTEs: 14; InitPlans: 84; SubPlans: 34
- tipos de nó: Aggregate×81, Append×1, CTE Scan×151, Function Scan×2, Hash×65, Hash Join×48, Hash Right Join×4, Hash Semi Join×13, HashAggregate×24, Index Only Scan×2, Index Scan×18, Nested Loop×16, Nested Loop Left Join×1, Result×1, Seq Scan×40, Sort×1, Unique×1, Values Scan×2
- Seq Scan por relação: card×3, card_set×2, card_variant×4, card_variant_type×27, catalog_variant_import_row×3, pricing_source_variant_mapping×1
- Index/Index Only Scan: card_pkey on card (Index Scan)×1, ix_card_variant_variant_type_id on card_variant (Index Scan)×2, ix_catalog_variant_import_row_matched_variant on catalog_variant_import_row (Index Only Scan)×1, ix_pricing_source_card_identity_card_variant_type_id on pricing_source_card_identity (Index Only Scan)×1, uq_asset_source_code on asset_source (Index Scan)×2, uq_card_set_expansion_code on card_set (Index Scan)×12, uq_game_code on game (Index Scan)×1
- Function Scan: resolve_variant_mapping_scope×1, resolve_variant_row_axes×1
- nós de escrita/LockRows/JIT/tempo: nenhum

## S5-P9A-D1X
- linhas de plano: 430; nó raiz: `Nested Loop`
- CTEs: 33; InitPlans: 32; SubPlans: 6
- tipos de nó: Aggregate×29, Append×16, CTE Scan×76, Function Scan×2, Hash×25, Hash Anti Join×1, Hash Join×18, Hash Left Join×1, Hash Right Anti Join×1, Hash Right Join×1, Hash Semi Join×3, HashAggregate×14, HashSetOp Except×10, Index Only Scan×2, Index Scan×6, Nested Loop×5, Nested Loop Left Join×1, Result×11, Seq Scan×25, Sort×8, Subquery Scan×20, Unique×1, Values Scan×7
- Seq Scan por relação: card×4, card_set×3, card_variant×5, card_variant_type×8, catalog_variant_import_row×2, pricing_source_card_identity×1, pricing_source_variant_mapping×2
- Index/Index Only Scan: card_pkey on card (Index Scan)×1, ix_card_variant_variant_type_id on card_variant (Index Only Scan)×1, ix_card_variant_variant_type_id on card_variant (Index Scan)×2, ix_pricing_source_card_identity_card_variant_type_id on pricing_source_card_identity (Index Only Scan)×1, uq_asset_source_code on asset_source (Index Scan)×2, uq_game_code on game (Index Scan)×1
- Function Scan: resolve_variant_mapping_scope×1, resolve_variant_row_axes×1
- nós de escrita/LockRows/JIT/tempo: nenhum
