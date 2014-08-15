/*
Author: Edwin Hu
Date: 2013-05-24

# SAS2POSTGRE #

## Summary ##
Exports SAS dataset to PostgreSQL database

## Variables ##
- lib: default library (USER)
- dsetin: input dataset
- server: Postgresql server address (localhost)
- port: Postgresql port number (5432)
- user: Postgresql user
- pass: Postgresql user password
- db: Postgresql database
- format: format statement for SAS dataset columns
- rename: rename statement for SAS dataset columns
- debug: debug mode (n)

## Usage ##
```
%IMPORT "~/git/sas/SAS2POSTGRE.sas";

%SAS2POSTGRE(lib=USER,dsetin=&syslast.,
                    server=localhost, port=5432,
                    user=eddyhu, pass='asdf', db=wrds,
                    format=,rename=,debug=n);
```
 */
%MACRO SAS2POSTGRE(lib=USER,dsetin=&syslast.,
                    server=localhost, port=5432,
                    user=eddyhu, pass='asdf', db=wrds,
                    format=,rename=,debug=n);

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
