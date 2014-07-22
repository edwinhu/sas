 /*    name: parse-sysparm.sas
description: parse the text in option sysparm into macro variables
    purpose: support batch processing command-line parameter passing
;/* testing in program ****** **
options source2;%* for put _global_;
options sysparm = 'a=1;b=2;d=4';
;/***** ********************* */
 
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