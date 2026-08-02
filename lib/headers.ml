type t = (string * string) list

let empty = []

let of_list headers = headers

let to_list headers = headers

let add name value headers = headers @ [(name, value)]

let equal_name a b =
  String.equal (String.lowercase_ascii a) (String.lowercase_ascii b)

let remove name headers =
  List.filter (fun (candidate, _) -> not (equal_name name candidate)) headers

let get_all name headers =
  List.filter_map
    (fun (candidate, value) ->
      if equal_name name candidate then Some value else None )
    headers

let get name headers = List.nth_opt (get_all name headers) 0

let mem name headers = Option.is_some (get name headers)

let trim value =
  let is_ows = function ' ' | '\t' -> true | _ -> false in
  let first = ref 0 in
  let last = ref (String.length value - 1) in
  while !first <= !last && is_ows value.[!first] do
    incr first
  done ;
  while !last >= !first && is_ows value.[!last] do
    decr last
  done ;
  String.sub value !first (!last - !first + 1)

let tokens name headers =
  get_all name headers
  |> List.concat_map (String.split_on_char ',')
  |> List.map (fun value -> String.lowercase_ascii (trim value))
  |> List.filter (fun value -> not (String.equal value ""))
