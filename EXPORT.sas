/*
Author: Edwin Hu
Date: 2013-05-24

# EXPORT #

## Summary ##
Exports SAS Datasets to a variety of formats (.csv, .tsv, .dta, .xls, .xlsx)
and also exports the column descriptions to make it easy to port tables to
other data storage format.

## Variables ##
- lib: library where SAS file is located
- dsetin: SAS file to export
- dir: path to export file to (do not use quotes)
- outfile: name of file to create (do not include suffix)
- dbms: file format (e.g. .csv)
- format: manually set column formats using DATA Step format syntax
- debug: keep or delete temporary files

## Usage ##
```
%IMPORT "~/git/sas/EXPORT.sas";

%EXPORT(lib=user,dsetin=&syslast.,
                dir=/path/to/output/file,outfile=outfile,
                dbms=csv,
                format=,
                debug=n);

```
 */

%MACRO EXPORT(lib=,dsetin=,
   dir=,outfile=,
   dbms=csv,
   format=,
   debug=n);

/* Summarize dataset metadata */
proc sql;
   create view _data_info as
   select name as Column,
      label as Description,
      type as Column_Type,
      format,
      informat
   from sashelp.vcolumn
   where libname="%UPCASE(&lib.)" and memname="%UPCASE(&dsetin.)"
   ;
quit;

/* Create a standardized copy of the data
   this is important when there are 'special missing' numeric values
   which will print out as chars in the output and interfere with I/O
*/
data _std_&dsetin. / view = _std_&dsetin.;
   set &lib..&dsetin.;
   array a(*) _numeric_;
   do i=1 to dim(a);
   if a(i) <= .Z then a(i) = .;
   end;
   drop i;
   format _character_ $quote. &format.;
run;

%if %SUBSTR(%LOWCASE(&dbms.),1,1) = c %then %do;
/* Export CSVs */

proc export data=_data_info
   outfile="&dir./&outfile._desc.csv"
   dbms=csv replace;
run;

proc export data=_std_&dsetin.
   outfile="&dir./&outfile..csv"
   dbms=csv replace;
run;

%end;

%else %if %SUBSTR(%LOWCASE(&dbms.),1,1) = t %then %do;
/* Export TSVs */

proc export data=_data_info
   outfile="&dir./&outfile._desc.tsv"
   dbms=tab replace;
run;

proc export data=_std_&dsetin.
   outfile="&dir./&outfile..tsv"
   dbms=tab replace;
run;

%end;

%else %if %SUBSTR(%LOWCASE(&dbms.),1,1) = x | %SUBSTR(%LOWCASE(&dbms.),1,1) = e %then %do;
/* Export XLS with two sheets */

proc export data=_data_info
   outfile="&dir./&outfile..xlsx"
   dbms=xlsx replace;
   sheet="description";
run;

proc export data=_std_&dsetin.
   outfile="&dir./&outfile..xlsx"
   dbms=xlsx replace;
   sheet="data";
run;

%end;

%else %do;

/* Throw error if not implemented */
ERROR 'Other file formats not implemented';
%ABORT;

%end;

%if %SUBSTR(%LOWCASE(&dbms.),1,1) = n %then %do;

* Delete Description File ;

proc datasets nolist;
   delete _data_info, _std_&dsetin. / memtype=view;
run;

%end;

%MEND;
