      *================================================================*
      * TODODB - THE TODO STORE. EVERY SQL STATEMENT LIVES HERE.       *
      *                                                                *
      * THE SQL IS WRITTEN INLINE AS "EXEC SQL ... END-EXEC". BEFORE   *
      * COMPILING, THE OCESQL PREPROCESSOR REWRITES EACH ONE INTO      *
      * CALLS TO ITS RUNTIME, WHICH TALKS TO POSTGRESQL THROUGH LIBPQ. *
      *                                                                *
      * VALUES ONLY EVER TRAVEL IN HOST VARIABLES (":HV-TITLE"). THE   *
      * PREPROCESSOR TURNS EACH ONE INTO A STATEMENT PARAMETER ($1,    *
      * $2) THAT POSTGRESQL RECEIVES SEPARATELY FROM THE SQL TEXT, SO  *
      * NO TITLE CAN EVER BECOME PART OF A QUERY.                      *
      *                                                                *
      * THE STATEMENTS ARE THOSE OF THE GO VERSION'S STORE.GO.         *
      *================================================================*
       IDENTIFICATION DIVISION.
       PROGRAM-ID. TODODB.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. LINUX-X86-64.
       OBJECT-COMPUTER. LINUX-X86-64.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
      *    HOST VARIABLES MUST BE DECLARED BETWEEN THESE TWO MARKERS.
      *    "PIC X(800) VARYING" IS TEXT WITH ITS OWN LENGTH: OCESQL
      *    SPLITS IT INTO HV-TITLE-LEN (HOW MANY BYTES ARE REAL) AND
      *    HV-TITLE-ARR (THE BYTES), SO NO TRAILING SPACES GET STORED.
           EXEC SQL BEGIN DECLARE SECTION END-EXEC.
       01  HV-ID                       PIC S9(19).
       01  HV-TITLE                    PIC X(800) VARYING.
       01  HV-TITLE-BYTES              PIC S9(9).
       01  HV-DONE                     PIC X(5).
       01  HV-CREATED-AT               PIC X(20).
           EXEC SQL END DECLARE SECTION END-EXEC.

      *    THE SQL COMMUNICATION AREA. AFTER EVERY STATEMENT, SQLCODE
      *    IS 0 (FINE), 100 (NO ROW) OR NEGATIVE (FAILED); SQLSTATE AND
      *    SQLERRMC SAY WHY, AND SQLERRD(3) COUNTS THE ROWS TOUCHED.
           EXEC SQL INCLUDE SQLCA END-EXEC.

      *    PARSING DATABASE_URL, E.G.
      *    postgres://postgres@postgres:5432/todos?sslmode=disable
       01  WS-DATABASE-URL             PIC X(2048).
       01  WS-URL-LENGTH               BINARY-LONG.
       01  WS-AT                       BINARY-LONG.
       01  WS-SCAN                     BINARY-LONG.
       01  WS-PART-START               BINARY-LONG.
       01  WS-PART-END                 BINARY-LONG.
       01  WS-AUTHORITY-END            BINARY-LONG.
       01  WS-COLON                    BINARY-LONG.
       01  WS-USER-INFO-END            BINARY-LONG.
       01  WS-HOST-END                 BINARY-LONG.
       01  WS-PATH-END                 BINARY-LONG.
       01  WS-EQUALS                   BINARY-LONG.
       01  WS-ENV-NAME                 PIC X(24).
       01  WS-PARAMETER-NAME           PIC X(64).
       01  WS-TIMEOUT-GIVEN            PIC X.
           88  URL-SETS-CONNECT-TIMEOUT VALUE 'Y'.
       01  WS-URL-STATE                PIC X.
           88  URL-IS-USABLE           VALUE 'Y'.
           88  URL-IS-UNUSABLE         VALUE 'N'.
       COPY URLWORK.

      *    LIBPQ, THE POSTGRESQL CLIENT LIBRARY UNDER OCESQL, READS ITS
      *    SETTINGS FROM PG* ENVIRONMENT VARIABLES. THE URL IS TAKEN
      *    APART AND EACH PIECE SET AS ONE OF THEM. THIS TABLE MAPS A
      *    URL PARAMETER ("?sslmode=disable") TO ITS VARIABLE. IT IS
      *    WRITTEN AS A LIST OF VALUES AND THEN REDEFINED AS A TABLE OF
      *    NAME PAIRS, A CLASSIC WAY TO BUILD A CONSTANT TABLE IN COBOL.
       01  WS-URL-PARAMETER-VALUES.
           05  FILLER PIC X(48) VALUE
               'application_name        PGAPPNAME'.
           05  FILLER PIC X(48) VALUE
               'channel_binding         PGCHANNELBINDING'.
           05  FILLER PIC X(48) VALUE
               'connect_timeout         PGCONNECT_TIMEOUT'.
           05  FILLER PIC X(48) VALUE
               'dbname                  PGDATABASE'.
           05  FILLER PIC X(48) VALUE
               'gssencmode              PGGSSENCMODE'.
           05  FILLER PIC X(48) VALUE
               'host                    PGHOST'.
           05  FILLER PIC X(48) VALUE
               'hostaddr                PGHOSTADDR'.
           05  FILLER PIC X(48) VALUE
               'krbsrvname              PGKRBSRVNAME'.
           05  FILLER PIC X(48) VALUE
               'options                 PGOPTIONS'.
           05  FILLER PIC X(48) VALUE
               'passfile                PGPASSFILE'.
           05  FILLER PIC X(48) VALUE
               'password                PGPASSWORD'.
           05  FILLER PIC X(48) VALUE
               'port                    PGPORT'.
           05  FILLER PIC X(48) VALUE
               'service                 PGSERVICE'.
           05  FILLER PIC X(48) VALUE
               'sslcert                 PGSSLCERT'.
           05  FILLER PIC X(48) VALUE
               'sslkey                  PGSSLKEY'.
           05  FILLER PIC X(48) VALUE
               'sslmode                 PGSSLMODE'.
           05  FILLER PIC X(48) VALUE
               'sslnegotiation          PGSSLNEGOTIATION'.
           05  FILLER PIC X(48) VALUE
               'sslrootcert             PGSSLROOTCERT'.
           05  FILLER PIC X(48) VALUE
               'target_session_attrs    PGTARGETSESSIONATTRS'.
           05  FILLER PIC X(48) VALUE
               'user                    PGUSER'.
       01  WS-URL-PARAMETER-TABLE REDEFINES WS-URL-PARAMETER-VALUES.
           05  WS-URL-PARAMETER        OCCURS 20 TIMES
                                       INDEXED BY WS-PARAMETER-INDEX.
               10  WS-PARAMETER-KEY    PIC X(24).
               10  WS-PARAMETER-ENV    PIC X(24).

       01  WS-CONNECTION-STATE         PIC X VALUE 'N'.
           88  DB-CONNECTED            VALUE 'Y'.
           88  DB-DISCONNECTED         VALUE 'N'.
       01  WS-ATTEMPT                  PIC 99.
       01  WS-ATTEMPT-SHOWN            PIC Z9.
       01  WS-SQLCODE-SHOWN            PIC -(9)9.
       01  WS-ID-SHOWN                 PIC Z(18)9.
       01  WS-LOG-TEXT                 PIC X(1024).

       LINKAGE SECTION.
       COPY DBREQ.
       COPY TODOREC.

       PROCEDURE DIVISION USING DB-REQUEST TODO-RECORD.
       0000-MAIN.
           SET DB-OK TO TRUE
           MOVE SPACES TO DB-MESSAGE
           EVALUATE TRUE
               WHEN DB-FN-CONNECT
                   PERFORM 1000-CONNECT-WITH-RETRY
               WHEN DB-FN-MIGRATE
                   PERFORM 2000-MIGRATE
               WHEN DB-FN-LIST-OPEN
                   PERFORM 3000-OPEN-LIST
               WHEN DB-FN-LIST-NEXT
                   PERFORM 3100-FETCH-NEXT-TODO
               WHEN DB-FN-LIST-CLOSE
                   PERFORM 3200-CLOSE-LIST
               WHEN DB-FN-CREATE
                   PERFORM 4000-CREATE-TODO
               WHEN DB-FN-SET-DONE
                   PERFORM 5000-SET-DONE
               WHEN DB-FN-DELETE
                   PERFORM 6000-DELETE-TODO
           END-EVALUATE
           GOBACK.

      *----------------------------------------------------------------*
      * CONNECTING. THE DATABASE MAY STILL BE STARTING, SO TRY UP TO   *
      * 60 TIMES, 2 SECONDS APART, LOGGING EACH MISS (STORE.GO).       *
      *----------------------------------------------------------------*
       1000-CONNECT-WITH-RETRY.
      *    OCESQL WOULD OTHERWISE ASK POSTGRESQL FOR SHIFT-JIS TEXT.
           SET ENVIRONMENT 'OCDB_DB_CHAR' TO 'UTF8'
           PERFORM VARYING WS-ATTEMPT FROM 1 BY 1
                   UNTIL WS-ATTEMPT > 60 OR DB-CONNECTED
               PERFORM 1100-APPLY-DATABASE-URL
               IF URL-IS-USABLE
                   PERFORM 1200-CONNECT-ONCE
               END-IF
               IF DB-DISCONNECTED
                   MOVE WS-ATTEMPT TO WS-ATTEMPT-SHOWN
                   MOVE SPACES TO WS-LOG-TEXT
                   STRING 'waiting for database (attempt '
                          FUNCTION TRIM(WS-ATTEMPT-SHOWN) '): '
                          FUNCTION TRIM(DB-MESSAGE TRAILING)
                       DELIMITED BY SIZE INTO WS-LOG-TEXT
                   END-STRING
                   CALL 'LOGLINE' USING WS-LOG-TEXT
                   CALL 'C$SLEEP' USING 2
               END-IF
           END-PERFORM
           IF DB-DISCONNECTED
               MOVE SPACES TO WS-LOG-TEXT
               STRING 'giving up: ' FUNCTION TRIM(DB-MESSAGE TRAILING)
                   DELIMITED BY SIZE INTO WS-LOG-TEXT
               END-STRING
               MOVE WS-LOG-TEXT TO DB-MESSAGE
               SET DB-FAILED TO TRUE
           ELSE
               SET DB-OK TO TRUE
               MOVE SPACES TO DB-MESSAGE
           END-IF.

       1100-APPLY-DATABASE-URL.
           SET URL-IS-USABLE TO TRUE
           MOVE 'N' TO WS-TIMEOUT-GIVEN
           MOVE SPACES TO WS-DATABASE-URL
           ACCEPT WS-DATABASE-URL FROM ENVIRONMENT 'DATABASE_URL'
           END-ACCEPT
           IF WS-DATABASE-URL = SPACES
               STRING 'postgres://postgres@localhost:5432/todos'
                      '?sslmode=disable'
                   DELIMITED BY SIZE INTO WS-DATABASE-URL
               END-STRING
           END-IF
           MOVE FUNCTION LENGTH(FUNCTION TRIM(WS-DATABASE-URL TRAILING))
             TO WS-URL-LENGTH

      *    THE SCHEME.
           EVALUATE TRUE
               WHEN WS-DATABASE-URL(1:11) = 'postgres://'
                   MOVE 12 TO WS-PART-START
               WHEN WS-DATABASE-URL(1:13) = 'postgresql://'
                   MOVE 14 TO WS-PART-START
               WHEN OTHER
                   MOVE SPACES TO DB-MESSAGE
                   STRING 'DATABASE_URL must start with postgres:// '
                          'or postgresql://'
                       DELIMITED BY SIZE INTO DB-MESSAGE
                   END-STRING
                   SET URL-IS-UNUSABLE TO TRUE
                   EXIT PARAGRAPH
           END-EVALUATE

      *    THE AUTHORITY, [USER[:PASSWORD]@]HOST[:PORT], RUNS UP TO THE
      *    FIRST "/" OR "?".
           MOVE WS-PART-START TO WS-SCAN
           PERFORM UNTIL WS-SCAN > WS-URL-LENGTH
                   OR WS-DATABASE-URL(WS-SCAN:1) = '/'
                   OR WS-DATABASE-URL(WS-SCAN:1) = '?'
               ADD 1 TO WS-SCAN
           END-PERFORM
           COMPUTE WS-AUTHORITY-END = WS-SCAN - 1

      *    USER AND PASSWORD COME BEFORE THE LAST "@".
           MOVE 0 TO WS-AT
           PERFORM VARYING WS-SCAN FROM WS-PART-START BY 1
                   UNTIL WS-SCAN > WS-AUTHORITY-END
               IF WS-DATABASE-URL(WS-SCAN:1) = '@'
                   MOVE WS-SCAN TO WS-AT
               END-IF
           END-PERFORM
           IF WS-AT > 0
               COMPUTE WS-USER-INFO-END = WS-AT - 1
               MOVE 0 TO WS-COLON
               PERFORM VARYING WS-SCAN FROM WS-PART-START BY 1
                       UNTIL WS-SCAN > WS-USER-INFO-END OR WS-COLON > 0
                   IF WS-DATABASE-URL(WS-SCAN:1) = ':'
                       MOVE WS-SCAN TO WS-COLON
                   END-IF
               END-PERFORM
               IF WS-COLON > 0
                   MOVE 'PGUSER' TO WS-ENV-NAME
                   COMPUTE WS-PART-END = WS-COLON - 1
                   PERFORM 1150-EXPORT-URL-PART
                   MOVE 'PGPASSWORD' TO WS-ENV-NAME
                   COMPUTE WS-PART-START = WS-COLON + 1
                   MOVE WS-USER-INFO-END TO WS-PART-END
                   PERFORM 1150-EXPORT-URL-PART
               ELSE
                   MOVE 'PGUSER' TO WS-ENV-NAME
                   MOVE WS-USER-INFO-END TO WS-PART-END
                   PERFORM 1150-EXPORT-URL-PART
               END-IF
               COMPUTE WS-PART-START = WS-AT + 1
           END-IF

      *    THE HOST, AND THE PORT AFTER ITS LAST ":". AN IPV6 ADDRESS
      *    IS WRITTEN IN BRACKETS, "[::1]:5432".
           MOVE WS-AUTHORITY-END TO WS-HOST-END
           MOVE 0 TO WS-COLON
           PERFORM VARYING WS-SCAN FROM WS-PART-START BY 1
                   UNTIL WS-SCAN > WS-AUTHORITY-END
               EVALUATE WS-DATABASE-URL(WS-SCAN:1)
                   WHEN ':'
                       MOVE WS-SCAN TO WS-COLON
                   WHEN ']'
                       MOVE 0 TO WS-COLON
               END-EVALUATE
           END-PERFORM
           IF WS-COLON > 0
               COMPUTE WS-HOST-END = WS-COLON - 1
           END-IF
           IF WS-HOST-END >= WS-PART-START
              AND WS-DATABASE-URL(WS-PART-START:1) = '['
              AND WS-DATABASE-URL(WS-HOST-END:1) = ']'
               ADD 1 TO WS-PART-START
               SUBTRACT 1 FROM WS-HOST-END
           END-IF
           MOVE 'PGHOST' TO WS-ENV-NAME
           MOVE WS-HOST-END TO WS-PART-END
           PERFORM 1150-EXPORT-URL-PART
           IF WS-COLON > 0
               MOVE 'PGPORT' TO WS-ENV-NAME
               COMPUTE WS-PART-START = WS-COLON + 1
               MOVE WS-AUTHORITY-END TO WS-PART-END
               PERFORM 1150-EXPORT-URL-PART
           END-IF

      *    THE DATABASE NAME, BETWEEN "/" AND "?".
           MOVE WS-AUTHORITY-END TO WS-PATH-END
           IF WS-AUTHORITY-END < WS-URL-LENGTH
              AND WS-DATABASE-URL(WS-AUTHORITY-END + 1:1) = '/'
               COMPUTE WS-PART-START = WS-AUTHORITY-END + 2
               MOVE WS-PART-START TO WS-SCAN
               PERFORM UNTIL WS-SCAN > WS-URL-LENGTH
                       OR WS-DATABASE-URL(WS-SCAN:1) = '?'
                   ADD 1 TO WS-SCAN
               END-PERFORM
               COMPUTE WS-PATH-END = WS-SCAN - 1
               MOVE 'PGDATABASE' TO WS-ENV-NAME
               MOVE WS-PATH-END TO WS-PART-END
               PERFORM 1150-EXPORT-URL-PART
           END-IF

      *    THE PARAMETERS AFTER "?", NAME=VALUE&NAME=VALUE.
           COMPUTE WS-PART-START = WS-PATH-END + 2
           PERFORM UNTIL WS-PART-START > WS-URL-LENGTH
                   OR URL-IS-UNUSABLE
               MOVE WS-PART-START TO WS-SCAN
               MOVE 0 TO WS-EQUALS
               PERFORM UNTIL WS-SCAN > WS-URL-LENGTH
                       OR WS-DATABASE-URL(WS-SCAN:1) = '&'
                   IF WS-DATABASE-URL(WS-SCAN:1) = '=' AND WS-EQUALS = 0
                       MOVE WS-SCAN TO WS-EQUALS
                   END-IF
                   ADD 1 TO WS-SCAN
               END-PERFORM
               PERFORM 1160-EXPORT-URL-PARAMETER
               COMPUTE WS-PART-START = WS-SCAN + 1
           END-PERFORM

      *    THE GO VERSION GAVE EACH CONNECTION ATTEMPT 3 SECONDS.
           IF NOT URL-SETS-CONNECT-TIMEOUT
               SET ENVIRONMENT 'PGCONNECT_TIMEOUT' TO '3'
           END-IF.

       1150-EXPORT-URL-PART.
      *    PERCENT-DECODE WS-DATABASE-URL(WS-PART-START..WS-PART-END)
      *    AND SET IT AS ENVIRONMENT VARIABLE WS-ENV-NAME. AN EMPTY
      *    PART LEAVES LIBPQ'S OWN DEFAULT IN PLACE.
           IF WS-PART-END < WS-PART-START
               EXIT PARAGRAPH
           END-IF
           MOVE 'DECODE' TO UW-FUNCTION
           COMPUTE UW-INPUT-LENGTH = WS-PART-END - WS-PART-START + 1
           MOVE WS-DATABASE-URL(WS-PART-START:UW-INPUT-LENGTH)
             TO UW-INPUT
           CALL 'URLPATH' USING URL-WORK
           SET ENVIRONMENT WS-ENV-NAME
                        TO UW-OUTPUT(1:UW-OUTPUT-LENGTH).

       1160-EXPORT-URL-PARAMETER.
      *    ONE NAME=VALUE PAIR, FROM WS-PART-START UP TO WS-SCAN.
           IF WS-SCAN = WS-PART-START
               EXIT PARAGRAPH
           END-IF
           IF WS-EQUALS = 0
               MOVE WS-SCAN TO WS-EQUALS
           END-IF
           IF WS-EQUALS = WS-PART-START
               MOVE 'DATABASE_URL has a parameter without a name'
                 TO DB-MESSAGE
               SET URL-IS-UNUSABLE TO TRUE
               EXIT PARAGRAPH
           END-IF
           MOVE SPACES TO WS-PARAMETER-NAME
           IF WS-EQUALS - WS-PART-START <= 24
               MOVE WS-DATABASE-URL(WS-PART-START:
                                    WS-EQUALS - WS-PART-START)
                 TO WS-PARAMETER-NAME
           END-IF
      *    SEARCH WALKS THE TABLE UNTIL A "WHEN" HOLDS, OR RUNS OFF
      *    THE END ("AT END").
           SET WS-PARAMETER-INDEX TO 1
           SEARCH WS-URL-PARAMETER
               AT END
                   MOVE SPACES TO DB-MESSAGE
                   STRING 'unsupported DATABASE_URL parameter: '
                          WS-DATABASE-URL(WS-PART-START:
                                          WS-EQUALS - WS-PART-START)
                       DELIMITED BY SIZE INTO DB-MESSAGE
                   END-STRING
                   SET URL-IS-UNUSABLE TO TRUE
               WHEN WS-PARAMETER-KEY(WS-PARAMETER-INDEX)
                    = WS-PARAMETER-NAME
                   MOVE WS-PARAMETER-ENV(WS-PARAMETER-INDEX)
                     TO WS-ENV-NAME
                   IF WS-ENV-NAME = 'PGCONNECT_TIMEOUT'
                       SET URL-SETS-CONNECT-TIMEOUT TO TRUE
                   END-IF
                   COMPUTE WS-PART-START = WS-EQUALS + 1
                   COMPUTE WS-PART-END = WS-SCAN - 1
                   PERFORM 1150-EXPORT-URL-PART
           END-SEARCH.

       1200-CONNECT-ONCE.
      *    WITH NO NAMES GIVEN, CONNECT USES THE PG* VARIABLES.
           EXEC SQL CONNECT END-EXEC
           IF SQLCODE = 0
               SET DB-CONNECTED TO TRUE
      *        LIBPQ PRINTS POSTGRESQL'S NOTICES ("RELATION TODOS
      *        ALREADY EXISTS, SKIPPING") TO THE LOG. ONLY WARNINGS AND
      *        WORSE ARE WORTH A LINE THERE.
               EXEC SQL SET client_min_messages TO WARNING END-EXEC
               EXEC SQL COMMIT WORK END-EXEC
           ELSE
               SET DB-DISCONNECTED TO TRUE
               MOVE SQLCODE TO WS-SQLCODE-SHOWN
               MOVE SPACES TO DB-MESSAGE
               STRING 'could not connect (SQLCODE '
                      FUNCTION TRIM(WS-SQLCODE-SHOWN)
                      ', SQLSTATE ' SQLSTATE ')'
                   DELIMITED BY SIZE INTO DB-MESSAGE
               END-STRING
           END-IF.

      *----------------------------------------------------------------*
      * THE SCHEMA: ONE TABLE, CREATED IF IT IS NOT THERE YET.         *
      *----------------------------------------------------------------*
       2000-MIGRATE.
           EXEC SQL
               CREATE TABLE IF NOT EXISTS todos (
                   id BIGSERIAL PRIMARY KEY,
                   title TEXT NOT NULL,
                   done BOOLEAN NOT NULL DEFAULT FALSE,
                   created_at TIMESTAMPTZ NOT NULL DEFAULT now()
               )
           END-EXEC
           IF SQLCODE < 0
               PERFORM 8000-SQL-FAILED
               EXIT PARAGRAPH
           END-IF
           PERFORM 7900-COMMIT-WORK.

      *----------------------------------------------------------------*
      * LISTING: A CURSOR WALKS THE ROWS IN ORDER, ONE FETCH PER TODO. *
      *----------------------------------------------------------------*
       3000-OPEN-LIST.
           PERFORM 7000-BEGIN-WORK
           IF DB-FAILED
               EXIT PARAGRAPH
           END-IF
           EXEC SQL
               DECLARE TODOCURS CURSOR FOR
                   SELECT id, title, done,
                          to_char(created_at AT TIME ZONE 'UTC',
                                  'YYYYMMDDHH24MISSUS'),
                          octet_length(title)
                     FROM todos
                    ORDER BY created_at, id
           END-EXEC
           EXEC SQL OPEN TODOCURS END-EXEC
           IF SQLCODE < 0
               PERFORM 8000-SQL-FAILED
           END-IF.

       3100-FETCH-NEXT-TODO.
           EXEC SQL
               FETCH TODOCURS
                INTO :HV-ID, :HV-TITLE, :HV-DONE, :HV-CREATED-AT,
                     :HV-TITLE-BYTES
           END-EXEC
           EVALUATE TRUE
               WHEN SQLCODE = 100
                   SET DB-END-OF-LIST TO TRUE
               WHEN SQLCODE < 0
                   PERFORM 8000-SQL-FAILED
               WHEN OTHER
                   PERFORM 7100-ROW-TO-RECORD
           END-EVALUATE.

       3200-CLOSE-LIST.
           EXEC SQL CLOSE TODOCURS END-EXEC
           IF SQLCODE < 0
               PERFORM 8000-SQL-FAILED
               EXIT PARAGRAPH
           END-IF
           PERFORM 7900-COMMIT-WORK.

      *----------------------------------------------------------------*
      * CREATING. POSTGRESQL FILLS IN THE ID, DONE AND CREATED_AT; THE *
      * SELECT READS THE NEW ROW BACK BY THE ID ITS SEQUENCE JUST      *
      * HANDED OUT (CURRVAL ONLY SEES THIS SESSION'S OWN INSERTS).     *
      *----------------------------------------------------------------*
       4000-CREATE-TODO.
           PERFORM 7000-BEGIN-WORK
           IF DB-FAILED
               EXIT PARAGRAPH
           END-IF
           MOVE TODO-TITLE-LENGTH TO HV-TITLE-LEN
           MOVE TODO-TITLE(1:TODO-TITLE-LENGTH) TO HV-TITLE-ARR
           EXEC SQL
               INSERT INTO todos (title) VALUES (:HV-TITLE)
           END-EXEC
           IF SQLCODE < 0
               PERFORM 8000-SQL-FAILED
               EXIT PARAGRAPH
           END-IF
           EXEC SQL
               SELECT id, title, done,
                      to_char(created_at AT TIME ZONE 'UTC',
                              'YYYYMMDDHH24MISSUS'),
                      octet_length(title)
                 INTO :HV-ID, :HV-TITLE, :HV-DONE, :HV-CREATED-AT,
                      :HV-TITLE-BYTES
                 FROM todos
                WHERE id = currval(pg_get_serial_sequence('todos',
                                                          'id'))
           END-EXEC
           IF SQLCODE NOT = 0
               PERFORM 8000-SQL-FAILED
               EXIT PARAGRAPH
           END-IF
           PERFORM 7900-COMMIT-WORK
           IF DB-OK
               PERFORM 7100-ROW-TO-RECORD
           END-IF.

      *----------------------------------------------------------------*
      * TOGGLING. AN UPDATE THAT TOUCHED NO ROW MEANS NO SUCH TODO.    *
      *----------------------------------------------------------------*
       5000-SET-DONE.
           PERFORM 7000-BEGIN-WORK
           IF DB-FAILED
               EXIT PARAGRAPH
           END-IF
           MOVE TODO-ID TO HV-ID
           IF TODO-IS-DONE
               MOVE 'true' TO HV-DONE
           ELSE
               MOVE 'false' TO HV-DONE
           END-IF
           EXEC SQL
               UPDATE todos SET done = :HV-DONE WHERE id = :HV-ID
           END-EXEC
           IF SQLCODE < 0
               PERFORM 8000-SQL-FAILED
               EXIT PARAGRAPH
           END-IF
           IF SQLERRD(3) = 0
               PERFORM 7800-ROLLBACK-WORK
               SET DB-NOT-FOUND TO TRUE
               EXIT PARAGRAPH
           END-IF
           EXEC SQL
               SELECT id, title, done,
                      to_char(created_at AT TIME ZONE 'UTC',
                              'YYYYMMDDHH24MISSUS'),
                      octet_length(title)
                 INTO :HV-ID, :HV-TITLE, :HV-DONE, :HV-CREATED-AT,
                      :HV-TITLE-BYTES
                 FROM todos
                WHERE id = :HV-ID
           END-EXEC
           IF SQLCODE NOT = 0
               PERFORM 8000-SQL-FAILED
               EXIT PARAGRAPH
           END-IF
           PERFORM 7900-COMMIT-WORK
           IF DB-OK
               PERFORM 7100-ROW-TO-RECORD
           END-IF.

      *----------------------------------------------------------------*
      * DELETING.                                                      *
      *----------------------------------------------------------------*
       6000-DELETE-TODO.
           PERFORM 7000-BEGIN-WORK
           IF DB-FAILED
               EXIT PARAGRAPH
           END-IF
           MOVE TODO-ID TO HV-ID
           EXEC SQL
               DELETE FROM todos WHERE id = :HV-ID
           END-EXEC
           IF SQLCODE < 0
               PERFORM 8000-SQL-FAILED
               EXIT PARAGRAPH
           END-IF
           IF SQLERRD(3) = 0
               PERFORM 7800-ROLLBACK-WORK
               SET DB-NOT-FOUND TO TRUE
               EXIT PARAGRAPH
           END-IF
           PERFORM 7900-COMMIT-WORK.

      *----------------------------------------------------------------*
      * UNITS OF WORK.                                                 *
      *----------------------------------------------------------------*
       7000-BEGIN-WORK.
      *    OCESQL ALWAYS KEEPS A TRANSACTION OPEN: IT STARTS THE NEXT
      *    ONE THE MOMENT THE LAST ONE COMMITS. THAT TRANSACTION MAY BE
      *    MINUTES OLD BY NOW, AND POSTGRESQL'S NOW() (THE DEFAULT FOR
      *    CREATED_AT) IS THE TIME A TRANSACTION STARTED. ENDING IT
      *    HERE GIVES THIS REQUEST A FRESH ONE. IT DOUBLES AS A CHECK
      *    THAT THE CONNECTION IS ALIVE: IF POSTGRESQL RESTARTED, THE
      *    ROLLBACK FAILS AND WE CONNECT AGAIN, ONCE.
           EXEC SQL ROLLBACK WORK END-EXEC
           IF SQLCODE < 0
               EXEC SQL DISCONNECT ALL END-EXEC
               SET DB-DISCONNECTED TO TRUE
               PERFORM 1200-CONNECT-ONCE
               IF DB-DISCONNECTED
                   SET DB-FAILED TO TRUE
               END-IF
           END-IF.

       7100-ROW-TO-RECORD.
      *    THE API ONLY STORES TITLES OF AT MOST 200 CHARACTERS, BUT A
      *    ROW WRITTEN BY SOMETHING ELSE COULD HOLD MORE THAN FITS
      *    HERE. SAY SO RATHER THAN SEND IT CUT SHORT.
           IF HV-TITLE-BYTES > LENGTH OF HV-TITLE-ARR
               MOVE HV-ID TO WS-ID-SHOWN
               MOVE SPACES TO DB-MESSAGE
               STRING 'the title of todo ' FUNCTION TRIM(WS-ID-SHOWN)
                      ' is longer than 800 bytes'
                   DELIMITED BY SIZE INTO DB-MESSAGE
               END-STRING
               PERFORM 7800-ROLLBACK-WORK
               SET DB-FAILED TO TRUE
               EXIT PARAGRAPH
           END-IF
           MOVE HV-ID TO TODO-ID
           MOVE HV-TITLE-LEN TO TODO-TITLE-LENGTH
           MOVE HV-TITLE-ARR TO TODO-TITLE
           IF HV-DONE(1:1) = 't'
               SET TODO-IS-DONE TO TRUE
           ELSE
               SET TODO-IS-OPEN TO TRUE
           END-IF
           MOVE HV-CREATED-AT TO TODO-CREATED-AT.

       7800-ROLLBACK-WORK.
           EXEC SQL ROLLBACK WORK END-EXEC.

       7900-COMMIT-WORK.
           EXEC SQL COMMIT WORK END-EXEC
           IF SQLCODE < 0
               PERFORM 8000-SQL-FAILED
           END-IF.

       8000-SQL-FAILED.
      *    KEEP THE REASON FOR THE LOG, THEN UNDO THE UNIT OF WORK.
           MOVE SQLCODE TO WS-SQLCODE-SHOWN
           MOVE SPACES TO DB-MESSAGE
           IF SQLERRML > 0 AND SQLERRML <= 70
               STRING 'SQLSTATE ' SQLSTATE ': '
                      SQLERRMC(1:SQLERRML)
                   DELIMITED BY SIZE INTO DB-MESSAGE
               END-STRING
           ELSE
               STRING 'SQLSTATE ' SQLSTATE ' (SQLCODE '
                      FUNCTION TRIM(WS-SQLCODE-SHOWN) ')'
                   DELIMITED BY SIZE INTO DB-MESSAGE
               END-STRING
           END-IF
           PERFORM 7800-ROLLBACK-WORK
           SET DB-FAILED TO TRUE.
