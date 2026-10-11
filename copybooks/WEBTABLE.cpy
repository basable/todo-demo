      *================================================================*
      * WEBTABLE - THE FILES IN WEB/, LOADED INTO MEMORY AT STARTUP.   *
      *                                                                *
      * OCCURS MAKES A TABLE: WEB-FILE(1), WEB-FILE(2), WEB-FILE(3).   *
      * "INDEXED BY" GIVES IT AN INDEX THAT THE SEARCH STATEMENT USES  *
      * TO LOOK A FILE UP BY ITS URL. ONLY THESE FILES ARE EVER SENT;  *
      * NO URL IS EVER TURNED INTO A PATH ON DISK.                     *
      *================================================================*
       01  WEB-FILE-TABLE.
           05  WEB-FILE                OCCURS 3 TIMES
                                       INDEXED BY WEB-INDEX.
               10  WEB-URL-PATH        PIC X(16).
               10  WEB-DISK-PATH       PIC X(32).
               10  WEB-CONTENT-TYPE    PIC X(40).
               10  WEB-FILE-SIZE       BINARY-LONG.
               10  WEB-FILE-BYTES      PIC X(65536).
