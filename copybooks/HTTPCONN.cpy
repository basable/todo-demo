      *================================================================*
      * HTTPCONN - ONE CLIENT CONNECTION.                              *
      *                                                                *
      * A COPYBOOK IS A SHARED PIECE OF SOURCE: EVERY PROGRAM THAT     *
      * SAYS "COPY HTTPCONN." GETS THIS EXACT RECORD LAYOUT, SO THE    *
      * PROGRAMS AGREE ON WHERE EACH FIELD STARTS AND ENDS.            *
      *                                                                *
      * HOW TO READ A RECORD:                                          *
      *   01 STARTS A RECORD, 05 IS A FIELD INSIDE IT.                 *
      *   BINARY-LONG   IS A 32-BIT MACHINE INTEGER.                   *
      *   BINARY-DOUBLE IS A 64-BIT MACHINE INTEGER.                   *
      *   PIC X(n)      IS n BYTES OF TEXT ("PIC" = PICTURE).          *
      *================================================================*
       01  HTTP-CONNECTION.
      *    THE SOCKET NUMBER THAT ACCEPT() HANDED US FOR THIS CLIENT.
           05  CONN-SOCKET             BINARY-LONG.
      *    THE WHOLE REQUEST MUST ARRIVE BEFORE THIS MOMENT, IN
      *    HUNDREDTHS OF A SECOND (SEE UTCCLOCK). A SLOW CLIENT IS
      *    CUT OFF HERE, SO IT CANNOT HOLD THE SERVER HOSTAGE.
           05  CONN-DEADLINE           BINARY-DOUBLE.
      *    HOW MANY BYTES HAVE ARRIVED IN CONN-BUFFER SO FAR.
           05  CONN-RECEIVED           BINARY-LONG.
      *    WHERE THE REQUEST LINE AND HEADERS END (THE BLANK LINE).
      *    ANYTHING AFTER IT IN CONN-BUFFER IS THE START OF THE BODY.
           05  CONN-HEAD-LENGTH        BINARY-LONG.
      *    THE RAW BYTES OFF THE WIRE. 1 MIB + 4 KIB, THE SAME LIMIT
      *    GO'S NET/HTTP PUTS ON A REQUEST LINE PLUS ITS HEADERS.
           05  CONN-BUFFER             PIC X(1052672).
