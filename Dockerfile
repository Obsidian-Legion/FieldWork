ARG DEPENDENCIES=download
FROM ubuntu:24.04 AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl libgmp10 libtinfo6 zlib1g libnuma1 && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/unison
RUN curl -fsSL https://github.com/unisonweb/unison/releases/download/release/1.3.0/ucm-linux-x64.tar.gz -o /tmp/ucm.tar.gz \
    && echo '0c52e223746ba36029993f38c6774675a2d61ff01dfc75c463a6e3df7d6d433b  /tmp/ucm.tar.gz' | sha256sum -c - \
    && tar -xzf /tmp/ucm.tar.gz && rm /tmp/ucm.tar.gz
ENV PATH="/opt/unison:${PATH}" LANG=C.UTF-8

FROM runtime AS download
WORKDIR /build
COPY scripts/setup.md scripts/build.md ./scripts/
RUN mkdir -p .runtime && ucm -C .unison transcript.in-place scripts/setup.md
FROM runtime AS cached
WORKDIR /build
COPY --from=unison-codebase / ./.unison/
COPY scripts/build.md ./scripts/
RUN mkdir -p .runtime

FROM ${DEPENDENCIES} AS build
COPY src ./src
RUN ucm -c .unison transcript.in-place scripts/build.md

FROM runtime AS app
RUN useradd --create-home --uid 10001 fieldwork
WORKDIR /app
COPY --from=build /build/.runtime/fieldwork.uc ./fieldwork.uc
COPY ui ./ui
COPY content ./content
RUN mkdir data && chown fieldwork:fieldwork data
USER fieldwork
ENV FIELDWORK_BIND=0.0.0.0 FIELDWORK_AUTH=locked
EXPOSE 8787
CMD ["ucm", "run.compiled", "fieldwork.uc", "data", "8787"]
