(** Crista's Picos server backend. *)

include module type of Crista

val serve :
     ?backlog:int
  -> ?limits:Connection.limits
  -> ?address:Unix.inet_addr
  -> port:int
  -> handler
  -> unit
(** [serve ~port handler] listens on [port] and handles each connection in a
    separate Picos fiber. It must run under a scheduler that handles the Picos
    effects. By default it listens on the loopback address with a backlog of
    128. [limits] controls request header and body sizes.
    @raise Invalid_argument if [port] is outside [0, 65535]. *)
