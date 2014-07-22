%MACRO SIGNON;
        SIGNOFF;
        %INCLUDE "~/.ssh/wrds_pass.sas";
        %LET wrds=wrds.wharton.upenn.edu 4016;
        options comamid=TCP remote=WRDS;
        signon username="eddyhu" password="&wrds_pass";
%MEND;
