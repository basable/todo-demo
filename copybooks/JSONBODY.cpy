      *================================================================*
      * JSONBODY - WHAT JSONREAD FOUND IN A REQUEST BODY.              *
      *                                                                *
      * POST /API/TODOS SENDS {"title": "..."} AND                     *
      * PATCH /API/TODOS/{ID} SENDS {"done": true}. THE CALLER SAYS    *
      * WHICH FIELD IT WANTS; EVERY OTHER FIELD IS SKIPPED.            *
      *================================================================*
       01  JSON-BODY.
           05  JB-WANTED               PIC X.
               88  JB-WANTS-TITLE      VALUE 'T'.
               88  JB-WANTS-DONE       VALUE 'D'.
           05  JB-OUTCOME              PIC X.
               88  JB-IS-VALID         VALUE 'V'.
      *        NOT JSON, NOT AN OBJECT, OR A FIELD OF THE WRONG TYPE.
               88  JB-IS-INVALID       VALUE 'X'.
      *    "done": TRUE, FALSE, OR NEITHER (MISSING, OR NULL).
           05  JB-DONE                 PIC X.
               88  JB-DONE-TRUE        VALUE 'T'.
               88  JB-DONE-FALSE       VALUE 'F'.
               88  JB-DONE-MISSING     VALUE ' '.
      *    "title", DECODED TO UTF-8 BUT NOT YET TRIMMED. 3 MIB: EVERY
      *    BYTE OF A 1 MIB BODY MAY TURN INTO A 3-BYTE REPLACEMENT
      *    CHARACTER, AND IT MUST STILL FIT.
           05  JB-TITLE-LENGTH         BINARY-LONG.
           05  JB-TITLE                PIC X(3145744).
