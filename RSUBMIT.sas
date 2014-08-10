/*
Author: Edwin Hu
Date: 2013-05-24

RSUBMIT Library for SAS
*/

%MACRO SIGNON(
              ident=~/.ssh/wrds_pass.sas,
              server=wrds.wharton.upenn.edu,
              port=4016,
              user=eddyhu
              );
/*
# SIGNON #

## Summary ##
Remote submit signon wrapper.

## Variables ##
- ident: identity file location
- server: server address
- port: server port
- user: user name

## Usage ##
```
%IMPORT "~/git/sas/RSUBMIT.sas";

%SIGNON(
        ident=~/.ssh/wrds_pass.sas,
        server=wrds.wharton.upenn.edu,
        port=4016,
        user=eddyhu
        );
```
 */
        SIGNOFF;
        %INCLUDE "&ident.";
        options comamid=TCP remote=&server. &port.;
        signon username="&user." password="&wrds_pass.";
%MEND;


%MACRO RSUBMIT(dir=);
/*
# RSUBMUT #

## Summary ##
Remote submit wrapper.

## Variables ##
- dir: remote directory

## Usage ##
```
%IMPORT "~/git/sas/RSUBMIT.sas";

%SIGNON(dir=/sastemp7/eh7/
        );
```
*/


/* Set remote directory on server side */
%syslput remote_dir=&dir;

RSUBMIT;

/* Check if directory exists on the remote server and if not create it and set the library */
/* Also set home directory, other libraries, etc.                                          */
%MACRO init(dir=) ;
    /**/
    %LOCAL rc fileref ;
    %LET rc = %SYSFUNC(filename(fileref,&remote_dir)) ;
    %IF %SYSFUNC(fexist(&fileref))  %THEN
        %PUT NOTE: The directory "&remote_dir" exists ;
    %ELSE
    %DO ;
    %SYSEXEC mkdir &remote_dir ;
    %PUT %SYSFUNC(sysmsg()) The directory dhas been created. ;
    %END ;
    %LET rc=%SYSFUNC(filename(fileref)) ;

%MEND init ;

    /* Note: this is done on the server side */
    %init(dir=&remote_dir.);

    libname out &remote_dir.;
    options user="&remote_dir.";
    libname home "~";

%MEND RSUBMIT;
