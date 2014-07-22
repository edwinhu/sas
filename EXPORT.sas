%MACRO EXPORT(lib=,dsetin=,
   dir=,outfile=,
   dbms=csv,
   format=,
   debug=n);

/* 

lib : input library
dsetin : input dataset
dir : output directory
outfile: output filename
format : output format (default csv)

*/

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

/**

* Sends the resulting spreadsheet from Unix to my inbox ;
data _null_;
   file sendit email
      to="eddyhu@gmail.com" 
      subject="Resulting Excel spreadsheet"
      attach=(
      "~/data_dictionary.xls"
      content_type="application/excel"
      );
   put "Attached is the Excel spreadsheet with the metadata for sashelp.demographics";
run;

**/
