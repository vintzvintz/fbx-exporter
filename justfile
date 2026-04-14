# Stack freebox — Freebox exporter Prometheus

deploy:
    docker compose build
    docker compose up -d

restart:
    docker compose restart

stop:
    docker compose down

logs *ARGS:
    docker compose logs {{ARGS}}
