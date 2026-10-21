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

# ADR-157: post photos (ImageMagick with JPEG, PNG, WebP and HEIC coders)
# and short videos (ffmpeg with libx264 and AAC) are processed in the API.
RUN apk add --no-cache imagemagick imagemagick-jpeg imagemagick-webp imagemagick-heic ffmpeg

WORKDIR /app

ENV HOME=/app

COPY --from=build /app/_build/prod/rel/palee ./

# The deployed manifests still start `bin/milos_training` and run
# `MilosTraining.Release.migrate()` (TD-109). Keep that entry point until the
# infrastructure rename lands, then drop this link and LegacyReleaseEntrypoint.
RUN ln -s palee bin/milos_training

CMD ["./bin/palee", "start"]
