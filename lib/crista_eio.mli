(** Crista's Eio server backend. *)

include module type of Crista

val serve :
     ?backlog:int
  -> ?limits:Connection.limits
  -> ?address:Unix.inet_addr
  -> net:_ Eio.Net.t
  -> port:int
  -> handler
  -> unit
(** [serve ~net ~port handler] listens on [port] using the Eio network
    capability [net]. It handles each connection in a separate Eio fiber. By
    default it listens on the loopback address with a backlog of 128. [limits]
    controls request header and body sizes.
    @raise Invalid_argument if [port] is outside [0, 65535]. *)
