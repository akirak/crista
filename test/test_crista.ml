open Crista

let fail_parse = function
  | Ok _ -> Alcotest.fail "request unexpectedly parsed"
  | Error _ -> ()

let test_parse_request () =
  match
    Http.parse_request_head ~max_body_size:1024
      "POST /submit?q=yes HTTP/1.1\r\n\
       Host: example.test\r\n\
       X-Test: one\r\n\
       \r\n"
  with
  | Error _ -> Alcotest.fail "valid request was rejected"
  | Ok (request, Http.Empty) ->
      Alcotest.(check string) "method" "POST" request.meth ;
      Alcotest.(check string) "path" "/submit" (Request.path request) ;
      Alcotest.(check (option string))
        "query" (Some "q=yes") (Request.query request) ;
      Alcotest.(check (option string))
        "case-insensitive header" (Some "example.test")
        (Request.header "host" request)
  | Ok _ -> Alcotest.fail "wrong request framing"

let test_search_params () =
  let request target =
    Request.make ~meth:"GET" ~target ~version:`HTTP_1_1 ()
  in
  Alcotest.(check (list (pair string string)))
    "search parameters"
    [ ("q", "yes")
    ; ("page", "2")
    ; ("empty", "a=b")
    ; ("hello world", "hello world!")
    ; ("form value", "a+b") ]
    (Request.search_params
       (request
          "/search?q=yes&page=2&empty=a=b&hello%20world=hello%20world%21&form+value=a%2Bb" ) ) ;
  Alcotest.(check (list (pair string string)))
    "no query" []
    (Request.search_params (request "/search"))

let test_content_length () =
  let parse fields =
    Http.parse_request_head ~max_body_size:32
      ("POST / HTTP/1.1\r\nHost: example.test\r\n" ^ fields ^ "\r\n")
  in
  ( match parse "Content-Length: 4\r\nContent-Length: 4\r\n" with
  | Ok (_, Http.Fixed 4) -> ()
  | _ -> Alcotest.fail "matching Content-Length fields should be accepted" ) ;
  fail_parse (parse "Content-Length: 4\r\nContent-Length: 5\r\n") ;
  fail_parse (parse "Content-Length: +4\r\n") ;
  fail_parse (parse "Transfer-Encoding: chunked\r\nContent-Length: 4\r\n")

let test_rejects_obsolete_folding () =
  fail_parse
    (Http.parse_request_head ~max_body_size:1024
       "GET / HTTP/1.1\r\nHost: example.test\r\n folded\r\n\r\n" )

let test_host_requirement () =
  fail_parse
    (Http.parse_request_head ~max_body_size:1024 "GET / HTTP/1.1\r\n\r\n") ;
  fail_parse
    (Http.parse_request_head ~max_body_size:1024
       "GET / HTTP/1.1\r\nHost: one.test\r\nHost: two.test\r\n\r\n" ) ;
  match
    Http.parse_request_head ~max_body_size:1024 "GET / HTTP/1.0\r\n\r\n"
  with
  | Ok _ -> ()
  | Error _ -> Alcotest.fail "HTTP/1.0 does not require Host"

module Memory_io = struct
  type t = {input: string; mutable offset: int; output: Buffer.t}

  let create input = {input; offset= 0; output= Buffer.create 256}

  let read flow bytes ~off ~len =
    let available = String.length flow.input - flow.offset in
    let count = min len available in
    Bytes.blit_string flow.input flow.offset bytes off count ;
    flow.offset <- flow.offset + count ;
    count

  let write flow string ~off ~len =
    Buffer.add_substring flow.output string off len
end

module Test_connection = Connection.Make (Memory_io)

let test_chunked_and_pipelined_connection () =
  let flow =
    Memory_io.create
      ( "POST /echo HTTP/1.1\r\nHost: example.test\r\n"
      ^ "Transfer-Encoding: chunked\r\n\
         \r\n\
         4\r\n\
         Wiki\r\n\
         5\r\n\
         pedia\r\n\
         0\r\n\
         \r\n"
      ^ "GET /next HTTP/1.1\r\n\
         Host: example.test\r\n\
         Connection: close\r\n\
         \r\n" )
  in
  Test_connection.serve flow (fun request -> Response.text request.body) ;
  let output = Buffer.contents flow.output in
  Alcotest.(check bool)
    "decoded chunked body" true
    ( String.starts_with ~prefix:"HTTP/1.1 200 OK" output
    && String.contains output 'W' ) ;
  let response_count =
    let marker = "HTTP/1.1 200 OK" in
    let rec count from total =
      match String.index_from_opt output from 'H' with
      | None -> total
      | Some index ->
          if
            index + String.length marker <= String.length output
            && String.sub output index (String.length marker) = marker
          then count (index + String.length marker) (total + 1)
          else count (index + 1) total
    in
    count 0 0
  in
  Alcotest.(check int) "two pipelined responses" 2 response_count

let test_head_response () =
  let response = Response.text "hello" in
  let wire =
    Http.serialize_response ~request_method:"HEAD" ~close:true response
  in
  Alcotest.(check bool)
    "representation length retained" true
    (String.contains wire '5') ;
  Alcotest.(check bool)
    "body omitted" false
    (String.ends_with ~suffix:"hello" wire)

let websocket_request =
  "GET /websocket HTTP/1.1\r\n\
   Host: example.test\r\n\
   Upgrade: websocket\r\n\
   Connection: keep-alive, Upgrade\r\n\
   Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\
   Sec-WebSocket-Version: 13\r\n\
   \r\n"

let masked_frame ?(fin = true) ~opcode payload =
  if String.length payload > 125 then invalid_arg "test frame is too large" ;
  let mask = "\x12\x34\x56\x78" in
  let frame = Bytes.create (6 + String.length payload) in
  Bytes.set frame 0 (Char.chr ((if fin then 0x80 else 0) lor opcode)) ;
  Bytes.set frame 1 (Char.chr (0x80 lor String.length payload)) ;
  Bytes.blit_string mask 0 frame 2 4 ;
  String.iteri
    (fun index character ->
      Bytes.set frame (index + 6)
        (Char.chr (Char.code character lxor Char.code mask.[index land 3])) )
    payload ;
  Bytes.unsafe_to_string frame

let websocket_echo websocket =
  let rec loop () =
    match Websocket.receive websocket with
    | Some (Websocket.Text text) ->
        Websocket.send_text websocket text ;
        loop ()
    | Some (Websocket.Binary data) ->
        Websocket.send_binary websocket data ;
        loop ()
    | None -> ()
  in
  loop ()

let find_substring haystack needle =
  let rec search index =
    if index + String.length needle > String.length haystack then None
    else if String.sub haystack index (String.length needle) = needle then
      Some index
    else search (index + 1)
  in
  search 0

let after_http_headers output =
  match find_substring output "\r\n\r\n" with
  | None -> Alcotest.fail "response has no header terminator"
  | Some index ->
      String.sub output (index + 4) (String.length output - index - 4)

let test_websocket_accept_key () =
  Alcotest.(check (option string))
    "RFC example" (Some "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    (Websocket.For_connection.accept_key "dGhlIHNhbXBsZSBub25jZQ==") ;
  Alcotest.(check (option string))
    "wrong decoded length" None
    (Websocket.For_connection.accept_key "dGhlIHNhbXBsZQ==") ;
  Alcotest.(check (option string))
    "non-canonical base64" None
    (Websocket.For_connection.accept_key "dGhlIHNhbXBsZSBub25jZQ=")

let test_websocket_fragmentation_ping_and_close () =
  let input =
    websocket_request
    ^ masked_frame ~fin:false ~opcode:1 "hel"
    ^ masked_frame ~opcode:9 "?"
    ^ masked_frame ~opcode:0 "lo"
    ^ masked_frame ~opcode:8 "\x03\xe8"
  in
  let flow = Memory_io.create input in
  Test_connection.serve flow (fun _ -> Response.websocket websocket_echo) ;
  let output = Buffer.contents flow.output in
  Alcotest.(check bool)
    "switching protocols" true
    (String.starts_with ~prefix:"HTTP/1.1 101 Switching Protocols\r\n" output) ;
  Alcotest.(check bool)
    "accept header" true
    (Option.is_some
       (find_substring output
          "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n" ) ) ;
  Alcotest.(check string)
    "pong, assembled text, and echoed close"
    "\x8a\x01?\x81\x05hello\x88\x02\x03\xe8"
    (after_http_headers output)

let close_code_from_output output =
  let frames = after_http_headers output in
  if String.length frames < 4 || frames.[0] <> '\x88' then
    Alcotest.fail "server did not send a close frame" ;
  (Char.code frames.[2] lsl 8) lor Char.code frames.[3]

let test_websocket_rejects_unmasked_frame () =
  let flow = Memory_io.create (websocket_request ^ "\x81\x01x") in
  Test_connection.serve flow (fun _ -> Response.websocket websocket_echo) ;
  Alcotest.(check int)
    "protocol error close code" 1002
    (close_code_from_output (Buffer.contents flow.output))

let test_websocket_rejects_invalid_utf8 () =
  let flow =
    Memory_io.create (websocket_request ^ masked_frame ~opcode:1 "\xc0\x80")
  in
  Test_connection.serve flow (fun _ -> Response.websocket websocket_echo) ;
  Alcotest.(check int)
    "invalid payload close code" 1007
    (close_code_from_output (Buffer.contents flow.output))

let test_websocket_rejects_invalid_utf8_before_final_fragment () =
  let flow =
    Memory_io.create
      ( websocket_request
      ^ masked_frame ~fin:false ~opcode:1 "\xf4"
      ^ masked_frame ~fin:false ~opcode:0 "\x90" )
  in
  Test_connection.serve flow (fun _ -> Response.websocket websocket_echo) ;
  Alcotest.(check int)
    "invalid fragmented payload close code" 1007
    (close_code_from_output (Buffer.contents flow.output))

let test_websocket_rejects_bad_handshake () =
  let request =
    "GET /websocket HTTP/1.1\r\n\
     Host: example.test\r\n\
     Upgrade: websocket\r\n\
     Connection: Upgrade\r\n\
     Sec-WebSocket-Key: not-base64\r\n\
     Sec-WebSocket-Version: 13\r\n\
     \r\n"
  in
  let called = ref false in
  let flow = Memory_io.create request in
  Test_connection.serve flow (fun _ ->
      Response.websocket (fun _ -> called := true) ) ;
  Alcotest.(check bool) "handler was not called" false !called ;
  Alcotest.(check bool)
    "bad request" true
    (String.starts_with ~prefix:"HTTP/1.1 400 Bad Request"
       (Buffer.contents flow.output) )

let test_routes_integration () =
  let router =
    Routes.one_of
      [ Routes.(
          (s "resource" / int /? nil)
          @--> fun resource_id request ->
          if request.Request.meth = "GET" then
            Response.text (string_of_int resource_id)
          else Response.empty 405 ) ]
  in
  let dispatch request =
    match Routes.match' router ~target:(Request.path request) with
    | Routes.FullMatch handler | Routes.MatchWithTrailingSlash handler ->
        handler request
    | Routes.NoMatch -> Response.empty 404
  in
  let request meth target =
    Request.make ~meth ~target ~version:`HTTP_1_1 ()
  in
  Alcotest.(check int)
    "typed route" 200
    (Response.status (dispatch (request "GET" "/resource/42?q=1"))) ;
  Alcotest.(check string)
    "typed parameter" "42"
    (Response.body (dispatch (request "GET" "/resource/42"))) ;
  Alcotest.(check int)
    "method not allowed" 405
    (Response.status (dispatch (request "POST" "/resource/42"))) ;
  Alcotest.(check int)
    "not found" 404
    (Response.status (dispatch (request "GET" "/missing")))

let () =
  Alcotest.run "crista"
    [ ( "http parsing"
      , [ Alcotest.test_case "request" `Quick test_parse_request
        ; Alcotest.test_case "search parameters" `Quick test_search_params
        ; Alcotest.test_case "content length" `Quick test_content_length
        ; Alcotest.test_case "obsolete folding" `Quick
            test_rejects_obsolete_folding
        ; Alcotest.test_case "Host requirement" `Quick test_host_requirement
        ] )
    ; ( "connection"
      , [ Alcotest.test_case "chunked and pipelined" `Quick
            test_chunked_and_pipelined_connection
        ; Alcotest.test_case "HEAD" `Quick test_head_response
        ; Alcotest.test_case "WebSocket accept key" `Quick
            test_websocket_accept_key
        ; Alcotest.test_case "WebSocket fragmentation, ping, and close"
            `Quick test_websocket_fragmentation_ping_and_close
        ; Alcotest.test_case "WebSocket unmasked frame" `Quick
            test_websocket_rejects_unmasked_frame
        ; Alcotest.test_case "WebSocket invalid UTF-8" `Quick
            test_websocket_rejects_invalid_utf8
        ; Alcotest.test_case "WebSocket invalid fragmented UTF-8" `Quick
            test_websocket_rejects_invalid_utf8_before_final_fragment
        ; Alcotest.test_case "WebSocket bad handshake" `Quick
            test_websocket_rejects_bad_handshake ] )
    ; ( "routing integration"
      , [Alcotest.test_case "routes" `Quick test_routes_integration] ) ]
