/*
Author: Edwin Hu
Date: 2019-02-02

# MERGE_ASOF #

## Summary ##
Does an as-of or "window" merge

## Variables ##
- a: dataset a
- b: dataset b
- merged: output merged dataset
- idvar: firm identifier (permno)
- datevar: date variable to use (date)
- num_vars: numeric variables from b to merge in
- char_vars: character variables from b to merge in

## Usage ##
```
%INCLUDE "~/git/sas/MERGE_ASOF.sas";
%MERGE_ASOF(a=,b=,
    merged=,
    num_vars=);
```
*/
%MACRO MERGE_ASOF(a=,b=,
    merged=,
    idvar=permno,
    datevar=date,
    num_vars=,
    char_vars=);
    proc sort data=&a.;
        by &idvar. &datevar.;
    proc sort data=&b.;
        by &idvar. &datevar.;        
    data &merged.;
        retain
            %local i next_name;
        %do i=1 %to %sysfunc(countw(&num_vars. &char_vars.));
            %let next_name = %scan(&num_vars. &char_vars., &i);
            &next_name._
                %end;;
        set &b.(in=b keep=&idvar. &datevar. &num_vars. &char_vars.)
            &a.(in=a);
        by &idvar. &datevar.;
        if first.&idvar. then do;
            %do i=1 %to %sysfunc(countw(&num_vars.));
                %let next_name = %scan(&num_vars., &i);
                &next_name._=.;
                %end;
            %if %sysevalf(%superq(char_vars)=,boolean) %then %do;%end;
            %else %do;
                %do i=1 %to %sysfunc(countw(&char_vars.));
                    %let next_name = %scan(&char_vars., &i);
                        &next_name._='';
                %end;%end;
        end;    
        %do i=1 %to %sysfunc(countw(&num_vars. &char_vars.));
            %let next_name = %scan(&num_vars. &char_vars., &i);
            if not missing(&next_name.) then &next_name._=&next_name.;
            drop &next_name.;
            rename &next_name._=&next_name.;
        %end;
        format &datevar. yymmdd10.;
        if a then output;
    run;
    %MEND;
%MERGE_ASOF(a=,b=,
    merged=,
    num_vars=);
