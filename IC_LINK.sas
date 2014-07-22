%MACRO IC_LINK(
               lib = USER,
               inames = ibes.idsum,
               cnames = crsp.stocknames,
               debug = n
               );

    %local dsid num rc;
    %local oldoptions errors;
    %let oldoptions=%sysfunc(getoption(mprint)) %sysfunc(getoption(notes))
                    %sysfunc(getoption(source));
    %let errors=%sysfunc(getoption(errors));
    options nonotes nomprint nosource errors=0;

    %macro print(str);
        %put; %put &str.; %put;
    %mend;

    %print(### STEP 1. CUSIP LINK );
    /* IBES: Get the list of IBES TICKERS for US firms in IBES */
    proc sort data=&inames.
        out=_icusip1 (keep=ticker cusip cname sdates);
        where usfirm=1 and not(missing(cusip));
        by ticker cusip sdates;
    run;

    /* Create first and last 'start dates' for CUSIP link */
    proc sql;
        create table _icusip2
        as select *,
            min(sdates) as fdate,
            max(sdates) as ldate
        from _icusip1
        group by ticker, cusip
        order by ticker, cusip, sdates
        ;
    quit;

    /* Label date range variables and keep only most recent company name for CUSIP link */
    data _icusip2;
        set _icusip2;
        by ticker cusip;
        if last.cusip;
        label fdate="First Start date of CUSIP record";
        label ldate="Last Start date of CUSIP record";
        format fdate ldate yymmdd10.;
        drop sdates;
    run;
    %let dsid=%sysfunc(open(&syslast.));
    %let num=%sysfunc(attrn(&dsid,nlobs));
    %let rc=%sysfunc(close(&dsid));
    %print(    &num. IBES CUSIPs);

    /* CRSP: Get all PERMNO-NCUSIP combinations */
    proc sort data=&cnames.
        out=_ccusip1 (keep=permno ncusip comnam namedt nameenddt);
        where not missing(ncusip);
        by permno ncusip namedt;
    run;

    /* Arrange effective dates for CUSIP link */
    proc sql;
        create table _ccusip2
        as select permno,ncusip,comnam,
            min(namedt)as namedt,
            max(nameenddt) as nameenddt
        from _ccusip1
        group by permno, ncusip
        order by permno, ncusip, namedt
        ;
    quit;

    /* Label date range variables and keep only most recent company name */
    data _ccusip2;
    set _ccusip2;
        by permno ncusip;
        if last.ncusip;
        label namedt="Start date of CUSIP record";
        label nameenddt="End date of CUSIP record";
        format namedt nameenddt yymmdd10.;
    run;
    %let dsid=%sysfunc(open(&syslast.));
    %let num=%sysfunc(attrn(&dsid,nlobs));
    %let rc=%sysfunc(close(&dsid));
    %print(    &num. CRSP CUSIPs);

    /* Create CUSIP Link Table */
    /* CUSIP date ranges are only used in scoring as CUSIPs are not reused for
        different companies overtime */
    proc sql;
        create table _clink1
        as select *
        from _icusip2 as a, _ccusip2 as b
        where a.cusip = b.ncusip
        order by ticker, permno, ldate
        ;
    quit;

    /* Score links using CUSIP date range and company name spelling distance */
    /* Idea: date ranges the same cusip was used in CRSP and IBES should intersect */
    data _clink2;
        set _clink1;
        by ticker permno;
        if last.permno; * keep link with most recent company name;
        name_dist = min(spedis(cname,comnam),spedis(comnam,cname));
        if (not ((ldate<namedt) or (fdate>nameenddt))) and name_dist < 30 then score = 0;
        else if (not ((ldate<namedt) or (fdate>nameenddt))) then score = 1;
        else if name_dist < 30 then score = 2;
        else score = 3;
        keep ticker permno cname comnam score;
    run;
    %let dsid=%sysfunc(open(&syslast.));
    %let num=%sysfunc(attrn(&dsid,nlobs));
    %let rc=%sysfunc(close(&dsid));
    %print(    &num. IBES TICKERs matched to CRSP PERMNOs );

    %print(### Step 2: Find links for the remaining unmatched cases using Exchange Ticker );
    /* Identify remaining unmatched cases */
    proc sql;
        create table _cnomatch1
        as select distinct a.*
        from _icusip1 (keep=ticker) as a
        where a.ticker not in (select ticker from _clink2)
        order by a.ticker;
    quit;
    %let dsid=%sysfunc(open(&syslast.));
    %let num=%sysfunc(attrn(&dsid,nlobs));
    %let rc=%sysfunc(close(&dsid));
    %print(    &num. IBES TICKERs not matched with CRSP PERMNOs using CUSIP );

    /* Add IBES identifying information */
    proc sql;
        create table _cnomatch2
        as select b.ticker, b.CNAME, b.OFTIC, b.sdates, b.cusip
        from _cnomatch1 as a, &inames. as b
        where a.ticker = b.ticker and not (missing(b.OFTIC))
        order by ticker, oftic, sdates;
    quit;

    /* Create first and last 'start dates' for Exchange Tickers */
    proc sql;
        create table _cnomatch3
        as select *, min(sdates) as fdate, max(sdates) as ldate
        from _cnomatch2
        group by ticker, oftic
        order by ticker, oftic, sdates
        ;
    quit;

    /* Label date range variables and keep only most recent company name */
    data _cnomatch3;
        set _cnomatch3;
        by ticker oftic;
        if last.oftic;
        label fdate="First Start date of OFTIC record";
        label ldate="Last Start date of OFTIC record";
        format fdate ldate yymmdd10.;
        drop sdates;
    run;

    /* Get entire list of CRSP stocks with Exchange Ticker information */
    proc sort data=&cnames.
        out=_cticks1 (keep=ticker comnam permno ncusip namedt nameenddt);
        where not missing(ticker);
        by permno ticker namedt;
    run;

    /* Arrange effective dates for link by Exchange Ticker */
    proc sql;
        create table _cticks2
        as select permno,comnam,ticker as crsp_ticker,ncusip,
        min(namedt)as namedt,max(nameenddt) as nameenddt
        from _cticks1
        group by permno, ticker
        order by permno, crsp_ticker, namedt;
    quit; * CRSP exchange ticker renamed to crsp_ticker to avoid confusion with IBES TICKER;

    /* Label date range variables and keep only most recent company name */
    data _cticks2;
        set _cticks2;
        if  last.crsp_ticker;
        by permno crsp_ticker;
        label namedt="Start date of exch. ticker record";
        label nameenddt="End date of exch. ticker record";
        format namedt nameenddt yymmdd10.;
    run;

    /* Merge remaining unmatched cases using Exchange Ticker */
    /* Note: Use ticker date ranges as exchange tickers are reused overtime */
    proc sql;
        create table _tlink1
        as select a.ticker,a.oftic, b.permno, a.cname, b.comnam, a.cusip, b.ncusip, a.ldate
        from _cnomatch3 as a, _cticks2 as b
        where a.oftic = b.crsp_ticker and
         (ldate>=namedt) and (fdate<=nameenddt)
        order by ticker, oftic, ldate;
    quit;

    /* Score using company name using 6-digit CUSIP and company name spelling distance */
    data _tlink2;
        set _tlink1;
        name_dist = min(spedis(cname,comnam),spedis(comnam,cname));
        if substr(cusip,1,6)=substr(ncusip,1,6) and name_dist < 30 then score=0;
        else if substr(cusip,1,6)=substr(ncusip,1,6) then score = 4;
        else if name_dist < 30 then score = 5;
        else score = 6;
    run;

    /* Some companies may have more than one TICKER-PERMNO link,         */
    /* so re-sort and keep the case (PERMNO & Company name from CRSP)    */
    /* that gives the lowest score for each IBES TICKER (first.ticker=1) */
    proc sort data=_tlink2; by ticker score; run;
    data _tlink3;
        set _tlink2;
        by ticker score;
        if first.ticker;
        keep ticker permno cname comnam permno score;
    run;
    %let dsid=%sysfunc(open(&syslast.));
    %let num=%sysfunc(attrn(&dsid,nlobs));
    %let rc=%sysfunc(close(&dsid));
    %print(    &num. new matches of IBES TICKERs to CRSP EXCHANGE TICKERS );

    %print(### Step 3: Add Exchange Ticker links to CUSIP links );
    /* Create final link table and save it in home directory */
    data &lib..iclink;
    set _clink2 _tlink3;
    run;
    proc sort data=&syslast.; by ticker permno; run;
    %let dsid=%sysfunc(open(&syslast.));
    %let num=%sysfunc(attrn(&dsid,nlobs));
    %let rc=%sysfunc(close(&dsid));
    %print(    &num. IBES-CRSP links in &syslast. );

    /* Create Labels for ICLINK dataset and variables */
    proc datasets lib=&lib. nolist;
        modify iclink (label="IBES-CRSP Link Table");
            label CNAME = "Company Name in IBES";
            label COMNAM= "Company Name in CRSP";
            label SCORE= "Link Score: 0(best) - 6";
        run;
    quit;

    %if %substr(%lowcase(&debug),1,1) = n %then %do;
        %print(### Step 4. Deleting temporary datasets );
        proc datasets nolist;
        delete _icusip: _ccusip:
            _clink: _tlink:
            _cticks: _cnomatch:
            ;
        quit;
    %end;
    options errors=&errors &oldoptions;

%MEND IC_LINK;
