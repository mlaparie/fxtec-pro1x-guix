;; greetd-login.scm — log a user in through greetd's IPC, as a greeter does,
;; and start a session.  On the phone, as root, so the agent can log in
;; without the touchscreen:
;;   guile --no-auto-compile greetd-login.scm /run/greetd-<pid>.sock USER PASSWORD \
;;     CMD ARG...      (CMD as tuigreet runs it: env LIBSEAT_BACKEND=seatd bash -lc EXEC)
;; It cancels the session tuigreet keeps pending for the remembered user.
;; Messages: 32-bit native-endian length, then JSON.
(use-modules (ice-9 binary-ports) (rnrs bytevectors) (ice-9 regex)
             (ice-9 match))

(define (json-string s)
  (string-append "\""
                 (string-concatenate
                  (map (lambda (c)
                         (case c
                           ((#\") "\\\"") ((#\\) "\\\\")
                           (else (string c))))
                       (string->list s)))
                 "\""))

(define (send sock json)
  (let* ((body (string->utf8 json))
         (len (make-bytevector 4)))
    (bytevector-u32-native-set! len 0 (bytevector-length body))
    (put-bytevector sock len)
    (put-bytevector sock body)
    (force-output sock)))

(define (receive sock)
  (let* ((len (bytevector-u32-native-ref (get-bytevector-n sock 4) 0))
         (reply (utf8->string (get-bytevector-n sock len))))
    (format #t "<- ~a~%" reply)
    reply))

(define (type-of reply)
  (match:substring (string-match "\"type\" *: *\"([a-z_]+)\"" reply) 1))

(match (command-line)
  ((_ path user password cmd ...)
   (let ((sock (socket PF_UNIX SOCK_STREAM 0)))
     (connect sock AF_UNIX path)
     ;; tuigreet keeps a session pending for the remembered user; greetd
     ;; configures one session at a time.
     (send sock "{\"type\":\"cancel_session\"}")
     (receive sock)
     (send sock (string-append "{\"type\":\"create_session\",\"username\":"
                               (json-string user) "}"))
     (let loop ((reply (receive sock)))
       (match (type-of reply)
         ("auth_message"
          (send sock (string-append
                      "{\"type\":\"post_auth_message_response\",\"response\":"
                      (if (string-contains reply "\"secret\"")
                          (json-string password)
                          "null")
                      "}"))
          (loop (receive sock)))
         ("success"
          (send sock (string-append
                      "{\"type\":\"start_session\",\"cmd\":["
                      (string-join (map json-string cmd) ",")
                      "],\"env\":[]}"))
          (let ((r (receive sock)))
            (exit (if (string=? (type-of r) "success") 0 1))))
         (_
          (send sock "{\"type\":\"cancel_session\"}")
          (exit 1)))))))
