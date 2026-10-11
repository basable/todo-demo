      *================================================================*
      * UTF8WORK - ONE REQUEST TO UTF8TEXT.                            *
      *                                                                *
      * 'SEQ ': IS THERE A WELL-FORMED UTF-8 CHARACTER AT U8-POSITION, *
      *         ENDING NO LATER THAN U8-END? U8-SEQUENCE-LENGTH IS ITS *
      *         SIZE IN BYTES (1 TO 4), OR 0 WHEN THE BYTES ARE BROKEN.*
      * 'TRIM': NARROW U8-POSITION..U8-END TO DROP UNICODE WHITESPACE  *
      *         AT BOTH ENDS, AND COUNT THE CHARACTERS THAT REMAIN     *
      *         INTO U8-CHARACTERS.                                    *
      * 'CUT ': KEEP AT MOST U8-BYTE-LIMIT BYTES FROM U8-POSITION,     *
      *         WITHOUT SPLITTING A CHARACTER, AND DROP WHITESPACE THE *
      *         CUT LEAVES AT THE END. U8-END MOVES IN TO MATCH.       *
      *================================================================*
       01  UTF8-WORK.
           05  U8-FUNCTION             PIC X(4).
           05  U8-POSITION             BINARY-LONG.
           05  U8-END                  BINARY-LONG.
           05  U8-SEQUENCE-LENGTH      BINARY-LONG.
           05  U8-CHARACTERS           BINARY-LONG.
           05  U8-BYTE-LIMIT           BINARY-LONG.
