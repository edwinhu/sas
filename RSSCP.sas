proc fcmp outlib=sasuser.temp.subr; 
 deletesubr rsscp; 
run; 
 
proc fcmp outlib=sasuser.temp.subr; 
 subroutine rsscp(nobs,ws,nv,_data[*,*],_rssc[*,*,*],_rsum[*,*]) varargs; 
 outargs _rssc,_rsum; 
 /* Arguments: */ 
 /* NOBS: Number of populated rows in _DATA matrix */ 
 /* WS: Window Size to develop */ 
 /* NV: N of variables (columns) in _DATA matrix */ 
 /* _DATA[*,*] Data Items passed to this subroutine */ 
 /* _RSSC[*,*,*] Rolling SSCP to return, */ 
 /* with dimensions NOBS,NV,NV */ 
 /* _RSUM[*,*] Rolling simple sums to return (NOBS,NV) */ 
 
 /* Generate Squares, Cross-Prods for row 1 only */ 
 do obs=1 to 1; 
 do r=1 to nv; 
 _rsum[obs,r] = _data[obs,r]; 
 _rssc[obs,r,r] = _data[obs,r]**2; 
 if r<nv then do c=r+1 to nv; 
 _rssc[obs,r,c] = _data[obs,r]*_data[obs,c]; 
 _rssc[obs,c,r] = _rssc[obs,r,c]; 
 end; 
 end; 
 end; 
 
 /* Starting at obs 2, add current SQ & CP to previous total */ 
 do obs=2 to ws; 
 do r=1 to nv; 
 _rsum[obs,r] = _rsum(obs-1,r) + _data[obs,r] ; 
 _rssc[obs,r,r] = _rssc[obs-1,r,r] + _data[obs,r]**2 ; 
 if r<nv then do c=r+1 to nv; 
 _rssc[obs,r,c] = _rssc[obs-1,r,c] +_data[obs,r]*_data[obs,c] ; 
 _rssc[obs,c,r] = _rssc[obs,r,c]; 
 end; 
 end; 
 end; 
 
 /* At obs ws+1 start subtracting observations leaving the window*/ 
 if nobs>ws then do obs=ws+1 to nobs; 
 do r=1 to nv; 
 _rsum[obs,r] = _rsum(obs-1,r) + _data[obs,r] - _data[obs-ws,r]; 
 _rssc[obs,r,r] = _rssc[obs-1,r,r] + _data[obs,r]**2 - _data[obs-ws,r]**2; 
 
 if r<nv then do c=r+1 to nv; 
  _rssc[obs,r,c] = _rssc[obs-1,r,c] + _data[obs,r]*_data[obs,c] 
 - _data[obs-ws,r]*_data[obs-ws,c]; 
 _rssc[obs,c,r] = _rssc[obs,r,c]; 
 end; 
 end; 
 end; 
 
endsub; 

