#lang setup/infotab
(define name "SQLite 3 FFI")
(define release-notes
  (list '(ul
          (li "Rackety"))))
(define repositories
  (list "4.x"))
(define blurb
  (list "Allows access to SQLite databases."))
(define scribblings '(("sqlite.scrbl" ())))
(define primary-file "sqlite.rkt")
(define categories '(io))