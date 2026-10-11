      *================================================================*
      * JSONTODO - WRITE TODOS AS JSON.                                *
      *                                                                *
      * GNUCOBOL'S JSON GENERATE STATEMENT CAN NOT WRITE THIS: IT HAS  *
      * NO WAY TO SAY TRUE OR FALSE (ONLY TEXT AND NUMBERS), AND NONE  *
      * TO WRITE A LIST ("OCCURS ITEMS IN JSON GENERATE IS NOT         *
      * IMPLEMENTED"). SO THIS PROGRAM WRITES THE JSON BY HAND, BYTE   *
      * FOR BYTE THE WAY GO'S ENCODING/JSON DID:                       *
      *                                                                *
      * {"id":1,"title":"buy milk","done":false,                       *
      *  "createdAt":"2026-10-11T12:28:23.82663Z"}                     *
      *                                                                *
      * A TITLE IS SENT CUT TO 64 BYTES (SEE TITLELIM). IN IT, " AND \ *
      * ARE ESCAPED, CONTROL CHARACTERS BECOME                         *
      * \n, \t, \u0001 AND SO ON, AND < > & BECOME \u003c              *
      * \u003e \u0026, SO THE JSON IS SAFE TO PASTE INTO HTML.         *
      * OTHER NON-ASCII TEXT IS WRITTEN AS UTF-8, EXCEPT U+2028 AND    *
      * U+2029, WHICH JAVASCRIPT TREATS AS LINE BREAKS AND SO ARE      *
      * ESCAPED TOO.                                                   *
      *================================================================*
       IDENTIFICATION DIVISION.
       PROGRAM-ID. JSONTODO.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. LINUX-X86-64.
       OBJECT-COMPUTER. LINUX-X86-64.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
      *    AN "EDITED" PICTURE: Z PRINTS A LEADING ZERO AS A SPACE, SO
      *    MOVING 42 HERE GIVES SEVENTEEN SPACES AND "42".
       01  WS-ID-EDITED                PIC Z(18)9.
       01  WS-FRACTION-LENGTH          BINARY-LONG.
       01  WS-INDEX                    BINARY-LONG.
       01  WS-TITLE-END                BINARY-LONG.
       01  WS-PIECE                    PIC X(64).
       01  WS-PIECE-LENGTH             BINARY-LONG.
       01  WS-HEX-DIGITS               PIC X(16)
           VALUE '0123456789abcdef'.
       01  WS-HIGH-NIBBLE              BINARY-LONG.
       01  WS-LOW-NIBBLE               BINARY-LONG.

       01  WS-BYTE-VALUE               BINARY-CHAR UNSIGNED.
       01  WS-BYTE REDEFINES WS-BYTE-VALUE PIC X.
      *        THE ASCII CHARACTERS GO WRITES AS \u00XX.
           88  NEEDS-HEX-ESCAPE        VALUES X'00' THRU X'1F'
                                              '<' '>' '&'.
       01  WS-THREE-BYTES              PIC X(3).
           88  IS-LINE-SEPARATOR       VALUE X'E280A8'.
           88  IS-PARAGRAPH-SEPARATOR  VALUE X'E280A9'.

       COPY UTF8WORK.
       COPY TITLELIM.

       LINKAGE SECTION.
       COPY JSONOUT.
       COPY TODOREC.
       COPY HTTPRSP.

       PROCEDURE DIVISION USING JSON-OUT TODO-RECORD HTTP-RESPONSE.
       0000-MAIN.
           SET JO-FITS TO TRUE
           EVALUATE TRUE
               WHEN JO-START-LIST
                   MOVE 0 TO JO-ITEMS-WRITTEN
                   MOVE '[' TO WS-PIECE
                   MOVE 1 TO WS-PIECE-LENGTH
                   PERFORM 9000-APPEND-PIECE
               WHEN JO-ADD-TO-LIST
                   IF JO-ITEMS-WRITTEN > 0
                       MOVE ',' TO WS-PIECE
                       MOVE 1 TO WS-PIECE-LENGTH
                       PERFORM 9000-APPEND-PIECE
                   END-IF
                   PERFORM 1000-WRITE-TODO
                   ADD 1 TO JO-ITEMS-WRITTEN
               WHEN JO-END-LIST
                   MOVE ']' TO WS-PIECE
                   MOVE X'0A' TO WS-PIECE(2:1)
                   MOVE 2 TO WS-PIECE-LENGTH
                   PERFORM 9000-APPEND-PIECE
               WHEN JO-SINGLE-TODO
                   PERFORM 1000-WRITE-TODO
                   MOVE X'0A' TO WS-PIECE
                   MOVE 1 TO WS-PIECE-LENGTH
                   PERFORM 9000-APPEND-PIECE
           END-EVALUATE
           GOBACK.

       1000-WRITE-TODO.
           MOVE TODO-ID TO WS-ID-EDITED
           MOVE SPACES TO WS-PIECE
           STRING '{"id":' FUNCTION TRIM(WS-ID-EDITED LEADING)
                  ',"title":"'
               DELIMITED BY SIZE INTO WS-PIECE
           END-STRING
           PERFORM 9100-APPEND-TRIMMED-PIECE

           PERFORM 2000-WRITE-ESCAPED-TITLE

           MOVE SPACES TO WS-PIECE
           IF TODO-IS-DONE
               MOVE '","done":true,"createdAt":"' TO WS-PIECE
           ELSE
               MOVE '","done":false,"createdAt":"' TO WS-PIECE
           END-IF
           PERFORM 9100-APPEND-TRIMMED-PIECE

           PERFORM 3000-WRITE-CREATED-AT
           MOVE '"}' TO WS-PIECE
           MOVE 2 TO WS-PIECE-LENGTH
           PERFORM 9000-APPEND-PIECE.

       2000-WRITE-ESCAPED-TITLE.
      *    A ROW THE GO VERSION STORED MAY BE LONGER THAN THE LIMIT.
           MOVE 'CUT ' TO U8-FUNCTION
           MOVE 1 TO U8-POSITION
           MOVE TODO-TITLE-LENGTH TO U8-END
           MOVE TITLE-BYTE-LIMIT TO U8-BYTE-LIMIT
           CALL 'UTF8TEXT' USING UTF8-WORK TODO-TITLE
           MOVE U8-END TO WS-TITLE-END
           MOVE 1 TO WS-INDEX
           PERFORM UNTIL WS-INDEX > WS-TITLE-END OR JO-BODY-FULL
               MOVE TODO-TITLE(WS-INDEX:1) TO WS-BYTE
               EVALUATE TRUE
                   WHEN WS-BYTE-VALUE >= 128
                       PERFORM 2100-WRITE-NON-ASCII
                   WHEN WS-BYTE = '"'
                       MOVE '\"' TO WS-PIECE
                       MOVE 2 TO WS-PIECE-LENGTH
                       PERFORM 9000-APPEND-PIECE
                       ADD 1 TO WS-INDEX
                   WHEN WS-BYTE = '\'
                       MOVE '\\' TO WS-PIECE
                       MOVE 2 TO WS-PIECE-LENGTH
                       PERFORM 9000-APPEND-PIECE
                       ADD 1 TO WS-INDEX
                   WHEN WS-BYTE-VALUE = 8
                       MOVE '\b' TO WS-PIECE
                       MOVE 2 TO WS-PIECE-LENGTH
                       PERFORM 9000-APPEND-PIECE
                       ADD 1 TO WS-INDEX
                   WHEN WS-BYTE-VALUE = 9
                       MOVE '\t' TO WS-PIECE
                       MOVE 2 TO WS-PIECE-LENGTH
                       PERFORM 9000-APPEND-PIECE
                       ADD 1 TO WS-INDEX
                   WHEN WS-BYTE-VALUE = 10
                       MOVE '\n' TO WS-PIECE
                       MOVE 2 TO WS-PIECE-LENGTH
                       PERFORM 9000-APPEND-PIECE
                       ADD 1 TO WS-INDEX
                   WHEN WS-BYTE-VALUE = 12
                       MOVE '\f' TO WS-PIECE
                       MOVE 2 TO WS-PIECE-LENGTH
                       PERFORM 9000-APPEND-PIECE
                       ADD 1 TO WS-INDEX
                   WHEN WS-BYTE-VALUE = 13
                       MOVE '\r' TO WS-PIECE
                       MOVE 2 TO WS-PIECE-LENGTH
                       PERFORM 9000-APPEND-PIECE
                       ADD 1 TO WS-INDEX
                   WHEN NEEDS-HEX-ESCAPE
                       PERFORM 2200-WRITE-HEX-ESCAPE
                       ADD 1 TO WS-INDEX
                   WHEN OTHER
                       MOVE WS-BYTE TO WS-PIECE
                       MOVE 1 TO WS-PIECE-LENGTH
                       PERFORM 9000-APPEND-PIECE
                       ADD 1 TO WS-INDEX
               END-EVALUATE
           END-PERFORM.

       2100-WRITE-NON-ASCII.
           MOVE 'SEQ ' TO U8-FUNCTION
           MOVE WS-INDEX TO U8-POSITION
           MOVE WS-TITLE-END TO U8-END
           CALL 'UTF8TEXT' USING UTF8-WORK TODO-TITLE
           MOVE SPACES TO WS-THREE-BYTES
           IF U8-SEQUENCE-LENGTH = 3
               MOVE TODO-TITLE(WS-INDEX:3) TO WS-THREE-BYTES
           END-IF
           EVALUATE TRUE
               WHEN U8-SEQUENCE-LENGTH = 0
                   MOVE '\ufffd' TO WS-PIECE
                   MOVE 6 TO WS-PIECE-LENGTH
                   ADD 1 TO WS-INDEX
               WHEN IS-LINE-SEPARATOR
                   MOVE '\u2028' TO WS-PIECE
                   MOVE 6 TO WS-PIECE-LENGTH
                   ADD 3 TO WS-INDEX
               WHEN IS-PARAGRAPH-SEPARATOR
                   MOVE '\u2029' TO WS-PIECE
                   MOVE 6 TO WS-PIECE-LENGTH
                   ADD 3 TO WS-INDEX
               WHEN OTHER
                   MOVE TODO-TITLE(WS-INDEX:U8-SEQUENCE-LENGTH)
                     TO WS-PIECE
                   MOVE U8-SEQUENCE-LENGTH TO WS-PIECE-LENGTH
                   ADD U8-SEQUENCE-LENGTH TO WS-INDEX
           END-EVALUATE
           PERFORM 9000-APPEND-PIECE.

       2200-WRITE-HEX-ESCAPE.
      *    \u00 AND THEN THE BYTE AS TWO LOWERCASE HEX DIGITS.
           COMPUTE WS-HIGH-NIBBLE = WS-BYTE-VALUE / 16
           COMPUTE WS-LOW-NIBBLE = FUNCTION MOD(WS-BYTE-VALUE, 16)
           MOVE '\u00' TO WS-PIECE
           MOVE WS-HEX-DIGITS(WS-HIGH-NIBBLE + 1:1) TO WS-PIECE(5:1)
           MOVE WS-HEX-DIGITS(WS-LOW-NIBBLE + 1:1) TO WS-PIECE(6:1)
           MOVE 6 TO WS-PIECE-LENGTH
           PERFORM 9000-APPEND-PIECE.

       3000-WRITE-CREATED-AT.
      *    RFC 3339, AS GO WRITES A TIME: "2026-10-11T12:28:23.82663Z".
      *    THE FRACTION LOSES ITS TRAILING ZEROS, AND DISAPPEARS
      *    ALTOGETHER WHEN IT IS ZERO.
           MOVE 6 TO WS-FRACTION-LENGTH
           PERFORM UNTIL WS-FRACTION-LENGTH = 0
                   OR TODO-CREATED-MICROS(WS-FRACTION-LENGTH:1)
                      NOT = '0'
               SUBTRACT 1 FROM WS-FRACTION-LENGTH
           END-PERFORM
           MOVE SPACES TO WS-PIECE
           STRING TODO-CREATED-YEAR '-' TODO-CREATED-MONTH '-'
                  TODO-CREATED-DAY  'T' TODO-CREATED-HOUR  ':'
                  TODO-CREATED-MINUTE ':' TODO-CREATED-SECOND
               DELIMITED BY SIZE INTO WS-PIECE
           END-STRING
           MOVE 19 TO WS-PIECE-LENGTH
           IF WS-FRACTION-LENGTH > 0
               MOVE '.' TO WS-PIECE(20:1)
               MOVE TODO-CREATED-MICROS(1:WS-FRACTION-LENGTH)
                 TO WS-PIECE(21:WS-FRACTION-LENGTH)
               COMPUTE WS-PIECE-LENGTH = 20 + WS-FRACTION-LENGTH
           END-IF
           ADD 1 TO WS-PIECE-LENGTH
           MOVE 'Z' TO WS-PIECE(WS-PIECE-LENGTH:1)
           PERFORM 9000-APPEND-PIECE.

      *----------------------------------------------------------------*
      * APPENDING TO THE RESPONSE BODY, WITHOUT EVER WRITING PAST ITS  *
      * END. IF A LIST DOES NOT FIT, THE CALLER ANSWERS 500.           *
      *----------------------------------------------------------------*
       9000-APPEND-PIECE.
           IF RSP-BODY-LENGTH + WS-PIECE-LENGTH > LENGTH OF RSP-BODY
               SET JO-BODY-FULL TO TRUE
               EXIT PARAGRAPH
           END-IF
           MOVE WS-PIECE(1:WS-PIECE-LENGTH)
             TO RSP-BODY(RSP-BODY-LENGTH + 1:WS-PIECE-LENGTH)
           ADD WS-PIECE-LENGTH TO RSP-BODY-LENGTH.

       9100-APPEND-TRIMMED-PIECE.
           MOVE FUNCTION LENGTH(FUNCTION TRIM(WS-PIECE TRAILING))
             TO WS-PIECE-LENGTH
           PERFORM 9000-APPEND-PIECE.
