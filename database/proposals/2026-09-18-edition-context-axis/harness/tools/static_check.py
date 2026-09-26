# 2830H — verificação estática local dos envelopes (não conecta a banco). Uso: python3 tools/static_check.py
import re,sys,pathlib
H=pathlib.Path(__file__).resolve().parent.parent
def code(s):  # remove -- comments, keep strings
    out=[]
    for l in s.splitlines():
        i=l.find('--')
        out.append(l if i<0 else l[:i])
    return '\n'.join(out)
def nostr(c):
    c=re.sub(r"\$re\$.*?\$re\$","''",c,flags=re.S)
    return re.sub(r"'(?:[^']|'')*'","''",c)
res=[]
def chk(name,cond,detail=''):
    res.append((name,bool(cond),detail))
for f,exp,tag in [('2830H_E01_section1_structural.sql',['1.1','1.2','1.3','1.4','1.5','1.6','1.7','1.8','1.9','1.10','1.11','1.12'],'h2830_e01'),
                  ('2830H_E02_identity_terminal_D1_D5.sql',['D1','D2','D3','D4','D5'],'h2830_e02')]:
    s=(H/f).read_text(encoding='utf-8'); c=code(s); U=c.upper()
    chk(f+': 1 DO por arquivo', len(re.findall(r'\bDO\s+\$',c))==1)
    chk(f+': dollar-quote abre/fecha', c.count('$'+tag+'$')==2 and c.rstrip().endswith('$'+tag+'$;'))
    body=c.split('$'+tag+'$')[1]
    bodyns=nostr(body)
    stmts_outside=c.split('$'+tag+'$')[0].strip()
    chk(f+': nada executável fora do DO', stmts_outside.upper().strip()=='DO')
    for tok in [r'\bCOMMIT\b',r'\bROLLBACK\b',r'\bCREATE\b',r'\bALTER\b',r'\bDROP\b',r'\bTEMP\b',r'\bTEMPORARY\b',r'SET_CONFIG',r'\bSET\s+ROLE\b',r'\bSET\s+LOCAL\b',r'\bSET\s+SESSION\b',r'\bGRANT\b',r'\bREVOKE\b',r'\bTRUNCATE\b',r'\bDELETE\b',r'\bUPDATE\b',r'PG_SLEEP',r'DBLINK',r'\bNET\.',r'\bPERFORM\b',r'\bEXECUTE\b',r'RAISE\s+NOTICE',r'RAISE\s+WARNING',r'RAISE\s+INFO']:
        chk(f+f': proibido ausente {tok}', not re.search(tok,bodyns.upper()))
    cases=re.findall(r"v_case\s*:=\s*'([^']+)'",body)
    chk(f+': casos na ordem = esperado', cases==exp, str(cases))
    exp_arr=re.search(r"c_expected\s+CONSTANT\s+text\[\]\s*:=\s*ARRAY\[(.*?)\]",body,re.S).group(1)
    chk(f+': c_expected = esperado', re.findall(r"'([^']+)'",exp_arr)==exp)
    codes=set(re.findall(r"ERRCODE\s*=\s*'([A-Z0-9]{5})'",body))
    chk(f+': ERRCODEs só H283C/F/P', codes<= {'H283C','H283F','H283P'}, str(codes))
    chk(f+': H283P exatamente 1', len(re.findall(r"ERRCODE\s*=\s*'H283P'",body))==1)
    # H283P é o último RAISE do corpo
    last=[m.group(0) for m in re.finditer(r"ERRCODE\s*=\s*'H283[CFP]'",body)][-1]
    chk(f+': último sinal é H283P', "H283P" in last)
    # cada caso: 1 sinal H283C, 1 handler H283C, 1 handler H283F re-raise, 1 WHEN OTHERS convertendo
    blocks=re.split(r"v_case\s*:=\s*'[^']+'\s*;",body)[1:]
    for cid,b in zip(cases,blocks):
        b=b.split('v_case :=')[0]
        ok = (len(re.findall(r"ERRCODE\s*=\s*'H283C'",b))==1 and
              "WHEN SQLSTATE 'H283C'" in b and "WHEN SQLSTATE 'H283F' THEN RAISE;" in b and
              'v_done := v_done || v_case' in b)
        chk(f+f': caso {cid} estrutura de subtransação', ok)
        # negativos: todo "EXCEPTION WHEN OTHERS THEN v_got := true" deve ser seguido de checagem de sqlstate+constraint
        negs=len(re.findall(r'EXCEPTION WHEN OTHERS THEN\s+v_got := true;',b))
        sqlst=len(re.findall(r"v_state <> '(23514|23505)' OR v_con IS DISTINCT FROM '",b))
        if negs: chk(f+f': caso {cid} negativos={negs} com SQLSTATE+constraint', sqlst>=1 and 'IF NOT v_got' in b, f'negs={negs} checks={sqlst}')
    # BEGIN/END balance (END IF/LOOP excluídos)
    nb=len(re.findall(r'\bBEGIN\b',U)); ne=len(re.findall(r'\bEND\b(?!\s+(IF|LOOP))',U))
    chk(f+': BEGIN/END balanceados', nb==ne, f'{nb}/{ne}')
    n_if=len(re.findall(r'(?<!END )\bIF\b',U)); n_eif=len(re.findall(r'\bEND\s+IF\b',U))
    chk(f+': IF/END IF balanceados', n_if==n_eif, str(n_if)+'/'+str(n_eif))
    chk(f+': parênteses balanceados', nostr(c).count('(')==nostr(c).count(')'))
    chk(f+': aspas simples pares', c.count("'")%2==0)
    ins=re.findall(r'INSERT INTO [^;]*;',body,re.S)
    chk(f+f': INSERTs={len(ins)} todos com marcador', all('v_marker' in i for i in ins))
for f in ['2830H_E00_precheck_inventory.sql','2830H_E99_postcheck_residue.sql']:
    raw=re.sub(r"\$re\$.*?\$re\$","''",(H/f).read_text(encoding='utf-8'),flags=re.S)
    c=code(raw); U=nostr(c).upper()
    chk(f+': 1 statement', U.count(';')==1 and U.rstrip().endswith(';'))
    for tok in [r'\bINSERT\b',r'\bUPDATE\b',r'\bDELETE\b',r'\bCREATE\b',r'\bALTER\b',r'\bDROP\b',r'SET_CONFIG',r'\bSET\b',r'\bDO\b',r'\bTEMP\b']:
        chk(f+f': ausente {tok}', not re.search(tok,U))
    chk(f+': parênteses balanceados', nostr(c).count('(')==nostr(c).count(')'))

# ---------------------------------------------------------------------------
# CORRECTION-01: 1.12 com MAINTAIN; baselines E00/E99; P7
# ---------------------------------------------------------------------------
import json
PRIVS=['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']
e01=(H/'2830H_E01_section1_structural.sql').read_text(encoding='utf-8')
b112=code(e01).split("v_case := '1.12'")[1]
arrs=re.findall(r"unnest\(ARRAY\[([^\]]*)\]\)\s+AS\s+p\(priv\)",b112)
chk('1.12: 2 matrizes de privilégio', len(arrs)==2, str(len(arrs)))
chk('1.12: cada matriz = 8 privilégios PG17 (inclui MAINTAIN)', all(re.findall(r"'([A-Z]+)'",a)==PRIVS for a in arrs))
chk('1.12: anon e authenticated conferidos', "has_table_privilege('anon'" in b112 and "has_table_privilege('authenticated'" in b112)
e00=(H/'2830H_E00_precheck_inventory.sql').read_text(encoding='utf-8')
e99=(H/'2830H_E99_postcheck_residue.sql').read_text(encoding='utf-8')
def block(t,name):
    m=re.search(r'-- '+name+r':BEGIN\n(.*?)\n\s*-- '+name+r':END',t,re.S); return m.group(1) if m else None
for name in ['BASELINE-BUILDER','FREEZE-CANON']:
    a,b=block(e00,name),block(e99,name)
    chk(f'{name}: presente em E00 e E99', a is not None and b is not None)
    chk(f'{name}: idêntico byte a byte E00 x E99', a is not None and a==b)
canon_txt=re.search(r"SELECT '(\{.*?\})'::jsonb AS c",block(e00,'FREEZE-CANON') or '',re.S)
canon=json.loads(canon_txt.group(1)) if canon_txt else {}
chk('CANON: JSON válido', bool(canon))
req={'trait','profile','profile_trait','mapping','mapping_null_signature','card_variant','card_variant_ec_nonnull','staging_rows','staging_max_upd_utc','staging_status','operational_tristate','cancelled_without_key','lineage','jobs','jobs_by_status','jobs_max_upd_utc','jobs_in_flight'}
chk('CANON: chaves canônicas exatas', set(canon)==req, str(sorted(set(canon)^req)))
chk('CANON: staging_status soma = staging_rows', sum(canon.get('staging_status',{}).values())==canon.get('staging_rows'))
chk('CANON: jobs_by_status soma = jobs', sum(canon.get('jobs_by_status',{}).values())==canon.get('jobs'))
chk('CANON: sem chaves sem valor canônico (action_log, mapping_trait, marker_*)', not ({'action_log','mapping_trait','marker_trait','marker_profile','marker_mapping'} & set(canon)))
bkeys=set(re.findall(r"^\s*'([a-z_]+)',\s*",block(e00,'BASELINE-BUILDER') or '',re.M))
chk('BUILDER: toda chave canônica é produzida pelo builder', req<=bkeys, str(sorted(req-bkeys)))
g00=['g_freeze_canonical_equal','g_p7_all_classified','g_p7_no_external_or_dynamic','g_p7_search_path_safe','g_p7_identity_pinned','g_p7_lexically_supported','g_p7_no_unqualified_dml','g_p7_no_unresolved','g_p7_writes_in_scope','g_p7_closure_complete','g_no_rules','g_no_enabled_event_triggers','g_no_sequences_touched_now','g_rls_bypass','g_no_residue','g_no_concurrency','g_roles_1_12','g_pg17_maintain_privilege']
c00=code(e00)
for gname in g00: chk(f'E00: gate {gname} definido', re.search(r'AS\s+'+gname+r'\b',c00) is not None)
chk('E00: gate_pass agrega TODOS os g_* (bool_and + NULL=falha)', 'bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g))' in c00 and 'WHERE v IS NULL' in c00)
chk('E00: exporta d_baseline e d_baseline_md5', "'d_baseline'," in c00 and "'d_baseline_md5'," in c00 and 'md5(b::text)' in c00)
chk('E00: P7 fecho recursivo + classificação + UNCLASSIFIED', 'WITH RECURSIVE walk' in c00 and "'UNCLASSIFIED'" in e00 and 'p7_allowlist' in c00)
chk('E00: P7 raízes trigger+check+default+index', all(x in e00 for x in ["'trigger '","'check '","'default '","'index '"]))
c99=code(e99)
for ph in ['__E00_D_BASELINE__','__E00_D_BASELINE_MD5__','__E00_ROLE_SETTING_ROWS__']:
    chk(f'E99: marcador {ph} exatamente 1x no código', len(re.findall(r"'"+ph+r"'",c99))==1)
g99=['g_captured_present','g_captured_integrity','g_keys_identical','g_baseline_equal','g_freeze_canonical_equal','g_marker_absent','g_no_open_txn_others','g_lock_timeout_default','g_role_setting_unchanged']
for gname in g99: chk(f'E99: gate {gname} definido', re.search(r'AS\s+'+gname+r'\b',c99) is not None)
chk('E99: gate_pass agrega TODOS os g_* (bool_and + NULL=falha)', 'bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g))' in c99 and 'WHERE v IS NULL' in c99)
chk('E99: diff por chave sobre a UNIÃO das chaves', 'all_keys' in c99 and 'UNION' in c99 and 'd_diff' in c99)


# ---------------------------------------------------------------------------
# CORRECTION-02: MODELO DO P7 v3 (sem banco). Os padrões, palavras-chave,
# lista negra e pinos da allowlist são EXTRAÍDOS do próprio E00 — o modelo
# testa o mesmo texto que o PostgreSQL executará. Tradução ARE→Python:
# \m e \M → \b (fronteiras de palavra); o resto é sintaxe comum.
# ---------------------------------------------------------------------------
import hashlib
e00=(H/'2830H_E00_precheck_inventory.sql').read_text(encoding='utf-8')
REP=dict((n,v) for v,n in re.findall(r"\$re\$(.*?)\$re\$\s+AS\s+([a-z_]+)",e00,re.S))
chk('P7 modelo: 10 padrões extraídos do E00', set(REP)=={'lex','unsupported_raw','unsupported_lexed','lock_or_upsert','qcall','ucall','qdml','udml','signal_raw','dynamic_lexed'}, str(sorted(REP)))
def are(p): return p.replace(r'\m',r'\b').replace(r'\M',r'\b')
R={k:re.compile(are(v),re.I if k in ('lock_or_upsert','qdml','udml','signal_raw','dynamic_lexed') else 0) for k,v in REP.items()}
KW=set(re.findall(r"'([a-z_]+)'",re.search(r"p7_keywords\(word\) AS \(\s*SELECT unnest\(ARRAY\[(.*?)\]\)",e00,re.S).group(1)))
DENY=set(re.findall(r"\('([a-z_]+)'\)",re.search(r"p7_denylist\(proname\) AS \(\s*VALUES(.*?)\n\),",e00,re.S).group(1)))
ALLOW={}
for row in re.findall(r"^\s*\(('(?:internal|public|extensions)'.*?)\),?\s*$",re.search(r"p7_allowlist\(.*?\) AS \(\s*VALUES(.*?)\n\),",e00,re.S).group(1),re.M):
    f=[x.strip() for x in re.findall(r"ARRAY\['[^']*'\]|NULL::text\[\]|'(?:[^']|'')*'|true|false|NULL",row)]
    unq=lambda x: None if x in ('NULL','NULL::text[]') else (x=='true' if x in ('true','false') else (re.findall(r"'([^']*)'",x) if x.startswith('ARRAY') else x[1:-1].replace("''","'")))
    v=[unq(x) for x in f]
    ALLOW[(v[0],v[1],v[2])]=dict(lang=v[3],secdef=v[4],vol=v[5],config=v[6],md5=v[7],csym=v[8],ext=v[9],cls=v[10])
chk('P7 modelo: allowlist com 12 entradas pinadas', len(ALLOW)==12, str(len(ALLOW)))
# catálogo simulado (pg_catalog) — suficiente para os corpos reais e os controles
PGCAT_FN={'upper','lower','btrim','trim','regexp_replace','cardinality','now','coalesce','format','count','array_agg',
          'jsonb_typeof','jsonb_exists','gen_random_uuid','unnest','md5','pg_notify','set_config','pg_sleep','txid_current'}
PGCAT_TYPE={'text','uuid','int4','varchar','numeric','timestamp','bool'}
SCOPE={'public.card_edition_context_trait','public.card_edition_context_profile','public.card_edition_context_profile_trait',
       'public.card_edition_context_external_mapping','public.card_edition_context_external_mapping_trait'}
RELATIONS=SCOPE|{'public.card_variant','public.catalog_admin_action_log','public.catalog_variant_import_row'}
def p7_gate(fns, ext_members):
    """fns: dict fqkey->(nsp,name,idargs,lang,secdef,vol,config,prosrc). Retorna (pass, motivos)."""
    reasons=[]; procs={(f[0],f[1]) for f in fns.values()}|{('pg_catalog',n) for n in PGCAT_FN}
    for k,(nsp,name,ida,lang,secdef,vol,cfg,src) in fns.items():
        # classificação
        if nsp=='pg_catalog':
            cls='DENIED' if name in DENY else 'BUILTIN'
        else:
            a=ALLOW.get((nsp,name,ida))
            if a is None: cls='UNCLASSIFIED'
            elif (lang!=a['lang'] or secdef!=a['secdef'] or (a['vol'] is not None and vol!=a['vol'])
                  or (a['config'] is not None and cfg!=a['config'])
                  or (a['md5'] is not None and hashlib.md5(src.encode()).hexdigest()!=a['md5'])
                  or (a['csym'] is not None and src!=a['csym'])
                  or (a['ext'] is not None and k not in ext_members.get(a['ext'],set()))): cls='ALLOWLIST_MISMATCH'
            else: cls=a['cls']
        if cls in ('UNCLASSIFIED','DENIED'): reasons.append('g_p7_all_classified:'+k)
        if cls=='ALLOWLIST_MISMATCH': reasons.append('g_p7_identity_pinned:'+k)
        if lang in ('c','internal'): continue
        lexed=R['lex'].sub(' ',src)
        if nsp!='pg_catalog' and not (cfg is not None and sum(1 for c in cfg if c.startswith('search_path='))==1 and 'search_path=""' in cfg):
            reasons.append('g_p7_search_path_safe:'+k)
        if R['signal_raw'].search(src) or (lang=='plpgsql' and R['dynamic_lexed'].search(lexed)): reasons.append('g_p7_no_external_or_dynamic:'+k)
        if R['unsupported_raw'].search(src) or R['unsupported_lexed'].search(lexed): reasons.append('g_p7_lexically_supported:'+k)
        t=R['lock_or_upsert'].sub(' ',lexed)
        for m in R['qcall'].finditer(t):
            ref=(m.group(1).lower(),m.group(2).lower())
            if ref not in procs and '.'.join(ref) not in RELATIONS: reasons.append('g_p7_no_unresolved:'+k+'->'+'.'.join(ref))
        for m in R['ucall'].finditer(t):
            n=m.group(1).lower()
            if n in KW: continue
            if n in DENY or not (n in PGCAT_FN or n in PGCAT_TYPE): reasons.append('g_p7_no_unresolved:'+k+'->'+n)
        for m in R['qdml'].finditer(t):
            tgt=m.group(4).lower()+'.'+m.group(5).lower()
            if tgt not in RELATIONS or tgt not in SCOPE: reasons.append('g_p7_writes_in_scope:'+k+'->'+tgt)
        for m in R['udml'].finditer(t): reasons.append('g_p7_no_unqualified_dml:'+k+'->'+m.group(4))
    return (not reasons, reasons)
# corpos REAIS do repositório (mesma extração dos pinos)
REPO=H.parent.parent.parent
real={}
for f,nsp_default in [('proposals/2026-09-18-edition-context-axis/2206_create_edition_context_composition_guards.sql',None),
                      ('proposals/2026-09-18-edition-context-axis/2207_create_card_edition_context_external_mapping.sql',None),
                      ('schema/2095_create_normalize_external_catalog_value_function.sql',None)]:
    src=(REPO/f).read_text(encoding='utf-8')
    for m in re.finditer(r'CREATE OR REPLACE FUNCTION ([a-z_]+)\.([a-z_]+)\(([^)]*)\)(.*?)AS \$\$(.*?)\$\$;',src,re.S):
        nsp,name,args,hdr,body=m.groups()
        ida=' '.join(args.lower().split())
        lang=re.search(r'LANGUAGE (\w+)',hdr).group(1)
        vol='s' if 'STABLE' in hdr else ('i' if 'IMMUTABLE' in hdr else 'v')
        real[nsp+'.'+name]=(nsp,name,ida,lang,'SECURITY DEFINER' in hdr,vol,['search_path=""'],body)
real['extensions.unaccent(text)']=('extensions','unaccent','text','c',False,'s',None,'unaccent_dict')
real['extensions.unaccent(regdictionary, text)']=('extensions','unaccent','regdictionary, text','c',False,'s',None,'unaccent_dict')
EXT={'unaccent':{'extensions.unaccent(text)','extensions.unaccent(regdictionary, text)'}}
chk('P7 modelo: 12 funções reais carregadas', len(real)==12, str(len(real)))
ok,why=p7_gate(real,EXT)
chk('P7 CONTROLE POSITIVO: definições reais do repositório passam (sem falso STOP)', ok, '; '.join(why[:5]))
def body_with(extra): return '\nBEGIN\n'+extra+'\n    RETURN NEW;\nEND;\n'
EXPECT={
 'chamada NÃO qualificada a função desconhecida':'g_p7_no_unresolved',
 'chamada NÃO qualificada a builtin negado (pg_notify)':'g_p7_no_unresolved',
 'DML NÃO qualificado (UPDATE card_variant)':'g_p7_no_unqualified_dml',
 'DML NÃO qualificado (INSERT INTO audit_log)':'g_p7_no_unqualified_dml',
 'DML NÃO qualificado com ONLY (DELETE FROM ONLY t)':'g_p7_no_unqualified_dml',
 'DML qualificado FORA do escopo (public.card_variant)':'g_p7_writes_in_scope',
 'DML qualificado para relação inexistente (public.ghost)':'g_p7_writes_in_scope',
 'chamada qualificada NÃO resolvida (internal.ghost_fn)':'g_p7_no_unresolved',
 'função permitida pelo NOME com corpo alterado (md5)':'g_p7_identity_pinned',
 'função permitida pelo NOME com assinatura diferente':'g_p7_all_classified',
 'função permitida com SECURITY DEFINER divergente':'g_p7_identity_pinned',
 'função permitida com linguagem divergente':'g_p7_identity_pinned',
 'função C permitida com símbolo divergente':'g_p7_identity_pinned',
 'search_path ausente':'g_p7_search_path_safe',
 'search_path inseguro (public)':'g_p7_search_path_safe',
 'search_path duplicado':'g_p7_search_path_safe',
 'search_path com pg_temp':'g_p7_search_path_safe',
 'função não classificada alcançada':'g_p7_all_classified',
 'SQL dinâmico (EXECUTE)':'g_p7_no_external_or_dynamic',
 'E-string escondendo conteúdo':'g_p7_lexically_supported',
 'dollar-quote interno':'g_p7_lexically_supported',
 'identificador entre aspas duplas chamado':'g_p7_lexically_supported',
 'nome em três partes':'g_p7_lexically_supported',
 'espaço entre schema, ponto e função (x . f)':'g_p7_no_unresolved',
 'chamada aninhada não qualificada (f(g(x)))':'g_p7_no_unresolved',
 'sinal de efeito externo (net.http_post)':'g_p7_no_external_or_dynamic'}
def neg(label, fns):
    ok,why=p7_gate(fns,EXT); exp=EXPECT[label]
    chk('P7 CONTROLE NEGATIVO bloqueado: '+label+' [gate '+exp+']', (not ok) and any(w.startswith(exp+':') for w in why), 'motivos='+str(why[:3]))
    return why
base=dict(real)
def mut_body(fq, newbody):
    d=dict(base); t=list(d[fq]); t[7]=newbody; d[fq]=tuple(t); return d
evil=('internal','evil_fn','', 'plpgsql', True,'v',['search_path=""'], body_with('    PERFORM 1;'))
neg('chamada NÃO qualificada a função desconhecida', {**base,'x':('internal','x_trigger','','plpgsql',True,'v',['search_path=""'],body_with('    NEW.a := evil_fn(1);'))})
neg('chamada NÃO qualificada a builtin negado (pg_notify)', mut_body('internal.guard_edition_context_trait_active', body_with("    PERFORM pg_notify('c', 'x');")))
neg('DML NÃO qualificado (UPDATE card_variant)', mut_body('internal.guard_edition_context_trait_active', body_with('    UPDATE card_variant SET is_default = false;')))
neg('DML NÃO qualificado (INSERT INTO audit_log)', mut_body('internal.guard_edition_context_trait_active', body_with('    INSERT INTO audit_log (a) VALUES (1);')))
neg('DML NÃO qualificado com ONLY (DELETE FROM ONLY t)', mut_body('internal.guard_edition_context_trait_active', body_with('    DELETE FROM ONLY t WHERE true;')))
neg('DML qualificado FORA do escopo (public.card_variant)', mut_body('internal.guard_edition_context_trait_active', body_with('    UPDATE public.card_variant SET is_default = false;')))
neg('DML qualificado para relação inexistente (public.ghost)', mut_body('internal.guard_edition_context_trait_active', body_with('    DELETE FROM public.ghost;')))
neg('chamada qualificada NÃO resolvida (internal.ghost_fn)', mut_body('internal.guard_edition_context_trait_active', body_with('    PERFORM internal.ghost_fn(1);')))
neg('função permitida pelo NOME com corpo alterado (md5)', mut_body('internal.guard_edition_context_trait_active', real['internal.guard_edition_context_trait_active'][7].replace('RETURN NEW;','RETURN NULL;')))
d=dict(base); t=list(d['public.normalize_external_catalog_value']); t[2]='p_value text, p_extra text'; d['public.normalize_external_catalog_value']=tuple(t)
neg('função permitida pelo NOME com assinatura diferente', d)
d=dict(base); t=list(d['internal.seal_edition_context_composition']); t[4]=False; d['internal.seal_edition_context_composition']=tuple(t)
neg('função permitida com SECURITY DEFINER divergente', d)
d=dict(base); t=list(d['public.normalize_external_catalog_value']); t[3]='plpgsql'; d['public.normalize_external_catalog_value']=tuple(t)
neg('função permitida com linguagem divergente', d)
d=dict(base); t=list(d['extensions.unaccent(text)']); t[7]='evil_symbol'; d['extensions.unaccent(text)']=tuple(t)
neg('função C permitida com símbolo divergente', d)
neg('função C permitida fora da extensão', {k:v for k,v in base.items()} ) if False else None
ok_ext,_=p7_gate(base,{'unaccent':set()}); chk('P7 CONTROLE NEGATIVO bloqueado: função C permitida sem pertença à extensão', not ok_ext)
for label,cfg in [('search_path ausente',None),('search_path inseguro (public)',['search_path=public']),
                  ('search_path duplicado',['search_path=""','search_path=public']),('search_path com pg_temp',['search_path=pg_temp'])]:
    d=dict(base); t=list(d['internal.guard_edition_context_trait_active']); t[6]=cfg; d['internal.guard_edition_context_trait_active']=tuple(t)
    neg(label, d)
neg('função não classificada alcançada', {**base,'internal.evil_fn':evil})
neg('SQL dinâmico (EXECUTE)', mut_body('internal.guard_edition_context_trait_active', body_with("    EXECUTE 'SELECT 1';")))
neg('E-string escondendo conteúdo', mut_body('internal.guard_edition_context_trait_active', body_with("    NEW.a := E'x\\\\' ; evil_fn(1) ; ''';")))
neg('dollar-quote interno', mut_body('internal.guard_edition_context_trait_active', body_with("    NEW.a := $q$ x $q$;")))
neg('identificador entre aspas duplas chamado', mut_body('internal.guard_edition_context_trait_active', body_with('    PERFORM "evil"(1);')))
neg('nome em três partes', mut_body('internal.guard_edition_context_trait_active', body_with('    PERFORM db.internal.evil_fn(1);')))
neg('espaço entre schema, ponto e função (x . f)', mut_body('internal.guard_edition_context_trait_active', body_with('    PERFORM internal . evil_fn(1);')))
neg('chamada aninhada não qualificada (f(g(x)))', mut_body('internal.guard_edition_context_trait_active', body_with('    NEW.a := upper(evil_fn(1));')))
neg('sinal de efeito externo (net.http_post)', mut_body('internal.guard_edition_context_trait_active', body_with("    PERFORM net.http_post('u');")))
# controles positivos de NÃO-falso-STOP: comentário/literal/lock não são dependências
fine=body_with("    -- UPDATE que não é DML: evil_fn( update card_variant\n    /* INSERT INTO ghost (x) */\n    NEW.a := 'texto com evil_fn(1) e UPDATE card_variant';\n    PERFORM 1 FROM public.card_edition_context_trait t WHERE t.id = NEW.trait_id FOR UPDATE;")
d=mut_body('internal.guard_edition_context_trait_active', fine);
# ajusta o pino md5 do corpo modificado só neste controle positivo
key=('internal','guard_edition_context_trait_active',''); saved=dict(ALLOW[key]); ALLOW[key]['md5']=hashlib.md5(fine.encode()).hexdigest()
ok,why=p7_gate(d,EXT); ALLOW[key]=saved
chk('P7 CONTROLE POSITIVO: comentário, literal e FOR UPDATE não geram dependência', ok, '; '.join(why))


e99t=(H/'2830H_E99_postcheck_residue.sql').read_text(encoding='utf-8')
chk('E99: comentário declara TRÊS marcadores (não dois)', 'EXATAMENTE TRÊS marcadores' in e99t and 'EXATAMENTE dois' not in e99t)
chk('E99: md5 declarado como fidelidade da cópia, NÃO origem da rodada', 'NÃO' in e99t and 'prova de QUAL rodada' in e99t)
chk('E99: vinculação documental E00 → envelope → E99 explícita', 'VINCULAÇÃO DOCUMENTAL' in e99t and 'checked_at(E00) < submissão do envelope' in e99t)

bad=[r for r in res if not r[1]]
for n,ok,d in res: print(('PASS ' if ok else 'FAIL ')+n+(' '+d if d and not ok else ''))
print(f'TOTAL {len(res)} PASS {len(res)-len(bad)} FAIL {len(bad)}')
