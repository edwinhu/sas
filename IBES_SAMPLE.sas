/*
Author: Edwin Hu
Date: 2013-05-24

# IBES_SAMPLE #

## Summary ##
Gets the median analyst forecasts from IBES

## Variables ##
- itickers: dataset with IBES ticker list (iclink)
- suffix: which ibes files to use (epsus)
- det_filter: detail file filters
- act_filter: actual file filters
- ibes_var: IBES variables to keep
- debug: debug mode

## Usage ##
```
%IMPORT "~/git/sas/IBES_SAMPLE.sas";

%IBES_SAMPLE(
             itickers=iclink,
             suffix=epsus,
             begindate=,
             enddate=,
             det_filter=measure='EPS' and fpi in ('6','7') and &begindate<=fpedats<=&enddate,
             act_filter=missing(repdats)=0 and missing(anndats)=0 and 0<intck('day',anndats,repdats)<=90,
             ibes_vars=ticker value fpedats anndats revdats measure fpi estimator analys pdf usfirm,
             debug=n
             );
```
 */

%MACRO IBES_SAMPLE(
                itickers=iclink,
                suffix=epsus,
                begindate=,
                enddate=,
                det_filter=and measure='EPS' and fpi in ('6','7'),
                act_filter=missing(repdats)=0 and missing(anndats)=0 and 0<intck('day',anndats,repdats)<=90,
                ibes_vars=ticker value fpedats anndats revdats measure fpi estimator analys pdf usfirm,
                debug=n
                );

    %local dsid num rc;
    %local oldoptions errors;
    %let oldoptions=%sysfunc(getoption(mprint)) %sysfunc(getoption(notes))
                    %sysfunc(getoption(source));
    %let errors=%sysfunc(getoption(errors));
    %if %substr(%lowcase(&debug),1,1) = n %then %do;
    options nonotes nomprint nosource errors=0;
    %end;

    %macro print(str);
        %put; %put &str.; %put;
    %mend;

    %print(### Step 1. Sample detail file: ibes.detu_&suffix. );
    proc sql;
        create table ibes (drop=measure fpi) as
            select *
            from ibes.detu_&suffix.
                    (
                    where=(fpedats between "&begindate."d and "&enddate."d &det_filter.)
                    keep=&ibes_vars
                    ) as a, /* det_filter and ibes_vars are specified*/
                 &itickers as b                                              /* prior to invoking IBES_SAMPLE*/
        where a.ticker=b.ticker
        order by a.ticker, fpedats, estimator, analys, anndats, revdats;
    quit;

    /*Select the last estimate for a firm within broker-analyst group*/
    data ibes; set ibes;
        by ticker fpedats estimator analys;
        if last.analys;
    run;

    %print(### Step 2. Merge unadjusted estimates with unadjusted actuals ibes.actu_&suffix. );
    /*How many estimates are reported on primary/diluted basis? */
    proc sql;
        create table ibes as
            select a.*, sum(pdf='P') as p_count, sum(pdf='D') as d_count
            from ibes as a
        group by ticker, fpedats
        ;

    /* a. Link unadjusted estimates with unadjusted actuals and CRSP permnos                                */
    /* b. Adjust report and estimate dates to be CRSP trading days                                          */
        create table ibes1 (where=(&act_filter)) as
            select a.*,
            b.anndats as repdats,
            b.value as act,
            c.permno,
            case when weekday(a.anndats)=1 then intnx('day',a.anndats,-2)                  /*if sunday move back by 2 days;*/
                 when weekday(a.anndats)=7 then intnx('day',a.anndats,-1)
                 else a.anndats   /*if saturday move back by 1 day*/
            end as estdats1,
            case when weekday(b.anndats)=1 then intnx('day',b.anndats,1)                  /*if sunday move forward by 1 day  */
                 when weekday(b.anndats)=7 then intnx('day',b.anndats,2)
                 else b.anndats   /*if saturday move forward by 2 days*/
            end as repdats1
        from ibes as a, ibes.actu_&suffix. as b, iclink as c
        where a.ticker=b.ticker
        and a.fpedats=b.pends
        and a.usfirm=b.usfirm
        and b.pdicity='QTR'
        and b.measure='EPS'
        and a.ticker=c.ticker
        and c.score in (0,1,2)
        ;

    /*  Making sure that estimates and actuals are on the same basis */
    /*  1. retrieve CRSP cumulative adjustment factor for IBES report and estimate dates                                           */
        create table adjfactor
            as select distinct a.*
            from crsp.dsf (keep=permno date cfacshr) as a, ibes1 as b
            where a.permno=b.permno and (a.date=b.estdats1 or a.date=b.repdats1)
        ;

    /*  2.if adjustment factors are not the same, adjust the estimate to be on the same basis with the actual   */
        create table ibes1
            as select distinct a.*, b.est_factor, c.rep_factor,
                case when (b.est_factor ne c.rep_factor)
                    and missing(b.est_factor)=0
                    and missing(c.rep_factor)=0
                then (rep_factor/est_factor)*value
                else value
                end as new_value
            from ibes1 as a,
                adjfactor (rename=(cfacshr=est_factor)) as b,
                adjfactor (rename=(cfacshr=rep_factor)) as c
                where (a.permno=b.permno and a.estdats1=b.date) and
                      (a.permno=c.permno and a.repdats1=c.date)
        ;
    quit;

    /* Make sure the last observation per analyst is included */
    proc sort data=ibes1;
        by ticker fpedats estimator analys anndats revdats;
    run;

    data ibes1;
        set ibes1;
        by ticker fpedats estimator analys;
        if last.analys;
    run;

    %print(### Step 3. Compute the median forecast based on estimates in the 90 days prior to the report date );
    proc means data=ibes1 noprint;
        by ticker fpedats;
        var /*value*/ new_value;                         /* new_value is the estimate appropriately adjusted         */
        output out= medest (drop=_type_ _freq_)         /* to be on the same basis with the actual reported earnings */
        median=medest n=numest;
    run;

    /* Merge median estimates with ancillary information on permno, actuals and report dates                              */
    /* Determine whether most analysts are reporting estimates on primary or diluted basis                                */
    /* following the methodology outlined in Livnat and Mendenhall (2006)                                                 */
    proc sql;
        create table medest as
            select distinct a.*, b.repdats, b.act, b.permno,
            case when p_count>d_count then 'P'
                 when p_count<=d_count then 'D'
            end as basis
            from medest as a
            left join ibes1 as b
            on a.ticker=b.ticker
            and a.fpedats=b.fpedats;
    quit;

    %if %substr(%lowcase(&debug),1,1) = n %then %do;
        %print(### Step 4. Deleting temporary datasets );
        proc datasets nolist;
        delete ibes ibes1
            ;
        quit;
    %end;

    %print(### DONE );
    options errors=&errors &oldoptions;
%MEND;
