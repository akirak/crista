(** Limits applied while reading one HTTP connection. *)
type limits = {max_header_size: int; max_body_size: int}

val default_limits : limits
(** Default limits: 64 KiB for headers and 10 MiB for request bodies. *)

(** The byte-stream operations required by {!Make}. *)
module type IO = sig
  type t

  val read : t -> bytes -> off:int -> len:int -> int
  (** Reads up to [len] bytes at [off], returning the number read. *)

  val write : t -> string -> off:int -> len:int -> unit
  (** Writes [len] bytes from [string] at [off]. *)
end

(** Creates an HTTP server for a particular byte-stream transport. *)
module Make (Io : IO) : sig
  val serve : ?limits:limits -> Io.t -> (Request.t -> Response.t) -> unit
  (** [serve ?limits io handler] serves requests read from [io] and writes
    responses produced by [handler].
    @raise Invalid_argument if the supplied limits are invalid. *)
end
