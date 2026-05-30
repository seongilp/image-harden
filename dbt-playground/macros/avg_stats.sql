{# 포켓몬 종족값 평균 컬럼을 한 번에 생성하는 매크로.
   여러 마트에서 반복되던 round(avg(...)) 패턴을 한 곳으로. #}
{% macro avg_stats(include_spatk=false) %}
    round(avg(total), 1)    as avg_total,
    round(avg(attack), 1)   as avg_attack,
    round(avg(defense), 1)  as avg_defense,
    round(avg(speed), 1)    as avg_speed
    {%- if include_spatk %},
    round(avg(sp_atk), 1)   as avg_sp_atk
    {%- endif %}
{% endmacro %}
