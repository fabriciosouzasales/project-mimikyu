/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5231 - Bucket privado `binder-slot-image` + políticas por dono
              (P2-BINDER-CUSTOM-IMAGES-PROPOSAL-01)
Versão......: 1.1 (2026-10-23, AUDIT-CORRECTION-01: política DELETE movida
              para a 5232, que a cria protegendo arquivos vinculados)
              1.0 (2026-10-23)
Status......: PROPOSTA — NÃO EXECUTADA. Aplicar só com autorização de
              Fabrício, antes de 5232–5236.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

Objetivo: guardar a imagem personalizada que o colecionador coloca num
bolso vazio do Fichário Digital (C-198). Mesmo padrão da capa de coleção
(5176, LIVE), com três endurecimentos:

  1. Limites NO ARMAZENAMENTO (não só no navegador): 512 KB por arquivo;
     só image/webp e image/jpeg. A API do Storage recusa o resto antes de
     gravar. PNG/HEIC/GIF/SVG ficam fora: o navegador reencoda para
     WebP/JPEG antes de enviar, e o banco não aceita outra coisa.
  2. SEM política de UPDATE: arquivos são imutáveis. Substituir = enviar
     arquivo NOVO (caminho novo) e trocar o vínculo (5233). Um envio que
     falha nunca sobrescreve a imagem em uso.
  3. Teto de arquivos por usuário na política de INSERT
     (c_objects_cap = 550 = limite de 500 imagens vinculadas + 50 de folga
     para substituições em curso e envios abandonados ainda não limpos).
     Impede acumular arquivos sem vínculo para contornar o limite.
     Sob concorrência o teto pode ser excedido por poucos arquivos
     (leitura sem trava) — aceito: a folga existe para isso.

Pasta obrigatória: `<auth.uid()>/<layout_id>/<uuid>.(webp|jpg)`.
Esta migration cria SELECT e INSERT. A política DELETE nasce na 5232
(depois da tabela), porque precisa recusar a remoção de arquivo que esteja
VINCULADO a um bolso (AUDIT-CORRECTION-01). Até a 5232, nenhum usuário
apaga arquivos deste bucket (bucket novo, vazio).
As políticas exigem a primeira pasta = auth.uid(); ninguém lê, envia
ou apaga arquivo de outra pessoa. A segunda pasta (fichário) e o formato
completo do nome são conferidos pela RPC de vínculo (5233), como na 5178.
Sem `anon` em nenhuma política. Leitura só por URL assinada (o bucket é
privado; nenhuma URL pública existe).

Fichário compartilhado: todas as coleções participantes são do MESMO
usuário (5229, gatilho), então a pasta do usuário serve a todas.

Como validar: Query 5852, Seção 0 (estrutura, somente leitura).
Como reverter (só com o bucket vazio):
  drop policy binder_slot_image_select_own on storage.objects;
  drop policy binder_slot_image_insert_own on storage.objects;
  delete from storage.buckets where id = 'binder-slot-image';
================================================================
*/

begin;

do $pre$
begin
  if exists (select 1 from storage.buckets b where b.id = 'binder-slot-image') then
    raise exception 'PRECHECK 5231: bucket binder-slot-image já existe — conferir configuração antes';
  end if;
  if exists (select 1 from pg_policies p
             where p.schemaname = 'storage' and p.tablename = 'objects'
               and p.policyname like 'binder\_slot\_image\_%') then
    raise exception 'PRECHECK 5231: políticas binder_slot_image_* já existem';
  end if;
end;
$pre$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('binder-slot-image', 'binder-slot-image', false, 524288, array['image/webp', 'image/jpeg']);

create policy binder_slot_image_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'binder-slot-image'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy binder_slot_image_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'binder-slot-image'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(webp|jpg)$'
    and (
      select count(*)
      from storage.objects o
      where o.bucket_id = 'binder-slot-image'
        and o.name like (select auth.uid())::text || '/%'
    ) < 550
  );

commit;
