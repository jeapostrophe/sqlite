#lang setup/infotab
(define name "SQLite 3 FFI")
(define release-notes
  (list '(ul
          (li "Allowing negative INTEGER column values"))))
(define repositories
  (list "4.x"))
(define blurb
  (list "Allows access to SQLite databases."))
(define scribblings '(("sqlite.scrbl" ())))
(define primary-file "sqlite.ss")
(define categories '(io))