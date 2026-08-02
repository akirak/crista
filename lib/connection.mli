type limits = {max_header_size: int; max_body_size: int}

val default_limits : limits

module type IO = sig
  type t

  val read : t -> bytes -> off:int -> len:int -> int

  val write : t -> string -> off:int -> len:int -> unit
end

module Make (Io : IO) : sig
  val serve : ?limits:limits -> Io.t -> (Request.t -> Response.t) -> unit
end
