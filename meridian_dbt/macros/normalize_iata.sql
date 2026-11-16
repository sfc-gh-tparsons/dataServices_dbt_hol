{# Normalizes an IATA airport code: UPPER + TRIM + null if not 3 chars. #}
{% macro normalize_iata(col) %}
    CASE
      WHEN LENGTH(TRIM(UPPER({{ col }}))) = 3 THEN TRIM(UPPER({{ col }}))
      ELSE NULL
    END
{% endmacro %}
