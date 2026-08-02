type t

val create : unit -> t

val add : ?meth:string -> string -> (Request.t -> Response.t) -> t -> unit

val get : string -> (Request.t -> Response.t) -> t -> unit

val post : string -> (Request.t -> Response.t) -> t -> unit

val route : t -> Request.t -> Response.t
