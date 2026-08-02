(** An HTTP response. *)
type t

(** [make status] constructs a response with optional headers and body.
    [status] must be between 100 and 599 inclusive.
    @raise Invalid_argument if [status] is outside that range. *)
val make : ?headers:Headers.t -> ?body:string -> int -> t

(** [empty status] constructs a response with no body. *)
val empty : ?headers:Headers.t -> int -> t

(** [text body] constructs a plain-text response, defaulting to status 200. *)
val text : ?headers:Headers.t -> ?status:int -> string -> t

(** [html body] constructs an HTML response, defaulting to status 200. *)
val html : ?headers:Headers.t -> ?status:int -> string -> t

(** [json body] constructs a JSON response, defaulting to status 200. *)
val json : ?headers:Headers.t -> ?status:int -> string -> t

(** [redirect location] constructs a temporary redirect (302). Pass
    [~permanent:true] to use status 308. *)
val redirect : ?permanent:bool -> string -> t

(** [add_header name value response] appends a header to [response]. *)
val add_header : string -> string -> t -> t

(** [status response] returns the HTTP status code. *)
val status : t -> int

(** [headers response] returns the response headers. *)
val headers : t -> Headers.t

(** [body response] returns the response body. *)
val body : t -> string
