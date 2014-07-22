%MACRO DOWNLOAD(
        inlib=,outlib=,
        inset=,outset=,
        index=YES
        );

        %SYSLPUT inlib=&inlib.;
        %SYSLPUT outlib=&outlib.;
        %SYSLPUT inset=&inset.;
        %SYSLPUT outset=&outset.;
        %SYSLPUT index=&index.;

        RSUBMIT;

        PROC DOWNLOAD
        %if not(%sysevalf(%superq(index)=,boolean)) %then %do ;
                index=&index.
        %end;
        %if not(%sysevalf(%superq(inlib)=,boolean)) %then %do ;
                inlib=&inlib.
        %end;
        %if not(%sysevalf(%superq(outlib)=,boolean)) %then %do ;
                outlib=&outlib.
        %end;
        %if not(%sysevalf(%superq(inset)=,boolean)) %then %do ;
                data=&inset.
        %end;
        %if not(%sysevalf(%superq(outset)=,boolean))
                and %sysevalf(%superq(index)=,boolean)
        %then %do ;
                out=&outset.
        %end;

                ;
        RUN;

        ENDRSUBMIT;
%MEND;
