#!/bin/sh

# Script based off of: https://github.com/LukeMathWalker/zero-to-production/blob/main/scripts/init_db.sh
# (from Zero to Production)

usage() {
    echo "$0 path-to-compose-conf path-to-env"
}

if [ -z "${1}" ]; then
    COMPOSE_CONF="containers/postgres/compose.yaml"
    echo "Defaulting to ${COMPOSE_CONF}"
else
    COMPOSE_CONF="${1}"
fi

if [ -z "${2}" ]; then
    ENV_PATH="$(dirname ${0})/.env"
    echo "Defaulting to ${ENV_PATH}"
else
    ENV_PATH="${2}"
fi

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
if ! [ -e "${ENV_PATH}" ]; then
    printf "Missing: \".env\""
    printf "You need an environment file to pass to postgres"
    usage
    exit 1
fi

if ! [ -e "${COMPOSE_CONF}" ]; then
    printf "Missing a Docker Compose configuration file"
    usage
    exit 1
fi

# Source .env for pg_isready
. "${ENV_PATH}"

# Launch docker and detach so that it runs in the background
if ! docker compose -f "${COMPOSE_CONF}" --env-file "${ENV_PATH}" up --detach; then
    echo "Unable to start postgres container via Docker"
    printf "\tCompose path: %s\n" "${COMPOSE_CONF}"
    exit 1
fi

until pg_isready -d "${DATABASE_URL}"; do
    echo "Waiting for postgres server to be ready (${PGHOST}:${PGPORT})"
    sleep 1
done

echo "Running sqlx migrations"
if ! sqlx database create; then
    echo "Migrations: Failed to create database"
    docker compose -f "${COMPOSE_CONF}" --env-file .env down
    exit 1
fi

if ! sqlx migrate run; then
    echo "Migrations: Failed to run migrations"
    docker compose -f "${COMPOSE_CONF}" --env-file .env down
    exit 1
fi

# Server started; tail logs
echo "Postgres server is ready"
docker compose -f "${COMPOSE_CONF}" logs --follow
