      *================================================================*
      * JSONOUT - ONE REQUEST TO JSONTODO, WHICH WRITES TODOS AS JSON  *
      * INTO THE RESPONSE BODY.                                        *
      *================================================================*
       01  JSON-OUT.
           05  JO-FUNCTION             PIC X(5).
      *        "[": START A LIST.
               88  JO-START-LIST       VALUE 'START'.
      *        ONE TODO IN THE LIST, WITH A "," BEFORE ALL BUT THE
      *        FIRST.
               88  JO-ADD-TO-LIST      VALUE 'ITEM'.
      *        "]" AND A NEWLINE: END THE LIST.
               88  JO-END-LIST         VALUE 'END'.
      *        ONE TODO ON ITS OWN, AND A NEWLINE.
               88  JO-SINGLE-TODO      VALUE 'ONE'.
           05  JO-ITEMS-WRITTEN        BINARY-LONG.
           05  JO-OUTCOME              PIC X.
               88  JO-FITS             VALUE 'Y'.
               88  JO-BODY-FULL        VALUE 'N'.
