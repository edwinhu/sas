/*
Author: Edwin Hu
Date: 2013-05-24

# COMP_EAD #

## Summary ##
Gets quarterly earnings announcement dates from COMPUSTAT and
fetches CRSP PERMNOs. Makes a file `comp_ead_events`.

## Variables ##
- comp_vars: list of COMPUSTAT variables to fetch
- filter: filters to place on COMPUSTAT quarterly

## Usage ##
```
%IMPORT "~/git/sas/COMP_EAD.sas";

%COMP_EAD(comp_vars=gvkey fyearq fqtr conm datadate rdq
                                epsfxq epspxq
                        prccq ajexq
                        spiq cshoq cshprq cshfdq
                        saleq atq
                        fyr datafqtr,
                        filter=not missing(saleq) or atq>0
                        );

* Now do stuff with comp_ead_events file ;
```
*/

%MACRO COMP_EAD(comp_vars=gvkey fyearq fqtr conm datadate rdq
                                epsfxq epspxq
                        prccq ajexq
                        spiq cshoq cshprq cshfdq
                        saleq atq
                        fyr datafqtr,
                        filter=not missing(saleq) or atq>0
                        );

    %put;%put Merging comp.fundq with CCM linking table;
        proc sql;
                drop table comp_ead;
                drop table _comp_ead, _ead;

            create table _comp_ead as
            select a.gvkey, a.datadate, a.rdq,
                    b.lpermno as permno, b.lpermco as permco,
                /*Compustat variables*/
                (a.cshoq*a.prccq) as mcap, a.*
            from comp.fundq(where=(&filter.)) as a,
                ccm.ccmxpf_linktable as b
            where a.indfmt = 'INDL'
            and a.datafmt = 'STD'
            and a.popsrc = 'D'
            and a.consol = 'C'
            and substr(b.linktype,1,1)='L'
            and b.linkprim in ('P','C')
            and b.usedflag = 1
            and (b.LINKDT <= a.datadate or b.LINKDT = .B)
            and (a.datadate <= b.LINKENDDT or b.LINKENDDT = .E)
            and a.gvkey = b.gvkey
            and a.rdq IS NOT NULL
            ;

            create table _ead as
            select a.*, b.date as rdq_adj
                format=yymmdd10. label='Adjusted Report Date of Quarterly Earnings'
            from (select distinct rdq from _comp_ead) a
        left join (select distinct date from crsp.dsi) b
        on 5>=b.date-a.rdq>=0
        group by rdq
        having b.date-a.rdq=min(b.date-a.rdq)
        ;

        create table _comp_ead_events
                (keep=gvkey datadate rdq rdq_adj
                permno permco event_id mcap prccq &comp_vars.) as
        select a.*, b.rdq_adj
        from _comp_ead as a left join _ead as b
        on a.rdq = b.rdq
        order by a.gvkey, a.fyearq desc, a.fqtr desc
        ;
    quit;

   %put;%put Checking for duplicates and outputting;
        proc sort data=_comp_ead_events
                out=comp_ead_events nodupkey;
                by permno rdq_adj;
        run;

        data comp_ead_events;
                set comp_ead_events;
                event_id = _N_;
                label event_id="Unique Event Identifier";
        run;

    proc sql;
        drop table _comp_ead_events, _comp_ead, _ead;
        quit;

    %put;%put COMP_EAD created;
%MEND COMP_EAD;
