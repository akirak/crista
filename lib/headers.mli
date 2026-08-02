(** HTTP header fields. Header names are compared case-insensitively.
    The order of fields is preserved and duplicate fields are allowed. *)
type t = (string * string) list

val empty : t
(** No header fields. *)

val of_list : (string * string) list -> t
(** [of_list fields] creates headers from [fields]. *)

val to_list : t -> (string * string) list
(** [to_list headers] returns fields in their original order. *)

val add : string -> string -> t -> t
(** [add name value headers] appends a field to [headers]. *)

val remove : string -> t -> t
(** [remove name headers] removes every field with the given name. *)

val get : string -> t -> string option
(** [get name headers] returns the first value for [name], if present. *)

val get_all : string -> t -> string list
(** [get_all name headers] returns all values for [name], in order. *)

val mem : string -> t -> bool
(** [mem name headers] is [true] when [headers] contains [name]. *)

val tokens : string -> t -> string list
(** [tokens name headers] splits comma-separated values, trims whitespace,
    and lowercases the resulting tokens. *)
