      *================================================================*
      * UTCCLOCK - WHAT TIME IS IT, IN UTC?                            *
      *                                                                *
      * FUNCTION CURRENT-DATE RETURNS THE LOCAL DATE AND TIME AND HOW  *
      * FAR LOCAL TIME IS FROM UTC. THIS PROGRAM TAKES THAT OFFSET OFF *
      * AGAIN AND HANDS BACK THE TIME THREE WAYS (SEE CLOCKREC): AS A  *
      * COUNTER FOR TIME LIMITS, AS A LOG STAMP AND AS AN HTTP DATE.   *
      *================================================================*
       IDENTIFICATION DIVISION.
       PROGRAM-ID. UTCCLOCK.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. LINUX-X86-64.
       OBJECT-COMPUTER. LINUX-X86-64.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
      *    THE 21 CHARACTERS OF FUNCTION CURRENT-DATE, GIVEN NAMES.
      *    PIC 99 IS A TWO-DIGIT NUMBER, PIC 9(8) AN EIGHT-DIGIT ONE.
       01  WS-NOW.
           05  WS-NOW-DATE             PIC 9(8).
           05  WS-NOW-HOUR             PIC 99.
           05  WS-NOW-MINUTE           PIC 99.
           05  WS-NOW-SECOND           PIC 99.
           05  WS-NOW-HUNDREDTHS       PIC 99.
           05  WS-NOW-OFFSET-SIGN      PIC X.
           05  WS-NOW-OFFSET-HOURS     PIC 99.
           05  WS-NOW-OFFSET-MINUTES   PIC 99.

       01  WS-DAY-NUMBER               BINARY-LONG.
       01  WS-SECOND-OF-DAY            BINARY-LONG.
       01  WS-OFFSET-SECONDS           BINARY-LONG.
       01  WS-WEEKDAY                  BINARY-LONG.
       01  WS-UTC-HOUR                 PIC 99.
       01  WS-UTC-MINUTE               PIC 99.
       01  WS-UTC-SECOND               PIC 99.

      *    REDEFINES LAYS A SECOND DESCRIPTION OVER THE SAME BYTES:
      *    THE EIGHT DIGITS OF WS-UTC-DATE CAN ALSO BE READ AS A YEAR,
      *    A MONTH AND A DAY.
       01  WS-UTC-DATE                 PIC 9(8).
       01  WS-UTC-DATE-PARTS REDEFINES WS-UTC-DATE.
           05  WS-UTC-YEAR             PIC 9(4).
           05  WS-UTC-MONTH            PIC 99.
           05  WS-UTC-DAY              PIC 99.

      *    TWO LOOKUP TABLES, EACH WRITTEN AS ONE STRING AND REDEFINED
      *    AS A TABLE OF THREE-LETTER ENTRIES. DAY 1 OF COBOL'S
      *    CALENDAR, 1 JANUARY 1601, WAS A MONDAY, SO THE WEEK HERE
      *    STARTS ON MONDAY.
       01  WS-DAY-NAME-LIST            PIC X(21)
           VALUE 'MonTueWedThuFriSatSun'.
       01  WS-DAY-NAMES REDEFINES WS-DAY-NAME-LIST.
           05  WS-DAY-NAME             PIC X(3) OCCURS 7 TIMES.
       01  WS-MONTH-NAME-LIST          PIC X(36)
           VALUE 'JanFebMarAprMayJunJulAugSepOctNovDec'.
       01  WS-MONTH-NAMES REDEFINES WS-MONTH-NAME-LIST.
           05  WS-MONTH-NAME           PIC X(3) OCCURS 12 TIMES.

       LINKAGE SECTION.
       COPY CLOCKREC.

       PROCEDURE DIVISION USING CLOCK-READING.
       0000-MAIN.
           MOVE FUNCTION CURRENT-DATE TO WS-NOW
           PERFORM 1000-CONVERT-TO-UTC
           PERFORM 2000-FORMAT-READINGS
           GOBACK.

       1000-CONVERT-TO-UTC.
      *    HOW MANY SECONDS LOCAL TIME IS AHEAD OF UTC.
           MOVE ZERO TO WS-OFFSET-SECONDS
           IF WS-NOW-OFFSET-HOURS IS NUMERIC
              AND WS-NOW-OFFSET-MINUTES IS NUMERIC
               COMPUTE WS-OFFSET-SECONDS = WS-NOW-OFFSET-HOURS * 3600
                                         + WS-NOW-OFFSET-MINUTES * 60
               IF WS-NOW-OFFSET-SIGN = '-'
                   MULTIPLY -1 BY WS-OFFSET-SECONDS
               END-IF
           END-IF
      *    INTEGER-OF-DATE TURNS YYYYMMDD INTO A DAY NUMBER, WHICH
      *    MAKES "THE DAY BEFORE" AND "THE DAY AFTER" PLAIN ARITHMETIC.
           COMPUTE WS-DAY-NUMBER =
               FUNCTION INTEGER-OF-DATE(WS-NOW-DATE)
           COMPUTE WS-SECOND-OF-DAY = WS-NOW-HOUR * 3600
                                    + WS-NOW-MINUTE * 60
                                    + WS-NOW-SECOND
                                    - WS-OFFSET-SECONDS
           IF WS-SECOND-OF-DAY < 0
               ADD 86400 TO WS-SECOND-OF-DAY
               SUBTRACT 1 FROM WS-DAY-NUMBER
           END-IF
           IF WS-SECOND-OF-DAY >= 86400
               SUBTRACT 86400 FROM WS-SECOND-OF-DAY
               ADD 1 TO WS-DAY-NUMBER
           END-IF.

       2000-FORMAT-READINGS.
           COMPUTE CLK-TICKS = WS-DAY-NUMBER * 8640000
                             + WS-SECOND-OF-DAY * 100
                             + WS-NOW-HUNDREDTHS
           MOVE FUNCTION DATE-OF-INTEGER(WS-DAY-NUMBER) TO WS-UTC-DATE
      *    A COMPUTE INTO A WHOLE NUMBER DROPS THE FRACTION, SO
      *    7199 / 3600 STORES 1, NOT 1.99.
           COMPUTE WS-UTC-HOUR   = WS-SECOND-OF-DAY / 3600
           COMPUTE WS-UTC-MINUTE =
               FUNCTION MOD(WS-SECOND-OF-DAY, 3600) / 60
           COMPUTE WS-UTC-SECOND = FUNCTION MOD(WS-SECOND-OF-DAY, 60)
           COMPUTE WS-WEEKDAY = FUNCTION MOD(WS-DAY-NUMBER - 1, 7) + 1

           STRING WS-UTC-YEAR  '/' WS-UTC-MONTH  '/' WS-UTC-DAY ' '
                  WS-UTC-HOUR  ':' WS-UTC-MINUTE ':' WS-UTC-SECOND
               DELIMITED BY SIZE INTO CLK-LOG-STAMP
           END-STRING

           STRING WS-DAY-NAME(WS-WEEKDAY) ', ' WS-UTC-DAY ' '
                  WS-MONTH-NAME(WS-UTC-MONTH) ' ' WS-UTC-YEAR ' '
                  WS-UTC-HOUR ':' WS-UTC-MINUTE ':' WS-UTC-SECOND
                  ' GMT'
               DELIMITED BY SIZE INTO CLK-HTTP-DATE
           END-STRING.
