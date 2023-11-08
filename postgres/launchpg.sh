#!/bin/sh

# Script based off of: https://github.com/LukeMathWalker/zero-to-production/blob/main/scripts/init_db.sh
# (from Zero to Production)

COMPOSE_CONF="containers/postgres/compose.yaml"

if ! [ -x "$(command -v pg_isready)" ]; then
    printf "Missing: \"pg_isready\""
    printf "Install the postgres package for your distro"
    exit 1
fi

# sqlx for migrations
if ! [ -x "$(command -v sqlx)" ]; then
    printf "Missing: \"sqlx\""
    printf "Install Rust/cargo with:"
    printf "\tcargo install sqlx-cli --no-default-features --features rustls,postgres"
fi

# .env is required or else postgres doesn't launch
if ! [ -e .env ]; then
    printf "Missing: \".env\""
    printf "You need an environment file to pass to postgres"
    exit 1
fi

# Source .env for pg_isready
. ./.env

# Launch docker and detach so that it runs in the background
docker compose -f "${COMPOSE_CONF}" --env-file .env up --detach

if [ "$?" ]; then
    echo "Unable to start postgres container via Docker"
    printf "\tCompose path: %s\n" ${COMPOSE_CONF}
    exit 1
fi

until pg_isready -d "${DATABASE_URL}"; do
    echo "Waiting for postgres server to be ready (${PGHOST}:${PGPORT})"
    sleep 1
done

echo "Running sqlx migrations"
sqlx database create
if [ "$?" ]; then
    echo "Migrations: Failed to create database"
    docker compose -f "${COMPOSE_CONF}" --env-file .env down
    exit 1
fi

sqlx migrate run
if [ "$?" ]; then
    echo "Migrations: Failed to run migrations"
    docker compose -f "${COMPOSE_CONF}" --env-file .env down
    exit 1
fi

echo "Postgres server is ready"

docker compose -f "${COMPOSE_CONF}" logs
