﻿       IDENTIFICATION DIVISION.
       PROGRAM-ID. test5_disappear.        
       ENVIRONMENT DIVISION.        
       DATA DIVISION.  
       PROCEDURE DIVISION. 
           EXEC SQL AT CONN1 SAVEPOINT SP1 END-EXEC.
           EXEC SQL AT CONN1
               SELECT SUM(FLD2) INTO :T2 FROM TAB2
           END-EXEC.       
      * this instruction disappear when the file is parsed and reparsed     
           DISPLAY 'HELLO WORLD '
           EXEC SQL AT CONN1 ROLLBACK TO SAVEPOINT SP1 END-EXEC.
           