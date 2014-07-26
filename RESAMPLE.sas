/*
Author: Edwin Hu
Date: 2013-05-24

# RESAMPLE #

## Summary ##
Resample and forward-fill data from low to high frequency

Commonly used to sample low frequency COMPUSTAT data before merging
with higher frequency CRSP data.

## Variables ##
- lib: input dataset library
- dsetin: input dataset
- dsetout: output (resampled) dataset
- datevar: date variable to resample
- idvar: group by id variable
- infreq: input frequency
- outfreq: output (higher) frequency
- alignment: date alignment (E,S,B)
- debug: keep or delete temporary datasets

## Usage ##
```
%IMPORT "~/git/sas/RESAMPLE.sas";

%RESAMPLE(lib=sashelp, dsetin=citiyr, outfreq=monthly, idvar=, datevar=date);

```
 */
%macro RESAMPLE(lib = USER,
                dsetin = &syslast.,
                dsetout = ,
                datevar = datadate,
                idvar = gvkey,
                infreq = yearly,
                outfreq = monthly,
                alignment = E,
                debug = n
                );

    %if %length(&dsetout) < 1 %then %do;
        %let dsetout = &dsetin._&outfreq. ;
    %end;

    %let infreq = "&infreq.";
    %let outfreq = "&outfreq.";
    %let alignment = "&alignment.";

    proc sort data=&lib..&dsetin. out=&lib.._RESAMPLE_SORTED;
        by &idvar. &datevar.;
    proc printto log=junk;
    proc expand data=&lib.._RESAMPLE_SORTED out=&lib.._RESAMPLE_DIFF(drop=TIME);
        by &idvar.;
        convert &datevar. = &datevar._next / transform = (lead 1);
    proc printto;run;
    data &lib.._RESAMPLE_DIFF;
        set &lib.._RESAMPLE_DIFF;
        &datevar._diff = min(
                intck(&outfreq.,&datevar.,intnx(&infreq.,&datevar.,1,'S')),
                intck(&outfreq.,&datevar.,intnx(&outfreq.,&datevar._next,0,'E'))
                );
                * Example: yearly -> monthly
                * compute the number of months that this data remains valid;
        label &datevar._next='Next date' &datevar._diff='Number of periods to next date';
    run;

    data &lib..&dsetout.;
    retain &idvar. date;
    set &lib.._RESAMPLE_DIFF;
    do i = 1 to &datevar._diff;
        date = intnx(&outfreq.,&datevar.,i,&alignment.);
        output;
    end;
    format date yymmdd10.;
    drop i &datevar._next &datevar._diff;
    label date='Resampled date';
    run;

    %if %SUBSTR(%LOWCASE(&debug),1,1) = n %then %do;
    proc datasets lib=&lib. nolist;
        delete _RESAMPLE_: ;
    run;quit;
    %end;

%mend RESAMPLE;
