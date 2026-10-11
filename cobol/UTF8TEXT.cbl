      *================================================================*
      * UTF8TEXT - SMALL JOBS ON UTF-8 TEXT.                           *
      *                                                                *
      * UTF-8 WRITES EACH CHARACTER AS ONE TO FOUR BYTES. A BYTE BELOW *
      * 128 IS PLAIN ASCII; A LONGER CHARACTER STARTS WITH A "LEAD"    *
      * BYTE (194-244) FOLLOWED BY "CONTINUATION" BYTES (128-191).     *
      *                                                                *
      * 'SEQ ' CHECKS THAT A SEQUENCE IS WELL FORMED, BY THE SAME      *
      * RULES AS GO'S UTF8.DECODERUNE (NO OVERLONG FORMS, NO           *
      * SURROGATES, NOTHING ABOVE U+10FFFF).                           *
      * 'TRIM' DOES WHAT GO'S STRINGS.TRIMSPACE DOES, THEN COUNTS THE  *
      * CHARACTERS LEFT (NOT THE BYTES: "CAFE" WITH AN ACCENT IS 4).   *
      * 'CUT ' SHORTENS TEXT TO A NUMBER OF BYTES, BETWEEN CHARACTERS. *
      *================================================================*
       IDENTIFICATION DIVISION.
       PROGRAM-ID. UTF8TEXT.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. LINUX-X86-64.
       OBJECT-COMPUTER. LINUX-X86-64.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
      *    A ONE-BYTE NUMBER AND, OVER THE SAME BYTE, A ONE-CHARACTER
      *    FIELD. MOVE A CHARACTER INTO WS-BYTE AND READ ITS VALUE
      *    (0-255) FROM WS-BYTE-VALUE.
       01  WS-BYTE-VALUE               BINARY-CHAR UNSIGNED.
       01  WS-BYTE REDEFINES WS-BYTE-VALUE PIC X.

       01  WS-BYTES-NEEDED             BINARY-LONG.
       01  WS-SECOND-LOW               BINARY-LONG.
       01  WS-SECOND-HIGH              BINARY-LONG.
       01  WS-INDEX                    BINARY-LONG.

      *    THE WHITESPACE GO'S UNICODE.ISSPACE KNOWS, BY BYTE LENGTH.
      *    "VALUES ... THRU ..." NAMES A WHOLE RANGE AT ONCE.
       01  WS-ONE-BYTE                 PIC X.
           88  IS-ASCII-SPACE          VALUES X'09' THRU X'0D' X'20'.
       01  WS-TWO-BYTES                PIC X(2).
      *        U+0085 NEXT LINE, U+00A0 NO-BREAK SPACE
           88  IS-WIDE-SPACE-2         VALUES X'C285' X'C2A0'.
       01  WS-THREE-BYTES              PIC X(3).
      *        U+1680 OGHAM SPACE, U+2000-U+200A THE TYPOGRAPHIC
      *        SPACES, U+2028 LINE SEPARATOR, U+2029 PARAGRAPH
      *        SEPARATOR, U+202F NARROW NO-BREAK SPACE, U+205F MEDIUM
      *        MATHEMATICAL SPACE, U+3000 IDEOGRAPHIC SPACE
           88  IS-WIDE-SPACE-3         VALUES X'E19A80'
                                              X'E28080' THRU X'E2808A'
                                              X'E280A8' X'E280A9'
                                              X'E280AF' X'E2819F'
                                              X'E38080'.
       01  WS-TRIM-STATE               PIC X.
           88  STILL-TRIMMING          VALUE 'Y'.
           88  DONE-TRIMMING           VALUE 'N'.

       LINKAGE SECTION.
       COPY UTF8WORK.
      *    THE TEXT ITSELF. IT IS THE CALLER'S FIELD; THIS PROGRAM
      *    ONLY LOOKS AT THE BYTES BETWEEN U8-POSITION AND U8-END.
       01  U8-TEXT                     PIC X(3145744).

       PROCEDURE DIVISION USING UTF8-WORK U8-TEXT.
       0000-MAIN.
           EVALUATE U8-FUNCTION
               WHEN 'SEQ '
                   PERFORM 1000-MEASURE-SEQUENCE
               WHEN 'TRIM'
                   PERFORM 2000-TRIM-LEADING-SPACE
                   PERFORM 2100-TRIM-TRAILING-SPACE
                   PERFORM 3000-COUNT-CHARACTERS
               WHEN 'CUT '
                   PERFORM 4000-CUT-TO-BYTE-LIMIT
                   PERFORM 3000-COUNT-CHARACTERS
           END-EVALUATE
           GOBACK.

       1000-MEASURE-SEQUENCE.
           MOVE 0 TO U8-SEQUENCE-LENGTH
           MOVE U8-TEXT(U8-POSITION:1) TO WS-BYTE
      *    THE LEAD BYTE SAYS HOW LONG THE SEQUENCE IS, AND NARROWS THE
      *    RANGE THE SECOND BYTE MAY FALL IN (THAT IS WHAT RULES OUT
      *    OVERLONG FORMS AND SURROGATES).
           MOVE 128 TO WS-SECOND-LOW
           MOVE 191 TO WS-SECOND-HIGH
           EVALUATE TRUE
               WHEN WS-BYTE-VALUE < 128
                   MOVE 1 TO U8-SEQUENCE-LENGTH
                   EXIT PARAGRAPH
               WHEN WS-BYTE-VALUE >= 194 AND <= 223
                   MOVE 2 TO WS-BYTES-NEEDED
               WHEN WS-BYTE-VALUE = 224
                   MOVE 3 TO WS-BYTES-NEEDED
                   MOVE 160 TO WS-SECOND-LOW
               WHEN WS-BYTE-VALUE >= 225 AND <= 236
                   MOVE 3 TO WS-BYTES-NEEDED
               WHEN WS-BYTE-VALUE = 237
                   MOVE 3 TO WS-BYTES-NEEDED
                   MOVE 159 TO WS-SECOND-HIGH
               WHEN WS-BYTE-VALUE >= 238 AND <= 239
                   MOVE 3 TO WS-BYTES-NEEDED
               WHEN WS-BYTE-VALUE = 240
                   MOVE 4 TO WS-BYTES-NEEDED
                   MOVE 144 TO WS-SECOND-LOW
               WHEN WS-BYTE-VALUE >= 241 AND <= 243
                   MOVE 4 TO WS-BYTES-NEEDED
               WHEN WS-BYTE-VALUE = 244
                   MOVE 4 TO WS-BYTES-NEEDED
                   MOVE 143 TO WS-SECOND-HIGH
               WHEN OTHER
                   EXIT PARAGRAPH
           END-EVALUATE
      *    A SEQUENCE CUT SHORT BY THE END OF THE TEXT IS BROKEN TOO.
           IF U8-POSITION + WS-BYTES-NEEDED - 1 > U8-END
               EXIT PARAGRAPH
           END-IF
           MOVE U8-TEXT(U8-POSITION + 1:1) TO WS-BYTE
           IF WS-BYTE-VALUE < WS-SECOND-LOW
              OR WS-BYTE-VALUE > WS-SECOND-HIGH
               EXIT PARAGRAPH
           END-IF
           PERFORM VARYING WS-INDEX FROM 2 BY 1
                   UNTIL WS-INDEX >= WS-BYTES-NEEDED
               MOVE U8-TEXT(U8-POSITION + WS-INDEX:1) TO WS-BYTE
               IF WS-BYTE-VALUE < 128 OR WS-BYTE-VALUE > 191
                   EXIT PARAGRAPH
               END-IF
           END-PERFORM
           MOVE WS-BYTES-NEEDED TO U8-SEQUENCE-LENGTH.

       2000-TRIM-LEADING-SPACE.
           SET STILL-TRIMMING TO TRUE
           PERFORM UNTIL DONE-TRIMMING OR U8-POSITION > U8-END
               MOVE U8-TEXT(U8-POSITION:1) TO WS-ONE-BYTE
               MOVE SPACES TO WS-TWO-BYTES WS-THREE-BYTES
               IF U8-POSITION + 1 <= U8-END
                   MOVE U8-TEXT(U8-POSITION:2) TO WS-TWO-BYTES
               END-IF
               IF U8-POSITION + 2 <= U8-END
                   MOVE U8-TEXT(U8-POSITION:3) TO WS-THREE-BYTES
               END-IF
               EVALUATE TRUE
                   WHEN IS-ASCII-SPACE
                       ADD 1 TO U8-POSITION
                   WHEN IS-WIDE-SPACE-2
                       ADD 2 TO U8-POSITION
                   WHEN IS-WIDE-SPACE-3
                       ADD 3 TO U8-POSITION
                   WHEN OTHER
                       SET DONE-TRIMMING TO TRUE
               END-EVALUATE
           END-PERFORM.

       2100-TRIM-TRAILING-SPACE.
           SET STILL-TRIMMING TO TRUE
           PERFORM UNTIL DONE-TRIMMING OR U8-END < U8-POSITION
               MOVE U8-TEXT(U8-END:1) TO WS-ONE-BYTE
               MOVE SPACES TO WS-TWO-BYTES WS-THREE-BYTES
               IF U8-END - 1 >= U8-POSITION
                   MOVE U8-TEXT(U8-END - 1:2) TO WS-TWO-BYTES
               END-IF
               IF U8-END - 2 >= U8-POSITION
                   MOVE U8-TEXT(U8-END - 2:3) TO WS-THREE-BYTES
               END-IF
               EVALUATE TRUE
                   WHEN IS-ASCII-SPACE
                       SUBTRACT 1 FROM U8-END
                   WHEN IS-WIDE-SPACE-2
                       SUBTRACT 2 FROM U8-END
                   WHEN IS-WIDE-SPACE-3
                       SUBTRACT 3 FROM U8-END
                   WHEN OTHER
                       SET DONE-TRIMMING TO TRUE
               END-EVALUATE
           END-PERFORM.

       4000-CUT-TO-BYTE-LIMIT.
           IF U8-END - U8-POSITION + 1 <= U8-BYTE-LIMIT
               EXIT PARAGRAPH
           END-IF
           COMPUTE U8-END = U8-POSITION + U8-BYTE-LIMIT - 1
      *    THE BYTE AFTER THE CUT MUST BE THE START OF A CHARACTER. IF
      *    IT IS A CONTINUATION BYTE (128-191), THE CUT WENT THROUGH A
      *    CHARACTER, SO MOVE IT BACK TO WHERE THAT CHARACTER BEGINS.
           MOVE U8-TEXT(U8-END + 1:1) TO WS-BYTE
           PERFORM UNTIL U8-END < U8-POSITION
                   OR WS-BYTE-VALUE < 128 OR WS-BYTE-VALUE > 191
               SUBTRACT 1 FROM U8-END
               MOVE U8-TEXT(U8-END + 1:1) TO WS-BYTE
           END-PERFORM
      *    A CUT RIGHT AFTER A SPACE WOULD LEAVE IT DANGLING.
           PERFORM 2100-TRIM-TRAILING-SPACE.

       3000-COUNT-CHARACTERS.
      *    EVERY CHARACTER HAS EXACTLY ONE BYTE THAT IS NOT A
      *    CONTINUATION BYTE, SO COUNT THOSE.
           MOVE 0 TO U8-CHARACTERS
           PERFORM VARYING WS-INDEX FROM U8-POSITION BY 1
                   UNTIL WS-INDEX > U8-END
               MOVE U8-TEXT(WS-INDEX:1) TO WS-BYTE
               IF WS-BYTE-VALUE < 128 OR WS-BYTE-VALUE > 191
                   ADD 1 TO U8-CHARACTERS
               END-IF
           END-PERFORM.
