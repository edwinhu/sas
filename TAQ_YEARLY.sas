/*
Author: Edwin Hu
Date: 2013-05-24

# TAQ_YEARLY #

## Summary ##
Computes buys, sells, prices, and volume at a daily level from TAQ.

The macro does this 1 year at a time.

Runs on the WRDS-Cloud.

## Variables ##
- yyyy: year (Note: splitting it by year allows for parallel processing)
- outlib: library to save files to
- pre: output file prefix (regular, overnight, premarket)
- timefilter: which hours to use (see below)
- corrvar: quote correction flag
- condvar: sale condition var (see below)
- ex: exchange code ('A','N','T')
- modevar: deprecated

## Time Filter ##

Regular Hours: 09:30:00 to 16:29:59 (EST)

Pre-market Hours: 04:00:00 (varies by exchange) to 09:29:59 (EST)

Extended Trading Hours: 16:30:00 to 20:00:00 (varies)

## Sale Condition (COND)  ##

From what I understand this tells you how the trade will be
settled. Most of the time it is "regular" meaning the sale condition
variable is ' ' (blank), '@', or '*' (not in the data). Sometimes
the trade is settled in cash, done the next day, or some other
strange settlement type, so we ignore these because the sale
might have a different pricing scheme.

For Regular Trading Hours we use:
COND IN ('@',' ','*')

## Quote Condition (MODE) ##

This is deprecated since the WRDS WTAQ.WCT files already filter out
the non-NBBO quotes. Normally you have to check the TAQ manuals to
find out what counts as a valid quote. For instance from the 2008
manual on WRDS, valid NBBO quotes have MODE 1,2,6,12,23. 7 is
invalid because it is a quote during a market closure due to order
imbalance.

It is important to filter these out if working with the raw quotes
files because you get a lot of crazy quotes like 0 or 99999999.

## Usage ##
```
%INCLUDE "~/git/sas/TAQ_YEARLY.sas";
```
*/

%MACRO TAQ_YEARLY(yyyy=1993,
    outlib=/scratch/rice/eddy,
    pre=regular,
    timefilter= time GE "09:30:00"t and time LE "16:29:59"t,
    corrvar= and corr in (0,1),
    condvar= and cond in ('F','T','E','@F','FT','TE'),
    ex= and ex in ('A','N','T'),
    modevar = and mode not in (4,7,9,11,13,14,15,19,20,27,28)
    );

    libname wtaq "/wrds/nyse/sasdata/wrds_taqs_ct";
    libname out "&outlib.";

    %if &yyyy.<2000 %then %let sec=5;
    %else %if &yyyy. < 2007 %then %let sec=1;
    %else %let sec = 0;

    %do m=01 %to 12;
        %let mm = %sysfunc(putn(&m.,z2.));
        %do d=01 %to 31;
            %let dd = %sysfunc(putn(&d.,z2.));

            %if %sysfunc(exist(wtaq.wct_&yyyy.&mm.&dd.)) %then %do;

                /* Step 1: Lee and Ready Algorithm to classify trades */
                data Lee_Ready_&yyyy.&mm.&dd. / view=Lee_Ready_&yyyy.&mm.&dd. ;
                    set WTAQ.WCT_&yyyy.&mm.&dd. (where=( price>0 and size>0 &timefilter. &corrvar. &condvar. &ex. ));
                    by symbol date time;
                    retain last_dp midpoint;
                    if first.symbol then do;
                        last_dp = .;
                        end;

                    *Tick test with lagged variables;
                    tick2 = tick;
                    if tick=0 then tick2 = last_dp;
                    else last_dp = tick;

                      /* Lee and Ready Test */
                      /* Apply Quote Test first */
                      LeeReady=sign(Price-MidPoint&sec);
                      LeeReady2 = LeeReady;
                      /* Then, Apply Tick Test  */
                      if LeeReady=0 or LeeReady = . then LeeReady=TICK;                               *Tick is already generated on the WRDS-matched NBBO file;
                      if LeeReady2=0 or LeeReady2 = . then LeeReady2=tick2;                           *tick2 (uses lagged price change info as well);
                      qspread0 = qspread0/midpoint0;
                      espread0 = abs(price - midpoint0)/midpoint0;
                      if symbol = lag(symbol) then amihud = abs( price - lag(price))/(price*size);
                      keep symbol date time price size LeeReady espread0 amihud midpoint: qspread0 LeeReady2 tick tick2;
                run;

                  /* Step 2: Calculate Daily Buy and Sell Volumes */
                data &pre._&yyyy.&mm.&dd. / view = &pre._&yyyy.&mm.&dd.;
                    set Lee_Ready_&yyyy.&mm.&dd.;
                    by symbol date time;
                    retain N_TRADES SIZ_SUM VAL_SUM BUYS SELLS n_buys n_sells buyval sellval qs_sum es_sum ami_sum high low n_buys_tick n_sells_tick buys_tick sells_tick buyval_tick sellval_tick
                        n_buys2 n_sells2 buys2 sells2 buyval2 sellval2 n_buys_tick2 n_sells_tick2 buys_tick2 sells_tick2 buyval_tick2 sellval_tick2 ;
                    if first.date then do; N_TRADES=0; SIZ_SUM=0; VAL_SUM=0;
                        n_buys = 0; n_sells=0; Buys=0; sells =0; buyval=0; sellval=0;
                        n_buys2= 0; n_sells2=0; Buys2=0; sells2 =0; buyval2=0; sellval2=0;
                        n_buys_tick = 0; n_sells_tick=0; Buys_tick=0; sells_tick =0; buyval_tick=0; sellval_tick=0;
                        n_buys_tick2 = 0; n_sells_tick2=0; Buys_tick2=0; sells_tick2 =0; buyval_tick2=0; sellval_tick2=0;
                        qs_sum0=0; es_sum0=0; ami_sum0=0;
                        qs_sum=0; es_sum=0; ami_sum=0; high=.; low = .;
                        end;

                    N_TRADES+1;                          *Total trades (N);
                    SIZ_SUM+size;                        *Total volume (shares);
                    VAL_SUM+size*price;                  *Total volume (dollar);

                    n_buys+(LeeReady=1);                 *Total buy volume (N);
                    n_sells+(LeeReady=-1);               *Total sell volume (N);

                    n_buys2+(LeeReady2=1);               *Total buy volume (N);
                    n_sells2+(LeeReady2=-1);             *Total sell volume (N);

                    n_buys_tick + (tick=1);              *Total buy volume (N);
                    n_sells_tick + (tick=-1);            *Total sell volume (N);

                    n_buys_tick2+ (tick2=1);             *Total buy volume (N);
                    n_sells_tick2 + (tick2=-1);          *Total sell volume (N);

                    Buys+size*(LeeReady=1);              *Total buy volume (shares);
                    Sells+size*(LeeReady=-1);            *Total sell volume (shares);

                    Buys2+size*(LeeReady2=1);            *Total buy volume (shares);
                    Sells2+size*(LeeReady2=-1);          *Total sell volume (shares);

                    buys_tick + size*(tick=1);           *Total buy volume (shares);
                    sells_tick +size*(tick=-1);          *Total sell volume (shares);

                    buys_tick2 + size*(tick2=1);         *Total buy volume (shares);
                    sells_tick2 +size*(tick2=-1);        *Total sell volume (shares);

                    buyval+size*price*(LeeReady=1);      *Total buy volume (dollar);
                    sellval+size*price*(LeeReady=-1);    *Total sell volume (dollar);

                    buyval2+size*price*(LeeReady2=1);    *Total buy volume (dollar);
                    sellval2+size*price*(LeeReady2=-1);  *Total sell volume (dollar);

                    buyval_tick + size*price*(tick=1);   *Total buy volume (dollar);
                    sellval_tick+ size*price*(tick=-1);  *Total sell volume (dollar);

                    buyval_tick2 + size*price*(tick2=1); *Total buy volume (dollar);
                    sellval_tick2+ size*price*(tick2=-1);*Total sell volume (dollar);

                    VWAP=val_sum/siz_sum;                *Volume weighted average price;

                    qs_sum0 + qspread0;
                    ewqs = qs_sum0 / n_trades;              *Equal weighted average QS;

                    es_sum0 + espread0;
                    ewes = es_sum0 / n_trades;              *Volume weighted average ES;

                    ami_sum0 + amihud;
                    ewami = ami_sum0 / n_trades;            *Volume weighted average Amihud;

                    qs_sum + size*qspread0;
                    vwqs = qs_sum / siz_sum;                *Volume weighted (shares) average QS;

                    es_sum + size*espread0;
                    vwes = es_sum / siz_sum;                *Volume weighted (shares) average ES;

                    ami_sum + size*amihud;
                    vwami = ami_sum / siz_sum;              *Volume weighted (shares) average Amihud;

                    high = max(price, high);
                    low = min(price,low);
                    range = (high - low)/sqrt(val_sum);     *Range measure;
                    if last.date;
                    label Buys = "Total Buy Volume" Sells="Total Sell Volume" N_Trades="Number of Trades";
                    label SIZ_SUM="Total Volume" VAL_SUM="Total Dollar Volume";
                    label n_buys = "# of Buys" n_sells = "# of Sells";
                    label buyval = "Total Buy Volume ($)" sellval = "Total Sell Volume ($)";
                    label Price="Price at Period End" VWAP="Volume Weighted Average Price";
                    label vwqs = "VW Quoted Spread" vwes = "VW Eff Spread" vwami="VW Amihud" range="Range";
                    label ewqs = "EW Quoted Spread" ewes = "EW Eff Spread" ewami="EW Amihud";
                    format SIZ_SUM N_TRADES comma12. VAL_SUM dollar12. VWAP Price dollar8.2;
                    format Buys Sells comma12. buyval sellval dollar12.;
                    format Buys2 Sells2 comma12. buyval2 sellval2 dollar12.;
                    format Buys_tick Sells_tick comma12. buyval_tick sellval_tick dollar12.;
                    format Buys_tick2 Sells_tick2 comma12. buyval_tick2 sellval_tick2 dollar12.;
                    keep symbol date time buys sells VAL_SUM SIZ_SUM N_TRADES VWAP Price vwqs vwes vwami range ewqs ewes ewami n_buys n_sells buyval sellval n_buys_tick n_sells_tick buyval_tick sellval_tick buys_tick sells_tick
                        n_buys2 n_sells2 buys2 sells2 buyval2 sellval2 n_buys_tick2 n_sells_tick2 buyval_tick2 sellval_tick2 buys_tick2 sells_tick2 ;
                run;

                %end;
            %end;
        %end;

    /* Make yearly version */
    data out.&pre._&yyyy.;
        set &pre._&yyyy.:;
    run;

%MEND;
