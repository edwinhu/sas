
%include '~/git/sasmacros/PARSE-SYSPARM.sas';

PROC EXPORT DATA=&infile.
            FILE="&outfile."
            DBMS=STATA REPLACE;
RUN;