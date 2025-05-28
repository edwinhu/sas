data msf;
    set crspm.msf;
    ME = abs(coalesce(PRC,0)*coalesce(shrout,0));
proc sort data=msf;
    by date permco ME;
run;

/* Combine PERMCOs with two issues and keep larger PERMNO */
data msf2;
    retain MET;
    set msf;
    by date permco;
    if first.date or first.permco then MET=ME;
    else MET+ME;
    if last.permco then output;
proc sort data=msf2 nodupkey;
    by permno date;
run;

data msf3;
    retain ME6 ME12;
    set msf2;
    by permno;
    if first.permno then ME6=.;
    if month(date)=6 then ME6=MET;
    if first.permno then ME12=.;
    if month(date)=12 then ME12=MET;
run;

proc expand data=msf3 out=msf4
method=none;
by permno;
convert MET = ME_L1 / transformout = (LAG 1) ;
convert MET = ME_L2 / transformout = (LAG 2) ;
CONVERT RET = MOM6/ transformin=(setmiss 0) transformout = (+1 movprod 6 -1 trimleft 5 );
run;

%INCLUDE "~/git/sas/MERGE_ASOF.sas";

%MERGE_ASOF(a=msf4,b=compx2,
    merged=msfx,
    idvar=permno,
    datevar=date,
    num_vars=BE ME_COMP LEV AT LT DATADATE COUNT,
    char_vars=GVKEY CUSIP);

PROC SQL noprint;
    create table crspx as
    select a.*,
    1e3*BE/ME12 as BML,
    ME6 as MCL,
    year(date) as YEAR,
    b.exchcd,
    b.shrcd,
    b.siccd,
    sum(1,a.ret)*sum(1,c.dlret)-1 as RETADJ 
    "Return adjusted for delisting"
    from msfx a
    left join
    crspm.msenames b
    on a.permno = b.permno
    and a.date ge b.namedt
    and a.date le coalesce(b.nameendt,today())
    left join
    crspm.msedelist(where=(missing(dlret)=0)) c
    on a.permno=c.permno 
    and a.date=intnx('month',c.DLSTDT,0,'E')
    ;
QUIT;

proc sort data=crspx out=rank;
    by year;
    where month(date)=7;
run;
proc univariate data=rank noprint;
    where exchcd=1 and shrcd in (10,11)
    and siccd not between 6000 and 6999
    and count >= 2;
    by date;
    var BML MCL MOM6;
    output out=NYSE 
    pctlpts = 10 to 100 by 10 pctlpre=B_ M_ R_;
run;

data rank2;
    merge rank NYSE(keep=date M_50 B_30 B_70 R_30 R_70);
    by date;
    if MCL >= 0 and MCL <= M_50 then MCR = 1;
    if MCL > M_50 then MCR = 2;
    if BML > 0 and BML <= B_30 then BMR = 1;
    if BML > B_30 and BML <= B_70 then BMR = 2;
    if BML > B_70 then BMR = 3;
    if MOM6 > 0 and MOM6 <= R_30 then UDR = 1;
    if MOM6 > R_30 and MOM6 <= R_70 then UDR = 2;
    if MOM6 > R_70 then UDR = 3;
    WT = ME_L1;
run;

%MERGE_ASOF(a=crspx,b=rank2,
    merged=crspx2,
    idvar=permno,
    datevar=date,
    num_vars=MCR BMR UDR WT
    );

/* PROC PRINT data=crspx2(obs=25);
where permno = 11850 and year=1999;RUN; */

proc sort data=crspx2 nodupkey;by date BMR MCR UDR permno;run;
proc means data=crspx2 noprint;
by date;
class BMR MCR UDR;
where WT>0 and BE > 0 
and SHRCD in (10,11) and EXCHCD in (1,2,3);
var RETADJ / weight=WT;
output out=FF_VWRET(drop=_type_ _freq_) mean=VWRET;
run;
PROC TRANSPOSE 
    data=FF_VWRET
    out=FF_SMB(drop=_:);
    where MCR > 0 and BMR = . and UDR = .;
    by date;
    var VWRET;
RUN;
PROC TRANSPOSE data=FF_VWRET
    out=FF_HML(drop=_:);
    where BMR > 0 and MCR = . and UDR = .;
    by date;
    var VWRET;
RUN;
PROC TRANSPOSE data=FF_VWRET
    out=FF_UMD(drop=_:);
    where UDR > 0 and MCR = . and BMR = .;
    by date;
    var VWRET;
RUN;
proc sql;
    create table FF_FACTORS as
    select a.date, 
    a.COL1-a.COL2 as SMB,
    b.COL3-b.COL1 as HML,
    c.COL3-b.COL1 as UMD
    from FF_SMB a,
    FF_HML b,
    FF_UMD c
    where a.date=b.date
    and a.date=c.date;
quit;

proc sql;
    create table FF_TEST as
    select a.*,
    b.hml as hml_e,
    b.smb as smb_e,
    b.umd as umd_e
    from ff.factors_monthly a,
    FF_FACTORS b
    where a.dateff = b.date
    ;
quit;
PROC CORR data=ff_test nosimple;
    where year(date) > 1972;
    var smb:;
RUN;    
PROC CORR data=ff_test nosimple;
    where year(date) > 1972;
    var hml:;
RUN;
PROC CORR data=ff_test nosimple;
    where year(date) > 1972;
    var umd:;
RUN;
