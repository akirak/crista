(** An HTTP response. *)
type t

val make : ?headers:Headers.t -> ?body:string -> int -> t
(** [make status] constructs a response with optional headers and body.
    [status] must be between 100 and 599 inclusive.
    @raise Invalid_argument if [status] is outside that range. *)

val empty : ?headers:Headers.t -> int -> t
(** [empty status] constructs a response with no body. *)

val text : ?headers:Headers.t -> ?status:int -> string -> t
(** [text body] constructs a plain-text response, defaulting to status 200. *)

val html : ?headers:Headers.t -> ?status:int -> string -> t
(** [html body] constructs an HTML response, defaulting to status 200. *)

val json : ?headers:Headers.t -> ?status:int -> string -> t
(** [json body] constructs a JSON response, defaulting to status 200. *)

val redirect : ?permanent:bool -> string -> t
(** [redirect location] constructs a temporary redirect (302). Pass
    [~permanent:true] to use status 308. *)

val add_header : string -> string -> t -> t
(** [add_header name value response] appends a header to [response]. *)

val status : t -> int
(** [status response] returns the HTTP status code. *)

val headers : t -> Headers.t
(** [headers response] returns the response headers. *)

val body : t -> string
(** [body response] returns the response body. *)
