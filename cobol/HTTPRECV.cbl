      *================================================================*
      * HTTPRECV - READ ONE HTTP REQUEST FROM A CLIENT SOCKET.         *
      *                                                                *
      * 'HEAD' READS THE REQUEST LINE AND THE HEADERS:                 *
      *                                                                *
      *     POST /api/todos HTTP/1.1                                   *
      *     Host: todo.example.com                                     *
      *     Content-Length: 20                                         *
      *     (A BLANK LINE)                                             *
      *                                                                *
      * 'BODY' READS THE CONTENT-LENGTH BYTES THAT FOLLOW, AT MOST     *
      * 1 MIB OF THEM. A HANDLER ASKS FOR THE BODY ONLY WHEN IT NEEDS  *
      * IT, AS GO'S HANDLERS DID.                                      *
      *                                                                *
      * THE NETWORK MAY DELIVER A REQUEST IN ANY NUMBER OF PIECES, SO  *
      * EACH PART IS READ IN A LOOP UNTIL IT IS COMPLETE. THE WHOLE    *
      * REQUEST MUST ARRIVE WITHIN 10 SECONDS OF THE CONNECTION, OR    *
      * THE CONNECTION IS DROPPED. THE SERVER ANSWERS ONE CLIENT AT A  *
      * TIME, AND THAT LIMIT KEEPS A SLOW ONE FROM HOLDING IT FOREVER. *
      *                                                                *
      * A REQUEST GO'S NET/HTTP WOULD HAVE REFUSED IS REFUSED HERE     *
      * WITH THE SAME STATUS AND TEXT, AND NEVER REACHES THE ROUTER.   *
      *================================================================*
       IDENTIFICATION DIVISION.
       PROGRAM-ID. HTTPRECV.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. LINUX-X86-64.
       OBJECT-COMPUTER. LINUX-X86-64.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY CLOCKREC.

      *    CONSTANTS FROM THE C HEADER FILES. COBOL PASSES THEM TO THE
      *    C LIBRARY AS PLAIN NUMBERS.
       01  SOL-SOCKET                  BINARY-LONG VALUE 1.
       01  SO-RCVTIMEO                 BINARY-LONG VALUE 20.
       01  MSG-NOSIGNAL                BINARY-LONG VALUE 16384.
       01  WS-TIMEVAL-SIZE             BINARY-LONG VALUE 16.

      *    A C "STRUCT TIMEVAL": SECONDS AND MICROSECONDS, EACH A
      *    64-BIT NUMBER. RECV() GIVES UP WHEN THIS MUCH TIME PASSES
      *    WITH NOTHING ARRIVING.
       01  WS-TIMEVAL.
           05  WS-TIMEVAL-SECONDS      BINARY-DOUBLE.
           05  WS-TIMEVAL-MICROS       BINARY-DOUBLE.
       01  WS-TICKS-LEFT               BINARY-DOUBLE.

       01  WS-HEAD-LIMIT               BINARY-LONG.
       01  WS-WANTED                   BINARY-DOUBLE.
       01  WS-RECEIVED-NOW             BINARY-DOUBLE.
       01  WS-SENT                     BINARY-DOUBLE.
       01  WS-RC                       BINARY-LONG.
       01  WS-COUNT                    BINARY-LONG.
       01  WS-INDEX                    BINARY-LONG.

       01  WS-HEAD-STATE               PIC X.
           88  HEAD-INCOMPLETE         VALUE 'I'.
           88  HEAD-COMPLETE           VALUE 'C'.
           88  HEAD-TOO-LARGE          VALUE 'L'.
       01  WS-CLIENT-STATE             PIC X.
           88  CLIENT-CONNECTED        VALUE 'C'.
           88  CLIENT-GONE             VALUE 'G'.

      *    FINDING THE BLANK LINE AT THE END OF THE HEAD.
       01  WS-SCAN-FROM                BINARY-LONG.
       01  WS-LINE-FEED                BINARY-LONG.

      *    THE REQUEST LINE.
       01  WS-LINE-START               BINARY-LONG.
       01  WS-LINE-LENGTH              BINARY-LONG.
       01  WS-NEXT-LINE                BINARY-LONG.
       01  WS-FIRST-SPACE              BINARY-LONG.
       01  WS-SECOND-SPACE             BINARY-LONG.
       01  WS-TARGET-START             BINARY-LONG.
       01  WS-TARGET-LENGTH            BINARY-LONG.
       01  WS-PATH-START               BINARY-LONG.
       01  WS-PATH-END                 BINARY-LONG.
       01  WS-TARGET-END               BINARY-LONG.
       01  WS-VERSION                  PIC X(8).
       01  WS-MAJOR-VERSION            PIC 9.

      *    ONE HEADER LINE.
       01  WS-COLON                    BINARY-LONG.
       01  WS-VALUE-START              BINARY-LONG.
       01  WS-VALUE-END                BINARY-LONG.
       01  WS-VALUE-LENGTH             BINARY-LONG.
       01  WS-HEADER-NAME              PIC X(32).
       01  WS-FIRST-HEADER             PIC X.
           88  ON-FIRST-HEADER         VALUE 'Y'.
       01  WS-HOST-COUNT               BINARY-LONG.
       01  WS-HOST-VALUE               PIC X(256).
       01  WS-HOST-LENGTH              BINARY-LONG.
       01  WS-TRANSFER-ENCODING        PIC X.
           88  HAS-TRANSFER-ENCODING   VALUE 'Y'.
       01  WS-EXPECT-VALUE             PIC X(64).
       01  WS-EXPECT-SEEN              PIC X.
           88  HAS-EXPECT              VALUE 'Y'.
       01  WS-CONTENT-LENGTH-TEXT      PIC X(256).
       01  WS-CONTENT-LENGTH-SEEN      PIC X.
           88  HAS-CONTENT-LENGTH      VALUE 'Y'.
       01  WS-DIGITS                   PIC X(19).
       01  WS-DIGIT-COUNT              BINARY-LONG.
       01  WS-FIRST-DIGIT              BINARY-LONG.
       01  WS-NUMBER                   PIC 9(19).

      *    CHARACTER CLASSES. A "TOKEN" IS WHAT HTTP ALLOWS IN A
      *    METHOD OR A HEADER NAME.
       01  WS-CHARACTER                PIC X.
           88  IS-TOKEN-CHARACTER      VALUES '!' '#' '$' '%' '&' "'"
                                              '*' '+' '-' '.' '^' '_'
                                              '`' '|' '~'
                                              '0' THRU '9'
                                              'A' THRU 'Z'
                                              'a' THRU 'z'.
           88  IS-HOST-CHARACTER       VALUES '!' '$' '%' '&' "'"
                                              '(' ')' '*' '+' ',' '-'
                                              '.' ':' ';' '=' '[' ']'
                                              '_' '~'
                                              '0' THRU '9'
                                              'A' THRU 'Z'
                                              'a' THRU 'z'.
           88  IS-HEX-DIGIT            VALUES '0' THRU '9'
                                              'A' THRU 'F'
                                              'a' THRU 'f'.
           88  IS-SCHEME-CHARACTER     VALUES '+' '-' '.'
                                              '0' THRU '9'
                                              'A' THRU 'Z'
                                              'a' THRU 'z'.
           88  IS-CONTROL-CHARACTER    VALUES X'00' THRU X'1F' X'7F'.
           88  IS-SPACE-OR-TAB         VALUES X'20' X'09'.

       01  WS-CONTINUE-RESPONSE        PIC X(25).
       01  WS-CONTINUE-LENGTH          BINARY-DOUBLE VALUE 25.

       01  WS-REJECT-STATUS            PIC 9(3).
       01  WS-REJECT-REASON            PIC X(64).

       LINKAGE SECTION.
       01  HR-FUNCTION                 PIC X(4).
       COPY HTTPCONN.
       COPY HTTPREQ.
       COPY HTTPRSP.

       PROCEDURE DIVISION USING HR-FUNCTION HTTP-CONNECTION
                                HTTP-REQUEST HTTP-RESPONSE.
       0000-MAIN.
           EVALUATE HR-FUNCTION
               WHEN 'HEAD'
                   PERFORM 1000-READ-HEAD
               WHEN 'BODY'
                   PERFORM 5000-READ-BODY
           END-EVALUATE
           GOBACK.

      *----------------------------------------------------------------*
      * 1. RECEIVE BYTES UNTIL A BLANK LINE ENDS THE HEAD.             *
      *----------------------------------------------------------------*
       1000-READ-HEAD.
           SET REQ-IS-READY TO TRUE
           MOVE 'HTTP/1.1' TO RSP-PROTOCOL
           MOVE LENGTH OF CONN-BUFFER TO WS-HEAD-LIMIT
           MOVE 0 TO CONN-RECEIVED CONN-HEAD-LENGTH
           MOVE 0 TO REQ-PATH-LENGTH REQ-QUERY-LENGTH REQ-BODY-LENGTH
           MOVE -1 TO REQ-CONTENT-LENGTH
           MOVE 'N' TO REQ-EXPECT-FLAG
           MOVE SPACES TO REQ-METHOD

           CALL 'UTCCLOCK' USING CLOCK-READING
           COMPUTE CONN-DEADLINE = CLK-TICKS + 1000

           MOVE 1 TO WS-SCAN-FROM
           SET HEAD-INCOMPLETE TO TRUE
           SET CLIENT-CONNECTED TO TRUE
           PERFORM UNTIL NOT HEAD-INCOMPLETE OR CLIENT-GONE
               PERFORM 1100-LOOK-FOR-BLANK-LINE
               IF HEAD-INCOMPLETE
                   IF CONN-RECEIVED >= WS-HEAD-LIMIT
                       SET HEAD-TOO-LARGE TO TRUE
                   ELSE
                       PERFORM 9000-RECEIVE-MORE-HEAD
                   END-IF
               END-IF
           END-PERFORM

           EVALUATE TRUE
               WHEN CLIENT-GONE
                   SET REQ-IS-ABANDONED TO TRUE
               WHEN HEAD-TOO-LARGE
                   MOVE 431 TO WS-REJECT-STATUS
                   MOVE 'Request Header Fields Too Large'
                     TO WS-REJECT-REASON
                   PERFORM 8000-REJECT
               WHEN OTHER
                   PERFORM 2000-PARSE-REQUEST-LINE
                   IF REQ-IS-READY
                       PERFORM 3000-PARSE-HEADERS
                   END-IF
                   IF REQ-IS-READY
                       PERFORM 4000-CHECK-REQUEST
                   END-IF
           END-EVALUATE.

       1100-LOOK-FOR-BLANK-LINE.
      *    THE HEAD ENDS AT AN EMPTY LINE: A LINE FEED FOLLOWED BY
      *    ANOTHER LINE FEED, OR BY CARRIAGE RETURN + LINE FEED.
      *    INSPECT ... TALLYING COUNTS THE BYTES BEFORE THE NEXT LINE
      *    FEED, WHICH IS HOW FAR AWAY THAT LINE FEED IS.
           PERFORM UNTIL WS-SCAN-FROM > CONN-RECEIVED
                   OR NOT HEAD-INCOMPLETE
               MOVE 0 TO WS-COUNT
               INSPECT CONN-BUFFER(WS-SCAN-FROM:
                                   CONN-RECEIVED - WS-SCAN-FROM + 1)
                   TALLYING WS-COUNT
                   FOR CHARACTERS BEFORE INITIAL X'0A'
               COMPUTE WS-LINE-FEED = WS-SCAN-FROM + WS-COUNT
               EVALUATE TRUE
                   WHEN WS-LINE-FEED > CONN-RECEIVED
                       MOVE WS-LINE-FEED TO WS-SCAN-FROM
                   WHEN WS-LINE-FEED + 1 > CONN-RECEIVED
      *                TOO FEW BYTES YET TO TELL. LOOK AGAIN LATER.
                       MOVE WS-LINE-FEED TO WS-SCAN-FROM
                       EXIT PERFORM
                   WHEN CONN-BUFFER(WS-LINE-FEED + 1:1) = X'0A'
                       COMPUTE CONN-HEAD-LENGTH = WS-LINE-FEED + 1
                       SET HEAD-COMPLETE TO TRUE
                   WHEN CONN-BUFFER(WS-LINE-FEED + 1:1) = X'0D'
                    AND WS-LINE-FEED + 2 > CONN-RECEIVED
                       MOVE WS-LINE-FEED TO WS-SCAN-FROM
                       EXIT PERFORM
                   WHEN CONN-BUFFER(WS-LINE-FEED + 1:2) = X'0D0A'
                       COMPUTE CONN-HEAD-LENGTH = WS-LINE-FEED + 2
                       SET HEAD-COMPLETE TO TRUE
                   WHEN OTHER
                       COMPUTE WS-SCAN-FROM = WS-LINE-FEED + 1
               END-EVALUATE
           END-PERFORM.

      *----------------------------------------------------------------*
      * 2. THE REQUEST LINE: METHOD, SPACE, TARGET, SPACE, VERSION.    *
      *----------------------------------------------------------------*
       2000-PARSE-REQUEST-LINE.
           MOVE 1 TO WS-LINE-START
           PERFORM 2900-MEASURE-LINE
           MOVE 0 TO WS-FIRST-SPACE WS-SECOND-SPACE
           PERFORM VARYING WS-INDEX FROM 1 BY 1
                   UNTIL WS-INDEX > WS-LINE-LENGTH
                      OR WS-SECOND-SPACE > 0
               IF CONN-BUFFER(WS-INDEX:1) = SPACE
                   IF WS-FIRST-SPACE = 0
                       MOVE WS-INDEX TO WS-FIRST-SPACE
                   ELSE
                       MOVE WS-INDEX TO WS-SECOND-SPACE
                   END-IF
               END-IF
           END-PERFORM
           IF WS-SECOND-SPACE = 0
               PERFORM 8100-REJECT-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF

      *    THE VERSION: "HTTP/" DIGIT "." DIGIT. AN HTTP/1.0 CLIENT
      *    GETS AN HTTP/1.0 ANSWER, LIKE GO GIVES IT.
           IF WS-LINE-LENGTH - WS-SECOND-SPACE NOT = 8
               PERFORM 8100-REJECT-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
           MOVE CONN-BUFFER(WS-SECOND-SPACE + 1:8) TO WS-VERSION
           IF WS-VERSION(1:5) NOT = 'HTTP/'
              OR WS-VERSION(6:1) IS NOT NUMERIC
              OR WS-VERSION(7:1) NOT = '.'
              OR WS-VERSION(8:1) IS NOT NUMERIC
               PERFORM 8100-REJECT-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
           MOVE WS-VERSION(6:1) TO WS-MAJOR-VERSION
           MOVE WS-VERSION(8:1) TO REQ-MINOR-VERSION
           IF WS-VERSION = 'HTTP/1.0'
               MOVE 'HTTP/1.0' TO RSP-PROTOCOL
           END-IF

      *    THE METHOD: ONE OR MORE TOKEN CHARACTERS.
           COMPUTE REQ-METHOD-LENGTH = WS-FIRST-SPACE - 1
           IF REQ-METHOD-LENGTH = 0
               PERFORM 8100-REJECT-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
           PERFORM VARYING WS-INDEX FROM 1 BY 1
                   UNTIL WS-INDEX > REQ-METHOD-LENGTH
               MOVE CONN-BUFFER(WS-INDEX:1) TO WS-CHARACTER
               IF NOT IS-TOKEN-CHARACTER
                   PERFORM 8100-REJECT-BAD-REQUEST
                   EXIT PARAGRAPH
               END-IF
           END-PERFORM
           IF REQ-METHOD-LENGTH <= LENGTH OF REQ-METHOD
               MOVE CONN-BUFFER(1:REQ-METHOD-LENGTH) TO REQ-METHOD
           END-IF

           COMPUTE WS-TARGET-START = WS-FIRST-SPACE + 1
           COMPUTE WS-TARGET-LENGTH = WS-SECOND-SPACE - WS-FIRST-SPACE
                                    - 1
           PERFORM 2100-PARSE-TARGET.

       2100-PARSE-TARGET.
           IF WS-TARGET-LENGTH = 0
               PERFORM 8100-REJECT-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
           PERFORM VARYING WS-INDEX FROM WS-TARGET-START BY 1
                   UNTIL WS-INDEX >= WS-TARGET-START + WS-TARGET-LENGTH
               MOVE CONN-BUFFER(WS-INDEX:1) TO WS-CHARACTER
               IF IS-CONTROL-CHARACTER
                   PERFORM 8100-REJECT-BAD-REQUEST
                   EXIT PARAGRAPH
               END-IF
           END-PERFORM
           COMPUTE WS-TARGET-END = WS-TARGET-START + WS-TARGET-LENGTH
                                 - 1

      *    "*" IS ONLY FOR "OPTIONS * HTTP/1.1"; THE ROUTER ANSWERS IT.
           IF WS-TARGET-LENGTH = 1
              AND CONN-BUFFER(WS-TARGET-START:1) = '*'
               SET REQ-TARGET-IS-STAR TO TRUE
               EXIT PARAGRAPH
           END-IF
           SET REQ-TARGET-IS-PATH TO TRUE

      *    USUALLY THE TARGET IS A PATH. A CLIENT TALKING TO A PROXY
      *    SENDS A WHOLE URL INSTEAD, "HTTP://HOST/PATH"; KEEP ITS PATH.
           IF CONN-BUFFER(WS-TARGET-START:1) = '/'
               MOVE WS-TARGET-START TO WS-PATH-START
           ELSE
               PERFORM 2200-SKIP-SCHEME-AND-HOST
               IF NOT REQ-IS-READY
                   EXIT PARAGRAPH
               END-IF
           END-IF

      *    THE PATH ENDS AT THE FIRST "?"; THE QUERY IS THE REST.
           MOVE WS-PATH-START TO WS-PATH-END
           PERFORM UNTIL WS-PATH-END > WS-TARGET-END
                   OR CONN-BUFFER(WS-PATH-END:1) = '?'
               ADD 1 TO WS-PATH-END
           END-PERFORM
           COMPUTE REQ-PATH-LENGTH = WS-PATH-END - WS-PATH-START
           COMPUTE REQ-QUERY-LENGTH = WS-TARGET-END - WS-PATH-END
           IF REQ-QUERY-LENGTH < 0
               MOVE 0 TO REQ-QUERY-LENGTH
           END-IF
           IF REQ-PATH-LENGTH > LENGTH OF REQ-PATH
              OR REQ-QUERY-LENGTH > LENGTH OF REQ-QUERY
               MOVE 414 TO WS-REJECT-STATUS
               MOVE 'URI Too Long' TO WS-REJECT-REASON
               PERFORM 8000-REJECT
               EXIT PARAGRAPH
           END-IF

      *    EVERY "%" IN THE PATH MUST BE FOLLOWED BY TWO HEX DIGITS.
           PERFORM VARYING WS-INDEX FROM WS-PATH-START BY 1
                   UNTIL WS-INDEX >= WS-PATH-END
               IF CONN-BUFFER(WS-INDEX:1) = '%'
                   IF WS-INDEX + 2 >= WS-PATH-END
                       PERFORM 8100-REJECT-BAD-REQUEST
                       EXIT PARAGRAPH
                   END-IF
                   MOVE CONN-BUFFER(WS-INDEX + 1:1) TO WS-CHARACTER
                   IF NOT IS-HEX-DIGIT
                       PERFORM 8100-REJECT-BAD-REQUEST
                       EXIT PARAGRAPH
                   END-IF
                   MOVE CONN-BUFFER(WS-INDEX + 2:1) TO WS-CHARACTER
                   IF NOT IS-HEX-DIGIT
                       PERFORM 8100-REJECT-BAD-REQUEST
                       EXIT PARAGRAPH
                   END-IF
               END-IF
           END-PERFORM

           IF REQ-PATH-LENGTH > 0
               MOVE CONN-BUFFER(WS-PATH-START:REQ-PATH-LENGTH)
                 TO REQ-PATH
           END-IF
           IF REQ-QUERY-LENGTH > 0
               MOVE CONN-BUFFER(WS-PATH-END + 1:REQ-QUERY-LENGTH)
                 TO REQ-QUERY
           END-IF.

       2200-SKIP-SCHEME-AND-HOST.
      *    A SCHEME (LETTERS, THEN LETTERS, DIGITS, "+", "-" OR "."),
      *    THEN "://", THEN A HOST UP TO THE FIRST "/" OR "?".
           MOVE CONN-BUFFER(WS-TARGET-START:1) TO WS-CHARACTER
           IF WS-CHARACTER IS NOT ALPHABETIC OR WS-CHARACTER = SPACE
               PERFORM 8100-REJECT-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
           MOVE WS-TARGET-START TO WS-INDEX
           PERFORM UNTIL WS-INDEX > WS-TARGET-END
               MOVE CONN-BUFFER(WS-INDEX:1) TO WS-CHARACTER
               IF NOT IS-SCHEME-CHARACTER
                   EXIT PERFORM
               END-IF
               ADD 1 TO WS-INDEX
           END-PERFORM
           IF WS-INDEX + 2 > WS-TARGET-END
              OR CONN-BUFFER(WS-INDEX:3) NOT = '://'
               PERFORM 8100-REJECT-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
           ADD 3 TO WS-INDEX
           PERFORM UNTIL WS-INDEX > WS-TARGET-END
                   OR CONN-BUFFER(WS-INDEX:1) = '/'
                   OR CONN-BUFFER(WS-INDEX:1) = '?'
               ADD 1 TO WS-INDEX
           END-PERFORM
           MOVE WS-INDEX TO WS-PATH-START.

       2900-MEASURE-LINE.
      *    FROM WS-LINE-START: HOW LONG IS THIS LINE (WITHOUT ITS LINE
      *    FEED OR CARRIAGE RETURN), AND WHERE DOES THE NEXT ONE START?
           MOVE 0 TO WS-COUNT
           INSPECT CONN-BUFFER(WS-LINE-START:
                               CONN-HEAD-LENGTH - WS-LINE-START + 1)
               TALLYING WS-COUNT FOR CHARACTERS BEFORE INITIAL X'0A'
           MOVE WS-COUNT TO WS-LINE-LENGTH
           COMPUTE WS-NEXT-LINE = WS-LINE-START + WS-COUNT + 1
           IF WS-LINE-LENGTH > 0
              AND CONN-BUFFER(WS-LINE-START + WS-LINE-LENGTH - 1:1)
                  = X'0D'
               SUBTRACT 1 FROM WS-LINE-LENGTH
           END-IF.

      *----------------------------------------------------------------*
      * 3. THE HEADERS: "NAME: VALUE", ONE PER LINE.                   *
      *----------------------------------------------------------------*
       3000-PARSE-HEADERS.
           MOVE 0 TO WS-HOST-COUNT
           MOVE 'N' TO WS-TRANSFER-ENCODING WS-EXPECT-SEEN
                       WS-CONTENT-LENGTH-SEEN
           MOVE 'Y' TO WS-FIRST-HEADER
           MOVE WS-NEXT-LINE TO WS-LINE-START
           PERFORM UNTIL WS-LINE-START > CONN-HEAD-LENGTH
                   OR NOT REQ-IS-READY
               PERFORM 2900-MEASURE-LINE
               IF WS-LINE-LENGTH = 0
                   EXIT PERFORM
               END-IF
               PERFORM 3100-PARSE-ONE-HEADER
               MOVE WS-NEXT-LINE TO WS-LINE-START
           END-PERFORM.

       3100-PARSE-ONE-HEADER.
      *    A LINE THAT STARTS WITH A SPACE CONTINUES THE HEADER ABOVE
      *    IT (AN OLD STYLE GO STILL ACCEPTS). NONE OF THE HEADERS WE
      *    READ IS EVER WRITTEN THAT WAY, SO IT IS SIMPLY PASSED OVER.
           MOVE CONN-BUFFER(WS-LINE-START:1) TO WS-CHARACTER
           IF IS-SPACE-OR-TAB
               IF ON-FIRST-HEADER
                   PERFORM 8100-REJECT-BAD-REQUEST
               END-IF
               EXIT PARAGRAPH
           END-IF
           MOVE 'N' TO WS-FIRST-HEADER

           MOVE 0 TO WS-COLON
           PERFORM VARYING WS-INDEX FROM WS-LINE-START BY 1
                   UNTIL WS-INDEX >= WS-LINE-START + WS-LINE-LENGTH
                      OR WS-COLON > 0
               IF CONN-BUFFER(WS-INDEX:1) = ':'
                   MOVE WS-INDEX TO WS-COLON
               END-IF
           END-PERFORM
           IF WS-COLON = 0
               PERFORM 8100-REJECT-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
           IF WS-COLON = WS-LINE-START
               PERFORM 8200-REJECT-BAD-HEADER-NAME
               EXIT PARAGRAPH
           END-IF
           PERFORM VARYING WS-INDEX FROM WS-LINE-START BY 1
                   UNTIL WS-INDEX >= WS-COLON
               MOVE CONN-BUFFER(WS-INDEX:1) TO WS-CHARACTER
               IF NOT IS-TOKEN-CHARACTER
                   PERFORM 8200-REJECT-BAD-HEADER-NAME
                   EXIT PARAGRAPH
               END-IF
           END-PERFORM

      *    THE VALUE, WITHOUT THE SPACES AND TABS AROUND IT.
           COMPUTE WS-VALUE-START = WS-COLON + 1
           COMPUTE WS-VALUE-END = WS-LINE-START + WS-LINE-LENGTH - 1
           PERFORM UNTIL WS-VALUE-START > WS-VALUE-END
               MOVE CONN-BUFFER(WS-VALUE-START:1) TO WS-CHARACTER
               IF NOT IS-SPACE-OR-TAB
                   EXIT PERFORM
               END-IF
               ADD 1 TO WS-VALUE-START
           END-PERFORM
           PERFORM UNTIL WS-VALUE-END < WS-VALUE-START
               MOVE CONN-BUFFER(WS-VALUE-END:1) TO WS-CHARACTER
               IF NOT IS-SPACE-OR-TAB
                   EXIT PERFORM
               END-IF
               SUBTRACT 1 FROM WS-VALUE-END
           END-PERFORM
           COMPUTE WS-VALUE-LENGTH = WS-VALUE-END - WS-VALUE-START + 1
           PERFORM VARYING WS-INDEX FROM WS-VALUE-START BY 1
                   UNTIL WS-INDEX > WS-VALUE-END
               MOVE CONN-BUFFER(WS-INDEX:1) TO WS-CHARACTER
               IF IS-CONTROL-CHARACTER AND WS-CHARACTER NOT = X'09'
                   PERFORM 8100-REJECT-BAD-REQUEST
                   EXIT PARAGRAPH
               END-IF
           END-PERFORM

      *    HEADER NAMES IGNORE CASE. ONLY FOUR OF THEM MATTER HERE.
           MOVE SPACES TO WS-HEADER-NAME
           IF WS-COLON - WS-LINE-START <= LENGTH OF WS-HEADER-NAME
               MOVE CONN-BUFFER(WS-LINE-START:WS-COLON - WS-LINE-START)
                 TO WS-HEADER-NAME
           END-IF
           INSPECT WS-HEADER-NAME
               CONVERTING 'abcdefghijklmnopqrstuvwxyz'
                       TO 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
           EVALUATE WS-HEADER-NAME
               WHEN 'HOST'
                   ADD 1 TO WS-HOST-COUNT
                   MOVE SPACES TO WS-HOST-VALUE
                   MOVE WS-VALUE-LENGTH TO WS-HOST-LENGTH
                   IF WS-VALUE-LENGTH > 0
                      AND WS-VALUE-LENGTH <= LENGTH OF WS-HOST-VALUE
                       MOVE CONN-BUFFER(WS-VALUE-START:WS-VALUE-LENGTH)
                         TO WS-HOST-VALUE
                   END-IF
               WHEN 'CONTENT-LENGTH'
                   PERFORM 3200-READ-CONTENT-LENGTH
               WHEN 'TRANSFER-ENCODING'
                   SET HAS-TRANSFER-ENCODING TO TRUE
               WHEN 'EXPECT'
                   IF NOT HAS-EXPECT
                       SET HAS-EXPECT TO TRUE
                       MOVE SPACES TO WS-EXPECT-VALUE
                       IF WS-VALUE-LENGTH > 0
                           MOVE CONN-BUFFER(WS-VALUE-START:
                                            WS-VALUE-LENGTH)
                             TO WS-EXPECT-VALUE
                       END-IF
                   END-IF
           END-EVALUATE.

       3200-READ-CONTENT-LENGTH.
      *    DIGITS ONLY, AT MOST 2**63 - 1. SEVERAL CONTENT-LENGTH
      *    HEADERS ARE ALLOWED ONLY IF THEY ALL SAY THE SAME THING.
           IF WS-VALUE-LENGTH = 0
              OR WS-VALUE-LENGTH > LENGTH OF WS-CONTENT-LENGTH-TEXT
               PERFORM 8100-REJECT-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
           IF HAS-CONTENT-LENGTH
               IF CONN-BUFFER(WS-VALUE-START:WS-VALUE-LENGTH)
                  NOT = WS-CONTENT-LENGTH-TEXT
                   PERFORM 8100-REJECT-BAD-REQUEST
               END-IF
               EXIT PARAGRAPH
           END-IF
           SET HAS-CONTENT-LENGTH TO TRUE
           MOVE CONN-BUFFER(WS-VALUE-START:WS-VALUE-LENGTH)
             TO WS-CONTENT-LENGTH-TEXT
           IF CONN-BUFFER(WS-VALUE-START:WS-VALUE-LENGTH)
              IS NOT NUMERIC
               PERFORM 8100-REJECT-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
      *    LEADING ZEROS ARE ALLOWED; COUNT THE DIGITS AFTER THEM.
           MOVE WS-VALUE-START TO WS-FIRST-DIGIT
           PERFORM UNTIL WS-FIRST-DIGIT >= WS-VALUE-END
                   OR CONN-BUFFER(WS-FIRST-DIGIT:1) NOT = '0'
               ADD 1 TO WS-FIRST-DIGIT
           END-PERFORM
           COMPUTE WS-DIGIT-COUNT = WS-VALUE-END - WS-FIRST-DIGIT + 1
           IF WS-DIGIT-COUNT > 19
               PERFORM 8100-REJECT-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
           MOVE CONN-BUFFER(WS-FIRST-DIGIT:WS-DIGIT-COUNT) TO WS-NUMBER
           IF WS-NUMBER > 9223372036854775807
               PERFORM 8100-REJECT-BAD-REQUEST
               EXIT PARAGRAPH
           END-IF
           MOVE WS-NUMBER TO REQ-CONTENT-LENGTH.

      *----------------------------------------------------------------*
      * 4. THE CHECKS GO'S SERVER MAKES ONCE THE HEADERS ARE IN.       *
      *----------------------------------------------------------------*
       4000-CHECK-REQUEST.
           EVALUATE TRUE
               WHEN WS-HOST-COUNT > 1
                   PERFORM 8100-REJECT-BAD-REQUEST
      *        CHUNKED (OR ANY OTHER TRANSFER-ENCODED) REQUEST BODIES
      *        ARE NOT SUPPORTED. AN HTTP/1.0 CLIENT CANNOT USE THEM,
      *        SO FOR IT THE HEADER IS IGNORED, AS IN GO.
               WHEN HAS-TRANSFER-ENCODING
                AND (WS-MAJOR-VERSION > 1 OR REQ-MINOR-VERSION > 0)
                   MOVE 501 TO WS-REJECT-STATUS
                   MOVE 'Not Implemented' TO WS-REJECT-REASON
                   PERFORM 8000-REJECT
                   MOVE 'Unsupported transfer encoding' TO RSP-BODY
                   MOVE 29 TO RSP-BODY-LENGTH
               WHEN WS-MAJOR-VERSION NOT = 1
                   MOVE 505 TO WS-REJECT-STATUS
                   MOVE SPACES TO WS-REJECT-REASON
                   STRING 'HTTP Version Not Supported: '
                          'unsupported protocol version'
                       DELIMITED BY SIZE INTO WS-REJECT-REASON
                   END-STRING
                   PERFORM 8000-REJECT
               WHEN REQ-MINOR-VERSION > 0 AND WS-HOST-COUNT = 0
                   MOVE 400 TO WS-REJECT-STATUS
                   MOVE 'Bad Request: missing required Host header'
                     TO WS-REJECT-REASON
                   PERFORM 8000-REJECT
               WHEN WS-HOST-COUNT = 1
                   PERFORM 4100-CHECK-HOST-VALUE
           END-EVALUATE
           IF REQ-IS-READY AND HAS-EXPECT
              AND WS-EXPECT-VALUE NOT = SPACES
               PERFORM 4200-CHECK-EXPECT
           END-IF.

       4100-CHECK-HOST-VALUE.
           IF WS-HOST-LENGTH > LENGTH OF WS-HOST-VALUE
               PERFORM 4110-REJECT-BAD-HOST
               EXIT PARAGRAPH
           END-IF
           PERFORM VARYING WS-INDEX FROM 1 BY 1
                   UNTIL WS-INDEX > WS-HOST-LENGTH
               MOVE WS-HOST-VALUE(WS-INDEX:1) TO WS-CHARACTER
               IF NOT IS-HOST-CHARACTER
                   PERFORM 4110-REJECT-BAD-HOST
                   EXIT PARAGRAPH
               END-IF
           END-PERFORM.

       4110-REJECT-BAD-HOST.
           MOVE 400 TO WS-REJECT-STATUS
           MOVE 'Bad Request: malformed Host header' TO WS-REJECT-REASON
           PERFORM 8000-REJECT.

       4200-CHECK-EXPECT.
      *    "EXPECT: 100-CONTINUE" IS THE ONLY EXPECTATION ANYONE USES.
      *    ANY OTHER ONE IS REFUSED WITH 417.
           INSPECT WS-EXPECT-VALUE
               CONVERTING 'abcdefghijklmnopqrstuvwxyz'
                       TO 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
           MOVE 0 TO WS-COUNT
           INSPECT WS-EXPECT-VALUE TALLYING WS-COUNT
               FOR ALL '100-CONTINUE'
           IF WS-COUNT = 0
               MOVE 417 TO WS-REJECT-STATUS
               MOVE 'Expectation Failed' TO WS-REJECT-REASON
               PERFORM 8000-REJECT
               MOVE SPACES TO RSP-CONTENT-TYPE
               MOVE 0 TO RSP-BODY-LENGTH
           ELSE
               IF REQ-MINOR-VERSION > 0 AND REQ-CONTENT-LENGTH > 0
                   SET REQ-EXPECTS-CONTINUE TO TRUE
               END-IF
           END-IF.

      *----------------------------------------------------------------*
      * 5. THE BODY: CONTENT-LENGTH BYTES, BUT NEVER MORE THAN 1 MIB.  *
      *    BYTES THAT CAME IN WITH THE HEAD ARE USED FIRST.            *
      *----------------------------------------------------------------*
       5000-READ-BODY.
           MOVE 0 TO REQ-BODY-LENGTH
           IF REQ-CONTENT-LENGTH <= 0
               EXIT PARAGRAPH
           END-IF
           MOVE REQ-CONTENT-LENGTH TO WS-WANTED
           IF WS-WANTED > LENGTH OF REQ-BODY
               MOVE LENGTH OF REQ-BODY TO WS-WANTED
           END-IF

           COMPUTE WS-COUNT = CONN-RECEIVED - CONN-HEAD-LENGTH
           IF WS-COUNT > WS-WANTED
               MOVE WS-WANTED TO WS-COUNT
           END-IF
           IF WS-COUNT > 0
               MOVE CONN-BUFFER(CONN-HEAD-LENGTH + 1:WS-COUNT)
                 TO REQ-BODY(1:WS-COUNT)
               MOVE WS-COUNT TO REQ-BODY-LENGTH
           END-IF

      *    A CLIENT THAT SENT "EXPECT: 100-CONTINUE" WAITS FOR THIS
      *    BEFORE IT SENDS THE BODY.
           IF REQ-BODY-LENGTH < WS-WANTED AND REQ-EXPECTS-CONTINUE
               MOVE SPACES TO WS-CONTINUE-RESPONSE
               STRING 'HTTP/1.1 100 Continue' X'0D0A0D0A'
                   DELIMITED BY SIZE INTO WS-CONTINUE-RESPONSE
               END-STRING
               CALL 'send' USING BY VALUE CONN-SOCKET
                                 BY REFERENCE WS-CONTINUE-RESPONSE
                                 BY VALUE WS-CONTINUE-LENGTH
                                 BY VALUE MSG-NOSIGNAL
                   RETURNING WS-SENT
               END-CALL
           END-IF

           SET CLIENT-CONNECTED TO TRUE
           PERFORM UNTIL REQ-BODY-LENGTH >= WS-WANTED OR CLIENT-GONE
               PERFORM 9100-SET-TIME-LEFT
               IF CLIENT-CONNECTED
                   COMPUTE WS-RECEIVED-NOW = WS-WANTED - REQ-BODY-LENGTH
                   CALL 'recv' USING BY VALUE CONN-SOCKET
                                     BY REFERENCE
                                        REQ-BODY(REQ-BODY-LENGTH + 1:
                                                 WS-RECEIVED-NOW)
                                     BY VALUE WS-RECEIVED-NOW
                                     BY VALUE 0
                       RETURNING WS-RECEIVED-NOW
                   END-CALL
                   IF WS-RECEIVED-NOW > 0
                       ADD WS-RECEIVED-NOW TO REQ-BODY-LENGTH
                   ELSE
                       SET CLIENT-GONE TO TRUE
                   END-IF
               END-IF
           END-PERFORM.

      *----------------------------------------------------------------*
      * REFUSALS. GO WRITES THE REASON INTO THE STATUS LINE AND REPEATS*
      * IT AS A PLAIN-TEXT BODY: "400 Bad Request".                    *
      *----------------------------------------------------------------*
       8000-REJECT.
           SET REQ-IS-REJECTED TO TRUE
           MOVE 'HTTP/1.1' TO RSP-PROTOCOL
           MOVE WS-REJECT-STATUS TO RSP-STATUS
           MOVE WS-REJECT-REASON TO RSP-REASON
           MOVE 'text/plain; charset=utf-8' TO RSP-CONTENT-TYPE
           MOVE SPACES TO RSP-BODY(1:100)
           STRING RSP-STATUS ' ' FUNCTION TRIM(RSP-REASON TRAILING)
               DELIMITED BY SIZE INTO RSP-BODY
           END-STRING
           COMPUTE RSP-BODY-LENGTH = 4 + FUNCTION LENGTH(
               FUNCTION TRIM(RSP-REASON TRAILING)).

       8100-REJECT-BAD-REQUEST.
           MOVE 400 TO WS-REJECT-STATUS
           MOVE 'Bad Request' TO WS-REJECT-REASON
           PERFORM 8000-REJECT.

       8200-REJECT-BAD-HEADER-NAME.
           MOVE 400 TO WS-REJECT-STATUS
           MOVE 'Bad Request: invalid header name' TO WS-REJECT-REASON
           PERFORM 8000-REJECT.

      *----------------------------------------------------------------*
      * RECEIVING. BEFORE EACH RECV(), TELL THE SOCKET HOW MUCH OF THE *
      * 10 SECONDS IS LEFT, SO A CLIENT THAT SENDS ONE BYTE A SECOND   *
      * IS STILL CUT OFF ON TIME.                                      *
      *----------------------------------------------------------------*
       9000-RECEIVE-MORE-HEAD.
           PERFORM 9100-SET-TIME-LEFT
           IF CLIENT-GONE
               EXIT PARAGRAPH
           END-IF
           COMPUTE WS-WANTED = WS-HEAD-LIMIT - CONN-RECEIVED
           IF WS-WANTED > 65536
               MOVE 65536 TO WS-WANTED
           END-IF
           CALL 'recv' USING BY VALUE CONN-SOCKET
                             BY REFERENCE
                                CONN-BUFFER(CONN-RECEIVED + 1:WS-WANTED)
                             BY VALUE WS-WANTED
                             BY VALUE 0
               RETURNING WS-RECEIVED-NOW
           END-CALL
           IF WS-RECEIVED-NOW > 0
               ADD WS-RECEIVED-NOW TO CONN-RECEIVED
           ELSE
      *        0 MEANS THE CLIENT HUNG UP; -1 MEANS TIME RAN OUT (OR
      *        THE CONNECTION BROKE). EITHER WAY THERE IS NOBODY TO
      *        ANSWER.
               SET CLIENT-GONE TO TRUE
           END-IF.

       9100-SET-TIME-LEFT.
           CALL 'UTCCLOCK' USING CLOCK-READING
           COMPUTE WS-TICKS-LEFT = CONN-DEADLINE - CLK-TICKS
           IF WS-TICKS-LEFT <= 0
               SET CLIENT-GONE TO TRUE
               EXIT PARAGRAPH
           END-IF
           COMPUTE WS-TIMEVAL-SECONDS = WS-TICKS-LEFT / 100
           COMPUTE WS-TIMEVAL-MICROS =
               FUNCTION MOD(WS-TICKS-LEFT, 100) * 10000
           CALL 'setsockopt' USING BY VALUE CONN-SOCKET
                                   BY VALUE SOL-SOCKET
                                   BY VALUE SO-RCVTIMEO
                                   BY REFERENCE WS-TIMEVAL
                                   BY VALUE WS-TIMEVAL-SIZE
               RETURNING WS-RC
           END-CALL.
