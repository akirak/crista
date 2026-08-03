type version = [`HTTP_1_0 | `HTTP_1_1]

type t =
  { meth: string
  ; target: string
  ; version: version
  ; headers: Headers.t
  ; body: string }

let make ?(headers = Headers.empty) ?(body = "") ~meth ~target ~version () =
  {meth; target; version; headers; body}

let with_body request body = {request with body}

let header name request = Headers.get name request.headers

let headers name request = Headers.get_all name request.headers

let split_target target =
  match String.index_opt target '?' with
  | None -> (target, None)
  | Some index ->
      ( String.sub target 0 index
      , Some
          (String.sub target (index + 1) (String.length target - index - 1))
      )

let path request = fst (split_target request.target)

let query request = snd (split_target request.target)

let hex_digit = function
  | '0' .. '9' as digit -> Char.code digit - Char.code '0'
  | 'a' .. 'f' as digit -> Char.code digit - Char.code 'a' + 10
  | 'A' .. 'F' as digit -> Char.code digit - Char.code 'A' + 10
  | _ -> -1

let decode_parameter value =
  let length = String.length value in
  let decoded = Buffer.create length in
  let rec loop index =
    if index = length then Buffer.contents decoded
    else
      match value.[index] with
      | '+' ->
          Buffer.add_char decoded ' ' ;
          loop (index + 1)
      | '%' when index + 2 < length ->
          let high = hex_digit value.[index + 1] in
          let low = hex_digit value.[index + 2] in
          if high >= 0 && low >= 0 then (
            Buffer.add_char decoded (Char.chr ((high lsl 4) + low)) ;
            loop (index + 3) )
          else (
            Buffer.add_char decoded '%' ;
            loop (index + 1) )
      | character ->
          Buffer.add_char decoded character ;
          loop (index + 1)
  in
  loop 0

let search_params request =
  match query request with
  | None | Some "" -> []
  | Some query ->
      List.map
        (fun parameter ->
          match String.index_opt parameter '=' with
          | None -> (decode_parameter parameter, "")
          | Some index ->
              ( decode_parameter (String.sub parameter 0 index)
              , decode_parameter
                  (String.sub parameter (index + 1)
                     (String.length parameter - index - 1) ) ) )
        (String.split_on_char '&' query)
