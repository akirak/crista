(** An HTTP protocol version supported by the server. *)
type version = [`HTTP_1_0 | `HTTP_1_1]

(** An HTTP request. The record is private and can only be constructed through
    {!make}. *)
type t = private
  { meth: string
  ; target: string
  ; version: version
  ; headers: Headers.t
  ; body: string }

(** [make ~meth ~target ~version ()] constructs a request. [headers] and
    [body] default to {!Headers.empty} and the empty string. *)
val make :
     ?headers:Headers.t
  -> ?body:string
  -> meth:string
  -> target:string
  -> version:version
  -> unit
  -> t

(** [with_body request body] returns [request] with [body] as its body. *)
val with_body : t -> string -> t

(** [header name request] returns the first value of a request header. *)
val header : string -> t -> string option

(** [headers name request] returns all values of a request header. *)
val headers : string -> t -> string list

(** [path request] returns the request target without its query string. *)
val path : t -> string

(** [query request] returns the part of the target after [?], if present. *)
val query : t -> string option
