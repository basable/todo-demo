      *================================================================*
      * HTTPREQ - ONE PARSED HTTP REQUEST, FILLED IN BY HTTPRECV.      *
      *                                                                *
      * A LEVEL-88 ENTRY IS A NAMED CONDITION ON THE FIELD ABOVE IT:   *
      * "IF REQ-IS-READY" MEANS "IF REQ-OUTCOME = 'R'", AND            *
      * "SET REQ-IS-READY TO TRUE" STORES THE 'R'.                     *
      *================================================================*
       01  HTTP-REQUEST.
           05  REQ-OUTCOME             PIC X.
      *        THE REQUEST IS COMPLETE AND VALID: ROUTE IT.
               88  REQ-IS-READY        VALUE 'R'.
      *        THE REQUEST IS MALFORMED: HTTPRECV HAS ALREADY PUT THE
      *        ERROR RESPONSE (400, 505, ...) INTO HTTP-RESPONSE.
               88  REQ-IS-REJECTED     VALUE 'X'.
      *        THE CLIENT HUNG UP OR RAN OUT OF TIME: SAY NOTHING.
               88  REQ-IS-ABANDONED    VALUE 'A'.
      *    THE METHOD (GET, POST, ...) AND HOW LONG IT REALLY WAS.
      *    A METHOD LONGER THAN THE FIELD CAN NEVER BE ONE WE ROUTE.
           05  REQ-METHOD              PIC X(16).
               88  REQ-IS-GET          VALUE 'GET'.
               88  REQ-IS-HEAD         VALUE 'HEAD'.
               88  REQ-IS-GET-OR-HEAD  VALUES 'GET' 'HEAD'.
               88  REQ-IS-POST         VALUE 'POST'.
               88  REQ-IS-PATCH        VALUE 'PATCH'.
               88  REQ-IS-DELETE       VALUE 'DELETE'.
               88  REQ-IS-OPTIONS      VALUE 'OPTIONS'.
           05  REQ-METHOD-LENGTH       BINARY-LONG.
      *    THE X IN HTTP/1.X. 0 MEANS HTTP/1.0.
           05  REQ-MINOR-VERSION       PIC 9.
           05  REQ-TARGET-FORM         PIC X.
      *        "/PATH?QUERY" OR "HTTP://HOST/PATH?QUERY".
               88  REQ-TARGET-IS-PATH  VALUE 'P'.
      *        "*", AS IN "OPTIONS * HTTP/1.1".
               88  REQ-TARGET-IS-STAR  VALUE '*'.
      *    THE PATH EXACTLY AS SENT, STILL %-ENCODED, AND THE QUERY.
           05  REQ-PATH-LENGTH         BINARY-LONG.
           05  REQ-PATH                PIC X(8192).
           05  REQ-QUERY-LENGTH        BINARY-LONG.
           05  REQ-QUERY               PIC X(8192).
      *    -1 WHEN THE REQUEST HAS NO CONTENT-LENGTH HEADER.
           05  REQ-CONTENT-LENGTH      BINARY-DOUBLE.
           05  REQ-EXPECT-FLAG         PIC X.
      *        "EXPECT: 100-CONTINUE": THE CLIENT WAITS FOR OUR NOD
      *        BEFORE IT SENDS THE BODY.
               88  REQ-EXPECTS-CONTINUE VALUE 'Y'.
      *    THE BODY, READ ONLY WHEN A HANDLER ASKS FOR IT, AND NEVER
      *    MORE THAN 1 MIB OF IT (GO'S HTTP.MAXBYTESREADER LIMIT).
           05  REQ-BODY-LENGTH         BINARY-LONG.
           05  REQ-BODY                PIC X(1048576).
