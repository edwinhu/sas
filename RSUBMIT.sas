%MACRO RSUBMIT(dir=);
/*

EDITED: 2013-11-26

A macro that extends RSUBMIT

Creates a working directory &dir. if it does not exist
and assigns the user library to it.

&dir. can be accessed via the libname out.
The home directory on the server can be accssed via libname home.

*/


/* Note: this is done on the local side */
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

    /* Note: this is done on the remote side */
    %init(dir=&remote_dir.);

    libname out &remote_dir.;
    options user="&remote_dir.";
    libname home "~";

%MEND RSUBMIT;