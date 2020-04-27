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
        lib=USER,
        merged=,
        idvar=permno,
        datevar=date,
        num_vars=,
        char_vars=,
        sort_statement=&idvar. &datevar.);
data _ncols;
set _null_;
retain &num_vars. .;
run;
%if %sysevalf(%superq(char_vars)^=,boolean) %then %do;
data _ccols;
set _null_;
retain &char_vars. '';
run;
%end;
proc sql noprint;
    select a.length
    into :nlen separated by ' '
    from dictionary.columns a
    inner join
    dictionary.columns b
    on upcase(a.name) = upcase(b.name)
    where upcase(a.libname)=upcase("&lib.")
    and upcase(a.memname)=upcase("&b.")
    and upcase(b.libname)=upcase("&lib.")
    and upcase(b.memname)="_NCOLS"
    ;
    %if %sysevalf(%superq(char_vars)^=,boolean) %then %do;
    select a.length
    into :clen separated by ' '
    from dictionary.columns a
    inner join
    dictionary.columns b
    on upcase(a.name) = upcase(b.name)
    where upcase(a.libname)=upcase("&lib.")
    and upcase(a.memname)=upcase("&b.")
    and upcase(b.libname)=upcase("&lib.")
    and upcase(b.memname)="_CCOLS"
    %end;
    ;
quit; 
data &merged.;
    length 
        %local i next_name;
        %do i=1 %to %sysfunc(countw(&num_vars.));
            %let next_name = %scan(&num_vars., &i);
            %let next_len = %scan(&nlen., &i);
            &next_name._ &next_len.
        %end;
        %if %sysevalf(%superq(char_vars)^=,boolean) %then %do;
        %do i=1 %to %sysfunc(countw(&char_vars.));
            %let next_name = %scan(&char_vars., &i);
            %let next_len = %scan(&clen., &i);
            &next_name._ $ &next_len.
        %end;%end;;
    retain
        %local i next_name;
        %do i=1 %to %sysfunc(countw(&num_vars.));
            %let next_name = %scan(&num_vars., &i);
            &next_name._ .
        %end;
        %if %sysevalf(%superq(char_vars)^=,boolean) %then %do;
        %do i=1 %to %sysfunc(countw(&char_vars.));
                %let next_name = %scan(&char_vars., &i);
                &next_name._ ''
        %end;%end;;
    set &b.(in=b keep=&idvar. &datevar. &num_vars. &char_vars.)
        &a.(in=a);
    by &sort_statement.;
    if first.&idvar. then do;
        %do i=1 %to %sysfunc(countw(&num_vars.));
            %let next_name = %scan(&num_vars., &i);
            &next_name._=.;
        %end;
    %if %sysevalf(%superq(char_vars)^=,boolean) %then %do;
	%do i=1 %to %sysfunc(countw(&char_vars.));
            %let next_name = %scan(&char_vars., &i);
            &next_name._='';
        %end;
    %end;
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
