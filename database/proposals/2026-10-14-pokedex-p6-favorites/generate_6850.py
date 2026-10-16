#!/usr/bin/env python3
"""Gera 6850_dryrun_pokedex_species_favorite.sql a partir de 6850.template.sql e dos arquivos 6136/6137/6849 (sem acesso a banco). Uso: python3 generate_6850.py"""
import hashlib, sys
from pathlib import Path
D=str(Path(__file__).resolve().parent)+"/"
def rd(n): return open(D+n,encoding='utf-8').read()
s36=rd("6136_create_pokedex_species_favorite_table.sql")
s37=rd("6137_create_pokedex_species_favorite_functions.sql")
s49=rd("6849_validate_pokedex_species_favorite.sql")
def inner(s):
    a=s.index('\nbegin;\n')+len('\nbegin;\n'); b=s.rindex('\ncommit;\n')+1
    return s[a:b]
i36=inner(s36); i37=inner(s37)
st=s49.index('create or replace function pg_temp.p6_6849_validate')
f1=s49.index('$fn$'); f2=s49.index('$fn$',f1+4)
end=f2+len('$fn$;')
vfun=s49[st:end]
prosrc=s49[f1+4:f2]
H=lambda t: hashlib.sha256(t.replace('\r','').encode('utf-8')).hexdigest()
for tag,t in (('p6136',i36),('p6137',i37)):
    assert '$'+tag+'$' not in t
assert '$dry$' not in i36+i37+vfun
tpl=open(D+'6850.template.sql',encoding='utf-8').read()
out=(tpl.replace('@@VALIDATOR_FUNCTION@@',vfun)
        .replace('@@DDL_6136@@','$p6136$'+i36+'$p6136$')
        .replace('@@DDL_6137@@','$p6137$'+i37+'$p6137$')
        .replace('@@H6136@@',H(i36)).replace('@@H6137@@',H(i37)).replace('@@H6849@@',H(prosrc))
        .replace('@@F6136@@',hashlib.sha256(s36.encode()).hexdigest())
        .replace('@@F6137@@',hashlib.sha256(s37.encode()).hexdigest())
        .replace('@@F6849@@',hashlib.sha256(s49.encode()).hexdigest()))
assert '@@' not in out
open(D+"6850_dryrun_pokedex_species_favorite.sql",'w',encoding='utf-8',newline='').write(out)
print(H(i36),H(i37),H(prosrc))
