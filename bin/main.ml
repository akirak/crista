open Mitochondria

let port = ref 8080

let bind = ref "127.0.0.1"

let cors_headers =
  Headers.of_list
    [ ("access-control-allow-origin", "*")
    ; ("access-control-allow-methods", "GET, HEAD, POST, OPTIONS")
    ; ("access-control-allow-headers", "content-type")
    ; ("access-control-allow-private-network", "true")
    ; ("access-control-expose-headers", "x-mitochondria-method")
    ; ("cache-control", "no-store") ]

let handler request =
  match Request.path request with
  | "/" -> Response.text "mitochondria is alive\n"
  | "/__mitochondria/status" ->
      Response.json ~headers:cors_headers "{\"status\":\"ok\"}"
  | "/__mitochondria/echo" ->
      Response.make
        ~headers:
          (Headers.add "x-mitochondria-method" request.meth cors_headers)
        ~body:request.body 200
  | "/__mitochondria/redirect" ->
      Response.make
        ~headers:
          (Headers.add "location" "/__mitochondria/status" cors_headers)
        302
  | _ -> Response.text ~headers:cors_headers ~status:404 "Not found\n"

let usage = "mitochondria [--bind ADDRESS] [--port PORT]"

let () =
  Arg.parse
    [ ("--bind", Arg.Set_string bind, "Address to bind (default: 127.0.0.1)")
    ; ("--port", Arg.Set_int port, "TCP port to bind (default: 8080)") ]
    (fun argument -> raise (Arg.Bad ("unexpected argument: " ^ argument)))
    usage ;
  let address =
    try Unix.inet_addr_of_string !bind
    with Failure _ ->
      prerr_endline ("Invalid numeric bind address: " ^ !bind) ;
      exit 2
  in
  Printf.eprintf "Listening on http://%s:%d\n%!" !bind !port ;
  Miou_server.run ~address ~port:!port handler
