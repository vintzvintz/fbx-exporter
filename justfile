# Stack freebox — Freebox exporter Prometheus

status:
    docker compose ps

deploy:
    docker compose build
    docker compose up -d

restart:
    docker compose restart

stop:
    docker compose down

logs *ARGS:
    docker compose logs {{ARGS}}
