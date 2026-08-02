type t = (string * string) list

val empty : t

val of_list : (string * string) list -> t

val to_list : t -> (string * string) list

val add : string -> string -> t -> t

val remove : string -> t -> t

val get : string -> t -> string option

val get_all : string -> t -> string list

val mem : string -> t -> bool

val tokens : string -> t -> string list
