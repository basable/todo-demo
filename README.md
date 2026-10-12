# todo-demo

A to-do app whose server is written entirely in COBOL.

## How it works

Banks still run on COBOL, and so does this to-do app. Everything behind the
page, from the TCP socket to the SQL, is fixed-format GnuCOBOL 3.2: twelve
programs and twelve copybooks, 4,565 lines of which 3,584 are code. The
browser side (`web/`) is the same HTML and JavaScript as before, and the API
answers it byte for byte as the Go server it replaced did, with one change for
a public demo: a title is kept to at most 64 bytes, cut between characters.

- **TODOSRV** is the main program. It calls the C library's `socket`, `bind`,
  `listen` and `accept` directly, handing them COBOL records laid out like the
  C structs they expect (the port sits in a `COMP-X` field, which stores
  numbers big-endian, the byte order the network wants). It answers one
  request at a time and routes it the way Go's `http.ServeMux` did.
- **HTTPRECV** and **HTTPSEND** speak HTTP/1.1: they read until the blank line
  and then exactly `Content-Length` bytes, refuse malformed requests with a
  400, and give every request a 10-second deadline, so a slow client cannot
  hold the server.
- **TODODB** holds every SQL statement, written inline as
  `EXEC SQL ... END-EXEC` with `:HOST-VARIABLES`. The Open COBOL ESQL
  preprocessor turns them into parameterised libpq calls, so a title can never
  become part of a query. Listing todos is a classic cursor:
  `OPEN`, `FETCH` until `SQLCODE` is 100, `CLOSE`.
- **JSONREAD** reads request bodies. COBOL has a `JSON PARSE` statement, but
  GnuCOBOL has not built it yet ("JSON PARSE is not implemented"), so this
  program walks the JSON byte by byte with its own stack of open brackets.
- **JSONTODO** writes the todos. GnuCOBOL's `JSON GENERATE` has no way to say
  `true` or `false` and cannot write a list, so the todos are written by hand.
  `JSON GENERATE` still writes every `{"error": "..."}` response.
- **UTF8TEXT**, **URLPATH**, **WEBFILES**, **UTCCLOCK**, **LOGLINE** and
  **ONSTOP** trim and count Unicode text, tidy URL paths, load `web/` at
  startup with ordinary COBOL file I/O, tell the time, write Go-style log lines,
  and end the process cleanly when Kubernetes sends SIGTERM.

On Basable the page itself is not served by the COBOL server: each deploy
uploads `web/` into the environment's public bucket (`Dockerfile.site`, the
`site-upload` Job in `k8s/`), the platform serves `/` from there, and the
HTTPRoute sends only `/api` to the server. The server still answers `web/`
itself when run on its own, as the test does.

No C, shell or other language is involved at runtime. The only foreign code is
what COBOL calls: the C library for sockets, libpq underneath the SQL
preprocessor, and json-c underneath `JSON GENERATE`.

## Build, run and test

Everything happens in Docker:

```sh
docker build -t todo-demo .     # compiles the COBOL; any warning fails the build
bash test/e2e.sh todo-demo      # starts PostgreSQL and the server, checks them with curl
```

The server reads `DATABASE_URL` (default
`postgres://postgres@localhost:5432/todos?sslmode=disable`) and `PORT`
(default `8080`). `.basable/verify.sh` runs the same two steps on every branch.
