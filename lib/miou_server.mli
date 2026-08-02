val serve :
     ?backlog:int
  -> ?limits:Connection.limits
  -> ?address:Unix.inet_addr
  -> port:int
  -> (Request.t -> Response.t)
  -> unit

val run :
     ?domains:int
  -> ?backlog:int
  -> ?limits:Connection.limits
  -> ?address:Unix.inet_addr
  -> port:int
  -> (Request.t -> Response.t)
  -> unit
