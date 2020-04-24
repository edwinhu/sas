/*
Author: Edwin Hu
Date: 2020-03-28

# FF_FACTORS #

## Summary ##
Replicates Fama-French (1993) SMB & HML Factors
Currently obtaining correlations of 99.5% (SMB) 97.8% (HML)
for sample period 1975 to 2019.

Runs on WRDS Cloud
*/

%let comp=comp;
%let crsp=crsp;

%let begdate=01jan1975;
%let enddate=31dec2019;
   
/************************ Part 1: Compustat ****************************/
/* Compustat XpressFeed Variables:                                     */
/* AT      = Total Assets                                              */
/* PSTKL   = Preferred Stock Liquidating Value                         */
/* TXDITC  = Deferred Taxes and Investment Tax Credit                  */
/* PSTKRV  = Preferred Stock Redemption Value                          */
/* CEQ     = Common/Ordinary Equity - Total                            */
/* PSTK    = Preferred/Preference Stock (Capital) - Total              */
   
/* In calculating Book Equity, incorporate Preferred Stock (PS) values */
/*  use the redemption value of PS, or the liquidation value           */
/*    or the par value (in that order) (FF,JFE, 1993, p. 8)            */
/* USe Balance Sheet Deferred Taxes TXDITC if available                */
/* Flag for number of years in Compustat (<2 likely backfilled data)   */
   
%let vars = PSTKRV PSTKL PSTK TXDITC TXDB SEQ CEQ CEQL AT LT CSHPRI PRCC_F;
data comp;
  set &comp..funda
  (keep= gvkey datadate &vars indfmt datafmt popsrc consol);
  by gvkey datadate;
  where indfmt='INDL' and datafmt='STD' and popsrc='D' and consol='C'
  and datadate >=%sysfunc(putn("&begdate"d,5.));
  /* See Davis, Fama , French (2002) for a complete description */
  /* Preferred Stock Equity is measured as redemption, liquidation, or par value */
  PS = coalesce(PSTKRV,PSTKL,PSTK,0);
  /* Deferred tax is measured as balance sheet deferred taxes and investment tax credit (if available) */
  DEFTX = coalesce(TXDITC, TXDB,0);
  /* Shareholder's equity is measured as COMPUSTAT shareholder equity (total), 
  		or common plus preferred stock, or total assets minus total liabilities */
  SHE = coalesce(SEQ,coalesce(CEQ,CEQL,0) + coalesce(PSTK,0),coalesce(AT,0) - coalesce(LT,0),0);
  /* Book equity is shareholder's equity plus deferred taxes minus preferred stock */
  BE = coalesce(SHE + DEFTX - PS);
  if BE<0 then BE=.;
  ME = abs(coalesce(CSHPRI,0)*coalesce(PRCC_F,0));
  year = year(datadate);
  label BE='Book Value of Equity FYear t-1' ;
  drop indfmt datafmt popsrc consol ps &vars;
  retain count;
  if first.gvkey then count=1;
  else count = count+1;
run;
   
/************************ Part 2: CRSP **********************************/
/* Create a CRSP Subsample with Monthly Stock and Event Variables       */
/* This procedure creates a SAS dataset named "CRSP_M"                  */
/* Restrictions will be applied later                                   */
/* Select variables from the CRSP monthly stock and event datasets      */
%let msevars=ticker ncusip shrcd exchcd;
%let msfvars = prc ret retx shrout cfacpr cfacshr;

%include '/wrds/crsp/samples/crspmerge.sas';

%crspmerge(s=m,start=&begdate.,end=&enddate.,
sfvars=&msfvars,sevars=&msevars,filters=exchcd in (1,2,3));
   
/* CRSP_M is sorted by date and permno and has historical returns     */
/* as well as historical share codes and exchange codes               */
/* Add CRSP delisting returns */
proc sql; create table crspm2
 as select a.*, b.dlret,
  sum(1,ret)*sum(1,dlret)-1 as retadj "Return adjusted for delisting",
  abs(a.prc)*a.shrout as MEq 'Market Value of Equity'
 from work.Crsp_m a left join &crsp..msedelist(where=(missing(dlret)=0)) b
 on a.permno=b.permno and
    intnx('month',a.date,0,'E')=intnx('month',b.DLSTDT,0,'E')
 order by a.date, a.permco, MEq;
quit;
   
/* There are cases when the same firm (permco) has two or more         */
/* securities (permno) at same date. For the purpose of ME for         */
/* the firm, we aggregated all ME for a given permco, date. This       */
/* aggregated ME will be assigned to the Permno with the largest ME    */
data crspm2a (drop = Meq); set crspm2;
  by date permco Meq;
  retain ME;
  if first.permco and last.permco then do;
    ME=meq;
  output; /* most common case where a firm has a unique permno*/
  end;
  else do ;
    if  first.permco then ME=meq;
    else ME=sum(meq,ME);
    if last.permco then output;
  end;
run;
   
/* There should be no duplicates*/
proc sort data=crspm2a nodupkey; by permno date;run;
   
/* The next step does 2 things:                                        */
/* - Create weights for later calculation of VW returns.               */
/*   Each firm's monthly return RET t willl be weighted by             */
/*   ME(t-1) = ME(t-2) * (1 + RETX (t-1))                              */
/*     where RETX is the without-dividend return.                      */
/* - Create a File with December t-1 Market Equity (ME)                */
data crspm3 (keep=permno date retadj weight_port ME exchcd shrcd cumretx)
decme (keep = permno date ME rename=(me=DEC_ME) )  ;
     set crspm2a;
 by permno date;
 retain weight_port cumretx me_base;
 LME=lag(me);
     if first.permno then do;
     LME=me/(1+retx); cumretx=sum(1,retx); me_base=LME;weight_port=.;end;
     else do;
     if month(date)=7 then do;
        weight_port= LME;
        me_base=LME; /* lag ME also at the end of June */
        cumretx=sum(1,retx);
     end;
     else do;
        if LME>0 then weight_port=cumretx*me_base;
        else weight_port=.;
        cumretx=cumretx*sum(1,retx);
     end; end;
output crspm3;
if month(date)=12 and ME>0 then output decme;
run;
   
/* Create a file with data for each June with ME from previous December */
proc sql;
  create table crspjune as
  select a.*, b.DEC_ME
  from crspm3 (where=(month(date)=6)) as a, decme as b
  where a.permno=b.permno and
  intck('month',b.date,a.date)=6;
quit;
   
/***************   Part 3: Merging CRSP and Compustat ***********/
/* Add Permno to Compustat sample */
proc sql;
  create table ccm1 as
  select a.*, b.lpermno as permno, b.linkprim
  from comp as a, &crsp..ccmxpf_linktable as b
  where a.gvkey=b.gvkey
  and substr(b.linktype,1,1)='L' and linkprim in ('P','C')
  and (intnx('month',intnx('year',a.datadate,0,'E'),6,'E') >= b.linkdt)
  and (b.linkenddt >= intnx('month',intnx('year',a.datadate,0,'E'),6,'E')
  or missing(b.linkenddt))
  order by a.datadate, permno, b.linkprim desc;
quit;
   
/*  Cleaning Compustat Data for no relevant duplicates                      */
/*  Eliminating overlapping matching : few cases where different gvkeys     */
/*  for same permno-date --- some of them are not 'primary' matches in CCM  */
/*  Use linkprim='P' for selecting just one gvkey-permno-date combination   */
data ccm1a; set ccm1;
  by datadate permno descending linkprim;
  if first.permno;
run;
   
/* Sanity Check -- No Duplicates */
proc sort data=ccm1a nodupkey; by permno year datadate; run;
   
/* 2. However, there other type of duplicates within the year                */
/* Some companies change fiscal year end in the middle of the calendar year */
/* In these cases, there are more than one annual record for accounting data */
/* We will be selecting the last annual record in a given calendar year      */
data ccm2a ; set ccm1a;
  by permno year datadate;
  if last.year;
run;
   
/* Sanity Check -- No Duplicates */
proc sort data=ccm2a nodupkey; by permno datadate; run;
   
/* Finalize Compustat Sample                              */
/* Merge CRSP with Compustat data, at June of every year  */
/* Match fiscal year ending calendar year t-1 with June t */
proc sql; create table ccm2_june as
  select a.*, b.BE, (1000*b.BE)/a.DEC_ME as BEME, b.count,
  b.datadate,
  intck('month',b.datadate, a.date) as dist
  from crspjune a, ccm2a b
  where a.permno=b.permno and intnx('month',a.date,0,'E')=
  intnx('month',intnx('year',b.datadate,0,'E'),6,'E')
  order by a.date;
quit;
   
/************************ Part 4: Size and Book to Market Portfolios ***/
/* Forming Portolio by ME and BEME as of each June t                   */
/* Calculate NYSE Breakpoints for Market Equity (ME) and               */
/* Book-to-Market (BEME)                                               */
proc univariate data=ccm2_june noprint;
  where exchcd=1 and beme>0 and shrcd in (10,11) and me>0 and count>=2;
  var ME BEME;
  by date; /*at june;*/
  output out=nyse_breaks median = SIZEMEDN pctlpre=ME BEME pctlpts=30 70;
run;
   
/* Use Breakpoints to classify stock only at end of all June's */
proc sql;
  create table ccm3_june as
  select a.*, b.sizemedn, b.beme30, b.beme70
  from ccm2_june as a, nyse_breaks as b
  where a.date=b.date;
quit;
   
/* Create portfolios as of June                       */
/* SIZE Portfolios          : S[mall] or B[ig]        */
/* Book-to-market Portfolios: L[ow], M[edium], H[igh] */
data june ; set ccm3_june;
 If beme>0 and me>0 and count>=2 then do;
 positivebeme=1;
 * beme>0 includes the restrictioncs that ME at Dec(t-1)>0
 * and BE (t-1) >0 and more than two years in Compustat;
 if 0 <= ME <= sizemedn     then sizeport = 'S';
 else if ME > sizemedn      then sizeport = 'B';
 else sizeport='';
 if 0 < beme <= beme30 then           btmport = 'L';
 else if beme30 < beme <= beme70 then btmport = 'M' ;
 else if beme  > beme70 then          btmport = 'H';
 else btmport='';
end;
else positivebeme=0;
if cmiss(sizeport,btmport)=0 then nonmissport=1; else nonmissport=0;
keep permno date sizeport btmport positivebeme exchcd shrcd nonmissport;
run;
   
/* Identifying each month the securities of              */
/* Buy and hold June portfolios from July t to June t+1  */
proc sql; create table ccm4 as
 select a.*, b.sizeport, b.btmport, b.date as portdate format date9., 
        b.positivebeme , b.nonmissport 
 from crspm3 as a, june as b
 where a.permno=b.permno and  1 <= intck('month',b.date,a.date) <= 12
 order by date, sizeport, btmport;
quit;
   
/*************** Part 5: Calculating Fama-French Factors  **************/
/* Calculate monthly time series of weighted average portfolio returns */
proc means data=ccm4 noprint;
 where weight_port>0 and positivebeme=1 and exchcd in (1,2,3) 
      and shrcd in (10,11) and nonmissport=1;
 by date sizeport btmport;
 var retadj;
 weight weight_port;
 output out=vwret (drop= _type_ _freq_ ) mean=vwret n=n_firms;
run;
   
/* Monthly Factor Returns: SMB and HML */
proc transpose data=vwret(keep=date sizeport btmport vwret) 
 out=vwret2 (drop=_name_ _label_);
 by date ;
 ID sizeport btmport;
 Var vwret;
run;
   
/************************ Part 6: Saving Output ************************/
data out.ff_factors;
set vwret2;
 WH = (bh + sh)/2  ;
 WL = (sl + bl)/2 ;
 WHML = WH - WL;
 WB = (bl + bm + bh)/3 ;
 WS = (sl + sm + sh)/3 ;
 WSMB = WS - WB;
 label WH   = 'WRDS High'
       WL   = 'WRDS Low'
       WHML = 'WRDS HML'
       WS   = 'WRDS Small'
       WB   = 'WRDS Big'
       WSMB = 'WRDS SMB';
run;
   
/* Number of Firms */
proc transpose data=vwret(keep=date sizeport btmport n_firms) 
               out=vwret3 (drop=_name_ _label_) prefix=n_;
by date ;
ID sizeport btmport;
Var n_firms;
run;
   
data out.ff_nfirms;
set vwret3;
 N_H = n_sh + n_bh;
 N_L = n_sl + n_bl;
 N_HML = N_H + N_L;
 N_B =  n_bl + n_bm + n_bh;
 N_S =  n_sl + n_sm + n_sh ;
 N_SMB = N_S + N_B;
 Total1= N_SMB;
 label N_H   = 'N_firms High'
       N_L   = 'N_firms Low'
       N_HML = 'N_firms HML'
       N_S   = 'N_firms Small'
       N_B   = 'N_firms Big'
       N_SMB = 'N_firms SMB';
run;

/************************ Part 7: Check Correlations ************************/

proc sql;
    create table ff_merged as
    select a.*, WHML, WSMB
    from ff.factors_monthly as a
    inner join out.ff_factors as b
    on a.dateff = b.date
    ;
quit;

proc corr data=ff_merged nosimple;
    var smb hml;
    with WSMB WHML;
run;

/* Clean house*/
proc sql; 
   drop table ccm1, ccm1a,ccm2a,ccm2_june,
              ccm3_june, ccm4, comp,
              crspm2, crspm2a, crspm3, crsp_m,
              decme, june, nyse_breaks;
quit;
