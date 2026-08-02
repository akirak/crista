type t

val make : ?headers:Headers.t -> ?body:string -> int -> t

val empty : ?headers:Headers.t -> int -> t

val text : ?headers:Headers.t -> ?status:int -> string -> t

val html : ?headers:Headers.t -> ?status:int -> string -> t

val json : ?headers:Headers.t -> ?status:int -> string -> t

val redirect : ?permanent:bool -> string -> t

val add_header : string -> string -> t -> t

val status : t -> int

val headers : t -> Headers.t

val body : t -> string
