/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5330 - Leitura do logo ATUAL de Card Set pelo visitante (anon)
Versão......: 1.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (V1-12, autorização
              expressa do proprietário; ledger 20261030203139 `5330_create_card_set_logo_public_read_policy`). Aplicada no LIVE DEPOIS da 5331 (ordem real do ledger: 5325→5329, 5331, 5330).
              Idêntica ao arquivo de database/proposals/2026-10-30-card-set-logo-public-read/
              (só este bloco Status difere); texto do ledger ≡ corpo após o cabeçalho (md5).
              Validação: 5864 7/7 PASS (200/200 logos atuais; 3 substituídos negados), resíduo zero.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Contexto:
A 5174 liberou SELECT do bucket privado `card-set-logo` para
`authenticated`. O visitante da vitrine pública (`/fichario/[id]`, papel
anon) não consegue assinar a URL do logo do Set → a capa cai na
identidade tipográfica. Logo de Set é conteúdo de catálogo, não dado de
usuário.

Menor escopo seguro (mais estreito que a 5174):
- só SELECT, só `anon`, só bucket `card-set-logo`;
- só o arquivo que é o logo ATUAL de algum Card Set
  (`card_set.logo_storage_path`). Envios antigos/substituídos (hoje 3 dos
  203 objetos) e qualquer caminho inventado continuam negados — também na
  listagem;
- `card_set` é admin-only por RLS; a checagem passa por função
  SECURITY DEFINER que devolve só booleano (EXECUTE para anon, exigido
  pela avaliação da política).

Não muda: políticas de `authenticated` e de administrador; escrita
(INSERT/UPDATE/DELETE) segue admin-only; bucket continua privado (URLs
assinadas, nunca URL pública); `expansion-logo` e demais buckets intactos;
frontend não muda (a vitrine já pede a URL assinada com a sessão anon).

Custo: card_set tem ~200 linhas; avaliação por objeto. Desprezível.
Como validar: 5864.
Reversão: DROP POLICY card_set_logo_public_current_select ON storage.objects;
          DROP FUNCTION public.card_set_logo_is_current(text);
================================================================
*/

CREATE OR REPLACE FUNCTION public.card_set_logo_is_current(p_name TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
COST 1000
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.card_set cs
        WHERE cs.logo_storage_path = p_name
    );
$$;

COMMENT ON FUNCTION public.card_set_logo_is_current(TEXT) IS
  'Query 5330: o objeto do bucket card-set-logo é o logo atual de algum Card Set? Usada só pela política de leitura anon card_set_logo_public_current_select.';

REVOKE ALL ON FUNCTION public.card_set_logo_is_current(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.card_set_logo_is_current(TEXT) TO anon, authenticated;

CREATE POLICY card_set_logo_public_current_select
  ON storage.objects
  FOR SELECT
  TO anon
  USING (
    bucket_id = 'card-set-logo'
    AND public.card_set_logo_is_current(name)
  );
