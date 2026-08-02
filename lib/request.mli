type version = [`HTTP_1_0 | `HTTP_1_1]

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

val with_body : t -> string -> t

val header : string -> t -> string option

val headers : string -> t -> string list

val path : t -> string

val query : t -> string option
