/*
Author: Edwin Hu
Date: 2013-05-24

# CC_LINK #

## Summary ##
Links COMPUSTAT GVKEYs to CRSP PERMNOs.

Takes a file which contains GVKEYs and dates and merges in the
appropriate PERMNOs. This handles a lot of silly merge issues.

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
    CREATE TABLE &dsetout. AS
    SELECT b.lpermno AS permno,
            b.lpermco as permco,
            a.*
    FROM &dsetin.(keep=GVKEY &datevar.
        &keep_vars.
        CUSIP CIK
        INDFMT DATAFMT CONSOL POPSRC
        %if &dsetin.=comp.funda %then %do;
        PSTKRV PSTKL PSTK TXDITC TXDB SEQ CEQ CEQL AT LT CSHPRI PRCC_F GP
        %end;
        %if &dsetin.=comp.fundq %then %do;
        ATQ LTQ IBQ RDQ
        %end;        
        ) AS a, crsp.ccmxpf_linktable AS b
    WHERE a.indfmt IN ('INDL','BANK','UTIL')
    AND a.datafmt = 'STD'
    AND a.popsrc = 'D'
    AND a.consol = 'C'
    AND a.gvkey=b.gvkey
    AND SUBSTR(b.linktype,1,1)='L' AND linkprim IN ('P','C')
    AND (b.LINKDT <= a.&datevar. or b.LINKDT = .B)
    AND (a.&datevar. <= b.LINKENDDT or b.LINKENDDT = .E)
    AND b.usedflag=1
    /* In some instances there are two datadates in a given year */
    /* for example, when a firm changes fiscal year there may be */
    /* two reports, but one of them is blank, so take the last   */
    /* report which contains the full report, e.g. GKVEY 013379  */
    /* around 1994 it switches from April to June.               */
    GROUP BY b.LPERMNO, YEAR(a.&datevar.)
    HAVING MAX(a.&datevar.)=a.&datevar.
    ORDER BY permno, a.&datevar.;
QUIT;

%if &dsetin.=comp.funda %then %do;
/* Compute Book Equity */
data &dsetout.;
    set &dsetout.;
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
    YEAR = year(datadate);
    label BE='Book Value of Equity Fiscal Year t-1' YEAR='Calendar Year';
    drop INDFMT DATAFMT CONSOL POPSRC
        PSTKRV PSTKL PSTK TXDITC TXDB SEQ CEQ CEQL CSHPRI PRCC_F
        PS DEFTX SHE;
run;
%end;

OPTIONS NOTES;
%PUT ### DONE ###;

%MEND CC_LINK;
