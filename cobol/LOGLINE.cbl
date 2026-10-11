      *================================================================*
      * LOGLINE - WRITE ONE LINE TO THE LOG.                           *
      *                                                                *
      * THE LINE GOES TO STANDARD ERROR, STAMPED THE WAY GO'S LOG      *
      * PACKAGE STAMPS IT ("2026/10/11 12:28:23 LISTENING ON ..."), SO *
      * THE POD'S LOGS READ THE SAME AS BEFORE THE PORT.               *
      *================================================================*
       IDENTIFICATION DIVISION.
       PROGRAM-ID. LOGLINE.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. LINUX-X86-64.
       OBJECT-COMPUTER. LINUX-X86-64.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY CLOCKREC.

      *    THE LINKAGE SECTION DESCRIBES DATA THAT BELONGS TO THE
      *    CALLER. "CALL 'LOGLINE' USING X" LETS THIS PROGRAM SEE THE
      *    CALLER'S FIELD X UNDER THE NAME LOG-TEXT.
       LINKAGE SECTION.
       01  LOG-TEXT                    PIC X(1024).

       PROCEDURE DIVISION USING LOG-TEXT.
       0000-MAIN.
           CALL 'UTCCLOCK' USING CLOCK-READING
           DISPLAY CLK-LOG-STAMP ' '
                   FUNCTION TRIM(LOG-TEXT TRAILING)
               UPON SYSERR
           END-DISPLAY
           GOBACK.
