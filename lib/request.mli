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

val make :
     ?headers:Headers.t
  -> ?body:string
  -> meth:string
  -> target:string
  -> version:version
  -> unit
  -> t
(** [make ~meth ~target ~version ()] constructs a request. [headers] and
    [body] default to {!Headers.empty} and the empty string. *)

val with_body : t -> string -> t
(** [with_body request body] returns [request] with [body] as its body. *)

val header : string -> t -> string option
(** [header name request] returns the first value of a request header. *)

val headers : string -> t -> string list
(** [headers name request] returns all values of a request header. *)

val path : t -> string
(** [path request] returns the request target without its query string. *)

val query : t -> string option
(** [query request] returns the part of the target after [?], if present. *)

val search_params : t -> (string * string) list
(** [search_params request] returns the query parameters in [request]. *)
