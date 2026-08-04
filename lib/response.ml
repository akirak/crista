type websocket_upgrade = {handler: Websocket.t -> unit; max_message_size: int}

type t =
  { status: int
  ; headers: Headers.t
  ; body: string
  ; websocket_upgrade: websocket_upgrade option }

let make ?(headers = Headers.empty) ?(body = "") status =
  if status < 100 || status > 599 then
    invalid_arg "HTTP status must be 100..599" ;
  {status; headers; body; websocket_upgrade= None}

let empty ?headers status = make ?headers status

let with_content_type content_type headers =
  if Headers.mem "content-type" headers then headers
  else Headers.add "content-type" content_type headers

let text ?(headers = Headers.empty) ?(status = 200) body =
  make
    ~headers:(with_content_type "text/plain; charset=utf-8" headers)
    ~body status

let html ?(headers = Headers.empty) ?(status = 200) body =
  make
    ~headers:(with_content_type "text/html; charset=utf-8" headers)
    ~body status

let json ?(headers = Headers.empty) ?(status = 200) body =
  make ~headers:(with_content_type "application/json" headers) ~body status

let redirect ?(permanent = false) location =
  let status = if permanent then 308 else 302 in
  make ~headers:(Headers.of_list [("location", location)]) status

let websocket ?(headers = Headers.empty)
    ?(max_message_size = 16 * 1024 * 1024) handler =
  if max_message_size < 0 then
    invalid_arg "WebSocket maximum message size must be non-negative" ;
  { status= 101
  ; headers
  ; body= ""
  ; websocket_upgrade= Some {handler; max_message_size} }

let add_header name value response =
  {response with headers= Headers.add name value response.headers}

let status response = response.status

let headers response = response.headers

let body response = response.body

let websocket_upgrade response = response.websocket_upgrade
