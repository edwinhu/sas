/*
Author: Edwin Hu
Date: 2015-08-03

# PARFOR #

## Summary ##
A parallel FOR loop SAS Macro

If you have huge files it is often better to use Split-Apply-Combine
processing. For example processing daily trades by year can be done
by splitting the dataset into yearly datasets and doing the processing
in a parallel FOR loop.

This Macro spawns multiple SAS processes in the background to make
parallel processing easy. The Macro waits until all processes are
complete before returning control to the user.

## WARNING ##

There is no built-in resource control (RAM/CPU) so make sure to
test your code on one group at a time before spawning too many
concurrent processes!

*/

OPTIONS SASCMD='sas -nosyntaxcheck' AUTOSIGNON;
%LET TASKLIST = ;
%MACRO PARFOR;
    %DO yyyy=1999 %TO 2012;
        %LET TASKLIST = &TASKLIST. p&yyyy.;
        %SYSLPUT _ALL_ / REMOTE=p&yyyy.;
        RSUBMIT p&yyyy. WAIT=N PERSIST=NO;
        /* INSERT YOUR CODE HERE */
        ENDRSUBMIT;
   %END;
%MEND;
%PARFOR;
WAITFOR _ALL_ &TASKLIST.;
%PUT DONE;
