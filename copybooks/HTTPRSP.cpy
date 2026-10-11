      *================================================================*
      * HTTPRSP - ONE HTTP RESPONSE, WRITTEN TO THE SOCKET BY HTTPSEND.*
      *                                                                *
      * A FIELD LEFT AS SPACES MEANS "NO SUCH HEADER". HTTPSEND ADDS   *
      * THE HEADERS EVERY RESPONSE CARRIES: CONTENT-SECURITY-POLICY,   *
      * X-CONTENT-TYPE-OPTIONS, DATE, CONTENT-LENGTH AND CONNECTION.   *
      *================================================================*
       01  HTTP-RESPONSE.
      *    "HTTP/1.1", OR "HTTP/1.0" WHEN ANSWERING AN HTTP/1.0 CLIENT.
           05  RSP-PROTOCOL            PIC X(8).
      *    PIC 9(3) HOLDS EXACTLY THREE DECIMAL DIGITS: 200, 404, ...
           05  RSP-STATUS              PIC 9(3).
      *    THE TEXT AFTER THE CODE ("OK", "NOT FOUND"). SPACES MEANS
      *    HTTPSEND LOOKS UP THE STANDARD ONE.
           05  RSP-REASON              PIC X(64).
           05  RSP-CONTENT-TYPE        PIC X(40).
           05  RSP-ALLOW               PIC X(32).
           05  RSP-LOCATION-LENGTH     BINARY-LONG.
           05  RSP-LOCATION            PIC X(49200).
           05  RSP-BODY-FLAG           PIC X.
      *        A HEAD REQUEST GETS THE HEADERS OF A GET, BUT NO BODY.
               88  RSP-BODY-SUPPRESSED VALUE 'Y'.
               88  RSP-BODY-SENT       VALUE 'N'.
           05  RSP-BODY-LENGTH         BINARY-LONG.
      *    16 MIB: ROOM FOR SOME TEN THOUSAND TODOS EVEN IF EVERY ONE
      *    OF THEM HAS A 200-CHARACTER TITLE THAT NEEDS ESCAPING.
           05  RSP-BODY                PIC X(16777216).
