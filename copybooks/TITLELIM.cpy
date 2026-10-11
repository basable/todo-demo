      *================================================================*
      * TITLELIM - THE LONGEST TITLE THE APP KEEPS.                    *
      *                                                                *
      * THE APP IS OPEN TO THE WHOLE INTERNET, SO A TITLE IS CUT TO AT *
      * MOST 64 BYTES, BOTH WHEN IT IS STORED AND WHEN IT IS SENT OUT  *
      * (WHICH ALSO SHORTENS ROWS THE GO VERSION STORED). THE CUT      *
      * NEVER SPLITS A CHARACTER, SO IT MAY KEEP A FEW BYTES LESS.     *
      * "CONSTANT" MAKES THIS A NAMED NUMBER, NOT A VARIABLE.          *
      *================================================================*
       01  TITLE-BYTE-LIMIT            CONSTANT AS 64.
