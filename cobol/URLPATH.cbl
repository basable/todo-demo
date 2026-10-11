      *================================================================*
      * URLPATH - TIDY AND DECODE URL PATHS, THE WAY GO'S NET/HTTP     *
      * DOES IT.                                                       *
      *                                                                *
      * 'CLEAN'    "/A//B/./C/../D" BECOMES "/A/B/D". A TRAILING "/"   *
      *            STAYS. THE SERVER REDIRECTS UNTIDY PATHS TO THE     *
      *            TIDY ONE, JUST AS GO'S SERVEMUX DOES.               *
      * 'CLEANDIR' THE SAME, BUT A TRAILING "/" GOES TOO               *
      *            (GO'S PATH.CLEAN).                                  *
      * 'DECODE'   "%41" BECOMES "A".                                  *
      *                                                                *
      * NOTHING HERE EVER TOUCHES THE DISK: A TIDY PATH IS ONLY EVER   *
      * COMPARED WITH THE FIXED NAMES IN WEBTABLE.                     *
      *================================================================*
       IDENTIFICATION DIVISION.
       PROGRAM-ID. URLPATH.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. LINUX-X86-64.
       OBJECT-COMPUTER. LINUX-X86-64.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-PATH                     PIC X(8208).
       01  WS-PATH-LENGTH              BINARY-LONG.
      *    READ POSITION, BYTES WRITTEN, AND HOW FAR BACK A ".." MAY
      *    GO (NEVER PAST THE LEADING "/").
       01  WS-READ                     BINARY-LONG.
       01  WS-WRITTEN                  BINARY-LONG.
       01  WS-FLOOR                    BINARY-LONG.

       01  WS-HEX-CHARACTER            PIC X.
           88  IS-HEX-DIGIT            VALUES '0' THRU '9'
                                              'A' THRU 'F'
                                              'a' THRU 'f'.
       01  WS-HIGH-NIBBLE              BINARY-LONG.
       01  WS-LOW-NIBBLE               BINARY-LONG.
       01  WS-NIBBLE                   BINARY-LONG.
       01  WS-BYTE-VALUE               BINARY-CHAR UNSIGNED.
       01  WS-BYTE REDEFINES WS-BYTE-VALUE PIC X.

       LINKAGE SECTION.
       COPY URLWORK.

       PROCEDURE DIVISION USING URL-WORK.
       0000-MAIN.
           EVALUATE UW-FUNCTION
               WHEN 'CLEAN'
               WHEN 'CLEANDIR'
                   PERFORM 1000-CLEAN-PATH
               WHEN 'DECODE'
                   PERFORM 3000-PERCENT-DECODE
           END-EVALUATE
           GOBACK.

       1000-CLEAN-PATH.
      *    AN EMPTY PATH MEANS "/", AND A PATH ALWAYS STARTS WITH "/".
           MOVE 0 TO WS-PATH-LENGTH
           IF UW-INPUT-LENGTH = 0 OR UW-INPUT(1:1) NOT = '/'
               MOVE '/' TO WS-PATH(1:1)
               MOVE 1 TO WS-PATH-LENGTH
           END-IF
           IF UW-INPUT-LENGTH > 0
               MOVE UW-INPUT(1:UW-INPUT-LENGTH)
                 TO WS-PATH(WS-PATH-LENGTH + 1:UW-INPUT-LENGTH)
               ADD UW-INPUT-LENGTH TO WS-PATH-LENGTH
           END-IF
           PERFORM 2000-DROP-DOTS-AND-SLASHES
      *    GO'S SERVEMUX PUTS A TRAILING "/" BACK; PATH.CLEAN DOES NOT.
           IF UW-FUNCTION = 'CLEAN'
              AND WS-PATH(WS-PATH-LENGTH:1) = '/'
              AND UW-OUTPUT-LENGTH > 1
               ADD 1 TO UW-OUTPUT-LENGTH
               MOVE '/' TO UW-OUTPUT(UW-OUTPUT-LENGTH:1)
           END-IF.

       2000-DROP-DOTS-AND-SLASHES.
      *    A LINE-BY-LINE PORT OF GO'S PATH.CLEAN FOR A PATH THAT
      *    STARTS WITH "/". IT COPIES ONE PATH ELEMENT AT A TIME FROM
      *    WS-PATH TO UW-OUTPUT, SKIPPING EMPTY AND "." ELEMENTS, AND
      *    FOR ".." TAKING BACK THE ELEMENT IT COPIED LAST.
           MOVE '/' TO UW-OUTPUT(1:1)
           MOVE 1 TO WS-WRITTEN
           MOVE 1 TO WS-FLOOR
           MOVE 2 TO WS-READ
           PERFORM UNTIL WS-READ > WS-PATH-LENGTH
               EVALUATE TRUE
                   WHEN WS-PATH(WS-READ:1) = '/'
                       ADD 1 TO WS-READ
                   WHEN WS-PATH(WS-READ:1) = '.'
                    AND (WS-READ = WS-PATH-LENGTH
                         OR WS-PATH(WS-READ + 1:1) = '/')
                       ADD 1 TO WS-READ
                   WHEN WS-PATH(WS-READ:1) = '.'
                    AND WS-READ < WS-PATH-LENGTH
                    AND WS-PATH(WS-READ + 1:1) = '.'
                    AND (WS-READ + 1 = WS-PATH-LENGTH
                         OR WS-PATH(WS-READ + 2:1) = '/')
                       ADD 2 TO WS-READ
                       IF WS-WRITTEN > WS-FLOOR
                           SUBTRACT 1 FROM WS-WRITTEN
                           PERFORM UNTIL WS-WRITTEN <= WS-FLOOR
                                   OR UW-OUTPUT(WS-WRITTEN + 1:1) = '/'
                               SUBTRACT 1 FROM WS-WRITTEN
                           END-PERFORM
                       END-IF
                   WHEN OTHER
                       IF WS-WRITTEN NOT = 1
                           ADD 1 TO WS-WRITTEN
                           MOVE '/' TO UW-OUTPUT(WS-WRITTEN:1)
                       END-IF
                       PERFORM UNTIL WS-READ > WS-PATH-LENGTH
                               OR WS-PATH(WS-READ:1) = '/'
                           ADD 1 TO WS-WRITTEN
                           MOVE WS-PATH(WS-READ:1)
                             TO UW-OUTPUT(WS-WRITTEN:1)
                           ADD 1 TO WS-READ
                       END-PERFORM
               END-EVALUATE
           END-PERFORM
           MOVE WS-WRITTEN TO UW-OUTPUT-LENGTH.

       3000-PERCENT-DECODE.
           MOVE 0 TO UW-OUTPUT-LENGTH
           MOVE 1 TO WS-READ
           PERFORM UNTIL WS-READ > UW-INPUT-LENGTH
               ADD 1 TO UW-OUTPUT-LENGTH
               IF UW-INPUT(WS-READ:1) = '%'
                  AND WS-READ + 2 <= UW-INPUT-LENGTH
                   MOVE UW-INPUT(WS-READ + 1:1) TO WS-HEX-CHARACTER
                   PERFORM 3100-NIBBLE-VALUE
                   MOVE WS-NIBBLE TO WS-HIGH-NIBBLE
                   MOVE UW-INPUT(WS-READ + 2:1) TO WS-HEX-CHARACTER
                   PERFORM 3100-NIBBLE-VALUE
                   MOVE WS-NIBBLE TO WS-LOW-NIBBLE
               ELSE
                   MOVE -1 TO WS-HIGH-NIBBLE
               END-IF
               IF WS-HIGH-NIBBLE >= 0 AND WS-LOW-NIBBLE >= 0
                   COMPUTE WS-BYTE-VALUE =
                       WS-HIGH-NIBBLE * 16 + WS-LOW-NIBBLE
                   MOVE WS-BYTE TO UW-OUTPUT(UW-OUTPUT-LENGTH:1)
                   ADD 3 TO WS-READ
               ELSE
                   MOVE UW-INPUT(WS-READ:1)
                     TO UW-OUTPUT(UW-OUTPUT-LENGTH:1)
                   ADD 1 TO WS-READ
               END-IF
           END-PERFORM.

       3100-NIBBLE-VALUE.
      *    THE VALUE (0-15) OF ONE HEX DIGIT, OR -1 IF IT IS NOT ONE.
           MOVE WS-HEX-CHARACTER TO WS-BYTE
           EVALUATE TRUE
               WHEN NOT IS-HEX-DIGIT
                   MOVE -1 TO WS-NIBBLE
               WHEN WS-HEX-CHARACTER <= '9'
                   COMPUTE WS-NIBBLE = WS-BYTE-VALUE - 48
               WHEN WS-HEX-CHARACTER <= 'F'
                   COMPUTE WS-NIBBLE = WS-BYTE-VALUE - 55
               WHEN OTHER
                   COMPUTE WS-NIBBLE = WS-BYTE-VALUE - 87
           END-EVALUATE.
