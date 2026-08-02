(** Limits applied while reading one HTTP connection. *)
type limits = {max_header_size: int; max_body_size: int}

(** Default limits: 64 KiB for headers and 10 MiB for request bodies. *)
val default_limits : limits

(** The byte-stream operations required by {!Make}. *)
module type IO = sig
  type t

(** Reads up to [len] bytes at [off], returning the number read. *)
  val read : t -> bytes -> off:int -> len:int -> int

(** Writes [len] bytes from [string] at [off]. *)
  val write : t -> string -> off:int -> len:int -> unit
end

(** Creates an HTTP server for a particular byte-stream transport. *)
module Make (Io : IO) : sig
(** [serve ?limits io handler] serves requests read from [io] and writes
    responses produced by [handler].
    @raise Invalid_argument if the supplied limits are invalid. *)
  val serve : ?limits:limits -> Io.t -> (Request.t -> Response.t) -> unit
end
