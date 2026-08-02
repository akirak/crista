(** A TCP server built on the Miou scheduler. *)

val serve :
     ?backlog:int
  -> ?limits:Connection.limits
  -> ?address:Unix.inet_addr
  -> port:int
  -> (Request.t -> Response.t)
  -> unit
(** [serve ~port handler] listens on [port] and handles requests until the
    server is stopped or an exception occurs. By default it listens on the
    loopback address with a backlog of 128. [limits] controls request header
    and body sizes.
    @raise Invalid_argument if [port] is outside [0, 65535]. *)

val run :
     ?domains:int
  -> ?backlog:int
  -> ?limits:Connection.limits
  -> ?address:Unix.inet_addr
  -> port:int
  -> (Request.t -> Response.t)
  -> unit
(** [run ~port handler] runs [serve] inside {!Miou_unix.run}. [domains]
    controls the number of Miou domains. *)
