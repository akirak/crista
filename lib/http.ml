type framing = Empty | Fixed of int | Chunked

type parse_error =
  [ `Bad_request of string
  | `Body_too_large
  | `Expectation_failed
  | `Headers_too_large
  | `Unsupported_transfer_encoding ]

let is_tchar = function
  | '!' | '#' | '$' | '%' | '&' | '\'' | '*' | '+' | '-' | '.' | '^' | '_'
   |'`' | '|' | '~'
   |'0' .. '9'
   |'A' .. 'Z'
   |'a' .. 'z' ->
      true
  | _ -> false

let is_target_char character =
  let code = Char.code character in
  code > 0x20 && code <> 0x7f

let is_field_value_char character =
  let code = Char.code character in
  character = '\t' || (code >= 0x20 && code <> 0x7f)

let trim_ows value =
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

let parse_syntax input =
  let parser () =
    let meth = Parseff.take_while ~at_least:1 ~label:"method" is_tchar in
    ignore (Parseff.char ' ') ;
    let target =
      Parseff.take_while ~at_least:1 ~label:"request target" is_target_char
    in
    ignore (Parseff.char ' ') ;
    let version =
      Parseff.one_of
        [ (fun () ->
            ignore (Parseff.consume "HTTP/1.1") ;
            `HTTP_1_1 )
        ; (fun () ->
            ignore (Parseff.consume "HTTP/1.0") ;
            `HTTP_1_0 ) ]
        ()
    in
    ignore (Parseff.consume "\r\n") ;
    let rec headers count reversed =
      if count > 100 then Parseff.fail "too many header fields" ;
      Parseff.or_
        (fun () ->
          ignore (Parseff.consume "\r\n") ;
          List.rev reversed )
        (fun () ->
          let name =
            Parseff.take_while ~at_least:1 ~label:"header name" is_tchar
          in
          ignore (Parseff.char ':') ;
          Parseff.skip_while (function ' ' | '\t' -> true | _ -> false) ;
          let value = Parseff.take_while is_field_value_char |> trim_ows in
          ignore (Parseff.consume "\r\n") ;
          headers (count + 1) ((name, value) :: reversed) )
        ()
    in
    let headers = headers 0 [] in
    Parseff.end_of_input () ;
    (meth, target, version, Headers.of_list headers)
  in
  match Parseff.parse input parser with
  | Ok value -> Ok value
  | Error {pos; error} ->
      let detail =
        match error with
        | `Expected expected -> "expected " ^ expected
        | `Failure message -> message
        | `Unexpected_end_of_input -> "unexpected end of input"
        | `Depth_limit_exceeded message -> message
      in
      Error (`Bad_request (Printf.sprintf "%s at byte %d" detail pos))

let decimal value =
  let length = String.length value in
  if length = 0 then None
  else if String.for_all (function '0' .. '9' -> true | _ -> false) value
  then try Some (int_of_string value) with Failure _ -> None
  else None

let content_length headers =
  match
    Headers.get_all "content-length" headers
    |> List.concat_map (String.split_on_char ',')
    |> List.map trim_ows
  with
  | [] -> Ok None
  | first :: rest -> (
    match decimal first with
    | Some length
      when List.for_all
             (fun value ->
               match decimal value with
               | Some other -> other = length
               | None -> false )
             rest ->
        Ok (Some length)
    | _ -> Error (`Bad_request "invalid or conflicting Content-Length") )

let parse_request_head ~max_body_size input =
  match parse_syntax input with
  | Error _ as error -> error
  | Ok (meth, target, version, headers) -> (
      let hosts = Headers.get_all "host" headers in
      let valid_host =
        match (version, hosts) with
        | `HTTP_1_0, _ -> true
        | `HTTP_1_1, [host] -> not (String.equal (trim_ows host) "")
        | `HTTP_1_1, _ -> false
      in
      if not valid_host then
        Error
          (`Bad_request "HTTP/1.1 requires exactly one non-empty Host field")
      else
        let transfer_encoding = Headers.tokens "transfer-encoding" headers in
        match (transfer_encoding, content_length headers) with
        | _, (Error _ as error) -> error
        | _ :: _, Ok (Some _) ->
            Error
              (`Bad_request
                 "both Transfer-Encoding and Content-Length present" )
        | [], Ok None ->
            Ok (Request.make ~meth ~target ~version ~headers (), Empty)
        | [], Ok (Some length) when length > max_body_size ->
            Error `Body_too_large
        | [], Ok (Some length) ->
            Ok (Request.make ~meth ~target ~version ~headers (), Fixed length)
        | ["chunked"], Ok None ->
            Ok (Request.make ~meth ~target ~version ~headers (), Chunked)
        | _ -> Error `Unsupported_transfer_encoding )

let reason_phrase = function
  | 100 -> "Continue"
  | 200 -> "OK"
  | 201 -> "Created"
  | 202 -> "Accepted"
  | 204 -> "No Content"
  | 206 -> "Partial Content"
  | 301 -> "Moved Permanently"
  | 302 -> "Found"
  | 304 -> "Not Modified"
  | 307 -> "Temporary Redirect"
  | 308 -> "Permanent Redirect"
  | 400 -> "Bad Request"
  | 404 -> "Not Found"
  | 405 -> "Method Not Allowed"
  | 408 -> "Request Timeout"
  | 413 -> "Content Too Large"
  | 417 -> "Expectation Failed"
  | 431 -> "Request Header Fields Too Large"
  | 500 -> "Internal Server Error"
  | 501 -> "Not Implemented"
  | 503 -> "Service Unavailable"
  | _ -> "Status"

let valid_header_text value =
  not
    (String.exists
       (function '\r' | '\n' | '\000' -> true | _ -> false)
       value )

let valid_header_name name =
  String.length name > 0 && String.for_all is_tchar name

let serialize_response ~request_method ~close response =
  let status = Response.status response in
  let original_body = Response.body response in
  let forbids_payload = (status >= 100 && status < 200) || status = 204 in
  let suppresses_payload = forbids_payload || status = 304 in
  let body =
    if suppresses_payload || String.equal request_method "HEAD" then ""
    else original_body
  in
  let headers =
    Response.headers response
    |> Headers.remove "content-length"
    |> Headers.remove "connection"
    |> Headers.add "connection" (if close then "close" else "keep-alive")
  in
  let headers =
    if forbids_payload then headers
    else
      Headers.add "content-length"
        (string_of_int (String.length original_body))
        headers
  in
  let buffer = Buffer.create (128 + String.length body) in
  Printf.bprintf buffer "HTTP/1.1 %d %s\r\n" status (reason_phrase status) ;
  Headers.to_list headers
  |> List.iter (fun (name, value) ->
      if not (valid_header_name name && valid_header_text value) then
        invalid_arg "invalid response header" ;
      Printf.bprintf buffer "%s: %s\r\n" name value ) ;
  Buffer.add_string buffer "\r\n" ;
  Buffer.add_string buffer body ;
  Buffer.contents buffer
