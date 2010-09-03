#lang racket
(require rackunit)
(require "sqlite.rkt")

(provide sqlite-tests)

(define test-db "test.db")
(define test-journal (format "~a-journal" test-db))

(define (delete-file* p)
  (when (file-exists? p)
    (delete-file p)))

(define (clean)
  (delete-file* test-db)
  (delete-file* test-journal))

(define (with-dummy-database test)
  (define db #f)
  (dynamic-wind
   (lambda ()
     (clean)
     (set! db (open (string->path test-db)))
     (exec/ignore db "CREATE TABLE user ( user_id INTEGER PRIMARY KEY, name TEXT )")
     (insert db "INSERT INTO user (name) VALUES ('noel')")
     (insert db "INSERT INTO user (name) VALUES ('matt')")
     (insert db "INSERT INTO user (name) VALUES ('dave')"))
   (lambda ()
     (test db))
   (lambda ()
     (with-handlers ([exn:fail? void]) (close db))
     (clean))))

(define (member? key lst)
  (if (member key lst) #t #f))


(define sqlite-tests
  (test-suite
   "All tests for sqlite"
   #:before clean
   #:after clean
   
   (test-case
    "Open and close"
    (let ((db (open (string->path test-db))))
      (close db)
      (clean)))
   
   (test-case
    "Open and close (in memory)"
    (let ((db (open ':memory:)))
      (close db)))
   
   (test-case
    "Open and close (tmp on disk)"
    (let ((db (open ':temp:)))
      (close db)))
   
   (test-case
    "Table creation w/ exec/ignore"
    (let ((db (open (string->path test-db))))
      (exec/ignore db "CREATE TABLE user ( user_id INTEGER, name TEXT )")
      (close db)
      (clean)))
   
   (test-case
    "Insertion and selection"
    (let ((db (open (string->path test-db))))
      (exec/ignore db "CREATE TABLE user ( user_id INTEGER, name TEXT )")
      (insert db "INSERT INTO user VALUES (1, 'noel')")
      (check-equal?
       (select db "SELECT * FROM user WHERE name='noel'")
       (list (vector "user_id" "name") (vector 1 "noel")))
      (close db)
      (clean)))
   
   (test-case
    "Insertion and selection (negative)"
    (let ((db (open (string->path test-db))))
      (exec/ignore db "CREATE TABLE user ( user_id INTEGER, name TEXT )")
      (insert db "INSERT INTO user VALUES (-1, 'noel')")
      (check-equal?
       (select db "SELECT * FROM user WHERE name='noel'")
       (list (vector "user_id" "name") (vector -1 "noel")))
      (close db)
      (clean)))
   
   (test-case
    "Insertion and selection of UTF-8"
    (let ((db (open (string->path test-db))))
      (exec/ignore db "CREATE TABLE user ( user_id INTEGER, name TEXT )")
      (insert db "INSERT INTO user VALUES (1, 'noelTM£¡')")
      (check-equal?
       (select db "SELECT * FROM user WHERE user_id=1")
       (list (vector "user_id" "name") (vector 1 "noelTM£¡")))
      (close db)
      (clean)))
   
   (test-case
    "insert returns row ids"
    (let ((db (open (string->path test-db))))
      (exec/ignore db "CREATE TABLE user ( user_id INTEGER PRIMARY KEY, name TEXT )")
      (check-equal?
       (insert db "INSERT INTO user (name) VALUES ('noel')")
       1)
      (check-equal?
       (insert db "INSERT INTO user (name) VALUES ('matt')")
       2)
      (check-equal?
       (insert db "INSERT INTO user (name) VALUES ('dave')")
       3)
      (close db)
      (clean)))
   
   (test-case
    "insert raises an exception when given rubbish"
    (with-dummy-database
        (lambda (db)
          (check-exn exn:sqlite?
                     (lambda ()
                       (insert db "some rubbish!"))))))
   
   (test-case
    "select raises an exception when given rubbish"
    (with-dummy-database
        (lambda (db)
          (check-exn exn:sqlite?
                     (lambda ()
                       (select db "some rubbish!"))))))
   
   (test-case
    "exec calls callback when there is data"
    (with-dummy-database
        (lambda (db)
          (let ((called 0))
            (exec db "SELECT * from user"
                  (lambda (names results)
                    (check-equal? '#("user_id" "name")
                                  names)
                    (check
                     member?
                     results
                     '(#(1 "noel")
                       #(2 "matt")
                       #(3 "dave")))
                    (set! called (add1 called))
                    0))
            (check = called 3)))))
   
   (test-case
    "exec stops when callback returns non-zero"
    (with-dummy-database
        (lambda (db)
          (let ((called 0))
            (check-exn
             exn:sqlite?
             (lambda ()
               (exec db "SELECT * from user"
                     (lambda (names results)
                       (check-equal? names
                                     '#("user_id" "name"))
                       (check-equal? results
                                     '#(1 "noel"))
                       (set! called (add1 called))
                       1))))
            (check = called 1)))))
   
   (test-case
    "exec does not call callback when there is no data"
    (with-dummy-database
        (lambda (db)
          (let ((called 0))
            (exec db "INSERT INTO user (name) VALUES ('jay')"
                  (lambda (names results)
                    (set! called (add1 called))
                    0))
            (check = called 0)))))
   
   (test-case
    "exec raises an exception when passed invalid SQL"
    (with-dummy-database
        (lambda (db)
          (check-exn
           exn:sqlite?
           (lambda ()
             (exec db "some rubbish!" (lambda (n r) 0)))))))
   
   (test-case
    "exec/ignore works"
    (with-dummy-database
        (lambda (db)
          (check-pred
           void?
           (exec/ignore db "INSERT INTO user (name) VALUES ('jay')")))))
   
   (test-case
    "exec/ignore raises an execption when passed invalid SQL"
    (with-dummy-database
        (lambda (db)
          (check-exn
           exn:sqlite?
           (lambda ()
             (exec/ignore db "some rubbish!"))))))
   
   (test-case
    "select returns correct values"
    (with-dummy-database
        (lambda (db)
          (check-equal?
           (select db "SELECT * from user")
           '(#("user_id" "name")
             #(1 "noel")
             #(2 "matt")
             #(3 "dave"))))))
   
   (test-case
    "select returns nothing when no values selected"
    (with-dummy-database
        (lambda (db)
          (check-equal?
           (select db "SELECT * from user where name='john'")
           '()))))
   
   (test-case
    "select returns nothing when not given a SELECT statement"
    (with-dummy-database
        (lambda (db)
          (check-equal?
           (select db "INSERT INTO user (name) VALUES ('jay')")
           '()))))
   
   (test-case
    "select raises an exception when passed invalid SQL"
    (with-dummy-database
        (lambda (db)
          (check-exn
           exn:sqlite?
           (lambda ()
             (select db "some rubbish!"))))))
   
   (test-case
    "prepare works with valid SQL"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * from user")))
            (check-pred statement? stmt)
            (finalize stmt)))))
   
   (test-case
    "prepare raises an exception when given rubbish"
    (with-dummy-database
        (lambda (db)
          (check-exn
           exn:sqlite?
           (lambda ()
             (prepare db "some rubbish!"))))))
   
   (test-case
    "prepare raises an exception when given an empty string"
    (with-dummy-database
        (lambda (db)
          (check-exn
           exn:sqlite?
           (lambda ()
             (prepare db ""))))))
   
   (test-case
    "prepare accepts statements with parameters"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT ? FROM user")))
            (check-pred statement? stmt)
            (finalize stmt)))))
   
   (test-case
    "step returns statement results"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user WHERE name='noel'")))
            (check-equal? (step stmt)
                          #(1 "noel"))
            (finalize stmt)))))
   
   (test-case
    "step returns #f when statement has no results"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user WHERE name='john'")))
            (check-false (step stmt))
            (finalize stmt)))))
   
   (test-case
    "step returns all statement results"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user"))
                (data '(#(1 "noel")
                        #(2 "matt")
                        #(3 "dave"))))
            (check member? (step stmt) data)
            (check member? (step stmt) data)
            (check member? (step stmt) data)
            (check-false (step stmt))
            (finalize stmt)))))
   
   (test-case
    "step returns all statement results (case-insensitive tables)"
    (let ((db #f))
      (dynamic-wind
       (lambda ()
         (set! db (open (string->path test-db)))
         (exec/ignore db "CREATE TABLE user ( user_id integer PRIMARY KEY, name text )")
         (insert db "INSERT INTO user (name) VALUES ('noel')")
         (insert db "INSERT INTO user (name) VALUES ('matt')")
         (insert db "INSERT INTO user (name) VALUES ('dave')"))
       (lambda ()
         (let ((stmt (prepare db "SELECT * FROM user"))
               (data '(#(1 "noel")
                       #(2 "matt")
                       #(3 "dave"))))
           (check member? (step stmt) data)
           (check member? (step stmt) data)
           (check member? (step stmt) data)
           (check-false (step stmt))
           (finalize stmt)))
       (lambda ()
         (with-handlers ([exn:fail? void]) (close db))
         (clean)))))
   
   (test-case
    "step raises an exception if the statement hasn't been reset"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user WHERE name='noel'")))
            (check-equal? (step stmt) #(1 "noel"))
            (check-false (step stmt))
            (check-exn exn:sqlite?
                       (lambda ()
                         (step stmt)))
            (finalize stmt)))))
   
   (test-case
    "reset enables a statement to be reused"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user WHERE name='noel'")))
            (check-equal? (step stmt) #(1 "noel"))
            (check-false (step stmt))
            (reset stmt)
            (check-equal? (step stmt) #(1 "noel"))
            (check-false (step stmt))
            (finalize stmt)))))
   
   (test-case
    "load-params works with parameterised statement"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user WHERE name=?")))
            (load-params stmt "noel")
            (check-equal? (step stmt) #(1 "noel"))
            (check-false (step stmt))
            (finalize stmt)))))
   
   (test-case
    "parameterised statement can be reused"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user WHERE name=?")))
            (load-params stmt "noel")
            (check-equal? (step stmt) #(1 "noel"))
            (check-false (step stmt))
            (reset stmt)
            (load-params stmt "matt")
            (check-equal? (step stmt) #(2 "matt"))
            (check-false (step stmt))           
            (finalize stmt)))))
   
   (test-case
    "statement-names"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user WHERE name=?")))
            (check-equal? (statement-names stmt) #("user_id" "name"))
            (finalize stmt)))))
   
   (test-case
    "load-params works with integer parameter"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user WHERE user_id=?")))
            (load-params stmt 2)
            (check-equal? (step stmt) #(2 "matt"))
            (check-false (step stmt))
            (finalize stmt)))))
   
   (test-case
    "load-params works with null parameter"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user WHERE user_id=?")))
            (load-params stmt #f)
            (check-false (step stmt))
            (finalize stmt)))))
   
   (test-case
    "load-params works with multiple parameters"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user WHERE name=? OR user_id=? ORDER BY user_id")))
            (load-params stmt "noel" 2)
            (check-equal? (step stmt) #(1 "noel"))
            (check-equal? (step stmt) #(2 "matt"))
            (check-false (step stmt))
            (finalize stmt)))))
   
   (test-case
    "load-params and step work with blobs"
    (with-dummy-database
        (lambda (db)
          (exec/ignore db "CREATE TABLE blobby (dump BLOB)")
          (let ((stmt (prepare db "INSERT INTO blobby VALUES (?)")))
            (load-params stmt #"abcdefghijklmnop")
            (check-false (step stmt))
            (finalize stmt)
            (let ((stmt (prepare db "SELECT * FROM blobby")))
              (check-equal? (step stmt) '#(#"abcdefghijklmnop"))
              (check-false (step stmt))
              (finalize stmt))
            (exec/ignore db "DROP TABLE blobby")))))
   
   (test-case
    "load-params and step work with UTF-8"
    (with-dummy-database
        (lambda (db)
          (exec/ignore db "CREATE TABLE blobby (dump TEXT)")
          (let ((stmt (prepare db "INSERT INTO blobby VALUES (?)")))
            (load-params stmt "¡TM£ ̊∆©a¢")
            (check-false (step stmt))
            (finalize stmt)
            (let ((stmt (prepare db "SELECT * FROM blobby")))
              (check-equal? (step stmt) '#("¡TM£ ̊∆©a¢"))
              (check-false (step stmt))
              (finalize stmt))
            (exec/ignore db "DROP TABLE blobby")))))
   
   (test-case
    "load-params raises an exception when too many parameters given"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user WHERE name=?")))
            (check-exn
             exn:fail:contract?
             (lambda ()
               (load-params stmt "noel" 1 2 3)))
            (finalize stmt)))))
   
   (test-case
    "load-params raises an exception when too few parameters given"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user WHERE name=?")))
            (check-exn
             exn:fail:contract?
             (lambda ()
               (load-params stmt)))
            (finalize stmt)))))
   
   (test-case
    "run works with string parameter"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "INSERT INTO user (name) VALUES (?)")))
            (check-pred void? (run stmt "john"))
            (check-equal? (select db "SELECT * from user WHERE name='john'")
                          '(#("user_id" "name") #(4 "john")))
            (finalize stmt)))))
   
   (test-case
    "run works with string and integer parameters"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "INSERT INTO user (user_id, name) VALUES (?, ?)")))
            (check-pred void? (run stmt 12345 "john"))
            (check-equal? (select db "SELECT * from user WHERE name='john'")
                          '(#("user_id" "name") #(12345 "john")))
            (finalize stmt)))))
   
   (test-case
    "run raises mismatch exception when given too many parameters"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "INSERT INTO user (user_id, name) VALUES (?, ?)")))
            (check-exn
             exn:fail:contract?
             (lambda () (run stmt 12345 "john" "duffer")))
            (finalize stmt)))))
   
   (test-case
    "run raises mismatch exception when given too few parameters"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "INSERT INTO user (user_id, name) VALUES (?, ?)")))
            (check-exn
             exn:fail:contract?
             (lambda () (run stmt "john")))
            (finalize stmt)))))
   
   (test-case
    "run works with blobs"
    (with-dummy-database
        (lambda (db)
          (exec/ignore db "CREATE TABLE blobby (dump BLOB)")
          (let ((stmt (prepare db "INSERT INTO blobby VALUES (?)")))
            (run stmt #"abcdefghijklmnop")
            (finalize stmt)
            (let ((stmt (prepare db "SELECT * FROM blobby")))
              (check-equal? (step stmt) '#(#"abcdefghijklmnop"))
              (check-false (step stmt))
              (finalize stmt))
            (exec/ignore db "DROP TABLE blobby")))))
   
   (test-case
    "changes-count is correct"
    (with-dummy-database
        (lambda (db)
          (check = (changes-count db) 1)
          (exec/ignore db "INSERT INTO user (name) VALUES ('jay')")
          (check = (changes-count db) 1)
          (exec/ignore db "INSERT INTO user (name) VALUES ('john')")
          (exec/ignore db "INSERT INTO user (name) VALUES ('doe')")
          (check = (changes-count db) 1))))
   
   (test-case
    "total-changes-count is correct"
    (with-dummy-database
        (lambda (db)
          (check = (total-changes-count db) 3)
          (exec/ignore db "INSERT INTO user (name) VALUES ('jay')")
          (check = (total-changes-count db) 4)
          (exec/ignore db "INSERT INTO user (name) VALUES ('john')")
          (exec/ignore db "INSERT INTO user (name) VALUES ('doe')")
          (check = (total-changes-count db) 6))))
   
   (test-case
    "step* returns all results"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user ORDER BY user_id")))
            (check-equal? (step* stmt)
                          '(#(1 "noel") #(2 "matt") #(3 "dave")))
            (finalize stmt)))))
   
   (test-case
    "step* returns empty list when no results available"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user WHERE user_id='john'")))
            (check-equal? (step* stmt) null)
            (finalize stmt)))))
   
   (test-case
    "step* raises an exception if the statement hasn't been reset"
    (with-dummy-database
        (lambda (db)
          (let ((stmt (prepare db "SELECT * FROM user WHERE name='noel'")))
            (check-equal? (step* stmt)
                          '(#(1 "noel")))
            (check-exn exn:sqlite?
                       (lambda ()
                         (step* stmt)))
            (finalize stmt)))))
   
   (test-case
    "with-transaction* returns the results of the body"
    (with-dummy-database
        (lambda (db)
          (check-equal?
           (with-transaction*
               db
             'none
             (lambda (fail)
               (select db "SELECT * FROM user WHERE name='noel'")))
           '(#("user_id" "name") #(1 "noel"))))))
   
   (test-case
    "with-transaction* aborts when fail is called"
    (with-dummy-database
        (lambda (db)
          (check-eq?
           'done
           (with-transaction*
               db
             'none
             (lambda (fail)
               (fail 'done)
               (insert db "INSERT INTO user (name) VALUES ('john')"))))
          (check-equal?
           null
           (select db "SELECT * FROM user WHERE name='john'")))))
   
   (test-case
    "with-transaction* rolls back when fail is called"
    (with-dummy-database
        (lambda (db)
          (with-transaction*
              db
            'none
            (lambda (fail)
              (insert db "INSERT INTO user (name) VALUES ('john')")
              (fail 'done)))
          (check-equal?
           null
           (select db "SELECT * FROM user WHERE name='john'")))))
   
   (test-case
    "with-transaction* raises exception if lock type is unknown"
    (with-dummy-database
        (lambda (db)
          (check-exn
           exn:fail?
           (lambda ()
             (with-transaction*
                 db
               'rubbish
               (lambda (fail) 1)))))))
   
   (test-case
    "with-transaction* allows all valid lock types"
    (with-dummy-database
        (lambda (db)
          (for-each
           (lambda (lock-type)
             (check-eq?
              'done
              (with-transaction* db lock-type (lambda (fail) 'done))))
           '(none deferred immediate exclusive)))))
   
   (test-case
    "with-transaction* aborts if action raises an exception"
    (with-dummy-database
        (lambda (db)
          (with-handlers
              ((exn:fail?
                (lambda (exn)
                  (check-equal?
                   null
                   (select db "SELECT * FROM user WHERE name='john'")))))
            (with-transaction*
                db
              'none
              (lambda (fail)
                (insert db "INSERT INTO user (name) VALUES ('john')")
                (check-equal?
                 (select db "SELECT * FROM user WHERE name='john'")
                 '(#("user_id" "name") #(4 "john")))
                (raise
                 (make-exn:fail
                  "Exit transaction!"
                  (current-continuation-marks)))))))))
   
   (test-case
    "with-transaction returns the results of the body"
    (with-dummy-database
        (lambda (db)
          (check-equal?
           (with-transaction (db fail)
             (select db "SELECT * FROM user WHERE name='noel'"))
           '(#("user_id" "name") #(1 "noel"))))))
   
   (test-case
    "with-transaction aborts when fail is called"
    (with-dummy-database
        (lambda (db)
          (check-eq?
           'done
           (with-transaction (db fail)
             (fail 'done)
             (insert db "INSERT INTO user (name) VALUES ('john')")))
          (check-equal?
           null
           (select db "SELECT * FROM user WHERE name='john'")))))
   
   (test-case
    "with-transaction rolls back when fail is called"
    (with-dummy-database
        (lambda (db)
          (with-transaction (db fail)
            (insert db "INSERT INTO user (name) VALUES ('john')")
            (fail 'done))
          (check-equal?
           null
           (select db "SELECT * FROM user WHERE name='john'")))))
   
   (test-case
    "with-transaction/lock returns the results of the body"
    (with-dummy-database
        (lambda (db)
          (check-equal?
           (with-transaction/lock (db none fail)
             (select db "SELECT * FROM user WHERE name='noel'"))
           '(#("user_id" "name") #(1 "noel"))))))
   
   (test-case
    "with-transaction/lock aborts when fail is called"
    (with-dummy-database
        (lambda (db)
          (check-eq?
           'done
           (with-transaction/lock (db deferred fail)
             (fail 'done)
             (insert db "INSERT INTO user (name) VALUES ('john')")))
          (check-equal?
           null
           (select db "SELECT * FROM user WHERE name='john'")))))
   
   (test-case
    "with-transaction/lock rolls back when fail is called"
    (with-dummy-database
        (lambda (db)
          (with-transaction/lock (db exclusive fail)
            (insert db "INSERT INTO user (name) VALUES ('john')")
            (fail 'done))
          (check-equal?
           null
           (select db "SELECT * FROM user WHERE name='john'")))))
   
   (test-case
    "load-params and step work with blobs between transactions"
    (with-dummy-database
        (lambda (db)
          (let ([result
                 (with-transaction
                     (db abort)
                   (exec/ignore db "CREATE TABLE blobby (dump BLOB)")
                   (let ((stmt (prepare db "INSERT INTO blobby VALUES (?)")))
                     (load-params stmt #"abcdefghijklmnopqrstuvwxyz")
                     (check-false (step stmt))
                     (finalize stmt)
                     (let ((stmt (prepare db "SELECT * FROM blobby")))
                       (let ([result (step stmt)])
                         (finalize stmt)
                         (select db "select last_insert_rowid()")
                         (exec/ignore db "DROP TABLE blobby")
                         result))))])
            (check-equal? result '#(#"abcdefghijklmnopqrstuvwxyz"))))))
   
   (test-case
    "prepare errors on multiple statements"
    (check-exn
     (lambda (exn)
       (and (exn:sqlite? exn)
            (regexp-match #rx"You should only prepare one statement at a time!" (exn-message exn))))
     (lambda ()
       (let ((db (open (string->path test-db))))
         (exec/ignore db "CREATE TABLE user ( user_id INTEGER, name TEXT ); CREATE TABLE user ( user_id INTEGER, name TEXT )")
         (close db)
         (delete-file test-db)))))
   
   (test-case
    "extraction of nulls works"
    (with-dummy-database
        (lambda (db)
          (exec/ignore db "INSERT INTO user (user_id) VALUES (8)")
          (check-equal? (select db "SELECT * FROM user")
                        (list (vector "user_id" "name")
                              (vector 1 "noel")
                              (vector 2 "matt")
                              (vector 3 "dave")
                              (vector 8 #f)))
          (check-equal? (select db "SELECT * FROM user WHERE user_id = 8")
                        (list (vector "user_id" "name")
                              (vector 8 #f)))
          (check-equal? (select db "SELECT * FROM user WHERE name IS NULL")
                        (list (vector "user_id" "name")
                              (vector 8 #f))))))
   
   (test-case
    "real column types"
    (let ([db (open (string->path test-db))])
      (exec/ignore db "CREATE TABLE test ( value REAL )")
      (insert db "INSERT INTO test (value) VALUES (3.14)")
      (check-equal? (select db "SELECT * FROM test")
                    (list #("value")
                          #(3.14)))
      (close db)
      (clean)))
   
   (test-case
    "varchar column types"
    (let ([db (open (string->path test-db))])
      (exec/ignore db "CREATE TABLE test ( value VARCHAR(2) )")
      (insert db "INSERT INTO test (value) VALUES ('Foo')")
      (check-equal? (select db "SELECT * FROM test")
                    (list #("value")
                          #("Foo")))
      (close db)
      (clean)))
   
   (test-case
    "varchar with space column types"
    (let ([db (open (string->path test-db))])
      (exec/ignore db "CREATE TABLE test ( value VARCHAR (2) )")
      (insert db "INSERT INTO test (value) VALUES ('Foo')")
      (check-equal? (select db "SELECT * FROM test")
                    (list #("value")
                          #("Foo")))
      (close db)
      (clean)))
   
   (test-case
    "varchar column types"
    (let ([db (open (string->path test-db))])
      (exec/ignore db "CREATE TABLE test ( value CHARACTER VARYING(2) )")
      (insert db "INSERT INTO test (value) VALUES ('Foo')")
      (check-equal? (select db "SELECT * FROM test")
                    (list #("value")
                          #("Foo")))
      (close db)
      (clean)))
   
   (test-case
    "varchar with space column types"
    (let ([db (open (string->path test-db))])
      (exec/ignore db "CREATE TABLE test ( value CHARACTER VARYING (2) )")
      (insert db "INSERT INTO test (value) VALUES ('Foo')")
      (check-equal? (select db "SELECT * FROM test")
                    (list #("value")
                          #("Foo")))
      (close db)
      (clean)))
   
   (test-case
    "syntax error"
    (check-exn
     (lambda (exn)
       (and (exn:sqlite? exn)
            (regexp-match #rx"syntax error" (exn-message exn))))
     (lambda ()
       (let ((db (open (string->path test-db))))
         (exec/ignore db "CREATE TABLE user ( user_id INTEGER, name TEXT")
         (close db)
         (clean)))))
   
   (test-case
    "syntax error"
    (check-exn
     (lambda (exn)
       (and (exn:sqlite? exn)
            (regexp-match #rx"Syntax error" (exn-message exn))))
     (lambda ()
       (with-dummy-database
           (lambda (db)
             (select db "SELECT (*) FROM user"))))))
   
   (test-case
    "run after finalize"
    (check-exn
     (lambda (exn)
       (and (exn:fail? exn)
            (regexp-match (regexp-quote "on load-params; expected <open-statement?>, given: #<statement>") (exn-message exn))))
     (lambda ()
       (with-dummy-database
           (lambda (db)
             (let ((stmt (prepare db "SELECT * FROM user WHERE user_id=?")))
               (load-params stmt 2)
               (check-equal? (step stmt) #(2 "matt"))
               (check-false (step stmt))
               (finalize stmt)
               (load-params stmt 2)
               (check-equal? (step stmt) #(2 "matt"))
               (check-false (step stmt))))))))
   
   ))