      *================================================================*
      * URLWORK - ONE REQUEST TO URLPATH.                              *
      *                                                                *
      * 'CLEAN   ': TIDY A PATH THE WAY GO'S SERVEMUX DOES: "//", "."  *
      *             AND ".." DISAPPEAR, A TRAILING "/" STAYS.          *
      * 'CLEANDIR': THE SAME, BUT DROP A TRAILING "/" TOO, LIKE GO'S   *
      *             PATH.CLEAN.                                        *
      * 'DECODE  ': TURN %-ESCAPES BACK INTO BYTES ("%41" -> "A").     *
      *================================================================*
       01  URL-WORK.
           05  UW-FUNCTION             PIC X(8).
           05  UW-INPUT-LENGTH         BINARY-LONG.
           05  UW-INPUT                PIC X(8200).
           05  UW-OUTPUT-LENGTH        BINARY-LONG.
           05  UW-OUTPUT               PIC X(8200).
