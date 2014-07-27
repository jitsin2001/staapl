staapl pic18/double-math
staapl pic18/double-pred
staapl pic18/execute
staapl pic18/mem16
staapl pic18/cond
staapl pic18/compose-macro


\ A direct threaded Forth using native code primitives.  NEXT is
\ procedure return to an explicit interpreter loop.

\ This is a DTC variant, so no execution from RAM on the PIC.
\ Execution tokens are 16 bit Flash byte addresses.

\ Going for simple code here.  Can be made faster.


: IP@    fl @ fh @ ;  \ -- lo hi
: IP!    fh ! fl ! ;  \ lo hi --
: _exit  _r> IP! ;    \ --
: fetch  @f+ @f+ ;    \ -- lo hi
: jump   fetch IP! ;  \ --
: 0jump  or nfdrop z? if jump ; then fetch _drop ; \ lo hi --
    
: enter
    IP@ _>r
    TOSL fl @!  \ TOS cannot be movff dst, but src is ok       
    TOSH fh @!
    pop ;   
  
\ Return stack
: _>r    >r >r ;
: _r>    r> r> ;    
: _rdrop rdrop rdrop ;
: _r     rl rh ;

    
    
\ Macros to create DTC words in staapl code.
\ To compile from outer interpreter:
\  _foo is a macro then use as is
\  _foo is a target word then replace with:  ' _foo _compile
macro
: cw>label  word>m m> ;
: label,    2 * ,, ; \ store byte addresses    
: _compile  i cw>label label, ;
: _literal  >m ' fetch _compile m> ,, ;     
: _if       ' 0jump _compile make-label dup >m label, ;
: _then     then ;  \ includes end:
: _begin    begin ; \ includes enter:
: _again    ' jump  _compile m> label, ;
: _until    ' 0jump _compile m> label, ;    
forth
    
    
\ Trampoline entry from native code.  The 'interpret' word will run a
\ dtc primitive or primitive wrapped program as "<xt> bye"
: interpret     \ ( lo hi -- )
    bye>r       \ push original IP, IP=bye
    execute/b   \ invoke the XT (primitive or high level word's enter)
    thread-loop ;
: thread-loop   \ execute token thread
    begin fetch execute/b again
: bye>r
    enter
    ' _bye _compile ;
: _bye
    _exit  \ pop original IP
    pop ;  \ break out of thread-loop

