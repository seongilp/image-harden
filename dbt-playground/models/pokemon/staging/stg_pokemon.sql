-- Pokemon 800마리 스탯 CSV을 URL에서 직접 읽기 (httpfs)
select
    "#"          as pokedex_no,
    "Name"       as name,
    "Type 1"     as type1,
    nullif("Type 2", '') as type2,
    "Total"      as total,
    "HP"         as hp,
    "Attack"     as attack,
    "Defense"    as defense,
    "Sp. Atk"    as sp_atk,
    "Sp. Def"    as sp_def,
    "Speed"      as speed,
    "Generation" as generation,
    "Legendary"  as is_legendary
from read_csv_auto('https://gist.githubusercontent.com/armgilles/194bcff35001e7eb53a2a8b441e8b2c6/raw/92200bc0a673d5ce2110aaad4544ed6c4010f687/pokemon.csv')
