/**********************************************************************************************/
/* FILENAME:        Winsorize_Truncate.sas                                                    */
/* ORIGINAL AUTHOR: Steve Stubben (Stanford University)                                       */
/* MODIFIED BY:     Ryan Ball (UNC-Chapel Hill)                                               */
/* DATE CREATED:    August 3, 2005                                                            */
/* LAST MODIFIED:   August 3, 2005                                                            */
/* MACRO NAME:      Winsorize_Truncate                                                        */
/* ARGUMENTS:       1) DSETIN: input dataset containing variables that will be win/trunc.     */
/*                  2) DSETOUT: output dataset (leave blank to overwrite DSETIN)              */
/*                  3) BYVAR: variable(s) used to form groups (leave blank for total sample)  */
/*                  4) VARS: variable(s) that will be winsorized/truncated                    */
/*                  5) TYPE: = W to winsorize and = T (or anything else) to truncate          */
/*                  6) PCTL = percentile points (in ascending order) to truncate/winsorize    */
/*                            values.  Default is 1st and 99th percentiles.                   */
/* DESCRIPTION:     This macro is capable of both truncating and winsorizing one or multiple  */
/*                  variables.  Truncated values are replaced with a missing observation      */
/*                  rather than deleting the observation.  This gives the user more control   */
/*                  over the resulting dataset.                                               */
/* EXAMPLE(S):      1) %Winsorize_Truncate(dsetin = mydata, dsetout = mydata2, byvar = year,  */
/*                          vars = assets earnings, type = W, pctl = 0 98)                    */
/*                      ==> Winsorizes by year at 98% and puts resulting dataset into mydata2 */
/**********************************************************************************************/

%macro Winsorize_Truncate(dsetin = , 
                          dsetout = , 
                          byvar = none, 
                          vars = , 
                          type = W, 
                          pctl = 1 99,
                          filter = and exchcd eq 1);

    %if &dsetout = %then %let dsetout = &dsetin;
    
    %let varL=;
    %let varH=;
    %let xn=1;


	/* This iterates over the list of input variables and creates */
	/* empty lists to store the Low and High quantiles for each   */
    %do %until (%scan(&vars,&xn)= );
        %let token = %scan(&vars,&xn);
        %let varL = &varL &token.L;
        %let varH = &varH &token.H;
        %let xn = %EVAL(&xn + 1);
    %end;

    %let xn = %eval(&xn-1);

    data xtemp;
        set &dsetin;

    %let dropvar = ;
    %if &byvar = none %then %do;
        data xtemp;
            set xtemp;
            xbyvar = 1;

        %let byvar = xbyvar;
        %let dropvar = xbyvar;
    %end;

    proc sort data = xtemp;
        by &byvar;

    /*compute percentage cutoff values*/
    proc univariate data = xtemp noprint;
        by &byvar;
        var &vars;
        where 1 &filter;
        output out = xtemp_pctl PCTLPTS = &pctl PCTLPRE = &vars PCTLNAME = L H;

    data &dsetout;
        merge xtemp xtemp_pctl; /*merge percentage cutoff values into main dataset*/
        by &byvar;
        array trimvars{&xn} &vars;
        array trimvarl{&xn} &varL;
        array trimvarh{&xn} &varH;

        do xi = 1 to dim(trimvars);
            /*winsorize variables*/
            %if &type = W %then %do;
                if trimvars{xi} ne . then do;
                    if (trimvars{xi} < trimvarl{xi}) then trimvars{xi} = trimvarl{xi};
                    if (trimvars{xi} > trimvarh{xi}) then trimvars{xi} = trimvarh{xi};
                end;
            %end;
            /*truncate variables*/
            %else %do;
                if trimvars{xi} ne . then do;
                    /*insert .T code if value is truncated*/
                    if (trimvars{xi} < trimvarl{xi}) then trimvars{xi} = .T;
                    if (trimvars{xi} > trimvarh{xi}) then trimvars{xi} = .T;
                end;
            %end;
        end;
        drop &varL &varH &dropvar xi;

    /*delete temporary datasets created during macro execution*/
    proc datasets library=work nolist;
        delete xtemp xtemp_pctl; quit; run;

%mend;
