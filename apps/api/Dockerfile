FROM hexpm/elixir:1.18.4-erlang-27.3.4.14-alpine-3.22.5 AS build

RUN apk add --no-cache build-base git

WORKDIR /app

COPY mix.exs mix.lock ./
COPY config config

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

RUN mix deps.get --only prod
RUN mix deps.compile

COPY lib lib
COPY priv priv

RUN mix compile
RUN mix release

FROM alpine:3.22.5 AS runtime

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

ENV HOME=/app

COPY --from=build /app/_build/prod/rel/milos_training ./

CMD ["./bin/milos_training", "start"]
