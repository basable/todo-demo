      *================================================================*
      * HTTPSEND - SEND ONE HTTP RESPONSE AND CLOSE THE CONNECTION.    *
      *                                                                *
      *     HTTP/1.1 201 Created                                       *
      *     Content-Security-Policy: frame-ancestors 'self' ...        *
      *     Content-Type: application/json                             *
      *     X-Content-Type-Options: nosniff                            *
      *     Date: Sun, 11 Oct 2026 12:28:23 GMT                        *
      *     Content-Length: 83                                         *
      *     Connection: close                                          *
      *     (A BLANK LINE, THEN THE BODY)                              *
      *                                                                *
      * EVERY RESPONSE CARRIES THE TWO SECURITY HEADERS: THE PAGE MAY  *
      * ONLY BE FRAMED BY ITSELF AND BY BASABLE.COM, AND THE BROWSER   *
      * MUST NOT SECOND-GUESS THE CONTENT TYPE.                        *
      *================================================================*
       IDENTIFICATION DIVISION.
       PROGRAM-ID. HTTPSEND.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. LINUX-X86-64.
       OBJECT-COMPUTER. LINUX-X86-64.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY CLOCKREC.

       01  SOL-SOCKET                  BINARY-LONG VALUE 1.
       01  SO-RCVTIMEO                 BINARY-LONG VALUE 20.
      *    SEND() FLAGS: DO NOT KILL THE PROCESS WITH SIGPIPE IF THE
      *    CLIENT HAS GONE; AND "MORE IS COMING", SO THE HEADERS AND
      *    THE BODY LEAVE IN AS FEW NETWORK PACKETS AS POSSIBLE.
       01  MSG-NOSIGNAL                BINARY-LONG VALUE 16384.
       01  MSG-MORE                    BINARY-LONG VALUE 32768.
       01  SHUT-WR                     BINARY-LONG VALUE 1.
       01  WS-TIMEVAL-SIZE             BINARY-LONG VALUE 16.
       01  WS-ONE-SECOND.
           05  FILLER                  BINARY-DOUBLE VALUE 1.
           05  FILLER                  BINARY-DOUBLE VALUE 0.

       01  CR-LF                       PIC XX VALUE X'0D0A'.
       01  WS-HEAD                     PIC X(65536).
       01  WS-HEAD-LENGTH              BINARY-LONG.
       01  WS-POINTER                  BINARY-LONG.
       01  WS-LENGTH-SHOWN             PIC Z(8)9.
       01  WS-BODY-TO-SEND             BINARY-LONG.

       01  WS-OFFSET                   BINARY-LONG.
       01  WS-REMAINING                BINARY-DOUBLE.
       01  WS-SENT                     BINARY-DOUBLE.
       01  WS-FLAGS                    BINARY-LONG.
       01  WS-RC                       BINARY-LONG.
       01  WS-SEND-STATE               PIC X.
           88  SEND-WORKING            VALUE 'W'.
           88  SEND-FAILED             VALUE 'F'.

       01  WS-DRAIN-BUFFER             PIC X(65536).
       01  WS-DRAIN-SIZE               BINARY-DOUBLE VALUE 65536.
       01  WS-DRAINED                  BINARY-DOUBLE.
       01  WS-DRAINED-NOW              BINARY-DOUBLE.
       01  WS-DRAIN-UNTIL              BINARY-DOUBLE.
       01  WS-DRAIN-LIMIT              BINARY-DOUBLE VALUE 1048576.

       LINKAGE SECTION.
       COPY HTTPCONN.
       COPY HTTPRSP.

       PROCEDURE DIVISION USING HTTP-CONNECTION HTTP-RESPONSE.
       0000-MAIN.
           PERFORM 1000-BUILD-HEAD
           PERFORM 2000-SEND-RESPONSE
           PERFORM 3000-CLOSE-CONNECTION
           GOBACK.

       1000-BUILD-HEAD.
           IF RSP-REASON = SPACES
               PERFORM 1100-STANDARD-REASON
           END-IF
           CALL 'UTCCLOCK' USING CLOCK-READING

      *    204 NO CONTENT HAS NO BODY AND NO CONTENT-LENGTH. A HEAD
      *    REQUEST GETS THE LENGTH THE BODY WOULD HAVE, BUT NOT THE
      *    BODY.
           MOVE RSP-BODY-LENGTH TO WS-BODY-TO-SEND
           IF RSP-STATUS = 204
               MOVE 0 TO WS-BODY-TO-SEND
           END-IF
           IF RSP-BODY-SUPPRESSED
               MOVE 0 TO WS-BODY-TO-SEND
           END-IF

      *    STRING ... WITH POINTER APPENDS EACH PIECE WHERE THE LAST
      *    ONE ENDED; WS-POINTER ENDS UP ONE PAST THE LAST BYTE.
           MOVE 1 TO WS-POINTER
           STRING RSP-PROTOCOL ' ' RSP-STATUS ' '
                  FUNCTION TRIM(RSP-REASON TRAILING) CR-LF
               DELIMITED BY SIZE INTO WS-HEAD WITH POINTER WS-POINTER
           END-STRING
           IF RSP-ALLOW NOT = SPACES
               STRING 'Allow: ' FUNCTION TRIM(RSP-ALLOW TRAILING) CR-LF
                   DELIMITED BY SIZE INTO WS-HEAD
                   WITH POINTER WS-POINTER
               END-STRING
           END-IF
           STRING 'Content-Security-Policy: frame-ancestors '
                  "'self' https://basable.com" CR-LF
               DELIMITED BY SIZE INTO WS-HEAD WITH POINTER WS-POINTER
           END-STRING
           IF RSP-CONTENT-TYPE NOT = SPACES
               STRING 'Content-Type: '
                      FUNCTION TRIM(RSP-CONTENT-TYPE TRAILING) CR-LF
                   DELIMITED BY SIZE INTO WS-HEAD
                   WITH POINTER WS-POINTER
               END-STRING
           END-IF
           IF RSP-LOCATION-LENGTH > 0
               STRING 'Location: '
                      RSP-LOCATION(1:RSP-LOCATION-LENGTH) CR-LF
                   DELIMITED BY SIZE INTO WS-HEAD
                   WITH POINTER WS-POINTER
               END-STRING
           END-IF
           STRING 'X-Content-Type-Options: nosniff' CR-LF
                  'Date: ' CLK-HTTP-DATE CR-LF
               DELIMITED BY SIZE INTO WS-HEAD WITH POINTER WS-POINTER
           END-STRING
           IF RSP-STATUS NOT = 204
               MOVE RSP-BODY-LENGTH TO WS-LENGTH-SHOWN
               STRING 'Content-Length: '
                      FUNCTION TRIM(WS-LENGTH-SHOWN LEADING) CR-LF
                   DELIMITED BY SIZE INTO WS-HEAD
                   WITH POINTER WS-POINTER
               END-STRING
           END-IF
           STRING 'Connection: close' CR-LF CR-LF
               DELIMITED BY SIZE INTO WS-HEAD WITH POINTER WS-POINTER
           END-STRING
           COMPUTE WS-HEAD-LENGTH = WS-POINTER - 1.

       1100-STANDARD-REASON.
           EVALUATE RSP-STATUS
               WHEN 200 MOVE 'OK'                      TO RSP-REASON
               WHEN 201 MOVE 'Created'                 TO RSP-REASON
               WHEN 204 MOVE 'No Content'              TO RSP-REASON
               WHEN 301 MOVE 'Moved Permanently'       TO RSP-REASON
               WHEN 400 MOVE 'Bad Request'             TO RSP-REASON
               WHEN 404 MOVE 'Not Found'               TO RSP-REASON
               WHEN 405 MOVE 'Method Not Allowed'      TO RSP-REASON
               WHEN 500 MOVE 'Internal Server Error'   TO RSP-REASON
               WHEN OTHER MOVE 'Unknown'               TO RSP-REASON
           END-EVALUATE.

       2000-SEND-RESPONSE.
      *    SEND() MAY TAKE ONLY PART OF WHAT IT IS GIVEN; KEEP CALLING
      *    UNTIL ALL OF IT IS GONE, OR UNTIL IT FAILS (THE CLIENT LEFT,
      *    OR STOPPED READING FOR 10 SECONDS).
           SET SEND-WORKING TO TRUE
           MOVE MSG-NOSIGNAL TO WS-FLAGS
           IF WS-BODY-TO-SEND > 0
               ADD MSG-MORE TO WS-FLAGS
           END-IF
           MOVE 1 TO WS-OFFSET
           MOVE WS-HEAD-LENGTH TO WS-REMAINING
           PERFORM UNTIL WS-REMAINING = 0 OR SEND-FAILED
               CALL 'send' USING BY VALUE CONN-SOCKET
                                 BY REFERENCE
                                    WS-HEAD(WS-OFFSET:WS-REMAINING)
                                 BY VALUE WS-REMAINING
                                 BY VALUE WS-FLAGS
                   RETURNING WS-SENT
               END-CALL
               PERFORM 2100-COUNT-SENT
           END-PERFORM

           MOVE MSG-NOSIGNAL TO WS-FLAGS
           MOVE 1 TO WS-OFFSET
           MOVE WS-BODY-TO-SEND TO WS-REMAINING
           PERFORM UNTIL WS-REMAINING = 0 OR SEND-FAILED
               CALL 'send' USING BY VALUE CONN-SOCKET
                                 BY REFERENCE
                                    RSP-BODY(WS-OFFSET:WS-REMAINING)
                                 BY VALUE WS-REMAINING
                                 BY VALUE WS-FLAGS
                   RETURNING WS-SENT
               END-CALL
               PERFORM 2100-COUNT-SENT
           END-PERFORM.

       2100-COUNT-SENT.
           IF WS-SENT > 0
               ADD WS-SENT TO WS-OFFSET
               SUBTRACT WS-SENT FROM WS-REMAINING
           ELSE
               SET SEND-FAILED TO TRUE
           END-IF.

       3000-CLOSE-CONNECTION.
      *    SAY "NO MORE FROM US" (SHUTDOWN), THEN READ AND THROW AWAY
      *    WHATEVER THE CLIENT STILL SENDS, FOR AT MOST A SECOND.
      *    CLOSING A SOCKET WITH UNREAD DATA IN IT MAKES THE KERNEL
      *    RESET THE CONNECTION, AND A RESET CAN WIPE OUT THE RESPONSE
      *    BEFORE THE CLIENT HAS READ IT.
           CALL 'shutdown' USING BY VALUE CONN-SOCKET BY VALUE SHUT-WR
               RETURNING WS-RC
           END-CALL
           CALL 'setsockopt' USING BY VALUE CONN-SOCKET
                                   BY VALUE SOL-SOCKET
                                   BY VALUE SO-RCVTIMEO
                                   BY REFERENCE WS-ONE-SECOND
                                   BY VALUE WS-TIMEVAL-SIZE
               RETURNING WS-RC
           END-CALL
           CALL 'UTCCLOCK' USING CLOCK-READING
           COMPUTE WS-DRAIN-UNTIL = CLK-TICKS + 100
           MOVE 0 TO WS-DRAINED
           PERFORM UNTIL WS-DRAINED > WS-DRAIN-LIMIT
               CALL 'recv' USING BY VALUE CONN-SOCKET
                                 BY REFERENCE WS-DRAIN-BUFFER
                                 BY VALUE WS-DRAIN-SIZE
                                 BY VALUE 0
                   RETURNING WS-DRAINED-NOW
               END-CALL
               IF WS-DRAINED-NOW <= 0
                   EXIT PERFORM
               END-IF
               ADD WS-DRAINED-NOW TO WS-DRAINED
               CALL 'UTCCLOCK' USING CLOCK-READING
               IF CLK-TICKS > WS-DRAIN-UNTIL
                   EXIT PERFORM
               END-IF
           END-PERFORM
           CALL 'close' USING BY VALUE CONN-SOCKET
               RETURNING WS-RC
           END-CALL.
