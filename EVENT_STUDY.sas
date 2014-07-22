/* ********************************************************************************* */
/* ******************** W R D S   R E S E A R C H   M A C R O S ******************** */
/* ********************************************************************************* */
/* WRDS Macro: EVENT_STUDY                                                              */
/* Summary   : Performs an event study                                               */
/* Date      : July 17, 2009                                                         */
/* Modified  : May 30, 2012                                                          */
/* Author    : Denys Glushkov, WRDS                                                  */
/* Parameters:                                                                       */
/*    - ID     : Name of security identifier in INSET: PERMNO or CUSIP               */
/*               CUSIP should be at least 8 (eight) characters                       */
/*    - INSET  : Input dataset containg security IDs and event dates                 */
/*    - OUTSET : Name of the output dataset to store mean CAR and t-stats            */
/*    - OUTSTATS:Name of the output dataset to store test statistics (Patell Z, etc) */
/*    - EVTDATE: Name of the event date variable in INSET dataset                    */
/*    - DATA   : Name of CRSP library to use. CRSP and CRSPQ for annual and          */
/*               quarterly updates, respectively                                     */
/*    - ESTPER : Length of the estimation period in trading days over which          */
/*               the risk model is run, e.g., 110;                                   */
/*    - START  : Beginning of the event window (relative to the event date, eg. -2)  */
/*    - END    : End of the event window (relative to the event date, e.g., +1)      */
/*    - GAP    : Length of pre-event window, i.e., number of trading days between    */
/*               the end of estimation period and the beginning of the event window  */
/*    -GROUP: Defines an subgroup (can be more than 2)                               */
/*    -MODEL: Risk model to be used for risk-adjustment                              */
/*            madj - Market-Adjusted Model (assumes stock beta=1)                    */
/*            m    - Standard Market Model (CRSP value-weighted index as the market) */
/*            ff   - Fama-French three factor model                                  */
/*            ffm  - Carhart model that includes FF factors plus momentum            */
/* ********************************************************************************* */
%MACRO EVENT_STUDY (INSET=, OUTSET=, OUTSTATS=, ID=permno, EVTDATE=, DATA=CRSP,
                 ESTPER=, START=,END=,GAP=,GROUP=,MODEL=,DEBUG=n);
    %local evtwin factors abret newvars;
    %local oldoptions errors;
    %let oldoptions=%sysfunc(getoption(mprint)) %sysfunc(getoption(notes))
    %sysfunc(getoption(source));
    %let errors=%sysfunc(getoption(errors));
    %if %SUBSTR(%LOWCASE(&debug),1,1) = n %then %do;
    options nonotes nomprint nosource errors=0;
    %end;

  %let evtwin=%eval(&end-&start+1); *length of event window in trading days;

  /*depending on the model, define the model for abnormal returns*/
  %if %lowcase(&model)=madj %then %do; %let factors=vwretd;
              %let abret=ret-vwretd;
              %let newvars=(intercept=alpha);
              %end;%else
  %if %lowcase(&model)=m %then  %do; %let factors=vwretd;
              %let abret=ret-alpha-beta*vwretd;
              %let newvars=(intercept=alpha vwretd=beta);
              %end;%else
  %if %lowcase(&model)=ff %then %do;
              %let factors=vwretd smb hml;
              %let abret=ret-alpha-beta*vwretd-sminb*smb-hminl*hml;
              %let newvars=(intercept=alpha vwretd=beta smb=sminb hml=hminl);
              %end;%else
  %if %lowcase(&model)=ffm %then %do;
              %let factors=vwretd smb hml mom;
              %let abret=ret-alpha-beta*vwretd-sminb*smb-hminl*hml-wminl*mom;
              %let newvars=(intercept=alpha vwretd=beta smb=sminb hml=hminl mom=wminl);
              %end;

  %put; %put ### STEP 1. CREATING TRADING DAY CALENDAR...;
  data _caldates;
   merge &data..dsiy (keep=caldt rename=(caldt=estper_beg))
   &data..dsiy (keep=caldt firstobs=%eval(&estper) rename=(caldt=estper_end))
   &data..dsiy (keep=caldt firstobs=%eval(&estper+&gap+1) rename=(caldt=evtwin_beg))
   &data..dsiy (keep=caldt firstobs=%eval(&estper+&gap-&start+1) rename=(caldt=&evtdate))
   &data..dsiy (keep=caldt firstobs=%eval(&estper+&gap+&evtwin) rename=(caldt=evtwin_end));
   format estper_beg estper_end evtwin_beg &evtdate evtwin_end yymmdd10.;
   if nmiss(estper_beg,estper_end,evtwin_beg,evtwin_end,&evtdate)=0;
   time+1;
  run;
 %put ### DONE!;

  /*If primary identifier is Cusip, then link in permno*/
  %if %lowcase(&id)=cusip %then %do;
  proc sql;
   create view  _link
   as select permno, ncusip,
   min(namedt) as fdate format=yymmdd10., max(nameendt) as ldate format=yymmdd10.
   from &data..dsenames
   group by permno, ncusip;

   create table _temp
   as select distinct b.permno, a.*
   from &inset a left join _link b
   on a.cusip=b.ncusip and b.fdate<=a.&evtdate<=b.ldate
   order by a.&evtdate;
  quit;%end;
  %else %do;
  /*pre-sort the input dataset in case it is not sorted yet*/
  proc sort data=&inset out=_temp;
   by &evtdate;
  run;
  %end;

  /*Event dates should already be trading calendar days    */
  /*Merge in relevant dates from the trading calendar      */
  proc printto log=junk new;run;
  proc sql;
   create table _temp (drop=&evtdate)
   as select a.*, a.&evtdate as _edate format yymmdd10., b.*
   from _temp a, _caldates (drop=time) b
   where a.&evtdate = b.&evtdate
   ;
  quit;
  proc printto;run;

  %put ; %put ### STEP 2. PREPARING BENCHMARK FACTORS... ;
  proc sql;create table _factors
   as select a.caldt as date, a.vwretd, b.smb, b.hml, b.umd as mom
   from &data..dsiy (keep=caldt vwretd) a left join ff.factors_daily b
   on a.caldt=b.date;
  quit;
  %put ### DONE! ;

  %put; %put ### STEP 3. RETRIEVING RETURNS DATA FROM CRSP...;
  proc printto log=junk new;run;
  proc sql;
   create table _evtrets_temp
    as select a.permno, a.date format yymmdd10.,
      a.ret as ret1,
      abs(a.shrout*a.prc) as me label='Market equity',
      b.*
   from &data..dsf a, _temp b
    where a.permno=b.&id. and b.estper_beg<=a.date<=b.evtwin_end;
  quit;
  proc printto;run;
  %put ### DONE!;

  %put; %put ### STEP 4. MERGING IN BECHMARK FACTORS...;

  proc sql;
    create table _evtrets as
      select a.*,
        a.ret_adj - b.vwretd as exret label='Market-adjusted total ret',
        b.*
    from _evtrets_temp a, _factors b
    where a.date = b.caldt
    ;
  quit;
      
  proc sql;
   create table _evtrets1
     as select a.*, b.*, (c.time-d.time) as evttime
   from _evtrets_temp a
   left join _factors (keep=date &factors) b
        on a.date=b.date
   left join _caldates c
        on a.date=c.&evtdate
   left join _caldates d
        on a._edate=d.&evtdate;

   create table _evtrets (where=(not missing(vwretd)))
     as select a.*, a.ret1 label='Ret unadjusted for delisting',
     (1+a.ret1)*sum(1,b.dlret)-1-a.vwretd as exret label='Market-adjusted total ret',
     (1+a.ret1)*sum(1,b.dlret)-1 as ret "Ret adjusted for delisting"
   from _evtrets1 a left join &data..dsedelist (where=(missing(dlret)=0)) b
   on a.permno=b.permno and a.date=b.dlstdt
   order by a.permno,a._edate,a.date, a.evttime;
 quit;
 
 %put ### DONE!;

 %put; %put ### STEP 5. ESTIMATING FACTOR EXPOSURES OVER THE ESTIMATION PERIOD...;
 proc printto log=junk new;run;
 %if %lowcase(&model) ne madj %then %do;
  /*estimate risk factor exposures during the estimation period*/
  proc reg data=_evtrets edf outest=_params (rename=&newvars
    keep=permno _edate intercept &factors _rmse_  _p_ _edf_) noprint;
    where estper_beg<=date<=estper_end;
    by permno _edate;
    model ret=&factors;
  quit;%end;
  %else %do;
   proc reg data=_evtrets edf outest=_params (rename=&newvars
    keep=permno _edate intercept _rmse_  _p_ _edf_) noprint;
    where estper_beg<=date<=estper_end;
    by permno _edate;
    model ret=;
  quit;%end;
 %put ### DONE!;
 proc printto;run;

 %put; %put ### STEP 6. CALCULATING ONE-DAY ABNORMAL RETURN IN THE EVENT WINDOW...;
  data _abrets/view=_abrets;
    merge _evtrets (where=(evtwin_beg<=date<=evtwin_end) in=a) _params;
     by permno _edate;
     abret=&abret;
     logret=log(1+ret);
     var_estp=_rmse_*_rmse_;
     nobs=_p_+_edf_;
     label var_estp='Estimation Period Variance'
           abret=   'One-day Abnormal Return (AR)'
           ret=     'Raw Return'
           _edate= 'Event Date'
           evttime= "Trading day within (&start,&end) event window";
     drop &factors _p_ _edf_ estper_beg estper_end;
     if a;
  run;
 %put ### DONE!;

 %put; %put ### STEP 7. CALCULATING CARS AND VARIOUS STATISTICS...;
  proc means data=_abrets noprint;
   by permno _edate;
   id &group var_estp;
  output out=_car sum(logret)=cret sum(abret)=car n(abret)=nrets;

  /*calculate Standardized Cumulative Abnormal Returns*/
  data _car; set _car;
    poscar=car>0;
    scar=car/(&evtwin*var_estp)**0.5;
    cret=exp(cret)-1;
    label poscar='Positive Abnormal Return Dummy'
          scar=  'Standardized Cumulative Abnormal Return (SCAR)'
          car=   'Cumulative Abnormal Return (CAR)'
          cret=  'Cumulative Raw Return'
         nrets=  'Number of non-missing abnormal returns within event window';

  /*compute stats across all events (i.e., permno-event date combinations*/
  proc means data=_car noprint;
    var cret car scar poscar;
    class &group;
    output out=_test
  mean= n= t=/autoname;

  /*calculate different stats for assessing    */
  /*statistical signficance of abnormal returns*/
  data &outstats; set _test;
    tpatell=scar_mean*((scar_n)**0.5);
    tsign=(poscar_mean-0.5)/sqrt(0.25/poscar_n);
    format cret_mean car_mean percent7.5;
    label tpatell=     "Patell's t-stat"
     car_mean=    'Mean Cumulative Abnormal Return'
     cret_mean=   'Mean Cumulative Raw Return'
     scar_mean=   'Mean Cumulative Standardized Abnormal Return'
     car_t=       'Cross-sectional t-stat'
     scar_t=      "Boehmer's et al. (1991) t-stat"
     car_n=       'Number of events in the portfolio'
     poscar_mean= 'Percent of positive abnormal returns'
     tsign=       'Sign-test statistic';
	drop cret_N scar_N poscar_N cret_t poscar_t;
   run;
  %put ### DONE!;

  proc print label u;
    title1 "Output for dataset &inset for a
   (&start,&end) event window using &model model";
    id &group;
    var cret_mean car_mean scar_mean poscar_mean
         car_n tsign tpatell car_t scar_t;

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

/*create the final output dataset*/
proc sort data=&inset.;
    by permno &evtdate.;
run;
 data &outset;
   merge &inset (in=a rename=(&evtdate.=_edate))
         _abrets(keep=permno _edate date evttime ret abret me var_estp)
         _car   (keep=permno _edate cret car scar nrets);
   by permno _edate;
   rename _edate=evtdate;
   label _edate='Event date'
         date='Trading date in event window';
   format _edate yymmdd10. date yymmdd10.;
   if a;
  run;

 %if %SUBSTR(%LOWCASE(&debug),1,1) = n %then %do;
 /*house cleaning*/
 proc sql; drop table _caldates, _car, _factors, _test,
         _params, _temp, _evtrets,_evtrets1, _evtrets_temp;
          drop view _abrets; quit;
 options errors=&errors &oldoptions;
 %end;
 %put ;%put ### OUTPUT IN THE DATASET &outset;
 %put ;%put ### TEST STATISTICS IN THE DATASET &outstats;

%MEND;
/* ********************************************************************************* */
/* *************  Material Copyright Wharton Research Data Services  *************** */
/* ****************************** All Rights Reserved ****************************** */
/* ********************************************************************************* */
