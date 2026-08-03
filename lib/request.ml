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

let search_params request =
  match query request with
  | None | Some "" -> []
  | Some query ->
      List.map
        (fun parameter ->
          match String.index_opt parameter '=' with
          | None -> (parameter, "")
          | Some index ->
              ( String.sub parameter 0 index
              , String.sub parameter (index + 1)
                  (String.length parameter - index - 1) ))
        (String.split_on_char '&' query)
