/*
Author: Edwin Hu
Date: 2013-05-24
Last Update: 2019-01-18

# EVENT_MACROS #

## Summary ##
A collection of event study macros adapted from WRDS.

## Usage ##
```
%IMPORT "~/git/sas/EVENT_MACROS.sas";

%EVENT_SETUP(pref=,
    crsp_lib=crspm,
    frequency=d,
    date_var=event_date,
    id_var=permno,
    model=ffm,
    ret_var=retx,
    est_per=252, gap_win=30,
    beg_win=-30, end_win=120
    );

%EVENT_EXPAND(lib=user, debug = n);

%EVENT_STATS(prefix = ,
    dsetin = ,
    group = ,
    filter = and shrcd in (10,11) and exchcd in (1,2,3),
    debug= = n
    );

```
*/

%MACRO EVENT_SETUP(pref=,
    crsp_lib=crspm,
    frequency=d,
    date_var=date,
    id_var=permno,
    model=ffm,
    ret_var=retx,
    est_per=252, gap_win=30,
    beg_win=-30, end_win=60
    );
    /* Assign as global  */
    %global prefix crsp s datevar idvar retvar estper gap beg end evtwin factors abret newvars;
    %let prefix=&pref.;
    %let crsp=&crsp_lib.;
    %let s=&frequency.;
    %let datevar=&date_var.;
    %let idvar=&id_var.;
    %let retvar=&ret_var.;
    %let estper=&est_per.;
    %let gap=&gap_win.;
    %let beg=&beg_win.;
    %let end=&end_win.;
    %let evtwin=%eval(&end-&beg+1); *length of event window in trading days;
    /*depending on the model, define the model for abnormal returns*/
    %if %lowcase(&model)=madj %then %do;
        %let factors=;
        %let abret=&retvar.-vwretd;
        %let newvars=(intercept=alpha);
    %end;%else
    %if %lowcase(&model)=m %then %do;
        %let factors=vwretd;
        %let abret=&retvar.-alpha-beta*vwretd;
        %let newvars=(intercept=alpha vwretd=beta);
    %end;%else
    %if %lowcase(&model)=ff %then %do;
        %let factors=vwretd smb hml;
        %let abret=&retvar.-alpha-beta*vwretd-sminb*smb-hminl*hml;
        %let newvars=(intercept=alpha vwretd=beta smb=sminb hml=hminl);
    %end;%else
    %if %lowcase(&model)=ffm %then %do;
        %let factors=vwretd smb hml mom;
        %let abret=&retvar.-alpha-beta*vwretd-sminb*smb-hminl*hml-wminl*mom;
        %let newvars=(intercept=alpha vwretd=beta smb=sminb hml=hminl mom=wminl);
    %end;
    %put;%put ### EVENT_SETUP DONE! ###;
%MEND EVENT_SETUP;

%MACRO EVENT_EXPAND(lib=user,
    debug=n
    );

/*****************************************************************
*  MACRO:      EVENT_EXPAND()
*  GOAL:       Expand an event file into an (t, event_id) ordered file
*****************************************************************/

    %put; %put ### STEP 1. CREATING TRADING CALENDAR...;
    data _caldates;
        merge &crsp..&s.siy (keep=caldt rename=(caldt=estper_beg))
        &crsp..&s.siy (keep=caldt firstobs=%eval(&estper) rename=(caldt=estper_end))
        &crsp..&s.siy (keep=caldt firstobs=%eval(&estper+&gap+1) rename=(caldt=evtwin_beg))
        &crsp..&s.siy (keep=caldt firstobs=%eval(&estper+&gap-&beg+1) rename=(caldt=edate))
        &crsp..&s.siy (keep=caldt firstobs=%eval(&estper+&gap+&evtwin) rename=(caldt=evtwin_end));
        format estper_beg estper_end evtwin_beg edate evtwin_end yymmdd10.;
        if nmiss(estper_beg,estper_end,evtwin_beg,evtwin_end,edate)=0;
        time+1;
    run;
    proc sort data=_caldates;
        by edate;
    run;
    %put;%put ### DONE! ###;

    /*If primary identifier is Cusip, then link in permno*/
    %if %lowcase(&idvar.)=cusip %then %do;
    proc sql;
        create view  _link
        as select permno, ncusip,
        min(namedt) as fdate format=yymmdd10., max(nameendt) as ldate format=yymmdd10.
        from &crsp..&s.senames
        group by permno, ncusip;
        create table _temp
        as select distinct b.permno, a.*
        from &prefix._events a left join _link b
        on substr(a.cusip,1,6)=substr(b.ncusip,1,6) and b.fdate<=a.&datevar.<=b.ldate
        order by a.&datevar.;
    quit;
    %end;
    /*pre-sort the input dataset in case it is not sorted yet*/
    %else %do;
    proc sort data=&prefix._events out=_temp;
        by &datevar.;
    run;
    %end;
    data _temp;
        set _temp;
        event_id=_n_;
        %if %lowcase("&s.") eq "m" %then %do;
            edate = intnx("MONTH",&datevar.,0,'E');
        %end;
        %else %do;
            edate=&datevar.;
        %end;
        format edate yymmdd10.;
    run;    

    /*Event dates should already be trading calendar days    */
    /*Merge in relevant dates from the trading calendar      */
    %MACRO MERGE;
        %let num_vars = estper_beg estper_end evtwin_beg evtwin_end time;
        data _temp2;
            retain
                %local i next_name;
            %do i=1 %to %sysfunc(countw(&num_vars.));
                %let next_name = %scan(&num_vars., &i);
                &next_name._
                    %end;;
                set _caldates(in=b) _temp(in=a);
                by edate;
                %local i next_name;
                %do i=1 %to %sysfunc(countw(&num_vars.));
                    %let next_name = %scan(&num_vars., &i);
                    if not missing(&next_name.) then &next_name._=&next_name.;
                    drop &next_name.;
                    rename &next_name._=&next_name.;
                    %end;
                format estper: evtwin: yymmdd10.;
                if a then output;
                drop edate;
        run;
    %MEND;%MERGE;

    %put ; %put ### STEP 2. PREPARING BENCHMARK FACTORS... ;
    data factors_d/view=factors_d;
        set ff.factors_daily;
    run;
    data factors_m/view=factors_m;
        set ff.factors_monthly(drop=date);
        date=dateff;
        format date yymmddn8.;
    run;
    
    proc sql;create table _factors
        as select a.caldt as date, a.vwretd, b.smb, b.hml, b.umd as mom
        from &crsp..&s.siy (keep=caldt vwretd) a left join factors_&s. b
        on a.caldt=b.date;
    quit;
    %put ### DONE! ###;

    proc sort data=_temp2;
        by permno estper_beg evtwin_end;
    run;
    %put; %put ### STEP 3. RETRIEVING RETURNS DATA FROM CRSP...;

    proc sql;
        create table _temp_expand (drop=time)
            as select
                (c.time-b.time) as t,
                b.event_id,
                b.*,a.*
            from &crsp..&s.sf as a, _temp2 as b, _caldates as c
            where a.date between b.estper_beg and b.evtwin_end
            and a.permno = b.permno
            and a.date = c.edate
            group by b.event_id
            ;
    quit;
    proc sort data=_temp_expand;
        by event_id t;
    run;

    %put ### DONE! ###;
    /*
    NOTE: Table USER._TEMP_EXPAND created, with 39720564 rows and 40 columns.

    NOTE: PROCEDURE SQL used (Total process time):
          real time           6:30.64
          cpu time            3:10.59
    */

    %put; %put ### STEP 4. MERGING IN BECHMARK FACTORS...;
    proc sql;
        create table &prefix._expand as
            select a.*,
            a.&retvar. - b.vwretd as exret label='Market-adjusted total ret',
            b.*
            from _temp_expand a, _factors (keep=date vwretd &factors) b
            where a.date = b.date
            group by a.event_id
            ;
    quit;

    /*
    NOTE: Table USER.&PREFIX._EXPAND created, with 39720564 rows and 45 columns.

    NOTE: PROCEDURE SQL used (Total process time):
          real time           4:39.30
          cpu time            57.79 seconds
    */

    proc sort data=&prefix._expand;
        by event_id t;
    run;

    %if %substr(%lowcase(&debug),1,1) = n %then %do;
    proc datasets noprint;
        delete _temp:;
    quit;
    %end;

    %put;%put ### EVENT_EXPAND DONE! ###;

%MEND EVENT_EXPAND;

%MACRO EVENT_STATS(prefix = ,
                dsetin = ,
                group = ,
                filter = and shrcd in (10,11) and exchcd in (1,2,3),
                debug= = n
               );

    %if %sysevalf(%superq(dsetin)=,boolean)
        %then %let data=&prefix._expand;
        %else %let data=&dsetin.;
    %put;%put Using input dataset &data.;
    proc sort data=&data.;
        by event_id t;
    run;

/*****************************************************************
*  MACRO:      EVENT_STATS()
*  GOAL:       Estimate betas over event study window, compute abnormal returns
*  PARAMETERS: prefix        = prefix to describe the event, used to name
*                               output files
*              group         = give summary stats by group
*****************************************************************/
    %put; %put ### STEP 5. ESTIMATING FACTOR EXPOSURES OVER THE ESTIMATION PERIOD...;
    proc printto log=junk new;run;
    /*estimate risk factor exposures during the estimation period*/
    proc reg data=&data. edf outest=_params (rename=&newvars
        keep=event_id intercept &factors _rmse_  _p_ _edf_) noprint;
    where estper_beg<=date<=estper_end;
    by event_id;
    model &retvar.=&factors;
    quit;
    %put ### DONE! ###;
    proc printto;run;

    %put; %put ### STEP 6. CALCULATING ONE-DAY ABNORMAL RETURN IN THE EVENT WINDOW...;
    proc sql;
        create table &prefix._car(drop=&factors. _p_ _edf_ estper_beg estper_end) as
        select *,
            &abret. as abret label='One-day Abnormal Return (AR)',
            log(1+&retvar.) as logret,
            _rmse_*_rmse_ as var_estp label='Estimation Period Variance',
            _p_+_edf_ as nobs,
            year(&datevar.) as yyyy,
            coalesce(a.date GE a.&datevar.,0) as post
        from &data. a, _params b
        where a.event_id = b.event_id
        and a.date between a.evtwin_beg and a.evtwin_end
        ;
    quit;
    %put ### DONE! ###;

    %put; %put ### STEP 7. CALCULATING CARS AND VARIOUS STATISTICS...;
    proc means data=&prefix._car noprint;
        by event_id;
        class &group.;
        where 1 &filter.;
        id var_estp;
        output out=_car sum(logret)=cret sum(abret)=car mean(abret)=aar n(abret)=nrets;
    run;
    
    /*calculate Standardized Cumulative Abnormal Returns*/
    data _car; set _car;
      poscar=car>0;
      aar=aar*&evtwin.;
      scar=car/(&evtwin*var_estp)**0.5;
      cret=exp(cret)-1;
    label poscar='Positive Abnormal Return Dummy'
        scar=  'Standardized Cumulative Abnormal Return (SCAR)'
        car=   'Cumulative Abnormal Return (CAR)'
        aar =  'Average Abnormal Return (AAR)'
        cret=  'Cumulative Raw Return'
        nrets=  'Number of non-missing abnormal returns within event window';

    /*compute stats across all events (i.e., permno-event date combinations*/
    proc means data=_car noprint;
      var cret car aar scar poscar;
      class &group.;
      output out=_test
          mean= n= t=/autoname;
    run;
    
    /*calculate different stats for assessing    */
    /*statistical signficance of abnormal returns*/
    data &prefix._stats; set _test;
      tpatell=scar_mean*((scar_n)**0.5);
      tsign=(poscar_mean-0.5)/sqrt(0.25/poscar_n);
    format cret_mean car_mean aar_mean percent7.5;
    label tpatell=     "Patell's t-stat"
        car_mean=    'Mean Cumulative Abnormal Return'
        aar_mean=    'Mean Average Abnormal Return'
        cret_mean=   'Mean Cumulative Raw Return'
        scar_mean=   'Mean Cumulative Standardized Abnormal Return'
        car_t=       'CAR Cross-sectional t-stat'
        aar_t=       'AAR Cross-sectional t-stat'
        scar_t=      "Boehmer's et al. (1991) t-stat"
        car_n=       'Number of events in the portfolio'
        poscar_mean= 'Percent of positive abnormal returns'
        tsign=       'Sign-test statistic';
    drop cret_N scar_N poscar_N cret_t poscar_t;
    run;
    proc sort data=&prefix._stats;
        by &group.;
    run;

    proc print label u;
        title1 "Output for &prefix.";
        id &group;
        var cret_mean car_mean aar_mean scar_mean poscar_mean
            car_n tsign tpatell car_t aar_t scar_t;

    %if "&group" ne "" %then %do;
    title2 "Test for Equality of CARs among groups defined by &group";

    /*To find out the results of the hypothesis test for comparing groups   */
    /*find the row of output labeled 'Model' and look at the column labeled */
    /*F-value for the Fisher statistic and Pr>F for the associated p-value  */
    /*HOVTEST tests for whether variances of two groups are the same        */
        proc glm data=_car;
            class &group;
            model scar=&group;
            means &group /hovtest;

        proc npar1way data=_car wilcoxon;
            var scar;
            class &group;
            %end;
    run;

    %if %substr(%lowcase(&debug),1,1) = n %then %do;
    proc datasets noprint;
        delete _car _params;
    quit;
    %end;

    %put;%put ### EVENT_STATS DONE! ###;

%MEND EVENT_STATS;

%MACRO EVENT_PLOT (retvar=retx,
                dsetin = ,
                prefix = ,
                weightvar = vweight,
                r=1,
                filter = and shrcd in (10,11) and exchcd in (1,2,3),
                start = -30,
                end = 60,
                group =,
                plot = b,
                fileref = figdir,
                style = grayscaleprinter,
                debug = n
                );

/*****************************************************************
*  MACRO:      EVENT_PLOT()
*  GOAL:       Plot cumulative abnormal returns
*  PARAMETERS: prefix        = prefix to describe the event, used to name
*                               output files
*              dsetin        = dataset to plot
*              weightvar     = variable to weight returns by (default vweight)
*              r             = which return to use (default 1)
*                              0 - raw return (adjusted for delisting)
*                              1 - market excess return
*                              2 - model adjusted abnormal return
*              plot          = plot CAR or BHAR (default b)
*              ...
*****************************************************************/

    %if %sysevalf(%superq(fileref)=,boolean)
        %then filename figdir "~/";

    %if %sysevalf(%superq(dsetin)=,boolean)
        %then %let data=&prefix._car;
        %else %let data=&dsetin.;

    %if &weightvar=me %then %let &weightvar=me_l1;

    /* Compute portfolio returns */
    %if %SUBSTR(%LOWCASE(&debug),1,1) = n %then %do;
    proc printto log=junk new;run;
    %end;
    proc sort data=&data.;by t;run;
    proc means data=&data. noprint;
        by t;
        var &retvar. exret abret;
        class &group; 
        /* weight &weightvar.;  */
        where 1 &filter;
        output out=_port/* (where=(_TYPE_=1)) */
      mean= n= t=/autoname;
    run;
    %if %SUBSTR(%LOWCASE(&debug),1,1) = n %then %do;
    proc printto;run;
    %end;

    /* Compute BHAR and CAR */
    %if %SUBSTR(%LOWCASE(&debug),1,1) = n %then %do;
    proc printto log=junk new;run;
    %end;
    proc sort data=_port;
        by &group. t;
    proc expand data=_port
        out=_car(keep=t &group.
                &retvar._Mean exret_Mean abret_Mean
                bhar: car:
                &group.) method=none;
      by &group.; id t;
      convert &retvar._Mean=bhar0/
        transformin=(trim 1 setleft (. 0))
        transformout=(+1 cuprod);
      convert &retvar._Mean=car0/
        transformin=(trim 1 setleft (. 0))
        transformout=(sum);
      convert exret_Mean=bhar1/
        transformin=(trim 1 setleft (. 0))
        transformout=(+1 cuprod);
      convert exret_Mean=car1/
        transformin=(trim 1 setleft (. 0))
        transformout=(sum);
      convert abret_Mean=bhar2/
        transformin=(trim 1 setleft (. 0))
        transformout=(+1 cuprod);
      convert abret_Mean=car2/
        transformin=(trim 1 setleft (. 0))
        transformout=(sum);
    run;
    %if %SUBSTR(%LOWCASE(&debug),1,1) = n %then %do;
    proc printto;run;
    %end;

    /* Normalize so that first observation is 1 */
    data _car;
        set _car;
        label bhar0='Growth of $1, Returns Adjusted for Delistings';
        label car0='Cumulative Returns';
        label bhar1='Growth of $1, Excess Returns';
        label car1='Cumulative Excess Returns';
        label bhar2='Growth of $1, Abnormal Returns';
        label car2='Cumulative Abnormal Returns';
    run;

    ODS _ALL_ CLOSE;
    ODS PDF STYLE=&style. FILE=&fileref. BOOKMARKGEN=NO;
    ODS SELECT SGPlot.SGPlot;
    OPTIONS NODATE NONUMBER ORIENTATION=LANDSCAPE;
    GOPTIONS DEVICE=PDF;
    title1 "Cumulative returns for &prefix.";
    proc sgplot data=_car;
        %if %lowcase(&plot.)=b %then %do;
        series x=t y=bhar&r. /
            %if not(%sysevalf(%superq(group)=,boolean)) %then %do ;
                group=&group.
            %end;
                lineattrs=(thickness=3);
        %end;
        %if %lowcase(&plot.)=c %then %do;
        series x=t y=car&r. /
            %if not(%sysevalf(%superq(group)=,boolean)) %then %do ;
                group=&group.
            %end;
                lineattrs=(thickness=3);
        %end;
        refline 0 / axis=x lineattrs= (thickness=2 pattern=4);
    run;
    ODS PDF CLOSE;
    ODS LISTING;ODS OUTPUT;

    %if %SUBSTR(%LOWCASE(&debug),1,1) = n %then %do;
    /*house cleaning*/
    proc sql;
        drop table _car, _port;
    quit;
    %end;
%MEND EVENT_PLOT;

/* I don't use the below anymore */

%MACRO EVENT_SUMM(
                  prefix=,
                  varlist=me,
                  stats=n mean std q1 median q3,
                  filter=
                  );

/*****************************************************************
*  MACRO:      EVENT_SUMM()
*  GOAL:       Summary stats for events
*  PARAMETERS: prefix        = prefix to describe the event, used to name
*                               output files
*              varlist       = characteristics to summarize
*              stats         = statistics to compute
                                default n mean std q1 median q3
*              filter        = filter to apply to &prefix._merged file
*****************************************************************/

    proc sort data=&prefix._merged
        out=_summ_data(keep=
                        t event_id
                        &varlist.
                        hshrcd hexcd
                        where=(1 and &filter.)
                        ) NODUPKEY;
        by permno date;
    run;

    %better_means(data=_summ_data,clss=,varlst=&varlist.,
        stts=&stats.,lib=user,print=N);

    title "Summary Statistics - &prefix.";
    proc print data=_summ_data_means NOOBS ;
        var NAME &stats.;
    run;

    proc freq data=_summ_data NOPRINT;
        tables hexcd / out=_summ_freq sparse;
    run;
    proc transpose data=_summ_freq out=_&prefix._freq(drop=_NAME_ rename=(_LABEL_=Variable)) prefix=Exchange;
        var COUNT PERCENT;
    run;
    data _&prefix._freq;
        set _&prefix._freq;
        label Variable='Variable' Exchange1='NYSE' Exchange2='AMEX' Exchange3='NASDAQ';
    run;

    title "Exchanges - &prefix.";
    proc print data=_&prefix._freq NOOBS LABEL;run;

    proc datasets noprint;
        delete _summ: _&prefix.: _label;
    quit;

%MEND;

*%include 'E:\Dropbox\Research\STOCK CODE\SAS\BETTER_MEANS.sas';

%MACRO EVENT_OUT(
                 prefix=,
                 out_vars=,
                 filter=,
                 beg=-282, end=60,
                 min_obs = 200,
                 min_nret = 50
                 );

    /* Output estimation window data for PIN estimation */
    /* drop all days in which either buys or sells are equal to zero */

    proc sort data = &prefix._merged
        out = &prefix._out(
               keep = t event_id
                        &out_vars
                        n_buys n_sells
                        hshrcd hexcd
               where=(1 and &filter.)
               ) NODUPKEY;
        by event_id t;
    run;

    proc sql;
        create table &prefix._out as
        select *
        from &prefix._out
        group by event_id
        having count(*) > &min_obs.
        ;
    quit;

%MEND EVENT_OUT;
