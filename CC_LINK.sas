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

%MACRO CC_LINK(dsetin=&syslast.,
               dsetout=compx,
               datevar=datadate,
               keep_vars=
               );

OPTIONS NONOTES;

/* If PERMNO is the primary key, then the CRSP Manual recommends              */
/* forming GVKEY-PERMNO links where the USEDFLAG=1, which is unique           */
/* See: http://www.crsp.chicagobooth.edu/documentation/product/ccm/crsp_link/ */

PROC SQL;
    CREATE TABLE &dsetout. AS
    SELECT b.lpermno AS permno,
            b.lpermco as permco,
            a.*
    FROM &dsetin.(keep=gvkey &datevar.
                    &keep_vars.
                    indfmt
                    datafmt
                    consol
                    popsrc
                    cusip cik
                    ) AS a, ccm.ccmxpf_linktable AS b
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
    ORDER BY a.&datevar., permno;
QUIT;

OPTIONS NOTES;

%MEND CC_LINK;
