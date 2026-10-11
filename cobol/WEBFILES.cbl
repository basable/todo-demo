      *================================================================*
      * WEBFILES - LOAD THE FILES IN WEB/ INTO MEMORY AT STARTUP.      *
      *                                                                *
      * THE GO VERSION BAKED WEB/ INTO ITS BINARY. THIS ONE READS THE  *
      * SAME THREE FILES ONCE, WITH ORDINARY COBOL FILE I/O, AND THE   *
      * SERVER ANSWERS FROM MEMORY AFTER THAT. A FILE ADDED TO WEB/    *
      * NEEDS A LINE IN 1000-DESCRIBE-FILES (AND A BIGGER OCCURS IN    *
      * WEBTABLE) BEFORE IT IS SERVED.                                 *
      *================================================================*
       IDENTIFICATION DIVISION.
       PROGRAM-ID. WEBFILES.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. LINUX-X86-64.
       OBJECT-COMPUTER. LINUX-X86-64.
      *    THE INPUT-OUTPUT SECTION TIES A FILE NAME USED IN THE
      *    PROGRAM TO A FILE ON DISK. "ASSIGN TO WS-DISK-PATH" MEANS
      *    "WHATEVER PATH WS-DISK-PATH HOLDS WHEN THE FILE IS OPENED",
      *    SO ONE DEFINITION SERVES ALL THREE FILES IN TURN.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT WEB-FILE-IN ASSIGN TO WS-DISK-PATH
               ORGANIZATION IS SEQUENTIAL
               ACCESS MODE IS SEQUENTIAL
               FILE STATUS IS WS-FILE-STATUS.

       DATA DIVISION.
       FILE SECTION.
      *    FD = FILE DESCRIPTION. RECORDS OF ONE CHARACTER MEAN EACH
      *    READ RETURNS THE NEXT BYTE, SO ANY FILE COMES IN EXACTLY.
       FD  WEB-FILE-IN
           RECORD CONTAINS 1 CHARACTERS.
       01  WEB-FILE-BYTE               PIC X.

       WORKING-STORAGE SECTION.
       01  WS-DISK-PATH                PIC X(32).
      *    EVERY FILE OPERATION SETS A TWO-CHARACTER STATUS:
      *    '00' FINE, '10' END OF FILE, '35' NO SUCH FILE, AND SO ON.
       01  WS-FILE-STATUS              PIC XX.
           88  WS-FILE-OK              VALUE '00'.
           88  WS-FILE-AT-END          VALUE '10'.
       01  WS-FILE-NUMBER              BINARY-LONG.
       01  WS-SIZE                     BINARY-LONG.

       LINKAGE SECTION.
       COPY WEBTABLE.
      *    SPACES WHEN EVERY FILE LOADED, OR WHAT WENT WRONG.
       01  WF-ERROR                    PIC X(200).

       PROCEDURE DIVISION USING WEB-FILE-TABLE WF-ERROR.
       0000-MAIN.
           MOVE SPACES TO WF-ERROR
           PERFORM 1000-DESCRIBE-FILES
           PERFORM 2000-LOAD-ONE-FILE
               VARYING WS-FILE-NUMBER FROM 1 BY 1
               UNTIL WS-FILE-NUMBER > 3 OR WF-ERROR NOT = SPACES
           GOBACK.

       1000-DESCRIBE-FILES.
           MOVE '/index.html'              TO WEB-URL-PATH(1)
           MOVE 'web/index.html'           TO WEB-DISK-PATH(1)
           MOVE 'text/html; charset=utf-8' TO WEB-CONTENT-TYPE(1)

           MOVE '/app.js'                  TO WEB-URL-PATH(2)
           MOVE 'web/app.js'               TO WEB-DISK-PATH(2)
           MOVE 'text/javascript; charset=utf-8'
                                           TO WEB-CONTENT-TYPE(2)

           MOVE '/style.css'               TO WEB-URL-PATH(3)
           MOVE 'web/style.css'            TO WEB-DISK-PATH(3)
           MOVE 'text/css; charset=utf-8'  TO WEB-CONTENT-TYPE(3).

       2000-LOAD-ONE-FILE.
           MOVE WEB-DISK-PATH(WS-FILE-NUMBER) TO WS-DISK-PATH
           MOVE 0 TO WS-SIZE
           OPEN INPUT WEB-FILE-IN
           IF NOT WS-FILE-OK
               STRING 'open ' FUNCTION TRIM(WS-DISK-PATH)
                      ': file status ' WS-FILE-STATUS
                   DELIMITED BY SIZE INTO WF-ERROR
               END-STRING
               EXIT PARAGRAPH
           END-IF

           PERFORM UNTIL NOT WS-FILE-OK
               READ WEB-FILE-IN
                   AT END
                       CONTINUE
                   NOT AT END
                       IF WS-SIZE = LENGTH OF WEB-FILE-BYTES(1)
                           STRING FUNCTION TRIM(WS-DISK-PATH)
                                  ' is larger than 65536 bytes'
                               DELIMITED BY SIZE INTO WF-ERROR
                           END-STRING
                           MOVE '99' TO WS-FILE-STATUS
                       ELSE
                           ADD 1 TO WS-SIZE
                           MOVE WEB-FILE-BYTE TO
                               WEB-FILE-BYTES(WS-FILE-NUMBER)(WS-SIZE:1)
                       END-IF
               END-READ
           END-PERFORM
           IF NOT WS-FILE-AT-END AND WF-ERROR = SPACES
               STRING 'read ' FUNCTION TRIM(WS-DISK-PATH)
                      ': file status ' WS-FILE-STATUS
                   DELIMITED BY SIZE INTO WF-ERROR
               END-STRING
           END-IF
           CLOSE WEB-FILE-IN
           MOVE WS-SIZE TO WEB-FILE-SIZE(WS-FILE-NUMBER).
