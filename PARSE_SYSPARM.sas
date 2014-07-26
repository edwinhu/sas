/*
Author: Edwin Hu
Date: 2013-05-24

# PARSE_SYSPARM #

## Summary ##
Parses &sysparm. macro variable to make it easier to pass variables to SAS programs.

`sas myprog.sas -sysparm a=1;b=2;c=3;`

will parse to something like

```
%let a = 1;
%let b = 2;
%let c = 3;
```

## Usage ##
```
%IMPORT "~/git/sas/PARSE_SYSPARM.sas";

```
*/

data _null_;
     attrib Stmnt   length = $132
            Testing length =    4;
     retain Testing %eval(0
            or "%sysfunc(getoption(Source2))"
                               eq "SOURCE2"
            or "%sysfunc(getoption(Verbose))"
                               eq "VERBOSE"  );
if "&SysParm." ne "" then do;
   putlog "SysParm: &SysParm.";
   do I = 1 to %*number of equal-signs;
          length(compress("&SysParm",'=','k'));
      Stmnt= catx(' ' %*separated by space;
                 ,'%let '
                 ,scan("&SysParm.",I,';')
                 ,';');
      if   Testing then putlog Stmnt=;
      call execute(cat('%nrstr(',Stmnt,')'));
      end; %*do I;
   if Testing then
      call execute('%nrstr(%put _global_;)');
   end; %*if "&SysParm." ne "";
stop;
run;    *calls execute here;
