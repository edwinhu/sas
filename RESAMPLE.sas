****************(1) MODULE-BUILDING STEP********************************;
/*******************READ ME*********************************************
* - Macro to resample and forward-fill data from low to high frequency -
*
* SAS VERSION:    9.4.0
* DATE:           2014-02-21
* AUTHOR:         eddyhu at the gmails
*
****************END OF READ ME******************************************/

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

   /*****************************************************************
   *  MACRO:      RESAMPLE()
   *  GOAL:       Resample and forward-fill data from low to high frequency
   *  PARAMETERS: lib     = SAS library (default USER)
   *              dsetin      = SAS dataset to resample (default &syslast)
   *              dsetout     = output resampled dataset (default &dsetin._resampled)
   *              datevar     = date variable (default COMPUSTAT datadate)
   *              idvar       = id variable (default COMPUSTAT gvkey)
   *              infreq      = input dataset frequency (default yearly)
   *              outfreq     = output dataset frequency (default month)
   *              alignment   = output date alignment (default END)
   *              debug       = if y then keep temporary files
   *****************************************************************/

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

****************(2) TESTING STEP****************************************;
%macro test(debug=n);
%if %SUBSTR(%LOWCASE(&debug),1,1) = y %then %do;
    * Resample the yearly city data;
    %resample(lib=sashelp, dsetin=citiyr, outfreq=monthly, idvar=, datevar=date);
    * Shift the date forward by 6 months;
    data sashelp.citiyr_monthly;
        set sashelp.citiyr_monthly;
        retain date_avail;
        date_avail = intnx('monthly',date,6,'e');    
        format date_avail yymmdd10.;
        label date_avail='Date Available';
    run;
%end;
%mend test;

%test(debug=n);

*'; *"; *); */; %mend; run;