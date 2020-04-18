/*
Author: Edwin Hu
Date: 2013-05-24

# CC_LINK #

## Summary ##
Links COMPUSTAT GVKEYs to CRSP PERMNOs.

Takes a file which contains GVKEYs and dates and merges in the
appropriate PERMNOs. This handles a lot of silly merge issues.

Suitable for most cases where you need COMPUSTAT data, but may not be
enough for specific paper replications (e.g., FF93)

## Variables ##
- dsetin: Input Dataset
- dsetout: Output Dataset Name, default compx
- datevar: date variable to use (datadate, rdq)
- keep_vars: variables to keep

## Usage ##
```
%IMPORT "~/git/sas/CC_LINK.sas";

%CC_LINK(dsetin=&syslast.,
    dsetout=compx,
    datevar=datadate,
    keep_vars=);
```
*/

%MACRO CC_LINK(dsetin=comp.funda,
               dsetout=compx,
               datevar=datadate,
               keep_vars=);

OPTIONS NONOTES;

/* If PERMNO is the primary key, then the CRSP Manual recommends              */
/* forming GVKEY-PERMNO links where the USEDFLAG=1, which is unique           */
/* See: http://www.crsp.chicagobooth.edu/documentation/product/ccm/crsp_link/ */

PROC SQL;
    CREATE TABLE compx AS
    SELECT b.lpermno AS permno,
        b.lpermco as permco,
        a.*,
        /* Fama French assume a six month minimum filing delay for 10-Ks */
        intnx('month',datadate,6,'E') as date
        FROM &dsetin.(keep=GVKEY &datevar.
        &keep_vars.
        CUSIP CIK FYEAR
        INDFMT DATAFMT CONSOL POPSRC
        %if &dsetin.=comp.funda %then %do;
        PSTKRV PSTKL PSTK TXDITC TXDB SEQ CEQ CEQL AT LT CSHPRI PRCC_F GP
        %end;
        %if &dsetin.=comp.fundq %then %do;
        ATQ LTQ IBQ RDQ
        %end;        
<<<<<<< HEAD
        ) AS a, crsp.ccmxpf_linktable AS b
    WHERE a.indfmt IN ('INDL','BANK','UTIL')
=======
        ) AS a, 
    crspm.ccmxpf_linktable AS b
    WHERE a.indfmt = 'INDL'
>>>>>>> 282d602362944b4003dc53c297f2cdbbd6b42f2b
    AND a.datafmt = 'STD'
    AND a.popsrc = 'D'
    AND a.consol = 'C'
    AND a.gvkey=b.gvkey
    AND SUBSTR(b.linktype,1,1)='L' AND linkprim IN ('P','C')
    AND (b.LINKDT <= CALCULATED date or b.LINKDT = .B)
    AND (CALCULATED date <= b.LINKENDDT or b.LINKENDDT = .E)
    /* If you don't use usedflag you will have duplicates */
    AND b.usedflag=1
    ORDER BY permno, CALCULATED date;
QUIT;

%if &dsetin.=comp.funda %then %do;
proc printto log=junk new;run;
/* Compute Book Equity */
data out.&dsetout.;
    set compx;
    /* See Davis, Fama , French (2002) for a complete description */
    /* Preferred Stock Equity is measured as redemption, liquidation, or par value */
    PS = coalesce(PSTKRV,PSTKL,PSTK,0);
    /* Deferred tax is measured as balance sheet deferred taxes and investment tax credit (if available) */
    DEFTX = coalesce(TXDITC,TXDB,0);
    /* Shareholder's equity is measured as COMPUSTAT shareholder equity (total),
    or common plus preferred stock, or total assets minus total liabilities */
    SHE = coalesce(SEQ,coalesce(CEQ,CEQL,0) + coalesce(PSTK,0),coalesce(AT,0) - coalesce(LT,0),0);
    /* Book equity is shareholder's equity plus deferred taxes minus preferred stock */
    BE = coalesce(SHE + DEFTX - PS);
    if BE<0 then BE=.;
    ME_COMP = abs(coalesce(CSHPRI,0)*coalesce(PRCC_F,0))*1000;
    LEV = LT/AT;
    YEAR=year(datadate);
    label BE='Book Value of Equity Fiscal Year t-1' 
    YEAR='Calendar Year' 
    date='Data available to market';
    format date yymmddn8.;
    if first.gvkey then count=1;
    else count+1;
    drop INDFMT DATAFMT CONSOL POPSRC
        PSTKRV PSTKL PSTK TXDITC TXDB SEQ CEQ CEQL CSHPRI PRCC_F
        PS DEFTX SHE;
run;
%put ### DONE! ###;
proc printto;run;
%end;%else %do;
data out.&dsetout.;
    set compx;
run;
%end;
OPTIONS NOTES;
%PUT ### DONE CC_LINK ###;
%MEND CC_LINK;
