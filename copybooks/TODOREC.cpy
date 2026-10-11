      *================================================================*
      * TODOREC - ONE TODO, AS THE DATABASE STORES IT.                 *
      *                                                                *
      * PIC S9(19) IS A SIGNED NUMBER OF UP TO 19 DECIMAL DIGITS:      *
      * WIDE ENOUGH FOR EVERY POSITIVE 64-BIT INTEGER, WHICH IS WHAT   *
      * POSTGRESQL'S BIGSERIAL HANDS OUT.                              *
      *================================================================*
       01  TODO-RECORD.
           05  TODO-ID                 PIC S9(19).
      *    THE APP STORES AT MOST 64 BYTES OF A TITLE (TITLELIM). 800
      *    BYTES ALSO HOLD ANY TITLE THE GO VERSION STORED: AT MOST 200
      *    CHARACTERS OF AT MOST 4 BYTES EACH.
           05  TODO-TITLE-LENGTH       BINARY-LONG.
           05  TODO-TITLE              PIC X(800).
           05  TODO-DONE-FLAG          PIC X.
               88  TODO-IS-DONE        VALUE 'Y'.
               88  TODO-IS-OPEN        VALUE 'N'.
      *    WHEN THE TODO WAS CREATED, IN UTC, AS POSTGRESQL'S TO_CHAR
      *    WRITES 'YYYYMMDDHH24MISSUS': 20 DIGITS, DOWN TO THE
      *    MICROSECOND. THE NAMED PIECES BELOW SPLIT THEM UP AGAIN.
           05  TODO-CREATED-AT.
               10  TODO-CREATED-YEAR   PIC X(4).
               10  TODO-CREATED-MONTH  PIC X(2).
               10  TODO-CREATED-DAY    PIC X(2).
               10  TODO-CREATED-HOUR   PIC X(2).
               10  TODO-CREATED-MINUTE PIC X(2).
               10  TODO-CREATED-SECOND PIC X(2).
               10  TODO-CREATED-MICROS PIC X(6).
