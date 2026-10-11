      *================================================================*
      * JSONREAD - READ ONE FIELD OUT OF A JSON REQUEST BODY.          *
      *                                                                *
      * COBOL HAS A JSON PARSE STATEMENT, BUT GNUCOBOL HAS NOT BUILT   *
      * IT YET (IT ANSWERS "JSON PARSE IS NOT IMPLEMENTED"). SO THIS   *
      * PROGRAM READS THE JSON ITSELF, ONE BYTE AT A TIME.             *
      *                                                                *
      * IT GIVES THE ANSWERS GO'S ENCODING/JSON GAVE THE ORIGINAL APP: *
      *  - THE BODY MUST START WITH ONE COMPLETE, VALID JSON VALUE;    *
      *    ANYTHING AFTER THAT VALUE IS IGNORED.                       *
      *  - THAT VALUE MUST BE AN OBJECT, OR NULL (WHICH SETS NOTHING). *
      *  - FIELD NAMES MATCH WITHOUT REGARD TO CASE ("TITLE" = "title")*
      *    AND THE LAST COPY OF A FIELD WINS. UNKNOWN FIELDS ARE       *
      *    SKIPPED, WHATEVER THEY HOLD.                                *
      *  - "title" MUST BE A STRING; NULL LEAVES IT AS IT WAS.         *
      *  - "done" MUST BE TRUE OR FALSE; NULL MAKES IT MISSING AGAIN.  *
      *  - BROKEN UTF-8 AND LONE SURROGATES IN A STRING BECOME U+FFFD. *
      *  - NO MORE THAN 10000 NESTED OBJECTS AND ARRAYS.               *
      *                                                                *
      * HOW IT WORKS: JSON NESTS, AND COBOL PARAGRAPHS ARE NOT         *
      * RECURSIVE, SO THE PROGRAM KEEPS ITS OWN STACK OF OPEN BRACKETS *
      * AND A STATE THAT SAYS WHAT MAY COME NEXT ("A VALUE", "A COLON",*
      * "A COMMA OR A CLOSING BRACKET", ...). EACH STEP READS ONE      *
      * TOKEN AND MOVES TO THE NEXT STATE.                             *
      *================================================================*
       IDENTIFICATION DIVISION.
       PROGRAM-ID. JSONREAD.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. LINUX-X86-64.
       OBJECT-COMPUTER. LINUX-X86-64.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-POSITION                 BINARY-LONG.
       01  WS-END                      BINARY-LONG.

       01  WS-STATE                    PIC X.
           88  EXPECT-VALUE            VALUE 'V'.
           88  EXPECT-FIRST-KEY        VALUE 'K'.
           88  EXPECT-NEXT-KEY         VALUE 'N'.
           88  EXPECT-COLON            VALUE 'C'.
           88  EXPECT-FIRST-ELEMENT    VALUE 'A'.
           88  EXPECT-COMMA-OR-CLOSE   VALUE 'E'.
           88  PARSE-COMPLETE          VALUE 'D'.
           88  PARSE-FAILED            VALUE 'X'.

      *    THE STACK: ONE ENTRY PER OPEN BRACKET, 'O' FOR AN OBJECT,
      *    'A' FOR AN ARRAY. WS-DEPTH IS HOW MANY ARE OPEN.
       01  WS-DEPTH                    BINARY-LONG.
       01  WS-MAXIMUM-DEPTH            BINARY-LONG VALUE 10000.
       01  WS-STACK.
           05  WS-OPEN-BRACKET         PIC X OCCURS 10000 TIMES.

       01  WS-TYPE-CHECK               PIC X.
           88  NO-WRONG-TYPE-SEEN      VALUE 'N'.
           88  WRONG-TYPE-SEEN         VALUE 'Y'.
      *    WHOSE VALUE ARE WE READING?
       01  WS-VALUE-ROLE               PIC X.
           88  VALUE-IS-THE-BODY       VALUE 'B'.
           88  VALUE-IS-WANTED-FIELD   VALUE 'W'.
           88  VALUE-IS-IGNORED        VALUE 'I'.
       01  WS-KEY-CHECK                PIC X.
           88  KEY-IS-WANTED           VALUE 'Y'.
           88  KEY-IS-OTHER            VALUE 'N'.

      *    WHERE THE CURRENT STRING'S QUOTES ARE.
       01  WS-STRING-START             BINARY-LONG.
       01  WS-STRING-END               BINARY-LONG.
       01  WS-STRING-STATE             PIC X.
           88  STRING-OPEN             VALUE 'O'.
           88  STRING-CLOSED           VALUE 'C'.

      *    DECODING A STRING: WHERE THE BYTES GO, AND A SHORT BUFFER
      *    FOR FIELD NAMES (A NAME LONGER THAN 8 BYTES IS NEVER ONE WE
      *    WANT, BUT ITS LENGTH STILL COUNTS).
       01  WS-DECODE-TARGET            PIC X.
           88  DECODE-INTO-KEY         VALUE 'K'.
           88  DECODE-INTO-TITLE       VALUE 'T'.
       01  WS-DECODE-AT                BINARY-LONG.
       01  WS-KEY                      PIC X(8).
       01  WS-KEY-LENGTH               BINARY-LONG.
       01  WS-CODE-POINT               BINARY-LONG.
       01  WS-LOW-SURROGATE            BINARY-LONG.
       01  WS-RUNE                     BINARY-LONG.
       01  WS-SIXTY-FOURTHS            BINARY-LONG.
       01  WS-HEX-AT                   BINARY-LONG.
       01  WS-HEX-VALUE                BINARY-LONG.
       01  WS-HEX-INDEX                BINARY-LONG.
       01  WS-COPY-INDEX               BINARY-LONG.
       01  WS-DIGITS-SEEN              BINARY-LONG.

      *    ONE BYTE AS A CHARACTER AND AS A NUMBER (0-255).
       01  WS-BYTE-VALUE               BINARY-CHAR UNSIGNED.
       01  WS-BYTE REDEFINES WS-BYTE-VALUE PIC X.
           88  IS-JSON-WHITESPACE      VALUES X'20' X'09' X'0A' X'0D'.
           88  IS-DIGIT                VALUES '0' THRU '9'.
           88  IS-HEX-DIGIT            VALUES '0' THRU '9'
                                              'A' THRU 'F'
                                              'a' THRU 'f'.
       01  WS-OUT-VALUE                BINARY-CHAR UNSIGNED.
       01  WS-OUT-BYTE REDEFINES WS-OUT-VALUE PIC X.

       COPY UTF8WORK.

       LINKAGE SECTION.
       COPY HTTPREQ.
       COPY JSONBODY.

       PROCEDURE DIVISION USING HTTP-REQUEST JSON-BODY.
       0000-MAIN.
           SET JB-IS-VALID TO TRUE
           SET JB-DONE-MISSING TO TRUE
           MOVE 0 TO JB-TITLE-LENGTH
           SET NO-WRONG-TYPE-SEEN TO TRUE
           SET KEY-IS-OTHER TO TRUE
           MOVE 0 TO WS-DEPTH
           MOVE 1 TO WS-POSITION
           MOVE REQ-BODY-LENGTH TO WS-END
           SET EXPECT-VALUE TO TRUE
           PERFORM 1000-TAKE-ONE-STEP
               UNTIL PARSE-COMPLETE OR PARSE-FAILED
           IF PARSE-FAILED OR WRONG-TYPE-SEEN
               SET JB-IS-INVALID TO TRUE
           END-IF
           GOBACK.

       1000-TAKE-ONE-STEP.
           PERFORM 1100-SKIP-WHITESPACE
           IF WS-POSITION > WS-END
      *        THE BODY RAN OUT BEFORE THE JSON VALUE ENDED.
               SET PARSE-FAILED TO TRUE
               EXIT PARAGRAPH
           END-IF
           MOVE REQ-BODY(WS-POSITION:1) TO WS-BYTE
           EVALUATE TRUE
               WHEN EXPECT-VALUE
                   PERFORM 2000-READ-VALUE
               WHEN EXPECT-FIRST-ELEMENT
                   IF WS-BYTE = ']'
                       PERFORM 4200-CLOSE-BRACKET
                   ELSE
                       PERFORM 2000-READ-VALUE
                   END-IF
               WHEN EXPECT-FIRST-KEY
                   EVALUATE WS-BYTE
                       WHEN '}'
                           PERFORM 4200-CLOSE-BRACKET
                       WHEN '"'
                           PERFORM 3000-READ-KEY
                       WHEN OTHER
                           SET PARSE-FAILED TO TRUE
                   END-EVALUATE
               WHEN EXPECT-NEXT-KEY
                   IF WS-BYTE = '"'
                       PERFORM 3000-READ-KEY
                   ELSE
                       SET PARSE-FAILED TO TRUE
                   END-IF
               WHEN EXPECT-COLON
                   IF WS-BYTE = ':'
                       ADD 1 TO WS-POSITION
                       SET EXPECT-VALUE TO TRUE
                   ELSE
                       SET PARSE-FAILED TO TRUE
                   END-IF
               WHEN EXPECT-COMMA-OR-CLOSE
                   PERFORM 1200-COMMA-OR-CLOSE
           END-EVALUATE.

       1100-SKIP-WHITESPACE.
           PERFORM UNTIL WS-POSITION > WS-END
               MOVE REQ-BODY(WS-POSITION:1) TO WS-BYTE
               IF NOT IS-JSON-WHITESPACE
                   EXIT PERFORM
               END-IF
               ADD 1 TO WS-POSITION
           END-PERFORM.

       1200-COMMA-OR-CLOSE.
      *    "EVALUATE ... ALSO ..." TESTS TWO THINGS AT ONCE: THE BYTE,
      *    AND THE KIND OF BRACKET THAT IS OPEN.
           EVALUATE WS-BYTE ALSO WS-OPEN-BRACKET(WS-DEPTH)
               WHEN ',' ALSO 'O'
                   ADD 1 TO WS-POSITION
                   SET EXPECT-NEXT-KEY TO TRUE
               WHEN ',' ALSO 'A'
                   ADD 1 TO WS-POSITION
                   SET EXPECT-VALUE TO TRUE
               WHEN '}' ALSO 'O'
                   PERFORM 4200-CLOSE-BRACKET
               WHEN ']' ALSO 'A'
                   PERFORM 4200-CLOSE-BRACKET
               WHEN OTHER
                   SET PARSE-FAILED TO TRUE
           END-EVALUATE.

       2000-READ-VALUE.
      *    THE BODY ITSELF IS DEPTH 0. THE FIELDS OF THE BODY'S OBJECT
      *    ARE DEPTH 1. ANYTHING DEEPER IS ONLY CHECKED, NEVER USED.
           EVALUATE TRUE
               WHEN WS-DEPTH = 0
                   SET VALUE-IS-THE-BODY TO TRUE
               WHEN WS-DEPTH = 1 AND WS-OPEN-BRACKET(1) = 'O'
                    AND KEY-IS-WANTED
                   SET VALUE-IS-WANTED-FIELD TO TRUE
               WHEN OTHER
                   SET VALUE-IS-IGNORED TO TRUE
           END-EVALUATE

           EVALUATE TRUE
               WHEN WS-BYTE = '{'
                   IF VALUE-IS-WANTED-FIELD
                       SET WRONG-TYPE-SEEN TO TRUE
                   END-IF
                   PERFORM 4100-OPEN-OBJECT
               WHEN WS-BYTE = '['
                   IF NOT VALUE-IS-IGNORED
                       SET WRONG-TYPE-SEEN TO TRUE
                   END-IF
                   PERFORM 4000-OPEN-ARRAY
               WHEN WS-BYTE = '"'
                   PERFORM 5000-SCAN-STRING
                   IF PARSE-FAILED
                       EXIT PARAGRAPH
                   END-IF
                   EVALUATE TRUE
                       WHEN VALUE-IS-WANTED-FIELD AND JB-WANTS-TITLE
                           SET DECODE-INTO-TITLE TO TRUE
                           PERFORM 7000-DECODE-STRING
                       WHEN NOT VALUE-IS-IGNORED
                           SET WRONG-TYPE-SEEN TO TRUE
                   END-EVALUATE
                   PERFORM 4300-VALUE-FINISHED
               WHEN WS-BYTE = 't'
                   PERFORM 6100-SCAN-TRUE
               WHEN WS-BYTE = 'f'
                   PERFORM 6200-SCAN-FALSE
               WHEN WS-BYTE = 'n'
                   PERFORM 6300-SCAN-NULL
               WHEN WS-BYTE = '-' OR IS-DIGIT
                   PERFORM 6000-SCAN-NUMBER
                   IF NOT VALUE-IS-IGNORED
                       SET WRONG-TYPE-SEEN TO TRUE
                   END-IF
                   PERFORM 4300-VALUE-FINISHED
               WHEN OTHER
                   SET PARSE-FAILED TO TRUE
           END-EVALUATE.

       3000-READ-KEY.
           PERFORM 5000-SCAN-STRING
           IF PARSE-FAILED
               EXIT PARAGRAPH
           END-IF
           SET KEY-IS-OTHER TO TRUE
           IF WS-DEPTH = 1 AND WS-OPEN-BRACKET(1) = 'O'
               SET DECODE-INTO-KEY TO TRUE
               PERFORM 7000-DECODE-STRING
      *        GO MATCHES FIELD NAMES WITHOUT REGARD TO CASE.
               INSPECT WS-KEY CONVERTING 'abcdefghijklmnopqrstuvwxyz'
                                      TO 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
               IF (JB-WANTS-TITLE AND WS-KEY-LENGTH = 5
                                  AND WS-KEY(1:5) = 'TITLE')
                  OR (JB-WANTS-DONE AND WS-KEY-LENGTH = 4
                                    AND WS-KEY(1:4) = 'DONE')
                   SET KEY-IS-WANTED TO TRUE
               END-IF
           END-IF
           SET EXPECT-COLON TO TRUE.

      *----------------------------------------------------------------*
      * BRACKETS: PUSH ON OPEN, POP ON CLOSE.                          *
      *----------------------------------------------------------------*
       4000-OPEN-ARRAY.
           IF WS-DEPTH >= WS-MAXIMUM-DEPTH
               SET PARSE-FAILED TO TRUE
               EXIT PARAGRAPH
           END-IF
           ADD 1 TO WS-DEPTH
           MOVE 'A' TO WS-OPEN-BRACKET(WS-DEPTH)
           ADD 1 TO WS-POSITION
           SET EXPECT-FIRST-ELEMENT TO TRUE.

       4100-OPEN-OBJECT.
           IF WS-DEPTH >= WS-MAXIMUM-DEPTH
               SET PARSE-FAILED TO TRUE
               EXIT PARAGRAPH
           END-IF
           ADD 1 TO WS-DEPTH
           MOVE 'O' TO WS-OPEN-BRACKET(WS-DEPTH)
           ADD 1 TO WS-POSITION
           SET EXPECT-FIRST-KEY TO TRUE.

       4200-CLOSE-BRACKET.
           ADD 1 TO WS-POSITION
           SUBTRACT 1 FROM WS-DEPTH
           PERFORM 4300-VALUE-FINISHED.

       4300-VALUE-FINISHED.
      *    A FINISHED VALUE AT DEPTH 0 IS THE WHOLE BODY: WE ARE DONE.
           IF PARSE-FAILED
               EXIT PARAGRAPH
           END-IF
           IF WS-DEPTH = 0
               SET PARSE-COMPLETE TO TRUE
           ELSE
               SET EXPECT-COMMA-OR-CLOSE TO TRUE
           END-IF.

      *----------------------------------------------------------------*
      * STRINGS: CHECK THE SYNTAX FIRST, DECODE ONLY IF WANTED.        *
      *----------------------------------------------------------------*
       5000-SCAN-STRING.
           MOVE WS-POSITION TO WS-STRING-START
           ADD 1 TO WS-POSITION
           SET STRING-OPEN TO TRUE
           PERFORM UNTIL STRING-CLOSED OR PARSE-FAILED
               IF WS-POSITION > WS-END
                   SET PARSE-FAILED TO TRUE
                   EXIT PERFORM
               END-IF
               MOVE REQ-BODY(WS-POSITION:1) TO WS-BYTE
               EVALUATE TRUE
                   WHEN WS-BYTE = '"'
                       MOVE WS-POSITION TO WS-STRING-END
                       ADD 1 TO WS-POSITION
                       SET STRING-CLOSED TO TRUE
                   WHEN WS-BYTE = '\'
                       PERFORM 5100-SCAN-ESCAPE
      *            A RAW CONTROL CHARACTER (A TAB, A NEWLINE) IS NOT
      *            ALLOWED INSIDE A JSON STRING; IT MUST BE ESCAPED.
                   WHEN WS-BYTE-VALUE < 32
                       SET PARSE-FAILED TO TRUE
                   WHEN OTHER
                       ADD 1 TO WS-POSITION
               END-EVALUATE
           END-PERFORM.

       5100-SCAN-ESCAPE.
           IF WS-POSITION + 1 > WS-END
               SET PARSE-FAILED TO TRUE
               EXIT PARAGRAPH
           END-IF
           MOVE REQ-BODY(WS-POSITION + 1:1) TO WS-BYTE
           EVALUATE WS-BYTE
               WHEN '"'
               WHEN '\'
               WHEN '/'
               WHEN 'b'
               WHEN 'f'
               WHEN 'n'
               WHEN 'r'
               WHEN 't'
                   ADD 2 TO WS-POSITION
               WHEN 'u'
                   IF WS-POSITION + 5 > WS-END
                       SET PARSE-FAILED TO TRUE
                       EXIT PARAGRAPH
                   END-IF
                   PERFORM VARYING WS-HEX-INDEX FROM 2 BY 1
                           UNTIL WS-HEX-INDEX > 5
                       MOVE REQ-BODY(WS-POSITION + WS-HEX-INDEX:1)
                         TO WS-BYTE
                       IF NOT IS-HEX-DIGIT
                           SET PARSE-FAILED TO TRUE
                           EXIT PARAGRAPH
                       END-IF
                   END-PERFORM
                   ADD 6 TO WS-POSITION
               WHEN OTHER
                   SET PARSE-FAILED TO TRUE
           END-EVALUATE.

      *----------------------------------------------------------------*
      * NUMBERS AND THE WORDS TRUE, FALSE AND NULL.                    *
      *----------------------------------------------------------------*
       6000-SCAN-NUMBER.
      *    -?(0|[1-9][0-9]*)(.[0-9]+)?([eE][+-]?[0-9]+)?
           IF REQ-BODY(WS-POSITION:1) = '-'
               ADD 1 TO WS-POSITION
           END-IF
           IF WS-POSITION > WS-END
               SET PARSE-FAILED TO TRUE
               EXIT PARAGRAPH
           END-IF
           MOVE REQ-BODY(WS-POSITION:1) TO WS-BYTE
           EVALUATE TRUE
               WHEN WS-BYTE = '0'
                   ADD 1 TO WS-POSITION
               WHEN IS-DIGIT
                   PERFORM 6050-SCAN-DIGITS
               WHEN OTHER
                   SET PARSE-FAILED TO TRUE
                   EXIT PARAGRAPH
           END-EVALUATE
           IF WS-POSITION <= WS-END
              AND REQ-BODY(WS-POSITION:1) = '.'
               ADD 1 TO WS-POSITION
               PERFORM 6050-SCAN-DIGITS
               IF WS-DIGITS-SEEN = 0
                   SET PARSE-FAILED TO TRUE
                   EXIT PARAGRAPH
               END-IF
           END-IF
           IF WS-POSITION <= WS-END
              AND (REQ-BODY(WS-POSITION:1) = 'e'
                   OR REQ-BODY(WS-POSITION:1) = 'E')
               ADD 1 TO WS-POSITION
               IF WS-POSITION <= WS-END
                  AND (REQ-BODY(WS-POSITION:1) = '+'
                       OR REQ-BODY(WS-POSITION:1) = '-')
                   ADD 1 TO WS-POSITION
               END-IF
               PERFORM 6050-SCAN-DIGITS
               IF WS-DIGITS-SEEN = 0
                   SET PARSE-FAILED TO TRUE
               END-IF
           END-IF.

       6050-SCAN-DIGITS.
           MOVE 0 TO WS-DIGITS-SEEN
           PERFORM UNTIL WS-POSITION > WS-END
               MOVE REQ-BODY(WS-POSITION:1) TO WS-BYTE
               IF NOT IS-DIGIT
                   EXIT PERFORM
               END-IF
               ADD 1 TO WS-POSITION
               ADD 1 TO WS-DIGITS-SEEN
           END-PERFORM.

       6100-SCAN-TRUE.
           IF WS-POSITION + 3 > WS-END
              OR REQ-BODY(WS-POSITION:4) NOT = 'true'
               SET PARSE-FAILED TO TRUE
               EXIT PARAGRAPH
           END-IF
           ADD 4 TO WS-POSITION
           EVALUATE TRUE
               WHEN VALUE-IS-WANTED-FIELD AND JB-WANTS-DONE
                   SET JB-DONE-TRUE TO TRUE
               WHEN NOT VALUE-IS-IGNORED
                   SET WRONG-TYPE-SEEN TO TRUE
           END-EVALUATE
           PERFORM 4300-VALUE-FINISHED.

       6200-SCAN-FALSE.
           IF WS-POSITION + 4 > WS-END
              OR REQ-BODY(WS-POSITION:5) NOT = 'false'
               SET PARSE-FAILED TO TRUE
               EXIT PARAGRAPH
           END-IF
           ADD 5 TO WS-POSITION
           EVALUATE TRUE
               WHEN VALUE-IS-WANTED-FIELD AND JB-WANTS-DONE
                   SET JB-DONE-FALSE TO TRUE
               WHEN NOT VALUE-IS-IGNORED
                   SET WRONG-TYPE-SEEN TO TRUE
           END-EVALUATE
           PERFORM 4300-VALUE-FINISHED.

       6300-SCAN-NULL.
      *    NULL IS NEVER THE WRONG TYPE. FOR "done" IT MEANS "NOT
      *    GIVEN" AGAIN; FOR "title" AND FOR THE BODY IT CHANGES
      *    NOTHING.
           IF WS-POSITION + 3 > WS-END
              OR REQ-BODY(WS-POSITION:4) NOT = 'null'
               SET PARSE-FAILED TO TRUE
               EXIT PARAGRAPH
           END-IF
           ADD 4 TO WS-POSITION
           IF VALUE-IS-WANTED-FIELD AND JB-WANTS-DONE
               SET JB-DONE-MISSING TO TRUE
           END-IF
           PERFORM 4300-VALUE-FINISHED.

      *----------------------------------------------------------------*
      * DECODING A STRING BETWEEN WS-STRING-START AND WS-STRING-END    *
      * (THE QUOTES) INTO A FIELD NAME OR INTO THE TITLE.              *
      *----------------------------------------------------------------*
       7000-DECODE-STRING.
           IF DECODE-INTO-KEY
               MOVE SPACES TO WS-KEY
               MOVE 0 TO WS-KEY-LENGTH
           ELSE
               MOVE 0 TO JB-TITLE-LENGTH
           END-IF
           COMPUTE WS-DECODE-AT = WS-STRING-START + 1
           PERFORM UNTIL WS-DECODE-AT >= WS-STRING-END
               MOVE REQ-BODY(WS-DECODE-AT:1) TO WS-BYTE
               EVALUATE TRUE
                   WHEN WS-BYTE = '\'
                       PERFORM 7100-DECODE-ESCAPE
                   WHEN WS-BYTE-VALUE < 128
                       MOVE WS-BYTE TO WS-OUT-BYTE
                       PERFORM 7900-EMIT-BYTE
                       ADD 1 TO WS-DECODE-AT
                   WHEN OTHER
                       PERFORM 7300-COPY-UTF8-SEQUENCE
               END-EVALUATE
           END-PERFORM.

       7100-DECODE-ESCAPE.
           MOVE REQ-BODY(WS-DECODE-AT + 1:1) TO WS-BYTE
           ADD 2 TO WS-DECODE-AT
           EVALUATE WS-BYTE
               WHEN 'b'
                   MOVE 8 TO WS-OUT-VALUE
               WHEN 'f'
                   MOVE 12 TO WS-OUT-VALUE
               WHEN 'n'
                   MOVE 10 TO WS-OUT-VALUE
               WHEN 'r'
                   MOVE 13 TO WS-OUT-VALUE
               WHEN 't'
                   MOVE 9 TO WS-OUT-VALUE
               WHEN 'u'
                   PERFORM 7200-DECODE-UNICODE-ESCAPE
                   EXIT PARAGRAPH
               WHEN OTHER
      *            \" \\ AND \/ STAND FOR THE CHARACTER ITSELF.
                   MOVE WS-BYTE TO WS-OUT-BYTE
           END-EVALUATE
           PERFORM 7900-EMIT-BYTE.

       7200-DECODE-UNICODE-ESCAPE.
      *    \uXXXX. CHARACTERS ABOVE U+FFFF ARE WRITTEN AS TWO ESCAPES,
      *    A "SURROGATE PAIR" (\uD83D\uDE00 IS ONE EMOJI). HALF A PAIR
      *    ON ITS OWN IS NOT A CHARACTER AND BECOMES U+FFFD.
           COMPUTE WS-HEX-AT = WS-DECODE-AT
           PERFORM 7210-READ-FOUR-HEX-DIGITS
           MOVE WS-HEX-VALUE TO WS-CODE-POINT
           ADD 4 TO WS-DECODE-AT
           MOVE WS-CODE-POINT TO WS-RUNE
           IF WS-CODE-POINT >= 55296 AND WS-CODE-POINT <= 57343
               MOVE 65533 TO WS-RUNE
               IF WS-CODE-POINT <= 56319
                  AND WS-DECODE-AT + 5 < WS-STRING-END
                  AND REQ-BODY(WS-DECODE-AT:2) = '\u'
                   COMPUTE WS-HEX-AT = WS-DECODE-AT + 2
                   PERFORM 7210-READ-FOUR-HEX-DIGITS
                   MOVE WS-HEX-VALUE TO WS-LOW-SURROGATE
                   IF WS-LOW-SURROGATE >= 56320
                      AND WS-LOW-SURROGATE <= 57343
                       COMPUTE WS-RUNE = 65536
                           + (WS-CODE-POINT - 55296) * 1024
                           + (WS-LOW-SURROGATE - 56320)
                       ADD 6 TO WS-DECODE-AT
                   END-IF
               END-IF
           END-IF
           PERFORM 7400-EMIT-RUNE-AS-UTF8.

       7210-READ-FOUR-HEX-DIGITS.
           MOVE 0 TO WS-HEX-VALUE
           PERFORM VARYING WS-HEX-INDEX FROM 0 BY 1
                   UNTIL WS-HEX-INDEX > 3
               MOVE REQ-BODY(WS-HEX-AT + WS-HEX-INDEX:1) TO WS-BYTE
               EVALUATE TRUE
                   WHEN WS-BYTE <= '9'
                       COMPUTE WS-HEX-VALUE =
                           WS-HEX-VALUE * 16 + WS-BYTE-VALUE - 48
                   WHEN WS-BYTE <= 'F'
                       COMPUTE WS-HEX-VALUE =
                           WS-HEX-VALUE * 16 + WS-BYTE-VALUE - 55
                   WHEN OTHER
                       COMPUTE WS-HEX-VALUE =
                           WS-HEX-VALUE * 16 + WS-BYTE-VALUE - 87
               END-EVALUATE
           END-PERFORM.

       7300-COPY-UTF8-SEQUENCE.
      *    A NON-ASCII BYTE: COPY THE WHOLE CHARACTER IF IT IS WELL
      *    FORMED, OTHERWISE WRITE U+FFFD FOR THIS ONE BAD BYTE.
           MOVE 'SEQ ' TO U8-FUNCTION
           MOVE WS-DECODE-AT TO U8-POSITION
           COMPUTE U8-END = WS-STRING-END - 1
           CALL 'UTF8TEXT' USING UTF8-WORK REQ-BODY
           IF U8-SEQUENCE-LENGTH = 0
               MOVE 65533 TO WS-RUNE
               PERFORM 7400-EMIT-RUNE-AS-UTF8
               ADD 1 TO WS-DECODE-AT
           ELSE
               PERFORM VARYING WS-COPY-INDEX FROM 0 BY 1
                       UNTIL WS-COPY-INDEX >= U8-SEQUENCE-LENGTH
                   MOVE REQ-BODY(WS-DECODE-AT + WS-COPY-INDEX:1)
                     TO WS-OUT-BYTE
                   PERFORM 7900-EMIT-BYTE
               END-PERFORM
               ADD U8-SEQUENCE-LENGTH TO WS-DECODE-AT
           END-IF.

       7400-EMIT-RUNE-AS-UTF8.
      *    UTF-8 PACKS A CHARACTER NUMBER INTO 1 TO 4 BYTES, 6 BITS PER
      *    CONTINUATION BYTE. DIVIDING BY 64 SHIFTS 6 BITS AWAY, AND
      *    MOD 64 KEEPS THE LOW 6.
           EVALUATE TRUE
               WHEN WS-RUNE < 128
                   MOVE WS-RUNE TO WS-OUT-VALUE
                   PERFORM 7900-EMIT-BYTE
               WHEN WS-RUNE < 2048
                   COMPUTE WS-OUT-VALUE = 192 + WS-RUNE / 64
                   PERFORM 7900-EMIT-BYTE
                   COMPUTE WS-OUT-VALUE =
                       128 + FUNCTION MOD(WS-RUNE, 64)
                   PERFORM 7900-EMIT-BYTE
               WHEN WS-RUNE < 65536
                   COMPUTE WS-OUT-VALUE = 224 + WS-RUNE / 4096
                   PERFORM 7900-EMIT-BYTE
                   COMPUTE WS-SIXTY-FOURTHS = WS-RUNE / 64
                   COMPUTE WS-OUT-VALUE =
                       128 + FUNCTION MOD(WS-SIXTY-FOURTHS, 64)
                   PERFORM 7900-EMIT-BYTE
                   COMPUTE WS-OUT-VALUE =
                       128 + FUNCTION MOD(WS-RUNE, 64)
                   PERFORM 7900-EMIT-BYTE
               WHEN OTHER
                   COMPUTE WS-OUT-VALUE = 240 + WS-RUNE / 262144
                   PERFORM 7900-EMIT-BYTE
                   COMPUTE WS-SIXTY-FOURTHS = WS-RUNE / 4096
                   COMPUTE WS-OUT-VALUE =
                       128 + FUNCTION MOD(WS-SIXTY-FOURTHS, 64)
                   PERFORM 7900-EMIT-BYTE
                   COMPUTE WS-SIXTY-FOURTHS = WS-RUNE / 64
                   COMPUTE WS-OUT-VALUE =
                       128 + FUNCTION MOD(WS-SIXTY-FOURTHS, 64)
                   PERFORM 7900-EMIT-BYTE
                   COMPUTE WS-OUT-VALUE =
                       128 + FUNCTION MOD(WS-RUNE, 64)
                   PERFORM 7900-EMIT-BYTE
           END-EVALUATE.

       7900-EMIT-BYTE.
           IF DECODE-INTO-KEY
               ADD 1 TO WS-KEY-LENGTH
               IF WS-KEY-LENGTH <= LENGTH OF WS-KEY
                   MOVE WS-OUT-BYTE TO WS-KEY(WS-KEY-LENGTH:1)
               END-IF
           ELSE
               ADD 1 TO JB-TITLE-LENGTH
               MOVE WS-OUT-BYTE TO JB-TITLE(JB-TITLE-LENGTH:1)
           END-IF.
