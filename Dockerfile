ARG ELIXIR=1.12.3
ARG OTP=24.0.5
ARG ALPINE=3.14.0

FROM hexpm/elixir:$ELIXIR-erlang-$OTP-alpine-$ALPINE as builder
COPY mix.* /app/
COPY lib /app/lib
WORKDIR /app
RUN mix local.hex --force
RUN mix local.rebar --force
RUN mix deps.get
RUN MIX_ENV=prod mix release

FROM alpine:$ALPINE AS app
RUN apk --no-cache add ncurses-libs
WORKDIR /
COPY --from=builder /app/_build/prod/rel/prometheus_ecs_discovery /
CMD /bin/prometheus_ecs_discovery start
