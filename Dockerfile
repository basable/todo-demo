# syntax=docker/dockerfile:1
# check=skip=FromPlatformFlagConstDisallowed
# The image is linux/amd64 on every builder, so FROM names the platform on
# purpose; the check above would otherwise warn about exactly that.

# Build stage: GnuCOBOL 3.2 (Debian's package, built with JSON support) and
# Open COBOL ESQL, the preprocessor that turns EXEC SQL into calls to libpq.
FROM --platform=linux/amd64 debian:13.7-slim AS build
ARG OCESQL_VERSION=1.4
ARG OCESQL_SHA256=c0310473aa38ea2921ae4c45ff2463be9cd874efd488d23cd8b0f687644060fd
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      gnucobol3 libpq-dev build-essential autoconf automake libtool pkgconf \
      flex bison curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/ocesql
RUN curl -fsSL -o ocesql.tar.gz \
      "https://github.com/opensourcecobol/Open-COBOL-ESQL/archive/refs/tags/v${OCESQL_VERSION}.tar.gz" \
 && echo "${OCESQL_SHA256}  ocesql.tar.gz" | sha256sum -c - \
 && tar -xzf ocesql.tar.gz --strip-components=1 \
 && autoreconf -fi \
 && ./configure --prefix=/usr/local \
 && make -j"$(nproc)" \
 && make install

WORKDIR /src
COPY copybooks/ copybooks/
COPY cobol/ cobol/
# ocesql rewrites the EXEC SQL in TODODB; cobc compiles every program and
# links them into one executable. -fstatic-call resolves each CALL at link
# time, which is what lets COBOL call socket(), recv() and friends in libc.
# Any warning fails the build, including text past column 72, which fixed-
# format COBOL would otherwise drop without a word.
RUN mkdir -p /out \
 && ocesql cobol/TODODB.cbl /out/TODODB.cob \
 && cobc -x -O2 -Wall -Wcolumn-overflow -Werror -fstatic-call \
      -I copybooks -I /usr/local/share/open-cobol-esql/copy \
      -o /out/todo-server \
      cobol/TODOSRV.cbl cobol/HTTPRECV.cbl cobol/HTTPSEND.cbl \
      /out/TODODB.cob cobol/JSONREAD.cbl cobol/JSONTODO.cbl \
      cobol/WEBFILES.cbl cobol/URLPATH.cbl cobol/UTF8TEXT.cbl \
      cobol/UTCCLOCK.cbl cobol/LOGLINE.cbl cobol/ONSTOP.cbl \
      -locesql

# Runtime stage: the COBOL runtime library, libpq and the ESQL runtime.
FROM --platform=linux/amd64 debian:13.7-slim
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libcob4t64 libpq5 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /usr/local/lib/libocesql.so.0.1.0 /usr/local/lib/
RUN ln -s libocesql.so.0.1.0 /usr/local/lib/libocesql.so.0 && ldconfig
WORKDIR /app
COPY --from=build /out/todo-server /app/todo-server
COPY web/ /app/web/
# The cluster enforces the restricted Pod Security Standard: a numeric,
# non-root user.
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/app/todo-server"]
