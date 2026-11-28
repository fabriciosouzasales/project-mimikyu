# V1-13 · D-E3-2 — Autoria no histórico do fichário do titular (5398)

| Campo | Valor |
|---|---|
| **Rodada** | E4 — rodada de correção (2026-11-27), decisão do proprietário: corrigir a D-E3-2 |
| **Status** | **EXECUTADA NO LIVE / CANÔNICA (2026-11-27; 00:51:15Z de 2026-11-28)** pelo executor v1.4, run-20261128T005110Z, manifesto `bfb3c846…dbfc218`: PRE PASS, migration exit 0, POST PASS, barreira CLOSED. Cópia canônica: `database/schema/5398_owner_binder_history_author.sql` (idêntica do `begin;` ao `commit;`). Prova funcional no reteste da E4: o titular viu "por Kauã Sales" e "por Fabrício Sales" no histórico do fichário. |
| **Problema** | O titular não via quem fez cada ação no histórico do **fichário**. A 5269 (`get_my_binder_activity`) não devolve o autor; os participantes já veem o autor pela 5388. |

## Contrato

`public.get_my_binder_activity_actors(p_layout_key uuid, p_event_ids bigint[])` devolve `(event_id, actor_role, actor_display_name)`.

- **Aditiva:** a 5269 não muda.
- **Escopo da leitura:** a tela lê a página como antes e pede só o autor dos ids dessa página, com no máximo 50 ids e 50 linhas.
- **Isolamento:** só retorna eventos do **próprio** titular (`owner_user_id = auth.uid()`) e deste fichário. Ids de outra pessoa somem sem erro.
- **Papel:** `OWNER` (o próprio titular), `PARTICIPANT` (outra conta) ou `null` (legado). O nome mostrado é só o público (`display_name`, C-241). Nada de e-mail, username ou dado patrimonial.
- **Barreira 5389:** atrás de `v1_13_capability_open()`. Com a barreira fechada, não devolve nenhuma linha, e a tela segue sem autor, como hoje.
- **Segurança da função:** definer, STABLE, `search_path` vazio, EXECUTE só para `authenticated`.
- **Front:** `readBinderActivity` chama a nova função só com a configuração D1 ligada e junta a autoria pela `withActors`. Se ela falhar, o histórico aparece normalmente, só que sem autor.

## Artefatos

| Arquivo | Conteúdo |
|---|---|
| `5398_owner_binder_history_author.sql` | migration em transação única, com conferências de entrada e saída |
| `D_E3_2_5398_PRE_readonly.sql` / `D_E3_2_5398_POST_readonly.sql` | gates do executor v1.4 |
| `D_E3_2_5398_MANIFEST.txt` | PRE → 5398 → POST |
| `ROLLBACK_5398.sql` | remove só a função nova, conferida por md5 |
| `build_5398.py` / `static_check_5398.py` | gerador e verificação estática: 15/15, com 9/9 mutações detectadas |

Os sha256 saem do `build_5398.py`. O plano da consulta foi conferido no LIVE com `EXPLAIN`, sem ler dados: ela usa o índice `ix_bae_owner_layout_time`.

## Implantação

1. `-Simular` com o manifesto: PASS.
2. Autorização expressa do proprietário.
3. Execução pelo executor com a barreira CLOSED: PRE PASS, migration exit 0, POST PASS (run-20261128T005110Z).
4. Prova funcional no reteste da E4 (TEST aberto): PASS, confirmada pelo proprietário.
