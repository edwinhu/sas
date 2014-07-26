/*******************READ ME*********************************************
* - Macro to bulk load write to PostgreSQL without ODBC -
*
* SAS VERSION:    9.4.0
* Postgre VERSION: 9.2.4
* DATE:           2013-12-19
* AUTHOR:         eddyhu@gmail.com
*
****************END OF READ ME******************************************/

%MACRO SAS2POSTGRE(lib=USER,dsetin=&syslast.,
                    server=localhost, port=5432,
                    user=eddyhu, pass='asdf', db=wrds,
                    format=,rename=,debug=n);
   /*****************************************************************
   *  MACRO:      SAS2POSTGRE()
   *  GOAL:       output a dataset in SAS to a table in PostgreSQL
   *  PARAMETERS: libname     = SAS library (default USER)
   *              dsetin      = SAS dataset to export
   *              server      = Postgre server address (default localhost)
   *              port        = Postgre server port (default 5432)
   *              user        = Postgre username
   *              pass        = Postgre user password
   *              db          = Postgre database
   *              format      = DATA step format statement (optional)
   *              rename      = DATA step rename statement (optional)
   *              debug       = if y then send BULKLOAD trace info to SAS log
   *                            useful for figuring out if you have badly formatted
   *                            columns, and if so what specific row is being rejected
   *
   *   NOTE:      The BULKLOAD options are hardcoded and should be modified
   *              to suit your system.
   *
   *              BL_PSQL_PATH  = Exact path to the psql batch (default psql)
   *                              can be removed if PostgreSQL\x.x\bin\ is in your %PATH%
   *              BL_DELETE_DATAFILE = If YES deletes generated logs/flat files
   *              BL_DEFAULT_DIR     = Directory to write logs/flat files (default %TEMP%)
   *****************************************************************/

%if %SUBSTR(%LOWCASE(&debug.),1,1) = n %then %do;
    options sastrace=',,,d' sastraceloc=saslog;
%end;

* Connection string;
libname pgdb postgres server=&server. port=&port.
   user=&user. password=&pass. database=&db. autocommit=no;

* Make a temp dataset with the correct data environment
   and format columns to bulk load into Postgre;
data _data_f / view=_data_f;
    set &lib..&dsetin.;
    &format.
    &rename.
run;

* Drop the table if it exists and bulk load the temp dataset;
ods listing close;
proc sql dquote=ansi;
    drop table pgdb.&dsetin.;
    create table pgdb.&dsetin.(
        BULKLOAD=YES
        BL_PSQL_PATH='psql'
        BL_DELETE_DATAFILE=NO
        BL_DEFAULT_DIR='/mnt/data/SASTemp/'
        )
    as select * from _data_f;

    drop view _data_f;

quit;
* Close session;
LIBNAME pgdb CLEAR;

ods listing;

%put;%put Table &dsetin. created on &server. &db.;

%MEND SAS2POSTGRE;
