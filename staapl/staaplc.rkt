#!/usr/bin/env racket
#lang racket/base

;; The 'Staapl Compiler' command line tool.
;;
;; Provides a standard command line interface to all (compilation)
;; functionality.  It is invoked as:
;;
;;   racket -l staapl/staaplc -- <arg> ...

;; The dictionary file produced is a mzscheme module that when invoked
;; produces a REPL to a live target.  This makes it possible to lift
;; any kind of behaviour from project source files to actual REPL
;; behaviour.

;; However, it can be interpreted as a data file by observing the
;; following structure:

;;   * The first line contains the PLT Scheme #lang construct and can
;;     be skipped using the 'read-line function.

;;   * The first scheme form accessible using 'read is a 'begin form
;;     containing only data definitions (define <name> (quote <datum>))

;;   * The second form accessible through 'read contains a 'require
;;     statement which imports the bindings for the target language in
;;     which the project is written, and interaction code.

;;   * Subsequent forms contain opaque scheme code necessary to
;;     configure and optionally start the console command interpreter
;;     using the data provided in the previous forms.




(require scheme/pretty  ;; racket/pretty prints quotes!
         racket/cmdline
         staapl/tools)

(define-syntax-rule (flags: name ...)
  (begin (define name (make-parameter #f)) ...))

(flags: output-hex
        output-dict
        console
        device
        baud
        filename
        print-asm
        debug-script
        dict-suffix
        debug-suffix
        )

;; Defaults
; (device "/dev/staapl0")
(baud #f)
(print-asm void)
(dict-suffix ".dict")
(debug-suffix ".rkt")

(define (get-arguments)
  (filename
   (command-line

    #:program "staaplc"
    
    #:once-each
    [("-o" "--output-hex") filename "Output Intel HEX file."
     (output-hex filename)]

    [("--print-code") "Print assembly and binary code output."
     (print-asm (lambda () (eval '(code-print))))]

    [("-c" "--comm") filename "Console port. (default: pickit2)"  (console (string->symbol filename))]

    [("-d" "--device") filename "Console system device. (default: /dev/staapl0)"  (device filename)]
    
    [("--baud") number   "Console baud rate. (default from source file)" (baud (string->number number))]
    
    [("-d" "--output-dict") filename "Output dictionary file."
     (output-dict filename)]

    #:args (fname)
    fname)))



 
(define (out param template suffix)
  (let ((p (param)))
    (unless p
      (param
       (let-values (((base name _) (split-path template)))
         (path-replace-suffix name suffix))))))

;; (*) The extension .ss is too confusing.  This is a generated file,
;; which should be removable by a simple rm *.<ext> in a Makefile.

(define (absolute param)
  (let ((p (param)))
    (param
     (if (absolute-path? p)
         (string->path p)
         (path->complete-path p)))))

(define (dir-of path)
  (let-values (((base name _) (split-path path)))
    base))

(define (requirements kernel-path)
  `(require
    staapl/live-pic18
    (file ,(path->string kernel-path))))

(define (process-arguments)
  (out output-hex (filename) ".hex")
  (out output-dict (filename) (dict-suffix)) ;; (*)
  (out debug-script (filename) (debug-suffix))

  ;; Why do these need to be absolute?
  (absolute filename)
  (absolute output-hex)
  (absolute output-dict)
  (absolute debug-script)
  )

(define (warnf . args)
  (display "WARNING: ")
  (apply printf args))


;; Figure out console config
(define (console-spec)

  ;; Unless overridden by command line arguments, get the console
  ;; specs from the Forth source files.
  (define (spec-from-source param id)
    (unless (param)
      (let ((v (eval `(macro-constant ',id))))
        (when v (param v)))))

  (define (device-string x)
    (if (symbol? x) (symbol->string x) x))

  (spec-from-source console 'console-type)
  (spec-from-source device  'console-device)
  (spec-from-source baud    'console-baud)
  
  `(console ',(console) ,(device-string (device)) ,(baud)))


(define (instantiate-and-save)
  ;;(printf "in:  ~a\n" (filename))
  ;;(printf "out: ~a ~a\n" (output-hex) (output-dict))

  (unless (file-exists? (filename))
    (printf "input file not found: ~a\n" (filename))
    (exit 1))


  (parameterize
      ((current-namespace
        (make-base-namespace)))

    ;; Load necessary code.
    (eval (requirements (filename)))

    ;; Optionally print assembler code.
    ((print-asm))  
    

    ;; Save binary output.
    (with-output-to-file/safe
     (output-hex)
     (lambda ()
       (eval '(write-ihex (code->binary)))))

    ;; Save symbolic output.
    (let* ((reqs (requirements (filename)))
           (boot-run
            `(begin
               ,(console-spec)
               (require readline/rep)
               (param-to-toplevel 'command repl-command-hook)
               (param-to-toplevel 'break   repl-break-hook)
               (forth-begin-prefix '(library "pic18")) ;; add library path
               (run
                (lambda ()
                  ;; After loading the .fm file the code buffer
                  ;; contains target code.  Get rid of it.
                  (code-clear!)
                  ;; Delete all target scratch buffer code past the
                  ;; 'code pointer.
                  (clear-flash)
                  ;; Load host debug script into toplevel namespace on
                  ;; a clean target.
                  (when-file ',(path->string (debug-script)) load)))))
            
           ;; formatting
           (save
            (lambda (text [code #f])
              (display text)
              (newline)
              (when code
                (pretty-print code))))
           (save-module
            (lambda ()
              (save "#!/usr/bin/env racket")
              (save "#lang scheme/load")  ;; (2)
              (save ";; Language" reqs)
              (save ";; Console"  boot-run))))
      
      (with-output-to-file/safe
       (output-dict)
       save-module))))

;; (1) Saving the addresses is not necessary if source code and target
;; are kept in sync.  When the interactive script is started,
;; everything will be simply re-compiled.  However, to enable a
;; scenario where code has changed internally, but the procedure
;; _interface_ hasn't, we save the addresses as they are on the
;; target.

;; (2) For interactive development we're using a toplevel namespace
;; instead of a (static) module namespace.


;; Toplevel actions
(define (main)
  (get-arguments)
  (process-arguments)
  (instantiate-and-save))

;; TESTING
;(current-command-line-arguments
; (vector "-m" "/home/tom/staapl/app/1220-8.fm"))

(main)






