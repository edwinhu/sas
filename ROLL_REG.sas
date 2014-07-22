%MACRO ROLL_REG(dsetin=,
	id=permno,
        date=date,
	y=exret,
	x=mktrf,
	ws=60,
	debug=n);

    ** Step 1: Generate Squares and Cross-Products **;
    data _roll_in / view=_roll_in;
        set &dsetin.(rename=(&id.=id &date.=date &y.=y &x.=x));
        xy=x*y;   xx=x*x;   yy=y*y;
    run;
    
    ** Step 2: Sum the squares and cross-products **;
    proc expand data=_roll_in out=_roll_sscp (where=(_n=&ws.)) method=none;
        by id ;
        id date;
        convert Y= _n / transformin=(*0) transformout=(+1 MOVSUM &ws.);
        convert x y xy xx yy / transformout=( MOVSUM &ws.);
    run;
    
    ** Step 3: Reshape the data into a TYPE=SSCP data set **;
    data _roll_rsscp (type=SSCP keep = id date _TYPE_ _NAME_ intercept x y)
        / view=_roll_rsscp;
        retain id date _TYPE_ _NAME_ intercept x y;
        set _roll_sscp;
        length _TYPE_ $8  _NAME_ $32 ;

        ** Store for later use **;
        _sumy=y;  _sumx=x;
        
        _TYPE_="SSCP"; /* For the record type, not the data set type*/
        ** First output record is just N, and sums already in each original variable **;
        _NAME_='Intercept';
        Intercept=_n;
        y=_sumy;  x=_sumx;
        output;
        _name_="X";
        intercept=_sumx; x=xx; y=xy;
        output;
        _name_="Y";
        intercept=_sumy; x=xy; y=yy;
        output;
        _TYPE_='N';
        _NAME_=' ';
        Intercept = _n; Y=_N; X=_N;
        output;
    run;
        
    proc reg data=_roll_rsscp noprint
        outest=roll_results(rename=(id=&id. date=&date. x=&x.)
          keep=id date Intercept x);
        by id date;
        model y=x;
    quit;
    
    %put;%put ### DONE! ###;
    
    %if %substr(%lowcase(&debug),1,1) = n %then %do;
        proc datasets memtype=view noprint;
            delete _roll:;
        quit;
    %end;
    
%MEND ROLL_REG;
