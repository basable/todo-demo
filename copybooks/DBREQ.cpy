      *================================================================*
      * DBREQ - ONE REQUEST TO TODODB, THE PROGRAM THAT OWNS ALL SQL.  *
      *                                                                *
      * THE CALLER PUTS A FUNCTION CODE IN DB-FUNCTION, CALLS TODODB   *
      * AND READS THE OUTCOME FROM DB-STATUS. THIS "FUNCTION CODE"     *
      * INTERFACE IS HOW MAINFRAME DATA-ACCESS MODULES HAVE BEEN       *
      * CALLED SINCE THE 1970S.                                        *
      *================================================================*
       01  DB-REQUEST.
           05  DB-FUNCTION             PIC X(8).
      *        WAIT FOR THE DATABASE: UP TO 60 TRIES, 2 SECONDS APART.
               88  DB-FN-CONNECT       VALUE 'CONNECT'.
      *        CREATE THE TODOS TABLE IF IT DOES NOT EXIST YET.
               88  DB-FN-MIGRATE       VALUE 'MIGRATE'.
      *        LIST: OPEN THE CURSOR, FETCH ONE ROW AT A TIME, CLOSE.
               88  DB-FN-LIST-OPEN     VALUE 'LISTOPEN'.
               88  DB-FN-LIST-NEXT     VALUE 'LISTNEXT'.
               88  DB-FN-LIST-CLOSE    VALUE 'LISTSTOP'.
               88  DB-FN-CREATE        VALUE 'CREATE'.
               88  DB-FN-SET-DONE      VALUE 'SETDONE'.
               88  DB-FN-DELETE        VALUE 'DELETE'.
           05  DB-STATUS               PIC X(8).
               88  DB-OK               VALUE 'OK'.
               88  DB-NOT-FOUND        VALUE 'NOTFOUND'.
               88  DB-END-OF-LIST      VALUE 'END'.
               88  DB-FAILED           VALUE 'FAILED'.
      *    WHY IT FAILED, FOR THE LOG.
           05  DB-MESSAGE              PIC X(200).
