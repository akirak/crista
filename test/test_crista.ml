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
        ; Alcotest.test_case "content length" `Quick test_content_length
        ; Alcotest.test_case "obsolete folding" `Quick
            test_rejects_obsolete_folding
        ; Alcotest.test_case "Host requirement" `Quick test_host_requirement
        ] )
    ; ( "connection"
      , [ Alcotest.test_case "chunked and pipelined" `Quick
            test_chunked_and_pipelined_connection
        ; Alcotest.test_case "HEAD" `Quick test_head_response ] )
    ; ( "routing integration"
      , [Alcotest.test_case "routes" `Quick test_routes_integration] ) ]
