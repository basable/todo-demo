# The end-to-end test client: curl and bash, plus the web/ files the server
# must send back byte for byte. Built from the repository root:
#   docker build -f test/Dockerfile .
FROM debian:13.7-slim
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY web/ /expected/web/
COPY test/cases.sh /cases.sh
ENTRYPOINT ["bash", "/cases.sh"]
