#lang racket/base
(require racket/sandbox)

(define e
  (make-module-evaluator
   '(module bug racket/base
      (require racket/control)
      (define foop (make-parameter #f))
      (define (doop)
        (reset
         (parameterize ((foop 0))
           (let loop ()
             (printf "foop = ~s\n" (foop))
             (foop (add1 (foop))) ;; mutate
             (shift k k)
             (loop))))))))


(e '(define asdf (doop)))
(e '(asdf))
(e '(asdf))
