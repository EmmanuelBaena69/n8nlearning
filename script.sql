CREATE TABLE kpi_historico (
  id SERIAL PRIMARY KEY,
  nombre_kpi varchar(100) NOT null,
  valor_kpi numeric(10, 2) NOT null,
  status varchar(10) check(status in ('OK', 'ALERTA')) NOT null,
  umbral numeric(10, 2) NOT null,
  fecha_hora timestamp default now()
);

CREATE TABLE IF NOT EXISTS interaccion_agente (
    id          SERIAL PRIMARY KEY,
    question    text        NOT null,
    response    text        NOT null,
    exec_status varchar(10) NOT null,
    timestamp   timestamp NOT null default now()
);
