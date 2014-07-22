%MACRO EVENT_PLOT (
                INSET = ,
                WEIGHTVAR = ,
                FILTER = shrcd in (10,11) and exchcd in (1,2,3),
                START = -30,
                END = 60,
                GROUP =,
                DEBUG = n
                );

    %if &WEIGHTVAR=me %then %let &WEIGHTVAR=me_l1;

    /* Compute BHAR and CAR */
    proc printto log=junk new;run;
    proc expand data=&INSET.
        out=_car(keep=permno
                evtdate evttime date
                abret bhar car
                me /*shrcd exchcd*/
                &GROUP. &WEIGHTVAR.) method=none;
      by permno evtdate; id evttime;
      convert abret=bhar/transformout=(+1 cuprod -1);
      convert abret=car/transformout=(sum);
      convert me=me_l1/transformout=(lag 1);
    run;
    proc printto;run;

    data _car;
        retain permno evtdate evttime date abret bhar car;
        set _car;
        label bhar='Buy and Hold Abnormal Returns';
        label car='Cumulative Abnormal Returns';
    run;

    /* Compute portfolio returns */
    proc printto log=junk new;run;
    proc sort data=_car;
        by evttime;
    proc means data=_car noprint;
        by evttime;
        var abret bhar car;
        class &GROUP;
        weight &WEIGHTVAR.;
        where 1 and &FILTER;
        output out=_port
      mean= n= t=/autoname;
    run;
    proc printto;run;

    /* Normalize portfolio returns - growth of $1 */
    data _port;
        set _port;
        retain bhar0 car0;
        if _n_ = 1 then do;
            bhar0 = bhar_mean;
            car0 = car_mean;
        end;
            bhar1 = bhar_mean/bhar0;
            car1 = car_mean/car0;
        label bhar1='Growth of $1 (BHAR)'
              car1='Growth of $1 (CAR)';
        drop bhar0 car0;
    run;

    title1 "Event time abnormal returns for &inset.";
    proc sgplot data=_port;
        series x=evttime y=abret_mean /
            %if not(%sysevalf(%superq(group)=,boolean)) %then %do ;
                group=&GROUP.
            %end;
                markers lineattrs=(thickness=3 pattern=1);
        refline 0 / axis=x lineattrs= (thickness=2 pattern=4);
    run;

    title1 "Event time buy-and-hold/cumulative abnormal returns for &inset.";
    proc sgplot data=_port;
        series x=evttime y=bhar1 /
            %if not(%sysevalf(%superq(group)=,boolean)) %then %do ;
                group=&GROUP.
            %end;
                markers lineattrs=(thickness=3 pattern=1);
        series x=evttime y=car1 /
            %if not(%sysevalf(%superq(group)=,boolean)) %then %do ;
                group=&GROUP.
            %end;
                markers lineattrs=(thickness=3 pattern=1);
        refline 0 / axis=x lineattrs= (thickness=2 pattern=4);
    run;

    %if %SUBSTR(%LOWCASE(&debug),1,1) = n %then %do;
    /*house cleaning*/
    proc sql;
        drop table _car, _port;
    quit;
    %end;
%MEND EVENT_PLOT;
