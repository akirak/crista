(** HTTP header fields. Header names are compared case-insensitively.
    The order of fields is preserved and duplicate fields are allowed. *)
type t = (string * string) list

(** No header fields. *)
val empty : t

(** [of_list fields] creates headers from [fields]. *)
val of_list : (string * string) list -> t

(** [to_list headers] returns fields in their original order. *)
val to_list : t -> (string * string) list

(** [add name value headers] appends a field to [headers]. *)
val add : string -> string -> t -> t

(** [remove name headers] removes every field with the given name. *)
val remove : string -> t -> t

(** [get name headers] returns the first value for [name], if present. *)
val get : string -> t -> string option

(** [get_all name headers] returns all values for [name], in order. *)
val get_all : string -> t -> string list

(** [mem name headers] is [true] when [headers] contains [name]. *)
val mem : string -> t -> bool

(** [tokens name headers] splits comma-separated values, trims whitespace,
    and lowercases the resulting tokens. *)
val tokens : string -> t -> string list
