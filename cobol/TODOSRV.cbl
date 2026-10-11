      *================================================================*
      * TODOSRV - THE TODO SERVER. THIS IS THE MAIN PROGRAM.           *
      *                                                                *
      * IT CONNECTS TO POSTGRESQL, CREATES THE TABLE, LOADS WEB/, AND  *
      * THEN ANSWERS HTTP REQUESTS ONE AT A TIME, FOREVER:             *
      *                                                                *
      *   GET    /health          "OK"                                 *
      *   GET    /api/todos       EVERY TODO, OLDEST FIRST             *
      *   POST   /api/todos       {"title": "..."} MAKES A NEW ONE,    *
      *                           ITS TITLE CUT TO 64 BYTES (TITLELIM) *
      *   PATCH  /api/todos/{ID}  {"done": true} TICKS ONE OFF         *
      *   DELETE /api/todos/{ID}  REMOVES ONE                          *
      *   GET    ANYTHING ELSE    A FILE FROM WEB/, OR 404             *
      *                                                                *
      * IT REPLACES MAIN.GO AND HANDLERS.GO; THE OTHER PROGRAMS DO THE *
      * DETAILED WORK:                                                 *
      *   HTTPRECV  READS A REQUEST        HTTPSEND  WRITES A RESPONSE *
      *   TODODB    ALL THE SQL            JSONREAD  READS JSON        *
      *   JSONTODO  WRITES TODOS AS JSON   WEBFILES  LOADS WEB/        *
      *   URLPATH   TIDIES URL PATHS       UTF8TEXT  TRIMS AND COUNTS  *
      *   UTCCLOCK  TELLS THE TIME         LOGLINE   WRITES THE LOG    *
      *   ONSTOP    ENDS THE PROCESS WHEN KUBERNETES STOPS THE POD     *
      *                                                                *
      * A COBOL PROGRAM HAS FOUR DIVISIONS: IDENTIFICATION (ITS NAME), *
      * ENVIRONMENT (THE MACHINE AND FILES IT USES), DATA (EVERY       *
      * VARIABLE, DECLARED UP FRONT WITH ITS EXACT SIZE) AND PROCEDURE *
      * (THE CODE, IN NAMED PARAGRAPHS THAT "PERFORM" RUNS).           *
      *================================================================*
       IDENTIFICATION DIVISION.
       PROGRAM-ID. TODOSRV.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. LINUX-X86-64.
       OBJECT-COMPUTER. LINUX-X86-64.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
      *    THE RECORDS SHARED WITH THE OTHER PROGRAMS (SEE COPYBOOKS/).
       COPY HTTPCONN.
       COPY HTTPREQ.
       COPY HTTPRSP.
       COPY DBREQ.
       COPY TODOREC.
       COPY JSONBODY.
       COPY JSONOUT.
       COPY UTF8WORK.
       COPY URLWORK.
       COPY WEBTABLE.
       COPY TITLELIM.

      *----------------------------------------------------------------*
      * THE LISTENING SOCKET.                                          *
      *----------------------------------------------------------------*
      *    CONSTANTS FROM THE C HEADER FILES (SYS/SOCKET.H AND FRIENDS).
       01  AF-INET                     BINARY-LONG VALUE 2.
       01  SOCK-STREAM                 BINARY-LONG VALUE 1.
       01  SOL-SOCKET                  BINARY-LONG VALUE 1.
       01  SO-REUSEADDR                BINARY-LONG VALUE 2.
       01  SO-SNDTIMEO                 BINARY-LONG VALUE 21.
       01  WS-BACKLOG                  BINARY-LONG VALUE 128.
       01  WS-OPTION-ON                BINARY-LONG VALUE 1.
       01  WS-OPTION-SIZE              BINARY-LONG VALUE 4.
       01  WS-ADDRESS-SIZE             BINARY-LONG VALUE 16.
       01  WS-TIMEVAL-SIZE             BINARY-LONG VALUE 16.

      *    A C "STRUCT SOCKADDR_IN": WHERE TO LISTEN. THE FAMILY IS IN
      *    THE MACHINE'S OWN BYTE ORDER (BINARY-SHORT), BUT THE PORT
      *    MUST BE BIG-ENDIAN, "NETWORK BYTE ORDER". COMP-X STORES A
      *    NUMBER BIG-ENDIAN, SO MOVING THE PORT INTO IT IS ENOUGH.
      *    LOW-VALUES (ALL ZERO BYTES) AS THE ADDRESS MEANS 0.0.0.0:
      *    EVERY NETWORK INTERFACE.
       01  WS-SOCKET-ADDRESS.
           05  SIN-FAMILY              BINARY-SHORT UNSIGNED VALUE 2.
           05  SIN-PORT                PIC X(2) COMP-X.
           05  SIN-ADDRESS             PIC X(4) VALUE LOW-VALUES.
           05  SIN-ZERO                PIC X(8) VALUE LOW-VALUES.

      *    A CLIENT THAT STOPS READING ITS ANSWER FOR 10 SECONDS IS
      *    GIVEN UP ON, LIKE ONE THAT STOPS SENDING ITS REQUEST.
       01  WS-SEND-TIMEOUT.
           05  FILLER                  BINARY-DOUBLE VALUE 10.
           05  FILLER                  BINARY-DOUBLE VALUE 0.

       01  WS-LISTEN-SOCKET            BINARY-LONG.
       01  WS-RC                       BINARY-LONG.
       01  WS-PORT-TEXT                PIC X(16).
       01  WS-PORT-LENGTH              BINARY-LONG.
       01  WS-PORT-NUMBER              PIC 9(5).

      *    SIGNALS: THE NUMBERS LINUX USES FOR "PLEASE STOP". A
      *    PROGRAM-POINTER HOLDS THE ADDRESS OF A PROGRAM.
       01  SIGINT                      BINARY-LONG VALUE 2.
       01  SIGTERM                     BINARY-LONG VALUE 15.
       01  WS-STOP-HANDLER             USAGE PROGRAM-POINTER.
       01  WS-PREVIOUS-HANDLER         USAGE PROGRAM-POINTER.

      *    NOTHING EVER SETS SERVER-STOPPING: THE SERVER RUNS UNTIL
      *    THE PROCESS IS STOPPED, AND ONSTOP ENDS IT THEN.
       01  WS-SERVER-STATE             PIC X VALUE 'R'.
           88  SERVER-RUNNING          VALUE 'R'.
           88  SERVER-STOPPING         VALUE 'S'.

      *    WHAT HTTPRECV IS ASKED TO READ.
       01  WS-READ-HEAD                PIC X(4) VALUE 'HEAD'.
       01  WS-READ-BODY                PIC X(4) VALUE 'BODY'.

      *----------------------------------------------------------------*
      * ROUTING.                                                       *
      *----------------------------------------------------------------*
       01  WS-TRAILING-SLASH           PIC X.
           88  HAS-TRAILING-SLASH      VALUE 'Y'.
       01  WS-PATH-END                 BINARY-LONG.
       01  WS-SEGMENT-COUNT            BINARY-LONG.
       01  WS-SEGMENTS.
           05  WS-SEGMENT              OCCURS 4 TIMES.
               10  WS-SEGMENT-LENGTH   BINARY-LONG.
               10  WS-SEGMENT-TEXT     PIC X(8200).
       01  WS-DECODED-SEGMENTS.
           05  WS-DECODED              OCCURS 3 TIMES.
               10  WS-DECODED-LENGTH   BINARY-LONG.
               10  WS-DECODED-TEXT     PIC X(8200).
       01  WS-SEGMENT-NUMBER           BINARY-LONG.
       01  WS-ROUTE                    PIC X.
           88  ROUTE-HEALTH            VALUE 'H'.
           88  ROUTE-TODO-LIST         VALUE 'L'.
           88  ROUTE-ONE-TODO          VALUE 'O'.
           88  ROUTE-WEB-FILES         VALUE 'W'.

      *    REDIRECTS.
       01  WS-INDEX                    BINARY-LONG.
       01  WS-BYTE-VALUE               BINARY-CHAR UNSIGNED.
       01  WS-BYTE REDEFINES WS-BYTE-VALUE PIC X.
      *        WHAT GO LEAVES UNESCAPED IN THE PATH OF A REDIRECT.
           88  IS-PATH-SAFE            VALUES 'A' THRU 'Z'
                                              'a' THRU 'z'
                                              '0' THRU '9'
                                              '-' '_' '.' '~' '$' '&'
                                              '+' ',' '/' ':' ';' '='
                                              '@'.
       01  WS-UPPER-HEX                PIC X(16)
           VALUE '0123456789ABCDEF'.
       01  WS-LOWER-HEX                PIC X(16)
           VALUE '0123456789abcdef'.
       01  WS-HEX-CASE                 PIC X.
           88  HEX-IN-UPPER-CASE       VALUE 'U'.
           88  HEX-IN-LOWER-CASE       VALUE 'L'.
       01  WS-HIGH-NIBBLE              BINARY-LONG.
       01  WS-LOW-NIBBLE               BINARY-LONG.
       01  WS-PIECE                    PIC X(8).
       01  WS-PIECE-LENGTH             BINARY-LONG.
       01  WS-LOCATION-PATH-LENGTH     BINARY-LONG.

      *    THE WEB FILE BEING ASKED FOR.
       01  WS-WEB-URL                  PIC X(8200).
       01  WS-WEB-URL-LENGTH           BINARY-LONG.
       01  WS-WEB-NAME                 PIC X(8200).
       01  WS-WEB-NAME-LENGTH          BINARY-LONG.
       01  WS-BASE-START               BINARY-LONG.
       01  WS-FILE-NUMBER              BINARY-LONG.
       01  WS-WEB-ERROR                PIC X(200).

      *    THE {ID} IN /API/TODOS/{ID}.
       01  WS-ID-STATE                 PIC X.
           88  ID-IS-VALID             VALUE 'Y'.
           88  ID-IS-INVALID           VALUE 'N'.
       01  WS-ID-FIRST                 BINARY-LONG.
       01  WS-ID-LENGTH                BINARY-LONG.
       01  WS-ID-NUMBER                PIC 9(19).

      *    A JSON ERROR BODY, {"error":"..."}. THIS ONE SHAPE IS WITHIN
      *    REACH OF JSON GENERATE: IT TURNS THE RECORD BELOW INTO JSON,
      *    WITH "NAME ... IS 'error'" CHOOSING THE KEY.
       01  WS-ERROR-TEXT               PIC X(40).
       01  WS-ERROR-RECORD.
           05  WS-ERROR-MESSAGE        PIC X(40).
       01  WS-ERROR-JSON               PIC X(200).
       01  WS-ERROR-JSON-LENGTH        BINARY-LONG.

       01  WS-NUL-COUNT                BINARY-LONG.
       01  WS-LOG-TEXT                 PIC X(1024).
       01  WS-JSON-CODE-SHOWN          PIC -(9)9.

       PROCEDURE DIVISION.
       0000-MAIN.
           PERFORM 1000-START-UP
           PERFORM 2000-SERVE-ONE-CLIENT UNTIL SERVER-STOPPING
           STOP RUN.

      *================================================================*
      * 1000: START-UP, IN THE ORDER MAIN.GO DID IT. ANY FAILURE HERE  *
      * IS LOGGED AND ENDS THE PROGRAM WITH EXIT CODE 1.               *
      *================================================================*
       1000-START-UP.
           PERFORM 1050-CATCH-STOP-SIGNALS

           SET DB-FN-CONNECT TO TRUE
           CALL 'TODODB' USING DB-REQUEST TODO-RECORD
           IF NOT DB-OK
               STRING 'database: ' DB-MESSAGE
                   DELIMITED BY SIZE INTO WS-LOG-TEXT
               END-STRING
               PERFORM 9900-STOP-WITH-ERROR
           END-IF

           SET DB-FN-MIGRATE TO TRUE
           CALL 'TODODB' USING DB-REQUEST TODO-RECORD
           IF NOT DB-OK
               STRING 'migrate: ' DB-MESSAGE
                   DELIMITED BY SIZE INTO WS-LOG-TEXT
               END-STRING
               PERFORM 9900-STOP-WITH-ERROR
           END-IF

           CALL 'WEBFILES' USING WEB-FILE-TABLE WS-WEB-ERROR
           IF WS-WEB-ERROR NOT = SPACES
               STRING 'static files: ' WS-WEB-ERROR
                   DELIMITED BY SIZE INTO WS-LOG-TEXT
               END-STRING
               PERFORM 9900-STOP-WITH-ERROR
           END-IF

           PERFORM 1100-OPEN-LISTENER.

       1050-CATCH-STOP-SIGNALS.
      *    "SET ... TO ENTRY" TAKES THE ADDRESS OF A PROGRAM. SIGNAL()
      *    RECORDS IT, AND THE KERNEL RUNS THAT PROGRAM (ONSTOP) WHEN
      *    THE SIGNAL ARRIVES, EVEN WHILE WE WAIT FOR THE DATABASE.
           SET WS-STOP-HANDLER TO ENTRY 'ONSTOP'
           CALL 'signal' USING BY VALUE SIGTERM
                               BY VALUE WS-STOP-HANDLER
               RETURNING WS-PREVIOUS-HANDLER
           END-CALL
           CALL 'signal' USING BY VALUE SIGINT
                               BY VALUE WS-STOP-HANDLER
               RETURNING WS-PREVIOUS-HANDLER
           END-CALL.

       1100-OPEN-LISTENER.
      *    THE PORT COMES FROM $PORT, 8080 IF IT IS NOT SET.
           MOVE SPACES TO WS-PORT-TEXT
           ACCEPT WS-PORT-TEXT FROM ENVIRONMENT 'PORT'
           END-ACCEPT
           IF WS-PORT-TEXT = SPACES
               MOVE '8080' TO WS-PORT-TEXT
           END-IF
           MOVE FUNCTION LENGTH(FUNCTION TRIM(WS-PORT-TEXT TRAILING))
             TO WS-PORT-LENGTH
           IF WS-PORT-LENGTH > 5
              OR WS-PORT-TEXT(1:WS-PORT-LENGTH) IS NOT NUMERIC
              OR FUNCTION NUMVAL(WS-PORT-TEXT) > 65535
               STRING 'listen tcp: address 0.0.0.0:'
                      FUNCTION TRIM(WS-PORT-TEXT TRAILING)
                      ': invalid port'
                   DELIMITED BY SIZE INTO WS-LOG-TEXT
               END-STRING
               PERFORM 9900-STOP-WITH-ERROR
           END-IF
           MOVE FUNCTION NUMVAL(WS-PORT-TEXT) TO WS-PORT-NUMBER
           MOVE WS-PORT-NUMBER TO SIN-PORT

      *    SOCKET, BIND, LISTEN: THE THREE C LIBRARY CALLS THAT OPEN A
      *    TCP SERVER. "BY VALUE" PASSES A NUMBER, "BY REFERENCE" THE
      *    ADDRESS OF A COBOL RECORD, THE WAY C EXPECTS.
           CALL 'socket' USING BY VALUE AF-INET
                               BY VALUE SOCK-STREAM
                               BY VALUE 0
               RETURNING WS-LISTEN-SOCKET
           END-CALL
           IF WS-LISTEN-SOCKET < 0
               MOVE 'listen tcp: socket() failed' TO WS-LOG-TEXT
               PERFORM 9900-STOP-WITH-ERROR
           END-IF
           CALL 'setsockopt' USING BY VALUE WS-LISTEN-SOCKET
                                   BY VALUE SOL-SOCKET
                                   BY VALUE SO-REUSEADDR
                                   BY REFERENCE WS-OPTION-ON
                                   BY VALUE WS-OPTION-SIZE
               RETURNING WS-RC
           END-CALL
           CALL 'bind' USING BY VALUE WS-LISTEN-SOCKET
                             BY REFERENCE WS-SOCKET-ADDRESS
                             BY VALUE WS-ADDRESS-SIZE
               RETURNING WS-RC
           END-CALL
           IF WS-RC NOT = 0
               STRING 'listen tcp 0.0.0.0:'
                      FUNCTION TRIM(WS-PORT-TEXT TRAILING)
                      ': bind() failed'
                   DELIMITED BY SIZE INTO WS-LOG-TEXT
               END-STRING
               PERFORM 9900-STOP-WITH-ERROR
           END-IF
           CALL 'listen' USING BY VALUE WS-LISTEN-SOCKET
                               BY VALUE WS-BACKLOG
               RETURNING WS-RC
           END-CALL
           IF WS-RC NOT = 0
               MOVE 'listen tcp: listen() failed' TO WS-LOG-TEXT
               PERFORM 9900-STOP-WITH-ERROR
           END-IF

           MOVE SPACES TO WS-LOG-TEXT
           STRING 'listening on 0.0.0.0:'
                  FUNCTION TRIM(WS-PORT-TEXT TRAILING)
               DELIMITED BY SIZE INTO WS-LOG-TEXT
           END-STRING
           CALL 'LOGLINE' USING WS-LOG-TEXT.

      *================================================================*
      * 2000: ONE CLIENT: ACCEPT, READ, ROUTE, ANSWER, HANG UP.        *
      *================================================================*
       2000-SERVE-ONE-CLIENT.
      *    ACCEPT() WAITS FOR THE NEXT CONNECTION AND RETURNS A NEW
      *    SOCKET FOR IT.
           CALL 'accept' USING BY VALUE WS-LISTEN-SOCKET
                               BY VALUE 0
                               BY VALUE 0
               RETURNING CONN-SOCKET
           END-CALL
           IF CONN-SOCKET < 0
      *        INTERRUPTED, OR OUT OF FILE HANDLES: PAUSE, TRY AGAIN.
               CALL 'C$SLEEP' USING 1
               EXIT PARAGRAPH
           END-IF
           CALL 'setsockopt' USING BY VALUE CONN-SOCKET
                                   BY VALUE SOL-SOCKET
                                   BY VALUE SO-SNDTIMEO
                                   BY REFERENCE WS-SEND-TIMEOUT
                                   BY VALUE WS-TIMEVAL-SIZE
               RETURNING WS-RC
           END-CALL

           MOVE 200 TO RSP-STATUS
           MOVE SPACES TO RSP-REASON RSP-CONTENT-TYPE RSP-ALLOW
           MOVE 0 TO RSP-LOCATION-LENGTH RSP-BODY-LENGTH
           SET RSP-BODY-SENT TO TRUE

           CALL 'HTTPRECV' USING WS-READ-HEAD HTTP-CONNECTION
                                 HTTP-REQUEST HTTP-RESPONSE
           EVALUATE TRUE
               WHEN REQ-IS-ABANDONED
                   CALL 'close' USING BY VALUE CONN-SOCKET
                       RETURNING WS-RC
                   END-CALL
               WHEN REQ-IS-REJECTED
                   CALL 'HTTPSEND' USING HTTP-CONNECTION HTTP-RESPONSE
               WHEN OTHER
                   PERFORM 3000-ROUTE-REQUEST
                   CALL 'HTTPSEND' USING HTTP-CONNECTION HTTP-RESPONSE
           END-EVALUATE.

      *================================================================*
      * 3000: ROUTING, AS GO'S HTTP.SERVEMUX DID IT.                   *
      *================================================================*
       3000-ROUTE-REQUEST.
      *    HEAD IS A GET WHOSE BODY IS NOT SENT.
           IF REQ-IS-HEAD
               SET RSP-BODY-SUPPRESSED TO TRUE
           END-IF
           IF REQ-TARGET-IS-STAR
               PERFORM 3100-ANSWER-ASTERISK
               EXIT PARAGRAPH
           END-IF

      *    1. AN UNTIDY PATH ("/a//b", "/x/../app.js") IS REDIRECTED
      *       TO THE TIDY ONE.
           MOVE 'CLEAN' TO UW-FUNCTION
           MOVE REQ-PATH-LENGTH TO UW-INPUT-LENGTH
           IF REQ-PATH-LENGTH > 0
               MOVE REQ-PATH(1:REQ-PATH-LENGTH) TO UW-INPUT
           END-IF
           CALL 'URLPATH' USING URL-WORK
           IF UW-OUTPUT-LENGTH NOT = REQ-PATH-LENGTH
               PERFORM 3200-REDIRECT-TO-CLEAN-PATH
               EXIT PARAGRAPH
           END-IF
           IF UW-OUTPUT(1:UW-OUTPUT-LENGTH)
              NOT = REQ-PATH(1:REQ-PATH-LENGTH)
               PERFORM 3200-REDIRECT-TO-CLEAN-PATH
               EXIT PARAGRAPH
           END-IF

      *    2. WHICH ROUTE DOES THE PATH NAME?
           PERFORM 3300-SPLIT-PATH
           PERFORM 3400-MATCH-ROUTE

      *    3. DOES THAT ROUTE TAKE THIS METHOD? IF NOT: 405, AND AN
      *       "ALLOW" HEADER LISTING THE METHODS IT DOES TAKE.
           EVALUATE TRUE
               WHEN ROUTE-HEALTH
                   EVALUATE TRUE
                       WHEN REQ-IS-GET-OR-HEAD
                           PERFORM 4000-HEALTH-CHECK
                       WHEN OTHER
                           MOVE 'GET, HEAD' TO RSP-ALLOW
                           PERFORM 8300-METHOD-NOT-ALLOWED
                   END-EVALUATE
               WHEN ROUTE-TODO-LIST
                   EVALUATE TRUE
                       WHEN REQ-IS-GET-OR-HEAD
                           PERFORM 4100-LIST-TODOS
                       WHEN REQ-IS-POST
                           PERFORM 4200-CREATE-TODO
                       WHEN OTHER
                           MOVE 'GET, HEAD, POST' TO RSP-ALLOW
                           PERFORM 8300-METHOD-NOT-ALLOWED
                   END-EVALUATE
               WHEN ROUTE-ONE-TODO
                   EVALUATE TRUE
                       WHEN REQ-IS-PATCH
                           PERFORM 4300-SET-TODO-DONE
                       WHEN REQ-IS-DELETE
                           PERFORM 4400-DELETE-TODO
                       WHEN REQ-IS-GET-OR-HEAD
                           PERFORM 4500-SERVE-WEB-FILE
                       WHEN OTHER
                           MOVE 'DELETE, GET, HEAD, PATCH' TO RSP-ALLOW
                           PERFORM 8300-METHOD-NOT-ALLOWED
                   END-EVALUATE
               WHEN OTHER
                   EVALUATE TRUE
                       WHEN REQ-IS-GET-OR-HEAD
                           PERFORM 4500-SERVE-WEB-FILE
                       WHEN OTHER
                           MOVE 'GET, HEAD' TO RSP-ALLOW
                           PERFORM 8300-METHOD-NOT-ALLOWED
                   END-EVALUATE
           END-EVALUATE.

       3100-ANSWER-ASTERISK.
      *    "OPTIONS * HTTP/1.1" ASKS ABOUT THE SERVER AS A WHOLE AND
      *    GETS AN EMPTY 200. "*" WITH ANY OTHER METHOD IS NONSENSE.
           IF REQ-IS-OPTIONS
               MOVE 200 TO RSP-STATUS
           ELSE
               MOVE 400 TO RSP-STATUS
           END-IF.

       3200-REDIRECT-TO-CLEAN-PATH.
      *    301 TO THE TIDY PATH (IN UW-OUTPUT), WITH THE QUERY KEPT.
      *    LIKE GO, ESCAPE THE PATH AGAIN FOR THE LOCATION HEADER.
           MOVE 301 TO RSP-STATUS
           MOVE 0 TO RSP-LOCATION-LENGTH
           SET HEX-IN-UPPER-CASE TO TRUE
           PERFORM VARYING WS-INDEX FROM 1 BY 1
                   UNTIL WS-INDEX > UW-OUTPUT-LENGTH
               MOVE UW-OUTPUT(WS-INDEX:1) TO WS-BYTE
               IF IS-PATH-SAFE
                   ADD 1 TO RSP-LOCATION-LENGTH
                   MOVE WS-BYTE TO RSP-LOCATION(RSP-LOCATION-LENGTH:1)
               ELSE
                   PERFORM 3210-APPEND-PERCENT-ESCAPE
               END-IF
           END-PERFORM
           MOVE RSP-LOCATION-LENGTH TO WS-LOCATION-PATH-LENGTH

      *    A BROWSER FOLLOWS THE LOCATION HEADER. A GET ALSO GETS A
      *    LINK, FOR ANYTHING THAT DOES NOT. THE LINK KEEPS THE QUERY
      *    AS IT CAME; ONLY & < > " ' ARE MADE SAFE FOR HTML.
           IF REQ-IS-GET-OR-HEAD
               MOVE 'text/html; charset=utf-8' TO RSP-CONTENT-TYPE
               MOVE '<a href="' TO RSP-BODY(1:9)
               MOVE 9 TO RSP-BODY-LENGTH
               PERFORM VARYING WS-INDEX FROM 1 BY 1
                       UNTIL WS-INDEX > WS-LOCATION-PATH-LENGTH
                   MOVE RSP-LOCATION(WS-INDEX:1) TO WS-BYTE
                   PERFORM 3220-APPEND-BYTE-AS-HTML
               END-PERFORM
               IF REQ-QUERY-LENGTH > 0
                   MOVE '?' TO WS-BYTE
                   PERFORM 3220-APPEND-BYTE-AS-HTML
                   PERFORM VARYING WS-INDEX FROM 1 BY 1
                           UNTIL WS-INDEX > REQ-QUERY-LENGTH
                       MOVE REQ-QUERY(WS-INDEX:1) TO WS-BYTE
                       PERFORM 3220-APPEND-BYTE-AS-HTML
                   END-PERFORM
               END-IF
               MOVE '">Moved Permanently</a>.'
                 TO RSP-BODY(RSP-BODY-LENGTH + 1:24)
               ADD 24 TO RSP-BODY-LENGTH
               MOVE X'0A0A' TO RSP-BODY(RSP-BODY-LENGTH + 1:2)
               ADD 2 TO RSP-BODY-LENGTH
           END-IF

      *    IN THE HEADER ITSELF, BYTES ABOVE 127 IN THE QUERY BECOME
      *    %XX, IN LOWERCASE HEX AS GO WRITES THEM THERE.
           IF REQ-QUERY-LENGTH > 0
               ADD 1 TO RSP-LOCATION-LENGTH
               MOVE '?' TO RSP-LOCATION(RSP-LOCATION-LENGTH:1)
               SET HEX-IN-LOWER-CASE TO TRUE
               PERFORM VARYING WS-INDEX FROM 1 BY 1
                       UNTIL WS-INDEX > REQ-QUERY-LENGTH
                   MOVE REQ-QUERY(WS-INDEX:1) TO WS-BYTE
                   IF WS-BYTE-VALUE < 128
                       ADD 1 TO RSP-LOCATION-LENGTH
                       MOVE WS-BYTE
                         TO RSP-LOCATION(RSP-LOCATION-LENGTH:1)
                   ELSE
                       PERFORM 3210-APPEND-PERCENT-ESCAPE
                   END-IF
               END-PERFORM
           END-IF.

       3210-APPEND-PERCENT-ESCAPE.
           COMPUTE WS-HIGH-NIBBLE = WS-BYTE-VALUE / 16
           COMPUTE WS-LOW-NIBBLE = FUNCTION MOD(WS-BYTE-VALUE, 16)
           ADD 1 TO RSP-LOCATION-LENGTH
           MOVE '%' TO RSP-LOCATION(RSP-LOCATION-LENGTH:1)
           IF HEX-IN-UPPER-CASE
               MOVE WS-UPPER-HEX(WS-HIGH-NIBBLE + 1:1)
                 TO RSP-LOCATION(RSP-LOCATION-LENGTH + 1:1)
               MOVE WS-UPPER-HEX(WS-LOW-NIBBLE + 1:1)
                 TO RSP-LOCATION(RSP-LOCATION-LENGTH + 2:1)
           ELSE
               MOVE WS-LOWER-HEX(WS-HIGH-NIBBLE + 1:1)
                 TO RSP-LOCATION(RSP-LOCATION-LENGTH + 1:1)
               MOVE WS-LOWER-HEX(WS-LOW-NIBBLE + 1:1)
                 TO RSP-LOCATION(RSP-LOCATION-LENGTH + 2:1)
           END-IF
           ADD 2 TO RSP-LOCATION-LENGTH.

       3220-APPEND-BYTE-AS-HTML.
      *    & < > " ' WOULD BREAK OUT OF THE HTML ATTRIBUTE.
           EVALUATE WS-BYTE
               WHEN '&'
                   MOVE '&amp;' TO WS-PIECE
                   MOVE 5 TO WS-PIECE-LENGTH
               WHEN '<'
                   MOVE '&lt;' TO WS-PIECE
                   MOVE 4 TO WS-PIECE-LENGTH
               WHEN '>'
                   MOVE '&gt;' TO WS-PIECE
                   MOVE 4 TO WS-PIECE-LENGTH
               WHEN '"'
                   MOVE '&#34;' TO WS-PIECE
                   MOVE 5 TO WS-PIECE-LENGTH
               WHEN "'"
                   MOVE '&#39;' TO WS-PIECE
                   MOVE 5 TO WS-PIECE-LENGTH
               WHEN OTHER
                   MOVE WS-BYTE TO WS-PIECE
                   MOVE 1 TO WS-PIECE-LENGTH
           END-EVALUATE
           MOVE WS-PIECE(1:WS-PIECE-LENGTH)
             TO RSP-BODY(RSP-BODY-LENGTH + 1:WS-PIECE-LENGTH)
           ADD WS-PIECE-LENGTH TO RSP-BODY-LENGTH.

       3300-SPLIT-PATH.
      *    "/api/todos/42" -> "api", "todos", "42". EACH PIECE IS THEN
      *    %-DECODED ON ITS OWN, SO AN ENCODED "/" (%2F) STAYS INSIDE
      *    ITS PIECE, AS IN GO.
           MOVE 'N' TO WS-TRAILING-SLASH
           MOVE REQ-PATH-LENGTH TO WS-PATH-END
           IF WS-PATH-END > 1 AND REQ-PATH(WS-PATH-END:1) = '/'
               SET HAS-TRAILING-SLASH TO TRUE
               SUBTRACT 1 FROM WS-PATH-END
           END-IF
           MOVE 0 TO WS-SEGMENT-COUNT
           IF WS-PATH-END > 1
      *        UNSTRING CUTS A FIELD INTO PIECES AT EACH DELIMITER.
               UNSTRING REQ-PATH(2:WS-PATH-END - 1) DELIMITED BY '/'
                   INTO WS-SEGMENT-TEXT(1) COUNT IN WS-SEGMENT-LENGTH(1)
                        WS-SEGMENT-TEXT(2) COUNT IN WS-SEGMENT-LENGTH(2)
                        WS-SEGMENT-TEXT(3) COUNT IN WS-SEGMENT-LENGTH(3)
                        WS-SEGMENT-TEXT(4) COUNT IN WS-SEGMENT-LENGTH(4)
                   TALLYING IN WS-SEGMENT-COUNT
               END-UNSTRING
           END-IF
           PERFORM VARYING WS-SEGMENT-NUMBER FROM 1 BY 1
                   UNTIL WS-SEGMENT-NUMBER > 3
                      OR WS-SEGMENT-NUMBER > WS-SEGMENT-COUNT
               MOVE 'DECODE' TO UW-FUNCTION
               MOVE WS-SEGMENT-LENGTH(WS-SEGMENT-NUMBER)
                 TO UW-INPUT-LENGTH
               MOVE WS-SEGMENT-TEXT(WS-SEGMENT-NUMBER) TO UW-INPUT
               CALL 'URLPATH' USING URL-WORK
               MOVE UW-OUTPUT-LENGTH
                 TO WS-DECODED-LENGTH(WS-SEGMENT-NUMBER)
               MOVE UW-OUTPUT TO WS-DECODED-TEXT(WS-SEGMENT-NUMBER)
           END-PERFORM.

       3400-MATCH-ROUTE.
           SET ROUTE-WEB-FILES TO TRUE
           IF HAS-TRAILING-SLASH
               EXIT PARAGRAPH
           END-IF
           EVALUATE WS-SEGMENT-COUNT
               WHEN 1
                   IF WS-DECODED-LENGTH(1) = 6
                      AND WS-DECODED-TEXT(1)(1:6) = 'health'
                       SET ROUTE-HEALTH TO TRUE
                   END-IF
               WHEN 2
                   IF WS-DECODED-LENGTH(1) = 3
                      AND WS-DECODED-TEXT(1)(1:3) = 'api'
                      AND WS-DECODED-LENGTH(2) = 5
                      AND WS-DECODED-TEXT(2)(1:5) = 'todos'
                       SET ROUTE-TODO-LIST TO TRUE
                   END-IF
               WHEN 3
      *            GO'S {ID} NEVER MATCHES A LONE "/" (FROM "%2F").
                   IF WS-DECODED-LENGTH(1) = 3
                      AND WS-DECODED-TEXT(1)(1:3) = 'api'
                      AND WS-DECODED-LENGTH(2) = 5
                      AND WS-DECODED-TEXT(2)(1:5) = 'todos'
                      AND NOT (WS-DECODED-LENGTH(3) = 1
                               AND WS-DECODED-TEXT(3)(1:1) = '/')
                       SET ROUTE-ONE-TODO TO TRUE
                   END-IF
           END-EVALUATE.

      *================================================================*
      * 4000: THE HANDLERS, ONE PER ROUTE (HANDLERS.GO).               *
      *================================================================*
       4000-HEALTH-CHECK.
           MOVE 200 TO RSP-STATUS
           MOVE 'text/plain' TO RSP-CONTENT-TYPE
           MOVE 'OK' TO RSP-BODY(1:2)
           MOVE 2 TO RSP-BODY-LENGTH.

       4100-LIST-TODOS.
           SET DB-FN-LIST-OPEN TO TRUE
           CALL 'TODODB' USING DB-REQUEST TODO-RECORD
           IF NOT DB-OK
               PERFORM 8500-INTERNAL-ERROR
               EXIT PARAGRAPH
           END-IF
           SET JO-START-LIST TO TRUE
           CALL 'JSONTODO' USING JSON-OUT TODO-RECORD HTTP-RESPONSE
      *    FETCH ROWS UNTIL THE CURSOR RUNS OUT. EACH ONE IS WRITTEN
      *    STRAIGHT INTO THE RESPONSE BODY.
           PERFORM UNTIL NOT DB-OK
               SET DB-FN-LIST-NEXT TO TRUE
               CALL 'TODODB' USING DB-REQUEST TODO-RECORD
               IF DB-OK
                   SET JO-ADD-TO-LIST TO TRUE
                   CALL 'JSONTODO' USING JSON-OUT TODO-RECORD
                                         HTTP-RESPONSE
                   IF JO-BODY-FULL
                       SET DB-FN-LIST-CLOSE TO TRUE
                       CALL 'TODODB' USING DB-REQUEST TODO-RECORD
                       MOVE 'the list does not fit in 16 MiB'
                         TO DB-MESSAGE
                       SET DB-FAILED TO TRUE
                   END-IF
               END-IF
           END-PERFORM
           IF DB-FAILED
               PERFORM 8500-INTERNAL-ERROR
               EXIT PARAGRAPH
           END-IF
           SET DB-FN-LIST-CLOSE TO TRUE
           CALL 'TODODB' USING DB-REQUEST TODO-RECORD
           IF NOT DB-OK
               PERFORM 8500-INTERNAL-ERROR
               EXIT PARAGRAPH
           END-IF
           SET JO-END-LIST TO TRUE
           CALL 'JSONTODO' USING JSON-OUT TODO-RECORD HTTP-RESPONSE
           IF JO-BODY-FULL
               MOVE 'the list does not fit in 16 MiB' TO DB-MESSAGE
               PERFORM 8500-INTERNAL-ERROR
               EXIT PARAGRAPH
           END-IF
           MOVE 200 TO RSP-STATUS
           MOVE 'application/json' TO RSP-CONTENT-TYPE.

       4200-CREATE-TODO.
           SET JB-WANTS-TITLE TO TRUE
           PERFORM 5000-READ-JSON-BODY
           IF JB-IS-INVALID
               MOVE 'invalid JSON body' TO WS-ERROR-TEXT
               PERFORM 8100-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
      *    TRIM THE TITLE, THEN COUNT ITS CHARACTERS (NOT ITS BYTES).
           MOVE 'TRIM' TO U8-FUNCTION
           MOVE 1 TO U8-POSITION
           MOVE JB-TITLE-LENGTH TO U8-END
           CALL 'UTF8TEXT' USING UTF8-WORK JB-TITLE
           IF U8-CHARACTERS = 0 OR U8-CHARACTERS > 200
               MOVE 'title must be 1-200 characters' TO WS-ERROR-TEXT
               PERFORM 8100-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
      *    THE APP IS PUBLIC: KEEP AT MOST 64 BYTES OF THE TITLE.
           MOVE 'CUT ' TO U8-FUNCTION
           MOVE TITLE-BYTE-LIMIT TO U8-BYTE-LIMIT
           CALL 'UTF8TEXT' USING UTF8-WORK JB-TITLE
           COMPUTE TODO-TITLE-LENGTH = U8-END - U8-POSITION + 1
           MOVE JB-TITLE(U8-POSITION:TODO-TITLE-LENGTH)
             TO TODO-TITLE(1:TODO-TITLE-LENGTH)
      *    POSTGRESQL TEXT CAN NOT HOLD A ZERO BYTE ("\u0000"). THE GO
      *    VERSION FOUND OUT FROM THE DATABASE AND ANSWERED 500; THE C
      *    STRINGS UNDER OCESQL WOULD QUIETLY CUT THE TITLE OFF THERE
      *    INSTEAD, SO ANSWER THE SAME 500 BEFORE SENDING IT.
           MOVE 0 TO WS-NUL-COUNT
           INSPECT TODO-TITLE(1:TODO-TITLE-LENGTH)
               TALLYING WS-NUL-COUNT FOR ALL X'00'
           IF WS-NUL-COUNT > 0
               MOVE SPACES TO DB-MESSAGE
               STRING 'the title contains a zero byte, which '
                      'PostgreSQL text can not hold'
                   DELIMITED BY SIZE INTO DB-MESSAGE
               END-STRING
               PERFORM 8500-INTERNAL-ERROR
               EXIT PARAGRAPH
           END-IF
           SET DB-FN-CREATE TO TRUE
           CALL 'TODODB' USING DB-REQUEST TODO-RECORD
           IF NOT DB-OK
               PERFORM 8500-INTERNAL-ERROR
               EXIT PARAGRAPH
           END-IF
           MOVE 201 TO RSP-STATUS
           MOVE 'application/json' TO RSP-CONTENT-TYPE
           SET JO-SINGLE-TODO TO TRUE
           CALL 'JSONTODO' USING JSON-OUT TODO-RECORD HTTP-RESPONSE.

       4300-SET-TODO-DONE.
           PERFORM 6000-PARSE-ID
           IF ID-IS-INVALID
               MOVE 'invalid id' TO WS-ERROR-TEXT
               PERFORM 8100-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
           SET JB-WANTS-DONE TO TRUE
           PERFORM 5000-READ-JSON-BODY
           IF JB-IS-INVALID
               MOVE 'invalid JSON body' TO WS-ERROR-TEXT
               PERFORM 8100-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
           IF JB-DONE-MISSING
               MOVE 'done is required' TO WS-ERROR-TEXT
               PERFORM 8100-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
           MOVE WS-ID-NUMBER TO TODO-ID
           IF JB-DONE-TRUE
               SET TODO-IS-DONE TO TRUE
           ELSE
               SET TODO-IS-OPEN TO TRUE
           END-IF
           SET DB-FN-SET-DONE TO TRUE
           CALL 'TODODB' USING DB-REQUEST TODO-RECORD
           EVALUATE TRUE
               WHEN DB-NOT-FOUND
                   MOVE 404 TO RSP-STATUS
                   MOVE 'todo not found' TO WS-ERROR-TEXT
                   PERFORM 8000-WRITE-ERROR-JSON
               WHEN DB-FAILED
                   PERFORM 8500-INTERNAL-ERROR
               WHEN OTHER
                   MOVE 200 TO RSP-STATUS
                   MOVE 'application/json' TO RSP-CONTENT-TYPE
                   SET JO-SINGLE-TODO TO TRUE
                   CALL 'JSONTODO' USING JSON-OUT TODO-RECORD
                                         HTTP-RESPONSE
           END-EVALUATE.

       4400-DELETE-TODO.
           PERFORM 6000-PARSE-ID
           IF ID-IS-INVALID
               MOVE 'invalid id' TO WS-ERROR-TEXT
               PERFORM 8100-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
           MOVE WS-ID-NUMBER TO TODO-ID
           SET DB-FN-DELETE TO TRUE
           CALL 'TODODB' USING DB-REQUEST TODO-RECORD
           EVALUATE TRUE
               WHEN DB-NOT-FOUND
                   MOVE 404 TO RSP-STATUS
                   MOVE 'todo not found' TO WS-ERROR-TEXT
                   PERFORM 8000-WRITE-ERROR-JSON
               WHEN DB-FAILED
                   PERFORM 8500-INTERNAL-ERROR
               WHEN OTHER
                   MOVE 204 TO RSP-STATUS
           END-EVALUATE.

       4500-SERVE-WEB-FILE.
      *    LIKE GO'S HTTP.FILESERVER: "/" IS INDEX.HTML, A FILE IN THE
      *    TABLE IS SENT, ANYTHING ELSE IS 404. THE PATH IS ONLY EVER
      *    COMPARED WITH THE TABLE, NEVER USED TO OPEN A FILE.
           MOVE 'DECODE' TO UW-FUNCTION
           MOVE REQ-PATH-LENGTH TO UW-INPUT-LENGTH
           MOVE REQ-PATH(1:REQ-PATH-LENGTH) TO UW-INPUT
           CALL 'URLPATH' USING URL-WORK
           MOVE UW-OUTPUT TO WS-WEB-URL
           MOVE UW-OUTPUT-LENGTH TO WS-WEB-URL-LENGTH

      *    ".../index.html" IS ALWAYS SENT BACK TO ".../" (301).
           IF WS-WEB-URL-LENGTH >= 11
              AND WS-WEB-URL(WS-WEB-URL-LENGTH - 10:11) = '/index.html'
               MOVE './' TO RSP-LOCATION
               MOVE 2 TO RSP-LOCATION-LENGTH
               PERFORM 8600-LOCAL-REDIRECT
               EXIT PARAGRAPH
           END-IF

           MOVE 'CLEANDIR' TO UW-FUNCTION
           MOVE WS-WEB-URL-LENGTH TO UW-INPUT-LENGTH
           MOVE WS-WEB-URL TO UW-INPUT
           CALL 'URLPATH' USING URL-WORK
           MOVE UW-OUTPUT TO WS-WEB-NAME
           MOVE UW-OUTPUT-LENGTH TO WS-WEB-NAME-LENGTH

           IF WS-WEB-NAME-LENGTH = 1
      *        THE ROOT DIRECTORY: SERVE ITS INDEX.HTML, BUT ONLY AT A
      *        URL THAT ENDS IN "/".
               IF WS-WEB-URL(WS-WEB-URL-LENGTH:1) NOT = '/'
                   PERFORM 4510-FIND-BASE-NAME
                   MOVE WS-WEB-URL(WS-BASE-START:
                                   WS-WEB-URL-LENGTH
                                   - WS-BASE-START + 1)
                     TO RSP-LOCATION
                   COMPUTE RSP-LOCATION-LENGTH =
                       WS-WEB-URL-LENGTH - WS-BASE-START + 2
                   MOVE '/' TO RSP-LOCATION(RSP-LOCATION-LENGTH:1)
                   PERFORM 8600-LOCAL-REDIRECT
                   EXIT PARAGRAPH
               END-IF
               MOVE '/index.html' TO WS-WEB-NAME
               MOVE 11 TO WS-WEB-NAME-LENGTH
           ELSE
      *        A FILE: A URL ENDING IN "/" IS SENT TO THE FILE ITSELF.
               IF WS-WEB-URL(WS-WEB-URL-LENGTH:1) = '/'
                   MOVE WS-WEB-NAME TO WS-WEB-URL
                   MOVE WS-WEB-NAME-LENGTH TO WS-WEB-URL-LENGTH
                   PERFORM 4510-FIND-BASE-NAME
                   MOVE '../' TO RSP-LOCATION
                   COMPUTE RSP-LOCATION-LENGTH =
                       WS-WEB-URL-LENGTH - WS-BASE-START + 4
                   MOVE WS-WEB-URL(WS-BASE-START:
                                   WS-WEB-URL-LENGTH
                                   - WS-BASE-START + 1)
                     TO RSP-LOCATION(4:RSP-LOCATION-LENGTH - 3)
                   PERFORM 4520-FIND-WEB-FILE
                   IF WS-FILE-NUMBER > 0
                       PERFORM 8600-LOCAL-REDIRECT
                   ELSE
                       MOVE 0 TO RSP-LOCATION-LENGTH
                       PERFORM 8400-NOT-FOUND
                   END-IF
                   EXIT PARAGRAPH
               END-IF
           END-IF

           PERFORM 4520-FIND-WEB-FILE
           IF WS-FILE-NUMBER = 0
               PERFORM 8400-NOT-FOUND
               EXIT PARAGRAPH
           END-IF
           MOVE 200 TO RSP-STATUS
           MOVE WEB-CONTENT-TYPE(WS-FILE-NUMBER) TO RSP-CONTENT-TYPE
           MOVE WEB-FILE-SIZE(WS-FILE-NUMBER) TO RSP-BODY-LENGTH
           MOVE WEB-FILE-BYTES(WS-FILE-NUMBER)(1:RSP-BODY-LENGTH)
             TO RSP-BODY(1:RSP-BODY-LENGTH).

       4510-FIND-BASE-NAME.
      *    WHERE THE LAST PATH ELEMENT OF WS-WEB-URL STARTS.
           MOVE WS-WEB-URL-LENGTH TO WS-BASE-START
           PERFORM UNTIL WS-BASE-START <= 1
                   OR WS-WEB-URL(WS-BASE-START - 1:1) = '/'
               SUBTRACT 1 FROM WS-BASE-START
           END-PERFORM.

       4520-FIND-WEB-FILE.
      *    SEARCH THE TABLE FOR WS-WEB-NAME. 0 MEANS NOT THERE.
           MOVE 0 TO WS-FILE-NUMBER
           IF WS-WEB-NAME-LENGTH > LENGTH OF WEB-URL-PATH(1)
               EXIT PARAGRAPH
           END-IF
           SET WEB-INDEX TO 1
           SEARCH WEB-FILE
               AT END
                   MOVE 0 TO WS-FILE-NUMBER
               WHEN WEB-URL-PATH(WEB-INDEX)
                    = WS-WEB-NAME(1:WS-WEB-NAME-LENGTH)
                AND FUNCTION LENGTH(
                        FUNCTION TRIM(WEB-URL-PATH(WEB-INDEX)))
                    = WS-WEB-NAME-LENGTH
                   SET WS-FILE-NUMBER TO WEB-INDEX
           END-SEARCH.

       5000-READ-JSON-BODY.
           CALL 'HTTPRECV' USING WS-READ-BODY HTTP-CONNECTION
                                 HTTP-REQUEST HTTP-RESPONSE
           CALL 'JSONREAD' USING HTTP-REQUEST JSON-BODY.

       6000-PARSE-ID.
      *    LIKE GO'S STRCONV.PARSEINT(ID, 10, 64): AN OPTIONAL SIGN,
      *    THEN DIGITS ONLY, AND IT MUST FIT IN 64 BITS. ONLY A NUMBER
      *    ABOVE ZERO IS AN ID. "+7" AND "007" ARE BOTH 7.
           SET ID-IS-INVALID TO TRUE
           MOVE WS-DECODED-LENGTH(3) TO WS-ID-LENGTH
           MOVE 1 TO WS-ID-FIRST
           IF WS-DECODED-TEXT(3)(1:1) = '+'
               MOVE 2 TO WS-ID-FIRST
           END-IF
           IF WS-DECODED-TEXT(3)(1:1) = '-'
      *        A MINUS SIGN CAN ONLY GIVE ZERO OR LESS.
               EXIT PARAGRAPH
           END-IF
           IF WS-ID-FIRST > WS-ID-LENGTH
               EXIT PARAGRAPH
           END-IF
           IF WS-DECODED-TEXT(3)(WS-ID-FIRST:
                                 WS-ID-LENGTH - WS-ID-FIRST + 1)
              IS NOT NUMERIC
               EXIT PARAGRAPH
           END-IF
           PERFORM UNTIL WS-ID-FIRST > WS-ID-LENGTH
                   OR WS-DECODED-TEXT(3)(WS-ID-FIRST:1) NOT = '0'
               ADD 1 TO WS-ID-FIRST
           END-PERFORM
           IF WS-ID-FIRST > WS-ID-LENGTH
               EXIT PARAGRAPH
           END-IF
           IF WS-ID-LENGTH - WS-ID-FIRST + 1 > 19
               EXIT PARAGRAPH
           END-IF
           MOVE WS-DECODED-TEXT(3)(WS-ID-FIRST:
                                   WS-ID-LENGTH - WS-ID-FIRST + 1)
             TO WS-ID-NUMBER
           IF WS-ID-NUMBER > 9223372036854775807
               EXIT PARAGRAPH
           END-IF
           SET ID-IS-VALID TO TRUE.

      *================================================================*
      * 8000: ERROR RESPONSES, WORD FOR WORD AS THE GO VERSION SENT.   *
      *================================================================*
       8000-WRITE-ERROR-JSON.
           MOVE WS-ERROR-TEXT TO WS-ERROR-MESSAGE
           JSON GENERATE WS-ERROR-JSON FROM WS-ERROR-RECORD
               COUNT IN WS-ERROR-JSON-LENGTH
               NAME OF WS-ERROR-RECORD  IS OMITTED
                       WS-ERROR-MESSAGE IS 'error'
               ON EXCEPTION
                   MOVE JSON-CODE TO WS-JSON-CODE-SHOWN
                   MOVE SPACES TO WS-LOG-TEXT
                   STRING 'error: JSON GENERATE failed, JSON-CODE '
                          FUNCTION TRIM(WS-JSON-CODE-SHOWN)
                       DELIMITED BY SIZE INTO WS-LOG-TEXT
                   END-STRING
                   CALL 'LOGLINE' USING WS-LOG-TEXT
                   MOVE 0 TO WS-ERROR-JSON-LENGTH
           END-JSON
           MOVE 'application/json' TO RSP-CONTENT-TYPE
           MOVE WS-ERROR-JSON-LENGTH TO RSP-BODY-LENGTH
           IF RSP-BODY-LENGTH > 0
               MOVE WS-ERROR-JSON(1:RSP-BODY-LENGTH)
                 TO RSP-BODY(1:RSP-BODY-LENGTH)
           END-IF
           ADD 1 TO RSP-BODY-LENGTH
           MOVE X'0A' TO RSP-BODY(RSP-BODY-LENGTH:1).

       8100-BAD-REQUEST.
           MOVE 400 TO RSP-STATUS
           PERFORM 8000-WRITE-ERROR-JSON.

       8300-METHOD-NOT-ALLOWED.
           MOVE 405 TO RSP-STATUS
           MOVE 'text/plain; charset=utf-8' TO RSP-CONTENT-TYPE
           MOVE 'Method Not Allowed' TO RSP-BODY(1:18)
           MOVE X'0A' TO RSP-BODY(19:1)
           MOVE 19 TO RSP-BODY-LENGTH.

       8400-NOT-FOUND.
           MOVE 404 TO RSP-STATUS
           MOVE 'text/plain; charset=utf-8' TO RSP-CONTENT-TYPE
           MOVE '404 page not found' TO RSP-BODY(1:18)
           MOVE X'0A' TO RSP-BODY(19:1)
           MOVE 19 TO RSP-BODY-LENGTH.

       8500-INTERNAL-ERROR.
      *    THE CLIENT ONLY LEARNS "INTERNAL ERROR"; THE LOG GETS WHY.
           MOVE SPACES TO WS-LOG-TEXT
           STRING 'error: ' DB-MESSAGE
               DELIMITED BY SIZE INTO WS-LOG-TEXT
           END-STRING
           CALL 'LOGLINE' USING WS-LOG-TEXT
           MOVE 500 TO RSP-STATUS
           MOVE 0 TO RSP-BODY-LENGTH
           MOVE 'internal error' TO WS-ERROR-TEXT
           PERFORM 8000-WRITE-ERROR-JSON.

       8600-LOCAL-REDIRECT.
      *    THE FILE SERVER'S OWN REDIRECTS: A RELATIVE LOCATION, THE
      *    QUERY KEPT, NO BODY.
           MOVE 301 TO RSP-STATUS
           IF REQ-QUERY-LENGTH > 0
               ADD 1 TO RSP-LOCATION-LENGTH
               MOVE '?' TO RSP-LOCATION(RSP-LOCATION-LENGTH:1)
               MOVE REQ-QUERY(1:REQ-QUERY-LENGTH)
                 TO RSP-LOCATION(RSP-LOCATION-LENGTH + 1:
                                 REQ-QUERY-LENGTH)
               ADD REQ-QUERY-LENGTH TO RSP-LOCATION-LENGTH
           END-IF
           MOVE SPACES TO RSP-CONTENT-TYPE
           MOVE 0 TO RSP-BODY-LENGTH.

      *================================================================*
      * 9900: A FAILURE THE SERVER CAN NOT RUN WITHOUT.                *
      *================================================================*
       9900-STOP-WITH-ERROR.
           CALL 'LOGLINE' USING WS-LOG-TEXT
           MOVE 1 TO RETURN-CODE
           STOP RUN.
