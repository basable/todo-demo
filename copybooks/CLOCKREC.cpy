      *================================================================*
      * CLOCKREC - THE TIME, AS UTCCLOCK RETURNS IT.                   *
      *================================================================*
       01  CLOCK-READING.
      *    HUNDREDTHS OF A SECOND SINCE 1 JANUARY 1601, COBOL'S DAY 1.
      *    ONLY USED TO MEASURE TIME LIMITS.
           05  CLK-TICKS               BINARY-DOUBLE.
      *    "2026/10/11 12:28:23", THE STAMP GO'S LOG PACKAGE WRITES.
           05  CLK-LOG-STAMP           PIC X(19).
      *    "Sun, 11 Oct 2026 12:28:23 GMT", FOR THE DATE HEADER.
           05  CLK-HTTP-DATE           PIC X(29).
