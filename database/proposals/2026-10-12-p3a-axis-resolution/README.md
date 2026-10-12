# P3a — Diagnóstico e resolução de Impressão e Contexto de Edição na importação

| Campo | Valor |
|---|---|
| **Status** | Queries 2271–2274 **propostas**. Ensaio transacional no LIVE (2026-10-12): `P3A-TEST PASS` (S1 S2 E1 P1 W1 N1 C1 G1 X1 K1 I1), tudo desfeito. Aplicação aguarda autorização. Interface (P3b) ainda não iniciada |
| **Mandato** | Fabrício, 2026-10-12: P3 aprovada em duas etapas; P3a = backend |
| **Normativo** | `docs/05b-cartas-e-raridade.md`, revisão 1.15 |

## Achado que motivou a P3

Um item de origem (`subtype`, `foil`, `stamp`) sem mapeamento de Impressão nem de Contexto **não** aparece como problema desses eixos: o resolvedor o deixa na sobra e a linha cai em NEEDS_REVIEW como **acabamento sem mapeamento**. A tela só oferecia mapear acabamento. A P3a dá ao administrador o diagnóstico por item e as operações para decidir o eixo.

## Arquivos

| Arquivo | O que é |
|---|---|
| `2271_admin_explain_catalog_variant_import_row.sql` | Diagnóstico de uma linha (só leitura): estado dos 3 eixos pelo resolvedor oficial e cada item de origem com status (`UNRECOGNIZED` sem presumir eixo) e eixos admitidos pelo campo |
| `2272_admin_preview_catalog_variant_import_axis_mapping.sql` | Prévia: executa a própria RPC de escrita (Impressão ou Contexto) num subbloco, lê o resultado de cada linha e desfaz tudo |
| `2273_admin_resolve_catalog_variant_import_edition_context_mapping.sql` | Seleção única das linhas atingidas, reconciliação A/B/C única para as RPCs novas, trava de conflito entre eixos, CHECKs do log e a RPC de Contexto (escopo Set ou global) |
| `2274_admin_create_card_edition_context_profile_with_backfill.sql` | Criação de perfil de Contexto com selo e reavaliação das linhas que ele passa a resolver |
| `2274_test_rollback.sql` | S1 S2 E1 P1 W1 N1 C1 G1 X1 K1 I1 sobre um job STAGED fictício. Termina sempre em `RAISE EXCEPTION`. Passou = `P3A-TEST PASS` |

## Decisões

- **Sem segundo algoritmo.** Estados vêm de `resolve_variant_row_axes`; acabamento, de `lookup_variant_type_for_row`; a prévia roda a RPC real e reverte.
- **Escopos.** Impressão é sempre global (a tabela não tem escopo de Set). Contexto: `SOURCE_SET` (padrão, external_set_id oficial do Card Set) ou `GLOBAL`; o específico do Set prevalece sobre o global (mesma precedência do resolvedor). Mapeamentos de Contexto em Sets diferentes não conflitam. Um global novo não substitui específicos e não atinge os Sets que os têm.
- **Log.** A 2273 amplia os três CHECKs do log (tipo de entidade, ação e par ação×entidade); o de tipo de entidade faltava na primeira versão e foi detectado antes do ensaio.
- **Conflito entre eixos.** O mesmo item nunca fica ativo em Impressão e em Contexto: Impressão é global e avaliada antes, então a sobreposição é sempre efetiva. Trava na tabela (SQLSTATE `MV002`) + mensagem legível na RPC + item `conflicts` na prévia. LIVE hoje: 0 sobreposições.
- **Histórico.** Substituir = aposentar o ativo do mesmo escopo e criar outro (a tabela proíbe reativar). Perfis são imutáveis após o selo.
- **Fora do escopo.** Criar características; alterar as RPCs existentes de Impressão e de acabamento.

## Sequência mínima no LIVE (aguardando autorização)

1. **Ensaio (desfeito):** 2271 + 2272 + 2273 + 2274 + `2274_test_rollback.sql` num único envio. Esperado `P3A-TEST PASS`; depois conferir que nenhuma das 4 funções existe.
2. **Aplicação:** 2271, 2272, 2273, 2274, nessa ordem, cada uma com o "Como validar" do cabeçalho.
3. **Postcheck:** contagens de mapeamentos (Impressão 24, Contexto 152), perfis de Contexto (179), variantes e linhas de importação iguais ao pré.
